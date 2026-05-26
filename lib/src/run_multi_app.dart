import 'package:flutter/foundation.dart';
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
/// are opened via [openWindow].
void runMultiApp(Widget home, {MultiAppConfig? config}) {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(createMultiViewRoot(home, config ?? MultiAppConfig.defaultConfig()));
}

class MultiAppConfig {
  final CloseMode mainCloseMode;
  final WindowOptions preferredOptions;

  MultiAppConfig._({this.mainCloseMode = CloseMode.cascade, this.preferredOptions = const WindowOptions()});

  factory MultiAppConfig({CloseMode? closeMode, WindowOptions? options}) =>
      MultiAppConfig._(mainCloseMode: closeMode ?? CloseMode.cascade, preferredOptions: options ?? WindowOptions());

  @internal
  factory MultiAppConfig.defaultConfig() => MultiAppConfig._();
}

enum CloseMode {
  /// soft close only main window.
  ///
  /// Cycle: close handle -> preventClose (if enabled)  -> confirm-close -> close window
  none,
  /// soft close all windows from last to first with full close-cycle
  ///
  /// Cycle: close handle -> preventClose (if enabled) -> confirm-close -> close window
  cascade,
  /// force close all secondary without close-cycle excluding main window
  force,
}

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
Future<void> openWindow(Widget child, {WindowOptions? options}) =>
    MultiViewDesktop.addWindow(child, options: options, parent: null);
