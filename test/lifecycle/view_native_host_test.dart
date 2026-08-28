import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

import 'lifecycle_test_harness.dart';

void main() {
  group('ViewNativeHost', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('delegates type checks to registry', () {
      h.seedWindow(1);
      h.seedDialog(2, parentId: 1, isModal: true);
      h.seedPopup(3, parentId: 1);

      expect(h.host.isWindow(1), isTrue);
      expect(h.host.isDialog(2), isTrue);
      expect(h.host.isModalDialog(2), isTrue);
      expect(h.host.isPopup(3), isTrue);
      expect(h.host.isManaged(1), isTrue);
      expect(h.host.dialogParentId(2), 1);
      expect(h.host.windowViewIds(), contains(1));
      expect(h.host.allManagedViewIds(), containsAll([1, 2]));
    });
  });

  group('ViewManagerProxies invoke guards', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('appearance.setOpacity no-ops for unknown view', () {
      h.proxies.appearance.setOpacity(99, 0.5);
      expect(h.ffi.calls, isEmpty);
    });

    test('appearance.setOpacity records for managed window', () {
      h.seedWindow(1);
      h.proxies.appearance.setOpacity(1, 0.25);
      expect(h.ffi.hasCall('setOpacity:1:0.25'), isTrue);
      expect(h.proxies.appearance.getOpacity(1), 0.25);
    });

    test('state.show works for dialogs via dialogSupports', () {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1);

      h.proxies.state.show(10);
      expect(h.ffi.hasCall('show:10'), isTrue);
    });

    test('state.maximize is skipped for dialogs without dialogSupports', () {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1);

      h.proxies.state.maximize(10);
      expect(h.ffi.hasCall('maximize'), isFalse);
    });

    test('state.hide works for windows', () {
      h.seedWindow(1);
      h.proxies.state.hide(1);
      expect(h.ffi.hasCall('hide:1'), isTrue);
    });
  });
}
