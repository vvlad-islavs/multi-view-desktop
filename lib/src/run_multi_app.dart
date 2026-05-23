import 'package:flutter/widgets.dart';

import 'multi_view_desktop.dart';
import 'view_root.dart' show createMultiViewRoot;
import 'window_options.dart';

/// The entry point for a multiview_desktop application.
///
/// Replaces [runApp].  Internally calls [runWidget] with a [ViewCollection]
/// root that automatically manages all OS windows in a single Flutter engine
/// and a single Dart isolate.
///
/// ```dart
/// void main() {
///   runMultiApp(const MyApp());
/// }
/// ```
///
/// [home] is rendered in the initial (main) OS window.  Additional windows
/// are opened via [addWindow].
void runMultiApp(Widget home, {MultiAppConfig? config}) {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(createMultiViewRoot(home, config ?? _defaultConfig));
}

MultiAppConfig _defaultConfig = MultiAppConfig(closeMode: CloseMode.cascade);

class MultiAppConfig {
  final CloseMode closeMode;

  MultiAppConfig({required this.closeMode});
}

enum CloseMode { none, cascade, force }

/// Opens a new OS window showing [child].
///
/// This is a convenience shorthand for [MultiViewDesktop.addWindow].
/// Can be called from any part of the application, including callbacks
/// and timers with no [BuildContext].
///
/// ```dart
/// ElevatedButton(
///   onPressed: () => addWindow(const SettingsPage()),
///   child: const Text('Open settings'),
/// )
/// ```
Future<void> addWindow(Widget child, {WindowOptions? options}) => MultiViewDesktop.addWindow(child, options: options);
