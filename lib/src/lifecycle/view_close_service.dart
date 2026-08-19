import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';
import 'package:multiview_desktop/src/lifecycle/lifecycle_views_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_close_host.dart';
import 'package:multiview_desktop/src/lifecycle/view_owner_base.dart';

/// Soft/force/destroy close orchestration mirroring `_ViewsManagerImpl`.
@internal
class ViewCloseService {
  ViewCloseService({
    required this.lifecycle,
    required this.closeHost,
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
  final ViewCloseHost closeHost;
  final ViewOwnerBase? Function(int viewId) resolveOwner;
  final CascadeCloseService cascadeCloseService;

  /// Anchor view for close-policy promotion (mirrors `_realAnchorId`).
  int? anchorViewId;

  void Function(int viewId, dynamic dialogRes)? onDialogCloseResult;
  void Function(int viewId)? onPopupDestroyed;
  VoidCallback? onBeforeCloseApp;
  VoidCallback? onCloseAppAborted;
  VoidCallback? onBeforeForceCloseApp;

  FfiBridge get ffi => lifecycle.ffiBridge;

  CloseMode closeMode = CloseMode.softCascade;

  // ---------------------------------------------------------------------------
  // Native close events (wire from `_onStaticCall`).
  // ---------------------------------------------------------------------------

  Future<void> handeFirstCloseStep(int viewId) async {
    final nextAnchorCandidates = closeHost.anchorCandidatesExcluding(excludingViewId: viewId)..sort();
    if (viewId == _anchorId && nextAnchorCandidates.isNotEmpty && !closeHost.enableDynamicAnchor) {
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
    await resolveOwner(viewId)?.close(viewId);

    closeHost.destroyPopupsByParent(viewId);
    closeHost.removeAllDialogsByParent(viewId);
    closeHost.disposeView(viewId);

    ffi.setConfirmClose(viewId, isConfirm: true);
    if (closeHost.isModalDialog(viewId)) {
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
    final parents = [...closeHost.parentWindowChain(viewId), ...closeHost.parentDialogChain(viewId), viewId];
    for (final parent in parents) {
      ffi.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  void closeView<T>(int viewId, {T? dialogRes}) {
    if (!_managedLive(viewId)) return;

    if (closeHost.isDialog(viewId)) {
      onDialogCloseResult?.call(viewId, dialogRes);
      _runNative(() => ffi.destroyModalDialog(viewId));
      closeHost.disposeView(viewId);
      return;
    }

    _runNative(() => ffi.softCloseWindow(viewId));
  }

  void destroyPopup(int viewId) {
    if (!closeHost.isPopup(viewId)) return;
    try {
      _runNative(() => ffi.destroyModalDialog(viewId));
    } on PlatformException catch (e) {
      if (e.code != 'NO_WINDOW') rethrow;
    }
    onPopupDestroyed?.call(viewId);
  }

  Future<bool> closeApp({CloseMode? mode}) async {
    final effectiveMode = mode ?? closeMode;
    final allRoots = closeHost.rootWindowIds()..sort();

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
    final descendants = closeHost.descendantWindowIdsDeepestFirst(rootId).toList()..sort();

    for (final id in descendants.reversed) {
      final closed = await _closeManaged(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.softCloseWindow(id);
        return cascadeCloseService.waitWindow(id);
      });
      if (!closed) return;
    }

    if (closeHost.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      return;
    }

    _preConfirmCloseCallable(rootId, dialogSupported: true);
  }

  Future<void> _removeSecondaryViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = closeHost.descendantWindowIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final closed = await _closeManaged(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      if (!closed) return;
    }

    if (loopCycle < maxLoopCycles && closeHost.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      unawaited(_removeSecondaryViewsForce(rootId, loopCycle: loopCycle + 1));
      return;
    }

    _preConfirmCloseCallable(rootId, dialogSupported: true);
  }

  Future<void> _destroyAllViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = closeHost.descendantWindowIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final closed = await _closeManaged(id, () {
        cascadeCloseService.attachWindow(id);
        ffi.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      if (!closed) return;
    }

    if (loopCycle < maxLoopCycles && closeHost.descendantWindowIdsDeepestFirst(rootId).isNotEmpty) {
      unawaited(_destroyAllViewsForce(rootId, loopCycle: loopCycle + 1));
      return;
    }

    _preConfirmCloseCallable(rootId, isForce: true, dialogSupported: true);
  }

  void _preConfirmCloseCallable(int viewId, {bool isForce = false, bool dialogSupported = false}) {
    if (!_managedLive(viewId, dialogSupported: dialogSupported)) return;

    ffi.setPreConfirmClose(viewId, true);

    if (isForce) {
      onBeforeForceCloseApp?.call();
      ffi.forceCloseView(viewId);
      return;
    }

    if (Platform.isMacOS && closeHost.isLastMacosRootView(viewId)) {
      closeHost.onMacosHideInsteadOfClose(viewId);
      cascadeCloseService.completeWindow(viewId);
      return;
    }

    ffi.softCloseWindow(viewId);
  }

  Future<bool> _closeManaged(int viewId, Future<bool> Function() closeAction) async {
    if (!_managedLive(viewId, dialogSupported: true)) return false;
    return closeAction();
  }

  bool _managedLive(int viewId, {bool dialogSupported = false}) {
    if (dialogSupported) {
      if (!closeHost.isManaged(viewId)) return false;
    } else if (!closeHost.isWindow(viewId)) {
      return false;
    }
    return closeHost.hasLiveFlutterView(viewId);
  }

  T? _runNative<T>(T Function() action) {
    try {
      return action();
    } on PlatformException catch (e) {
      if (e.code == 'NO_WINDOW') return null;
      rethrow;
    }
  }

  int? get _anchorId => anchorViewId;
}
