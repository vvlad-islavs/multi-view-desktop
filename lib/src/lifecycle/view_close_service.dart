import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';
import 'package:multiview_desktop/src/lifecycle/lifecycle_views_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_owner_base.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';

/// Soft/force/destroy close orchestration mirroring `_ViewsManagerImpl`.
@internal
class ViewCloseService {
  ViewCloseService({
    required this.lifecycle,
    required this.delegate,
    CascadeCloseService? cascadeCloseService,
    this.anchorViewId,
    this.onDialogCloseResult,
    this.onPopupDestroyed,
    this.onBeforeCloseApp,
    this.onCloseAppAborted,
    this.onBeforeForceCloseApp,
  }) : cascadeCloseService = cascadeCloseService ?? CascadeCloseService();

  final LifecycleViewsController lifecycle;
  final ViewCloseDelegate delegate;
  final CascadeCloseService cascadeCloseService;

  /// Anchor view for close-policy promotion (mirrors `_realAnchorId`).
  int? anchorViewId;

  void Function(int viewId, dynamic dialogRes)? onDialogCloseResult;
  void Function(int viewId)? onPopupDestroyed;
  VoidCallback? onBeforeCloseApp;
  VoidCallback? onCloseAppAborted;
  VoidCallback? onBeforeForceCloseApp;

  /// Lifecycle-only FFI (create/close-policy; no public proxy).
  FfiBridge get ffi => lifecycle.ffiBridge;

  ViewRegistry get registry => lifecycle.registry;

  CloseMode closeMode = CloseMode.softCascade;

  /// Waits until [SchedulerPhase.idle]. Used only where close FFI can nest into
  /// an active frame (fade-out ticks, direct programmatic modal destroy).
  /// Cascade close from native events is already deferred in `_ViewsManagerImpl`.
  Future<void> _awaitSchedulerIdle() async {
    if (BindingBase.debugBindingType() == null) return;
    final binding = SchedulerBinding.instance;
    while (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
    }
  }

  // ---------------------------------------------------------------------------
  // Native close events (wire from `_onStaticCall`).
  // ---------------------------------------------------------------------------

  Future<void> handeFirstCloseStep(int viewId) async {
    MvdLog.instance.info('close', 'first close step', {
      'realId': viewId,
      'closeMode': closeMode.name,
      'isWindow': registry.isWindow(viewId),
      'isDialog': registry.isDialog(viewId),
      'parentWindow': registry.windowParentId(viewId),
      'children': registry.directChildWindowIds(viewId).join(','),
      'anchorId': _anchorId,
    });
    final nextAnchorCandidates = delegate.anchorCandidatesExcluding(excludingViewId: viewId)..sort();
    if (viewId == _anchorId && nextAnchorCandidates.isNotEmpty && !delegate.enableDynamicAnchor) {
      for (final candidate in nextAnchorCandidates.reversed) {
        cascadeCloseService.abort(candidate);
        cascadeCloseService.attachWindow(candidate);
        await closeSubtreeByMode(candidate, closeMode);
        final closed = await cascadeCloseService.waitWindow(candidate);
        if (!closed) return;
      }
    }

    await closeSubtreeByMode(viewId, closeMode);
  }
  @visibleForTesting
  ViewOwnerBase? ownerFor(int viewId) {
    if (registry.isPopup(viewId)) return lifecycle.popupOwner;
    if (registry.isDialog(viewId)) {
      return registry.isModalDialog(viewId) ? lifecycle.modalDialogOwner : lifecycle.modelessDialogOwner;
    }
    if (registry.isWindow(viewId)) {
      return registry.windowParentId(viewId) == null ? lifecycle.windowOwner : lifecycle.childWindowOwner;
    }
    return null;
  }

  Future<void> handleLastCloseStep(int viewId) async {
    MvdLog.instance.info('close', 'last close step', {
      'realId': viewId,
      'isModalDialog': registry.isModalDialog(viewId),
      'isPopup': registry.isPopup(viewId),
      'parentWindow': registry.windowParentId(viewId),
      'children': registry.directChildWindowIds(viewId).join(','),
    });
    final isModalDialog = registry.isModalDialog(viewId);

    await _awaitSchedulerIdle();
    await ownerFor(viewId)?.close(viewId);

    destroyPopupsByParent(viewId);
    removeAllDialogsByParent(viewId);
    delegate.disposeView(viewId);

    ffi.setConfirmClose(viewId, isConfirm: true);
    if (isModalDialog) {
      ffi.destroyModalDialog(viewId);
    } else {
      ffi.forceCloseView(viewId);
    }
    cascadeCloseService.completeWindow(viewId);
  }

  Future<void> handleWindowCloseListenerResult(bool allowClose, int viewId) async {
    if (!allowClose) {
      cancelCascade(viewId);
    }
  }

  // ---------------------------------------------------------------------------
  // Public close API.
  // ---------------------------------------------------------------------------

