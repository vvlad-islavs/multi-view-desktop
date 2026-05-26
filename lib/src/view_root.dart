import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'utils/calc_window_position.dart';

// ---------------------------------------------------------------------------
// Internal global accessor used by MultiViewDesktop and addWindow().
// ---------------------------------------------------------------------------

_MultiViewRootState? _rootState;

// ignore: library_private_types_in_public_api
_MultiViewRootState? get globalRootState => _rootState;

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
  static const MethodChannel _staticChannel = MethodChannel('multiview_desktop');

  // The main FlutterView (viewId > 0), captured at startup.
  FlutterView? _mainView;

  int get _mainId => _mainView?.viewId ?? 1;

  // viewId -> widget for all secondary views.
  final Map<int, Widget> _views = {};

  Map<int, Widget> get views => _views;

  // token -> widget, entries waiting for the native "viewCreated" event.
  final Map<int, Widget> _pending = {};
  int _nextToken = 0;

  // token -> WindowOptions for pending views.
  final Map<int, WindowOptions> _pendingOptions = {};

  // viewId -> listener list.
  final Map<int, ObserverList<WindowListener>> _listeners = {};

  // viewId -> completer: true = closed, false = cancelled (preventClose).
  final Map<int, Completer<bool>> _closeCompleters = {};

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _rootState = this;
    _staticChannel.setMethodCallHandler(_onStaticCall);
    WidgetsBinding.instance.addObserver(this);

    _initMainView();
  }

  void _initMainView() {
    // Snapshot to avoid concurrent-modification errors on the live views set.
    final initial = WidgetsBinding.instance.platformDispatcher.views.toList();
    if (initial.isEmpty) return;

    _mainView = initial.firstWhere((v) => v.viewId != 0, orElse: () => initial.first);
    _applyOptionsToMain();

    if (!kReleaseMode) {
      // Close all secondary views after restart
      final orphaned = initial.where((v) => v.viewId != _mainView!.viewId && v.viewId != 0).toList();
      _removeSecondaryViewsForceAfterRestart(orphaned.map((e) => e.viewId).toList());
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

    if (_mainView == null && dispatcher.views.isNotEmpty) {
      setState(() => _mainView = realView ?? dispatcher.views.first);
      _applyOptionsToMain();
      return;
    }

    if (_mainView != null && _mainView!.viewId == 0 && realView != null) {
      setState(() => _mainView = realView);
      _applyOptionsToMain();
      return;
    }

    final gone = _views.keys.where((id) => dispatcher.view(id: id) == null).toList();

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
  // Static channel (native -> Dart)
  // --------------------------------------------------------------------------

  Future<dynamic> _onStaticCall(MethodCall call) async {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;

    if (eventName == 'viewCreated') {
      // Internal event, not forwarded to WindowListener.
      final int viewId = call.arguments['viewId'] as int;
      final int token = call.arguments['token'] as int;
      final widget = _pending.remove(token);
      final options = _pendingOptions.remove(token);
      if (widget != null && mounted) {
        setState(() => _views[viewId] = widget);
        if (options != null) {
          _applyOptions(viewId, options);
        }
      }
      await _setMainPreConfirmClose(false);
    } else if (eventName == 'main-preconfirm-close') {
      // Internal event, not forwarded to WindowListener.
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId == _mainId && viewId != null) {
        switch (widget.config.mainCloseMode) {
          case CloseMode.none:
            await _removeViewsNone();
            break;
          case CloseMode.cascade:
            await _removeViewsCascade();
            break;
          case CloseMode.force:
            await _removeViewsForce();
            break;
        }
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
    WindowCommunicator.disposeView(viewId);
    await setConfirmClose(viewId, true);
    await removeView(viewId);
    _closeCompleters[viewId]?.complete(true);
    // don't remove viewId completer here
  }

  /// Aborts the cascade close that is waiting on [viewId].
  ///
  /// Completing the completer with `false` causes the cascade loop to `return`
  /// early, leaving the main window open. All other pending completers are
  /// also cleared so that a later independent close of those windows does not
  /// unexpectedly resume the (already aborted) cascade.
  Future<void> cancelCascade(int viewId) async {
    await _setMainPreConfirmClose(false);
    final completer = _closeCompleters[viewId];
    if (completer == null || completer.isCompleted) return;

    // Abort the cascade: the loop awaiting this completer will see false and
    // return without closing the main window.
    completer.complete(false);

    // Clear remaining completers so their future completion (e.g. user later
    // closes those windows independently) does not re-trigger the cascade.
    _closeCompleters.remove(viewId);
    for (final c in _closeCompleters.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _closeCompleters.clear();
  }

  // --------------------------------------------------------------------------
  // Per-view event dispatch
  // --------------------------------------------------------------------------

  void _dispatchViewEvent(int viewId, String eventName) {
    final list = _listeners[viewId];
    debugPrint('Event $eventName отправлен в слушатели view с id $viewId');
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

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  Future<void> _applyOptionsToMain() => _applyOptions(_mainId, widget.config.preferredOptions);

  void _handleClose(int viewId) {
    if (!mounted) return;
    WindowCommunicator.disposeView(viewId);
    setState(() {
      _views.remove(viewId);
      _listeners.remove(viewId);
    });
  }

  Future<void> _applyOptions(int viewId, WindowOptions opts) async {
    Future<void> invoke(String method, [Map<String, dynamic>? extra]) {
      final args = <String, dynamic>{'viewId': viewId};
      if (extra != null) args.addAll(extra);
      return _staticChannel.invokeMethod<void>(method, args);
    }

    if (opts.size != null) {
      await invoke('setSize', {'width': opts.size!.width, 'height': opts.size!.height});
    }
    if (opts.alignment != null) {
      await setAlignment(viewId, alignment: opts.alignment!);
    }
    if (opts.minimumSize != null) {
      await invoke('setMinimumSize', {'width': opts.minimumSize!.width, 'height': opts.minimumSize!.height});
    }
    if (opts.maximumSize != null) {
      await invoke('setMaximumSize', {'width': opts.maximumSize!.width, 'height': opts.maximumSize!.height});
    }
    if (opts.title != null) await invoke('setTitle', {'title': opts.title});
    if (opts.titleBarStyle != null) {
      await invoke('setTitleBarStyle', {
        'titleBarStyle': opts.titleBarStyle!.name,
        'windowButtonVisibility': opts.windowButtonVisibility ?? true,
      });
    }
    if (opts.alwaysOnTop != null) {
      await invoke('setAlwaysOnTop', {'isAlwaysOnTop': opts.alwaysOnTop});
    }
    if (opts.fullScreen != null) {
      await invoke('setFullScreen', {'isFullScreen': opts.fullScreen});
    }
    if (opts.skipTaskbar) {
      await invoke('setSkipTaskbar', {'isSkipTaskbar': true});
    }
  }

  Future<void> _removeViewsNone() async {
    await _setMainPreConfirmClose(true);
    await removeView(_mainId);
  }

  /// Returns all secondary view IDs: registered ones plus native "orphaned"
  /// views that survived a hot restart (present in the platform dispatcher
  /// but absent from [_views]).
  List<int> _allSecondaryIds() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final registered = _views.keys.where((id) => id != _mainId);
    final orphaned = dispatcher.views
        .toList()
        .map((v) => v.viewId)
        .where((id) => id != _mainId && id != 0 && !_views.containsKey(id));
    return {...registered, ...orphaned}.toList();
  }

  Future<void> _removeViewsCascade() async {
    final allViews = _allSecondaryIds().reversed.toList();

    for (final id in allViews) {
      _closeCompleters[id] = Completer<bool>();
      await focus(id);
      await removeView(id);

      final closed = await _closeCompleters[id]!.future;
      _closeCompleters.remove(id);
      if (!closed) return;
    }

    await _setMainPreConfirmClose(true);
    await removeView(_mainId);
  }

  Future<void> _removeViewsForce() async {
    _closeCompleters.clear();
    for (final id in _allSecondaryIds()) {
      await setPreventClose(id, false);
      await setConfirmClose(id, true);
      await removeView(id);
    }

    await _setMainPreConfirmClose(true);
    // not disabled in main view
    // await setPreventClose(_mainId, false);
    await removeView(_mainId);
  }

  Future<Offset?> _calculateOffFromAlign(int viewId, {required Alignment alignment}) async {
    final sizeResult = await _staticChannel.invokeMethod<Map>('getBounds', {'viewId': viewId});
    if (sizeResult != null) {
      final windowSize = Size((sizeResult['width'] as num).toDouble(), (sizeResult['height'] as num).toDouble());
      return calcWindowPosition(windowSize, alignment);
    }
    return null;
  }

  Future<void> _removeSecondaryViewsForceAfterRestart(List<int> ids) async {
    _closeCompleters.clear();
    for (final id in ids) {
      // Stale entries (e.g. old main window ID after hot restart) are no longer
      // in the native windows dict, so calls may return NO_WINDOW. Ignore such
      // errors — the view will be cleaned up by the engine on its own.
      try {
        await setPreventClose(id, false);
        await setConfirmClose(id, true);
        await removeView(id);
      } catch (_) {}
    }
  }

  // --------------------------------------------------------------------------
  // Public API used by MultiViewDesktop
  // --------------------------------------------------------------------------

  Future<void> addView(Widget child, {WindowOptions? options}) async {
    final localOpt = options ?? widget.config.preferredOptions;

    final int token = _nextToken++;
    _pending[token] = child;
    _pendingOptions[token] = localOpt;

    Offset? pos;
    final windowSize = Size(localOpt.size?.width ?? 800.0, localOpt.size?.height ?? 600.0);
    if (localOpt.alignment != null) {
      pos = await calcWindowPosition(windowSize, localOpt.alignment!);
    }
    try {
      await _staticChannel.invokeMethod<void>('createWindow', {
        'token': token,
        'width': windowSize.width,
        'height': windowSize.height,
        'title': localOpt.title ?? '',
        'position': pos == null ? null : {'x': pos.dx, 'y': pos.dy},
        'titleBarStyle': localOpt.titleBarStyle?.name ?? 'normal',
        'windowButtonVisibility': localOpt.windowButtonVisibility ?? true,
      });
    } catch (e) {
      _pending.remove(token);
      _pendingOptions.remove(token);
      rethrow;
    }
  }

  Future<void> setPosition(int viewId, {required Offset pos}) async =>
      await _staticChannel.invokeMethod<void>('setPosition', _args(viewId, {'x': pos.dx, 'y': pos.dy}));

  Future<void> setAlignment(int viewId, {required Alignment alignment}) async {
    final pos = await _calculateOffFromAlign(viewId, alignment: alignment);
    if (pos != null) {
      await setPosition(viewId, pos: pos);
    }
  }

  Future<void> removeView(int viewId) async =>
      await _staticChannel.invokeMethod<void>('closeWindow', {'viewId': viewId});

  Future<void> focus(int viewId) async => await _staticChannel.invokeMethod<void>('focus', _args(viewId));

  Future<void> _setMainPreConfirmClose(bool isPreConfirm) async =>
      _staticChannel.invokeMethod<void>('mainPreConfirmClose', _args(_mainId, {'mainPreConfirmClose': isPreConfirm}));

  Future<void> setConfirmClose(int viewId, bool isConfirm) async =>
      await _staticChannel.invokeMethod<void>('confirmClose', _args(viewId, {'confirmClose': isConfirm}));

  Future<void> setPreventClose(int viewId, bool isPreventClose) async =>
      await _staticChannel.invokeMethod<void>('setPreventClose', _args(viewId, {'isPreventClose': isPreventClose}));

  /// Builds an argument map that always includes the [viewId] so the native
  /// side can route the call to the right OS window.
  static Map<String, dynamic> _args(int viewId, [Map<String, dynamic>? extra]) {
    final map = <String, dynamic>{'viewId': viewId};
    if (extra != null) map.addAll(extra);
    return map;
  }

  void addListener(int viewId, WindowListener listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListener>()).add(listener);
  }

  void removeListener(int viewId, WindowListener listener) {
    _listeners[viewId]?.remove(listener);
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = <Widget>[];
    if (_mainView != null) {
      views.add(
        View(
          key: ValueKey('view_$_mainId'),
          view: _mainView!,
          child: ViewScope(viewId: _mainView!.viewId, child: widget.home),
        ),
      );
    }

    for (final entry in _views.entries) {
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
