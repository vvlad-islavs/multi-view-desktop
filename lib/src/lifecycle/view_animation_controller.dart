import 'package:flutter/animation.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';
import 'package:multiview_desktop/src/lifecycle/view_animator.dart';
import 'package:multiview_desktop/src/lifecycle/view_animation_override.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

/// Native view animations. Uses [ViewAnimator] for ticks.
///
/// Owns the per-view override map ([stageForceOverride]). Each animate* method
/// consumes a matching staged override (same [viewId] + [ViewAnimationType]),
/// merges it over method/policy defaults, and applies native updates via proxies.
@internal
class ViewAnimationController {
  ViewAnimationController({required ViewAnimationConfig config, ViewAnimator? animator})
    : _config = config,
      _animator = animator ?? ViewAnimator();

  final ViewAnimationConfig _config;
  final ViewAnimator _animator;

  @internal
  ViewManagerProxies get proxies {
    if (_proxies == null) {
      throw Exception('proxies is not binded');
    }
    return _proxies!;
  }

  @internal
  set proxies(ViewManagerProxies v) {
    _proxies = v;
  }

  ViewManagerProxies? _proxies;

  final Map<int, ViewAnimationOverride> _pendingForceOverrides = {};
  final Map<int, ViewAnimationOverride> _pendingSoftOverrides = {};

  void bindProxies(ViewManagerProxies proxies) => this.proxies = proxies;

  /// Drops unused one-shot overrides for [viewId] (e.g. popup destroyed before show).
  void clearOverrides(int viewId) {
    _pendingForceOverrides.remove(viewId);
    _pendingSoftOverrides.remove(viewId);
  }

  /// Stages a one-shot force override. Runs the next matching animation even if
  /// that type is disabled in config. Timing wins over soft overrides.
  void stageForceOverride(int viewId, ViewAnimationType type, AnimationSettings? settings) {
    if (settings == null || settings.isEmpty) return;
    MvdLog.instance.info('animation', 'stageForceOverride', {'realId': viewId, 'type': type.name});
    _pendingForceOverrides[viewId] = ViewAnimationOverride(type: type, settings: settings);
  }

  /// Stages a one-shot soft override. Applied only when [type] is enabled in config.
  void stageSoftOverride(int viewId, ViewAnimationType type, AnimationSettings? settings) {
    if (settings == null || settings.isEmpty) return;
    if (!_isStagingAllowed(type)) return;
    MvdLog.instance.info('animation', 'stageSoftOverride', {'realId': viewId, 'type': type.name});
    _pendingSoftOverrides[viewId] = ViewAnimationOverride(type: type, settings: settings);
  }

  bool _isStagingAllowed(ViewAnimationType type) {
    switch (type) {
      case ViewAnimationType.setSize:
      case ViewAnimationType.setPosition:
      case ViewAnimationType.setAlignment:
      case ViewAnimationType.positionPopup:
        return _config.geometry.enabled;
      case ViewAnimationType.createWindow:
        return _config.windowOpenClose.fadeInOnOpen;
      case ViewAnimationType.closeWindow:
        return _config.windowOpenClose.fadeOutOnClose;
      case ViewAnimationType.createDialog:
        return _config.modelessDialogOpenClose.fadeInOnOpen;
      case ViewAnimationType.closeDialog:
        return _config.modelessDialogOpenClose.fadeOutOnClose;
      case ViewAnimationType.createPopup:
        return _config.popupOpenClose.fadeInOnOpen;
      case ViewAnimationType.closePopup:
        return _config.popupOpenClose.fadeOutOnClose;
    }
  }

  AnimationSettings? _takeForceOverride(int viewId, ViewAnimationType type) {
    if (type == ViewAnimationType.createPopup || type == ViewAnimationType.closePopup) {
      return null;
    }
    final pending = _pendingForceOverrides[viewId];
    if (pending == null || pending.type != type) return null;
    _pendingForceOverrides.remove(viewId);
    return pending.settings;
  }

  AnimationSettings? _takeSoftOverride(int viewId, ViewAnimationType type) {
    final pending = _pendingSoftOverrides[viewId];
    if (pending == null || pending.type != type) return null;
    _pendingSoftOverrides.remove(viewId);
    return pending.settings;
  }

