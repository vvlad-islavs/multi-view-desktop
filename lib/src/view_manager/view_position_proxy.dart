import 'dart:async';

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/lifecycle/view_animation_controller.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewPositionProxy extends ViewNativeProxy {
  ViewPositionProxy(
    super.host, {
    required ViewAnimationController animationController,
    WindowPositionCalculator? positionCalculator,
  }) : _animation = animationController,
       _positionCalculator = positionCalculator ?? WindowPositionCalculator.instance;

  final ViewAnimationController _animation;
  final WindowPositionCalculator _positionCalculator;

  final Map<int, int> _geometryGeneration = {};

  Rect? getDisplayRect(Rect query) => ffi.getDisplayRect(query) ;

  Rect getBounds(int viewId) => call(viewId, () => ffi.getBounds(viewId), dialogSupports: true) ?? Rect.zero;

  Size getSize(int viewId) => call(viewId, () => ffi.getSize(viewId), dialogSupports: true) ?? Size.zero;

  Offset getPosition(int viewId) => call(viewId, () => ffi.getPosition(viewId), dialogSupports: true) ?? Offset.zero;

  void setFrameBounds(int viewId, Rect rect, {bool dialogSupports = true}) {
    call(viewId, () => ffi.setFrame(viewId, rect), dialogSupports: dialogSupports);
  }

  bool setPopupBounds(int viewId, Rect bounds) =>
      call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;

  Future<void> setSize(int viewId, Size size, {AnimationSettings? animation}) {
    _animation.stageSoftOverride(viewId, ViewAnimationType.setSize, animation);
    return _applyFrame(viewId, ViewAnimationType.setSize, (current) {
      return Rect.fromLTWH(current.left, current.top, size.width, size.height);
    });
  }

  Future<void> setPosition(int viewId, Offset position, {AnimationSettings? animation}) {
    _animation.stageSoftOverride(viewId, ViewAnimationType.setPosition, animation);
    return _applyFrame(viewId, ViewAnimationType.setPosition, (current) {
      return Rect.fromLTWH(position.dx, position.dy, current.width, current.height);
    });
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

  Future<void> center(int viewId, {AnimationSettings? animation}) =>
      setAlignment(viewId, Alignment.center, animation: animation);

  Future<void> setAlignment(
    int viewId,
    Alignment alignment, {
    bool insideParent = false,
    AnimationSettings? animation,
  }) async {
    _animation.stageSoftOverride(viewId, ViewAnimationType.setAlignment, animation);

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
        ViewAnimationType.setAlignment,
        (_) => Rect.fromLTWH(pos.dx, pos.dy, current.width, current.height),
      );
      return;
    }

    if (host.isModalDialog(viewId)) {
      call(viewId, () => ffi.setAlignment(viewId, alignment: alignment), dialogSupports: false);
      return;
    }

    final current = getBounds(viewId);
    if (current == Rect.zero) return;
    final pos = _positionCalculator.calcWindowPosition(current.size, alignment);
    await _applyFrame(
      viewId,
      ViewAnimationType.setAlignment,
      (_) => Rect.fromLTWH(pos.dx, pos.dy, current.width, current.height),
    );
  }

  Future<bool> positionPopup(int viewId, Rect bounds, {AnimationSettings? animation}) async {
    if (!host.isPopup(viewId)) return false;

    _animation.stageSoftOverride(viewId, ViewAnimationType.positionPopup, animation);

    final current = getBounds(viewId);
    if (current == Rect.zero) {
      return setPopupBounds(viewId, bounds);
    }

    final generation = (_geometryGeneration[viewId] ?? 0) + 1;
    _geometryGeneration[viewId] = generation;

    await _animation.applyAnimatedPopupBounds(
      viewId,
      current,
      bounds,
      isCurrent: () => _geometryGeneration[viewId] == generation,
    );

    return true;
  }

  Future<void> _applyFrame(
    int viewId,
    ViewAnimationType type,
    Rect Function(Rect current) targetFor, {
    bool dialogSupports = true,
  }) async {
    final current = getBounds(viewId);
    if (current == Rect.zero) return;

    final target = targetFor(current);
    final generation = (_geometryGeneration[viewId] ?? 0) + 1;
    _geometryGeneration[viewId] = generation;

    await _animation.applyAnimatedFrame(
      viewId,
      type,
      current,
      target,
      dialogSupports: dialogSupports,
      isCurrent: () => _geometryGeneration[viewId] == generation,
    );
  }
}
