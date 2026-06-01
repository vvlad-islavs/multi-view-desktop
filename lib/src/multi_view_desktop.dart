import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'view_root.dart' show globalRootState;

/// Static facade for all per-window operations.
///
/// Every method that acts on a specific window takes a [BuildContext] and
/// resolves the target view through the nearest [ViewScope] ancestor.  This
/// removes the need to pass an explicit ID and mirrors the "current" mental
/// model from multi-window-manager.
///
/// All calls are routed through the single [MethodChannel] `multiview_desktop`
/// with a `viewId` key in the argument map -- the same pattern used by
/// multi-window-manager.
///
/// Example:
/// ```dart
/// // Hide the title bar of the current window
/// await MultiViewDesktop.setTitleBarStyle(
///   context,
///   TitleBarStyle.hidden,
/// );
///
/// // Get the ID of the current window
/// final id = MultiViewDesktop.getCurrentId(context);
///
/// // Open a new window from anywhere
/// await MultiViewDesktop.addWindow(const MySecondaryPage());
///
/// // Close the current window
/// await MultiViewDesktop.closeWindow(context);
/// ```
class MultiViewDesktop {
  MultiViewDesktop._();

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// In-process message bus shared by all views in this isolate.
  static WindowCommunicator get communicator => globalRootState.communicator;

  static ViewsManager get _manager => globalRootState.manager;

  // -------------------------------------------------------------------------
  // Identity
  // -------------------------------------------------------------------------

  static int _getRealId(BuildContext context) => ViewScope.of(context).viewId;

  /// Returns the numeric OS view-ID of the window that owns [context].
  static int getCurrentId(BuildContext context) =>
      _manager.realToShiftedId(_getRealId(context));

  /// Returns numeric view IDs for all secondary windows currently registered.
  static List<int> get allViewsIds =>
      List.unmodifiable(globalRootState.allShiftedViewsId);

  // -------------------------------------------------------------------------
  // Window lifecycle
  // -------------------------------------------------------------------------

  /// Opens a new OS window showing [child].
  ///
  /// Optionally pass [options] to set the initial size, title, title-bar
  /// style, etc.  After the window is created the options are applied before
  /// the first frame is rendered.
  ///
  /// This method can be called from any context, including callbacks and
  /// timers that have no [BuildContext].
  @internal
  static Future<int> addWindow(
    Widget child, {
    WindowOptions? options,
    BuildContext? parent,
  }) async {
    final parentId = parent == null ? null : _getRealId(parent);
    final newId = await _manager.createWindow(
      newOpts: options,
      onCreated: (int newId) async {
        globalRootState.addView(newId, child, parentId: parentId);
      },
      parent: parentId,
    );

    debugPrint('id нового окна: $newId');
    return newId;
  }

  /// Closes the window that owns [context].
  ///
  /// If [setPreventClose] was called with `true`, this emits a `close` event
  /// to [WindowListener.onWindowClose] but does **not** destroy the window.
  /// Once preventClose is cleared, calling this again actually closes the window.
  static Future<void> closeWindow(BuildContext context) async {
    await _manager.closeWindow(_getRealId(context));
  }

  /// Closes the window by [viewId]. Do nothing if window with [viewId] not exist
  ///
  /// If [setPreventClose] was called with `true`, this emits a `close` event
  /// to [WindowListener.onWindowClose] but does **not** destroy the window.
  /// Once preventClose is cleared, calling this again actually closes the window.
  static Future<void> closeWindowById(int viewId) async {
    await _manager.closeWindow(_manager.shiftedToRealId(viewId));
  }

  static Future<void> closeApp({CloseMode? closeMode}) async {
    await _manager.closeApp(closeMode: closeMode);
  }

  /// Closes all windows cascade from last to main
  ///
  /// If [setPreventClose] was called with `true`, this emits a `close` event
  /// to [WindowListener.onWindowClose] but does **not** destroy the window.
  /// If the window has not confirmed close yet (via [confirmClose]), this
  /// emits a `confirm-close` event instead.  Once the confirmation flag is
  /// set and preventClose is cleared, calling this again actually closes the
  /// window.
  // static Future<void> closeAllWindowsCascade() async {
  //   // await globalRootState?.removeViewsCascade();
  // }