  /// Open fade `0 → 1`, or [show] only when open fade is disabled in [policy].
  Future<void> animateOpen(
    int viewId, {
    required ViewAnimationType type,
    required ViewOpenCloseAnimationPolicy policy,
  }) async {
    final proxies = this.proxies;
    final forceOverride = _takeForceOverride(viewId, type);

    MvdLog.instance.info('animation', 'animateOpen', {
      'realId': viewId,
      'type': type.name,
      'fadeInOnOpen': policy.fadeInOnOpen,
      'hasForceOverride': forceOverride != null,
    });

    if (!policy.fadeInOnOpen && forceOverride == null) {
      proxies.state.show(viewId);
      return;
    }

    final softOverride = _takeSoftOverride(viewId, type);

    proxies.appearance.setOpacity(viewId, 0);
    proxies.state.show(viewId);

    await _animator.animate(
      onValue: (value) => proxies.appearance.setOpacity(viewId, value),
      from: 0,
      to: 1,
      duration: forceOverride?.duration ?? softOverride?.duration ?? policy.openDuration,
      curve: forceOverride?.curve ?? softOverride?.curve ?? policy.curve,
      fps: forceOverride?.fps ?? softOverride?.fps ?? policy.fps,
    );
  }

  /// Close fade `1 → 0` when [policy.fadeOutOnClose] is enabled.
  Future<void> animateClose(
    int viewId, {
    required ViewAnimationType type,
    required ViewOpenCloseAnimationPolicy policy,
  }) async {
    final override = _takeForceOverride(viewId, type);
    MvdLog.instance.info('animation', 'animateClose', {
      'realId': viewId,
      'type': type.name,
      'fadeOutOnClose': policy.fadeOutOnClose,
      'hasForceOverride': override != null,
    });
    if (!policy.fadeOutOnClose && override == null) return;

    final softOverride = _takeSoftOverride(viewId, type);
    await _animator.animate(
      onValue: (value) => proxies.appearance.setOpacity(viewId, value),
      from: 1,
      to: 0,
      duration: override?.duration ?? softOverride?.duration ?? policy.closeDuration,
      curve: override?.curve ?? softOverride?.curve ?? policy.curve,
      fps: override?.fps ?? softOverride?.fps ?? policy.fps,
    );
  }

  /// Animates frame bounds or sets [to] immediately when geometry animation is off.
  Future<void> applyAnimatedFrame(
    int viewId,
    ViewAnimationType type,
    Rect from,
    Rect to, {
    bool dialogSupports = true,
    bool Function()? isCurrent,
  }) async {
    final position = proxies.position;
    final geo = _config.geometry;
    final forceOverride = _takeForceOverride(viewId, type);

    if ((!geo.enabled && forceOverride == null) || _framesEqual(from, to)) {
      _takeSoftOverride(viewId, type);
      position.setFrameBounds(viewId, to, dialogSupports: dialogSupports);
      return;
    }
    final softOverride = _takeSoftOverride(viewId, type);

    await _animator.animate(
      from: 0,
      to: 1,
      duration: forceOverride?.duration ?? softOverride?.duration ?? geo.duration,
      curve: forceOverride?.curve ?? softOverride?.curve ?? geo.curve,
      fps: forceOverride?.fps ?? softOverride?.fps ?? geo.fps,
      onValue: (t) {
        if (isCurrent != null && !isCurrent()) return;
        position.setFrameBounds(viewId, Rect.lerp(from, to, t)!, dialogSupports: dialogSupports);
      },
    );

    if (isCurrent != null && !isCurrent()) return;
    position.setFrameBounds(viewId, to, dialogSupports: dialogSupports);
  }

  /// Animates popup bounds or sets [to] immediately when geometry animation is off.
  Future<void> applyAnimatedPopupBounds(int viewId, Rect from, Rect to, {bool Function()? isCurrent}) async {
    final position = proxies.position;
    final geo = _config.geometry;
    final type = ViewAnimationType.positionPopup;
    final forceOverride = _takeForceOverride(viewId, type);

    if ((!geo.enabled && forceOverride == null) || _framesEqual(from, to)) {
      _takeSoftOverride(viewId, type);
      position.setPopupBounds(viewId, to);
      return;
    }

    final softOverride = _takeSoftOverride(viewId, type);

    await _animator.animate(
      from: 0,
      to: 1,
      duration: forceOverride?.duration ?? softOverride?.duration ?? geo.duration,
      curve: forceOverride?.curve ?? softOverride?.curve ?? geo.curve,
      fps: forceOverride?.fps ?? softOverride?.fps ?? geo.fps,
      onValue: (t) {
        if (isCurrent != null && !isCurrent()) return;
        position.setPopupBounds(viewId, Rect.lerp(from, to, t)!);
      },
    );

    if (isCurrent != null && !isCurrent()) return;
    position.setPopupBounds(viewId, to);
  }

  bool _framesEqual(Rect a, Rect b) {
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }
}
