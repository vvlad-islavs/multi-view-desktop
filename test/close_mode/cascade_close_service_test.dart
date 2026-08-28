import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';

void main() {
  group('CascadeCloseService', () {
    late CascadeCloseService service;

    setUp(() => service = CascadeCloseService());

    test('waitWindow returns true when window completes', () async {
      service.attachWindow(1);
      service.completeWindow(1);

      expect(await service.waitWindow(1), isTrue);
    });

    test('waitWindow returns true when id was never attached', () async {
      expect(await service.waitWindow(42), isTrue);
    });

    test('waitWindow returns false when cascade is aborted while waiting', () async {
      service.attachWindow(1);
      service.attachWindow(2);

      final wait1 = service.waitWindow(1);
      final wait2 = service.waitWindow(2);
      service.abort(1);

      expect(await wait1, isFalse);
      expect(await wait2, isFalse);
    });

    test('abort is no-op for missing or already completed id', () async {
      service.attachWindow(1);
      service.completeWindow(1);
      service.abort(1);
      service.abort(99);

      expect(await service.waitWindow(1), isTrue);
    });

    test('abort completes remaining pending with false then clears', () async {
      service.attachWindow(10);
      service.attachWindow(11);
      final wait10 = service.waitWindow(10);
      final wait11 = service.waitWindow(11);

      service.abort(10);

      expect(await wait10, isFalse);
      expect(await wait11, isFalse);
      // After clear, wait without attach returns true.
      expect(await service.waitWindow(10), isTrue);
    });

    test('detachWindow removes completer without completing', () async {
      service.attachWindow(5);
      service.detachWindow(5);

      expect(await service.waitWindow(5), isTrue);
    });

    test('attachWindow is idempotent for the same id', () async {
      service.attachWindow(1);
      service.attachWindow(1);
      service.completeWindow(1);
      expect(await service.waitWindow(1), isTrue);
    });

    test('clear drops pending waits without completing them via abort', () async {
      service.attachWindow(1);
      service.clear();
      expect(await service.waitWindow(1), isTrue);
    });

    test('completeWindow is a no-op for unattached ids', () async {
      service.completeWindow(99);
      expect(await service.waitWindow(99), isTrue);
    });

    test('waitWindow detaches after completion so a later wait is fresh', () async {
      service.attachWindow(1);
      service.completeWindow(1);
      expect(await service.waitWindow(1), isTrue);

      // Completer was detached; without re-attach, wait returns true immediately.
      expect(await service.waitWindow(1), isTrue);

      service.attachWindow(1);
      final pending = service.waitWindow(1);
      service.completeWindow(1);
      expect(await pending, isTrue);
    });
  });
}
