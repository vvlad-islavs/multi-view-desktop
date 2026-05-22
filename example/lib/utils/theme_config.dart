import 'package:flutter/material.dart';

import 'package:multiview_desktop/multiview_desktop.dart';

/// Application-wide theme configuration shared across all windows.
///
/// Because all windows run in the same Dart isolate, this is a plain
/// [ChangeNotifier] with no IPC or platform channels needed.
class ThemeConfig extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    // Broadcast so every window can update its native brightness.
    WindowCommunicator.broadcast({'type': 'themeMode', 'value': mode.name});
  }
}

/// Single global instance shared by all views.
final themeConfig = ThemeConfig();
