import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/impl/modal_state_service.dart';

void main() {
  group('ModalStateService', () {
    late ModalStateService service;

    setUp(() => service = ModalStateService());

    test('registerDialog adds dialog to parent notifier', () {
      final notifier = service.getNotifier(1);
      expect(notifier.value, isEmpty);

      service.registerDialog(1, dialogId: 10, isModal: true);
      service.registerDialog(1, dialogId: 11, isModal: false);

      expect(notifier.value, [
        (id: 10, isModal: true),
        (id: 11, isModal: false),
      ]);
    });

    test('unregisterDialog removes dialog from parent notifier', () {
      service.registerDialog(1, dialogId: 10, isModal: true);
      service.registerDialog(1, dialogId: 11, isModal: false);

      service.unregisterDialog(1, realDialogId: 10);

      expect(service.getNotifier(1).value, [(id: 11, isModal: false)]);
    });

    test('registerDialog creates new list instance for listeners', () {
      final notifier = service.getNotifier(1);
      final before = notifier.value;

      service.registerDialog(1, dialogId: 5, isModal: true);

      expect(identical(notifier.value, before), isFalse);
    });
    test('disposeView removes notifier', () {
      final notifier = service.getNotifier(3);
      var disposed = false;
      notifier.addListener(() {});
      service.registerDialog(3, dialogId: 1, isModal: true);

      service.disposeView(3);
      disposed = true;

      expect(disposed, isTrue);
      // New notifier is created on next access after dispose.
      expect(service.getNotifier(3).value, isEmpty);
    });
  });
}
