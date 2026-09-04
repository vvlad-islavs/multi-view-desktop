import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';

import 'lifecycle_test_harness.dart';

void main() {
  group('ViewCloseService.closeSubtreeByMode', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('none only pre-confirms the root', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      await h.closeService.closeSubtreeByMode(1, CloseMode.none);

      expect(h.ffi.callsFor('setPreConfirmClose'), ['setPreConfirmClose:1:true']);
      expect(h.ffi.callsFor('softCloseWindow'), ['softCloseWindow:1']);
      expect(h.ffi.hasCall('forceCloseView'), isFalse);
    });

    test('softCascade soft-closes descendants newest-first then root', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(3, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);

      // Descendants sorted then reversed -> 3 then 2.
      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.callsFor('softCloseWindow'), ['softCloseWindow:3']);
      h.completeClose(3);

      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.callsFor('softCloseWindow'), ['softCloseWindow:3', 'softCloseWindow:2']);
      h.registry.windows.remove(3);
      h.registry.windows.remove(2);
      h.completeClose(2);

      await future;
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isTrue);
      expect(h.ffi.callsFor('softCloseWindow').last, 'softCloseWindow:1');
    });

    test('softCascade aborts when a descendant wait returns false', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(3, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);
      await Future<void>.delayed(Duration.zero);
      h.cascade.abort(3);
      await future;

      expect(h.ffi.callsFor('softCloseWindow'), ['softCloseWindow:3']);
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isFalse);
    });

    test('forceSecondary force-closes secondaries then soft-closes root', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.forceSecondary);
      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.hasCall('forceCloseView:2'), isTrue);
      h.registry.windows.remove(2);
      h.completeClose(2);
      await future;

      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isTrue);
      expect(h.ffi.callsFor('softCloseWindow'), contains('softCloseWindow:1'));
    });

    test('destroy force-closes secondaries and force-closes root', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.destroy);
      await Future<void>.delayed(Duration.zero);
      h.registry.windows.remove(2);
      h.completeClose(2);
      await future;

      expect(h.beforeForceCloseApp, 1);
      expect(h.ffi.hasCall('forceCloseView:1'), isTrue);
    });

    test('waits pending creates before starting close', () async {
      h.seedWindow(1);
      final completer = ViewCreateCompleter<int?>.window(99);
      h.lifecycle.createCompleters[99] = completer;

      var finished = false;
      final future = h.closeService.closeSubtreeByMode(1, CloseMode.none).then((_) {
        finished = true;
      });

      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);

      completer.complete();
      await future;
      expect(finished, isTrue);
      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
    });

    test('softCascade skips root when descendants remain registered', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);
      await Future<void>.delayed(Duration.zero);
      // Complete cascade wait but leave 2 in registry -> early return before root.
      h.completeClose(2);
      await future;

      expect(h.ffi.hasCall('softCloseWindow:2'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isFalse);
    });

    test('softCascade treats missing invoke as abort', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedWindow(3, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.softCascade);
      await Future<void>.delayed(Duration.zero);
      // First descendant is 3; drop 2 before its turn so invoke returns null.
      h.registry.windows.remove(2);
      h.completeClose(3);
      await future;

      expect(h.ffi.hasCall('softCloseWindow:3'), isTrue);
      expect(h.ffi.hasCall('softCloseWindow:2'), isFalse);
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isFalse);
    });

    test('forceSecondary aborts when a secondary wait fails', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.forceSecondary);
      await Future<void>.delayed(Duration.zero);
      h.cascade.abort(2);
      await future;

      expect(h.ffi.hasCall('forceCloseView:2'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:1:true'), isFalse);
    });

    test('destroy aborts when a secondary wait fails', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);

      final future = h.closeService.closeSubtreeByMode(1, CloseMode.destroy);
      await Future<void>.delayed(Duration.zero);
      h.cascade.abort(2);
      await future;

      expect(h.beforeForceCloseApp, 0);
      expect(h.ffi.hasCall('forceCloseView:1'), isFalse);
    });
  });

  group('ViewCloseService.closeApp', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('closes all roots newest-first and returns true', () async {
      h.seedWindow(1);
      h.seedWindow(2);

      final future = h.closeService.closeApp(mode: CloseMode.none);
      await Future<void>.delayed(Duration.zero);
      // roots sorted [1,2], reversed -> 2 then 1
      h.completeClose(2);
      await Future<void>.delayed(Duration.zero);
      h.completeClose(1);

      expect(await future, isTrue);
      expect(h.beforeCloseApp, 1);
      expect(h.closeAppAborted, 0);
    });

    test('returns false and notifies abort when a root wait fails', () async {
      h.seedWindow(1);
      h.seedWindow(2);

      final future = h.closeService.closeApp(mode: CloseMode.none);
      await Future<void>.delayed(Duration.zero);
      h.cascade.abort(2);

      expect(await future, isFalse);
      expect(h.closeAppAborted, 1);
    });

    test('uses closeMode field when mode argument is omitted', () async {
      h.seedWindow(1);
      h.closeService.closeMode = CloseMode.none;

      final future = h.closeService.closeApp();
      await Future<void>.delayed(Duration.zero);
      h.completeClose(1);

      expect(await future, isTrue);
      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
    });
  });

  group('ViewCloseService public close helpers', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('closeView soft-closes windows and waits for cascade', () async {
      h.seedWindow(1);
      final future = h.closeService.closeView(1);
      expect(h.ffi.callsFor('softCloseWindow'), ['softCloseWindow:1']);
      h.completeClose(1);
      expect(await future, isTrue);
    });

    test('closeView destroys dialogs and reports result', () async {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1, isModal: true);

      expect(await h.closeService.closeView(10, dialogRes: 'ok'), isTrue);

      expect(h.dialogResults, [(10, 'ok')]);
      expect(h.disposed, [10]);
      expect(h.ffi.callsFor('destroyModalDialog'), ['destroyModalDialog:10']);
    });

    test('destroyPopup ignores non-popups and destroys popups', () {
      h.seedWindow(1);
      h.closeService.destroyPopup(1);
      expect(h.ffi.calls, isEmpty);

      h.seedPopup(5, parentId: 1);
      h.closeService.destroyPopup(5);
      expect(h.ffi.callsFor('destroyModalDialog'), ['destroyModalDialog:5']);
      expect(h.popupDestroyed, [5]);
    });

    test('destroyPopupsByParent and removeAllDialogsByParent', () {
      h.seedWindow(1);
      h.seedPopup(5, parentId: 1);
      h.seedPopup(6, parentId: 1);
      h.seedDialog(10, parentId: 1);
      h.seedDialog(11, parentId: 1);

      h.closeService.destroyPopupsByParent(1);
      expect(h.popupDestroyed, unorderedEquals([5, 6]));

      h.closeService.removeAllDialogsByParent(1);
      expect(h.disposed, unorderedEquals([10, 11]));
      expect(h.ffi.callsFor('destroyModalDialog'), containsAll(['destroyModalDialog:10', 'destroyModalDialog:11']));
    });

    test('cancelCascade aborts parents and clears pre-confirm', () async {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.cascade.attachWindow(1);
      h.cascade.attachWindow(2);

      final wait1 = h.cascade.waitWindow(1);
      h.closeService.cancelCascade(2);

      expect(h.ffi.hasCall('setPreConfirmClose:1:false'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:2:false'), isTrue);
      expect(await wait1, isFalse);
    });

    test('cancelCascade also walks dialog parent chain', () async {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1);
      h.seedDialog(11, parentId: 10);
      h.cascade.attachWindow(1);
      h.cascade.attachWindow(10);

      final waitRoot = h.cascade.waitWindow(1);
      h.closeService.cancelCascade(11);

      expect(h.ffi.hasCall('setPreConfirmClose:11:false'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:10:false'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:1:false'), isTrue);
      expect(await waitRoot, isFalse);
    });
  });

  group('ViewCloseService native close steps', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('handleLastCloseStep disposes, confirms, and force-closes window', () async {
      h.seedWindow(1);
      h.seedPopup(5, parentId: 1);
      h.seedDialog(10, parentId: 1);
      h.cascade.attachWindow(1);

      await h.closeService.handleLastCloseStep(1);

      expect(h.disposed, containsAll([1, 10]));
      expect(h.popupDestroyed, [5]);
      expect(h.ffi.hasCall('setConfirmClose:1:true'), isTrue);
      expect(h.ffi.hasCall('forceCloseView:1'), isTrue);
      expect(await h.cascade.waitWindow(1), isTrue);
    });

    test('handleLastCloseStep destroys modal dialog via destroyModalDialog', () async {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1, isModal: true);
      h.cascade.attachWindow(10);

      await h.closeService.handleLastCloseStep(10);

      expect(h.ffi.hasCall('destroyModalDialog:10'), isTrue);
      expect(h.ffi.hasCall('forceCloseView:10'), isFalse);
    });

    test('handleWindowCloseListenerResult cancels cascade when disallowed', () async {
      h.seedWindow(1);
      h.cascade.attachWindow(1);
      final wait = h.cascade.waitWindow(1);

      await h.closeService.handleWindowCloseListenerResult(false, 1);

      expect(await wait, isFalse);
    });

    test('handleWindowCloseListenerResult keeps cascade when allowed', () async {
      h.seedWindow(1);
      h.cascade.attachWindow(1);
      final wait = h.cascade.waitWindow(1);

      await h.closeService.handleWindowCloseListenerResult(true, 1);
      h.completeClose(1);

      expect(await wait, isTrue);
    });

    test('handeFirstCloseStep promotes next anchors when dynamic anchor disabled', () async {
      h = LifecycleTestHarness(enableDynamicAnchor: false);
      h.seedWindow(1);
      h.seedWindow(2);
      h.closeService.anchorViewId = 1;
      h.closeService.closeMode = CloseMode.none;

      final future = h.closeService.handeFirstCloseStep(1);
      await Future<void>.delayed(Duration.zero);
      // next candidates excluding 1 -> [2], reversed still [2]
      h.completeClose(2);
      await Future<void>.delayed(Duration.zero);
      h.completeClose(1);
      await future;

      expect(h.ffi.hasCall('softCloseWindow:2'), isTrue);
      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
    });

    test('handeFirstCloseStep skips promotion when dynamic anchor enabled', () async {
      h = LifecycleTestHarness(enableDynamicAnchor: true);
      h.seedWindow(1);
      h.seedWindow(2);
      h.closeService.anchorViewId = 1;
      h.closeService.closeMode = CloseMode.none;

      final future = h.closeService.handeFirstCloseStep(1);
      await Future<void>.delayed(Duration.zero);
      h.completeClose(1);
      await future;

      expect(h.ffi.hasCall('softCloseWindow:1'), isTrue);
      expect(h.ffi.hasCall('softCloseWindow:2'), isFalse);
    });

    test('handeFirstCloseStep stops promotion when candidate cascade aborts', () async {
      h = LifecycleTestHarness(enableDynamicAnchor: false);
      h.seedWindow(1);
      h.seedWindow(2);
      h.seedWindow(3);
      h.closeService.anchorViewId = 1;
      h.closeService.closeMode = CloseMode.none;

      final future = h.closeService.handeFirstCloseStep(1);
      await Future<void>.delayed(Duration.zero);
      // candidates excluding 1 -> [2,3] reversed -> 3 then 2
      h.cascade.abort(3);
      await future;

      expect(h.ffi.hasCall('softCloseWindow:3'), isTrue);
      expect(h.ffi.hasCall('softCloseWindow:1'), isFalse);
    });
  });
}
