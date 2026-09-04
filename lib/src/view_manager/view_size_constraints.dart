import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Size and aspect-ratio constraints for native window geometry.
@internal
class ViewSizeConstraints {
  const ViewSizeConstraints();

  static const ViewSizeConstraints instance = ViewSizeConstraints();

  /// Native "no minimum": 0 (macOS/Windows) or -1 (Linux).
  bool hasMinConstraint(double value) => value > 0;

  /// Native "no maximum": 0 / -1 (Windows), G_MAXINT (Linux), FLT_MAX (macOS).
  bool hasMaxConstraint(double value) => value > 0 && value < 1e7;

  bool sizeBelowMinimum(Size size, Size minSize) {
    return (hasMinConstraint(minSize.width) && size.width < minSize.width) ||
        (hasMinConstraint(minSize.height) && size.height < minSize.height);
  }

  bool sizeAboveMaximum(Size size, Size maxSize) {
    return (hasMaxConstraint(maxSize.width) && size.width > maxSize.width) ||
        (hasMaxConstraint(maxSize.height) && size.height > maxSize.height);
  }

  bool isCorrectSize(Size size, {required Size minSize, required Size maxSize}) {
    return !sizeBelowMinimum(size, minSize) && !sizeAboveMaximum(size, maxSize);
  }

  /// Size that matches [ratio] (`width / height`), locking current height.
  ///
  /// Shrinks to [maxSize] / grows to [minSize] while keeping [ratio].
  /// If min and max cannot be satisfied together, returns [current].
  Size sizeLockedToAspectRatio(
    Size current,
    double ratio, {
    Size minSize = Size.zero,
    Size maxSize = Size.zero,
  }) {
    if (ratio <= 0 || current.width <= 0 || current.height <= 0) {
      return current;
    }

    Size fromWidth(double width) => Size(width, width / ratio);
    Size fromHeight(double height) => Size(height * ratio, height);

    var res = fromHeight(current.height);

    if (hasMaxConstraint(maxSize.width) && res.width > maxSize.width) {
      res = fromWidth(maxSize.width);
    }
    if (hasMaxConstraint(maxSize.height) && res.height > maxSize.height) {
      res = fromHeight(maxSize.height);
    }
    if (hasMinConstraint(minSize.width) && res.width < minSize.width) {
      res = fromWidth(minSize.width);
    }
    if (hasMinConstraint(minSize.height) && res.height < minSize.height) {
      res = fromHeight(minSize.height);
    }

    if (sizeBelowMinimum(res, minSize) || sizeAboveMaximum(res, maxSize)) {
      return current;
    }

    return res;
  }

  /// Tightens [minSize] to [ratio] without going below the original min on either side.
  Size minSizeForAspectRatio(Size minSize, double ratio) {
    if (ratio <= 0) return minSize;
    return Size(math.max(minSize.width, minSize.height * ratio), math.max(minSize.height, minSize.width / ratio));
  }

  /// Tightens [maxSize] to [ratio] without going above the original max on either side.
  Size maxSizeForAspectRatio(Size maxSize, double ratio) {
    if (ratio <= 0) return maxSize;
    return Size(math.min(maxSize.width, maxSize.height * ratio), math.min(maxSize.height, maxSize.width / ratio));
  }
}
