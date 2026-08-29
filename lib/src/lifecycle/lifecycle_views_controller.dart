import 'dart:async';

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/lifecycle/view_animation_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_close_delegate.dart';
import 'package:multiview_desktop/src/lifecycle/view_registry.dart';
import 'package:multiview_desktop/src/lifecycle/view_close_service.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';
import 'package:multiview_desktop/src/lifecycle/view_options_applier.dart';
import 'package:multiview_desktop/src/lifecycle/view_owner_base.dart';
import 'package:multiview_desktop/src/lifecycle/view_owners.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';

export 'view_animator.dart' show ViewAnimator;
export 'view_animation_controller.dart' show ViewAnimationController;
export 'view_animation_override.dart' show ViewAnimationOverride;
export 'view_registry.dart' show ViewRegistry;
export 'view_close_delegate.dart' show ViewCloseDelegate;
export 'view_close_service.dart' show ViewCloseService;
export 'view_owner_base.dart' show ViewCreatedCallback;
export 'view_options_applier.dart' show ViewOptionsApplier;

/// Central hub for native view lifecycle: open owners, close service, first-frame barrier.
///
/// Intended to replace inline logic in `_ViewsManagerImpl`.
@internal
class LifecycleViewsController {
  LifecycleViewsController({
    required this.registry,
    required this.proxies,
    required this.ffiBridge,
    required ViewCloseDelegate closeDelegate,
    required void Function(int parentId, {required int dialogId, required bool isModal}) registerDialog,
    required bool Function(int parentId) hasPendingDialogCreate,
    required bool Function(int parentId) hasModalDialog,
    required this.animation,
    required this.animationController,
    WindowPositionCalculator? positionCalculator,
    ViewCloseService? closeServiceOverride,
    CascadeCloseService? cascadeCloseService,
    void Function(int viewId, dynamic dialogRes)? onDialogCloseResult,
    void Function(int viewId)? onPopupDestroyed,
    VoidCallback? onBeforeCloseApp,
    VoidCallback? onCloseAppAborted,
    VoidCallback? onBeforeForceCloseApp,
  }) : positionCalculator = positionCalculator ?? WindowPositionCalculator.instance,
       _registerDialog = registerDialog,
       _hasPendingDialogCreate = hasPendingDialogCreate,
       _hasModalDialog = hasModalDialog {
    optionsApplier = ViewOptionsApplier(ffi: ffiBridge);
    windowOwner = WindowOwner(this);
    childWindowOwner = ChildWindowOwner(this);
    modelessDialogOwner = ModelessDialogOwner(this);
    modalDialogOwner = ModalDialogOwner(this);
    popupOwner = PopupOwner(this);
    closeService =
        closeServiceOverride ??
        ViewCloseService(
          lifecycle: this,
          delegate: closeDelegate,
          cascadeCloseService: cascadeCloseService,
          onDialogCloseResult: onDialogCloseResult,
          onPopupDestroyed: onPopupDestroyed,
          onBeforeCloseApp: onBeforeCloseApp,
          onCloseAppAborted: onCloseAppAborted,
          onBeforeForceCloseApp: onBeforeForceCloseApp,
        );
  }

  final ViewRegistry registry;

  /// View-scoped native calls (invoke guard + registry checks).
  final ViewManagerProxies proxies;

  /// Lifecycle-only FFI: create windows/dialogs/popups and close-policy hooks.
  final FfiBridge ffiBridge;

  final ViewAnimationController animationController;

  final WindowPositionCalculator positionCalculator;

  final ViewAnimationConfig animation;

  ViewOpenCloseAnimationPolicy get windowOpenCloseAnimation => animation.windowOpenClose;

  ViewOpenCloseAnimationPolicy get modelessDialogOpenCloseAnimation => animation.modelessDialogOpenClose;

  ViewOpenCloseAnimationPolicy get modalDialogOpenCloseAnimation => animation.modalDialogOpenClose;

