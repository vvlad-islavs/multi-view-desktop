import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';
import 'package:multiview_desktop/src/popup/element_position_tracker.dart';
import 'package:multiview_desktop/src/popup/popup_content_sizer.dart';
import 'package:multiview_desktop/src/popup/popup_controller.dart';
import 'package:multiview_desktop/src/popup/popup_positioner.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';
import 'package:multiview_desktop/src/view_root.dart' show globalRootState;
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/window_listener.dart';

/// Anchors a native popup to [child].
///
/// [PopupController] owns the native window and the overlay-hosted child.
/// This widget tracks the anchor and positions the window. Unmounting hides
/// the window without closing the session or rebuilding the child.
///
/// ```dart
/// final controller = PopupController();
///
/// PopupView(
///   controller: controller,
///   positioner: const PopupPositioner(),
///   builder: (context) => const MyMenu(),
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

  /// Opens, closes, and holds the popup child for the open session.
  final PopupController controller;

  /// Built once per [PopupController.open] and reused if this widget remounts.
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
  final ViewManagerProxies _proxies = globalRootState.proxies;

  PopupPositioner _positioner = const PopupPositioner();
  Rect? _anchorRect;
  Future<void>? _openWork;
  bool _dropping = false;
  Size _maxSize = const Size(800, 600);

  Rect _cachedParentFrame = Rect.zero;
  Rect _cachedDisplayRect = const Rect.fromLTWH(0, 0, 2560, 1440);
  bool _parentFrameDirty = true;
  int? _parentListenerViewId;
  late final _ParentWindowListener _parentListener;

  ScrollNotificationObserverState? _scrollObserver;
  int _parentScrollDepth = 0;
  bool _parentScrolling = false;
  bool _anchorMoving = false;
  Timer? _anchorSettleTimer;
  LocalElementPositionTracker? _tracker;
  Rect? _pendingPlaced;
  bool _boundsCommitScheduled = false;
  int _placeGeneration = 0;

  /// Precision-touchpad wheel bursts often have no lasting ScrollStart/End.
  /// Rect motion plus this delay is what actually defers native re-show.
  static const Duration _anchorSettleDelay = Duration(milliseconds: 50);

  PopupController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _parentListener = _ParentWindowListener(() {
      _parentFrameDirty = true;
      if (_controller.anchorHidden) return;
      _applyPositionSync();
    });
    _positioner = widget.positioner;
    _bindController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.hasSession) {
        _adoptSession();
      } else if (_controller.isOpen) {
        unawaited(_open(null));
      }
    });
  }

  @override
  void didUpdateWidget(PopupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller
        ..listenContentSize(null)
        ..detach();
      _bindController();
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
    _unbindPositioning();
    _controller.listenContentSize(null);
    _hideNative(reason: 'anchor unmounted', forceNativeHide: true);
    _controller.detach();
    super.dispose();
  }

  void _bindController() {
    _controller.attach(onOpen: _open, onClose: _onUserClose, dropSession: _dropSession);
    _controller.listenContentSize(_onContentSize);
  }

  void _adoptSession() {
    _startTracking();
    _applyClickThrough();
    if (_controller.anchorHidden) {
      MvdLog.instance.info('popup', 'adopt session skipped show, anchor still hidden', {
        'realId': _controller.viewId,
      });
      return;
    }
    _applyPositionSync();
  }

  Future<void> _onUserClose(AnimationSettings? animation) async {
    _unbindPositioning();
    if (mounted) setState(() {});
  }

  Future<void> _dropSession(AnimationSettings? animation) async {
    if (_dropping) return;
    _dropping = true;
    try {
      if (_controller.isOpen) {
        _resumeSession();
        return;
      }
      final viewId = _controller.viewId;
      if (viewId != null) {
        _proxies.input.setIgnoreMouseEvents(viewId, false);
        await globalRootState.manager.closePopup(viewId, animation: animation, destroy: false);
      }
      if (_controller.isOpen) {
        _resumeSession();
        return;
      }
      if (viewId != null) {
        await globalRootState.manager.destroyPopup(viewId);
      }
      _controller.clearSessionWidgets();
    } finally {
      _dropping = false;
    }
  }

  /// Re-binds tracking and shows the existing native window after a cancelled close.
  void _resumeSession() {
    if (!mounted || !_controller.isOpen || !_controller.hasSession) return;
    MvdLog.instance.info('popup', 'resume session after cancelled close', {
      'realId': _controller.viewId,
    });
    _controller.clearAnchorHidden();
    _controller.nativeShown = false;
    _startTracking();
    _applyClickThrough();
    if (mounted) setState(() {});
    _reveal(allowFade: true);
    _applyPositionSync();
  }

  Size _parentContentSize() {
    final view = View.of(context);
    final logical = view.physicalSize / view.devicePixelRatio;
    if (logical.width <= 0 || logical.height <= 0) return const Size(800, 600);
    return logical;
  }

  Future<void> _open(AnimationSettings? animation) async {
    while (true) {
      if (!mounted || !_controller.isOpen) return;
      if (_controller.hasSession) {
        _resumeSession();
        return;
      }
      final inFlight = _openWork;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      break;
    }
    final work = Completer<void>();
    _openWork = work.future;
    try {
      if (!mounted || !_controller.isOpen) return;
      if (_controller.hasSession) {
        _resumeSession();
        return;
      }
      final parentRealId = ViewScope.of(context).viewId;
      MvdLog.instance.info('popup', 'open session', {'parentRealId': parentRealId});
      _maxSize = _parentContentSize();
      _cachedParentFrame = _proxies.position.getBounds(parentRealId);
      _cachedDisplayRect = _proxies.position.getDisplayRect(_cachedParentFrame) ?? _cachedDisplayRect;
      _parentFrameDirty = false;

      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        throw FlutterError(
          'PopupView requires an Overlay ancestor (e.g. MaterialApp) so the '
          'popup child can outlive the anchor being unmounted.',
        );
      }

      _controller.retainContent(_OncePopupChild(builder: widget.builder));

      final viewId = await globalRootState.manager.createPopup(
        parentRealId: parentRealId,
        size: const Size(1, 1),
        animation: animation,
      );
      if (!mounted || !_controller.isOpen) {
        globalRootState.manager.destroyPopup(viewId);
        _controller.clearSessionWidgets();
        return;
      }
      if (_controller.hasSession) {
        globalRootState.manager.destroyPopup(viewId);
        _resumeSession();
        return;
      }
      final flutterView = WidgetsBinding.instance.platformDispatcher.view(id: viewId);
      if (flutterView == null) {
        MvdLog.instance.error('popup', 'FlutterView missing after createPopup', {'realId': viewId});
        globalRootState.manager.destroyPopup(viewId);
        _controller.clearSessionWidgets();
        return;
      }

      final host = OverlayEntry(
        builder: (context) => _PopupOverlayHost(controller: _controller, maxSize: _maxSize),
      );
      _controller.bindSession(viewId: viewId, flutterView: flutterView, host: host);
      overlay.insert(host);

      _startTracking();
      _applyClickThrough();
      if (mounted) setState(() {});
    } finally {
      _openWork = null;
      if (!work.isCompleted) work.complete();
    }
  }

  void _startTracking() {
    _unregisterParentListener();
    if (!mounted) return;
    final parentRealId = ViewScope.of(context).viewId;
    _parentListenerViewId = parentRealId;
    globalRootState.manager.addListener(parentRealId, _parentListener);
    _tracker?.dispose();
    _tracker = LocalElementPositionTracker(element: _anchorKey.currentContext ?? context);
    _anchorRect = _controller.anchorHidden ? null : _tracker?.getGlobalRect();
    _tracker?.onGlobalRectChange = (rect) {
      _anchorRect = rect;
      _noteAnchorMotion();
      _applyPositionSync();
    };
    _tracker?.onLost = () {
      _anchorRect = null;
      _hideNative(reason: 'tracker lost render object');
    };
    _catchUpAncestorScrolling();
  }

  void _unbindPositioning() {
    _unregisterParentListener();
    _parentFrameDirty = true;
    _cancelAnchorSettle();
    _tracker?.dispose();
    _tracker = null;
    _anchorRect = null;
    _parentScrollDepth = 0;
    _parentScrolling = false;
  }

  void _cancelAnchorSettle() {
    _anchorSettleTimer?.cancel();
    _anchorSettleTimer = null;
    _anchorMoving = false;
  }

  void _unregisterParentListener() {
    final id = _parentListenerViewId;
    if (id != null) {
      globalRootState.manager.removeListener(id, _parentListener);
      _parentListenerViewId = null;
    }
  }

  bool _isFromThisPopup(ScrollNotification n) {
    final popupId = _controller.viewId;
    if (popupId == null) return false;
    final origin = n.context;
    if (origin == null || !origin.mounted) return false;
    return View.maybeOf(origin)?.viewId == popupId;
  }

  void _onParentScrollNotification(ScrollNotification n) {
    if (_isFromThisPopup(n)) return;
    // Mark motion first so a same-frame Start/End pair (Windows trackpad
    // as discrete wheel ticks) cannot reveal the HWND mid-gesture.
    _noteAnchorMotion();
    if (n is ScrollStartNotification) {
      _parentScrollDepth++;
      _setParentScrolling(true);
    } else if (n is ScrollEndNotification) {
      if (_parentScrollDepth > 0) _parentScrollDepth--;
      if (_parentScrollDepth == 0) _setParentScrolling(false);
    }
  }

  /// True while an ancestor is scrolling or the anchor rect is still moving.
  /// Native re-show waits until this is false so ShowWindow is not called
  /// during a Windows touchpad wheel flood (DWM chrome without a Flutter frame).
  ///
  /// Only for windows.
  bool _shouldDeferNativeShow() => (_parentScrolling || _anchorMoving) && Platform.isWindows;

  void _noteAnchorMotion() {
    _anchorMoving = true;
    _anchorSettleTimer?.cancel();
    _anchorSettleTimer = Timer(_anchorSettleDelay, () {
      _anchorSettleTimer = null;
      _anchorMoving = false;
      if (mounted && _controller.hasSession) {
        _applyPositionSync();
      }
    });
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
    if (!on && mounted && _controller.hasSession) {
      _applyPositionSync();
    }
  }

  void _applyClickThrough() {
    _controller.setParentScrolling(_parentScrolling);
  }

  void _onContentSize(Size size) {
    if (!mounted || _controller.anchorHidden) return;
    _applyPositionSync();
  }

  void _reveal({required bool allowFade}) {
    final viewId = _controller.viewId;
    if (viewId == null || _controller.nativeShown || _controller.anchorHidden) return;
    if (_shouldDeferNativeShow()) return;
    _controller.nativeShown = true;
    unawaited(globalRootState.manager.showPopup(viewId, animate: allowFade && _controller.takeOpenFade()));
  }

  void _hideNative({required String reason, bool forceNativeHide = false}) {
    _placeGeneration++;
    _pendingPlaced = null;
    _controller.markAnchorHidden();
    final viewId = _controller.viewId;
    if (viewId == null || !_controller.isOpen) return;
    if (!_controller.nativeShown && !forceNativeHide) return;
    MvdLog.instance.info('popup', 'hiding native popup', {'realId': viewId, 'reason': reason});
    globalRootState.manager.hidePopup(viewId);
    _controller.nativeShown = false;
  }

  /// Visible clip of the scroll view: hide as soon as the trigger leaves it.
  bool _anchorInVisibleClip() {
    final box = _anchorBox();
    if (box == null) return false;
    final anchor = _globalRectOf(box);
    if (anchor == null || anchor.isEmpty) return false;

    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is RenderBox) {
      final visible = _globalRectOf(viewport as RenderBox);
      if (visible == null) return false;
      return visible.overlaps(anchor);
    }

    final view = View.maybeOf(context);
    if (view == null) return false;
    final logical = view.physicalSize / view.devicePixelRatio;
    if (logical.width <= 0 || logical.height <= 0) return false;
    return (Offset.zero & logical).overlaps(anchor);
  }

  /// Stricter than [_anchorInVisibleClip]: the trigger's center is inside the
  /// viewport's painted size. Used to re-show after [PopupController.anchorHidden]
  /// so cache-extent / remount layout cannot clear the hidden flag.
  bool _anchorPaintedInViewport() {
    final box = _anchorBox();
    if (box == null) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) {
      return _anchorInVisibleClip();
    }
    try {
      final revealed = viewport.getOffsetToReveal(box, 0.5);
      if (viewport is! RenderBox) return false;
      final vpBox = viewport as RenderBox;
      if (!vpBox.hasSize) return false;
      return (Offset.zero & vpBox.size).contains(revealed.rect.center);
    } catch (_) {
      return false;
    }
  }

  RenderBox? _anchorBox() {
    final ctx = _anchorKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box;
  }

  Rect? _globalRectOf(RenderBox box) {
    if (!box.attached || !box.hasSize) return null;
    try {
      return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    } catch (_) {
      return null;
    }
  }

  void _applyPositionSync() {
    final viewId = _controller.viewId;
    if (viewId == null || !mounted) return;
    if (_anchorRect == null || !_anchorInVisibleClip()) {
      _hideNative(reason: 'anchor not in view');
      return;
    }
    if (_controller.anchorHidden) {
      if (!_anchorPaintedInViewport() || _shouldDeferNativeShow()) {
        return;
      }
    }
    _controller.clearAnchorHidden();

    final anchor = _anchorRect!;

    if (_parentFrameDirty) {
      final pf = _proxies.position.getBounds(ViewScope.of(context).viewId);
      if (_controller.viewId != viewId) return;
      _cachedParentFrame = pf;
      _cachedDisplayRect = _proxies.position.getDisplayRect(pf) ?? _cachedDisplayRect;
      _parentFrameDirty = false;
    }

    final pf = _cachedParentFrame;
    final contentSize = View.of(context).physicalSize / View.of(context).devicePixelRatio;
    final dx = ((pf.width - contentSize.width) / 2).clamp(0.0, double.infinity);
    final dy = (pf.height - contentSize.height).clamp(0.0, double.infinity);
    final screenAnchor = anchor.shift(Offset(pf.left + dx, pf.top + dy));

    _pendingPlaced = _positioner.placeWindow(
      childSize: _controller.contentSize,
      anchorRect: screenAnchor,
      parentRect: pf,
      displayRect: _cachedDisplayRect,
    );
    _commitPopupBoundsWhenIdle();
  }

  /// Native [setPopupBounds] can synchronously pump a Flutter frame. That
  /// must not run during layout, paint, or post-frame callbacks.
  ///
  /// Same rule as view-close deferral: wait for [SchedulerBinding.endOfFrame]
  /// so the scheduler is [SchedulerPhase.idle].
  void _commitPopupBoundsWhenIdle() {
    final generation = _placeGeneration;
    void commit() {
      _boundsCommitScheduled = false;
      if (generation != _placeGeneration) return;
      final viewId = _controller.viewId;
      final placed = _pendingPlaced;
      if (viewId == null || placed == null || !mounted) return;
      if (!_anchorInVisibleClip()) return;
      if (_controller.anchorHidden) return;
      _proxies.position.setPopupBounds(viewId, placed);
      _reveal(allowFade: true);
    }

    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      commit();
      return;
    }
    if (_boundsCommitScheduled) return;
    _boundsCommitScheduled = true;
    binding.endOfFrame.then((_) => commit());
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _anchorKey, child: widget.child);
  }
}

/// Runs [builder] once in the popup [View], so the child keeps [State]
/// across anchor remounts (the widget is cached on [PopupController]).
class _OncePopupChild extends StatefulWidget {
  const _OncePopupChild({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_OncePopupChild> createState() => _OncePopupChildState();
}

class _OncePopupChildState extends State<_OncePopupChild> {
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    return _child ??= widget.builder(context);
  }
}

class _PopupOverlayHost extends StatelessWidget {
  const _PopupOverlayHost({required this.controller, required this.maxSize});

  final PopupController controller;
  final Size maxSize;

  @override
  Widget build(BuildContext context) {
    final flutterView = controller.flutterView;
    final viewId = controller.viewId;
    final content = controller.content;
    if (flutterView == null || viewId == null || content == null) {
      return const SizedBox.shrink();
    }
    return ViewAnchor(
      view: View(
        view: flutterView,
        child: InternalViewScope(
          viewId: viewId,
          child: PopupContentSizer(
            maxSize: maxSize,
            onSize: controller.reportContentSize,
            child: Overlay.wrap(alwaysSizeToContent: true, child: content),
          ),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

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
  bool onWindowClose() => true;

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
