import 'package:flutter/animation.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Per-call timing overrides for a single native view animation.
///
/// Soft: pass as `animation:` on `openWindow`, `setSize`, `closeWindow`,
/// popup `open` / `close`, etc.
/// Applied only when that animation type is already enabled in [ViewAnimationConfig].
///
/// Force: pass via [MultiViewDesktop.setForceAnimation] — runs once even if the
/// type is disabled in config. Force timing wins over soft when both are staged.
/// Not used for popups (no public view id).
class AnimationSettings {
  const AnimationSettings({
    this.duration,
    this.curve,
    this.fps,
  });

  final Duration? duration;
  final Curve? curve;
  final int? fps;

  bool get isEmpty => duration == null && curve == null && fps == null;
}

/// Identifies which operation the next staged animation override applies to.
///
/// Open/close fade is part of [createWindow], [createDialog], [createPopup],
/// [closeWindow], [closeDialog], and [closePopup] — not separate animation types.
enum ViewAnimationType {
  setSize,
  setPosition,
  setAlignment,
  positionPopup,
  createWindow,
  createDialog,
  createPopup,
  closeWindow,
  closeDialog,
  closePopup,
}

/// Application-wide native view animation policy.
///
/// Configure via [MultiPlatformParams.animation] in `runMultiApp`.
///
/// Use [ViewAnimationConfig.openClose], [ViewAnimationConfig.geometry], or
/// [ViewAnimationConfig.all] — each factory owns its parameters.
///
/// When [fps] is null, ticks follow completed display frames (one [onValue] per
/// [SchedulerBinding.endOfFrame]). When [fps] is set, [Timer.periodic] drives ticks.
class ViewAnimationConfig {
  const ViewAnimationConfig._({
    required this.windowOpenClose,
    required this.modelessDialogOpenClose,
    required this.modalDialogOpenClose,
    required this.popupOpenClose,
    required this.geometry,
  });

  /// Open/close fade for windows, modeless dialogs, and popups; geometry off.
  static const defaults = ViewAnimationConfig._(
    windowOpenClose: ViewOpenCloseAnimationPolicy(
      fadeInOnOpen: true,
      fadeOutOnClose: true,
      openDuration: Duration(milliseconds: 150),
      closeDuration: Duration(milliseconds: 150),
    ),
    modelessDialogOpenClose: ViewOpenCloseAnimationPolicy(
      fadeInOnOpen: true,
      fadeOutOnClose: true,
      openDuration: Duration(milliseconds: 150),
      closeDuration: Duration(milliseconds: 150),
    ),
    modalDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    popupOpenClose: ViewOpenCloseAnimationPolicy(
      fadeInOnOpen: true,
      fadeOutOnClose: true,
      openDuration: Duration(milliseconds: 150),
      closeDuration: Duration(milliseconds: 150),
    ),
    geometry: ViewGeometryAnimationPolicy.disabled,
  );

  /// Everything off.
  static const disabled = ViewAnimationConfig._(
    windowOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    modelessDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    modalDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    popupOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    geometry: ViewGeometryAnimationPolicy.disabled,
  );

  final ViewOpenCloseAnimationPolicy windowOpenClose;
  final ViewOpenCloseAnimationPolicy modelessDialogOpenClose;
  final ViewOpenCloseAnimationPolicy modalDialogOpenClose;
  final ViewOpenCloseAnimationPolicy popupOpenClose;
  final ViewGeometryAnimationPolicy geometry;

