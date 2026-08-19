import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'view_root.dart' show globalRootState;

/// Per-window facade for native window operations.
///
/// Create an instance once per call site and invoke methods on it:
/// ```dart
/// final win = MultiViewDesktop.of(context);
/// win.setTitle('Settings');
/// win.setTitleBarStyle(TitleBarStyle.hidden);
///
/// // macOS-only:
/// win.macos.setVisibleOnAllWorkspaces(true);
/// win.macos.isOnActiveSpace();
///
/// // Or inline:
/// MultiViewDesktop.of(context).closeWindow();
/// MultiViewDesktop.fromId(id).setAlwaysOnTop(true);
/// ```
///
/// App-wide operations that do not target a specific window remain static:
/// ```dart
/// await MultiViewDesktop.closeApp();
/// MultiViewDesktop.addListenerForView(id, listener);
/// ```

/// Snapshot of window kind for a view: whether it is a dialog and whether it is modal.
typedef WindowInfo = ({bool isModal, bool isDialog});

class MultiViewDesktop {
  final int _realId;

  /// The public view ID for this instance.
  int get id => _manager.realToShiftedId(_realId);

  /// macOS-only window APIs (Spaces, Mission Control, dock badge).
  MultiViewDesktopMacos get macos => MultiViewDesktopMacos(_realId, _manager);

  MultiViewDesktop._({required int realId}) : _realId = realId;

  /// Creates an instance bound to the window that owns `context`.
  factory MultiViewDesktop.of(BuildContext context) => MultiViewDesktop._(realId: _getRealId(context));

  /// Creates an instance bound to the window with the given public `viewId`.
  factory MultiViewDesktop.fromId(int viewId) => MultiViewDesktop._(realId: _manager.shiftedToRealId(viewId));

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static ViewsManager get _manager => globalRootState.manager;

  static int _getRealId(BuildContext context) => ViewScope.of(context).viewId;

  // ---------------------------------------------------------------------------
  // App-wide: identity
  // ---------------------------------------------------------------------------

  /// In-process message bus shared by all views in this isolate.
  static WindowCommunicator get communicator => globalRootState.communicator;

  /// Returns the public view ID of the window that owns `context`.
  static int getIdByContext(BuildContext context) => _manager.realToShiftedId(_getRealId(context));

  /// Sets the preferred brightness for native chrome on all windows at once.
  /// Does not change Flutter `ThemeData`; use `appShell` for that.
  static void setGlobalBrightness(Brightness brightness) => _manager.setGlobalBrightness(brightness);

  /// Snapshot of public view IDs for all secondary windows currently open.
  static List<int> get allWindowViewIds => List.unmodifiable(globalRootState.allShiftedViewsId);

  /// Snapshot of public view IDs for all dialogs currently open.
  static List<int> get allDialogViewsIds => List.unmodifiable(globalRootState.dialogsIdsNotif.value);

  /// Live-updating notifier; fires whenever a window opens or closes.
  static ValueNotifier<List<int>> get allWindowIdsNotifier => globalRootState.windowsIdsNotif;

  /// Live-updating notifier; fires whenever a dialog opens or closes.
  static ValueNotifier<List<int>> get allDialogIdsNotifier => globalRootState.dialogsIdsNotif;

  /// Shared entry shell for secondary and dialog views (theme, locale, and similar).
  ///
  /// Update through `AppShellController.patch` from any window. This works after
  /// the main window was closed. While the main window is open, the registry is
  /// also synced from the main `MaterialApp` on each frame.
  static AppShellController get appShell => globalRootState.appShell;

  // ---------------------------------------------------------------------------
  // App-wide: lifecycle
  // ---------------------------------------------------------------------------

  /// Opens a new OS window showing `child`.
  @internal
  static int addWindow(
    Widget Function(BuildContext context, int publicId) child, {
    WindowOptions? options,
    BuildContext? parent,
  }) {
    final parentId = parent == null ? null : _getRealId(parent);

    final realId = _manager.createWindow(
      newOpts: options,
      onCreated: (int newRealId) {
        globalRootState.addWindowView(
          newRealId,
          (context) => child(context, _manager.realToShiftedId(newRealId)),
          parentContext: parent,
          parentId: parentId,
          shellOverrides: options?.shellOverrides,
        );
      },
      parent: parentId,
    );

    return _manager.realToShiftedId(realId);
  }

