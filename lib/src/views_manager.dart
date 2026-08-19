import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Internal window manager contract. Public API: `MultiViewDesktop`.
abstract class ViewsManager {
  int realToShiftedId(int viewId);

  int shiftedToRealId(int viewId);

  /// Creates a native window and calls `onCreated` with its real view id.
  int createWindow({WindowOptions? newOpts, required void Function(int) onCreated, int? parent});

  /// Creates a dialog for `parentRealId`. See `DialogOptions` and `openDialog`.
  Future<int> createDialog({DialogOptions? newOpts, required int parentRealId, required void Function(int) onCreated});

  /// Creates a borderless popup owned by `parentRealId`. Returns the real view id.
  int createPopup({required int parentRealId, required Size size});

  /// Destroys a popup created by [createPopup].
  void destroyPopup(int viewId);

  /// Moves and optionally resizes a popup to [bounds] in logical screen space.
  bool positionPopup(int viewId, Rect bounds);

  WindowInfo windowType(int viewId);

  void closeView<T>(int viewId, {T? dialogRes});

  Future<bool> closeApp({CloseMode? closeMode});

  bool isPreventClose(int viewId);

  void setPreventClose(int viewId, bool isPreventClose);

  /// Aborts an in-progress `CloseMode.softCascade` waiting on `viewId`.
  void cancelCascadeClose(int viewId);

  /// Updates the strategy used when the main window close button is pressed.
  void setAppCloseMode(CloseMode closeMode);

  CloseMode getAppCloseMode();

  bool get isEnabledDynamicAnchor;

  String getTitle(int viewId);

  void setTitle(int viewId, String title);

  void setTitleBarStyle(
    int viewId,
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  });

  ({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})
  getTitleBarStyle(int viewId);

  void setAsFrameless(int viewId);

  /// Sets anchor id. Only for views without parents (root view). Returns `true` if id was set successfully
  bool setPublicAnchorId(int viewId);

  int? getPublicAnchorId();

  void setBackgroundColor(int viewId, Color color);

  void setBrightness(int viewId, Brightness brightness);

  void setGlobalBrightness(Brightness brightness);

  void setOpacity(int viewId, double opacity);

  double getOpacity(int viewId);

  bool hasShadow(int viewId);

  void setHasShadow(int viewId, bool value);

  Rect getBounds(int viewId);

  Size getSize(int viewId);

  Offset getPosition(int viewId);

  void setSize(int viewId, Size size);

  void setPosition(int viewId, Offset position);

  void center(int viewId);

  void setAlignment(int viewId, Alignment alignment, {bool insideParent = false});

  void setMinimumSize(int viewId, Size size);

  void setMaximumSize(int viewId, Size size);

  void setAspectRatio(int viewId, double ratio);

  void show(int viewId);

  void hide(int viewId);

  bool isVisible(int viewId);

  void focus(int viewId);

  void blur(int viewId);

  bool isFocused(int viewId);

  /// macOS: whether the window is on the active Mission Control Space.
  bool isOnActiveSpace(int viewId);

  bool isMaximized(int viewId);

  void maximize(int viewId, {bool vertically = false});

  void unmaximize(int viewId);

  bool isMinimized(int viewId);

  void minimize(int viewId);

  void restore(int viewId);

  bool isFullScreen(int viewId);

  void setFullScreen(int viewId, bool isFullScreen);

  bool isResizable(int viewId);

  void setResizable(int viewId, bool isResizable);

  bool isMovable(int viewId);

  void setMovable(int viewId, bool isMovable);

  bool isMinimizable(int viewId);

  void setMinimizable(int viewId, bool isMinimizable);

  bool isMaximizable(int viewId);

  void setMaximizable(int viewId, bool isMaximizable);

  bool isClosable(int viewId);

  void setClosable(int viewId, bool isClosable);

  bool isAlwaysOnTop(int viewId);

  void setAlwaysOnTop(int viewId, bool isAlwaysOnTop);

  void setTaskbarMenu({required List<TaskbarMenuItem> items});

  /// App-wide state (macOS activation policy; Windows: all tabs hidden from taskbar).
  bool isHideAppFromTaskbar();

  /// Per-window taskbar visibility (Windows/Linux).
  bool isHideAppTabFromTaskbar(int viewId);

  void hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId});

  void startDragging(int viewId);

  void startResizing(int viewId, ResizeEdge edge);

  bool isHideFromCollection(int viewId);

  void hideFromCollection(int viewId, bool isHideFromCollection);

  bool isVisibleOnAllWorkspaces(int viewId);

  void setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false});

  void setBadgeLabel(int viewId, String? label);

  void setProgressBar(double progress);

  void setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false});

  void popUpWindowMenu(int viewId);

  ({bool mouseMoveEvents, bool ignore}) isIgnoreMouseEvents(int viewId);

  void addListener(int viewId, WindowListenerCallbacks listener);

  void removeListener(int viewId, WindowListenerCallbacks listener);

  void patchViewShell(int viewId, ViewShellOverrides overrides);

  /// Replaces the entry shell overrides for `viewId`, or clears them when null.
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides);

  /// Returns the current entry shell overrides for `viewId`, if any.
  ViewShellOverrides? getViewShellOverrides(int viewId);
}
