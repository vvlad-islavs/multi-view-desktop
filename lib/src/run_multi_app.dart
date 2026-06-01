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
void runMultiApp(Widget home, {MultiAppConfig? config}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(await createMultiViewRoot(home, config ?? MultiAppConfig._defaultConfig()));
}

/// Application-wide settings passed to [runMultiApp].
class MultiAppConfig {
  /// Strategy used when closes the main window (see [CloseMode]).
  final MultiPlatformParams generalParams;
  final MacosPlatformParams macosParams;

  /// Default [WindowOptions] merged into every new window (per-window options override).
  final WindowOptions globalOptions;

  MultiAppConfig._({
    required this.generalParams,
    this.globalOptions = const WindowOptions(),
    required this.macosParams,
  });

  /// Creates configuration for [runMultiApp].
  ///
  /// - [generalParams] cross-platform params
  /// - [macosParams] macos specific params
  /// - [globalWindowOptions] are applied to the main window at startup and merged into [openWindow].
  factory MultiAppConfig({
    MultiPlatformParams? generalParams,
    MacosPlatformParams? macosParams,
    WindowOptions? globalWindowOptions,
  }) => MultiAppConfig._(
    globalOptions: globalWindowOptions ?? WindowOptions(),
    generalParams: generalParams ?? MultiPlatformParams.defaultParams(),
    macosParams: macosParams ?? MacosPlatformParams.defaultParams(),
  );

  factory MultiAppConfig._defaultConfig() => MultiAppConfig._(
    generalParams: MultiPlatformParams.defaultParams(),
    macosParams: MacosPlatformParams.defaultParams(),
  );
}

class MultiPlatformParams {
  final bool enableDynamicAnchor;
  final CloseMode closeMode;

  const MultiPlatformParams({this.enableDynamicAnchor = true, this.closeMode = CloseMode.cascade});

  factory MultiPlatformParams.defaultParams() =>
      MultiPlatformParams(enableDynamicAnchor: true, closeMode: CloseMode.cascade);
}

class MacosPlatformParams {
  final bool closeAppAfterLastWindowClosed;
  final bool saveLastWindowToReopen;

  //TODO: действие при тапу по приложению в таскбаре после закрытия всех окон
  final Function? onTaskbarTap;

  const MacosPlatformParams({
    this.saveLastWindowToReopen = true,
    this.onTaskbarTap,
    this.closeAppAfterLastWindowClosed = false,
  });

  factory MacosPlatformParams.defaultParams() =>
      MacosPlatformParams(saveLastWindowToReopen: true, closeAppAfterLastWindowClosed: false, onTaskbarTap: null);
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
  // macos,
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
Future<int> openWindow(Widget child, {WindowOptions? options, BuildContext? parentContext}) =>
    MultiViewDesktop.addWindow(child, options: options, parent: parentContext);
