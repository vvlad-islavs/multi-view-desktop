import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/display.dart';
import 'package:multiview_desktop/src/screen_retriever/display_matcher.dart';

void main() {
  Display display({
    required String id,
    Rect? physical,
    Offset logicalOrigin = Offset.zero,
    Size logicalSize = const Size(1920, 1080),
    num? dpi,
    double? widthMm,
    double? heightMm,
  }) {
    return Display(
      id: id,
      size: logicalSize,
      visiblePosition: logicalOrigin,
      visibleSize: logicalSize,
      scaleFactor: dpi != null ? dpi / 96 : null,
      dpi: dpi,
      physicalBounds: physical,
      physicalWidthMm: widthMm,
      physicalHeightMm: heightMm,
    );
  }

  group('DisplayMatcher', () {
    test('physical point beats shared DPI', () {
      final a = display(
        id: 'a',
        physical: const Rect.fromLTWH(0, 0, 1920, 1080),
        dpi: 96,
        widthMm: 500,
        heightMm: 280,
      );
      final b = display(
        id: 'b',
        physical: const Rect.fromLTWH(1920, 0, 1920, 1080),
        logicalOrigin: const Offset(1920, 0),
        dpi: 96,
        widthMm: 600,
        heightMm: 340,
      );

      final picked = DisplayMatcher.pick(
        displays: [a, b],
        fallback: a,
        physicalPoint: const Offset(2000, 100),
        dpi: 96,
      );
      expect(picked.id, 'b');
    });

    test('diagonal breaks a DPI tie when physical overlap is missing', () {
      final small = display(
        id: 'laptop',
        dpi: 144,
        widthMm: 300,
        heightMm: 170,
      );
      final large = display(
        id: 'external',
        dpi: 144,
        widthMm: 600,
        heightMm: 340,
      );

      final picked = DisplayMatcher.pick(
        displays: [small, large],
        fallback: small,
        dpi: 144,
        diagonalMm: large.diagonalMm,
      );
      expect(picked.id, 'external');
    });

    test('logical overlap is weaker than physical overlap', () {
      final a = display(
        id: 'a',
        physical: const Rect.fromLTWH(0, 0, 1920, 1080),
        dpi: 96,
      );
      final b = display(
        id: 'b',
        physical: const Rect.fromLTWH(1920, 0, 2560, 1440),
        logicalOrigin: const Offset(1280, 0),
        logicalSize: const Size(1707, 960),
        dpi: 144,
      );

      final picked = DisplayMatcher.pick(
        displays: [a, b],
        fallback: a,
        physicalRect: const Rect.fromLTWH(1920, 0, 2560, 1440),
        logicalBounds: const Rect.fromLTWH(0, 0, 1920, 1080),
      );
      expect(picked.id, 'b');
    });
  });
}