  /// Opens a dialog window bound to `parentContext`.
  ///
  /// See `openDialog` for the full documentation.
  @internal
  static Future<T?> addDialog<T>(
    Widget Function(BuildContext context, int publicId) child, {
    required BuildContext parentContext,
    DialogOptions? options,
  }) async {
    final parentRealId = _getRealId(parentContext);
    final completer = Completer<T>();

    await _manager.createDialog(
      newOpts: options,
      parentRealId: parentRealId,
      onCreated: (int newRealId) {
        globalRootState.addDialogView(
          newRealId,
          (context) => child(context, _manager.realToShiftedId(newRealId)),
          parentContext: parentContext,
          parentId: parentRealId,
          isModalDialog: options?.modal ?? false,
          closeCompleter: completer,
          shellOverrides: options?.shellOverrides,
        );
      },
    );

    return completer.future;
  }

  /// Opens a dialog window bound to `parentContext`.
  ///
  /// See `openDialog` for the full documentation.
  @internal
  static Future<DialogEntry<T?>> addDialogEntry<T>(
    Widget Function(BuildContext context, int publicId) child, {
    required BuildContext parentContext,
    DialogOptions? options,
  }) async {
    final parentRealId = _getRealId(parentContext);
    final completer = Completer<T>();
    final realId = await _manager.createDialog(
      newOpts: options,
      parentRealId: parentRealId,
      onCreated: (int newRealId) async {
        globalRootState.addDialogView(
          newRealId,
          (context) => child(context, _manager.realToShiftedId(newRealId)),
          parentContext: parentContext,
          parentId: parentRealId,
          isModalDialog: options?.modal ?? false,
          closeCompleter: completer,
          shellOverrides: options?.shellOverrides,
        );
      },
    );

    return DialogEntry(id: _manager.realToShiftedId(realId), result: completer.future);
  }

  /// Return `enableDynamicAnchor` from runMultiApp->config->generalParams->enableDynamicAnchor
  static bool get isEnabledDynamicAnchor => _manager.isEnabledDynamicAnchor;

  /// Closes all windows using `closeMode` or the mode set in `MultiAppConfig`.
  /// If all views successfully closed by mode `mode` return `true` else `false`
  static Future<bool> closeApp({CloseMode? closeMode}) async {
    return await _manager.closeApp(closeMode: closeMode);
  }

  /// Changes the strategy used when the main window close button is pressed.
  static void setCloseMode(CloseMode closeMode) {
    _manager.setAppCloseMode(closeMode);
  }

  /// Returns the currently active close mode.
  static CloseMode getCloseMode() => _manager.getAppCloseMode();

  /// Sets the anchor view by public `viewId`. Only valid for root views.
  static bool setAnchorId(int viewId) {
    return _manager.setPublicAnchorId(viewId);
  }

  /// Returns the current anchor view ID, or `null` if none is set.
  static int? getAnchorId() => _manager.getPublicAnchorId();

  // ---------------------------------------------------------------------------
  // App-wide: listeners
  // ---------------------------------------------------------------------------

  /// Subscribes `listener` to events for the window with the given public `publicViewId`.
  static void addListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.addListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  /// Unsubscribes `listener` from events for the given public `publicViewId`.
  static void removeListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.removeListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  // ---------------------------------------------------------------------------
  // App-wide: taskbar / dock
  // ---------------------------------------------------------------------------

  /// Returns whether the application icon is hidden from the dock / taskbar app-wide.
  static bool isHideAppFromTaskbar() {
    return _manager.isHideAppFromTaskbar();
  }

  /// Hides or shows the application icon in the dock / taskbar app-wide.
  static void hideAppFromTaskbar(bool isHideAppFromTaskbar) {
    _manager.hideAppFromTaskbar(isHideAppFromTaskbar);
  }

