import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/native_channel.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'utils/calc_window_position.dart';

// ---------------------------------------------------------------------------
// Internal global accessor used by MultiViewDesktop and openWindow().
// ---------------------------------------------------------------------------

_MultiViewRootState? _rootState;

/// Returns the live [_MultiViewRootState] after [runMultiApp] has started.
// ignore: library_private_types_in_public_api
_MultiViewRootState get globalRootState {
  if (_rootState == null) {
    throw Exception('globalRootState not initialized. Use runMultiApp instead of runApp or runWidget');
  }
  return _rootState!;
}

/// Creates the root multi-view widget.  Used by [runMultiApp] only.
Widget createMultiViewRoot(Widget home, MultiAppConfig config) => _MultiViewRoot(home: home, config: config);

// ---------------------------------------------------------------------------
// _MultiViewRoot
// ---------------------------------------------------------------------------

/// The invisible root widget placed at the top of the tree by [runMultiApp].
///
/// Manages a [ViewCollection] whose entries grow/shrink as windows are
/// opened or closed.  Each child is wrapped in a [ViewScope] so that any
/// descendant can call [MultiViewDesktop.getCurrentId].
class _MultiViewRoot extends StatefulWidget {
  const _MultiViewRoot({required this.home, required this.config});

  final Widget home;
  final MultiAppConfig config;

  @override
  State<_MultiViewRoot> createState() => _MultiViewRootState();
}

// ---------------------------------------------------------------------------
// _MultiViewRootState
// ---------------------------------------------------------------------------

class _MultiViewRootState extends State<_MultiViewRoot> with WidgetsBindingObserver {
  late final _ViewsManagerImpl _viewsManagerImpl;

  WindowCommunicator get communicator => _viewsManagerImpl.communicator;

  ViewsManager get manager => _viewsManagerImpl;

  List<int> get allViewsId => [_viewsManagerImpl.mainId, ..._viewsManagerImpl.views.keys];

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _rootState = this;
    _viewsManagerImpl = _ViewsManagerImpl(
      config: widget.config,
      cascadeCloseService: _CascadeCloseService(),
      communicator: _WindowCommunicatorImpl(),
    );
    WidgetsBinding.instance.addObserver(this);

    _initMainView();
    unawaited(_viewsManagerImpl.applyNativeMacOSLifecyclePolicy());
  }

  void _initMainView() {
    // Snapshot to avoid concurrent-modification errors on the live views set.
    final initial = WidgetsBinding.instance.platformDispatcher.views.toList();
    if (initial.isEmpty) return;

    _viewsManagerImpl.mainView = initial.firstWhere((v) => v.viewId != 0, orElse: () => initial.first);
    _applyOptionsToMain();

    if (!kReleaseMode) {
      // Close all secondary views after hot restart
      final orphaned = initial.where((v) => v.viewId != _viewsManagerImpl.mainId && v.viewId != 0).toList();
      _viewsManagerImpl.removeSecondaryViewsForceAfterRestart(orphaned.map((e) => e.viewId).toList());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_rootState, this)) _rootState = null;
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // WidgetsBindingObserver
  // --------------------------------------------------------------------------

  @override
  void didChangeMetrics() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;

    final nonZero = dispatcher.views.where((v) => v.viewId != 0);
    final FlutterView? realView = nonZero.isEmpty ? null : nonZero.first;

    if (_viewsManagerImpl.mainView == null && dispatcher.views.isNotEmpty) {
      setState(() => _viewsManagerImpl.mainView = realView ?? dispatcher.views.first);
      _applyOptionsToMain();
      return;
    }

    if (_viewsManagerImpl.mainView != null && _viewsManagerImpl.mainId == 0 && realView != null) {
      setState(() => _viewsManagerImpl.mainView = realView);
      _applyOptionsToMain();
      return;
    }

    _viewsManagerImpl.clearMainViewIfClosed();

    final gone = _viewsManagerImpl.views.keys.where((id) => dispatcher.view(id: id) == null).toList();

    if (gone.isNotEmpty) {
      debugPrint('Окна к удалению: $gone');
      setState(() {
        for (final id in gone) {
          _handleClose(id);
        }
      });
    } else {
      setState(() {});
    }
  }

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  Future<void> _applyOptionsToMain() =>
      _viewsManagerImpl.applyOptions(_viewsManagerImpl.mainId, opts: widget.config.globalOptions);

  void _handleClose(int viewId) {
    if (!mounted) return;
    debugPrint('Окна удаляется: $viewId');
    _viewsManagerImpl.disposeView(viewId);
    setState(() {});
  }

  /// Registers [child] as the widget tree for a newly created [viewId].
  void addView(int viewId, Widget child) {
    setState(() {
      _viewsManagerImpl.views[viewId] = child;
    });
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = <Widget>[];
    final mainView = _viewsManagerImpl.mainView;
    final mainId = _viewsManagerImpl.mainId;
    if (mainView != null) {
      views.add(
        View(
          key: ValueKey('view_$mainId'),
          view: mainView,
          child: ViewScope(viewId: mainView.viewId, child: widget.home),
        ),
      );
    }

    for (final entry in _viewsManagerImpl.views.entries) {
      final int id = entry.key;
      final flutterView = dispatcher.view(id: id);
      if (flutterView != null) {
        views.add(
          View(
            key: ValueKey('view_$id'),
            view: flutterView,
            child: ViewScope(viewId: id, child: entry.value),
          ),
        );
      }
    }

    return ViewCollection(views: views);
  }
}

