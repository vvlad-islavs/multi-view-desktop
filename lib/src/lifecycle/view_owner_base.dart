import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/lifecycle/lifecycle_views_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

typedef ViewCreatedCallback = void Function(int viewId);

/// Shared open/wait helpers; [fade] controls open/close animations.
@internal
abstract class ViewOwnerBase {
  ViewOwnerBase(this.host, {required this.fade, required this.openCloseType});

  final LifecycleViewsController host;
  final ViewOpenCloseAnimationPolicy fade;

  /// Staged override / animate* type for this owner's open/close fade.
  final ViewAnimationType openCloseType;

  /// View-scoped native calls (invoke guard).
  ViewManagerProxies get proxies => host.proxies;

  /// Lifecycle-only FFI: create and close-policy hooks without a public proxy.
  FfiBridge get ffi => host.ffiBridge;

  WindowPositionCalculator get positionCalculator => host.positionCalculator;

  Map<int, ViewCreateCompleter<int?>> get completers => host.createCompleters;

  static const int nativeCreateToken = 0;

  ViewAnimationType get _closeType => switch (openCloseType) {
        ViewAnimationType.createWindow => ViewAnimationType.closeWindow,
        ViewAnimationType.createDialog => ViewAnimationType.closeDialog,
        ViewAnimationType.createPopup => ViewAnimationType.closePopup,
        _ => openCloseType,
      };

  Future<void> fadeOut(int viewId) {
    return host.animationController.animateClose(
      viewId,
      type: _closeType,
      policy: fade,
    );
  }

  Future<void> close(int viewId);

  void throwIfNativeError(int? viewId, {required int errorToken}) {
    if (!CreateViewError.isErrorCode(viewId)) return;
    MvdLog.instance.error('create', 'native create failed', {
      'code': viewId,
      'token': errorToken,
      'error': CreateViewError.fromCode(viewId).name,
    });
    throw Exception(CreateViewError.fromCode(viewId).message(errorToken));
  }

  Future<void> waitAllCreatingViews({List<int> excludeTokens = const []}) =>
      host.waitAllCreatingViews(excludeTokens: excludeTokens);

  Future<int?> waitFirstFrame(int viewId, {int timeoutMs = 10000}) => host.waitFirstFrame(viewId, timeoutMs: timeoutMs);

  void trackUntilFirstFrame(int viewId, {required int? parentId, required bool isDialog}) {
    completers[viewId] = isDialog
        ? ViewCreateCompleter.dialog(viewId, parentId: parentId!)
        : ViewCreateCompleter.window(viewId, parentId: parentId);
  }

  /// Shows the window and runs open fade in parallel (opacity 0 → 1).
  Future<void> showWithFadeIn(int viewId) async {
    await host.animationController.animateOpen(
      viewId,
      type: openCloseType,
      policy: fade,
    );
  }

  Future<void> showAfterFirstFrame(int viewId) async {
    await waitFirstFrame(viewId);
    await showWithFadeIn(viewId);
  }

  int createNativeWindow({required WindowOptions opts, int? parentId}) {
    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = positionCalculator.calcWindowPosition(windowSize, opts.alignment!);
    }

    final newViewId = ffi.createWindow(
      token: nativeCreateToken,
      title: opts.title ?? '',
      titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
      windowButtonVisibility: opts.windowButtonVisibility ?? true,
      windowSize: windowSize,
      pos: pos,
      parentId: parentId,
    );

    if (parentId != null) {
      ffi.setPreConfirmClose(parentId, false);
    }

    throwIfNativeError(newViewId, errorToken: nativeCreateToken);
    return newViewId;
  }
}