  /// Replaces the entire app taskbar / dock context menu.
  ///
  /// Windows: taskbar jump list tasks (right-click the app icon).
  /// macOS: dock context menu.
  /// Linux: freedesktop `.desktop` Actions in the dock context menu.
  /// Optional [TaskbarMenuItem.iconAsset] on Windows and macOS; Linux uses [TaskbarMenuItem.title] only.
  ///
  /// Each call overwrites previous items. Item callbacks are matched by list index.
  static void setMenuItems(List<TaskbarMenuItem> items) {
    _manager.setTaskbarMenu(items: items);
  }

  // ---------------------------------------------------------------------------
  // App-wide: progress bar
  // ---------------------------------------------------------------------------

  /// Sets the taskbar / dock progress indicator (`0.0` to `1.0`), app-wide.
  static void setProgressBar(double progress) {
    _manager.setProgressBar(progress);
  }

  // ---------------------------------------------------------------------------
  // Per-window: lifecycle
  // ---------------------------------------------------------------------------

  /// Returns whether this view is a dialog and whether it is modal.
  WindowInfo getWindowInfo() {
    return _manager.windowType(_realId);
  }

  /// Soft-closes this window. If `setPreventClose(true)` was set, fires
  /// `WindowListener.onWindowClose` instead of destroying the window.
  void closeWindow() {
    _manager.closeView(_realId);
  }

  /// Closes this dialog and completes the `openDialog` future on the caller side.
  ///
  /// `res` is forwarded to the `await openDialog<T>()` expression. Has no effect
  /// on regular (non-dialog) windows; use `closeWindow` instead.
  void closeDialog<T>([T? res]) {
    _manager.closeView<T>(_realId, dialogRes: res);
  }

  /// Returns whether close is currently blocked for this window.
  bool isPreventClose() {
    return _manager.isPreventClose(_realId);
  }

  /// When `true`, any close attempt is blocked and `WindowListener.onWindowClose`
  /// fires instead. Set back to `false` to re-enable closing.
  void setPreventClose(bool isPreventClose) {
    _manager.setPreventClose(_realId, isPreventClose);
  }

  /// Aborts an in-progress `CloseMode.softCascade` that is waiting on this window.
  void cancelCascadeClose() {
    _manager.cancelCascadeClose(_realId);
  }

  /// Merges `overrides` into this view's entry shell (theme/locale and navigation).
  ///
  /// Appearance fields in `overrides.appearance` are merged on top of the
  /// global `appShell` snapshot. Navigation fields apply only to this view.
  void patchViewShell(ViewShellOverrides overrides) {
    _manager.patchViewShell(_realId, overrides);
  }

  /// Replaces this view's entry shell overrides, or clears them when null.
  void setViewShellOverrides(ViewShellOverrides? overrides) {
    _manager.setViewShellOverrides(_realId, overrides);
  }

  /// Current entry shell overrides for this view, if any.
  ViewShellOverrides? get viewShellOverrides => _manager.getViewShellOverrides(_realId);

  // ---------------------------------------------------------------------------
  // Per-window: title and appearance
  // ---------------------------------------------------------------------------

  /// Returns the native window title.
  String getTitle() {
    return _manager.getTitle(_realId);
  }

  /// Sets the native window title shown in the title bar and dock tooltip.
  void setTitle(String title) {
    _manager.setTitle(_realId, title);
  }

  /// Changes the title-bar style. Pass `TitleBarStyle.hidden` for a frameless window.
  void setTitleBarStyle(
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) {
    _manager.setTitleBarStyle(
      _realId,
      style,
      closeVisibility: closeVisibility,
      maximizeVisibility: maximizeVisibility,
      minimizeVisibility: minimizeVisibility,
    );
  }

  /// Returns the current title-bar style and button visibility.
  ({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})
  getTitleBarStyle() {
    return _manager.getTitleBarStyle(_realId);
  }

  /// Removes the native title bar and border entirely.
  void setAsFrameless() {
    _manager.setAsFrameless(_realId);
  }

  /// Sets the native window background color behind the Flutter view.
  void setBackgroundColor(Color color) {
    _manager.setBackgroundColor(_realId, color);
  }

