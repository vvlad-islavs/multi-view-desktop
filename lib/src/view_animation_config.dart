import 'package:flutter/animation.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Application-wide native view animation policy.
///
/// Configure via [MultiPlatformParams.animation] in `runMultiApp`.
///
/// Use [ViewAnimationConfig.openClose], [ViewAnimationConfig.geometry], or
/// [ViewAnimationConfig.all] — each factory owns its parameters.
///
/// When [fps] is null, ticks use [SchedulerBinding] (display refresh).
/// When [fps] is set, a fixed-rate timer is used instead.
class ViewAnimationConfig {
  const ViewAnimationConfig._({
    required this.windowOpenClose,
    required this.modelessDialogOpenClose,
    required this.modalDialogOpenClose,
    required this.geometry,
  });

  /// Open/close fade for windows and modeless dialogs; geometry off.
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
    geometry: ViewGeometryAnimationPolicy.disabled,
  );

  /// Everything off.
  static const disabled = ViewAnimationConfig._(
    windowOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    modelessDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    modalDialogOpenClose: ViewOpenCloseAnimationPolicy.disabled,
    geometry: ViewGeometryAnimationPolicy.disabled,
  );

  final ViewOpenCloseAnimationPolicy windowOpenClose;
  final ViewOpenCloseAnimationPolicy modelessDialogOpenClose;
  final ViewOpenCloseAnimationPolicy modalDialogOpenClose;
  final ViewGeometryAnimationPolicy geometry;

  /// Open/close fade only (windows, modeless dialogs; modal off by default).
  factory ViewAnimationConfig.openClose({
    int? fps,
    Curve curve = Curves.easeIn,
    Duration windowOpenDuration = const Duration(milliseconds: 150),
    Duration windowCloseDuration = const Duration(milliseconds: 150),
    Duration modelessOpenDuration = const Duration(milliseconds: 150),
    Duration modelessCloseDuration = const Duration(milliseconds: 150),
    bool windowFadeInOnOpen = true,
    bool windowFadeOutOnClose = true,
    bool modelessFadeInOnOpen = true,
    bool modelessFadeOutOnClose = true,
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
    Duration windowOpenDuration = const Duration(milliseconds: 150),
    Duration windowCloseDuration = const Duration(milliseconds: 150),
    Duration modelessOpenDuration = const Duration(milliseconds: 150),
    Duration modelessCloseDuration = const Duration(milliseconds: 150),
    bool windowFadeInOnOpen = true,
    bool windowFadeOutOnClose = true,
    bool modelessFadeInOnOpen = true,
    bool modelessFadeOutOnClose = true,
    bool modalFadeInOnOpen = false,
    bool modalFadeOutOnClose = false,
    Duration modalOpenDuration = const Duration(milliseconds: 150),
    Duration modalCloseDuration = const Duration(milliseconds: 150),
    Duration geometryDuration = const Duration(milliseconds: 250),
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
