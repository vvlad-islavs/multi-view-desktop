import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Internal window manager contract. Public API: `MultiViewDesktop`.
///
/// Native FFI proxies live on [ViewManagerProxies] (`globalRootState.proxies`).
abstract class ViewsManager {
  int realToShiftedId(int viewId);

  int shiftedToRealId(int viewId);

  /// Creates a native window and calls `onCreated` with its real view id.
  Future<int> createWindow({
    WindowOptions? newOpts,
    required void Function(int) onCreated,
    int? parent,
    AnimationSettings? animation,
  });

  /// Creates a dialog for `parentRealId`. See `DialogOptions` and `openDialog`.
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required void Function(int) onCreated,
    AnimationSettings? animation,
  });

  /// Creates a borderless popup owned by `parentRealId`. Returns the real view id.
  Future<int> createPopup({
    required int parentRealId,
    required Size size,
    AnimationSettings? animation,
  });

  /// Shows a popup created by [createPopup].
  ///
  /// When [animate] is true, runs open fade if enabled in config. Internal
  /// re-shows (anchor back on screen) should pass [animate] `false`.
  Future<void> showPopup(int viewId, {bool animate = true});

  /// Hides a popup without destroying the session. Cancels in-flight open fade.
  void hidePopup(int viewId);

  /// Fades out (when enabled) then destroys a popup created by [createPopup].
  ///
  /// Pass [destroy] `false` to only run the close fade so a later [open] can
  /// keep the same native session.
  Future<void> closePopup(int viewId, {AnimationSettings? animation, bool destroy = true});

  /// Destroys a popup created by [createPopup] without close fade.
  Future<void> destroyPopup(int viewId);

  /// Moves and optionally resizes a popup to [bounds] in logical screen space.
  Future<bool> positionPopup(
    int viewId,
    Rect bounds, {
    AnimationSettings? animation,
  });

  WindowInfo windowType(int viewId);

  Future<bool> closeView<T>(
    int viewId, {
    T? dialogRes,
    AnimationSettings? animation,
  });

  /// Stages one-shot animation params for [viewId]; consumed by the next matching animation.
  void stageForceViewAnimation(
    int viewId,
    ViewAnimationType type, {
    AnimationSettings? animation,
  });

  Future<bool> closeApp({CloseMode? closeMode});

  /// Aborts an in-progress `CloseMode.softCascade` waiting on `viewId`.
  void cancelCascadeClose(int viewId);

  /// Updates the strategy used when the main window close button is pressed.
  void setAppCloseMode(CloseMode closeMode);

  CloseMode getAppCloseMode();

  bool get isEnabledDynamicAnchor;

  /// Sets anchor id. Only for views without parents (root view).
  bool setPublicAnchorId(int viewId);

  int? getPublicAnchorId();

  void addListener(int viewId, WindowListenerCallbacks listener);

  void removeListener(int viewId, WindowListenerCallbacks listener);

  void patchViewShell(int viewId, ViewShellOverrides overrides);

  /// Replaces the entry shell overrides for `viewId`, or clears them when null.
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides);

  /// Returns the current entry shell overrides for `viewId`, if any.
  ViewShellOverrides? getViewShellOverrides(int viewId);
}
