import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

abstract class TaskbarMenuItem {}

/// Internal contract for per-window operations keyed by [viewId].
///
/// Implemented in `view_root.dart`. The public API
/// is [MultiViewDesktop], which resolves [viewId] from [BuildContext].
abstract class ViewsManager {
  int realToShiftedId(int viewId);

  int shiftedToRealId(int viewId);

  /// Creates a native window, then invokes [onCreated] with its [viewId].
  ///
  /// [newOpts] are merged with global options from [MultiAppConfig].
  /// [parent] will be in future for parent-window placement.
  Future<int> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent});

  /// Creates a dialog window bound to [parentRealId].
  ///
  /// Dialogs differ from regular windows in the following ways:
  /// - They always close when their parent closes, regardless of [CloseMode].
  /// - They cannot enter full-screen mode.
  /// - They are hidden from the taskbar / Mission Control on creation.
  /// - They are centered over their parent window.
  ///
  /// When [modal] is `true`, the parent window's [DialogModalLayer] will show a
  /// scrim for the duration that this dialog is open.
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required Future<void> Function(int) onCreated,
  });

  WindowInfo windowType(int viewId);

  /// Soft closes [viewId]
  Future<void> closeView<T>(int viewId, {T? dialogRes});

  /// Closes all views by using [closeMode] strategy or mode from [runMultiApp -> config -> closeMode] that can be overridden with [setAppCloseMode]
  Future<void> closeApp({CloseMode? closeMode});

  /// Whether programmatic / native close is blocked for [viewId].
  Future<bool> isPreventClose(int viewId);

  /// Blocks or allows closing [viewId]; blocked close emits [WindowListener.onWindowClose].
  Future<void> setPreventClose(int viewId, bool isPreventClose);

  /// Aborts an in-progress [CloseMode.softCascade] waiting on [viewId].
  Future<void> cancelCascadeClose(int viewId);

  /// Updates the strategy used when the main window close button is pressed.
  Future<void> setAppCloseMode(CloseMode closeMode);

  /// returns current strategy
  CloseMode getAppCloseMode();

  Future<String> getTitle(int viewId);

  Future<void> setTitle(int viewId, String title);

  Future<void> setTitleBarStyle(int viewId, TitleBarStyle style,{bool closeVisibility = true, bool maximizeVisibility = true, bool minimizeVisibility = true});

  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})> getTitleBarStyle(int viewId);

  /// Removes native title bar and frame chrome.
  Future<void> setAsFrameless(int viewId);

  /// Sets anchor id. Only for views without parents (root view). Returns [true] if id was set successfully
  Future<bool> setPublicAnchorId(int viewId);

  /// Returns current anchor id
  int? getPublicAnchorId();

  Future<void> setBackgroundColor(int viewId, Color color);

  Future<void> setBrightness(int viewId, Brightness brightness);

  Future<void> setOpacity(int viewId, double opacity);

  Future<double> getOpacity(int viewId);

  Future<bool> hasShadow(int viewId);

  Future<void> setHasShadow(int viewId, bool value);

  /// Window frame in Flutter logical coordinates.
  Future<Rect> getBounds(int viewId);

  Future<Size> getSize(int viewId);

  Future<Offset> getPosition(int viewId);

  Future<void> setSize(int viewId, Size size);

  Future<void> setPosition(int viewId, Offset position);

  Future<void> center(int viewId);

  Future<void> setAlignment(int viewId, Alignment alignment, {bool insideParent = false});

  Future<void> setMinimumSize(int viewId, Size size);

  Future<void> setMaximumSize(int viewId, Size size);

  Future<void> setAspectRatio(int viewId, double ratio);

  Future<void> show(int viewId);

  Future<void> hide(int viewId);

  Future<bool> isVisible(int viewId);

  Future<void> focus(int viewId);

  Future<void> blur(int viewId);

  Future<bool> isFocused(int viewId);

  Future<bool> isMaximized(int viewId);

  Future<void> maximize(int viewId, {bool vertically = false});

  Future<void> unmaximize(int viewId);

  Future<bool> isMinimized(int viewId);

  Future<void> minimize(int viewId);

  Future<void> restore(int viewId);

  Future<bool> isFullScreen(int viewId);

  Future<void> setFullScreen(int viewId, bool isFullScreen);

  Future<bool> isResizable(int viewId);

  Future<void> setResizable(int viewId, bool isResizable);

  Future<bool> isMovable(int viewId);

  Future<void> setMovable(int viewId, bool isMovable);

  Future<bool> isMinimizable(int viewId);

  Future<void> setMinimizable(int viewId, bool isMinimizable);

  Future<bool> isMaximizable(int viewId);

  Future<void> setMaximizable(int viewId, bool isMaximizable);

  Future<bool> isClosable(int viewId);

  Future<void> setClosable(int viewId, bool isClosable);

  Future<bool> isAlwaysOnTop(int viewId);

  Future<void> setAlwaysOnTop(int viewId, bool isAlwaysOnTop);

  Future<void> setTaskbarMenu({required List<TaskbarMenuItem> items});

  /// App-wide state (macOS activation policy; Windows: all tabs hidden from taskbar).
  Future<bool> isHideAppFromTaskbar();

  /// Per-window taskbar visibility (Windows/Linux).
  Future<bool> isHideAppTabFromTaskbar(int viewId);

  /// Params:
  /// - [viewId]: opt param for windows and linux (these platforms can hides only selected item)
  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId});

  /// Begins a native move drag (see [DragToMoveArea]).
  Future<void> startDragging(int viewId);

  /// Begins a native resize drag from [edge] (see [DragToResizeArea]).
  Future<void> startResizing(int viewId, ResizeEdge edge);

  Future<bool> isHideFromCollection(int viewId);

  Future<void> hideFromCollection(int viewId, bool isHideFromCollection);

  Future<bool> isVisibleOnAllWorkspaces(int viewId);

  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false});

  Future<void> setBadgeLabel(int viewId, String? label);

  Future<void> setProgressBar(double progress);

  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false});

  Future<void> popUpWindowMenu(int viewId);

  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(int viewId);

  void addListener(int viewId, WindowListenerCallbacks listener);

  void removeListener(int viewId, WindowListenerCallbacks listener);

  /// Merges [overrides] into the entry shell for [viewId] (appearance and navigation).
  void patchViewShell(int viewId, ViewShellOverrides overrides);

  /// Replaces the entry shell overrides for [viewId], or clears them when null.
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides);

  /// Returns the current entry shell overrides for [viewId], if any.
  ViewShellOverrides? getViewShellOverrides(int viewId);
}