  /// Returns whether programmatic (and native) close is currently blocked for
  /// the window that owns [context].
  static Future<bool> isPreventClose(BuildContext context) async {
    return await _manager.isPreventClose(_getRealId(context));
  }

  /// When set to `true`, any attempt to close the window (either via
  /// [closeWindow] or the native title-bar close button) is blocked and a
  /// `close` event is emitted to [WindowListener.onWindowClose] instead.
  ///
  /// Set back to `false` to re-enable closing.
  static Future<void> setPreventClose(
    BuildContext context,
    bool isPreventClose,
  ) async {
    await _manager.setPreventClose(_getRealId(context), isPreventClose);
  }

  /// Explicitly cancels a pending cascade close initiated by the main window.
  ///
  /// Call this from [WindowListener.onWindowClose] when decides NOT
  /// to close the window during a cascade (e.g. from a confirmation dialog).
  /// This completes the pending cascade completer with `false`, aborting the
  /// entire cascade and keeping both this window and the main window open.
  ///
  /// Without calling this method the cascade completer for this window hangs
  /// indefinitely and any later close of this window would unexpectedly trigger
  /// the main window to close as well.
  static Future<void> cancelCascadeClose(BuildContext context) async {
    await _manager.cancelCascadeClose(_getRealId(context));
  }

  /// Changes how closing the main window affects other windows (see [CloseMode]).
  ///
  /// On macOS also updates `applicationShouldTerminateAfterLastWindowClosed`
  /// (`false` for [CloseMode.macos], `true` otherwise).
  static Future<void> setCloseMode(CloseMode closeMode) async {
    await _manager.setAppCloseMode(closeMode);
  }

  static CloseMode getCloseMode() {
    return _manager.getAppCloseMode();
  }

  // -------------------------------------------------------------------------
  // Listeners
  // -------------------------------------------------------------------------

  /// Subscribes [listener] to window events for the window that owns
  /// [context].
  static void addListener(BuildContext context, WindowListener listener) {
    _manager.addListener(_getRealId(context), listener);
  }

  /// Unsubscribes [listener] from window events.
  static void removeListener(BuildContext context, WindowListener listener) {
    _manager.removeListener(_getRealId(context), listener);
  }

  // -------------------------------------------------------------------------
  // Title & appearance
  // -------------------------------------------------------------------------

  /// Returns the native window title string.
  static Future<String> getTitle(BuildContext context) async {
    return await _manager.getTitle(_getRealId(context));
  }

  /// Sets the native window title shown in the title bar or dock tooltip.
  static Future<void> setTitle(BuildContext context, String title) async {
    await _manager.setTitle(_getRealId(context), title);
  }

  /// Changes the title-bar style of the current window.
  ///
  /// Pass [TitleBarStyle.hidden] to hide the native title bar and use a
  /// custom [WindowCaption] widget instead.
  static Future<void> setTitleBarStyle(
    BuildContext context,
    TitleBarStyle style, {
    bool windowButtonVisibility = true,
  }) async {
    await _manager.setTitleBarStyle(
      _getRealId(context),
      style,
      windowButtonVisibility: windowButtonVisibility,
    );
  }

  /// Returns the current title-bar style and traffic-light / button visibility.
  static Future<({TitleBarStyle? style, bool? buttonVisibility})>
  getTitleBarStyle(BuildContext context) async {
    return await _manager.getTitleBarStyle(_getRealId(context));
  }

  /// Removes the window frame (title bar + border) entirely.
  static Future<void> setAsFrameless(BuildContext context) async {
    await _manager.setAsFrameless(_getRealId(context));
  }

  /// Sets the native window background color behind the Flutter view.
  static Future<void> setBackgroundColor(
    BuildContext context,
    Color color,
  ) async {
    await _manager.setBackgroundColor(_getRealId(context), color);
  }

  /// Sets the preferred appearance for native chrome (light / dark).
  static Future<void> setBrightness(
    BuildContext context,
    Brightness brightness,
  ) async {
    await _manager.setBrightness(_getRealId(context), brightness);
  }