  /// Sets the preferred appearance for native chrome (light or dark).
  void setBrightness(Brightness brightness) {
    _manager.setBrightness(_realId, brightness);
  }

  /// Sets window opacity in the range `0.0` (transparent) to `1.0` (opaque).
  void setOpacity(double opacity) {
    _manager.setOpacity(_realId, opacity);
  }

  /// Returns the current window opacity.
  double getOpacity() {
    return _manager.getOpacity(_realId);
  }

  /// Returns whether the window draws a native drop shadow.
  bool hasShadow() {
    return _manager.hasShadow(_realId);
  }

  /// Enables or disables the native drop shadow. No-op on Linux.
  void setHasShadow(bool value) {
    _manager.setHasShadow(_realId, value);
  }

  // ---------------------------------------------------------------------------
  // Per-window: size and position
  // ---------------------------------------------------------------------------

  /// Returns the window frame in Flutter logical coordinates (position + size).
  Rect getBounds() {
    return _manager.getBounds(_realId);
  }

  /// Returns the content size in logical pixels.
  Size getSize() => getBounds().size;

  /// Returns the top-left position of the window.
  Offset getPosition() => getBounds().topLeft;

  /// Resizes the window to `size` in logical pixels.
  void setSize(Size size) {
    _manager.setSize(_realId, size);
  }

  /// Moves the window so its top-left corner is at `position`.
  void setPosition(Offset position) {
    _manager.setPosition(_realId, position);
  }

  /// Centers the window on the screen that contains the largest portion of it.
  void center() {
    _manager.center(_realId);
  }

  /// Positions the window using `alignment` on the display under the cursor.
  void setAlignment(Alignment alignment) {
    _manager.setAlignment(_realId, alignment);
  }

  /// Repositions this dialog within its parent window bounds using `alignment`.
  ///
  /// Only meaningful for dialog views. Regular windows should use `setAlignment`.
  void setDialogAlignment(Alignment alignment) {
    _manager.setAlignment(_realId, alignment, insideParent: true);
  }

  /// Sets the minimum size the user can resize the window to.
  void setMinimumSize(Size size) {
    _manager.setMinimumSize(_realId, size);
  }

  /// Sets the maximum size the user can resize the window to.
  void setMaximumSize(Size size) {
    _manager.setMaximumSize(_realId, size);
  }

  /// Locks the content aspect ratio (width / height). Pass `0` to clear.
  void setAspectRatio(double ratio) {
    _manager.setAspectRatio(_realId, ratio);
  }

  // ---------------------------------------------------------------------------
  // Per-window: visibility and focus
  // ---------------------------------------------------------------------------

  /// Shows the window if it was hidden.
  void show() {
    _manager.show(_realId);
  }

  /// Hides the window without closing it.
  void hide() {
    _manager.hide(_realId);
  }

  /// Returns whether the window is currently visible.
  bool isVisible() {
    return _manager.isVisible(_realId);
  }

  /// Brings the window to the front and gives it keyboard focus.
  void focus() {
    _manager.focus(_realId);
  }

  /// Removes keyboard focus from the window.
  void blur() {
    _manager.blur(_realId);
  }

