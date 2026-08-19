import 'dart:async';
import 'dart:ui' show FlutterView, Offset, Rect, Size;

import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/src/popup/element_position_tracker.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/popup/popup_content_sizer.dart';
import 'package:multiview_desktop/src/popup/popup_controller.dart';
import 'package:multiview_desktop/src/popup/popup_positioner.dart';
import 'package:multiview_desktop/src/view_root.dart' show globalRootState;
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/window_listener.dart';

/// Hosts a native popup window anchored to [child] via [ViewAnchor].
///
/// The popup has no `MaterialApp`, router, or shell of its own. Theme and
/// inherited widgets from the parent window flow through [ViewAnchor].
/// Native window size follows the popup content:
/// wrap the content in [SizedBox] for a fixed size, otherwise it shrink-wraps.
///
/// ```dart
/// final controller = PopupController();
///
/// PopupView(
///   controller: controller,
///   positioner: const PopupPositioner(),
///   popup: (context) => const MyMenu(),
///   child: TextButton(
///     onPressed: controller.toggle,
///     child: const Text('Menu'),
///   ),
/// )
/// ```
class PopupView extends StatefulWidget {
  const PopupView({
    super.key,
    required this.controller,
    required this.builder,
    required this.child,
    this.positioner = const PopupPositioner(),
  });

  /// Opens, closes, and repositions the popup from outside its content.
  final PopupController controller;

  /// Built inside the popup `FlutterView`. Receives parent inherited widgets.
  final WidgetBuilder builder;

  /// Trigger widget the popup is anchored to.
  final Widget child;

  /// How the popup is placed relative to [child].
  final PopupPositioner positioner;

  @override
  State<PopupView> createState() => _PopupViewState();
}

class _PopupViewState extends State<PopupView> {
  final GlobalKey _anchorKey = GlobalKey();

  FlutterView? _flutterView;
  int? _realViewId;
  Size _contentSize = const Size(1, 1);
  Size _maxSize = const Size(800, 600);
  PopupPositioner _positioner = const PopupPositioner();
  Rect? _anchorRect;
  bool _opening = false;
  bool _isShown = false;

  // Cached data that doesn't change on every position tick.
  // Populated from sync FFI. Refreshed only when the parent window moves/resizes.
  Rect _cachedParentFrame = Rect.zero;
  Rect _cachedDisplayRect = const Rect.fromLTWH(0, 0, 2560, 1440);

  // Set when the parent window moves or resizes so that the next
  // _applyPositionSync() call refreshes the cached parent frame via FFI.
  // False during normal scroll — the parent is stationary so the cache is valid,
  // and we can skip the getFrame / getDisplayRect FFI calls entirely.
  bool _parentFrameDirty = true;
  int? _parentListenerViewId;
  late final _ParentWindowListener _parentListener;

  ScrollNotificationObserverState? _scrollObserver;
  int _parentScrollDepth = 0;
  bool _parentScrolling = false;

  LocalElementPositionTracker? _tracker;