  /// Sets window opacity in the range `0.0` (transparent) to `1.0` (opaque).
  static Future<void> setOpacity(BuildContext context, double opacity) async {
    await _manager.setOpacity(_getRealId(context), opacity);
  }

  /// Returns the current window opacity (`0.0`–`1.0`).
  static Future<double> getOpacity(BuildContext context) async {
    return await _manager.getOpacity(_getRealId(context));
  }

  /// Returns whether the window draws a drop shadow.
  static Future<bool> hasShadow(BuildContext context) async {
    return await _manager.hasShadow(_getRealId(context));
  }

  /// Enables or disables the native window drop shadow.
  static Future<void> setHasShadow(BuildContext context, bool value) async {
    await _manager.setHasShadow(_getRealId(context), value);
  }

  // -------------------------------------------------------------------------
  // Size & position
  // -------------------------------------------------------------------------

  /// Returns the window frame in Flutter logical coordinates (position + size).
  static Future<Rect> getBounds(BuildContext context) async {
    return await _manager.getBounds(_getRealId(context));
  }

  /// Returns the window content size in logical pixels.
  static Future<Size> getSize(BuildContext context) async =>
      (await getBounds(context)).size;

  /// Returns the top-left corner of the window in Flutter logical coordinates.
  static Future<Offset> getPosition(BuildContext context) async =>
      (await getBounds(context)).topLeft;

  /// Resizes the window to [size] in logical pixels.
  static Future<void> setSize(BuildContext context, Size size) async {
    await _manager.setSize(_getRealId(context), size);
  }

  /// Moves the window so its top-left corner is at [position].
  static Future<void> setPosition(BuildContext context, Offset position) async {
    await _manager.setPosition(_getRealId(context), position);
  }

  /// Centers the window on the screen that contains the largest overlap with it.
  static Future<void> center(BuildContext context) async {
    await _manager.center(_getRealId(context));
  }

  /// Positions the window using [alignment] on the display under the cursor.
  static Future<void> setAlignment(
    BuildContext context,
    Alignment alignment,
  ) async {
    await _manager.setAlignment(_getRealId(context), alignment);
  }

  /// Sets the minimum size the user can resize the window to.
  static Future<void> setMinimumSize(BuildContext context, Size size) async {
    await _manager.setMinimumSize(_getRealId(context), size);
  }

  /// Sets the maximum size the user can resize the window to.
  static Future<void> setMaximumSize(BuildContext context, Size size) async {
    await _manager.setMaximumSize(_getRealId(context), size);
  }

  /// Locks the window content aspect ratio (width / height). Pass `0` to clear.
  static Future<void> setAspectRatio(BuildContext context, double ratio) async {
    await _manager.setAspectRatio(_getRealId(context), ratio);
  }

  // -------------------------------------------------------------------------
  // Visibility & focus
  // -------------------------------------------------------------------------

  /// Shows the window if it was hidden.
  static Future<void> show(BuildContext context) async {
    await _manager.show(_getRealId(context));
  }

  /// Hides the window without closing it.
  static Future<void> hide(BuildContext context) async {
    await _manager.hide(_getRealId(context));
  }

  /// Returns whether the window is currently visible on screen.
  static Future<bool> isVisible(BuildContext context) async {
    return await _manager.isVisible(_getRealId(context));
  }

  /// Brings the window to the front and gives it keyboard focus.
  static Future<void> focus(BuildContext context) async {
    await _manager.focus(_getRealId(context));
  }

  /// Removes keyboard focus from the window.
  static Future<void> blur(BuildContext context) async {
    await _manager.blur(_getRealId(context));
  }

  /// Returns whether this window is the current key (focused) window.
  static Future<bool> isFocused(BuildContext context) async {
    return await _manager.isFocused(_getRealId(context));
  }

  // -------------------------------------------------------------------------
  // Maximize / minimize / full-screen
  // -------------------------------------------------------------------------

  /// Returns whether the window is in the zoomed / maximized state.
  static Future<bool> isMaximized(BuildContext context) async {
    return await _manager.isMaximized(_getRealId(context));
  }

