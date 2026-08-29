import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Generic stepped animation runner for native view properties.
///
/// Pass [onValue] to apply each tick (opacity, bounds, etc.). Timing params
/// stay on [animate]; the applier stays caller-specific.
///
/// When [fps] is null, [onValue] runs once per completed display frame
/// ([SchedulerBinding.endOfFrame]) — tied to actual frame boundaries.
///
/// When [fps] is set, [Timer.periodic] drives ticks at that fixed rate.
@internal
class ViewAnimator {
  ViewAnimator();

  /// Interpolates from [from] to [to] over [duration] and invokes [onValue] each tick.
  Future<void> animate({
    required void Function(double value) onValue,
    double from = 0.0,
    double to = 1.0,
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
    int? fps,
  }) {
    if (fps != null) {
      return _animateWithTimer(
        onValue: onValue,
        from: from,
        to: to,
        duration: duration,
        curve: curve,
        fps: fps,
      );
    }
    return _animatePerDisplayFrame(
      onValue: onValue,
      from: from,
      to: to,
      duration: duration,
      curve: curve,
    );
  }

  Future<void> _animateWithTimer({
    required void Function(double value) onValue,
    required double from,
    required double to,
    required Duration duration,
    required Curve curve,
    required int fps,
  }) async {
    final completer = Completer<void>();
    onValue(from);
    final totalMs = duration.inMilliseconds.clamp(1, 60000);
    final tickMs = math.max(1, (1000 / fps.clamp(1, 1000)).round());
    final start = DateTime.now();
    Timer? timer;
    timer = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final progress = (elapsed / totalMs).clamp(0.0, 1.0);
      final eased = curve.transform(progress);
      onValue(from + (to - from) * eased);
      if (progress >= 1.0) {
        timer?.cancel();
        onValue(to);
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> _animatePerDisplayFrame({
    required void Function(double value) onValue,
    required double from,
    required double to,
    required Duration duration,
    required Curve curve,
  }) async {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
    }

    final completer = Completer<void>();
    final totalMicros = duration.inMicroseconds.clamp(1, 60000000);
    Duration? startFrameTime;
    final wallStart = Stopwatch()..start();

    onValue(from);

    int elapsedMicros(Duration? frameTime) {
      if (frameTime != null) {
        startFrameTime ??= frameTime;
        return (frameTime - startFrameTime!).inMicroseconds;
      }
      return wallStart.elapsedMicroseconds;
    }

    void scheduleNextFrame() {
      binding.scheduleFrame();
      binding.endOfFrame.then((_) {
        if (completer.isCompleted) return;

        final progress = (elapsedMicros(binding.currentSystemFrameTimeStamp) / totalMicros).clamp(0.0, 1.0);
        final eased = curve.transform(progress);
        onValue(from + (to - from) * eased);

        if (progress >= 1.0) {
          onValue(to);
          if (!completer.isCompleted) completer.complete();
          return;
        }

        scheduleNextFrame();
      });
    }

    scheduleNextFrame();
    await completer.future;
  }
}
