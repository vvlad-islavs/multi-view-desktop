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
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/utils/calc_window_position.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

typedef ViewCreatedCallback = void Function(int viewId);

/// Shared open/wait helpers; [fade] controls open/close animations.
@internal
abstract class ViewOwnerBase {
  ViewOwnerBase(this.host, {required this.fade});

  final LifecycleViewsController host;
  final ViewOpenCloseAnimationPolicy fade;

  /// View-scoped native calls (invoke guard).
  ViewManagerProxies get proxies => host.proxies;

  /// Lifecycle-only FFI: create and close-policy hooks without a public proxy.
  FfiBridge get ffi => host.ffiBridge;

  Map<int, ViewCreateCompleter<int?>> get completers => host.createCompleters;

  static const int nativeCreateToken = 0;

  Future<void> fadeIn(int viewId) async {
    if (!fade.fadeInOnOpen) return;
    await host.viewAnimator.animate(
      onValue: (value) => proxies.appearance.setOpacity(viewId, value),
      duration: fade.openDuration,
      curve: fade.curve,
      fps: fade.fps,
    );
  }

  /// Fade-out step before native teardown; invoked by [ViewCloseService] and [close].
  Future<void> fadeOut(int viewId) async {
    if (!fade.fadeOutOnClose) return;
    await host.viewAnimator.animate(
      onValue: (value) => proxies.appearance.setOpacity(viewId, value),
      from: 1,
      to: 0,
      duration: fade.closeDuration,
      curve: fade.curve,
      fps: fade.fps,
    );
  }

  Future<void> close(int viewId);

  void throwIfNativeError(int? viewId, {required int errorToken}) {
    if (!CreateViewError.isErrorCode(viewId)) return;
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
    if (!fade.fadeInOnOpen) {
      proxies.state.show(viewId);
      return;
    }
    proxies.appearance.setOpacity(viewId, 0);
    proxies.state.show(viewId);

    await host.viewAnimator.animate(
      onValue: (value) => proxies.appearance.setOpacity(viewId, value),
      duration: fade.openDuration,
      curve: fade.curve,
      fps: fade.fps,
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
      pos = calcWindowPosition(windowSize, opts.alignment!);
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
