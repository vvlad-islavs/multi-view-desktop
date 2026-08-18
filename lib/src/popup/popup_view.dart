import 'dart:async';
import 'dart:ui' show FlutterView, Offset, Rect, Size;

import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/src/popup/element_position_tracker.dart';
import 'package:multiview_desktop/src/popup/popup_content_sizer.dart';
import 'package:multiview_desktop/src/popup/popup_controller.dart';
import 'package:multiview_desktop/src/popup/popup_positioner.dart';
import 'package:multiview_desktop/src/screen_retriever/screen_retriever.dart';
import 'package:multiview_desktop/src/view_root.dart' show globalRootState;
import 'package:multiview_desktop/src/view_scope.dart';

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
    required this.popup,
    required this.child,
    this.positioner = const PopupPositioner(),
  });

  /// Opens, closes, and repositions the popup from outside its content.
  final PopupController controller;

  /// Built inside the popup `FlutterView`. Receives parent inherited widgets.
  final WidgetBuilder popup;

  /// Trigger widget the popup is anchored to.
  final Widget child;

  /// How the popup is placed relative to [child].
  final PopupPositioner positioner;

  @override
  State<PopupView> createState() => _PopupViewState();
}

class _PopupViewState extends State<PopupView> {
  final GlobalKey _anchorKey = GlobalKey();

  ElementPositionTracker? _tracker;
  FlutterView? _flutterView;
  int? _realViewId;
  Size _contentSize = const Size(1, 1);
  Size _maxSize = const Size(800, 600);
  PopupPositioner _positioner = const PopupPositioner();
  Rect? _anchorRect;
  bool _opening = false;
  bool _isShown = false;

  // Cached data that doesn't change on every position tick.
  // Populated on open, refreshed in background while the popup is open.
  Rect _cachedParentFrame = Rect.zero;
  Rect _cachedDisplayRect = const Rect.fromLTWH(0, 0, 2560, 1440);
  bool _parentFrameRefreshing = false;
  bool _isPositioning = false;

  // Coalescing: only one native setBounds call in-flight at a time.
  // If another request arrives while one is running, _positionScheduled = true
  // causes a single follow-up call once the current one finishes.
  bool _positionInFlight = false;
  bool _positionScheduled = false;

  @override
  void initState() {
    super.initState();
    _positioner = widget.positioner;
    widget.controller.attach(onOpen: _open, onClose: _close, onUpdate: _onControllerUpdate);
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
      widget.controller.attach(onOpen: _open, onClose: _close, onUpdate: _onControllerUpdate);
    }
    if (oldWidget.positioner != widget.positioner) {
      _positioner = widget.positioner;
      _schedulePosition();
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    _tracker?.dispose();
    _tracker = null;
    final viewId = _realViewId;
    if (viewId != null) {
      unawaited(globalRootState.manager.destroyPopup(viewId));
    }
    super.dispose();
  }

