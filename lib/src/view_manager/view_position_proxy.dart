import 'dart:async';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/lifecycle/view_animator.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewPositionProxy extends ViewNativeProxy {
  ViewPositionProxy(
    super.host, {
    required ViewAnimator animator,
    required ViewGeometryAnimationPolicy geometryAnimation,
    WindowPositionCalculator? positionCalculator,
  })  : _animator = animator,
        _geometryAnimation = geometryAnimation,
        _positionCalculator = positionCalculator ?? WindowPositionCalculator.instance;

  final ViewAnimator _animator;
  final ViewGeometryAnimationPolicy _geometryAnimation;
  final WindowPositionCalculator _positionCalculator;

  final Map<int, int> _geometryGeneration = {};

  Rect getBounds(int viewId) => call(viewId, () => ffi.getBounds(viewId), dialogSupports: true) ?? Rect.zero;

  Size getSize(int viewId) => call(viewId, () => ffi.getSize(viewId), dialogSupports: true) ?? Size.zero;

  Offset getPosition(int viewId) =>
      call(viewId, () => ffi.getPosition(viewId), dialogSupports: true) ?? Offset.zero;

  Future<void> setSize(int viewId, Size size) {
    return _applyFrame(
      viewId,
      (current) => Rect.fromLTWH(current.left, current.top, size.width, size.height),
    );
  }

  Future<void> setPosition(int viewId, Offset position) {
    return _applyFrame(
      viewId,
      (current) => Rect.fromLTWH(position.dx, position.dy, current.width, current.height),
    );
  }

  Future<void> setMinimumSize(int viewId, Size size) async {
    call(viewId, () => ffi.setMinSize(viewId, size: size), dialogSupports: true);
  }

  Future<void> setMaximumSize(int viewId, Size size) async {
    call(viewId, () => ffi.setMaxSize(viewId, size: size), dialogSupports: true);
  }

  Future<void> setAspectRatio(int viewId, double ratio) async {
    call(viewId, () => ffi.setAspectRatio(viewId, ratio));
  }

  Future<void> center(int viewId) => setAlignment(viewId, Alignment.center);

  Future<void> setAlignment(int viewId, Alignment alignment, {bool insideParent = false}) async {
    if (host.isDialog(viewId) && insideParent) {
      final parentId = host.dialogParentId(viewId);
      if (parentId == null) return;
      final current = getBounds(viewId);
      if (current == Rect.zero) return;
      final parentBounds = ffi.getBounds(parentId);
      final pos = _positionCalculator.calcWindowPositionByParent(
        alignment,
        windowSize: current.size,
        parentBounds: parentBounds,
      );
      await _applyFrame(
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
    final pos = _positionCalculator.calcWindowPosition(current.size, alignment);
    await _applyFrame(
      viewId,
      (_) => Rect.fromLTWH(pos.dx, pos.dy, current.width, current.height),
    );
  }

  Future<bool> positionPopup(int viewId, Rect bounds) async {
    if (!host.isPopup(viewId)) return false;
    if (!_geometryAnimation.enabled) {
      return call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;
    }

    final current = getBounds(viewId);
    if (current == Rect.zero) {
      return call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;
    }

    await _animateFrame(viewId, current, bounds, dialogSupports: true);
    return true;
  }

  Future<void> _applyFrame(int viewId, Rect Function(Rect current) targetFor, {bool dialogSupports = true}) async {
    final current = getBounds(viewId);
    if (current == Rect.zero) return;

    final target = targetFor(current);
    if (!_geometryAnimation.enabled || _framesEqual(current, target)) {
      call(viewId, () => ffi.setFrame(viewId, target), dialogSupports: dialogSupports);
      return;
    }

    await _animateFrame(viewId, current, target, dialogSupports: dialogSupports);
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
