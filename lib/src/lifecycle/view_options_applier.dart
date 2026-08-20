import 'dart:io';

import 'package:multiview_desktop/multiview_desktop.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';

/// Maps [WindowOptions] / [DialogOptions] to native FFI during view creation.
///
/// Uses [FfiBridge] directly because options are applied before the view is
/// registered in [ViewRegistry] (proxy invoke guards would skip every call).
@internal
class ViewOptionsApplier {
  ViewOptionsApplier({required FfiBridge ffi}) : _ffi = ffi;

  final FfiBridge _ffi;

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
        closeVisibility: opts.windowButtonVisibility!,
        maximizeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: opts.windowButtonVisibility!,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffi.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
    if (opts.fullScreen != null) {
      _ffi.setFullScreen(viewId, isFullScreen: opts.fullScreen!);
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
        closeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: false,
        maximizeVisibility: false,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffi.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
  }
}