  void _onControllerUpdate({Rect? anchorRect, PopupPositioner? positioner}) {
    if (anchorRect != null) _anchorRect = anchorRect;
    if (positioner != null) _positioner = positioner;
    _schedulePosition();
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

      // Fetch parent frame and display rect once (blocking).
      // Hot-path position updates use the cached values.
      _cachedParentFrame = await globalRootState.manager.getBounds(parentRealId);
      _cachedDisplayRect = await _fetchDisplayRect(_cachedParentFrame);

      final tracker = ElementPositionTracker(element: _anchorKey.currentContext ?? context);
      _anchorRect = tracker.getGlobalRect();

      final viewId = await globalRootState.manager.createPopup(parentRealId: parentRealId, size: const Size(1, 1));
      if (!mounted) {
        await globalRootState.manager.destroyPopup(viewId);
        return;
      }
      final flutterView = WidgetsBinding.instance.platformDispatcher.view(id: viewId);
      if (flutterView == null) {
        await globalRootState.manager.destroyPopup(viewId);
        return;
      }
      _realViewId = viewId;
      _flutterView = flutterView;
      _tracker?.dispose();
      tracker.onGlobalRectChange = (rect) {
        _anchorRect = rect;
        _schedulePosition();
      };
      _tracker = tracker;
      if (mounted) setState(() {});
    } finally {
      _opening = false;
    }
  }

  Future<void> _close() async {
    _tracker?.dispose();
    _tracker = null;
    final viewId = _realViewId;
    _realViewId = null;
    _flutterView = null;
    _anchorRect = null;
    _contentSize = const Size(1, 1);
    _isShown = false;
    _positionScheduled = false;
    if (viewId != null) {
      await globalRootState.manager.destroyPopup(viewId);
    }
    if (mounted) setState(() {});
  }

  void _onContentSize(Size size) {
    if (!mounted) return;
    if ((size.width - _contentSize.width).abs() < 0.5 && (size.height - _contentSize.height).abs() < 0.5) {
      return;
    }
    _contentSize = Size(size.width.clamp(1.0, _maxSize.width), size.height.clamp(1.0, _maxSize.height));
    _schedulePosition();
  }

  // ─── Position scheduling ───────────────────────────────────────────────────

  /// Requests a position update. If one is already in-flight, queues at most
  /// one follow-up so rapid changes coalesce instead of stacking up.
  void _schedulePosition() {
    if (_realViewId == null || _anchorRect == null) return;
    if (_positionInFlight) {
      _positionScheduled = true;
      return;
    }
    unawaited(_runPosition());
  }

  Future<void> _runPosition() async {
    _positionInFlight = true;
    try {
      await _applyPosition();
    } finally {
      _positionInFlight = false;
      if (_positionScheduled) {
        _positionScheduled = false;
        unawaited(_runPosition());
      }
    }
  }

  /// Applies the current popup position using cached parent and display data.
  /// The cache is refreshed in the background so the hot path stays near-zero
  /// async overhead (only one native `setPopupBounds` call per update).
  Future<void> _applyPosition() async {
    final viewId = _realViewId;
    final anchor = _anchorRect;
    if (viewId == null || anchor == null || !mounted) return;

    // Refresh parent frame in background — does not block this call.
    final parentRealId = ViewScope.of(context).viewId;
    _refreshParentFrame(parentRealId);

    final flutterView = View.of(context);
    final contentSize = flutterView.physicalSize / flutterView.devicePixelRatio;
    final pf = _cachedParentFrame;
    final dx = ((pf.width - contentSize.width) / 2).clamp(0.0, double.infinity);
    final dy = (pf.height - contentSize.height).clamp(0.0, double.infinity);
    final contentOrigin = Offset(pf.left + dx, pf.top + dy);
    final screenAnchor = anchor.shift(contentOrigin);

    final placed = _positioner.placeWindow(
      childSize: _contentSize,
      anchorRect: screenAnchor,
      parentRect: pf,
      displayRect: _cachedDisplayRect,
    );

    if (!mounted || _realViewId != viewId) return;
    if (_isPositioning) return;
    _isPositioning = true;
    await globalRootState.manager
        .positionPopup(viewId, placed)
        .whenComplete(() =>_isPositioning = false);

    if (!_isShown && _realViewId != null) {
      _isShown = true;
      await globalRootState.manager.show(_realViewId!);
    }
  }

  // ─── Background cache refresh ──────────────────────────────────────────────

  void _refreshParentFrame(int parentRealId) {
    if (_parentFrameRefreshing) return;
    _parentFrameRefreshing = true;
    globalRootState.manager
        .getBounds(parentRealId)
        .then((frame) {
          if (mounted) _cachedParentFrame = frame;
        })
        .whenComplete(() => _parentFrameRefreshing = false);
  }

  static Future<Rect> _fetchDisplayRect(Rect parentFrame) async {
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      Display? best;
      var bestArea = 0.0;
      for (final display in displays) {
        final origin = display.visiblePosition ?? Offset.zero;
        final size = display.visibleSize ?? display.size;
        final rect = origin & size;
        final overlap = rect.intersect(parentFrame);
        final area = overlap.width.clamp(0.0, double.infinity) * overlap.height.clamp(0.0, double.infinity);
        if (area >= bestArea) {
          bestArea = area;
          best = display;
        }
      }
      if (best != null) {
        final origin = best.visiblePosition ?? Offset.zero;
        final size = best.visibleSize ?? best.size;
        return origin & size;
      }
    } catch (_) {}
    // Fallback: generous area around the parent window.
    return parentFrame.inflate(800);
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
                  child: Builder(builder: widget.popup),
                ),
              ),
            ),
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
    );
  }
}