/// Coordinates [CloseMode.cascade] by waiting for each secondary window to finish closing.
///
/// Each view ID gets a [Completer] completed with `true` when the window closes
/// or `false` when the user cancels via [ViewsManager.cancelCascadeClose].
class _CascadeCloseService {
  _CascadeCloseService();

  // viewId -> completer: true = closed, false = cancelled (preventClose).
  final Map<int, Completer<bool>> _closeCompleters = {};

  void clear() => _closeCompleters.clear();

  /// Completes the cascade for [id] with `false` and clears pending completers.
  void abort(int id) {
    final completer = _closeCompleters[id];
    if (completer == null || completer.isCompleted) return;

    completer.complete(false);

    // Clear remaining completers so their future completion (e.g. user later
    // closes those windows independently) does not re-trigger the cascade.
    _closeCompleters.remove(id);
    for (final c in _closeCompleters.values) {
      if (!c.isCompleted) c.complete(false);
    }
    clear();
  }

  /// Registers [id] as the next window in a cascade close sequence.
  void attachWindow(int id) => _closeCompleters[id] = Completer<bool>();

  /// Signals that [id] finished its soft-close cycle successfully.
  void completeWindow(int id) => _closeCompleters[id]?.complete(true);

  /// Waits until [id] closes or the cascade is aborted; then removes its completer.
  Future<bool> waitWindow(int id) async {
    final res = await _closeCompleters[id]?.future ?? false;
    detachWindow(id);

    return res;
  }

  void detachWindow(int id) => _closeCompleters.remove(id);
}

/// [WindowCommunicator] backed by in-memory broadcast [StreamController]s.
class _WindowCommunicatorImpl implements WindowCommunicator {
  _WindowCommunicatorImpl();

  // Per-view streams, keyed by viewId.
  final Map<int, StreamController<dynamic>> _viewControllers = {};

  final Map<int, Map<int, StreamController<dynamic>>> _linkedViewControllers = {};

  // Single broadcast stream shared across all views.
  final StreamController<dynamic> _broadcastController = StreamController<dynamic>.broadcast();

  // -------------------------------------------------------------------------
  // Point-to-point
  // -------------------------------------------------------------------------

  @override
  Stream<dynamic> onDirect(BuildContext context, {int? viewId}) {
    final currentViewId = MultiViewDesktop.getCurrentId(context);
    int listenableId = viewId ?? currentViewId;
    int? parentId = viewId == null || viewId == currentViewId ? null : currentViewId;

    final stream = _getStreamById(listenableId, parentId: parentId);
    return stream;
  }

  Stream<dynamic> _getStreamById(int viewId, {int? parentId}) {
    if (parentId != null) {
      _linkedViewControllers
          .putIfAbsent(parentId, () => {})
          .putIfAbsent(viewId, () => StreamController<dynamic>.broadcast());

      return _linkedViewControllers[parentId]![viewId]!.stream;
    }

    _viewControllers.putIfAbsent(viewId, () => StreamController<dynamic>.broadcast());
    return _viewControllers[viewId]!.stream;
  }

