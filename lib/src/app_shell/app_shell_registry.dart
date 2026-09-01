import 'package:flutter/foundation.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';

import 'app_shell_patch.dart';
import 'app_shell_snapshot.dart';

/// Internal store for the live `AppShellSnapshot`.
///
/// Not exported from the public API. Use `AppShellController` instead.
@internal
class AppShellRegistry extends ChangeNotifier {
  AppShellSnapshot? _snapshot;

  AppShellSnapshot? get snapshot => _snapshot;

  void replace(AppShellSnapshot? next) {
    if (_snapshot == next) return;
    MvdLog.instance.info('shell', 'appShell snapshot replaced', {
      'kind': next?.kind.name,
      'themeMode': next?.themeMode,
      'locale': next?.locale,
    });
    _snapshot = next;
    notifyListeners();
  }

  void patch(AppShellPatch patch) => replace(patch.applyTo(_snapshot));
}
