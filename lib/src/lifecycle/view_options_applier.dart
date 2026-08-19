import 'dart:io';

import 'package:multiview_desktop/multiview_desktop.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';

/// Maps [WindowOptions] / [DialogOptions] to native FFI calls.
///
/// Lives on [LifecycleViewsController] so creators stay create-only and
/// `view_root` can reuse the same applier after integration.
@internal
class ViewOptionsApplier {
  ViewOptionsApplier({
    required FfiBridge ffi,
    required void Function(bool hide, {int? viewId}) hideAppFromTaskbar,
  })  : _ffi = ffi,
        _hideAppFromTaskbar = hideAppFromTaskbar;

  final FfiBridge _ffi;
  final void Function(bool hide, {int? viewId}) _hideAppFromTaskbar;

  void applyWindow(int viewId, WindowOptions opts) {
    if (opts.size != null) {
      _ffi.setSize(viewId, size: opts.size!);
    }
    if (opts.alignment != null) {
      _ffi.setAlignment(viewId, alignment: opts.alignment!);
    }
    if (opts.backgroundColor != null) {
      _ffi.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.minimumSize != null) {
      _ffi.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      _ffi.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.title != null) {
      _ffi.setTitle(viewId, title: opts.title!);
    }
    if (opts.titleBarStyle != null) {
      _ffi.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility ?? true,
        maximizeVisibility: opts.windowButtonVisibility ?? true,
        minimizeVisibility: opts.windowButtonVisibility ?? true,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffi.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
    if (opts.fullScreen != null) {
      _ffi.setFullScreen(viewId, isFullScreen: opts.fullScreen!);
    }
    if (opts.hideAppFromTaskbar ?? false) {
      _hideAppFromTaskbar(true);
    }
  }

  void applyDialog(int viewId, DialogOptions opts) {
    if (!Platform.isWindows && opts.size != null) {
      _ffi.setSize(viewId, size: opts.size!);
    }
    if (opts.backgroundColor != null) {
      _ffi.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.minimumSize != null) {
      _ffi.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      _ffi.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.isResizable != null) {
      _ffi.setResizable(viewId, opts.isResizable!);
    }
    if (opts.title != null) {
      _ffi.setTitle(viewId, title: opts.title!);
    }
    if (opts.titleBarStyle != null) {
      _ffi.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility ?? true,
        minimizeVisibility: false,
        maximizeVisibility: false,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffi.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
  }
}
