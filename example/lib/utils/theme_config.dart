import 'package:material_ui/material_ui.dart';

import 'package:multiview_desktop/multiview_desktop.dart';

/// Application-wide theme configuration shared across all windows.
///
/// Because all windows run in the same Dart isolate, this is a plain
/// `ChangeNotifier` with no IPC or platform channels needed.
class ThemeConfig extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    MultiViewDesktop.appShell.patch(AppShellPatch(themeMode: mode));
    final Brightness brightness;
    if (_themeMode == ThemeMode.system) {
      brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    } else if (_themeMode == ThemeMode.dark) {
      brightness = Brightness.dark;
    } else {
      brightness = Brightness.light;
    }
    // Native title-bar / caption chrome for every open window.
    MultiViewDesktop.setGlobalBrightness(brightness);
    notifyListeners();

    MultiViewDesktop.communicator.broadcast({'type': 'themeMode', 'value': mode.name});
  }
}

class SharedParams extends ChangeNotifier {
  bool _isHideAppFromTaskbar = false;
  CloseMode _closeMode = CloseMode.softCascade;
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
