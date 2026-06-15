import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'multi_view_desktop.dart';
import 'title_bar_style.dart';
import 'view_root.dart' show createMultiViewRoot;
import 'window_observer.dart';
import 'window_options.dart';
import 'app_shell/view_shell_overrides.dart';

/// Entry point for a multiview_desktop application.
///
/// Replaces [runApp]. Internally uses [runWidget] with a [ViewCollection] root
/// that manages every OS window in a single Flutter engine and isolate.
///
/// ```dart
/// void main() {
///   runMultiApp(
///     home: (context, id) => MyHomeScreen(),
///   );
/// }
/// ```
///
/// [home] is shown in the first (main) OS window. Additional windows are opened
/// with [openWindow].
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
  final MultiPlatformParams generalParams;
  final MacosPlatformParams macosParams;

  /// Default options merged into every new window.
  final WindowOptions globalOptions;

  final DialogOptions globalDialogOptions;

  /// Notified when windows are opened, closed, or when the anchor changes.
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
  /// Only the main window goes through the normal soft-close cycle
  /// (prevent-close, confirm-close, destroy).
  none,

  /// Secondary windows are soft-closed one by one (newest first), then the main
  /// window. A cascade in progress can be aborted with [MultiViewDesktop.cancelCascadeClose].
  softCascade,

  /// All secondary windows are force-closed immediately, then the main window
  /// is soft-closed.
  forceSecondary,

  /// Every window is force-closed without the soft-close cycle.
  destroy,

  /// macOS only: the last root window is hidden instead of destroyed so the app
  /// stays in the dock. Requires the corresponding hook in AppDelegate.
  // macos,
}

/// Opens a new OS window. Convenience wrapper around [MultiViewDesktop.addWindow].
///
/// ```dart
/// ElevatedButton(
///   onPressed: () => openWindow((context, viewId) => const SettingsPage()),
///   child: const Text('Open settings'),
/// )
/// ```
Future<int> openWindow(
  Widget Function(BuildContext context, int publicId) childBuilder, {
  WindowOptions? options,
  BuildContext? parentContext,
}) => MultiViewDesktop.addWindow(childBuilder, options: options, parent: parentContext);

/// Options for a dialog opened with [openDialog].
///
/// Dialogs always belong to a parent window. They are centered over the parent
/// at creation, hidden from the taskbar, and closed automatically when the
/// parent closes (regardless of [CloseMode]). Full-screen mode is not available
/// for dialogs.
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

  /// Minimum size enforced by the native window.
  final Size? minimumSize;

  /// Maximum size enforced by the native window.
  final Size? maximumSize;

  final bool? isResizable;

  /// Native window title.
  final String? title;

  /// When true, the parent window is blocked at the OS level while the dialog
  /// is open (macOS sheet, Windows owner chain, Linux transient + input lock).
  /// A visual scrim in the parent additionally requires [DialogModalLayer] in
  /// the parent widget tree; the scrim alone does not block OS input.
  final bool? modal;

  /// Title bar appearance. [TitleBarStyle.hidden] removes native chrome.
  final TitleBarStyle? titleBarStyle;

  /// Visibility of caption buttons when the title bar is hidden.
  final bool? windowButtonVisibility;

  /// Background color behind the Flutter view.
  final Color? backgroundColor;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;

  /// Whether the window is shown right after creation. Defaults to true.
  final bool? showOnInit;

  /// Per-view shell overrides. See [WindowOptions.shellOverrides].
  final ViewShellOverrides? shellOverrides;
}

/// Opens a dialog window tied to [parentContext].
///
/// The returned future completes when the dialog is closed via [closeDialog]
/// (or [MvdContext.closeDialog]). The optional result is passed through from
/// that close call.
///
/// Unlike [openWindow], a parent [BuildContext] is required. Dialogs cannot
/// enter full-screen mode. With [DialogOptions.modal] set to true, the parent
/// is blocked at the OS level on supported platforms; [DialogModalLayer] in the
/// parent adds a visual scrim in Flutter.
///
/// ```dart
/// runMultiApp(
///   home: (context, id) => DialogModalLayer(child: MyHomeScreen()),
/// );
/// ```
///
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