  /// Open/close fade only (windows, modeless dialogs, popups; modal off by default).
  factory ViewAnimationConfig.openClose({
    int? fps,
    Curve curve = Curves.easeIn,
    Duration windowOpenDuration = const Duration(milliseconds: 150),
    Duration windowCloseDuration = const Duration(milliseconds: 150),
    Duration modelessOpenDuration = const Duration(milliseconds: 150),
    Duration modelessCloseDuration = const Duration(milliseconds: 150),
    Duration popupOpenDuration = const Duration(milliseconds: 150),
    Duration popupCloseDuration = const Duration(milliseconds: 150),
    bool windowFadeInOnOpen = true,
    bool windowFadeOutOnClose = true,
    bool modelessFadeInOnOpen = true,
    bool modelessFadeOutOnClose = true,
    bool popupFadeInOnOpen = true,
    bool popupFadeOutOnClose = true,
    bool modalFadeInOnOpen = false,
    bool modalFadeOutOnClose = false,
    Duration modalOpenDuration = const Duration(milliseconds: 150),
    Duration modalCloseDuration = const Duration(milliseconds: 150),
  }) {
    return ViewAnimationConfig._(
      windowOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: windowFadeInOnOpen,
        fadeOutOnClose: windowFadeOutOnClose,
        openDuration: windowOpenDuration,
        closeDuration: windowCloseDuration,
        curve: curve,
        fps: fps,
      ),
      modelessDialogOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: modelessFadeInOnOpen,
        fadeOutOnClose: modelessFadeOutOnClose,
        openDuration: modelessOpenDuration,
        closeDuration: modelessCloseDuration,
        curve: curve,
        fps: fps,
      ),
      modalDialogOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: modalFadeInOnOpen,
        fadeOutOnClose: modalFadeOutOnClose,
        openDuration: modalOpenDuration,
        closeDuration: modalCloseDuration,
        curve: curve,
        fps: fps,
      ),
      popupOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: popupFadeInOnOpen,
        fadeOutOnClose: popupFadeOutOnClose,
        openDuration: popupOpenDuration,
        closeDuration: popupCloseDuration,
        curve: curve,
        fps: fps,
      ),
      geometry: ViewGeometryAnimationPolicy.disabled,
    );
  }

  /// Position/size animation only (`setSize`, `setPosition`, …).
  factory ViewAnimationConfig.geometry({
    int? fps,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return ViewAnimationConfig._(
      windowOpenClose: ViewOpenCloseAnimationPolicy.disabled,
      modelessDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
      modalDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
      popupOpenClose: ViewOpenCloseAnimationPolicy.disabled,
      geometry: ViewGeometryAnimationPolicy(
        enabled: true,
        duration: duration,
        curve: curve,
        fps: fps,
      ),
    );
  }

  /// Open/close fade and geometry animation together.
  factory ViewAnimationConfig.all({
    int? fps,
    Curve openCloseCurve = Curves.easeIn,
    Duration windowOpenDuration = const Duration(milliseconds: 50),
    Duration windowCloseDuration = const Duration(milliseconds: 50),
    Duration modelessOpenDuration = const Duration(milliseconds: 150),
    Duration modelessCloseDuration = const Duration(milliseconds: 150),
    Duration popupOpenDuration = const Duration(milliseconds: 150),
    Duration popupCloseDuration = const Duration(milliseconds: 150),
    bool windowFadeInOnOpen = true,
    bool windowFadeOutOnClose = true,
    bool modelessFadeInOnOpen = true,
    bool modelessFadeOutOnClose = true,
    bool popupFadeInOnOpen = true,
    bool popupFadeOutOnClose = true,
    bool modalFadeInOnOpen = false,
    bool modalFadeOutOnClose = false,
    Duration modalOpenDuration = const Duration(milliseconds: 150),
    Duration modalCloseDuration = const Duration(milliseconds: 150),
    Duration geometryDuration = const Duration(milliseconds: 50),
    Curve geometryCurve = Curves.easeInOut,
  }) {
    return ViewAnimationConfig._(
      windowOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: windowFadeInOnOpen,
        fadeOutOnClose: windowFadeOutOnClose,
        openDuration: windowOpenDuration,
        closeDuration: windowCloseDuration,
        curve: openCloseCurve,
        fps: fps,
      ),
      modelessDialogOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: modelessFadeInOnOpen,
        fadeOutOnClose: modelessFadeOutOnClose,
        openDuration: modelessOpenDuration,
        closeDuration: modelessCloseDuration,
        curve: openCloseCurve,
        fps: fps,
      ),
      modalDialogOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: modalFadeInOnOpen,
        fadeOutOnClose: modalFadeOutOnClose,
        openDuration: modalOpenDuration,
        closeDuration: modalCloseDuration,
        curve: openCloseCurve,
        fps: fps,
      ),
      popupOpenClose: ViewOpenCloseAnimationPolicy(
        fadeInOnOpen: popupFadeInOnOpen,
        fadeOutOnClose: popupFadeOutOnClose,
        openDuration: popupOpenDuration,
        closeDuration: popupCloseDuration,
        curve: openCloseCurve,
        fps: fps,
      ),
      geometry: ViewGeometryAnimationPolicy(
        enabled: true,
        duration: geometryDuration,
        curve: geometryCurve,
        fps: fps,
      ),
    );
  }
}

/// Resolved open/close fade parameters (internal).
@internal
class ViewOpenCloseAnimationPolicy {
  const ViewOpenCloseAnimationPolicy({
    this.fadeInOnOpen = false,
    this.fadeOutOnClose = false,
    this.openDuration = const Duration(milliseconds: 150),
    this.closeDuration = const Duration(milliseconds: 150),
    this.curve = Curves.easeIn,
    this.fps,
  });

  static const disabled = ViewOpenCloseAnimationPolicy();

  final bool fadeInOnOpen;
  final bool fadeOutOnClose;
  final Duration openDuration;
  final Duration closeDuration;
  final Curve curve;
  final int? fps;
}

/// Resolved geometry animation parameters (internal).
@internal
class ViewGeometryAnimationPolicy {
  const ViewGeometryAnimationPolicy({
    this.enabled = false,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeInOut,
    this.fps,
  });

  static const disabled = ViewGeometryAnimationPolicy();

  final bool enabled;
  final Duration duration;
  final Curve curve;
  final int? fps;
}
