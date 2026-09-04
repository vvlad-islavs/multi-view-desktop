import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/display.dart';

void main() {
  group('Display', () {
    test('fromJson parses full display payload', () {
      final display = Display.fromJson({
        'id': 'screen-1',
        'name': 'Built-in',
        'size': {'width': 1920.0, 'height': 1080.0},
        'visiblePosition': {'dx': 0.0, 'dy': 100.0},
        'visibleSize': {'width': 1920.0, 'height': 980.0},
        'scaleFactor': 2.0,
        'dpi': 192.0,
        'physicalBounds': {'x': 1920.0, 'y': 0.0, 'width': 2560.0, 'height': 1440.0},
        'physicalWorkArea': {'x': 1920.0, 'y': 0.0, 'width': 2560.0, 'height': 1400.0},
        'physicalWidthMm': 600.0,
        'physicalHeightMm': 340.0,
      });

      expect(display.id, 'screen-1');
      expect(display.name, 'Built-in');
      expect(display.size, const Size(1920, 1080));
      expect(display.visiblePosition, const Offset(0, 100));
      expect(display.visibleSize, const Size(1920, 980));
      expect(display.scaleFactor, 2.0);
      expect(display.dpi, 192.0);
      expect(display.physicalBounds, const Rect.fromLTWH(1920, 0, 2560, 1440));
      expect(display.physicalWorkArea, const Rect.fromLTWH(1920, 0, 2560, 1400));
      expect(display.physicalWidthMm, 600);
      expect(display.physicalHeightMm, 340);
      expect(display.diagonalMm, closeTo(689.5, 0.5));
    });

    test('fromJson handles missing optional fields', () {
      final display = Display.fromJson({
        'id': 'screen-2',
        'size': {'width': 800.0, 'height': 600.0},
      });

      expect(display.name, isNull);
      expect(display.visiblePosition, isNull);
      expect(display.visibleSize, isNull);
      expect(display.scaleFactor, isNull);
      expect(display.dpi, isNull);
      expect(display.physicalBounds, isNull);
      expect(display.physicalWorkArea, isNull);
      expect(display.diagonalMm, isNull);
    });
  });
}
