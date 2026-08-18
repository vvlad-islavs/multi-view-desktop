import 'dart:ui';

/// Anchor point on a rectangle used by [PopupPositioner].
enum PopupPositionerAnchor {
  center,
  top,
  bottom,
  left,
  right,
  topLeft,
  bottomLeft,
  topRight,
  bottomRight,
}

extension on PopupPositionerAnchor {
  PopupPositionerAnchor get _flipX {
    return switch (this) {
      PopupPositionerAnchor.center => PopupPositionerAnchor.center,
      PopupPositionerAnchor.top => PopupPositionerAnchor.top,
      PopupPositionerAnchor.bottom => PopupPositionerAnchor.bottom,
      PopupPositionerAnchor.left => PopupPositionerAnchor.right,
      PopupPositionerAnchor.right => PopupPositionerAnchor.left,
      PopupPositionerAnchor.topLeft => PopupPositionerAnchor.topRight,
      PopupPositionerAnchor.bottomLeft => PopupPositionerAnchor.bottomRight,
      PopupPositionerAnchor.topRight => PopupPositionerAnchor.topLeft,
      PopupPositionerAnchor.bottomRight => PopupPositionerAnchor.bottomLeft,
    };
  }

  PopupPositionerAnchor get _flipY {
    return switch (this) {
      PopupPositionerAnchor.center => PopupPositionerAnchor.center,
      PopupPositionerAnchor.top => PopupPositionerAnchor.bottom,
      PopupPositionerAnchor.bottom => PopupPositionerAnchor.top,
      PopupPositionerAnchor.left => PopupPositionerAnchor.left,
      PopupPositionerAnchor.right => PopupPositionerAnchor.right,
      PopupPositionerAnchor.topLeft => PopupPositionerAnchor.bottomLeft,
      PopupPositionerAnchor.bottomLeft => PopupPositionerAnchor.topLeft,
      PopupPositionerAnchor.topRight => PopupPositionerAnchor.bottomRight,
      PopupPositionerAnchor.bottomRight => PopupPositionerAnchor.topRight,
    };
  }

  Offset _offsetFor(Size size) {
    return switch (this) {
      PopupPositionerAnchor.center => Offset(-size.width / 2.0, -size.height / 2.0),
      PopupPositionerAnchor.top => Offset(-size.width / 2.0, 0.0),
      PopupPositionerAnchor.bottom => Offset(-size.width / 2.0, -size.height),
      PopupPositionerAnchor.left => Offset(0.0, -size.height / 2.0),
      PopupPositionerAnchor.right => Offset(-size.width, -size.height / 2.0),
      PopupPositionerAnchor.topLeft => Offset.zero,
      PopupPositionerAnchor.bottomLeft => Offset(0.0, -size.height),
      PopupPositionerAnchor.topRight => Offset(-size.width, 0.0),
      PopupPositionerAnchor.bottomRight => Offset(-size.width, -size.height),
    };
  }

  Offset _anchorPositionFor(Rect rect) {
    return switch (this) {
      PopupPositionerAnchor.center => rect.center,
      PopupPositionerAnchor.top => rect.topCenter,
      PopupPositionerAnchor.bottom => rect.bottomCenter,
      PopupPositionerAnchor.left => rect.centerLeft,
      PopupPositionerAnchor.right => rect.centerRight,
      PopupPositionerAnchor.topLeft => rect.topLeft,
      PopupPositionerAnchor.bottomLeft => rect.bottomLeft,
      PopupPositionerAnchor.topRight => rect.topRight,
      PopupPositionerAnchor.bottomRight => rect.bottomRight,
    };
  }
}

/// How a popup adjusts when the unadjusted rect would leave the display.
class PopupConstraintAdjustment {
  const PopupConstraintAdjustment({
    this.flipX = false,
    this.flipY = false,
    this.slideX = false,
    this.slideY = false,
    this.resizeX = false,
    this.resizeY = false,
  });

  /// Flip to the opposite side of the parent on the X axis when clipped.
  final bool flipX;

  /// Flip to the opposite side of the parent on the Y axis when clipped.
  final bool flipY;

  /// Slide along X to stay inside the display.
  final bool slideX;

  /// Slide along Y to stay inside the display.
  final bool slideY;

  /// Shrink width to stay inside the display.
  final bool resizeX;

  /// Shrink height to stay inside the display.
  final bool resizeY;

  @override
  bool operator ==(Object other) {
    return other is PopupConstraintAdjustment &&
        other.flipX == flipX &&
        other.flipY == flipY &&
        other.slideX == slideX &&
        other.slideY == slideY &&
        other.resizeX == resizeX &&
        other.resizeY == resizeY;
  }

  @override
  int get hashCode => Object.hash(flipX, flipY, slideX, slideY, resizeX, resizeY);

  @override
  String toString() =>
      'PopupConstraintAdjustment(flipX: $flipX, flipY: $flipY, slideX: $slideX, slideY: $slideY, resizeX: $resizeX, resizeY: $resizeY)';
}

/// Places a popup relative to an anchor rectangle, following xdg_positioner rules.
class PopupPositioner {
  const PopupPositioner({
    this.parentAnchor = PopupPositionerAnchor.bottomLeft,
    this.childAnchor = PopupPositionerAnchor.topLeft,
    this.offset = Offset.zero,
    this.constraintAdjustment = const PopupConstraintAdjustment(flipY: true, slideX: true),
  });

  /// Point on [anchorRect] that the child is placed against.
  final PopupPositionerAnchor parentAnchor;

  /// Point on the popup that is aligned to [parentAnchor].
  final PopupPositionerAnchor childAnchor;

  /// Extra translation after aligning the anchors.
  final Offset offset;