  ViewOpenCloseAnimationPolicy get popupOpenCloseAnimation => animation.popupOpenClose;

  final void Function(int parentId, {required int dialogId, required bool isModal}) _registerDialog;
  final bool Function(int parentId) _hasPendingDialogCreate;
  final bool Function(int parentId) _hasModalDialog;

  /// Pending views keyed by viewId or auxiliary dialog-create token.
  final Map<int, ViewCreateCompleter<int?>> createCompleters = {};
  int _nextToken = 0;

  late final ViewOptionsApplier optionsApplier;
  late final ViewCloseService closeService;

  late final WindowOwner windowOwner;
  late final ChildWindowOwner childWindowOwner;
  late final ModelessDialogOwner modelessDialogOwner;
  late final ModalDialogOwner modalDialogOwner;
  late final PopupOwner popupOwner;

  int allocateToken() => _nextToken++;

  void registerDialog(int parentId, {required int dialogId, required bool isModal}) {
    _registerDialog(parentId, dialogId: dialogId, isModal: isModal);
  }

  bool isWindowRegistered(int viewId) => registry.isWindow(viewId);

  bool isViewRegistered(int viewId) => registry.isManaged(viewId);

  bool hasPendingDialogCreate(int parentId) => _hasPendingDialogCreate(parentId);

  bool hasModalDialog(int parentId) => _hasModalDialog(parentId);

  void applyWindowOptions(int viewId, WindowOptions opts) => optionsApplier.applyWindow(viewId, opts);

  void applyDialogOptions(int viewId, DialogOptions opts) => optionsApplier.applyDialog(viewId, opts);

  // ---------------------------------------------------------------------------
  // Typed open API.
  // ---------------------------------------------------------------------------

  Future<int> openWindow({
    WindowOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) =>
      windowOwner.open(options: options, onCreated: onCreated, animation: animation);

  Future<int> openChildWindow({
    required int parentId,
    WindowOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) =>
      childWindowOwner.open(
        parentId: parentId,
        options: options,
        onCreated: onCreated,
        animation: animation,
      );

  Future<int> openModelessDialog({
    required int parentId,
    DialogOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) =>
      modelessDialogOwner.open(
        parentId: parentId,
        options: options,
        onCreated: onCreated,
        animation: animation,
      );

  Future<int> openModalDialog({
    required int parentId,
    DialogOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) =>
      modalDialogOwner.open(
        parentId: parentId,
        options: options,
        onCreated: onCreated,
        animation: animation,
      );

  int openPopup({
    required int parentId,
    required Size size,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) =>
      popupOwner.open(parentId: parentId, size: size, onCreated: onCreated, animation: animation);

  // ---------------------------------------------------------------------------
  // First-frame barrier (call from ViewRoot post-frame callback).
  // ---------------------------------------------------------------------------

  void firstFrameCbComplete(int viewId) {
    createCompleters[viewId]?.complete();
    createCompleters.remove(viewId);
  }

  bool hasPendingCreates({List<int> excludeTokens = const []}) {
    return createCompleters.entries.any((e) => !excludeTokens.contains(e.key) && !e.value.isCompleted);
  }

  Future<void> waitAllCreatingViews({List<int> excludeTokens = const []}) async {
    if (!hasPendingCreates(excludeTokens: excludeTokens)) return;
    try {
      for (final key in createCompleters.keys.toList()..sort()) {
        if (excludeTokens.contains(key)) continue;
        final completer = createCompleters[key];
        if (!(completer?.isCompleted ?? true)) {
          await completer?.future;
        }
      }
    } catch (_) {
      // Non-critical: parallel create failure is surfaced by the caller.
    }
  }

  Future<int?> waitFirstFrame(int viewId, {int timeoutMs = 10000}) async {
    return createCompleters[viewId]?.future.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () {
        createCompleters[viewId]?.complete(CreateViewError.timeout.code);
        return CreateViewError.timeout.code;
      },
    );
  }
}