  @override
  void send(int targetViewId, dynamic message) {
    _viewControllers[targetViewId]?.add(message);

    for (final children in _linkedViewControllers.values) {
      for (final entry in children.entries) {
        if (entry.key == targetViewId) {
          entry.value.add(message);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Broadcast
  // -------------------------------------------------------------------------

  @override
  Stream<dynamic> get onBroadcast => _broadcastController.stream;

  @override
  void broadcast(dynamic message) {
    _broadcastController.add(message);
  }

  // -------------------------------------------------------------------------
  // Internal cleanup
  // -------------------------------------------------------------------------

  /// Closes and removes the per-view stream and children for [viewId].
  ///
  /// Called automatically by the library when a view is removed from the
  /// [ViewCollection].  Do not call this manually.
  @internal
  Future<void> disposeView(int viewId) async {
    _viewControllers.remove(viewId)?.close();
    await _disposeLinkedView(viewId);
  }

  Future<void> _disposeLinkedView(int parentViewId) async {
    for (final entry in _linkedViewControllers[parentViewId]?.entries ?? <MapEntry<int, StreamController<dynamic>>>[]) {
      await entry.value.close();
    }
    _linkedViewControllers.remove(parentViewId);
  }

  @override
  Future<void> dispose() async {
    for (final view in _viewControllers.keys) {
      await disposeView(view);
    }
    _viewControllers.clear();
    _linkedViewControllers.clear();
  }
}

/// Default [ViewsManager]: native channel, window registry, listeners, and close modes.
class _ViewsManagerImpl implements ViewsManager {
  final _CascadeCloseService cascadeCloseService;
  final _WindowCommunicatorImpl communicator;
  final MultiAppConfig config;

  /// Active strategy when the main window's close button is pressed.
  late CloseMode closeMode;

  _ViewsManagerImpl({required this.config, required this.cascadeCloseService, required this.communicator}) {
    _nativeChannel.setMethodCallHandler(_onStaticCall);
    closeMode = config.mainCloseMode;
  }

  /// Pushes [CloseMode] to native macOS lifecycle policy (terminate-after-last-window).
  Future<void> applyNativeMacOSLifecyclePolicy() async {
    if (!Platform.isMacOS) return;
    await _nativeChannel.setTerminateAfterLastWindowClosed(closeMode != CloseMode.macos);
  }

  WindowOptions _compareGlobalAndNewOpts({WindowOptions? preferred, required WindowOptions global}) {
    if (preferred == null) return global;
    return WindowOptions(
      size: preferred.size ?? global.size,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      alignment: preferred.alignment ?? global.alignment,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
      hideAppFromTaskbar: preferred.hideAppFromTaskbar ?? global.hideAppFromTaskbar,
      titleBarStyle: preferred.titleBarStyle ?? global.titleBarStyle,
      windowButtonVisibility: preferred.windowButtonVisibility ?? global.windowButtonVisibility,
      title: preferred.title ?? global.title,
      fullScreen: preferred.fullScreen ?? global.fullScreen,
      alwaysOnTop: preferred.alwaysOnTop ?? global.alwaysOnTop,
    );
  }

  static final NativeChannel _nativeChannel = NativeChannel();

  // token -> widget, entries waiting for the native "viewCreated" event.
  int _nextToken = 0;

  // token -> Completer<int?> for pending views.
  final Map<int, Completer<int?>> _createCompleters = {};

  // viewId -> listener list.
  final Map<int, ObserverList<WindowListener>> _listeners = {};

  // final Map<int, ViewController> _controllers = {};

  FlutterView? _mainView;

  FlutterView? get mainView => _mainView;

  set mainView(FlutterView value) {
    _mainView = value;
    _nativeChannel.mainId = value.viewId;
  }

  int get mainId => _mainView?.viewId ?? 1;

  // viewId -> widget for all secondary views.
  final Map<int, Widget> views = {};

  Future<dynamic> _onStaticCall(MethodCall call) async {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;

    if (eventName == 'viewCreated') {
      // Internal event, not forwarded to WindowListener.
      final int viewId = call.arguments['viewId'] as int;
      final int token = call.arguments['token'] as int;
      _createComplete(token, viewId);
      await _nativeChannel.setMainPreConfirmClose(false);
    } else if (eventName == 'main-preconfirm-close') {
      // Internal event, not forwarded to WindowListener.
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId == mainId && viewId != null) {
        await _closeAppByMode(closeMode);
      }
    } else if (eventName == 'confirm-close') {
      // Internal event, not forwarded to WindowListener.
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        await _onConfirmClose(viewId);
      }
    } else {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        _dispatchViewEvent(viewId, eventName);
      }
    }

    return null;
  }

  Future<void> _closeAppByMode(CloseMode mode) async {
    switch (mode) {
      case CloseMode.none:
        await _removeViewsNone();
        break;
      case CloseMode.cascade:
        await _removeViewsCascade();
        break;
      case CloseMode.forceSecondary:
        await _removeSecondaryViewsForce();
        break;
      case CloseMode.destroy:
        await _destroyAllViewsForce();
        break;
      case CloseMode.macos:
        await _macosViewsClose();
        break;
    }
  }

  Future<void> _onConfirmClose(int viewId) async {
    if (viewId == mainId) {
      _mainView = null;
      _listeners.remove(viewId);
    }
    await disposeView(viewId);
    communicator.disposeView(viewId);
    await _nativeChannel.setConfirmClose(viewId, isConfirm: true);
    await _nativeChannel.softCloseWindow(viewId);

    cascadeCloseService.completeWindow(viewId);
  }

  /// Aborts the cascade close that is waiting on [viewId].
  ///
  /// Completing the completer with `false` causes the cascade loop to `return`
  /// early, leaving the main window open. All other pending completers are
  /// also cleared so that a later independent close of those windows does not
  /// unexpectedly resume the (already aborted) cascade.
  Future<void> _cancelCascade(int viewId) async {
    await _nativeChannel.setMainPreConfirmClose(false);
    cascadeCloseService.abort(viewId);
  }

  // --------------------------------------------------------------------------
  // Per-view event dispatch
  // --------------------------------------------------------------------------

  void _dispatchViewEvent(int viewId, String eventName) {
    final list = _listeners[viewId];
    if (list == null) return;
    for (final l in List<WindowListener>.from(list)) {
      l.onWindowEvent(eventName);
      _dispatchListenerEvent(l, eventName);
    }
  }

  void _dispatchListenerEvent(WindowListener listener, String eventName) {
    switch (eventName) {
      case 'focus':
        listener.onWindowFocus();
      case 'blur':
        listener.onWindowBlur();
      case 'maximize':
        listener.onWindowMaximize();
      case 'unmaximize':
        listener.onWindowUnmaximize();
      case 'minimize':
        listener.onWindowMinimize();
      case 'restore':
        listener.onWindowRestore();
      case 'resize':
        listener.onWindowResize();
      case 'resized':
        listener.onWindowResized();
      case 'move':
        listener.onWindowMove();
      case 'moved':
        listener.onWindowMoved();
      case 'enter-full-screen':
        listener.onWindowEnterFullScreen();
      case 'leave-full-screen':
        listener.onWindowLeaveFullScreen();
      case 'close':
        listener.onWindowClose();
    }
  }

  Future<void> _removeViewsNone() async {
    await _nativeChannel.setMainPreConfirmClose(true);
    await _nativeChannel.softCloseWindow(mainId);
  }

  /// Returns all secondary view IDs: registered ones plus native "orphaned"
  /// views that survived a hot restart (present in the platform dispatcher
  /// but absent from [_views]).
  List<int> _allSecondaryIds() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;

    final registered = views.keys.where((id) => id != mainId);
    final orphaned = dispatcher.views
        .toList()
        .map((v) => v.viewId)
        .where((id) => id != mainId && id != 0 && !views.containsKey(id));
    return {...registered, ...orphaned}.toList();
  }

