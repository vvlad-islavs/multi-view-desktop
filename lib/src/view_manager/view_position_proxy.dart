import 'dart:async';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/lifecycle/view_animator.dart';
import 'package:multiview_desktop/src/utils/calc_window_position.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewPositionProxy extends ViewNativeProxy {
  ViewPositionProxy(
    super.host, {
    required ViewAnimator animator,
    required ViewGeometryAnimationPolicy geometryAnimation,
  })  : _animator = animator,
        _geometryAnimation = geometryAnimation;

  final ViewAnimator _animator;
  final ViewGeometryAnimationPolicy _geometryAnimation;

  final Map<int, int> _geometryGeneration = {};

  Rect getBounds(int viewId) => call(viewId, () => ffi.getBounds(viewId), dialogSupports: true) ?? Rect.zero;

  Size getSize(int viewId) => call(viewId, () => ffi.getSize(viewId), dialogSupports: true) ?? Size.zero;

  Offset getPosition(int viewId) =>
      call(viewId, () => ffi.getPosition(viewId), dialogSupports: true) ?? Offset.zero;

  void setSize(int viewId, Size size) {
    _applyFrame(
      viewId,
      (current) => Rect.fromLTWH(current.left, current.top, size.width, size.height),
    );
  }

  void setPosition(int viewId, Offset position) {
    _applyFrame(
      viewId,
      (current) => Rect.fromLTWH(position.dx, position.dy, current.width, current.height),
    );
  }

  void setMinimumSize(int viewId, Size size) {
    call(viewId, () => ffi.setMinSize(viewId, size: size), dialogSupports: true);
  }

  void setMaximumSize(int viewId, Size size) {
    call(viewId, () => ffi.setMaxSize(viewId, size: size), dialogSupports: true);
  }

  void setAspectRatio(int viewId, double ratio) {
    call(viewId, () => ffi.setAspectRatio(viewId, ratio));
  }

  void center(int viewId) => setAlignment(viewId, Alignment.center);

  void setAlignment(int viewId, Alignment alignment, {bool insideParent = false}) {
    if (host.isDialog(viewId) && insideParent) {
      final parentId = host.dialogParentId(viewId);
      if (parentId == null) return;
      final current = getBounds(viewId);
      if (current == Rect.zero) return;
      final parentBounds = ffi.getBounds(parentId);
      final pos = calcWindowPositionByParent(
        alignment,
        windowSize: current.size,
        parentBounds: parentBounds,
      );
      _applyFrame(
        viewId,
        (_) => Rect.fromLTWH(pos.dx, pos.dy, current.width, current.height),
      );
      return;
    }

    if (host.isModalDialog(viewId)) {
      call(
        viewId,
        () => ffi.setAlignment(viewId, alignment: alignment),
        dialogSupports: false,
      );
      return;
    }

    final current = getBounds(viewId);
    if (current == Rect.zero) return;
    final pos = calcWindowPosition(current.size, alignment);
    _applyFrame(
      viewId,
      (_) => Rect.fromLTWH(pos.dx, pos.dy, current.width, current.height),
    );
  }

  bool positionPopup(int viewId, Rect bounds) {
    if (!host.isPopup(viewId)) return false;
    if (!_geometryAnimation.enabled) {
      return call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;
    }

    final current = getBounds(viewId);
    if (current == Rect.zero) {
      return call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;
    }

    unawaited(_animateFrame(viewId, current, bounds, dialogSupports: true));
    return true;
  }

  void _applyFrame(int viewId, Rect Function(Rect current) targetFor, {bool dialogSupports = true}) {
    final current = getBounds(viewId);
    if (current == Rect.zero) return;

    final target = targetFor(current);
    if (!_geometryAnimation.enabled || _framesEqual(current, target)) {
      call(viewId, () => ffi.setFrame(viewId, target), dialogSupports: dialogSupports);
      return;
    }

    unawaited(_animateFrame(viewId, current, target, dialogSupports: dialogSupports));
  }

  Future<void> _animateFrame(
    int viewId,
    Rect from,
    Rect to, {
    required bool dialogSupports,
  }) async {
    final generation = (_geometryGeneration[viewId] ?? 0) + 1;
    _geometryGeneration[viewId] = generation;

    await _animator.animate(
      from: 0,
      to: 1,
      duration: _geometryAnimation.duration,
      curve: _geometryAnimation.curve,
      fps: _geometryAnimation.fps,
      onValue: (t) {
        if (_geometryGeneration[viewId] != generation) return;
        ffi.setFrame(viewId, Rect.lerp(from, to, t)!);
      },
    );

    if (_geometryGeneration[viewId] != generation) return;
    call(viewId, () => ffi.setFrame(viewId, to), dialogSupports: dialogSupports);
  }

  bool _framesEqual(Rect a, Rect b) {
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }
}
