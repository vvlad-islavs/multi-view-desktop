import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/native_channel.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'utils/calc_window_position.dart';

// ---------------------------------------------------------------------------
// Per-window registration (widget tree + optional parent link).
// ---------------------------------------------------------------------------

class _WindowEntry {
  const _WindowEntry({required this.widget, required this.parentContext, this.parentId});

  final Widget widget;
  final BuildContext? parentContext;
  final int? parentId;
}

// ---------------------------------------------------------------------------
// Internal global accessor used by MultiViewDesktop and openWindow().
// ---------------------------------------------------------------------------

_MultiViewRootState? _rootState;
final NativeChannel _nativeChannel = NativeChannel();
bool _hasInitView = true;

/// Returns the live [_MultiViewRootState] after [runMultiApp] has started.
// ignore: library_private_types_in_public_api
_MultiViewRootState get globalRootState {
  if (_rootState == null) {
    throw Exception('globalRootState not initialized. Use runMultiApp instead of runApp or runWidget');
  }
  return _rootState!;
}

/// Creates the root multi-view widget.  Used by [runMultiApp] only.
Future<Widget> createMultiViewRoot(Widget home, Widget Function(Widget child)? scope, MultiAppConfig config) async {
  final initialWindow = Platform.isWindows ? 0 : 1;
  _hasInitView = await _nativeChannel.checkWindowExist(initialWindow) ?? true;

  final mainRoot = _MultiViewRoot(home: home, config: config);
  return scope?.call(mainRoot) ?? mainRoot;
}

// ---------------------------------------------------------------------------
// _MultiViewRoot
// ---------------------------------------------------------------------------

