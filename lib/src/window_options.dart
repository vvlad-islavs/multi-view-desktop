import 'package:flutter/material.dart';

import 'title_bar_style.dart';

/// Initial configuration applied to a window when it is first created.
///
/// Pass to [addWindow] to control the initial appearance and position.
class WindowOptions {
  const WindowOptions({
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.alignment = Alignment.center,
    this.backgroundColor,
    this.hideAppFromTaskbar,
    this.titleBarStyle,
    this.windowButtonVisibility,
    this.title,
    this.fullScreen,
    this.alwaysOnTop,
  });

  /// Initial content size in logical pixels. Defaults to 800x600 when omitted.
  final Size? size;

  /// Minimum resizable size enforced by the OS window.
  final Size? minimumSize;

  /// Maximum resizable size enforced by the OS window.
  final Size? maximumSize;

  /// Where to place the window on the display under the cursor (or primary).
  final Alignment? alignment;

  /// Native window background color shown behind Flutter content.
  final Color? backgroundColor;

  /// When `true`, hides the entire application icon from the dock / taskbar.
  final bool? hideAppFromTaskbar;

  /// Initial title-bar style; use [TitleBarStyle.hidden] for frameless chrome.
  final TitleBarStyle? titleBarStyle;

  /// Whether traffic-light / caption buttons are visible when the bar is hidden.
  final bool? windowButtonVisibility;

  /// Native window title string.
  final String? title;

  /// Whether the window starts in full-screen mode.
  final bool? fullScreen;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;
}
