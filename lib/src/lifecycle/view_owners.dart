import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';
import 'package:multiview_desktop/src/lifecycle/view_owner_base.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';

/// Independent top-level window owner.
@internal
class WindowOwner extends ViewOwnerBase {
  WindowOwner(super.host) : super(fade: host.windowOpenCloseAnimation, openCloseType: ViewAnimationType.createWindow);

  Future<int> open({
    WindowOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) async {
    final opts = options ?? WindowOptions();
    final viewId = createNativeWindow(opts: opts);
    host.applyWindowOptions(viewId, opts);
    onCreated(viewId);
    trackUntilFirstFrame(viewId, parentId: null, isDialog: false);
    host.animationController.stageSoftOverride(viewId, ViewAnimationType.createWindow, animation);
    await showAfterFirstFrame(viewId);
    return viewId;
  }

  @override
  Future<void> close(int viewId) => fadeOut(viewId);
}

/// Child window owner (`parentId` set at native create).
@internal
class ChildWindowOwner extends ViewOwnerBase {
  ChildWindowOwner(super.host)
    : super(fade: host.windowOpenCloseAnimation, openCloseType: ViewAnimationType.createWindow);

  Future<int> open({
    required int parentId,
    WindowOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) async {
    if (!host.isWindowRegistered(parentId)) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent window is not registered');
    }

    final opts = options ?? WindowOptions();
    final viewId = createNativeWindow(opts: opts, parentId: parentId);
    host.applyWindowOptions(viewId, opts);
    onCreated(viewId);
    trackUntilFirstFrame(viewId, parentId: parentId, isDialog: false);
    host.animationController.stageSoftOverride(viewId, ViewAnimationType.createWindow, animation);
    await showAfterFirstFrame(viewId);
    return viewId;
  }

  @override
  Future<void> close(int viewId) => fadeOut(viewId);
}

/// Shared dialog open pipeline.
@internal
class DialogOwner extends ViewOwnerBase {
  DialogOwner(super.host, {required this.modal, required ViewOpenCloseAnimationPolicy fadeConfig})
    : super(fade: fadeConfig, openCloseType: ViewAnimationType.createDialog);

  final bool modal;

  Future<int> open({
    required int parentId,
    required DialogOptions opts,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) async {
    if (!host.isWindowRegistered(parentId)) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent window is not registered');
    }
    if (host.hasPendingDialogCreate(parentId)) {
      throw Exception('Create error: "Create dialog" was called while another dialog is creating in the same window');
    }
    if (modal && host.hasModalDialog(parentId)) {
      throw Exception('Create error: One window can has only one modal dialog');
    }

    final modalFinishedToken = host.allocateToken();
    completers[modalFinishedToken] = ViewCreateCompleter.dialog(modalFinishedToken, parentId: parentId);

    await waitAllCreatingViews(excludeTokens: [modalFinishedToken]);

    final windowSize = Size(opts.size?.width ?? 400.0, opts.size?.height ?? 300.0);
    int? newViewId;

    try {
      Offset? pos;
      if (!modal) {
        final parentBounds = host.proxies.position.getBounds(parentId);
        pos = positionCalculator.calcWindowPositionByParent(
          Alignment.center,
          windowSize: windowSize,
          parentBounds: parentBounds,
        );
      }

      newViewId = ffi.createDialog(
        token: ViewOwnerBase.nativeCreateToken,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        isModal: modal,
        pos: pos,
        parentId: parentId,
      );
    } catch (e, st) {
      completers[modalFinishedToken]?.complete(CreateViewError.unhandled.code);
      completers.remove(modalFinishedToken);
      throw Exception(
        'Failed to create dialog window, tokenId: ${ViewOwnerBase.nativeCreateToken}. Error: $e, stack: $st',
      );
    }

    throwIfNativeError(newViewId, errorToken: modalFinishedToken);
    final viewId = newViewId;

    host.registerDialog(parentId, dialogId: viewId, isModal: modal);
    host.applyDialogOptions(viewId, opts);
    onCreated(viewId);
    trackUntilFirstFrame(viewId, parentId: parentId, isDialog: true);

    await waitFirstFrame(viewId);

    if (opts.showOnInit ?? true) {
      if (modal) {
        await Future<void>.delayed(const Duration(milliseconds: 35));
        if (Platform.isMacOS) {
          ffi.completeModalDialogCreate(viewId);
        }
      } else {
        host.animationController.stageSoftOverride(viewId, ViewAnimationType.createDialog, animation);
        await showWithFadeIn(viewId);
      }
    }

    completers[modalFinishedToken]?.complete();
    completers.remove(modalFinishedToken);
    return viewId;
  }

