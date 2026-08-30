import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  void attach(PopupController controller, {Future<void> Function(AnimationSettings?)? onOpen, Future<void> Function(AnimationSettings?)? onClose}) {
    controller.attach(
      onOpen: onOpen ?? (_) async {},
      onClose: onClose ?? (_) async {},
      dropSession: (_) async {},
    );
  }

  group('PopupController animation', () {
    test('open and close forward animation settings to handlers', () async {
      final controller = PopupController();
      AnimationSettings? openedWith;
      AnimationSettings? closedWith;

      attach(
        controller,
        onOpen: (animation) async => openedWith = animation,
        onClose: (animation) async => closedWith = animation,
      );

      const openSettings = AnimationSettings(duration: Duration(milliseconds: 40));
      const closeSettings = AnimationSettings(duration: Duration(milliseconds: 25));

      await controller.open(animation: openSettings);
      expect(controller.isOpen, isTrue);
      expect(openedWith, same(openSettings));

      await controller.close(animation: closeSettings);
      expect(controller.isOpen, isFalse);
      expect(closedWith, same(closeSettings));
      controller.dispose();
    });

    test('takeOpenFade is true only once after user open', () async {
      final controller = PopupController();
      attach(controller);

      expect(controller.takeOpenFade(), isFalse);

      await controller.open();
      expect(controller.takeOpenFade(), isTrue);
      expect(controller.takeOpenFade(), isFalse);

      await controller.close();
      await controller.open();
      expect(controller.takeOpenFade(), isTrue);
      controller.dispose();
    });

    test('reattach while already open does not arm open fade', () async {
      final controller = PopupController();
      attach(controller);
      await controller.open();
      expect(controller.takeOpenFade(), isTrue);

      controller.detach();
      attach(controller);
      expect(controller.isOpen, isTrue);
      expect(controller.takeOpenFade(), isFalse);
      controller.dispose();
    });

    test('anchorHidden blocks show until cleared', () async {
      final controller = PopupController();
      attach(controller);
      await controller.open();
      expect(controller.anchorHidden, isFalse);

      controller.markAnchorHidden();
      expect(controller.anchorHidden, isTrue);

      controller.detach();
      attach(controller);
      expect(controller.anchorHidden, isTrue);
      expect(controller.isOpen, isTrue);

      controller.clearAnchorHidden();
      expect(controller.anchorHidden, isFalse);
      controller.dispose();
    });

    test('open and close reset the hidden-anchor flag', () async {
      final controller = PopupController();
      attach(controller);
      await controller.open();
      controller.markAnchorHidden();
      await controller.close();
      expect(controller.anchorHidden, isFalse);

      await controller.open();
      expect(controller.anchorHidden, isFalse);
      controller.dispose();
    });

    test('close still drops session after PopupView detach', () async {
      final controller = PopupController();
      var dropped = 0;
      controller.attach(
        onOpen: (_) async {},
        onClose: (_) async {},
        dropSession: (_) async => dropped++,
      );
      await controller.open();
      controller.detach();
      await controller.close();
      expect(dropped, 1);
      expect(controller.isOpen, isFalse);
      controller.dispose();
    });

    test('open during close still invokes onOpen', () async {
      final controller = PopupController();
      final dropGate = Completer<void>();
      var opens = 0;
      controller.attach(
        onOpen: (_) async => opens++,
        onClose: (_) async {},
        dropSession: (_) async => dropGate.future,
      );

      await controller.open();
      expect(opens, 1);

      final closing = controller.close();
      await controller.open();
      expect(controller.isOpen, isTrue);
      expect(opens, 2);

      dropGate.complete();
      await closing;
      expect(controller.isOpen, isTrue);
      controller.dispose();
    });

    test('retainContent returns the same widget until the session is cleared', () {
      final controller = PopupController();
      const first = SizedBox();
      const second = Text('other');
      expect(identical(controller.retainContent(first), controller.retainContent(second)), isTrue);
      controller.clearSessionWidgets();
      expect(identical(controller.retainContent(second), second), isFalse);
      expect((controller.retainContent(second) as KeyedSubtree).child, same(second));
      controller.dispose();
    });
  });

  group('PopupViewController', () {
    test('chrome methods no-op without a native session', () {
      final controller = PopupController();
      expect(() => controller.viewController.setOpacity(0.5), returnsNormally);
      expect(controller.viewController.getOpacity(), 1);
      expect(() => controller.viewController.setBackgroundColor(const Color(0x00000000)), returnsNormally);
      expect(() => controller.viewController.setHasShadow(false), returnsNormally);
      expect(controller.viewController.hasShadow(), isTrue);
      expect(() => controller.viewController.setIgnoreMouseEvents(true), returnsNormally);
      expect(controller.viewController.isIgnoreMouseEvents().ignore, isTrue);
      controller.dispose();
    });
  });
}