  /// What to do when the popup would leave [displayRect].
  final PopupConstraintAdjustment constraintAdjustment;

  PopupPositioner copyWith({
    PopupPositionerAnchor? parentAnchor,
    PopupPositionerAnchor? childAnchor,
    Offset? offset,
    PopupConstraintAdjustment? constraintAdjustment,
  }) {
    return PopupPositioner(
      parentAnchor: parentAnchor ?? this.parentAnchor,
      childAnchor: childAnchor ?? this.childAnchor,
      offset: offset ?? this.offset,
      constraintAdjustment: constraintAdjustment ?? this.constraintAdjustment,
    );
  }

  /// Computes the screen-space rectangle for the popup.
  ///
  /// All rectangles are in the same logical coordinate space (Y-down).
  Rect placeWindow({
    required Size childSize,
    required Rect anchorRect,
    required Rect parentRect,
    required Rect displayRect,
  }) {
    Rect defaultResult;
    {
      final Offset result =
          _constrainTo(parentRect, parentAnchor._anchorPositionFor(anchorRect) + offset) +
          childAnchor._offsetFor(childSize);
      defaultResult = result & childSize;
      if (_rectContains(displayRect, defaultResult)) {
        return defaultResult;
      }
    }

    if (constraintAdjustment.flipX) {
      final Offset result =
          _constrainTo(
            parentRect,
            parentAnchor._flipX._anchorPositionFor(anchorRect) + _flipX(offset),
          ) +
          childAnchor._flipX._offsetFor(childSize);
      if (_rectContains(displayRect, result & childSize)) {
        return result & childSize;
      }
    }

    if (constraintAdjustment.flipY) {
      final Offset result =
          _constrainTo(
            parentRect,
            parentAnchor._flipY._anchorPositionFor(anchorRect) + _flipY(offset),
          ) +
          childAnchor._flipY._offsetFor(childSize);
      if (_rectContains(displayRect, result & childSize)) {
        return result & childSize;
      }
    }

    if (constraintAdjustment.flipX && constraintAdjustment.flipY) {
      final Offset result =
          _constrainTo(
            parentRect,
            parentAnchor._flipY._flipX._anchorPositionFor(anchorRect) + _flipX(_flipY(offset)),
          ) +
          childAnchor._flipY._flipX._offsetFor(childSize);
      if (_rectContains(displayRect, result & childSize)) {
        return result & childSize;
      }
    }

    {
      Offset result =
          _constrainTo(parentRect, parentAnchor._anchorPositionFor(anchorRect) + offset) +
          childAnchor._offsetFor(childSize);

      if (constraintAdjustment.slideX) {
        final double leftOverhang = result.dx - displayRect.left;
        final double rightOverhang = result.dx + childSize.width - displayRect.right;
        if (leftOverhang < 0.0) {
          result = result.translate(-leftOverhang, 0.0);
        } else if (rightOverhang > 0.0) {
          result = result.translate(-rightOverhang, 0.0);
        }
      }

      if (constraintAdjustment.slideY) {
        final double topOverhang = result.dy - displayRect.top;
        final double bottomOverhang = result.dy + childSize.height - displayRect.bottom;
        if (topOverhang < 0.0) {
          result = result.translate(0.0, -topOverhang);
        } else if (bottomOverhang > 0.0) {
          result = result.translate(0.0, -bottomOverhang);
        }
      }

      if (_rectContains(displayRect, result & childSize)) {
        return result & childSize;
      }
    }

    {
      var sized = childSize;
      Offset result =
          _constrainTo(parentRect, parentAnchor._anchorPositionFor(anchorRect) + offset) +
          childAnchor._offsetFor(sized);

      if (constraintAdjustment.resizeX) {
        final double leftOverhang = result.dx - displayRect.left;
        final double rightOverhang = result.dx + sized.width - displayRect.right;
        if (leftOverhang < 0.0) {
          result = result.translate(-leftOverhang, 0.0);
          sized = Size(sized.width + leftOverhang, sized.height);
        }
        if (rightOverhang > 0.0) {
          sized = Size(sized.width - rightOverhang, sized.height);
        }
      }

      if (constraintAdjustment.resizeY) {
        final double topOverhang = result.dy - displayRect.top;
        final double bottomOverhang = result.dy + sized.height - displayRect.bottom;
        if (topOverhang < 0.0) {
          result = result.translate(0.0, -topOverhang);
          sized = Size(sized.width, sized.height + topOverhang);
        }
        if (bottomOverhang > 0.0) {
          sized = Size(sized.width, sized.height - bottomOverhang);
        }
      }

      if (_rectContains(displayRect, result & sized)) {
        return result & sized;
      }
    }

    return defaultResult;
  }

  @override
  bool operator ==(Object other) {
    return other is PopupPositioner &&
        other.parentAnchor == parentAnchor &&
        other.childAnchor == childAnchor &&
        other.offset == offset &&
        other.constraintAdjustment == constraintAdjustment;
  }

  @override
  int get hashCode => Object.hash(parentAnchor, childAnchor, offset, constraintAdjustment);

  @override
  String toString() {
    return 'PopupPositioner(parentAnchor: $parentAnchor, childAnchor: $childAnchor, offset: $offset, constraintAdjustment: $constraintAdjustment)';
  }
}

bool _rectContains(Rect r1, Rect r2) {
  return r1.left <= r2.left && r1.right >= r2.right && r1.top <= r2.top && r1.bottom >= r2.bottom;
}

Offset _constrainTo(Rect r, Offset p) {
  return Offset(clampDouble(p.dx, r.left, r.right), clampDouble(p.dy, r.top, r.bottom));
}

Offset _flipX(Offset offset) => Offset(-offset.dx, offset.dy);

Offset _flipY(Offset offset) => Offset(offset.dx, -offset.dy);
