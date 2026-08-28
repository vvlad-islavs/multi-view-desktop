import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';
import 'package:multiview_desktop/src/lifecycle/lifecycle_views_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_owner_base.dart';

/// Soft/force/destroy close orchestration mirroring `_ViewsManagerImpl`.
@internal
class ViewCloseService {
  ViewCloseService({
    required this.lifecycle,
    required this.delegate,
    required this.resolveOwner,
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
  final ViewOwnerBase? Function(int viewId) resolveOwner;
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

  // ---------------------------------------------------------------------------
  // Native close events (wire from `_onStaticCall`).
  // ---------------------------------------------------------------------------

  Future<void> handeFirstCloseStep(int viewId) async {
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

  Future<void> handleLastCloseStep(int viewId) async {
    final isModalDialog = registry.isModalDialog(viewId);

    await resolveOwner(viewId)?.close(viewId);

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
    for (final parent in parents) {
      ffi.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  Future<bool> closeView<T>(int viewId, {T? dialogRes}) async {
    if (registry.isDialog(viewId)) {
      onDialogCloseResult?.call(viewId, dialogRes);
      if (registry.isModalDialog(viewId)) {
        delegate.invoke<void>(viewId, () => ffi.destroyModalDialog(viewId), dialogSupports: true);
        delegate.disposeView(viewId);
        return true;
      }
    }

    final wait = delegate.invoke<Future<bool>>(viewId, () {
      cascadeCloseService.attachWindow(viewId);
      ffi.softCloseWindow(viewId);
      return cascadeCloseService.waitWindow(viewId);
    }, dialogSupports: registry.isDialog(viewId));

    if (wait == null) return false;
    return await wait;
  }

  void destroyPopup(int viewId) {
    if (!registry.isPopup(viewId)) return;
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
    _preConfirmCloseCallable(rootId);
  }

  Future<void> _removeViewsCascade(int rootId) async {
    final descendants = registry.descendantWindowIdsDeepestFirst(rootId).toList()..sort();

    for (final id in descendants.reversed) {
      final wait = delegate.invoke<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.softCloseWindow(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    if (registry.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
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