  Future<void> _removeViewsCascade() async {
    final allViews = _allSecondaryIds().reversed.toList();

    for (final id in allViews) {
      cascadeCloseService.attachWindow(id);
      await _nativeChannel.focus(id);
      await _nativeChannel.softCloseWindow(id);

      final closed = await cascadeCloseService.waitWindow(id);
      if (!closed) return;
    }
    await _nativeChannel.setMainPreConfirmClose(true);
    await _nativeChannel.focus(mainId);
    await _nativeChannel.softCloseWindow(mainId);
  }

  Future<void> _removeSecondaryViewsForce() async {
    cascadeCloseService.clear();
    for (final id in _allSecondaryIds()) {
      await _nativeChannel.forceCloseWindow(id);
    }
    await _nativeChannel.setMainPreConfirmClose(true);
    await _nativeChannel.softCloseWindow(mainId);
  }

  Future<void> _destroyAllViewsForce() async {
    cascadeCloseService.clear();
    for (final id in _allSecondaryIds()) {
      await _nativeChannel.forceCloseWindow(id);
    }
    await _nativeChannel.forceCloseWindow(mainId);
  }

  Future<void> _macosViewsClose() async {
    // for not macOS system
    if (!Platform.isMacOS) {
      await _removeViewsCascade();
      return;
    }

    for (final id in _allSecondaryIds()) {
      await _nativeChannel.focus(id);
      await _nativeChannel.softCloseWindow(id);
    }
    await _nativeChannel.hide(mainId);
  }

