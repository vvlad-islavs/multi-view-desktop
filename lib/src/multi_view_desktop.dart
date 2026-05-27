import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'resize_edge.dart';
import 'title_bar_style.dart';
import 'utils/calc_window_position.dart';
import 'view_root.dart' show globalRootState;
import 'view_scope.dart';
import 'window_listener.dart';
import 'window_options.dart';

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

  static const _kChannel = MethodChannel('multiview_desktop');

  /// Builds an argument map that always includes the [viewId] so the native
  /// side can route the call to the right OS window.
  static Map<String, dynamic> _args(int viewId, [Map<String, dynamic>? extra]) {
    final map = <String, dynamic>{'viewId': viewId};
    if (extra != null) map.addAll(extra);
    return map;
  }

  // -------------------------------------------------------------------------
  // Identity
  // -------------------------------------------------------------------------

  /// Returns the numeric OS view-ID of the window that owns [context].
  static int getCurrentId(BuildContext context) => ViewScope.of(context).viewId;

  /// Returns all active view ids
  static List<int> get allViewsIds => globalRootState?.views.keys.toList() ?? [];

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
    await globalRootState?.addView(child, options: options);
  }

  /// Closes the window that owns [context].
  ///
  /// If [setPreventClose] was called with `true`, this emits a `close` event
  /// to [WindowListener.onWindowClose] but does **not** destroy the window.
  /// If the window has not confirmed close yet (via [confirmClose]), this
  /// emits a `confirm-close` event instead.  Once the confirmation flag is
  /// set and preventClose is cleared, calling this again actually closes the
  /// window.
  static Future<void> closeWindow(BuildContext context) async {
    final id = getCurrentId(context);
    await globalRootState?.removeView(id);
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
    return await _safeInvokeMethod<bool>('isPreventClose', _args(getCurrentId(context))) ?? false;
  }

  /// When set to `true`, any attempt to close the window (either via
  /// [closeWindow] or the native title-bar close button) is blocked and a
  /// `close` event is emitted to [WindowListener.onWindowClose] instead.
  ///
  /// Set back to `false` to re-enable closing.
  static Future<void> setPreventClose(BuildContext context, bool isPreventClose) async {
    globalRootState?.setPreventClose(getCurrentId(context), isPreventClose);
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
  static void cancelCascadeClose(BuildContext context) {
    globalRootState?.cancelCascade(getCurrentId(context));
  }

  // -------------------------------------------------------------------------
  // Listeners
  // -------------------------------------------------------------------------

  /// Subscribes [listener] to window events for the window that owns
  /// [context].
  static void addListener(BuildContext context, WindowListener listener) {
    globalRootState?.addListener(getCurrentId(context), listener);
  }

  /// Unsubscribes [listener] from window events.
  static void removeListener(BuildContext context, WindowListener listener) {
    globalRootState?.removeListener(getCurrentId(context), listener);
  }

  // -------------------------------------------------------------------------
  // Title & appearance
  // -------------------------------------------------------------------------

  static Future<String> getTitle(BuildContext context) async {
    return await _safeInvokeMethod<String>('getTitle', _args(getCurrentId(context))) ?? '';
  }

  static Future<void> setTitle(BuildContext context, String title) async {
    await _safeInvokeMethod<void>('setTitle', _args(getCurrentId(context), {'title': title}));
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
    await _safeInvokeMethod<void>(
      'setTitleBarStyle',
      _args(getCurrentId(context), {'titleBarStyle': style.name, 'windowButtonVisibility': windowButtonVisibility}),
    );
  }

  static Future<({TitleBarStyle? style, bool? buttonVisibility})> getTitleBarStyle(BuildContext context) async {
    final mapResult = await _safeInvokeMethod<Map<Object?, Object?>>('getTitleBarStyle', _args(getCurrentId(context)));

    return (
      style: _barStyleFromJson(mapResult?['style'] as String?),
      buttonVisibility: mapResult?['windowButtonVisibility'] as bool?,
    );
  }

  static TitleBarStyle _barStyleFromJson(String? styleStr) {
    if (styleStr == 'hidden') return TitleBarStyle.hidden;
    return TitleBarStyle.normal;
  }

  /// Removes the window frame (title bar + border) entirely.
  static Future<void> setAsFrameless(BuildContext context) async {
    await _safeInvokeMethod<void>('setAsFrameless', _args(getCurrentId(context)));
  }

  static Future<void> setBackgroundColor(BuildContext context, Color color) async {
    await globalRootState?.setBackgroundColor(getCurrentId(context), color);
  }

  static Future<void> setBrightness(BuildContext context, Brightness brightness) async {
    await _safeInvokeMethod<void>('setBrightness', _args(getCurrentId(context), {'brightness': brightness.name}));
  }

  static Future<void> setOpacity(BuildContext context, double opacity) async {
    await _safeInvokeMethod<void>('setOpacity', _args(getCurrentId(context), {'opacity': opacity}));
  }

  static Future<double> getOpacity(BuildContext context) async {
    return await _safeInvokeMethod<double>('getOpacity', _args(getCurrentId(context))) ?? 1.0;
  }

  static Future<bool> hasShadow(BuildContext context) async {
    return await _safeInvokeMethod<bool>('hasShadow', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setHasShadow(BuildContext context, bool value) async {
    await _safeInvokeMethod<void>('setHasShadow', _args(getCurrentId(context), {'hasShadow': value}));
  }

  // -------------------------------------------------------------------------
  // Size & position
  // -------------------------------------------------------------------------

  static Future<Rect> getBounds(BuildContext context) async {
    final Map<dynamic, dynamic> r = await _safeInvokeMethod('getBounds', _args(getCurrentId(context))) as Map;
    return Rect.fromLTWH(
      (r['x'] as num).toDouble(),
      (r['y'] as num).toDouble(),
      (r['width'] as num).toDouble(),
      (r['height'] as num).toDouble(),
    );
  }

  static Future<Size> getSize(BuildContext context) async => (await getBounds(context)).size;

  static Future<Offset> getPosition(BuildContext context) async => (await getBounds(context)).topLeft;

  static Future<void> setSize(BuildContext context, Size size) async {
    await _safeInvokeMethod<void>(
      'setSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setPosition(BuildContext context, Offset position) async {
    await globalRootState?.setPosition(getCurrentId(context), pos: position);
  }

  static Future<void> center(BuildContext context) async {
    await globalRootState?.setAlignment(getCurrentId(context), alignment: Alignment.center);
  }

  static Future<void> setAlignment(BuildContext context, Alignment alignment) async {
    await globalRootState?.setAlignment(getCurrentId(context), alignment: alignment);
  }

  static Future<void> setMinimumSize(BuildContext context, Size size) async {
    await _safeInvokeMethod<void>(
      'setMinimumSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setMaximumSize(BuildContext context, Size size) async {
    await _safeInvokeMethod<void>(
      'setMaximumSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setAspectRatio(BuildContext context, double ratio) async {
    await _safeInvokeMethod<void>('setAspectRatio', _args(getCurrentId(context), {'aspectRatio': ratio}));
  }

  // -------------------------------------------------------------------------
  // Visibility & focus
  // -------------------------------------------------------------------------

  static Future<void> show(BuildContext context) async {
    await _safeInvokeMethod<void>('show', _args(getCurrentId(context)));
  }

  static Future<void> hide(BuildContext context) async {
    await _safeInvokeMethod<void>('hide', _args(getCurrentId(context)));
  }

  static Future<bool> isVisible(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isVisible', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> focus(BuildContext context) async {
    await globalRootState?.focus(getCurrentId(context));
  }

  static Future<void> blur(BuildContext context) async {
    await _safeInvokeMethod<void>('blur', _args(getCurrentId(context)));
  }

  static Future<bool> isFocused(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isFocused', _args(getCurrentId(context))) ?? false;
  }

  // -------------------------------------------------------------------------
  // Maximize / minimize / full-screen
  // -------------------------------------------------------------------------

  static Future<bool> isMaximized(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isMaximized', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> maximize(BuildContext context, {bool vertically = false}) async {
    await _safeInvokeMethod<void>('maximize', _args(getCurrentId(context), {'vertically': vertically}));
  }

  static Future<void> unmaximize(BuildContext context) async {
    await _safeInvokeMethod<void>('unmaximize', _args(getCurrentId(context)));
  }

  static Future<bool> isMinimized(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isMinimized', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> minimize(BuildContext context) async {
    await _safeInvokeMethod<void>('minimize', _args(getCurrentId(context)));
  }

  static Future<void> restore(BuildContext context) async {
    await _safeInvokeMethod<void>('restore', _args(getCurrentId(context)));
  }

  static Future<bool> isFullScreen(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isFullScreen', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> setFullScreen(BuildContext context, bool isFullScreen) async {
    await _safeInvokeMethod<void>('setFullScreen', _args(getCurrentId(context), {'isFullScreen': isFullScreen}));
  }

  // -------------------------------------------------------------------------
  // Resizability & movability
  // -------------------------------------------------------------------------

  static Future<bool> isResizable(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isResizable', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setResizable(BuildContext context, bool isResizable) async {
    await _safeInvokeMethod<void>('setResizable', _args(getCurrentId(context), {'isResizable': isResizable}));
  }

  static Future<bool> isMovable(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isMovable', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setMovable(BuildContext context, bool isMovable) async {
    await _safeInvokeMethod<void>('setMovable', _args(getCurrentId(context), {'isMovable': isMovable}));
  }

  static Future<bool> isMinimizable(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isMinimizable', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setMinimizable(BuildContext context, bool isMinimizable) async {
    await _safeInvokeMethod<void>('setMinimizable', _args(getCurrentId(context), {'isMinimizable': isMinimizable}));
  }

  static Future<bool> isMaximizable(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isMaximizable', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setMaximizable(BuildContext context, bool isMaximizable) async {
    await _safeInvokeMethod<void>('setMaximizable', _args(getCurrentId(context), {'isMaximizable': isMaximizable}));
  }

  static Future<bool> isClosable(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isClosable', _args(getCurrentId(context))) ?? true;
  }

  static Future<void> setClosable(BuildContext context, bool isClosable) async {
    await _safeInvokeMethod<void>('setClosable', _args(getCurrentId(context), {'isClosable': isClosable}));
  }

  // -------------------------------------------------------------------------
  // Always-on-top / taskbar
  // -------------------------------------------------------------------------

  static Future<bool> isAlwaysOnTop(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isAlwaysOnTop', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> setAlwaysOnTop(BuildContext context, bool isAlwaysOnTop) async {
    await _safeInvokeMethod<void>('setAlwaysOnTop', _args(getCurrentId(context), {'isAlwaysOnTop': isAlwaysOnTop}));
  }

  static Future<bool> isHideAppFromTaskbar() async {
    final res = await _safeInvokeMethod('isHideAppFromTaskbar', _args(1));
    return res ?? false;
  }

  static Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _safeInvokeMethod<void>('hideAppFromTaskbar', _args(1, {'isHideAppFromTaskbar': isHideAppFromTaskbar}));
  }

  // -------------------------------------------------------------------------
  // Drag & resize (used by DragToMoveArea / DragToResizeArea)
  // -------------------------------------------------------------------------

  static Future<void> startDragging(BuildContext context) async {
    await _safeInvokeMethod<void>('startDragging', _args(getCurrentId(context)));
  }

  static Future<void> startResizing(BuildContext context, ResizeEdge edge) async {
    await _safeInvokeMethod<void>(
      'startResizing',
      _args(getCurrentId(context), {
        'resizeEdge': edge.name,
        'top': edge == ResizeEdge.top || edge == ResizeEdge.topLeft || edge == ResizeEdge.topRight,
        'bottom': edge == ResizeEdge.bottom || edge == ResizeEdge.bottomLeft || edge == ResizeEdge.bottomRight,
        'right': edge == ResizeEdge.right || edge == ResizeEdge.topRight || edge == ResizeEdge.bottomRight,
        'left': edge == ResizeEdge.left || edge == ResizeEdge.topLeft || edge == ResizeEdge.bottomLeft,
      }),
    );
  }

  // -------------------------------------------------------------------------
  // macOS-specific
  // -------------------------------------------------------------------------

  static Future<bool> isHideFromCollection(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isHideFromCollection', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> hideFromCollection(BuildContext context, bool isHideFromCollection) async {
    await _safeInvokeMethod<void>(
      'hideFromCollection',
      _args(getCurrentId(context), {'isHideFromCollection': isHideFromCollection}),
    );
  }

  static Future<bool> isVisibleOnAllWorkspaces(BuildContext context) async {
    return await _safeInvokeMethod<bool>('isVisibleOnAllWorkspaces', _args(getCurrentId(context))) ?? false;
  }

  static Future<void> setVisibleOnAllWorkspaces(
    BuildContext context,
    bool visible, {
    bool visibleOnFullScreen = false,
  }) async {
    await _safeInvokeMethod<void>(
      'setVisibleOnAllWorkspaces',
      _args(getCurrentId(context), {'visible': visible, 'visibleOnFullScreen': visibleOnFullScreen}),
    );
  }

  static Future<void> setBadgeLabel(BuildContext context, [String? label]) async {
    await _safeInvokeMethod<void>('setBadgeLabel', _args(getCurrentId(context), {'label': label ?? ''}));
  }

  // -------------------------------------------------------------------------
  // Progress bar (Windows / macOS)
  // -------------------------------------------------------------------------

  static Future<void> setProgressBar(double progress) async {
    await _kChannel.invokeMethod<void>('setProgressBar', _args(1, {'progress': progress}));
  }

  // -------------------------------------------------------------------------
  // Mouse events
  // -------------------------------------------------------------------------

  static Future<void> setIgnoreMouseEvents(BuildContext context, bool ignore, {bool forward = false}) async {
    await _safeInvokeMethod<void>(
      'setIgnoreMouseEvents',
      _args(getCurrentId(context), {'ignore': ignore, 'forward': forward}),
    );
  }

  static Future<void> popUpWindowMenu(BuildContext context) async {
    await _safeInvokeMethod<void>('popUpWindowMenu', _args(getCurrentId(context)));
  }

  static Future<T?> _safeInvokeMethod<T>(String methodName, dynamic args) async {
    try {
      return await _kChannel.invokeMethod<T>(methodName, args);
    } catch (e) {
      return null;
    }
  }
}
