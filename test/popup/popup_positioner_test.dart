import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/popup/popup_controller.dart';
import 'package:multiview_desktop/src/popup/popup_positioner.dart';

void main() {
  group('PopupPositioner', () {
    test('places child below the parent bottom-left by default', () {
      const positioner = PopupPositioner();
      const parent = Rect.fromLTWH(100, 100, 200, 80);
      const anchor = Rect.fromLTWH(100, 140, 80, 40);
      const display = Rect.fromLTWH(0, 0, 1000, 1000);

      final placed = positioner.placeWindow(
        childSize: const Size(120, 60),
        anchorRect: anchor,
        parentRect: parent,
        displayRect: display,
      );

      expect(placed.left, anchor.left);
      expect(placed.top, anchor.bottom);
      expect(placed.size, const Size(120, 60));
    });

    test('flips vertically when the default placement leaves the display', () {
      const positioner = PopupPositioner(
        parentAnchor: PopupPositionerAnchor.bottomLeft,
        childAnchor: PopupPositionerAnchor.topLeft,
        constraintAdjustment: PopupConstraintAdjustment(flipY: true),
      );
      const parent = Rect.fromLTWH(10, 900, 100, 80);
      const anchor = Rect.fromLTWH(10, 940, 80, 40);
      const display = Rect.fromLTWH(0, 0, 400, 980);

      final placed = positioner.placeWindow(
        childSize: const Size(80, 80),
        anchorRect: anchor,
        parentRect: parent,
        displayRect: display,
      );

      expect(placed.bottom, lessThanOrEqualTo(display.bottom));
      expect(placed.top, lessThan(anchor.top));
    });
  });

  group('PopupController', () {
    test('open and close notify listeners', () async {
      final controller = PopupController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.open();
      expect(controller.isOpen, isTrue);
      expect(notifications, 1);

      await controller.close();
      expect(controller.isOpen, isFalse);
      expect(notifications, 2);
      controller.dispose();
    });

    test('open is idempotent', () async {
      final controller = PopupController();
      await controller.open();
      await controller.open();
      expect(controller.isOpen, isTrue);
      controller.dispose();
    });
  });
}