  @override
  Future<void> close(int viewId) async {
    final isModal = host.registry.isModalDialog(viewId);
    if (isModal) return;
    return fadeOut(viewId);
  }
}

/// Modeless dialog owner.
@internal
class ModelessDialogOwner extends ViewOwnerBase {
  ModelessDialogOwner(super.host)
    : _delegate = DialogOwner(host, modal: false, fadeConfig: host.modelessDialogOpenCloseAnimation),
      super(fade: host.modelessDialogOpenCloseAnimation, openCloseType: ViewAnimationType.createDialog);

  final DialogOwner _delegate;

  Future<int> open({
    required int parentId,
    DialogOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) => _delegate.open(parentId: parentId, opts: _asModeless(options), onCreated: onCreated, animation: animation);

  @override
  Future<void> close(int viewId) => _delegate.close(viewId);

  DialogOptions _asModeless(DialogOptions? options) {
    final base = options ?? DialogOptions();
    return DialogOptions(
      size: base.size,
      minimumSize: base.minimumSize,
      maximumSize: base.maximumSize,
      isResizable: base.isResizable,
      title: base.title,
      modal: false,
      titleBarStyle: base.titleBarStyle,
      windowButtonVisibility: base.windowButtonVisibility,
      backgroundColor: base.backgroundColor,
      alwaysOnTop: base.alwaysOnTop,
      showOnInit: base.showOnInit,
      shellOverrides: base.shellOverrides,
    );
  }
}

/// Modal dialog owner — no fade (native sheet animation on macOS).
@internal
class ModalDialogOwner extends ViewOwnerBase {
  ModalDialogOwner(super.host)
    : _delegate = DialogOwner(host, modal: true, fadeConfig: host.modalDialogOpenCloseAnimation),
      super(fade: host.modalDialogOpenCloseAnimation, openCloseType: ViewAnimationType.createDialog);

  final DialogOwner _delegate;

  Future<int> open({
    required int parentId,
    DialogOptions? options,
    required ViewCreatedCallback onCreated,
    AnimationSettings? animation,
  }) => _delegate.open(parentId: parentId, opts: _asModal(options), onCreated: onCreated, animation: animation);

  @override
  Future<void> close(int viewId) => _delegate.close(viewId);

  DialogOptions _asModal(DialogOptions? options) {
    final base = options ?? DialogOptions();
    return DialogOptions(
      size: base.size,
      minimumSize: base.minimumSize,
      maximumSize: base.maximumSize,
      isResizable: base.isResizable,
      title: base.title,
      modal: true,
      titleBarStyle: base.titleBarStyle,
      windowButtonVisibility: base.windowButtonVisibility,
      backgroundColor: base.backgroundColor,
      alwaysOnTop: base.alwaysOnTop,
      showOnInit: base.showOnInit,
      shellOverrides: base.shellOverrides,
    );
  }
}

/// Popup owner — open/close fade not configured yet.
@internal
class PopupOwner extends ViewOwnerBase {
  PopupOwner(super.host)
    : super(fade: ViewOpenCloseAnimationPolicy.disabled, openCloseType: ViewAnimationType.createWindow);

  int open({required int parentId, required Size size, required ViewCreatedCallback onCreated}) {
    if (!host.isViewRegistered(parentId)) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent view is not registered');
    }

    int? newViewId;
    try {
      newViewId = ffi.createPopupWindow(token: ViewOwnerBase.nativeCreateToken, parentId: parentId, windowSize: size);
    } catch (e, st) {
      throw Exception(
        'Failed to create popup window, tokenId: ${ViewOwnerBase.nativeCreateToken}. Error: $e, stack: $st',
      );
    }

    throwIfNativeError(newViewId, errorToken: ViewOwnerBase.nativeCreateToken);

    ffi.setPreConfirmClose(newViewId, true);
    ffi.setPreventClose(newViewId, isPreventClose: false);
    ffi.setConfirmClose(newViewId, isConfirm: true);

    onCreated(newViewId);
    return newViewId;
  }

  @override
  Future<void> close(int viewId) async {
    host.closeService.destroyPopup(viewId);
  }
}