  Future<void> removeSecondaryViewsForceAfterRestart(List<int> ids) async {
    cascadeCloseService.clear();
    for (final id in ids) {
      try {
        await _nativeChannel.forceCloseWindow(id);
      } catch (_) {}
    }
  }

  Future<void> applyOptions(int viewId, {required WindowOptions opts}) async => _applyOptions(viewId, opts);

  Future<void> _applyOptions(int viewId, WindowOptions opts) async {
    if (opts.size != null) {
      await _nativeChannel.setSize(viewId, size: opts.size!);
    }
    if (opts.alignment != null) {
      await _nativeChannel.setAlignment(viewId, alignment: opts.alignment!);
    }
    if (opts.backgroundColor != null) {
      await _nativeChannel.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.minimumSize != null) {
      await _nativeChannel.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      await _nativeChannel.setMaxSize(viewId, size: opts.minimumSize!);
    }
    if (opts.title != null) await _nativeChannel.setTitle(viewId, title: opts.title!);
    if (opts.titleBarStyle != null) {
      await _nativeChannel.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        buttonVisibility: opts.windowButtonVisibility!,
      );
    }
    if (opts.alwaysOnTop != null) {
      await _nativeChannel.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
    if (opts.fullScreen != null) {
      await _nativeChannel.setFullScreen(viewId, isFullScreen: opts.fullScreen!);
    }
    if (opts.hideAppFromTaskbar ?? false) {
      await _nativeChannel.hideAppFromTaskbar(isHideAppFromTaskbar: true);
    }
  }

  Future<void> disposeView(int viewId) async {
    _listeners.remove(viewId);
    views.remove(viewId);
    communicator.disposeView(viewId);
  }

