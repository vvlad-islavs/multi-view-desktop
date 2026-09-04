import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'display.dart';

/// Picks a [Display] from mixed hints.
///
/// DPI / scaleFactor alone cannot tell two similar monitors apart. Scores
/// combine physical overlap (strongest), DPI closeness, panel diagonal, then
/// logical overlap (weakest, because mixed-DPI logical space can overlap).
@internal
class DisplayMatcher {
  const DisplayMatcher._();

  static Display pick({
    required List<Display> displays,
    required Display fallback,
    Offset? physicalPoint,
    Rect? physicalRect,
    Offset? logicalPoint,
    Rect? logicalBounds,
    num? dpi,
    double? diagonalMm,
  }) {
    if (displays.isEmpty) return fallback;

    Display? best;
    var bestScore = -1.0;
    for (final display in displays) {
      final score = scoreOf(
        display,
        physicalPoint: physicalPoint,
        physicalRect: physicalRect,
        logicalPoint: logicalPoint,
        logicalBounds: logicalBounds,
        dpi: dpi,
        diagonalMm: diagonalMm,
      );
      if (score > bestScore) {
        bestScore = score;
        best = display;
      }
    }
    return best ?? fallback;
  }

  @visibleForTesting
  static double scoreOf(
    Display display, {
    Offset? physicalPoint,
    Rect? physicalRect,
    Offset? logicalPoint,
    Rect? logicalBounds,
    num? dpi,
    double? diagonalMm,
  }) {
    var score = 0.0;

    final physical = display.physicalBounds;
    if (physical != null) {
      if (physicalRect != null && physicalRect.width > 0 && physicalRect.height > 0) {
        score += 100 * _overlapRatio(physicalRect, physical);
      }
      if (physicalPoint != null) {
        score += physical.contains(physicalPoint) ? 80 : _nearness(physical, physicalPoint, 40);
      }
    }

    if (dpi != null && display.dpi != null && display.dpi! > 0 && dpi > 0) {
      final maxDpi = display.dpi! > dpi ? display.dpi! : dpi;
      final closeness = (1 - ((display.dpi! - dpi).abs() / maxDpi)).clamp(0, 1);
      score += 20 * closeness;
    }

    final displayDiag = display.diagonalMm;
    if (diagonalMm != null && displayDiag != null && displayDiag > 0 && diagonalMm > 0) {
      final maxDiag = displayDiag > diagonalMm ? displayDiag : diagonalMm;
      final closeness = (1 - ((displayDiag - diagonalMm).abs() / maxDiag)).clamp(0, 1);
      score += 25 * closeness;
    }

    if (logicalBounds != null && logicalBounds.width > 0 && logicalBounds.height > 0) {
      score += 35 * _overlapRatio(logicalBounds, display.logicalBounds);
    }
    if (logicalPoint != null) {
      score += display.logicalBounds.contains(logicalPoint) ? 30 : _nearness(display.logicalBounds, logicalPoint, 15);
    }

    return score;
  }

  static double _overlapRatio(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final denom = a.width * a.height;
    if (denom <= 0) return 0;
    return (overlap.width * overlap.height) / denom;
  }

  static double _nearness(Rect rect, Offset point, double maxScore) {
    if (rect.contains(point)) return maxScore;
    final dx = _distanceToRange(point.dx, rect.left, rect.right);
    final dy = _distanceToRange(point.dy, rect.top, rect.bottom);
    final dist = dx + dy;
    if (dist <= 0) return maxScore;
    return maxScore / (1 + dist / 500);
  }

  static double _distanceToRange(double value, double start, double end) {
    if (value < start) return start - value;
    if (value > end) return value - end;
    return 0;
  }
}
