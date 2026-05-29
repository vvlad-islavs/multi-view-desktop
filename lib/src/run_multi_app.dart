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
  runWidget(createMultiViewRoot(home, config ?? MultiAppConfig._defaultConfig()));
}

/// Application-wide settings passed to [runMultiApp].
class MultiAppConfig {
  /// Strategy used when closes the main window (see [CloseMode]).
  final CloseMode mainCloseMode;

  /// Default [WindowOptions] merged into every new window (per-window options override).
  final WindowOptions globalOptions;

  MultiAppConfig._({this.mainCloseMode = CloseMode.cascade, this.globalOptions = const WindowOptions()});

  /// Creates configuration for [runMultiApp].
  ///
  /// [closeMode] applies when the main window's close button is pressed.
  /// [globalOptions] are applied to the main window at startup and merged into [openWindow].
  factory MultiAppConfig({CloseMode closeMode = CloseMode.cascade, WindowOptions? globalOptions}) =>
      MultiAppConfig._(mainCloseMode: closeMode, globalOptions: globalOptions ?? WindowOptions());

  factory MultiAppConfig._defaultConfig() => MultiAppConfig._();
}

/// How closing the main window affects other open windows.
enum CloseMode {
  /// Close only main window through the normal soft-close cycle
  /// (prevent-close -> confirm-close -> destroy).
  none,

  /// Soft-close secondary windows one by one (newest first), then the main window.
  /// Each window runs the full close cycle; use [MultiViewDesktop.cancelCascadeClose]
  /// to abort from a confirmation dialog.
  cascade,

  /// Force-close all secondary windows immediately, then soft-close the main window.
  forceSecondary,

  /// Force-close all windows without running the soft-close cycle.
  destroy,

  /// Only for macOS. On other platforms will be used `CloseMode.cascade`.
  ///
  /// macOS: hide last window (main) instead of closing (app stays in the dock), `CMD+Q` to destroy by default.
  /// Soft-close secondary windows one by one (newest first).
  ///
  /// Automatically sets `applicationShouldTerminateAfterLastWindowClosed` to `false`
  /// on the native side. Requires forwarding that call in `AppDelegate`.
  macos,
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
