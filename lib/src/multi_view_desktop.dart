import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'view_root.dart' show globalRootState;

/// Per-window access to native window APIs.
///
/// An instance is bound to one OS window via [MultiViewDesktop.of] or
/// [MultiViewDesktop.fromId]:
///
/// ```dart
/// final win = MultiViewDesktop.of(context);
/// await win.setTitle('Settings');
/// await win.setTitleBarStyle(TitleBarStyle.hidden);
///
/// await MultiViewDesktop.fromId(id).setAlwaysOnTop(true);
/// ```
///
/// App-wide operations (close all windows, listeners, anchor) are static:
///
/// ```dart
/// await MultiViewDesktop.closeApp();
/// MultiViewDesktop.addListenerForView(id, listener);
/// ```
typedef WindowInfo = ({bool isModal, bool isDialog});

class MultiViewDesktop {
  final int _realId;

  /// Public view id for this window (shifted after hot restart).
  int get id => _manager.realToShiftedId(_realId);

  MultiViewDesktop._({required int realId}) : _realId = realId;

  factory MultiViewDesktop.of(BuildContext context) => MultiViewDesktop._(realId: _getRealId(context));

  factory MultiViewDesktop.fromId(int viewId) => MultiViewDesktop._(realId: _manager.shiftedToRealId(viewId));

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static ViewsManager get _manager => globalRootState.manager;

  static int _getRealId(BuildContext context) => ViewScope.of(context).viewId;

  // ---------------------------------------------------------------------------
  // App-wide: identity
  // ---------------------------------------------------------------------------

  static WindowCommunicator get communicator => globalRootState.communicator;

  static int getIdByContext(BuildContext context) => _manager.realToShiftedId(_getRealId(context));

  static Future<void> setGlobalBrightness(Brightness brightness) => _manager.setGlobalBrightness(brightness);

  static List<int> get allWindowViewIds => List.unmodifiable(globalRootState.allShiftedViewsId);

  static List<int> get allDialogViewsIds => List.unmodifiable(globalRootState.dialogsIdsNotif.value);

  static ValueNotifier<List<int>> get allWindowIdsNotifier => globalRootState.windowsIdsNotif;

  static ValueNotifier<List<int>> get allDialogIdsNotifier => globalRootState.dialogsIdsNotif;

  /// Shared theme, locale, and navigation shell for secondary and dialog views.
  /// Updated through [AppShellController.patch] from any window.
  static AppShellController get appShell => globalRootState.appShell;

  // ---------------------------------------------------------------------------
  // App-wide: lifecycle
  // ---------------------------------------------------------------------------

