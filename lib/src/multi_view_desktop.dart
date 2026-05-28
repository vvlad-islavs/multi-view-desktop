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

  static WindowCommunicator get communicator => globalRootState.communicator;

  static ViewsManager get _manager => globalRootState.manager;

  // -------------------------------------------------------------------------
  // Identity
  // -------------------------------------------------------------------------

  /// Returns the numeric OS view-ID of the window that owns [context].
  static int getCurrentId(BuildContext context) => ViewScope.of(context).viewId;

  /// Returns all active view ids
  static List<int> get allViewsIds => globalRootState.allViewsId;

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
  static Future<void> addWindow(Widget child, {WindowOptions? options, int? parent}) async {
    //TODO: use parent id. Example in MultiWindow experimental feature.
    // https://github.com/flutter/flutter/blob/master/examples/multiple_windows/lib/app/main_window.dart
    await _manager.createWindow(
      newOpts: options,
      onCreated: (int newId) async {
        globalRootState.addView(newId, child);
      },
    );
  }

  /// Closes the window that owns [context].
  ///
  /// If [setPreventClose] was called with `true`, this emits a `close` event
  /// to [WindowListener.onWindowClose] but does **not** destroy the window.
  /// If the window has not confirmed close yet (via [confirmClose]), this
  /// emits a `confirm-close` event instead.  Once the confirmation flag is
  /// set and preventClose is cleared, calling this again actually closes the
  /// window.
  static Future<void> closeWindow(BuildContext context, {CloseMode closeMode = CloseMode.none}) async {
    await _manager.closeWindow(getCurrentId(context), closeMode: closeMode);
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
    return await _manager.isPreventClose(getCurrentId(context));
  }

  /// When set to `true`, any attempt to close the window (either via
  /// [closeWindow] or the native title-bar close button) is blocked and a
  /// `close` event is emitted to [WindowListener.onWindowClose] instead.
  ///
  /// Set back to `false` to re-enable closing.
  static Future<void> setPreventClose(BuildContext context, bool isPreventClose) async {
    await _manager.setPreventClose(getCurrentId(context), isPreventClose);
  }

  /// Explicitly cancels a pending cascade close initiated by the main window.
  ///
  /// Call this from [WindowListener.onWindowClose] when the user decides NOT
  /// to close the window during a cascade (e.g. from a confirmation dialog).
  /// This completes the pending cascade completer with `false`, aborting the
  /// entire cascade and keeping both this window and the main window open.
  ///
  /// Without calling this method the cascade completer for this window hangs
  /// indefinitely and any later close of this window would unexpectedly trigger
  /// the main window to close as well.
  static Future<void> cancelCascadeClose(BuildContext context) async {
    await _manager.cancelCascadeClose(getCurrentId(context));
  }

  // -------------------------------------------------------------------------
  // Listeners
  // -------------------------------------------------------------------------

  /// Subscribes [listener] to window events for the window that owns
  /// [context].
  static void addListener(BuildContext context, WindowListener listener) {
    _manager.addListener(getCurrentId(context), listener);
  }

  /// Unsubscribes [listener] from window events.
  static void removeListener(BuildContext context, WindowListener listener) {
    _manager.removeListener(getCurrentId(context), listener);
  }

  // -------------------------------------------------------------------------
  // Title & appearance
  // -------------------------------------------------------------------------

  static Future<String> getTitle(BuildContext context) async {
    return await _manager.getTitle(getCurrentId(context));
  }

  static Future<void> setTitle(BuildContext context, String title) async {
    await _manager.setTitle(getCurrentId(context), title);
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
    await _manager.setTitleBarStyle(getCurrentId(context), style, windowButtonVisibility: windowButtonVisibility);
  }

  static Future<({TitleBarStyle? style, bool? buttonVisibility})> getTitleBarStyle(BuildContext context) async {
    return await _manager.getTitleBarStyle(getCurrentId(context));
  }

  /// Removes the window frame (title bar + border) entirely.
  static Future<void> setAsFrameless(BuildContext context) async {
    await _manager.setAsFrameless(getCurrentId(context));
  }

  static Future<void> setBackgroundColor(BuildContext context, Color color) async {
    await _manager.setBackgroundColor(getCurrentId(context), color);
  }

  static Future<void> setBrightness(BuildContext context, Brightness brightness) async {
    await _manager.setBrightness(getCurrentId(context), brightness);
  }

  static Future<void> setOpacity(BuildContext context, double opacity) async {
    await _manager.setOpacity(getCurrentId(context), opacity);
  }

  static Future<double> getOpacity(BuildContext context) async {
    return await _manager.getOpacity(getCurrentId(context));
  }

  static Future<bool> hasShadow(BuildContext context) async {
    return await _manager.hasShadow(getCurrentId(context));
  }

  static Future<void> setHasShadow(BuildContext context, bool value) async {
    await _manager.setHasShadow(getCurrentId(context), value);
  }

  // -------------------------------------------------------------------------
  // Size & position
  // -------------------------------------------------------------------------

  static Future<Rect> getBounds(BuildContext context) async {
    return await _manager.getBounds(getCurrentId(context));
  }

  static Future<Size> getSize(BuildContext context) async => (await getBounds(context)).size;

  static Future<Offset> getPosition(BuildContext context) async => (await getBounds(context)).topLeft;

  static Future<void> setSize(BuildContext context, Size size) async {
    await _manager.setSize(getCurrentId(context), size);
  }

  static Future<void> setPosition(BuildContext context, Offset position) async {
    await _manager.setPosition(getCurrentId(context), position);
  }

  static Future<void> center(BuildContext context) async {
    await _manager.center(getCurrentId(context));
  }

  static Future<void> setAlignment(BuildContext context, Alignment alignment) async {
    await _manager.setAlignment(getCurrentId(context), alignment);
  }

  static Future<void> setMinimumSize(BuildContext context, Size size) async {
    await _manager.setMinimumSize(getCurrentId(context), size);
  }

  static Future<void> setMaximumSize(BuildContext context, Size size) async {
    await _manager.setMaximumSize(getCurrentId(context), size);
  }

  static Future<void> setAspectRatio(BuildContext context, double ratio) async {
    await _manager.setAspectRatio(getCurrentId(context), ratio);
  }

  // -------------------------------------------------------------------------
  // Visibility & focus
  // -------------------------------------------------------------------------

  static Future<void> show(BuildContext context) async {
    await _manager.show(getCurrentId(context));
  }

  static Future<void> hide(BuildContext context) async {
    await _manager.hide(getCurrentId(context));
  }

  static Future<bool> isVisible(BuildContext context) async {
    return await _manager.isVisible(getCurrentId(context));
  }

  static Future<void> focus(BuildContext context) async {
    await _manager.focus(getCurrentId(context));
  }

  static Future<void> blur(BuildContext context) async {
    await _manager.blur(getCurrentId(context));
  }

  static Future<bool> isFocused(BuildContext context) async {
    return await _manager.isFocused(getCurrentId(context));
  }

  // -------------------------------------------------------------------------
  // Maximize / minimize / full-screen
  // -------------------------------------------------------------------------

  static Future<bool> isMaximized(BuildContext context) async {
    return await _manager.isMaximized(getCurrentId(context));
  }

  static Future<void> maximize(BuildContext context, {bool vertically = false}) async {
    await _manager.maximize(getCurrentId(context), vertically: vertically);
  }

  static Future<void> unmaximize(BuildContext context) async {
    await _manager.unmaximize(getCurrentId(context));
  }

  static Future<bool> isMinimized(BuildContext context) async {
    return await _manager.isMinimized(getCurrentId(context));
  }

  static Future<void> minimize(BuildContext context) async {
    await _manager.minimize(getCurrentId(context));
  }

  static Future<void> restore(BuildContext context) async {
    await _manager.restore(getCurrentId(context));
  }

  static Future<bool> isFullScreen(BuildContext context) async {
    return await _manager.isFullScreen(getCurrentId(context));
  }

  static Future<void> setFullScreen(BuildContext context, bool isFullScreen) async {
    await _manager.setFullScreen(getCurrentId(context), isFullScreen);
  }

  // -------------------------------------------------------------------------
  // Resizability & movability
  // -------------------------------------------------------------------------

  static Future<bool> isResizable(BuildContext context) async {
    return await _manager.isResizable(getCurrentId(context));
  }

  static Future<void> setResizable(BuildContext context, bool isResizable) async {
    await _manager.setResizable(getCurrentId(context), isResizable);
  }

  static Future<bool> isMovable(BuildContext context) async {
    return await _manager.isMovable(getCurrentId(context));
  }

  static Future<void> setMovable(BuildContext context, bool isMovable) async {
    await _manager.setMovable(getCurrentId(context), isMovable);
  }

  static Future<bool> isMinimizable(BuildContext context) async {
    return await _manager.isMinimizable(getCurrentId(context));
  }

  static Future<void> setMinimizable(BuildContext context, bool isMinimizable) async {
    await _manager.setMinimizable(getCurrentId(context), isMinimizable);
  }

  static Future<bool> isMaximizable(BuildContext context) async {
    return await _manager.isMaximizable(getCurrentId(context));
  }

  static Future<void> setMaximizable(BuildContext context, bool isMaximizable) async {
    await _manager.setMaximizable(getCurrentId(context), isMaximizable);
  }

  static Future<bool> isClosable(BuildContext context) async {
    return await _manager.isClosable(getCurrentId(context));
  }

  static Future<void> setClosable(BuildContext context, bool isClosable) async {
    await _manager.setClosable(getCurrentId(context), isClosable);
  }

  // -------------------------------------------------------------------------
  // Always-on-top / taskbar
  // -------------------------------------------------------------------------

  static Future<bool> isAlwaysOnTop(BuildContext context) async {
    return await _manager.isAlwaysOnTop(getCurrentId(context));
  }

  static Future<void> setAlwaysOnTop(BuildContext context, bool isAlwaysOnTop) async {
    await _manager.setAlwaysOnTop(getCurrentId(context), isAlwaysOnTop);
  }

  static Future<bool> isHideAppFromTaskbar() async {
    return await _manager.isHideAppFromTaskbar();
  }

  static Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _manager.hideAppFromTaskbar(isHideAppFromTaskbar);
  }

  // -------------------------------------------------------------------------
  // Drag & resize (used by DragToMoveArea / DragToResizeArea)
  // -------------------------------------------------------------------------

  static Future<void> startDragging(BuildContext context) async {
    await _manager.startDragging(getCurrentId(context));
  }

  static Future<void> startResizing(BuildContext context, ResizeEdge edge) async {
    await _manager.startResizing(getCurrentId(context), edge);
  }

  // -------------------------------------------------------------------------
  // macOS-specific
  // -------------------------------------------------------------------------

  static Future<bool> isHideFromCollection(BuildContext context) async {
    return await _manager.isHideFromCollection(getCurrentId(context));
  }

  static Future<void> hideFromCollection(BuildContext context, bool isHideFromCollection) async {
    await _manager.hideFromCollection(getCurrentId(context), isHideFromCollection);
  }

  static Future<bool> isVisibleOnAllWorkspaces(BuildContext context) async {
    return await _manager.isVisibleOnAllWorkspaces(getCurrentId(context));
  }

  static Future<void> setVisibleOnAllWorkspaces(
    BuildContext context,
    bool visible, {
    bool visibleOnFullScreen = false,
  }) async {
    await _manager.setVisibleOnAllWorkspaces(getCurrentId(context), visible, visibleOnFullScreen: visibleOnFullScreen);
  }

  static Future<void> setBadgeLabel(BuildContext context, {String? label}) async {
    await _manager.setBadgeLabel(getCurrentId(context), label);
  }

  // -------------------------------------------------------------------------
  // Progress bar (Windows / macOS)
  // -------------------------------------------------------------------------

  static Future<void> setProgressBar(double progress) async {
    await _manager.setProgressBar(progress);
  }

  // -------------------------------------------------------------------------
  // Mouse events
  // -------------------------------------------------------------------------

  static Future<void> setIgnoreMouseEvents(BuildContext context, bool ignore, {bool forward = false}) async {
    await _manager.setIgnoreMouseEvents(getCurrentId(context), ignore, forward: forward);
  }

  static Future<void> popUpWindowMenu(BuildContext context) async {
    await _manager.popUpWindowMenu(getCurrentId(context));
  }
}
