import 'package:flutter/material.dart';

import 'app_shell/view_shell_overrides.dart';
import 'title_bar_style.dart';

sealed class BaseOptions {
  const BaseOptions({
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.backgroundColor,
    this.titleBarStyle,
    this.windowButtonVisibility,
    this.title,
    this.fullScreen,
    this.alwaysOnTop,
    this.shellOverrides,
  });

  /// Initial content size in logical pixels. Defaults to 800x600 when omitted.
  final Size? size;

  /// Minimum resizable size enforced by the OS window.
  final Size? minimumSize;

  /// Maximum resizable size enforced by the OS window.
  final Size? maximumSize;

  /// Native window background color shown behind Flutter content.
  final Color? backgroundColor;

  /// When `true`, hides the entire application icon from the dock / taskbar.
  /// Initial title-bar style; use `TitleBarStyle.hidden` for frameless chrome.
  final TitleBarStyle? titleBarStyle;

  /// Whether traffic-light / caption buttons are visible when the bar is hidden.
  final bool? windowButtonVisibility;

  /// Native window title string.
  final String? title;

  /// Whether the window starts in full-screen mode.
  final bool? fullScreen;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;

  /// Per-view overrides merged on top of `MultiViewDesktop.appShell`.
  ///
  /// Set `ViewShellOverrides.appearance` for theme or locale on this window only.
  /// Set `ViewShellOverrides.routerConfig`, `ViewShellOverrides.home`, or `routes`
  /// for a dedicated navigator or router stack on this view.
  final ViewShellOverrides? shellOverrides;
}

/// Pass to `openWindow` to control initial appearance and position.
class WindowOptions extends BaseOptions {
  const WindowOptions({
    super.size,
    super.minimumSize,
    super.maximumSize,
    this.alignment = Alignment.center,
    super.backgroundColor,
    this.hideAppFromTaskbar,
    super.titleBarStyle,
    super.windowButtonVisibility,
    super.title,
    super.fullScreen,
    super.alwaysOnTop,
    super.shellOverrides,
  });

  /// Where to place the window on the display under the cursor (or primary).
  final Alignment? alignment;

  /// When `true`, hides the entire application icon from the dock / taskbar.
  final bool? hideAppFromTaskbar;
}

/// Configuration for a dialog opened via `openDialog`.
///
/// Dialogs differ from regular windows:
/// - They always require a parent (`openDialog` needs `parentContext`).
/// - They close automatically when the parent closes, regardless of `CloseMode`.
/// - Full-screen mode is not available.
/// - They are hidden from the taskbar and Mission Control on creation.
/// - They are centered over the parent at creation time.
///
/// Set `modal` to true to block the parent at the OS level while the dialog is
/// open. Add `DialogModalLayer` in the parent for a visual scrim in Flutter.
class DialogOptions extends BaseOptions {
  const DialogOptions({
    super.size,
    super.minimumSize,
    super.maximumSize,
    this.isResizable,
    super.title,
    this.modal,
    super.titleBarStyle,
    super.windowButtonVisibility,
    super.backgroundColor,
    super.alwaysOnTop,
    this.showOnInit,
    super.shellOverrides,
  });

  /// Whether the user can resize the dialog by dragging edges.
  final bool? isResizable;

  /// When true, the parent window is blocked at the OS level while this dialog
  /// is open (macOS sheet, Windows owner chain, Linux transient and input lock).
  /// `DialogModalLayer` in the parent adds a Flutter scrim; the scrim alone does
  /// not block OS input.
  final bool? modal;

  /// Whether the window is shown right after creation. Defaults to true.
  final bool? showOnInit;
}