  @internal
  static Future<int> addWindow(
    Widget Function(BuildContext context, int publicId) child, {
    WindowOptions? options,
    BuildContext? parent,
  }) async {
    final parentId = parent == null ? null : _getRealId(parent);
    final realId = await _manager.createWindow(
      newOpts: options,
      onCreated: (int newRealId) async {
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

  /// Opens a dialog bound to [parentContext]. See [openDialog] for details.
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

    return completer.future;
  }

  static Future<void> closeApp({CloseMode? closeMode}) async {
    await _manager.closeApp(closeMode: closeMode);
  }

  static Future<void> setCloseMode(CloseMode closeMode) async {
    await _manager.setAppCloseMode(closeMode);
  }

  static CloseMode getCloseMode() => _manager.getAppCloseMode();

  static Future<bool> setAnchorId(int viewId) async {
    return await _manager.setPublicAnchorId(viewId);
  }

  static int? getAnchorId() => _manager.getPublicAnchorId();

  // ---------------------------------------------------------------------------
  // App-wide: listeners
  // ---------------------------------------------------------------------------

  static void addListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.addListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  static void removeListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.removeListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  // ---------------------------------------------------------------------------
  // App-wide: taskbar / dock
  // ---------------------------------------------------------------------------

  static Future<bool> isHideAppFromTaskbar() async {
    return await _manager.isHideAppFromTaskbar();
  }

  static Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _manager.hideAppFromTaskbar(isHideAppFromTaskbar);
  }

  // ---------------------------------------------------------------------------
  // App-wide: progress bar
  // ---------------------------------------------------------------------------

  static Future<void> setProgressBar(double progress) async {
    await _manager.setProgressBar(progress);
  }

  // ---------------------------------------------------------------------------
  // Per-window: lifecycle
  // ---------------------------------------------------------------------------

  WindowInfo getWindowInfo() {
    return _manager.windowType(_realId);
  }

  /// Starts the soft-close flow. When [setPreventClose] is active, the native
  /// close is blocked and [WindowListener.onWindowClose] is emitted instead.
  Future<void> closeWindow() async {
    await _manager.closeView(_realId);
  }

  /// Closes this dialog. The optional [res] value completes the [openDialog]
  /// future on the caller side.
  Future<void> closeDialog<T>([T? res]) async {
    await _manager.closeView<T>(_realId, dialogRes: res);
  }

  Future<bool> isPreventClose() async {
    return await _manager.isPreventClose(_realId);
  }

  /// While true, native close attempts are blocked and [WindowListener.onWindowClose]
  /// is emitted instead of destroying the window.
  Future<void> setPreventClose(bool isPreventClose) async {
    await _manager.setPreventClose(_realId, isPreventClose);
  }

  /// Stops a [CloseMode.softCascade] that is waiting for this window to finish closing.
  Future<void> cancelCascadeClose() async {
    await _manager.cancelCascadeClose(_realId);
  }

  /// Merges [overrides] into this view's entry shell (theme, locale, navigation).
  void patchViewShell(ViewShellOverrides overrides) {
    _manager.patchViewShell(_realId, overrides);
  }

  void setViewShellOverrides(ViewShellOverrides? overrides) {
    _manager.setViewShellOverrides(_realId, overrides);
  }

  ViewShellOverrides? get viewShellOverrides => _manager.getViewShellOverrides(_realId);

  // ---------------------------------------------------------------------------
  // Per-window: title and appearance
  // ---------------------------------------------------------------------------

  Future<String> getTitle() async {
    return await _manager.getTitle(_realId);
  }

  Future<void> setTitle(String title) async {
    await _manager.setTitle(_realId, title);
  }

  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) async {
    await _manager.setTitleBarStyle(
      _realId,
      style,
      closeVisibility: closeVisibility,
      maximizeVisibility: maximizeVisibility,
      minimizeVisibility: minimizeVisibility,
    );
  }

  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})>
  getTitleBarStyle() async {
    return await _manager.getTitleBarStyle(_realId);
  }

  Future<void> setAsFrameless() async {
    await _manager.setAsFrameless(_realId);
  }

  Future<void> setBackgroundColor(Color color) async {
    await _manager.setBackgroundColor(_realId, color);
  }

  Future<void> setBrightness(Brightness brightness) async {
    await _manager.setBrightness(_realId, brightness);
  }

  Future<void> setOpacity(double opacity) async {
    await _manager.setOpacity(_realId, opacity);
  }

  Future<double> getOpacity() async {
    return await _manager.getOpacity(_realId);
  }

  /// Returns whether the window draws a native drop shadow.
  Future<bool> hasShadow() async {
    return await _manager.hasShadow(_realId);
  }

  /// No-op on Linux.
  Future<void> setHasShadow(bool value) async {
    await _manager.setHasShadow(_realId, value);
  }

  // ---------------------------------------------------------------------------
  // Per-window: size and position
  // ---------------------------------------------------------------------------

  Future<Rect> getBounds() async {
    return await _manager.getBounds(_realId);
  }

  Future<Size> getSize() async => (await getBounds()).size;

  Future<Offset> getPosition() async => (await getBounds()).topLeft;

  Future<void> setSize(Size size) async {
    await _manager.setSize(_realId, size);
  }

  Future<void> setPosition(Offset position) async {
    await _manager.setPosition(_realId, position);
  }

  Future<void> center() async {
    await _manager.center(_realId);
  }

  Future<void> setAlignment(Alignment alignment) async {
    await _manager.setAlignment(_realId, alignment);
  }

  /// Positions the dialog within its parent window bounds.
  Future<void> setDialogAlignment(Alignment alignment) async {
    await _manager.setAlignment(_realId, alignment, insideParent: true);
  }

  Future<void> setMinimumSize(Size size) async {
    await _manager.setMinimumSize(_realId, size);
  }

  Future<void> setMaximumSize(Size size) async {
    await _manager.setMaximumSize(_realId, size);
  }

  Future<void> setAspectRatio(double ratio) async {
    await _manager.setAspectRatio(_realId, ratio);
  }

  // ---------------------------------------------------------------------------
  // Per-window: visibility and focus
  // ---------------------------------------------------------------------------

  Future<void> show() async {
    await _manager.show(_realId);
  }

  Future<void> hide() async {
    await _manager.hide(_realId);
  }

  Future<bool> isVisible() async {
    return await _manager.isVisible(_realId);
  }

  Future<void> focus() async {
    await _manager.focus(_realId);
  }

  Future<void> blur() async {
    await _manager.blur(_realId);
  }

  Future<bool> isFocused() async {
    return await _manager.isFocused(_realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: maximize / minimize / full screen
  // ---------------------------------------------------------------------------

  Future<bool> isMaximized() async {
    return await _manager.isMaximized(_realId);
  }

  Future<void> maximize({bool vertically = false}) async {
    await _manager.maximize(_realId, vertically: vertically);
  }

  Future<void> unmaximize() async {
    await _manager.unmaximize(_realId);
  }

  Future<bool> isMinimized() async {
    return await _manager.isMinimized(_realId);
  }

  Future<void> minimize() async {
    await _manager.minimize(_realId);
  }

  Future<void> restore() async {
    await _manager.restore(_realId);
  }

  Future<bool> isFullScreen() async {
    return await _manager.isFullScreen(_realId);
  }

  Future<void> setFullScreen(bool isFullScreen) async {
    await _manager.setFullScreen(_realId, isFullScreen);
  }

  // ---------------------------------------------------------------------------
  // Per-window: resizability and movability
  // ---------------------------------------------------------------------------

  Future<bool> isResizable() async {
    return await _manager.isResizable(_realId);
  }

  Future<void> setResizable(bool isResizable) async {
    await _manager.setResizable(_realId, isResizable);
  }

  /// Returns whether the window can be moved by dragging the title bar.
  Future<bool> isMovable() async {
    return await _manager.isMovable(_realId);
  }

  /// On Linux this maps to [setResizable].
  Future<void> setMovable(bool isMovable) async {
    await _manager.setMovable(_realId, isMovable);
  }

  Future<bool> isMinimizable() async {
    return await _manager.isMinimizable(_realId);
  }

  Future<void> setMinimizable(bool isMinimizable) async {
    await _manager.setMinimizable(_realId, isMinimizable);
  }

  Future<bool> isMaximizable() async {
    return await _manager.isMaximizable(_realId);
  }

  Future<void> setMaximizable(bool isMaximizable) async {
    await _manager.setMaximizable(_realId, isMaximizable);
  }

  Future<bool> isClosable() async {
    return await _manager.isClosable(_realId);
  }

  Future<void> setClosable(bool isClosable) async {
    await _manager.setClosable(_realId, isClosable);
  }

  // ---------------------------------------------------------------------------
  // Per-window: always on top / taskbar
  // ---------------------------------------------------------------------------

  /// Returns whether the window floats above normal application windows.
  Future<bool> isAlwaysOnTop() async {
    return await _manager.isAlwaysOnTop(_realId);
  }

  /// On Linux the effect depends on the compositor.
  Future<void> setAlwaysOnTop(bool isAlwaysOnTop) async {
    await _manager.setAlwaysOnTop(_realId, isAlwaysOnTop);
  }

  Future<bool> isHideAppTabFromTaskbar() async {
    return await _manager.isHideAppTabFromTaskbar(_realId);
  }

  Future<void> hideCurrentAppTabFromTaskbar(bool isHide) async {
    await _manager.hideAppFromTaskbar(isHide, viewId: _realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: drag and resize (used by widgets)
  // ---------------------------------------------------------------------------

  /// Used by [DragToMoveArea] to start a native move drag.
  Future<void> startDragging() async {
    await _manager.startDragging(_realId);
  }

  /// Used by [DragToResizeArea] to start a native resize drag from [edge].
  Future<void> startResizing(ResizeEdge edge) async {
    await _manager.startResizing(_realId, edge);
  }

  // ---------------------------------------------------------------------------
  // Per-window: mouse events
  // ---------------------------------------------------------------------------

  /// When [ignore] is true, mouse events pass through the window. With
  /// [mouseMoveEvents], move events are still delivered.
  Future<void> setIgnoreMouseEvents(bool ignore, {bool mouseMoveEvents = false}) async {
    await _manager.setIgnoreMouseEvents(_realId, ignore, forward: mouseMoveEvents);
  }

  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents() async {
    return await _manager.isIgnoreMouseEvents(_realId);
  }

  Future<void> popUpWindowMenu() async {
    await _manager.popUpWindowMenu(_realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: macOS-specific
  // ---------------------------------------------------------------------------

  Future<bool> isHideFromCollection() async {
    return await _manager.isHideFromCollection(_realId);
  }

  Future<void> hideFromCollection(bool isHideFromCollection) async {
    await _manager.hideFromCollection(_realId, isHideFromCollection);
  }

  Future<bool> isVisibleOnAllWorkspaces() async {
    return await _manager.isVisibleOnAllWorkspaces(_realId);
  }

  Future<void> setVisibleOnAllWorkspaces(bool visible, {bool visibleOnFullScreen = false}) async {
    await _manager.setVisibleOnAllWorkspaces(_realId, visible, visibleOnFullScreen: visibleOnFullScreen);
  }

  Future<void> setBadgeLabel({String? label}) async {
    await _manager.setBadgeLabel(_realId, label);
  }
}