  /// Zooms / maximizes the window. [vertically] is reserved for platform-specific use.
  static Future<void> maximize(
    BuildContext context, {
    bool vertically = false,
  }) async {
    await _manager.maximize(_getRealId(context), vertically: vertically);
  }

  /// Restores the window from the zoomed / maximized state.
  static Future<void> unmaximize(BuildContext context) async {
    await _manager.unmaximize(_getRealId(context));
  }

  /// Returns whether the window is miniaturized to the dock.
  static Future<bool> isMinimized(BuildContext context) async {
    return await _manager.isMinimized(_getRealId(context));
  }

  /// Miniaturizes the window to the dock.
  static Future<void> minimize(BuildContext context) async {
    await _manager.minimize(_getRealId(context));
  }

  /// Restores the window from miniaturized state.
  static Future<void> restore(BuildContext context) async {
    await _manager.restore(_getRealId(context));
  }

  /// Returns whether the window is in native full-screen mode.
  static Future<bool> isFullScreen(BuildContext context) async {
    return await _manager.isFullScreen(_getRealId(context));
  }

  /// Enters or exits native full-screen mode.
  static Future<void> setFullScreen(
    BuildContext context,
    bool isFullScreen,
  ) async {
    await _manager.setFullScreen(_getRealId(context), isFullScreen);
  }

  // -------------------------------------------------------------------------
  // Resizability & movability
  // -------------------------------------------------------------------------

  /// Returns whether the user can resize the window by dragging edges.
  static Future<bool> isResizable(BuildContext context) async {
    return await _manager.isResizable(_getRealId(context));
  }

  /// Enables or disables user resizing of the window frame.
  static Future<void> setResizable(
    BuildContext context,
    bool isResizable,
  ) async {
    await _manager.setResizable(_getRealId(context), isResizable);
  }

  /// Returns whether the window can be moved by dragging the title bar / background.
  static Future<bool> isMovable(BuildContext context) async {
    return await _manager.isMovable(_getRealId(context));
  }

  /// Enables or disables moving the window by dragging.
  static Future<void> setMovable(BuildContext context, bool isMovable) async {
    await _manager.setMovable(_getRealId(context), isMovable);
  }

  /// Returns whether the minimize button / action is enabled.
  static Future<bool> isMinimizable(BuildContext context) async {
    return await _manager.isMinimizable(_getRealId(context));
  }

  /// Enables or disables miniaturizing the window.
  static Future<void> setMinimizable(
    BuildContext context,
    bool isMinimizable,
  ) async {
    await _manager.setMinimizable(_getRealId(context), isMinimizable);
  }

  /// Returns whether the zoom / maximize button / action is enabled.
  static Future<bool> isMaximizable(BuildContext context) async {
    return await _manager.isMaximizable(_getRealId(context));
  }

  /// Enables or disables zooming / maximizing the window.
  static Future<void> setMaximizable(
    BuildContext context,
    bool isMaximizable,
  ) async {
    await _manager.setMaximizable(_getRealId(context), isMaximizable);
  }

  /// Returns whether the close button / action is enabled.
  static Future<bool> isClosable(BuildContext context) async {
    return await _manager.isClosable(_getRealId(context));
  }

  /// Enables or disables closing the window from native chrome.
  static Future<void> setClosable(BuildContext context, bool isClosable) async {
    await _manager.setClosable(_getRealId(context), isClosable);
  }

  // -------------------------------------------------------------------------
  // Always-on-top / taskbar
  // -------------------------------------------------------------------------

  /// Returns whether the window floats above normal application windows.
  static Future<bool> isAlwaysOnTop(BuildContext context) async {
    return await _manager.isAlwaysOnTop(_getRealId(context));
  }

  /// Keeps the window above other windows when [isAlwaysOnTop] is `true`.
  static Future<void> setAlwaysOnTop(
    BuildContext context,
    bool isAlwaysOnTop,
  ) async {
    await _manager.setAlwaysOnTop(_getRealId(context), isAlwaysOnTop);
  }

  /// Returns whether the application is hidden from the dock / taskbar.
  ///
  /// On Windows, `true` only when every window is hidden from the taskbar.
  static Future<bool> isHideAppFromTaskbar() async {
    return await _manager.isHideAppFromTaskbar();
  }

