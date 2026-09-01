import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/display.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';

void main() {
  group('WindowPositionCalculator.calcPosition', () {
    late WindowPositionCalculator calc;

    setUp(() => calc = WindowPositionCalculator(resolveDisplay: () => throw StateError('unused')));

    test('centers window in visible rect', () {
      final pos = calc.calcPosition(
        alignment: Alignment.center,
        windowSize: const Size(200, 100),
        visibleWidth: 1000,
        visibleHeight: 800,
        visibleStartX: 10,
        visibleStartY: 20,
      );

      expect(pos, const Offset(10 + 400, 20 + 350));
    });

    test('topLeft uses visible origin', () {
      final pos = calc.calcPosition(
        alignment: Alignment.topLeft,
        windowSize: const Size(50, 50),
        visibleWidth: 100,
        visibleHeight: 100,
        visibleStartX: 5,
        visibleStartY: 7,
      );

      expect(pos, const Offset(5, 7));
    });

    test('bottomRight pins to far corner', () {
      final pos = calc.calcPosition(
        alignment: Alignment.bottomRight,
        windowSize: const Size(40, 20),
        visibleWidth: 200,
        visibleHeight: 100,
        visibleStartX: 0,
        visibleStartY: 0,
      );

      expect(pos, const Offset(160, 80));
    });
  });

  group('WindowPositionCalculator with fake display', () {
    late WindowPositionCalculator calc;

    setUp(() {
      calc = WindowPositionCalculator(
        resolveDisplay: () => Display.fromJson({
          'id': '1',
          'size': {'width': 1920.0, 'height': 1080.0},
          'visiblePosition': {'dx': 0.0, 'dy': 0.0},
          'visibleSize': {'width': 1920.0, 'height': 1080.0},
        }),
      );
    });

    test('calcWindowPosition uses display visible bounds', () {
      final pos = calc.calcWindowPosition(const Size(200, 100), Alignment.center);
      expect(pos, const Offset(860, 490));
    });

    test('calcWindowPositionByParent centers over parent frame', () {
      final pos = calc.calcWindowPositionByParent(
        Alignment.center,
        windowSize: const Size(200, 100),
        parentBounds: const Rect.fromLTWH(100, 50, 800, 600),
      );

      // visibleStart = parent origin (+ macOS title-bar inset on Y).
      final macInset = Platform.isMacOS ? 38.0 : 0.0;
      expect(pos.dx, 100 + 300);
      expect(pos.dy, 50 + 250 - macInset);
    });
  });
}