  @override
  Future<int> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent}) async {
    final comparedOpts = _compareGlobalAndNewOpts(preferred: newOpts, global: config.globalOptions);

    final newId = await _createWindow(
      opts: comparedOpts,
      onCreated: (viewId) async {
        await onCreated(viewId);
      },
    );

    return newId;
  }

  Future<void> _createComplete(int token, int newViewId) async {
    _createCompleters[token]?.complete(newViewId);
    await _nativeChannel.setMainPreConfirmClose(false);
  }

  Future<int> _createWindow({required WindowOptions opts, required Future<void> Function(int) onCreated}) async {
    final int token = _nextToken++;
    _createCompleters[token] = Completer();

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = await calcWindowPosition(windowSize, opts.alignment!);
    }
    try {
      await _nativeChannel.createWindowRequest(
        token: token,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
      );
    } catch (e, st) {
      throw Exception('Failed to create new window, tokenId: $token. Error: $e, stack: $st');
    }

    final newViewId = await _createCompleters[token]!.future.timeout(Duration(seconds: 1), onTimeout: () => null);
    _createCompleters.remove(token);

    if (newViewId == null) {
      throw Exception('Failed to create new window, tokenId: $token. Error: timeout');
    }

    await onCreated(newViewId);
    await _applyOptions(newViewId, opts);

    return newViewId;
  }

  @override
  void addListener(int viewId, WindowListener listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListener>()).add(listener);
  }

  @override
  void removeListener(int viewId, WindowListener listener) {
    _listeners[viewId]?.remove(listener);
  }

  @override
  Future<void> blur(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.blur(viewId));
  }

  @override
  Future<void> cancelCascadeClose(int viewId) async {
    await _cancelCascade(viewId);
  }

  @override
  Future<void> center(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setAlignment(viewId, alignment: Alignment.center));
  }

  @override
  Future<void> closeWindow(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.softCloseWindow(viewId));
  }

  @override
  Future<void> closeApp({CloseMode? closeMode}) async {
    final mode = closeMode ?? config.mainCloseMode;
    await _viewExistChecker(mainId, () async {
      await _closeAppByMode(mode);
    });
  }

  @override
  Future<void> focus(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.focus(viewId));
  }

  @override
  Future<Rect> getBounds(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getBounds(viewId)) ?? Rect.zero;
  }

  @override
  Future<double> getOpacity(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getOpacity(viewId)) ?? 1;
  }

  @override
  Future<Offset> getPosition(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getPosition(viewId)) ?? Offset.zero;
  }

  @override
  Future<Size> getSize(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getSize(viewId)) ?? Size.zero;
  }

  @override
  Future<String> getTitle(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getTitle(viewId)) ?? '';
  }

  @override
  Future<({bool? buttonVisibility, TitleBarStyle? style})> getTitleBarStyle(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getTitleBarStyle(viewId)) ??
        (buttonVisibility: true, style: TitleBarStyle.normal);
  }

  @override
  Future<bool> hasShadow(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.hasShadow(viewId)) ?? true;
  }

  @override
  Future<void> hide(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.hide(viewId));
  }

  @override
  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _viewExistChecker(
      mainId,
      () async => await _nativeChannel.hideAppFromTaskbar(isHideAppFromTaskbar: isHideAppFromTaskbar),
    );
  }

  @override
  Future<void> hideFromCollection(int viewId, bool isHideFromCollection) async {
    if (!Platform.isMacOS) return;
    await _viewExistChecker(viewId, () async => await _nativeChannel.hideFromCollection(viewId, isHideFromCollection));
  }

  @override
  Future<bool> isAlwaysOnTop(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isAlwaysOnTop(viewId)) ?? false;
  }

  @override
  Future<bool> isClosable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isClosable(viewId)) ?? true;
  }

  @override
  Future<bool> isFocused(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isFocused(viewId)) ?? true;
  }

  @override
  Future<bool> isFullScreen(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isFullScreen(viewId)) ?? false;
  }

  @override
  Future<bool> isHideAppFromTaskbar() async {
    return await _viewExistChecker(mainId, () async => await _nativeChannel.isHideAppFromTaskbar()) ?? false;
  }

  @override
  Future<bool> isHideFromCollection(int viewId) async {
    if (!Platform.isMacOS) return false;
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isHideFromCollection(viewId)) ?? false;
  }

  @override
  Future<bool> isMaximizable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMaximizable(viewId)) ?? true;
  }

  @override
  Future<bool> isMaximized(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMaximized(viewId)) ?? false;
  }

  @override
  Future<bool> isMinimizable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMinimizable(viewId)) ?? true;
  }

  @override
  Future<bool> isMinimized(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMinimized(viewId)) ?? false;
  }

  @override
  Future<bool> isMovable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMovable(viewId)) ?? true;
  }

  @override
  Future<bool> isPreventClose(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isPreventClose(viewId)) ?? false;
  }

  @override
  Future<bool> isResizable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isResizable(viewId)) ?? true;
  }

  @override
  Future<bool> isVisible(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isVisible(viewId)) ?? true;
  }

  @override
  Future<bool> isVisibleOnAllWorkspaces(int viewId) async {
    //TODO: протестить
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isVisibleOnAllWorkspaces(viewId)) ?? true;
  }

  @override
  Future<void> maximize(int viewId, {bool vertically = false}) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.maximize(viewId));
  }

  @override
  Future<void> minimize(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.minimize(viewId));
  }

  @override
  Future<void> popUpWindowMenu(int viewId) async {
    //TODO: протестить
    await _viewExistChecker(viewId, () async => await _nativeChannel.popUpWindowMenu(viewId));
  }

  @override
  Future<void> restore(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.restore(viewId));
  }

  @override
  Future<void> setAlignment(int viewId, Alignment alignment) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setAlignment(viewId, alignment: alignment));
  }

  @override
  Future<void> setAlwaysOnTop(int viewId, bool isAlwaysOnTop) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setAlwaysOnTop(viewId, isAlwaysOnTop: isAlwaysOnTop),
    );
  }

  @override
  Future<void> setAsFrameless(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setAsFrameless(viewId));
  }

  @override
  Future<void> setAspectRatio(int viewId, double ratio) async {
    //TODO: протестить
    await _viewExistChecker(viewId, () async => await _nativeChannel.setAspectRatio(viewId, ratio));
  }

  @override
  Future<void> setBackgroundColor(int viewId, Color color) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setBackgroundColor(viewId, color: color));
  }

  @override
  Future<void> setBadgeLabel(int viewId, String? label) async {
    if (!Platform.isMacOS) return;
    await _viewExistChecker(viewId, () async => await _nativeChannel.setBadgeLabel(viewId, label: label));
  }

  @override
  Future<void> setBrightness(int viewId, Brightness brightness) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setBrightness(viewId, brightness));
  }

  @override
  Future<void> setClosable(int viewId, bool isClosable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setClosable(viewId, isClosable));
  }

  @override
  Future<void> setCloseMode(CloseMode closeMode) async {
    this.closeMode = closeMode;
    await applyNativeMacOSLifecyclePolicy();
  }

  @override
  CloseMode getCloseMode() => closeMode;

  @override
  Future<void> setFullScreen(int viewId, bool isFullScreen) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setFullScreen(viewId, isFullScreen: isFullScreen));
  }

  @override
  Future<void> setHasShadow(int viewId, bool value) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setHasShadow(viewId, value));
  }

  @override
  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setIgnoreMouseEvents(viewId, ignore, forward: forward),
    );
  }

  @override
  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isIgnoreMouseEvents(viewId)) ??
        (mouseMoveEvents: false, ignore: false);
  }

  @override
  Future<void> setMaximizable(int viewId, bool isMaximizable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMaximizable(viewId, isMaximizable));
  }

  @override
  Future<void> setMaximumSize(int viewId, Size size) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMaxSize(viewId, size: size));
  }

  @override
  Future<void> setMinimizable(int viewId, bool isMinimizable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMinimizable(viewId, isMinimizable));
  }

  @override
  Future<void> setMinimumSize(int viewId, Size size) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMinSize(viewId, size: size));
  }

  @override
  Future<void> setMovable(int viewId, bool isMovable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMovable(viewId, isMovable));
  }

  @override
  Future<void> setOpacity(int viewId, double opacity) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setOpacity(viewId, opacity));
  }

  @override
  Future<void> setPosition(int viewId, Offset position) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setPosition(viewId, pos: position));
  }

  @override
  Future<void> setPreventClose(int viewId, bool isPreventClose) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setPreventClose(viewId, isPreventClose: isPreventClose),
    );
  }

  @override
  Future<void> setProgressBar(double progress) async {
    if (Platform.isLinux) return;
    await _viewExistChecker(mainId, () async => await _nativeChannel.setProgressBar(progress));
  }

  @override
  Future<void> setResizable(int viewId, bool isResizable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setResizable(viewId, isResizable));
  }

  @override
  Future<void> setSize(int viewId, Size size) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setSize(viewId, size: size));
  }

  @override
  Future<void> setTitle(int viewId, String title) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setTitle(viewId, title: title));
  }

  @override
  Future<void> setTitleBarStyle(int viewId, TitleBarStyle style, {bool windowButtonVisibility = true}) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setTitleBarStyle(viewId, style: style, buttonVisibility: windowButtonVisibility),
    );
  }

  @override
  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) async {
    if (!Platform.isMacOS) return;

    await _viewExistChecker(
      viewId,
      () async =>
          await _nativeChannel.setVisibleOnAllWorkspaces(viewId, visible, visibleOnFullScreen: visibleOnFullScreen),
    );
  }

  @override
  Future<void> show(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.show(viewId));
  }

  @override
  Future<void> startDragging(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.startDragging(viewId));
  }

  @override
  Future<void> startResizing(int viewId, ResizeEdge edge) async {
    if (Platform.isMacOS) return;
    await _viewExistChecker(viewId, () async => await _nativeChannel.startResizing(viewId, edge));
  }

  @override
  Future<void> unmaximize(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.unmaximize(viewId));
  }

  Future<T?> _viewExistChecker<T>(int viewId, Future<T> Function() func) async {
    if (!views.containsKey(viewId) && viewId != mainId) return null;
    if (!_hasLiveFlutterView(viewId)) return null;
    try {
      return await func();
    } on PlatformException catch (e) {
      // Race during cascade close: native window gone before didChangeMetrics.
      if (e.code == 'NO_WINDOW') return null;
      rethrow;
    }
  }

  bool _hasLiveFlutterView(int viewId) {
    return WidgetsBinding.instance.platformDispatcher.view(id: viewId) != null;
  }

  /// Clears [mainView] when its [FlutterView] was removed from the engine.
  void clearMainViewIfClosed() {
    final view = _mainView;
    if (view == null) return;
    if (_hasLiveFlutterView(view.viewId)) return;
    _listeners.remove(view.viewId);
    _mainView = null;
  }
}