  /// Per-window taskbar visibility (Windows/Linux).
  static Future<bool> isHideAppTabFromTaskbar(BuildContext context) async {
    return await _manager.isHideAppTabFromTaskbar(_getRealId(context));
  }

  /// Hides or shows the application icon in the dock / taskbar (app-wide).
  static Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _manager.hideAppFromTaskbar(isHideAppFromTaskbar);
  }

  static Future<void> hideCurrentAppTabFromTaskbar(
    BuildContext context,
    bool isHideAppFromTaskbar,
  ) async {
    await _manager.hideAppFromTaskbar(
      isHideAppFromTaskbar,
      viewId: _getRealId(context),
    );
  }

  // -------------------------------------------------------------------------
  // Drag & resize (used by DragToMoveArea / DragToResizeArea)
  // -------------------------------------------------------------------------

  /// Starts a native window-move session (used by [DragToMoveArea]).
  static Future<void> startDragging(BuildContext context) async {
    await _manager.startDragging(_getRealId(context));
  }

  /// Starts a native window-resize session from [edge] (used by [DragToResizeArea]).
  static Future<void> startResizing(
    BuildContext context,
    ResizeEdge edge,
  ) async {
    await _manager.startResizing(_getRealId(context), edge);
  }

  // -------------------------------------------------------------------------
  // macOS-specific
  // -------------------------------------------------------------------------

  /// Returns whether the window is excluded from Mission Control (macOS).
  static Future<bool> isHideFromCollection(BuildContext context) async {
    return await _manager.isHideFromCollection(_getRealId(context));
  }

  /// Hides or shows the window in Mission Control / Exposé (macOS).
  static Future<void> hideFromCollection(
    BuildContext context,
    bool isHideFromCollection,
  ) async {
    await _manager.hideFromCollection(
      _getRealId(context),
      isHideFromCollection,
    );
  }

  /// Returns whether the window is visible on all virtual desktops (macOS).
  static Future<bool> isVisibleOnAllWorkspaces(BuildContext context) async {
    return await _manager.isVisibleOnAllWorkspaces(_getRealId(context));
  }

  /// Pins the window to all Spaces / virtual desktops (macOS).
  static Future<void> setVisibleOnAllWorkspaces(
    BuildContext context,
    bool visible, {
    bool visibleOnFullScreen = false,
  }) async {
    await _manager.setVisibleOnAllWorkspaces(
      _getRealId(context),
      visible,
      visibleOnFullScreen: visibleOnFullScreen,
    );
  }

  /// Sets the dock icon badge label for this window (macOS).
  static Future<void> setBadgeLabel(
    BuildContext context, {
    String? label,
  }) async {
    await _manager.setBadgeLabel(_getRealId(context), label);
  }

  // -------------------------------------------------------------------------
  // Progress bar (Windows / macOS)
  // -------------------------------------------------------------------------

  /// Sets the taskbar / dock progress indicator (`0.0`–`1.0`, app-wide).
  static Future<void> setProgressBar(double progress) async {
    await _manager.setProgressBar(progress);
  }

  // -------------------------------------------------------------------------
  // Mouse events
  // -------------------------------------------------------------------------

  /// When [ignore] is `true`, mouse events pass through the window.
  ///
  /// If [mouseMoveEvents] is `true`, mouse move events stay.
  static Future<void> setIgnoreMouseEvents(
    BuildContext context,
    bool ignore, {
    bool mouseMoveEvents = false,
  }) async {
    await _manager.setIgnoreMouseEvents(
      _getRealId(context),
      ignore,
      forward: mouseMoveEvents,
    );
  }

  /// When [ignore] is `true`, mouse events pass through the window.
  ///
  /// If [mouseMoveEvents] is `true`, mouse move events stay.
  static Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(
    BuildContext context,
  ) async {
    return await _manager.isIgnoreMouseEvents(_getRealId(context));
  }

  /// Shows the native window context menu at the current cursor position (macOS).
  static Future<void> popUpWindowMenu(BuildContext context) async {
    await _manager.popUpWindowMenu(_getRealId(context));
  }
}
