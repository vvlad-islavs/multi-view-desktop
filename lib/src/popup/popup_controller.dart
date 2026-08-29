import 'dart:ui' show FlutterView, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_root.dart' show globalRootState;

/// Controls a [PopupView] from outside the popup content.
///
/// [isOpen] is the source of truth. The native window and popup child live on
/// this controller for the whole open session:
/// * [open] / [close] / [toggle] are user intent (close fades, then drops the child).
/// * If the anchor [PopupView] is unmounted, the native window is only hidden.
///   The child stays mounted under an [Overlay] entry, so its [State] is kept.
///   A new [PopupView] reattaches without fading and without rebuilding the child.
class PopupController extends ChangeNotifier {
  bool _isOpen = false;
  bool _attached = false;
  bool _fadeOnNextShow = false;

  Future<void> Function(AnimationSettings? animation)? _openHandler;
  Future<void> Function(AnimationSettings? animation)? _closeHandler;
  Future<void> Function(AnimationSettings? animation)? _dropSession;

  final GlobalKey _contentKey = GlobalKey();
  Widget? _content;
  OverlayEntry? _hostEntry;
  FlutterView? _flutterView;
  int? _viewId;
  Size _contentSize = const Size(1, 1);
  bool _nativeShown = false;
  void Function(Size size)? _onContentSize;

  /// Whether the popup is currently requested open.
  bool get isOpen => _isOpen;

  /// Whether a [PopupView] is currently bound to this controller.
  bool get isAttached => _attached;

  /// Opens the popup. No-op when already open.
  Future<void> open({AnimationSettings? animation}) async {
    if (_isOpen) return;
    _isOpen = true;
    _fadeOnNextShow = true;
    MvdLog.instance.info('popup', 'controller.open');
    notifyListeners();
    await _openHandler?.call(animation);
  }

  /// Closes the popup. No-op when already closed.
  ///
  /// Drops the native window and the cached child even if [PopupView] is
  /// currently unmounted.
  Future<void> close({AnimationSettings? animation}) async {
    if (!_isOpen) return;
    _isOpen = false;
    _fadeOnNextShow = false;
    MvdLog.instance.info('popup', 'controller.close', {'realId': _viewId});
    notifyListeners();
    await _closeHandler?.call(animation);
    await _dropSession?.call(animation);
  }

  /// Toggles [open] / [close].
  Future<void> toggle({AnimationSettings? animation}) =>
      _isOpen ? close(animation: animation) : open(animation: animation);

  @override
  void dispose() {
    _hostEntry?.remove();
    _hostEntry = null;
    _content = null;
    _openHandler = null;
    _closeHandler = null;
    _dropSession = null;
    _onContentSize = null;
    final id = _viewId;
    _viewId = null;
    _flutterView = null;
    if (id != null) {
      globalRootState.manager.destroyPopup(id);
    }
    super.dispose();
  }

  /// Bound by [PopupView]. Do not call from application code.
  @internal
  void attach({
    required Future<void> Function(AnimationSettings? animation) onOpen,
    required Future<void> Function(AnimationSettings? animation) onClose,
    required Future<void> Function(AnimationSettings? animation) dropSession,
  }) {
    _openHandler = onOpen;
    _closeHandler = onClose;
    _dropSession = dropSession;
    _attached = true;
  }

  /// Bound by [PopupView]. Does not drop the open session.
  @internal
  void detach() {
    _openHandler = null;
    _closeHandler = null;
    _attached = false;
  }

  /// True only for the first native show after a user [open].
  @internal
  bool takeOpenFade() {
    final pending = _fadeOnNextShow;
    _fadeOnNextShow = false;
    return pending;
  }

  @internal
  bool get hasSession => _viewId != null;

  @internal
  int? get viewId => _viewId;

  @internal
  FlutterView? get flutterView => _flutterView;

  @internal
  Widget? get content => _content;

  @internal
  Size get contentSize => _contentSize;

  @internal
  bool get nativeShown => _nativeShown;

  @internal
  set nativeShown(bool value) => _nativeShown = value;

  /// Holds [child] for the open session. Same instance is reused if the
  /// anchor [PopupView] remounts.
  @internal
  Widget retainContent(Widget child) {
    return _content ??= KeyedSubtree(key: _contentKey, child: child);
  }

  @internal
  void bindSession({
    required int viewId,
    required FlutterView flutterView,
    required OverlayEntry host,
  }) {
    _viewId = viewId;
    _flutterView = flutterView;
    _hostEntry = host;
    _contentSize = const Size(1, 1);
    _nativeShown = false;
  }

  @internal
  void listenContentSize(void Function(Size size)? listener) {
    _onContentSize = listener;
  }

  @internal
  void reportContentSize(Size size) {
    if ((size.width - _contentSize.width).abs() < 0.5 && (size.height - _contentSize.height).abs() < 0.5) {
      return;
    }
    _contentSize = size;
    _onContentSize?.call(size);
  }

  /// Removes the overlay host and cached child. Native destroy is done by
  /// [PopupView] via [dropSession].
  @internal
  void clearSessionWidgets() {
    _hostEntry?.remove();
    _hostEntry = null;
    _content = null;
    _flutterView = null;
    _viewId = null;
    _nativeShown = false;
    _contentSize = const Size(1, 1);
  }
}