/// The invisible root widget placed at the top of the tree by [runMultiApp].
///
/// Manages a [ViewCollection] whose entries grow/shrink as windows are
/// opened or closed.  Each child is wrapped in a [ViewScope] so that any
/// descendant can call [MultiViewDesktop.getIdByContext].
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

  List<int> get allShiftedViewsId => _viewsManagerImpl.allShiftedWindowIds;

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
  }

  void _initMainView() async {
    // Snapshot to avoid concurrent-modification errors on the live views set.
    final initial = WidgetsBinding.instance.platformDispatcher.views.toList();
    final excludeId = Platform.isWindows ? -1 : 0;
    final live = initial.where((v) => v.viewId != excludeId).toList();
    if (live.isEmpty) return;

    // After hot restart the lowest live view id may not be 1 (e.g. if view 1 was closed).
    live.sort((a, b) => a.viewId.compareTo(b.viewId));
    await _viewsManagerImpl.registerInitialWindow(viewId: live.first.viewId, home: widget.home);
    unawaited(_viewsManagerImpl.applyNativeLifecyclePolicy());
    // Only for debug. Closes all windows from past session on hot restart
    if (!kReleaseMode) {
      final registered = _viewsManagerImpl.allRealWindowIds.toSet();
      final orphaned = live.where((v) => !registered.contains(v.viewId)).toList();
      _viewsManagerImpl.removeOrphanViewsForceAfterRestart(orphaned.map((e) => e.viewId).toList());
    }

    _applyOptionsToInitialAnchor();
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
    final allViews = PlatformDispatcher.instance.views;
    _viewsManagerImpl.reconcileAnchor(dispatcher);

    final gone = _viewsManagerImpl.allRealWindowIds.where((id) => dispatcher.view(id: id) == null).toList();
    debugPrint('allViews on metrics changed: $allViews, gone: $gone');
    if (gone.isNotEmpty) {
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

  Future<void> _applyOptionsToInitialAnchor() async {
    final anchorId = _viewsManagerImpl.anchorId;
    if (anchorId == null) return;
    await _viewsManagerImpl.applyOptions(anchorId, opts: widget.config.globalOptions);
    unawaited(_nativeChannel.show(anchorId));
  }

  void _handleClose(int viewId) {
    final allViews = PlatformDispatcher.instance.views;
    debugPrint('allViews after handle dispatcher close: $allViews');
    if (!mounted) return;
    _viewsManagerImpl.disposeView(viewId);
    setState(() {});
  }

  /// Registers [child] as the widget tree for a newly created [viewId].
  void addView(int viewId, Widget child, {int? parentId, required BuildContext? parentContext}) {
    setState(() {
      _viewsManagerImpl.registerWindow(viewId, child, parentContext: parentContext, parentId: parentId);
    });
    final allViews = PlatformDispatcher.instance.views;
    debugPrint('allViews after newWindow add: $allViews');
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = <Widget>[];

    for (final entry in _viewsManagerImpl.windowEntries) {
      final id = entry.key;
      final parentContext = entry.value.parentContext;
      final flutterView = dispatcher.view(id: id);
      if (flutterView != null) {
        views.add(
          View(
            key: ValueKey('view_$id'),
            view: flutterView,
            child: ParentWindowScope(
              parentContext: parentContext,
              child: ViewScope(viewId: id, child: entry.value.widget),
            ),
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
    final res = await _closeCompleters[id]?.future ?? true;
    detachWindow(id);

    return res;
  }

  void detachWindow(int id) => _closeCompleters.remove(id);
}

/// [WindowCommunicator] backed by in-memory broadcast [StreamController]s.
/// Uses shifted ids cause has public API to add listeners by id
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
    final currentViewId = MultiViewDesktop.getIdByContext(context);
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
  Future<void> disposeViewByShiftedId(int viewId) async {
    _viewControllers.remove(viewId)?.close();
    await _disposeLinkedViewByShiftedId(viewId);
  }

  Future<void> _disposeLinkedViewByShiftedId(int parentViewId) async {
    for (final entry in _linkedViewControllers[parentViewId]?.entries ?? <MapEntry<int, StreamController<dynamic>>>[]) {
      await entry.value.close();
    }
    _linkedViewControllers.remove(parentViewId);
  }

  @override
  Future<void> dispose() async {
    for (final view in _viewControllers.keys) {
      await disposeViewByShiftedId(view);
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
    closeMode = config.generalParams.closeMode;
  }

  /// Pushes [CloseMode] to native macOS lifecycle policy (terminate-after-last-window).
  Future<void> applyNativeLifecyclePolicy() async {
    if (!Platform.isMacOS) return;
    await _nativeChannel.setTerminateAfterLastWindowClosed(config.macosParams.closeAppAfterLastWindowClosed);
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

  // token -> widget, entries waiting for the native "viewCreated" event.
  int _nextToken = 0;

  // id shift after hot restart
  int _hotRestartShift = 0;

  @override
  int shiftedToRealId(int viewId) => _shiftedToReal(viewId);

  @override
  int realToShiftedId(int viewId) => _realToShifted(viewId);

  // token -> Completer<int?> for pending views.
  final Map<int, Completer<int?>> _createCompleters = {};

  final Map<int, int> _childCreatePending = {};

  // viewId -> listener list.
  final Map<int, ObserverList<WindowListenerCallbacks>> _listeners = {};

  /// Anchor window: receives app-level close policy ([CloseMode]) from the native close button.
  int? _anchorId;

  int? get anchorId => _anchorId;

  /// Back-compat alias used by native channel app-wide calls.
  int? get mainId => _anchorId;

  /// View id for app-wide native calls (dock badge, taskbar, etc.).
  int? get _lifecycleViewId {
    if (_anchorId != null && _windows.containsKey(_anchorId)) return _anchorId;
    if (_windows.isEmpty) return null;
    return _windows.keys.reduce((a, b) => a < b ? a : b);
  }

  final Map<int, _WindowEntry> _windows = {};

  Iterable<MapEntry<int, _WindowEntry>> get windowEntries => _windows.entries;

  List<int> get allRealWindowIds => _windows.keys.toList();

  List<int> get allShiftedWindowIds => _windows.keys.map((e) => _realToShifted(e)).toList();

  Future<void> registerInitialWindow({required int viewId, required Widget home}) async {
    // Win by default init from 0 id but macos & linux from 1
    _hotRestartShift = Platform.isWindows ? -1 : 0;
    if (!_hasInitView) {
      viewId = await openWindow(home);
      _hotRestartShift = viewId - 1;
    }

    _windows[viewId] = _WindowEntry(widget: home, parentContext: null, parentId: null);
    _setAnchor(viewId, force: true);
  }

  void registerWindow(int viewId, Widget widget, {required BuildContext? parentContext, int? parentId}) {
    if (parentId != null && !_windows.containsKey(parentId)) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent window is not registered');
    }
    _windows[viewId] = _WindowEntry(widget: widget, parentContext: parentContext, parentId: parentId);
    if (_anchorId == null) {
      _setAnchor(viewId);
    }
  }

  Future<void> _setAnchor(int? viewId, {bool force = false}) async {
    if (!config.generalParams.enableDynamicAnchor && !force) return;
    _anchorId = viewId;
    if (viewId == null) return;
    await _nativeChannel.setAnchorViewId(viewId);
  }

  /// When the anchor [FlutterView] disappears, pick another root window.
  void reconcileAnchor(PlatformDispatcher dispatcher) {
    final anchor = _anchorId;
    if (anchor == null) return;
    if (dispatcher.view(id: anchor) != null) return;
    _setAnchor(_anchorId);
    _promoteAnchor();
  }

  List<int> _anchorCandidates({int? excludingViewId}) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates =
        _windows.entries
            .where((e) => e.value.parentId == null && e.key != excludingViewId)
            .map((e) => e.key)
            .where((id) => dispatcher.view(id: id) != null)
            .toList()
          ..sort();
    return candidates;
  }

  /// Picks another root window as anchor (lowest live view id), optionally skipping [excludingViewId].
  void _promoteAnchor({int? excludingViewId}) {
    final candidates = _anchorCandidates(excludingViewId: excludingViewId);
    if (candidates.isEmpty) {
      _setAnchor(null);
      return;
    }
    _setAnchor(candidates.first);
  }

  int _realToShifted(int viewId) => viewId - _hotRestartShift;

  int _shiftedToReal(int viewId) => viewId + _hotRestartShift;

  List<int> _directChildIds(int parentId) =>
      _windows.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  /// All descendants of [rootId], deepest first (safe for closing).
  List<int> _descendantIdsDeepestFirst(int rootId) {
    final result = <int>[];
    void walk(int id) {
      for (final child in _directChildIds(id)) {
        walk(child);
        result.add(child);
      }
    }

    walk(rootId);
    return result;
  }

  List<int> _rootWindowIds({int? excludingId}) =>
      _windows.entries.where((e) => e.value.parentId == null && e.key != excludingId).map((e) => e.key).toList();

  Future<dynamic> _onStaticCall(MethodCall call) async {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;

    if (eventName == 'viewCreated') {
      // Internal event, not forwarded to WindowListener.
      final int viewId = call.arguments['viewId'] as int;
      final int token = call.arguments['token'] as int;
      _createComplete(token, viewId);
      final maybeParentId = _childCreatePending[token];
      if (maybeParentId == null) return;
      _childCreatePending.remove(token);
      await _nativeChannel.setPreConfirmClose(maybeParentId, false);
    } else if (eventName == 'preconfirm-close') {
      // Internal event, not forwarded to WindowListener.
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        await _handlePreConfirmClose(viewId);
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

  Future<void> _onConfirmClose(int viewId) async {
    await disposeView(viewId);

    communicator.disposeViewByShiftedId(_realToShifted(viewId));
    await _nativeChannel.setConfirmClose(viewId, isConfirm: true);
    await _nativeChannel.forceCloseWindow(viewId);

    cascadeCloseService.completeWindow(viewId);
  }

  /// Runs before [isPreventClose] / [isConfirmClose]; subtree closes per [closeMode].
  Future<void> _handlePreConfirmClose(int viewId) async {
    final nextAnchorCandidates = _anchorCandidates(excludingViewId: viewId)..sort();
    if (viewId == _anchorId && nextAnchorCandidates.isNotEmpty && !config.generalParams.enableDynamicAnchor) {
      for (final candidate in nextAnchorCandidates.reversed) {
        cascadeCloseService.abort(candidate);
        cascadeCloseService.attachWindow(candidate);
        await _closeSubtreeByMode(candidate, closeMode);
        final closed = await cascadeCloseService.waitWindow(candidate);
        if (!closed) {
          return;
        }
      }
    }

    await _closeSubtreeByMode(viewId, closeMode);
  }

  Future<void> _closeSubtreeByMode(int rootId, CloseMode mode) async {
    switch (mode) {
      case CloseMode.none:
        await _removeViewsNone(rootId);
        break;
      case CloseMode.cascade:
        await _removeViewsCascade(rootId);
        break;
      case CloseMode.forceSecondary:
        await _removeSecondaryViewsForce(rootId);
        break;
      case CloseMode.destroy:
        await _destroyAllViewsForce(rootId);
        break;
    }
  }

  /// Aborts the cascade close that is waiting on [viewId].
  ///
  /// Completing the completer with `false` causes the cascade loop to `return`
  /// early, leaving the main window open. All other pending completers are
  /// also cleared so that a later independent close of those windows does not
  /// unexpectedly resume the (already aborted) cascade.
  Future<void> _cancelCascade(int viewId) async {
    final parentsRecurs = [..._parentsId(viewId), viewId];
    for (final parent in parentsRecurs) {
      await _nativeChannel.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  int? _directParentId(int childId) {
    final entry = _windows[childId];
    return entry?.parentId;
  }

  List<int> _parentsId(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = _directParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  // --------------------------------------------------------------------------
  // Per-view event dispatch
  // --------------------------------------------------------------------------

  void _dispatchViewEvent(int viewId, String eventName) {
    final list = _listeners[viewId];
    if (list == null) return;
    for (final l in List<WindowListenerCallbacks>.from(list)) {
      l.onWindowEvent(eventName);
      _dispatchListenerEvent(l, eventName);
    }
  }

  void _dispatchListenerEvent(WindowListenerCallbacks listener, String eventName) {
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

  Future<void> _removeViewsNone(int rootId) async {
    await _nativeChannel.setPreConfirmClose(rootId, true);
    await _nativeChannel.softCloseWindow(rootId);
  }

  Future<void> _removeViewsCascade(int rootId, {bool reverse = true}) async {
    Future<void> closeRoot() async {
      await _nativeChannel.setPreConfirmClose(rootId, true);
      if (Platform.isMacOS) {
        // Скрывает окно только если нет кандидатов или отключено динимаческое главное окно приложения,
        // при этом включено сохранение окна в таскбаре и id == _anchorId
        if ((_anchorCandidates(excludingViewId: rootId).isEmpty || !config.generalParams.enableDynamicAnchor) &&
            config.macosParams.saveLastWindowToReopen &&
            _anchorId == rootId) {
          await _nativeChannel.hide(rootId);
          await _nativeChannel.setPreConfirmClose(rootId, false);
          return;
        }
      }
      // await _nativeChannel.focus(rootId);
      await _nativeChannel.softCloseWindow(rootId);
    }

    if (!reverse) await closeRoot();
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();

    for (final id in reverse ? descendants.reversed : descendants) {
      cascadeCloseService.attachWindow(id);
      // await _nativeChannel.focus(id);
      await _nativeChannel.softCloseWindow(id);
      final closed = await cascadeCloseService.waitWindow(id);

      if (!closed) return;
    }

    if (reverse) await closeRoot();
  }

  Future<void> _removeSecondaryViewsForce(int rootId) async {
    cascadeCloseService.clear();
    for (final id in _descendantIdsDeepestFirst(rootId).reversed.toList()) {
      await _nativeChannel.forceCloseWindow(id);
    }
    await _nativeChannel.setPreConfirmClose(rootId, true);
    await _nativeChannel.softCloseWindow(rootId);
  }

  Future<void> _destroyAllViewsForce(int rootId) async {
    cascadeCloseService.clear();
    for (final id in _descendantIdsDeepestFirst(rootId)) {
      await _nativeChannel.forceCloseWindow(id);
    }
    await _nativeChannel.forceCloseWindow(rootId);
  }

  /// Closes every registered window (all roots and their subtrees).
  Future<void> _closeEntireApp(CloseMode mode) async {
    for (final root in _rootWindowIds()) {
      await _closeSubtreeByMode(root, mode);
    }
  }

  Future<void> removeOrphanViewsForceAfterRestart(List<int> ids) async {
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
      await hideAppFromTaskbar(true);
    }
  }

  Future<void> disposeView(int viewId) async {
    final allViews = PlatformDispatcher.instance.views;
    debugPrint('allViews after window close: $allViews');
    final wasAnchor = viewId == _anchorId;
    if (wasAnchor) {
      _setAnchor(null);
    }
    _listeners.remove(viewId);
    _windows.remove(viewId);
    communicator.disposeViewByShiftedId(_realToShifted(viewId));
    if (wasAnchor) {
      _promoteAnchor();
    }
  }

  @override
  Future<int> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent}) async {
    if (parent != null && !_windows.containsKey(parent)) {
      throw ArgumentError.value(parent, 'parent', 'Parent window is not registered');
    }

    final comparedOpts = _compareGlobalAndNewOpts(preferred: newOpts, global: config.globalOptions);

    return _createWindow(opts: comparedOpts, parentId: parent, onCreated: onCreated);
  }

  Future<void> _createComplete(int token, int newViewId) async {
    _createCompleters[token]?.complete(newViewId);
    await _nativeChannel.setPreConfirmClose(newViewId, false);
  }

  Future<int> _createWindow({
    required WindowOptions opts,
    int? parentId,
    required Future<void> Function(int) onCreated,
  }) async {
    final int token = _nextToken++;
    _createCompleters[token] = Completer();
    if (parentId != null) {
      _childCreatePending.putIfAbsent(token, () => parentId);
    }

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = await calcWindowPosition(windowSize, opts.alignment!);
    }

    debugPrint('до запроса на создание окна');
    try {
      await _nativeChannel.createWindowRequest(
        token: token,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
        parentId: parentId,
      );
    } catch (e, st) {
      throw Exception('Failed to create new window, tokenId: $token. Error: $e, stack: $st');
    }

    debugPrint('после запроса на создание окна');

    final newViewId = await _createCompleters[token]!.future.timeout(Duration(seconds: 1), onTimeout: () => null);
    _createCompleters.remove(token);

    debugPrint('после комлитера на создание окна');
    if (newViewId == null) {
      throw Exception('Failed to create new window, tokenId: $token. Error: timeout');
    }
    await _applyOptions(newViewId, opts);

    await onCreated(newViewId);

    return newViewId;
  }

  @override
  void addListener(int viewId, WindowListenerCallbacks listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListenerCallbacks>()).add(listener);
  }

  @override
  void removeListener(int viewId, WindowListenerCallbacks listener) {
    _listeners[viewId]?.remove(listener);
  }

  @override
  Future<void> setTaskbarMenu({required List<TaskbarMenuItem> items}) async {
    //TODO: кастомизация списка меню
  }

  @override
  Future<bool> setAnchorId(int viewId) async {
    if (config.generalParams.enableDynamicAnchor) return false;

    final realView = _shiftedToReal(viewId);
    if (_anchorCandidates().contains(realView)) {
      await _setAnchor(realView, force: true);
      return true;
    }

    return false;
  }

  @override
  int? getAnchorId() {
    if (_anchorId == null) return null;

    return _realToShifted(_anchorId!);
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
  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId}) async {
    if (Platform.isMacOS || Platform.isLinux) {
      final id = _lifecycleViewId;
      if (id == null) return;
      await _viewExistChecker(
        id,
        () async => await _nativeChannel.hideAppFromTaskbar(id, isHideAppFromTaskbar: isHideAppFromTaskbar),
      );
    } else {
      if (viewId == null) {
        for (final view in windowEntries) {
          await _viewExistChecker(
            view.key,
            () async => await _nativeChannel.hideAppFromTaskbar(view.key, isHideAppFromTaskbar: isHideAppFromTaskbar),
          );
        }
        return;
      }
      await _viewExistChecker(
        viewId,
        () async => await _nativeChannel.hideAppFromTaskbar(viewId, isHideAppFromTaskbar: isHideAppFromTaskbar),
      );
    }
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
    if (Platform.isWindows || Platform.isLinux) {
      return await _nativeChannel.isHideAppFromTaskbar();
    }
    final id = _lifecycleViewId;
    if (id == null) return false;
    return await _viewExistChecker(id, () async => await _nativeChannel.isHideAppFromTaskbar()) ?? false;
  }

  @override
  Future<bool> isHideAppTabFromTaskbar(int viewId) async {
    if (!Platform.isWindows) {
      return isHideAppFromTaskbar();
    }
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isHideAppTabFromTaskbar(viewId)) ?? false;
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
  CloseMode getAppCloseMode() => closeMode;

  @override
  Future<void> setAppCloseMode(CloseMode closeMode) async {
    this.closeMode = closeMode;
    await applyNativeLifecyclePolicy();
  }

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
    //TODO: тест на линуксе (ибунту)
    if (Platform.isLinux) return;
    final id = _lifecycleViewId;
    if (id == null) return;
    await _viewExistChecker(id, () async => await _nativeChannel.setProgressBar(progress));
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

  @override
  Future<void> closeApp({CloseMode? closeMode}) async {
    final mode = closeMode ?? config.generalParams.closeMode;
    await _closeEntireApp(mode);
  }

  Future<T?> _viewExistChecker<T>(int viewId, Future<T> Function() func) async {
    if (!_windows.containsKey(viewId)) return null;
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
}
