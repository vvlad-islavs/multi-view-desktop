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
    MultiViewDesktop.appShell.patch(AppShellPatch(themeMode: mode));
    notifyListeners();

    // Broadcast so every window can update its native brightness.
    MultiViewDesktop.communicator.broadcast({'type': 'themeMode', 'value': mode.name});
  }
}

class SharedParams extends ChangeNotifier {
  bool _isHideAppFromTaskbar = false;
  CloseMode _closeMode = CloseMode.none;
  int? _anchorId;

  bool get isHideAppFromTaskbar => _isHideAppFromTaskbar;
  CloseMode get closeMode => _closeMode;
  int? get anchorId => _anchorId;

  set isHideAppFromTaskbar(bool newValue) {
    _isHideAppFromTaskbar = newValue;
    notifyListeners();
  }

  set closeMode(CloseMode newValue) {
    _closeMode = newValue;
    notifyListeners();
  }

  set anchorId(int? id) {
    _anchorId = id;
    notifyListeners();
  }
}

/// Single global instance shared by all views.
final themeConfig = ThemeConfig();
final sharedConfig = SharedParams();
