import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'multi_view_desktop.dart';
import 'title_bar_style.dart';
import 'view_root.dart' show createMultiViewRoot;
import 'window_observer.dart';
import 'window_options.dart';
import 'app_shell/view_shell_overrides.dart';

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
void runMultiApp({
  required Widget Function(BuildContext globalScopeContext, int publicId) home,
  Widget Function(Widget child)? globalScope,
  MultiAppConfig? config,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(await createMultiViewRoot(home, globalScope, config ?? MultiAppConfig._defaultConfig()));
}

/// Application-wide settings passed to [runMultiApp].
class MultiAppConfig {
  /// Strategy used when closes the main window (see [CloseMode]).
  final MultiPlatformParams generalParams;
  final MacosPlatformParams macosParams;

  /// Default [WindowOptions] merged into every new window (per-window options override).
  final WindowOptions globalOptions;

  final DialogOptions globalDialogOptions;

  /// List of observers notified on window lifecycle events.
  ///
  /// Observers receive callbacks when windows are opened, closed, or when the
  /// anchor changes. See [WindowObserver] for the full list of events.
  ///
  /// ```dart
  /// config: MultiAppConfig(
  ///   observers: [MyWindowObserver()],
  /// )
  /// ```
  final List<WindowObserver> observers;

  MultiAppConfig._({
    required this.generalParams,
    required this.macosParams,
    this.globalOptions = const WindowOptions(),
    this.globalDialogOptions = const DialogOptions(),
    this.observers = const [],
  });

  /// Creates configuration for [runMultiApp].
  ///
  /// - [generalParams] cross-platform params
  /// - [macosParams] macos specific params
  /// - [globalWindowOptions] are applied to the main window at startup and merged into [openWindow].
  /// - [observers] are notified on window lifecycle events (see [WindowObserver]).
  factory MultiAppConfig({
    MultiPlatformParams? generalParams,
    MacosPlatformParams? macosParams,
    WindowOptions? globalWindowOptions,
    DialogOptions? globalDialogOptions,
    List<WindowObserver>? observers,
  }) => MultiAppConfig._(
    globalOptions: globalWindowOptions ?? WindowOptions(),
    globalDialogOptions: globalDialogOptions ?? DialogOptions(),
    generalParams: generalParams ?? MultiPlatformParams.defaultParams(),
    macosParams: macosParams ?? MacosPlatformParams.defaultParams(),
    observers: observers ?? const [],
  );

  factory MultiAppConfig._defaultConfig() => MultiAppConfig._(
    generalParams: MultiPlatformParams.defaultParams(),
    macosParams: MacosPlatformParams.defaultParams(),
  );
}

class MultiPlatformParams {
  ///
  final bool enableDynamicAnchor;
  final CloseMode closeMode;

  const MultiPlatformParams({this.enableDynamicAnchor = true, this.closeMode = CloseMode.softCascade});

  factory MultiPlatformParams.defaultParams() =>
      MultiPlatformParams(enableDynamicAnchor: true, closeMode: CloseMode.softCascade);
}

class MacosPlatformParams {
  final bool closeAppAfterLastWindowClosed;
  final bool saveLastWindowToReopen;

  // TODO: handle taskbar click after all windows are closed.
  @experimental
  final Function? onTaskbarTap;

  const MacosPlatformParams({
    this.saveLastWindowToReopen = true,
    @experimental this.onTaskbarTap,
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
  softCascade,

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
///   onPressed: () => openWindow((context, viewId)=> const SettingsPage()),
///   child: const Text('Open settings'),
/// )
/// ```
Future<int> openWindow(
  Widget Function(BuildContext context, int publicId) childBuilder, {
  WindowOptions? options,
  BuildContext? parentContext,
}) => MultiViewDesktop.addWindow(childBuilder, options: options, parent: parentContext);

// ---------------------------------------------------------------------------
// DialogOptions
// ---------------------------------------------------------------------------

/// Configuration for a dialog window opened via [openDialog].
///
/// Dialogs differ from regular windows in the following ways:
/// - They always require a parent ([openDialog] requires `parentContext`).
/// - They are automatically closed when the parent closes, regardless of
///   [CloseMode] (even `CloseMode.none`).
/// - They cannot enter full-screen mode.
/// - They are hidden from the taskbar / Mission Control on creation.
/// - They are centered over the parent window at creation time.
///
/// Set [modal] to `true` to dim the parent window while the dialog is open.
/// The parent window must wrap its content with [DialogModalLayer] for the
/// visual scrim to appear.
class DialogOptions {
  const DialogOptions({
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.isResizable,
    this.title,
    this.modal,
    this.titleBarStyle,
    this.windowButtonVisibility,
    this.backgroundColor,
    this.alwaysOnTop,
    this.showOnInit,
    this.shellOverrides,
  });

  /// Initial content size in logical pixels.
  final Size? size;

  /// Minimum resizable size enforced by the OS window.
  final Size? minimumSize;

  /// Maximum resizable size enforced by the OS window.
  final Size? maximumSize;

  final bool? isResizable;

  /// Native window title string.
  final String? title;

  /// When `true`, the parent window will be dimmed while this dialog is open.
  ///
  /// The parent must wrap its content with [DialogModalLayer] for the scrim to
  /// appear.  This does **not** block OS-level input on the parent window—the
  /// scrim is a pure Flutter overlay.
  final bool? modal;

  /// Initial title-bar style; use [TitleBarStyle.hidden] for frameless chrome.
  final TitleBarStyle? titleBarStyle;

  /// Whether traffic-light / caption buttons are visible when the bar is hidden.
  final bool? windowButtonVisibility;

  /// Native window background color shown behind Flutter content.
  final Color? backgroundColor;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;

  /// `true` by default
  final bool? showOnInit;

  /// Per-view entry shell overrides. See [WindowOptions.shellOverrides].
  final ViewShellOverrides? shellOverrides;
}

// ---------------------------------------------------------------------------
// openDialog
// ---------------------------------------------------------------------------

/// Opens a dialog window always associated with [parentContext].
///
/// Unlike [openWindow], dialogs:
/// - **Always require** a parent ([parentContext] is mandatory).
/// - Are automatically closed when the parent closes, regardless of
///   [CloseMode] (even `CloseMode.none`).
/// - Cannot enter full-screen mode.
/// - Are hidden from the taskbar / Mission Control.
/// - Are centered over the parent window at creation time.
///
/// Set [options.modal] to `true` to dim the parent window while the dialog is
/// open.  The parent must wrap its content with [DialogModalLayer]:
///
/// ```dart
/// runMultiApp(
///   home: (context, id) => DialogModalLayer(child: MyHomeScreen()),
/// );
/// ```
///
/// Usage:
/// ```dart
/// OutlinedButton(
///   onPressed: () => openDialog(
///     (context, id) => const SettingsDialog(),
///     parentContext: context,
///     options: DialogOptions(title: 'Settings', modal: true),
///   ),
///   child: const Text('Open dialog'),
/// )
/// ```
Future<T?> openDialog<T>(
  Widget Function(BuildContext context, int publicId) childBuilder, {
  required BuildContext parentContext,
  DialogOptions? options,
}) => MultiViewDesktop.addDialog(childBuilder, parentContext: parentContext, options: options);