  @override
  void initState() {
    super.initState();
    _parentListener = _ParentWindowListener(() {
      _parentFrameDirty = true;
      _applyPositionSync();
    });
    _positioner = widget.positioner;
    widget.controller.attach(onOpen: _open, onClose: _close);
    if (widget.controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.isOpen && _flutterView == null) {
          unawaited(_open());
        }
      });
    }
  }

  @override
  void didUpdateWidget(PopupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach(onOpen: _open, onClose: _close);
    }
    if (oldWidget.positioner != widget.positioner) {
      _positioner = widget.positioner;
      _applyPositionSync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (observer == _scrollObserver) return;
    _scrollObserver?.removeListener(_onParentScrollNotification);
    _scrollObserver = observer;
    _scrollObserver?.addListener(_onParentScrollNotification);
    _catchUpAncestorScrolling();
  }

  @override
  void dispose() {
    _scrollObserver?.removeListener(_onParentScrollNotification);
    _scrollObserver = null;
    _unregisterParentListener();
    widget.controller.detach();
    _tracker?.dispose();
    _tracker = null;
    final viewId = _realViewId;
    if (viewId != null) {
      globalRootState.manager.destroyPopup(viewId);
    }
    super.dispose();
  }

  Size _parentContentSize() {
    final view = View.of(context);
    final logical = view.physicalSize / view.devicePixelRatio;
    if (logical.width <= 0 || logical.height <= 0) return const Size(800, 600);
    return logical;
  }

  Future<void> _open() async {
    if (!mounted || _opening || _flutterView != null) return;
    _opening = true;
    try {
      final parentRealId = ViewScope.of(context).viewId;
      _maxSize = _parentContentSize();

      _cachedParentFrame = FfiBridge.instance.getFrame(parentRealId) ?? Rect.zero;
      _cachedDisplayRect = FfiBridge.instance.getDisplayRect(_cachedParentFrame) ?? _cachedDisplayRect;
      _unregisterParentListener();
      _parentListenerViewId = parentRealId;
      _parentFrameDirty = false;
      globalRootState.manager.addListener(parentRealId, _parentListener);
      _tracker?.dispose();
      _tracker = LocalElementPositionTracker(element: _anchorKey.currentContext ?? context);
      _anchorRect = _tracker?.getGlobalRect();

      final viewId = globalRootState.manager.createPopup(parentRealId: parentRealId, size: const Size(1, 1));
      if (!mounted) {
        globalRootState.manager.destroyPopup(viewId);
        return;
      }
      final flutterView = WidgetsBinding.instance.platformDispatcher.view(id: viewId);
      if (flutterView == null) {
        globalRootState.manager.destroyPopup(viewId);
        return;
      }
      _realViewId = viewId;
      _flutterView = flutterView;
      _tracker?.onGlobalRectChange = (rect) {
        _anchorRect = rect;
        _applyPositionSync();
      };
      _catchUpAncestorScrolling();
      _applyClickThrough();
      if (mounted) setState(() {});
    } finally {
      _opening = false;
    }
  }

  void _unregisterParentListener() {
    final id = _parentListenerViewId;
    if (id != null) {
      globalRootState.manager.removeListener(id, _parentListener);
      _parentListenerViewId = null;
    }
  }

  bool _isFromThisPopup(ScrollNotification n) {
    final popupId = _realViewId;
    if (popupId == null) return false;
    final origin = n.context;
    if (origin == null || !origin.mounted) return false;
    return View.maybeOf(origin)?.viewId == popupId;
  }

  void _onParentScrollNotification(ScrollNotification n) {
    if (_isFromThisPopup(n)) return;
    if (n is ScrollStartNotification) {
      _parentScrollDepth++;
      _setParentScrolling(true);
    } else if (n is ScrollEndNotification) {
      if (_parentScrollDepth > 0) _parentScrollDepth--;
      if (_parentScrollDepth == 0) _setParentScrolling(false);
    }
  }

  void _catchUpAncestorScrolling() {
    if (_parentScrollDepth > 0) return;
    var scrolling = false;
    context.visitAncestorElements((e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        if ((e.state as ScrollableState).position.isScrollingNotifier.value) {
          scrolling = true;
          return false;
        }
      }
      return true;
    });
    if (scrolling) {
      _parentScrollDepth = 1;
      _setParentScrolling(true);
    }
  }

  void _setParentScrolling(bool on) {
    if (_parentScrolling == on) return;
    _parentScrolling = on;
    _applyClickThrough();
  }

  void _applyClickThrough() {
    final id = _realViewId;
    if (id == null) return;
    FfiBridge.instance.setIgnoreMouseEvents(id, _parentScrolling);
  }

  Future<void> _close() async {
    _unregisterParentListener();
    _parentFrameDirty = true;
    _tracker?.dispose();
    _tracker = null;
    final viewId = _realViewId;
    if (viewId != null) {
      FfiBridge.instance.setIgnoreMouseEvents(viewId, false);
    }
    _realViewId = null;
    _flutterView = null;
    _anchorRect = null;
    _contentSize = const Size(1, 1);
    _isShown = false;
    _parentScrollDepth = 0;
    _parentScrolling = false;
    if (viewId != null) {
      globalRootState.manager.destroyPopup(viewId);
    }
    if (mounted) setState(() {});
  }

  void _onContentSize(Size size) {
    if (!mounted) return;
    if ((size.width - _contentSize.width).abs() < 0.5 && (size.height - _contentSize.height).abs() < 0.5) {
      return;
    }
    _contentSize = Size(size.width.clamp(1.0, _maxSize.width), size.height.clamp(1.0, _maxSize.height));
    _applyPositionSync();
  }

  /// Fully synchronous position update via FFI.
  ///
  /// Called directly on every anchor-position or content-size change.
  /// No Future, no await, no microtask queue involvement — executes inline and
  /// returns before the caller continues. This keeps the popup in lock-step
  /// with the display refresh rate (60 Hz, 120 Hz, etc.).
  void _applyPositionSync() {
    if (_realViewId == null || _anchorRect == null) return;
    final viewId = _realViewId;
    final anchor = _anchorRect;
    if (viewId == null || anchor == null || !mounted) return;

    // Only refresh parent frame / display rect from FFI when the parent window
    // actually moved or resized (flagged by _ParentWindowListener).
    if (_parentFrameDirty) {
      final pf = FfiBridge.instance.getFrame(ViewScope.of(context).viewId);
      if (pf == null || _realViewId != viewId) return;
      _cachedParentFrame = pf;
      _cachedDisplayRect = FfiBridge.instance.getDisplayRect(pf) ?? _cachedDisplayRect;
      _parentFrameDirty = false;
    }

    final pf = _cachedParentFrame;
    final contentSize = View.of(context).physicalSize / View.of(context).devicePixelRatio;
    final dx = ((pf.width - contentSize.width) / 2).clamp(0.0, double.infinity);
    final dy = (pf.height - contentSize.height).clamp(0.0, double.infinity);
    final screenAnchor = anchor.shift(Offset(pf.left + dx, pf.top + dy));

    final placed = _positioner.placeWindow(
      childSize: _contentSize,
      anchorRect: screenAnchor,
      parentRect: pf,
      displayRect: _cachedDisplayRect,
    );

    FfiBridge.instance.setFrame(viewId, placed);

    if (!_isShown && _realViewId != null) {
      _isShown = true;
      globalRootState.proxies.state.show(_realViewId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewAnchor(
      view: _flutterView == null || _realViewId == null
          ? null
          : View(
              view: _flutterView!,
              child: ViewScope(
                viewId: _realViewId!,
                child: PopupContentSizer(
                  maxSize: _maxSize,
                  onSize: _onContentSize,
                  child: Builder(builder: widget.builder),
                ),
              ),
            ),
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
    );
  }
}

// ─── Parent-window listener ────────────────────────────────────────────────────

/// Minimal [WindowListenerCallbacks] that marks the parent frame cache dirty
/// whenever the parent window moves or resizes. All other events are no-ops.
class _ParentWindowListener implements WindowListenerCallbacks {
  const _ParentWindowListener(this._onDirty);

  final VoidCallback _onDirty;

  @override
  void onWindowMove() => _onDirty();

  @override
  void onWindowMoved() => _onDirty();

  @override
  void onWindowResize() => _onDirty();

  @override
  void onWindowResized() => _onDirty();

  @override
  bool onWindowClose() {
    return true;
  }

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String _) {}
}
