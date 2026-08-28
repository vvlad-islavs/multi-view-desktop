import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'lifecycle_test_harness.dart';

/// End-to-end close orchestration across registry + cascade + closeService.
void main() {
  group('close integration', () {
    test('softCascade closes nested tree then root', () async {
      final h = LifecycleTestHarness();
      // root 1 → child 2 → grandchild 3; sibling 4 under 1
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(3, parentId: 2);
      h.seedWindow(4, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);

      // deepest-first: [3,2,4] sorted → [2,3,4] reversed → 4,3,2
      for (final id in [4, 3, 2]) {
        await Future<void>.delayed(Duration.zero);
        expect(h.ffi.callsFor('softCloseWindow').last, 'softCloseWindow:$id');
        h.registry.windows.remove(id);
        h.completeClose(id);
      }

      await future;
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isTrue);
      expect(h.ffi.callsFor('softCloseWindow').last, 'softCloseWindow:1');
    });

    test('closeApp with forceSecondary closes every root', () async {
      final h = LifecycleTestHarness();
      h.seedWindow(10);
      h.seedWindow(11, parentId: 10);
      h.seedWindow(20);

      final future = h.closeService.closeApp(mode: CloseMode.forceSecondary);

      // roots sorted [10,20] reversed → 20 then 10
      await Future<void>.delayed(Duration.zero);
      h.completeClose(20);
      await Future<void>.delayed(Duration.zero);

      // root 10 force-closes child 11 first
      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.hasCall('forceCloseView:11'), isTrue);
      h.registry.windows.remove(11);
      h.completeClose(11);
      await Future<void>.delayed(Duration.zero);
      h.completeClose(10);

      expect(await future, isTrue);
      expect(h.beforeCloseApp, 1);
    });

    test('cancel during softCascade leaves remaining windows open', () async {
      final h = LifecycleTestHarness();
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(3, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);
      await Future<void>.delayed(Duration.zero);
      // first descendant soft-closed is 3
      h.closeService.cancelCascade(3);
      await future;

      expect(h.registry.isWindow(1), isTrue);
      expect(h.registry.isWindow(2), isTrue);
      expect(h.ffi.hasCall('softCloseWindow:2'), isFalse);
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isFalse);
    });

    test('handleLastCloseStep after softCascade completes cascade wait', () async {
      final h = LifecycleTestHarness();
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final subtree = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);
      await Future<void>.delayed(Duration.zero);
      // soft-close 2 started; simulate native last step
      await h.closeService.handleLastCloseStep(2);
      expect(h.registry.isWindow(2), isFalse);

      await subtree;
      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
    });

    test('macOS last-root path hides instead of soft-close when last root', () async {
      final h = LifecycleTestHarness(isLastMacosRootView: (_) => true);
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1);
      h.seedPopup(5, parentId: 1);

      await h.closeService.closeSubtreeByMode(1, CloseMode.none);

      if (Platform.isMacOS) {
        expect(h.ffi.hasCall('hide:1'), isTrue);
        expect(h.disposed, contains(10));
        expect(h.popupDestroyed, [5]);
        expect(h.ffi.hasCall('setPreConfirmClose:1:false'), isTrue);
      } else {
        expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
      }
    });

    test('destroy mode closeApp force-closes every root tree', () async {
      final h = LifecycleTestHarness();
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(10);

      final future = h.closeService.closeApp(mode: CloseMode.destroy);

      await Future<void>.delayed(Duration.zero);
      // roots reversed → 10 then 1
      h.completeClose(10);
      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.hasCall('forceCloseView:2'), isTrue);
      h.registry.windows.remove(2);
      h.completeClose(2);
      await Future<void>.delayed(Duration.zero);
      h.completeClose(1);

      expect(await future, isTrue);
      expect(h.beforeForceCloseApp, greaterThanOrEqualTo(1));
      expect(h.ffi.hasCall('forceCloseView:1'), isTrue);
      expect(h.ffi.hasCall('forceCloseView:10'), isTrue);
    });

    test('closeView soft-close then last step completes cascade for closeApp', () async {
      final h = LifecycleTestHarness();
      h.seedWindow(1);

      final app = h.closeService.closeApp(mode: CloseMode.none);
      await Future<void>.delayed(Duration.zero);

      final closed = h.closeService.closeView(1);
      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);

      await h.closeService.handleLastCloseStep(1);
      expect(await closed, isTrue);
      expect(await app, isTrue);
      expect(h.disposed, contains(1));
    });

    test('anchor promotion closes sibling roots before the closing anchor', () async {
      final h = LifecycleTestHarness(enableDynamicAnchor: false);
      h.seedWindow(1);
      h.seedWindow(2);
      h.closeService.anchorViewId = 1;
      h.closeService.closeMode = CloseMode.none;

      final future = h.closeService.handeFirstCloseStep(1);
      await Future<void>.delayed(Duration.zero);
      await h.closeService.handleLastCloseStep(2);
      await Future<void>.delayed(Duration.zero);
      await h.closeService.handleLastCloseStep(1);
      await future;

      final soft = h.ffi.callsFor('softCloseWindow');
      expect(soft.indexOf('softCloseWindow:2'), lessThan(soft.indexOf('softCloseWindow:1')));
      expect(h.disposed, containsAll([1, 2]));
    });
  });
}
