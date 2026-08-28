import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';
import 'package:multiview_desktop/src/lifecycle/view_owners.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';

import 'lifecycle_test_harness.dart';

void main() {
  group('LifecycleViewsController', () {
    late LifecycleTestHarness h;

    setUp(() => h = LifecycleTestHarness());

    test('ownerFor routes by registry type', () {
      h.seedWindow(1);
      h.seedWindow(2, parentId: 1);
      h.seedDialog(10, parentId: 1, isModal: false);
      h.seedDialog(11, parentId: 1, isModal: true);
      h.seedPopup(20, parentId: 1);

      expect(h.lifecycle.ownerFor(1), isA<WindowOwner>());
      expect(h.lifecycle.ownerFor(2), isA<ChildWindowOwner>());
      expect(h.lifecycle.ownerFor(10), isA<ModelessDialogOwner>());
      expect(h.lifecycle.ownerFor(11), isA<ModalDialogOwner>());
      expect(h.lifecycle.ownerFor(20), isA<PopupOwner>());
      expect(h.lifecycle.ownerFor(99), isNull);
    });

    test('allocateToken increments', () {
      expect(h.lifecycle.allocateToken(), 0);
      expect(h.lifecycle.allocateToken(), 1);
      expect(h.lifecycle.allocateToken(), 2);
    });

    test('firstFrameCbComplete resolves create completer', () async {
      final c = ViewCreateCompleter<int?>.window(5);
      h.lifecycle.createCompleters[5] = c;

      expect(h.lifecycle.hasPendingCreates(), isTrue);
      final future = h.lifecycle.waitFirstFrame(5);
      h.lifecycle.firstFrameCbComplete(5);

      expect(await future, isNull);
      expect(h.lifecycle.hasPendingCreates(), isFalse);
      expect(h.lifecycle.createCompleters.containsKey(5), isFalse);
    });

    test('waitFirstFrame times out with CreateViewError.timeout', () async {
      final c = ViewCreateCompleter<int?>.window(7);
      h.lifecycle.createCompleters[7] = c;

      final result = await h.lifecycle.waitFirstFrame(7, timeoutMs: 1);
      expect(result, CreateViewError.timeout.code);
      expect(c.isCompleted, isTrue);
    });

    test('waitAllCreatingViews waits all pending and respects excludeTokens', () async {
      final a = ViewCreateCompleter<int?>.window(1);
      final b = ViewCreateCompleter<int?>.window(2);
      h.lifecycle.createCompleters[1] = a;
      h.lifecycle.createCompleters[2] = b;

      var done = false;
      final wait = h.lifecycle.waitAllCreatingViews(excludeTokens: [2]).then((_) => done = true);

      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      a.complete();
      await wait;
      expect(done, isTrue);
      expect(b.isCompleted, isFalse);
    });

    test('hasPendingCreates ignores excludeTokens and completed entries', () {
      final a = ViewCreateCompleter<int?>.window(1);
      final b = ViewCreateCompleter<int?>.window(2);
      h.lifecycle.createCompleters[1] = a;
      h.lifecycle.createCompleters[2] = b;
      a.complete();

      expect(h.lifecycle.hasPendingCreates(), isTrue);
      expect(h.lifecycle.hasPendingCreates(excludeTokens: [2]), isFalse);
    });

    test('registerDialog and hasModalDialog delegate to callbacks', () {
      h.seedWindow(1);
      expect(h.lifecycle.hasModalDialog(1), isFalse);

      h.lifecycle.registerDialog(1, dialogId: 10, isModal: true);
      expect(h.registry.isModalDialog(10), isTrue);
      expect(h.lifecycle.hasModalDialog(1), isTrue);
      expect(h.lifecycle.isWindowRegistered(1), isTrue);
      expect(h.lifecycle.isViewRegistered(10), isTrue);
    });

    test('openWindow creates, registers via callback, and shows after first frame', () async {
      late int createdId;
      final open = h.lifecycle.openWindow(
        options: const WindowOptions(alignment: null),
        onCreated: (id) {
          createdId = id;
          h.seedWindow(id);
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(h.ffi.hasCall('createWindow'), isTrue);
      h.lifecycle.firstFrameCbComplete(createdId);

      expect(await open, createdId);
      expect(h.ffi.hasCall('show:$createdId'), isTrue);
    });

    test('openChildWindow requires registered parent', () async {
      expect(
        () => h.lifecycle.openChildWindow(parentId: 1, onCreated: (_) {}),
        throwsA(isA<ArgumentError>()),
      );

      h.seedWindow(1);
      late int childId;
      final open = h.lifecycle.openChildWindow(
        parentId: 1,
        options: const WindowOptions(alignment: null),
        onCreated: (id) {
          childId = id;
          h.seedWindow(id, parentId: 1);
        },
      );
      await Future<void>.delayed(Duration.zero);
      h.lifecycle.firstFrameCbComplete(childId);
      expect(await open, childId);
      expect(h.ffi.hasCall('createWindow:$childId:parent=1'), isTrue);
    });

    test('openPopup requires registered parent and configures close flags', () {
      expect(
        () => h.lifecycle.openPopup(parentId: 1, size: const Size(10, 10), onCreated: (_) {}),
        throwsA(isA<ArgumentError>()),
      );

      h.seedWindow(1);
      final id = h.lifecycle.openPopup(
        parentId: 1,
        size: const Size(40, 40),
        onCreated: (popupId) => h.seedPopup(popupId, parentId: 1),
      );

      expect(h.ffi.hasCall('createPopup:$id:parent=1'), isTrue);
      expect(h.ffi.hasCall('setPreConfirmClose:$id:true'), isTrue);
      expect(h.ffi.hasCall('setPreventClose:$id:false'), isTrue);
      expect(h.ffi.hasCall('setConfirmClose:$id:true'), isTrue);
    });

    test('openModalDialog registers and returns id without display lookup', () async {
      h.seedWindow(1);

      late int modalId;
      final modal = h.lifecycle.openModalDialog(
        parentId: 1,
        onCreated: (id) {
          modalId = id;
        },
      );
      await Future<void>.delayed(Duration.zero);
      h.lifecycle.firstFrameCbComplete(modalId);
      expect(await modal, modalId);
      expect(h.registry.isModalDialog(modalId), isTrue);
      expect(h.ffi.hasCall('createDialog:$modalId:parent=1:modal=true'), isTrue);
    });

    test('openModelessDialog rejects missing parent', () {
      expect(
        () => h.lifecycle.openModelessDialog(parentId: 99, onCreated: (_) {}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('openModelessDialog creates, positions via calculator, and shows', () async {
      h.seedWindow(1);
      h.ffi.frames[1] = const Rect.fromLTWH(100, 50, 800, 600);
      h.fakePositionCalculator.byParentResult = const Offset(120, 80);

      late int dialogId;
      final open = h.lifecycle.openModelessDialog(
        parentId: 1,
        options: const DialogOptions(title: 'Modeless', size: Size(200, 150)),
        onCreated: (id) {
          dialogId = id;
        },
      );
      await Future<void>.delayed(Duration.zero);
      h.lifecycle.firstFrameCbComplete(dialogId);

      expect(await open, dialogId);
      expect(h.registry.isDialog(dialogId), isTrue);
      expect(h.registry.isModalDialog(dialogId), isFalse);
      expect(h.ffi.hasCall('createDialog:$dialogId:parent=1:modal=false'), isTrue);
      expect(h.ffi.hasCall('show:$dialogId'), isTrue);
      expect(h.ffi.hasCall('setTitle:$dialogId:Modeless'), isTrue);

      expect(h.fakePositionCalculator.byParentCalls, hasLength(1));
      final call = h.fakePositionCalculator.byParentCalls.single;
      expect(call.alignment, Alignment.center);
      expect(call.windowSize, const Size(200, 150));
      expect(call.parentBounds, const Rect.fromLTWH(100, 50, 800, 600));
    });

    test('openWindow uses position calculator when alignment is set', () async {
      h.fakePositionCalculator.byDisplayResult = const Offset(11, 22);

      late int createdId;
      final open = h.lifecycle.openWindow(
        options: const WindowOptions(alignment: Alignment.topLeft, size: Size(640, 480)),
        onCreated: (id) {
          createdId = id;
          h.seedWindow(id);
        },
      );
      await Future<void>.delayed(Duration.zero);
      h.lifecycle.firstFrameCbComplete(createdId);

      expect(await open, createdId);
      expect(h.fakePositionCalculator.byDisplayCalls, hasLength(1));
      expect(h.fakePositionCalculator.byDisplayCalls.single.windowSize, const Size(640, 480));
      expect(h.fakePositionCalculator.byDisplayCalls.single.alignment, Alignment.topLeft);
    });

    test('openModalDialog rejects when parent already has a modal', () {
      h.seedWindow(1);
      h.seedDialog(10, parentId: 1, isModal: true);

      expect(
        () => h.lifecycle.openModalDialog(parentId: 1, onCreated: (_) {}),
        throwsA(isA<Exception>()),
      );
    });

    test('openModalDialog rejects when parent has pending dialog create', () {
      h.seedWindow(1);
      h.pendingDialogParents.add(1);

      expect(
        () => h.lifecycle.openModalDialog(parentId: 1, onCreated: (_) {}),
        throwsA(isA<Exception>()),
      );
    });

    test('openWindow throws when native create returns error code', () {
      h.ffi.nextCreateResult = CreateViewError.timeout.code;

      expect(
        () => h.lifecycle.openWindow(onCreated: (_) {}),
        throwsA(isA<Exception>()),
      );
    });

    test('applyWindowOptions and applyDialogOptions forward to applier', () {
      h.lifecycle.applyWindowOptions(1, WindowOptions(title: 'W'));
      h.lifecycle.applyDialogOptions(2, DialogOptions(title: 'D'));

      expect(h.ffi.hasCall('setTitle:1:W'), isTrue);
      expect(h.ffi.hasCall('setTitle:2:D'), isTrue);
    });

    test('PopupOwner.close destroys popup via closeService', () async {
      h.seedWindow(1);
      h.seedPopup(5, parentId: 1);

      await h.lifecycle.popupOwner.close(5);

      expect(h.popupDestroyed, [5]);
      expect(h.ffi.hasCall('destroyModalDialog:5'), isTrue);
    });

    test('owner fadeOut runs when window open/close animation enabled', () async {
      h = LifecycleTestHarness(animation: ViewAnimationConfig.defaults);
      h.seedWindow(1);

      await h.lifecycle.windowOwner.close(1);

      expect(h.ffi.callsFor('setOpacity'), isNotEmpty);
      expect(h.ffi.callsFor('setOpacity').last, 'setOpacity:1:0.0');
    });
  });
}