  void cancelCascade(int viewId) {
    final parents = [...registry.parentWindowChain(viewId), ...registry.parentDialogChain(viewId), viewId];
    MvdLog.instance.info('close', 'cascade abort', {
      'realId': viewId,
      'chain': parents.join(','),
    });
    for (final parent in parents) {
      ffi.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  Future<bool> closeView<T>(int viewId, {T? dialogRes}) async {
    final isDialog = registry.isDialog(viewId);
    if (isDialog) {
      onDialogCloseResult?.call(viewId, dialogRes);
      // destroy only on macos
      if (registry.isModalDialog(viewId) && Platform.isMacOS) {
        await _awaitSchedulerIdle();
        delegate.invoke<void>(viewId, () => ffi.destroyModalDialog(viewId), dialogSupports: true);
        delegate.disposeView(viewId);
        return true;
      }
    }

    final wait = delegate.invoke<Future<bool>>(viewId, () {
      cascadeCloseService.attachWindow(viewId);
      ffi.softCloseWindow(viewId);
      return cascadeCloseService.waitWindow(viewId);
    }, dialogSupports: isDialog);

    if (wait == null) return false;
    return await wait;
  }

  void destroyPopup(int viewId) {
    if (!registry.isPopup(viewId)) return;
    MvdLog.instance.info('close', 'destroyPopup', {'realId': viewId});
    lifecycle.animationController.clearOverrides(viewId);
    delegate.invoke<void>(viewId, () => ffi.destroyModalDialog(viewId), dialogSupports: true);
    onPopupDestroyed?.call(viewId);
  }

  void destroyPopupsByParent(int parentId) {
    for (final id in registry.directPopupChildIds(parentId)) {
      destroyPopup(id);
    }
  }

  void removeAllDialogsByParent(int parentId) {
    final allDialogs = registry.directDialogChildIds(parentId)..sort();
    for (final dialogId in allDialogs.reversed) {
      ffi.destroyModalDialog(dialogId);
      delegate.disposeView(dialogId);
    }
  }

  Future<bool> closeApp({CloseMode? mode}) async {
    final effectiveMode = mode ?? closeMode;
    final allRoots = registry.rootWindowIds()..sort();

    onBeforeCloseApp?.call();
    for (final root in allRoots.reversed) {
      cascadeCloseService.attachWindow(root);
      unawaited(closeSubtreeByMode(root, effectiveMode));
      final closed = await cascadeCloseService.waitWindow(root);
      if (!closed) {
        MvdLog.instance.warn('close', 'closeApp aborted', {'rootId': root, 'mode': effectiveMode.name});
        onCloseAppAborted?.call();
        return false;
      }
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Subtree close modes.
  // ---------------------------------------------------------------------------

  Future<void> closeSubtreeByMode(int rootId, CloseMode mode) async {
    MvdLog.instance.info('close', 'closeSubtreeByMode', {
      'rootId': rootId,
      'mode': mode.name,
      'descendants': registry.descendantWindowIdsDeepestFirst(rootId).join(','),
      'pendingCreates': lifecycle.hasPendingCreates(),
    });
    if (lifecycle.hasPendingCreates()) {
      await lifecycle.waitAllCreatingViews();
    }

    switch (mode) {
      case CloseMode.none:
        _removeViewsNone(rootId);
      case CloseMode.softCascade:
        await _removeViewsCascade(rootId);
      case CloseMode.forceSecondary:
        await _removeSecondaryViewsForce(rootId);
      case CloseMode.destroy:
        await _destroyAllViewsForce(rootId);
    }
  }

  void _removeViewsNone(int rootId) {
    delegate.invoke<void>(rootId, () => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _removeViewsCascade(int rootId) async {
    final descendants = registry.descendantWindowIdsDeepestFirst(rootId).toList()..sort();
    MvdLog.instance.info('close', 'cascade order', {
      'rootId': rootId,
      'descendantsNewestFirst': descendants.reversed.join(','),
    });

    for (final id in descendants.reversed) {
      MvdLog.instance.info('close', 'cascade closing descendant', {'realId': id, 'rootId': rootId});
      final wait = delegate.invoke<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.softCloseWindow(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) {
        MvdLog.instance.warn('close', 'cascade aborted on descendant', {'realId': id, 'rootId': rootId});
        return;
      }
      if (!registry.isWindow(rootId)) {
        MvdLog.instance.error('close', 'cascade: parent destroyed before child cascade finished', {
          'rootId': rootId,
          'childId': id,
        });
      }
    }

    if (registry.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      MvdLog.instance.warn('close', 'cascade: descendants remain after child loop', {
        'rootId': rootId,
        'remaining': registry.descendantWindowIdsDeepestFirst(rootId).join(','),
      });
      return;
    }

    delegate.invoke<void>(rootId, () => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _removeSecondaryViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = registry.descendantWindowIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final wait = delegate.invoke<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    if (loopCycle < maxLoopCycles && registry.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      unawaited(_removeSecondaryViewsForce(rootId, loopCycle: loopCycle + 1));
      return;
    }

    delegate.invoke<void>(rootId, () => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _destroyAllViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = registry.descendantWindowIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final wait = delegate.invoke<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    if (loopCycle < maxLoopCycles && registry.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      unawaited(_destroyAllViewsForce(rootId, loopCycle: loopCycle + 1));
      return;
    }

    delegate.invoke<void>(rootId, () => _preConfirmCloseCallable(rootId, isForce: true), dialogSupports: true);
  }

  void _preConfirmCloseCallable(int viewId, {bool isForce = false}) {
    ffi.setPreConfirmClose(viewId, true);

    if (isForce) {
      onBeforeForceCloseApp?.call();
      ffi.forceCloseView(viewId);
      return;
    }

    if (Platform.isMacOS && delegate.isLastMacosRootView(viewId)) {
      _macosHideInsteadOfClose(viewId);
      cascadeCloseService.completeWindow(viewId);
      return;
    }

    ffi.softCloseWindow(viewId);
  }

  void _macosHideInsteadOfClose(int viewId) {
    destroyPopupsByParent(viewId);
    removeAllDialogsByParent(viewId);
    lifecycle.proxies.state.hide(viewId);
    ffi.setPreConfirmClose(viewId, false);
    cascadeCloseService.completeWindow(viewId);
  }

  int? get _anchorId => anchorViewId;
}