  /// Returns whether this window is the current focused window.
  bool isFocused() {
    return _manager.isFocused(_realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: maximize / minimize / full screen
  // ---------------------------------------------------------------------------

  /// Returns whether the window is in the maximized state.
  bool isMaximized() {
    return _manager.isMaximized(_realId);
  }

  /// Maximizes the window.
  ///
  /// When `vertically` is true (Windows only), maximizes to half the screen height.
  void maximize({bool vertically = false}) {
    _manager.maximize(_realId, vertically: vertically);
  }

  /// Restores the window from the maximized state.
  void unmaximize() {
    _manager.unmaximize(_realId);
  }

  /// Returns whether the window is minimized to the dock or taskbar.
  bool isMinimized() {
    return _manager.isMinimized(_realId);
  }

  /// Minimizes the window.
  void minimize() {
    _manager.minimize(_realId);
  }

  /// Restores the window from the minimized state.
  void restore() {
    _manager.restore(_realId);
  }

  /// Returns whether the window is in native full-screen mode.
  bool isFullScreen() {
    return _manager.isFullScreen(_realId);
  }

  /// Enters or exits native full-screen mode.
  void setFullScreen(bool isFullScreen) {
    _manager.setFullScreen(_realId, isFullScreen);
  }

  // ---------------------------------------------------------------------------
  // Per-window: resizability and movability
  // ---------------------------------------------------------------------------

  /// Returns whether the user can resize the window by dragging its edges.
  bool isResizable() {
    return _manager.isResizable(_realId);
  }

  /// Enables or disables user resizing.
  void setResizable(bool isResizable) {
    _manager.setResizable(_realId, isResizable);
  }

  /// Returns whether the window can be moved by dragging the title bar.
  bool isMovable() {
    return _manager.isMovable(_realId);
  }

  /// Enables or disables moving the window by dragging. On Linux maps to `setResizable`.
  void setMovable(bool isMovable) {
    _manager.setMovable(_realId, isMovable);
  }

  /// Returns whether the minimize button is enabled.
  bool isMinimizable() {
    return _manager.isMinimizable(_realId);
  }

  /// Enables or disables the minimize button and action.
  void setMinimizable(bool isMinimizable) {
    _manager.setMinimizable(_realId, isMinimizable);
  }

  /// Returns whether the maximize / zoom button is enabled.
  bool isMaximizable() {
    return _manager.isMaximizable(_realId);
  }

  /// Enables or disables the maximize button and action.
  void setMaximizable(bool isMaximizable) {
    _manager.setMaximizable(_realId, isMaximizable);
  }

  /// Returns whether the close button is enabled.
  bool isClosable() {
    return _manager.isClosable(_realId);
  }

  /// Enables or disables the close button and native close action.
  void setClosable(bool isClosable) {
    _manager.setClosable(_realId, isClosable);
  }

  // ---------------------------------------------------------------------------
  // Per-window: always on top / taskbar
  // ---------------------------------------------------------------------------

  /// Returns whether the window floats above normal application windows.
  bool isAlwaysOnTop() {
    return _manager.isAlwaysOnTop(_realId);
  }

  /// Keeps the window above other windows. On Linux depends on compositor support.
  void setAlwaysOnTop(bool isAlwaysOnTop) {
    _manager.setAlwaysOnTop(_realId, isAlwaysOnTop);
  }

  /// Returns whether this window is hidden from the taskbar (Windows / Linux).
  bool isHideAppTabFromTaskbar() {
    return _manager.isHideAppTabFromTaskbar(_realId);
  }

  /// Hides or shows this window in the taskbar (Windows / Linux).
  void hideCurrentAppTabFromTaskbar(bool isHide) {
    _manager.hideAppFromTaskbar(isHide, viewId: _realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: drag and resize (used by widgets)
  // ---------------------------------------------------------------------------

  /// Starts a native window-move drag session. Called by `DragToMoveArea`.
  void startDragging() {
    _manager.startDragging(_realId);
  }

  /// Starts a native window-resize drag session from `edge`. Called by `DragToResizeArea`.
  void startResizing(ResizeEdge edge) {
    _manager.startResizing(_realId, edge);
  }

  // ---------------------------------------------------------------------------
  // Per-window: mouse events
  // ---------------------------------------------------------------------------

  /// When `ignore` is `true`, all mouse events pass through the window.
  /// If `mouseMoveEvents` is `true`, mouse move events still arrive.
  void setIgnoreMouseEvents(bool ignore, {bool mouseMoveEvents = false}) {
    _manager.setIgnoreMouseEvents(_realId, ignore, forward: mouseMoveEvents);
  }

  /// Returns the current mouse pass-through state.
  ({bool mouseMoveEvents, bool ignore}) isIgnoreMouseEvents() {
    return _manager.isIgnoreMouseEvents(_realId);
  }

  /// Shows the native window context menu at the current cursor position.
  void popUpWindowMenu() {
    _manager.popUpWindowMenu(_realId);
  }
}
