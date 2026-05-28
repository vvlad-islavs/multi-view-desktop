import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

abstract class ViewsManager {
  Future<void> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent});

  Future<void> closeWindow(int viewId, {CloseMode closeMode = CloseMode.none});

  Future<bool> isPreventClose(int viewId);

  Future<void> setPreventClose(int viewId, bool isPreventClose);

  Future<void> cancelCascadeClose(int viewId);

  Future<void> setCloseMode(CloseMode closeMode);

  Future<String> getTitle(int viewId);

  Future<void> setTitle(int viewId, String title);

  Future<void> setTitleBarStyle(int viewId, TitleBarStyle style, {bool windowButtonVisibility = true});

  Future<({TitleBarStyle? style, bool? buttonVisibility})> getTitleBarStyle(int viewId);

  Future<void> setAsFrameless(int viewId);

  Future<void> setBackgroundColor(int viewId, Color color);

  Future<void> setBrightness(int viewId, Brightness brightness);

  Future<void> setOpacity(int viewId, double opacity);

  Future<double> getOpacity(int viewId);

  Future<bool> hasShadow(int viewId);

  Future<void> setHasShadow(int viewId, bool value);

  Future<Rect> getBounds(int viewId);

  Future<Size> getSize(int viewId);

  Future<Offset> getPosition(int viewId);

  Future<void> setSize(int viewId, Size size);

  Future<void> setPosition(int viewId, Offset position);

  Future<void> center(int viewId);

  Future<void> setAlignment(int viewId, Alignment alignment);

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

  Future<bool> isHideAppFromTaskbar();

  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar);

  Future<void> startDragging(int viewId);

  Future<void> startResizing(int viewId, ResizeEdge edge);

  Future<bool> isHideFromCollection(int viewId);

  Future<void> hideFromCollection(int viewId, bool isHideFromCollection);

  Future<bool> isVisibleOnAllWorkspaces(int viewId);

  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false});

  Future<void> setBadgeLabel(int viewId, String? label);

  Future<void> setProgressBar(double progress);

  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false});

  Future<void> popUpWindowMenu(int viewId);

  void addListener(int viewId, WindowListener listener);

  void removeListener(int viewId, WindowListener listener);
}
