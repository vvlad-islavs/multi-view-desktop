import 'package:flutter/foundation.dart' show internal;
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

  final Size? size;
  final Size? minimumSize;
  final Size? maximumSize;
  final Alignment? alignment;
  final Color? backgroundColor;
  final bool? hideAppFromTaskbar;
  final TitleBarStyle? titleBarStyle;
  final bool? windowButtonVisibility;
  final String? title;
  final bool? fullScreen;
  final bool? alwaysOnTop;

}
