import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Generic stepped animation runner for native view properties.
///
/// Pass [onValue] to apply each tick (opacity, bounds, etc.). Timing params
/// stay on [animate]; the applier stays caller-specific.
@internal
class ViewAnimator {
  const ViewAnimator();

  /// Interpolates from [from] to [to] over [duration] and invokes [onValue] each tick.
  Future<void> animate({
    required void Function(double value) onValue,
    double from = 0.0,
    double to = 1.0,
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
    int fps = 60,
  }) async {
    final completer = Completer<void>();
    onValue(from);
    final totalMs = duration.inMilliseconds.clamp(1, 60000);
    final tickMs = math.max(1, (1000 / fps).round());
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
}
