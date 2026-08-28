import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/lifecycle/view_animator.dart';

void main() {
  group('ViewAnimator', () {
    testWidgets('scheduler path reaches to value', (tester) async {
      final values = <double>[];
      const animator = ViewAnimator();

      final future = animator.animate(
        onValue: values.add,
        from: 0,
        to: 1,
        duration: const Duration(milliseconds: 50),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 50));
      await future;

      expect(values.first, 0);
      expect(values.last, 1);
      expect(values.length, greaterThan(2));
    });

    test('timer fps path reaches to value', () async {
      final values = <double>[];
      const animator = ViewAnimator();

      // Uses real DateTime + Timer.periodic — await wall-clock duration.
      final future = animator.animate(
        onValue: values.add,
        from: 1,
        to: 0,
        duration: const Duration(milliseconds: 40),
        fps: 50,
      );

      await future;

      expect(values.first, 1);
      expect(values.last, 0);
    });
  });
}
