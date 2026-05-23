import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'view_scope.dart';
import 'window_communicator.dart';
import 'window_listener.dart';
import 'window_options.dart';

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

    // Prefer viewId > 0 (real ViewController surface); fall back to first.
    final initial = WidgetsBinding.instance.platformDispatcher.views;
    if (initial.isNotEmpty) {
      _mainView = initial.firstWhere((v) => v.viewId != 0, orElse: () => initial.first);
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
      return;
    }

    if (_mainView != null && _mainView!.viewId == 0 && realView != null) {
      setState(() => _mainView = realView);
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
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId == _mainId && viewId != null) {
        switch (widget.config.closeMode) {
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
    if (opts.minimumSize != null) {
      await invoke('setMinimumSize', {'width': opts.minimumSize!.width, 'height': opts.minimumSize!.height});
    }
    if (opts.maximumSize != null) {
      await invoke('setMaximumSize', {'width': opts.maximumSize!.width, 'height': opts.maximumSize!.height});
    }
  }

  Future<void> _removeViewsNone() async {
    await _setMainPreConfirmClose(true);
    await removeView(_mainId);
  }

  Future<void> _removeViewsCascade() async {
    final allViews = List.from(_views.keys.toList().reversed);

    for (final id in allViews) {
      if (id == _mainId) continue;
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
    for (final id in _views.keys.toList()) {
      if (id == _mainId) continue;
      await setPreventClose(id, false);
      await setConfirmClose(id, true);
      await removeView(id);
    }

    await _setMainPreConfirmClose(true);
    await setPreventClose(_mainId, false);
    await removeView(_mainId);
  }

  // --------------------------------------------------------------------------
  // Public API used by MultiViewDesktop
  // --------------------------------------------------------------------------

  Future<void> addView(Widget child, {WindowOptions? options}) async {
    final int token = _nextToken++;
    _pending[token] = child;
    if (options != null) _pendingOptions[token] = options;

    try {
      await _staticChannel.invokeMethod<void>('createWindow', {
        'token': token,
        'width': options?.size?.width ?? 800.0,
        'height': options?.size?.height ?? 600.0,
        'title': options?.title ?? '',
        'center': options?.center ?? true,
        'titleBarStyle': options?.titleBarStyle?.name ?? 'normal',
        'windowButtonVisibility': options?.windowButtonVisibility ?? true,
      });
    } catch (e) {
      _pending.remove(token);
      _pendingOptions.remove(token);
      rethrow;
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
      final flutterView = dispatcher.view(id: entry.key);
      if (flutterView != null) {
        views.add(
          View(
            key: ValueKey('view_${entry.key}'),
            view: flutterView,
            child: ViewScope(viewId: entry.key, child: entry.value),
          ),
        );
      }
    }

    return ViewCollection(views: views);
  }
}
