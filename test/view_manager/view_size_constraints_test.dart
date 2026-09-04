import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/view_manager/view_size_constraints.dart';

void main() {
  const constraints = ViewSizeConstraints();
  const ratio = 16 / 9;

  group('sizeLockedToAspectRatio', () {
    test('locks height and derives width', () {
      expect(
        constraints.sizeLockedToAspectRatio(const Size(1000, 700), ratio),
        const Size(700 * ratio, 700),
      );
    });

    test('shrinks to max width when derived width overflows', () {
      expect(
        constraints.sizeLockedToAspectRatio(
          const Size(1000, 700),
          ratio,
          maxSize: const Size(800, 2000),
        ),
        const Size(800, 800 / ratio),
      );
    });

    test('grows to min width when derived width is too small', () {
      expect(
        constraints.sizeLockedToAspectRatio(
          const Size(200, 100),
          ratio,
          minSize: const Size(400, 50),
        ),
        const Size(400, 400 / ratio),
      );
    });

    test('returns current when min and max conflict with ratio', () {
      const current = Size(1000, 700);
      expect(
        constraints.sizeLockedToAspectRatio(
          current,
          ratio,
          minSize: const Size(0, 700),
          maxSize: const Size(800, 2000),
        ),
        current,
      );
    });

    test('ratio 0 leaves size unchanged', () {
      expect(
        constraints.sizeLockedToAspectRatio(const Size(1000, 700), 0),
        const Size(1000, 700),
      );
    });
  });

  group('sizeBelowMinimum / sizeAboveMaximum', () {
    test('rejects a size that breaks only one axis', () {
      expect(constraints.sizeBelowMinimum(const Size(100, 500), const Size(200, 200)), isTrue);
      expect(constraints.sizeAboveMaximum(const Size(300, 50), const Size(200, 200)), isTrue);
    });

    test('treats unset native sentinels as no constraint', () {
      expect(constraints.sizeBelowMinimum(const Size(100, 100), Size.zero), isFalse);
      expect(constraints.sizeBelowMinimum(const Size(100, 100), const Size(-1, -1)), isFalse);
      expect(constraints.sizeAboveMaximum(const Size(800, 600), const Size(-1, -1)), isFalse);
      expect(constraints.sizeAboveMaximum(const Size(800, 600), const Size(1e9, 1e9)), isFalse);
    });
  });

  group('minSizeForAspectRatio / maxSizeForAspectRatio', () {
    test('min raises the side that would otherwise fall below the original floor', () {
      expect(
        constraints.minSizeForAspectRatio(const Size(1000, 700), ratio),
        const Size(700 * ratio, 700),
      );
    });

    test('max lowers the side that would otherwise exceed the original cap', () {
      expect(
        constraints.maxSizeForAspectRatio(const Size(2000, 800), ratio),
        const Size(800 * ratio, 800),
      );
    });
  });
}
