import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/lifecycle/view_registry.dart';

void main() {
  group('ViewRegistry', () {
    late ViewRegistry registry;

    setUp(() => registry = ViewRegistry());

    ViewWindowEntry window({int? parentId}) => ViewWindowEntry(
          widgetBuilder: (_) => const SizedBox.shrink(),
          parentContext: null,
          parentId: parentId,
        );

    ViewDialogEntry dialog({required int parentId, bool isModal = false}) => ViewDialogEntry(
          widgetBuilder: (_) => const SizedBox.shrink(),
          parentContext: null,
          parentId: parentId,
          isModal: isModal,
          closeCompleter: Completer<Object?>(),
        );

    test('type checks and managed ids', () {
      registry.windows[1] = window();
      registry.dialogs[2] = dialog(parentId: 1, isModal: true);
      registry.popups[3] = ViewPopupEntry(parentId: 1);

      expect(registry.isWindow(1), isTrue);
      expect(registry.isDialog(2), isTrue);
      expect(registry.isModalDialog(2), isTrue);
      expect(registry.isPopup(3), isTrue);
      expect(registry.isManaged(1), isTrue);
      expect(registry.isManaged(99), isFalse);
      expect(registry.windowParentId(1), isNull);
      expect(registry.dialogParentId(2), 1);
      expect(registry.allManagedViewIds, containsAll([1, 2]));
    });

    test('direct children and roots', () {
      registry.windows[1] = window();
      registry.windows[2] = window(parentId: 1);
      registry.windows[3] = window(parentId: 1);
      registry.windows[4] = window();
      registry.dialogs[10] = dialog(parentId: 1);
      registry.popups[20] = ViewPopupEntry(parentId: 1);

      expect(registry.directChildWindowIds(1), unorderedEquals([2, 3]));
      expect(registry.directDialogChildIds(1), [10]);
      expect(registry.directPopupChildIds(1), [20]);
      expect(registry.rootWindowIds(), unorderedEquals([1, 4]));
      expect(registry.rootWindowIds(excludingId: 1), [4]);
    });

    test('descendantWindowIdsDeepestFirst walks nested children', () {
      // 1 -> 2 -> 4
      //   \-> 3
      registry.windows[1] = window();
      registry.windows[2] = window(parentId: 1);
      registry.windows[3] = window(parentId: 1);
      registry.windows[4] = window(parentId: 2);

      expect(registry.descendantWindowIdsDeepestFirst(1), [4, 2, 3]);
      expect(registry.descendantWindowIdsDeepestFirst(2), [4]);
      expect(registry.descendantWindowIdsDeepestFirst(3), isEmpty);
    });

    test('parentWindowChain and parentDialogChain', () {
      registry.windows[1] = window();
      registry.windows[2] = window(parentId: 1);
      registry.windows[3] = window(parentId: 2);
      registry.dialogs[10] = dialog(parentId: 1);
      registry.dialogs[11] = dialog(parentId: 10);

      expect(registry.parentWindowChain(3), [2, 1]);
      expect(registry.parentWindowChain(1), isEmpty);
      expect(registry.parentDialogChain(11), [10, 1]);
      expect(registry.parentDialogChain(10), [1]);
    });

    test('entryFor returns window or dialog entry', () {
      registry.windows[1] = window();
      registry.dialogs[2] = dialog(parentId: 1);

      expect(registry.entryFor(1), isA<ViewWindowEntry>());
      expect(registry.entryFor(2), isA<ViewDialogEntry>());
      expect(registry.entryFor(99), isNull);
    });

    test('allManagedViewIds excludes popups; windowViewIds lists windows', () {
      registry.windows[1] = window();
      registry.dialogs[2] = dialog(parentId: 1);
      registry.popups[3] = ViewPopupEntry(parentId: 1);

      expect(registry.windowViewIds, [1]);
      expect(registry.allManagedViewIds, unorderedEquals([1, 2]));
      expect(registry.allManagedViewIds, isNot(contains(3)));
      expect(registry.isManaged(3), isTrue);
      expect(registry.isModalDialog(2), isFalse);
    });

    test('ViewDialogEntry.completeResult completes once', () async {
      final entry = dialog(parentId: 1);
      entry.completeResult('ok');
      entry.completeResult('ignored');
      expect(await entry.closeCompleter.future, 'ok');
    });

    test('disposeEntryResources runs without error', () {
      final entry = window();
      expect(entry.disposeEntryResources, returnsNormally);
    });
  });
}
