import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'resize_edge.dart';
import 'title_bar_style.dart';
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
  static int getCurrentId(BuildContext context) =>
      ViewScope.of(context).viewId;

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
  static Future<void> addWindow(
    Widget child, {
    WindowOptions? options,
  }) async {
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

  /// Returns whether programmatic (and native) close is currently blocked for
  /// the window that owns [context].
  static Future<bool> isPreventClose(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isPreventClose', _args(getCurrentId(context))) ??
        false;
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
    await _kChannel.invokeMethod<void>(
      'setPreventClose',
      _args(getCurrentId(context), {'isPreventClose': isPreventClose}),
    );
  }

  /// Marks the window as having received user confirmation that it may close.
  ///
  /// After calling this with `true`, the next [closeWindow] call will proceed
  /// with the actual OS close (assuming [setPreventClose] is not active).
  /// Pass `false` to reset the confirmation so the window asks again next time.
  static Future<void> confirmClose(
    BuildContext context, {
    bool confirmed = true,
  }) async {
    await _kChannel.invokeMethod<void>(
      'confirmClose',
      _args(getCurrentId(context), {'confirmClose': confirmed}),
    );
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
    return await _kChannel.invokeMethod<String>(
          'getTitle', _args(getCurrentId(context))) ??
        '';
  }

  static Future<void> setTitle(BuildContext context, String title) async {
    await _kChannel.invokeMethod<void>(
        'setTitle', _args(getCurrentId(context), {'title': title}));
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
    await _kChannel.invokeMethod<void>(
      'setTitleBarStyle',
      _args(getCurrentId(context), {
        'titleBarStyle': style.name,
        'windowButtonVisibility': windowButtonVisibility,
      }),
    );
  }

  /// Removes the window frame (title bar + border) entirely.
  static Future<void> setAsFrameless(BuildContext context) async {
    await _kChannel.invokeMethod<void>(
        'setAsFrameless', _args(getCurrentId(context)));
  }

  static Future<void> setBackgroundColor(
    BuildContext context,
    Color color,
  ) async {
    await _kChannel.invokeMethod<void>(
      'setBackgroundColor',
      _args(getCurrentId(context), {
        'backgroundColorA': (color.a * 255).round(),
        'backgroundColorR': (color.r * 255).round(),
        'backgroundColorG': (color.g * 255).round(),
        'backgroundColorB': (color.b * 255).round(),
      }),
    );
  }

  static Future<void> setBrightness(
    BuildContext context,
    Brightness brightness,
  ) async {
    await _kChannel.invokeMethod<void>(
      'setBrightness',
      _args(getCurrentId(context), {'brightness': brightness.name}),
    );
  }

  static Future<void> setOpacity(BuildContext context, double opacity) async {
    await _kChannel.invokeMethod<void>(
        'setOpacity', _args(getCurrentId(context), {'opacity': opacity}));
  }

  static Future<double> getOpacity(BuildContext context) async {
    return await _kChannel.invokeMethod<double>(
            'getOpacity', _args(getCurrentId(context))) ??
        1.0;
  }

  static Future<bool> hasShadow(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'hasShadow', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setHasShadow(BuildContext context, bool value) async {
    await _kChannel.invokeMethod<void>(
        'setHasShadow', _args(getCurrentId(context), {'hasShadow': value}));
  }

  // -------------------------------------------------------------------------
  // Size & position
  // -------------------------------------------------------------------------

  static Future<Rect> getBounds(BuildContext context) async {
    final Map<dynamic, dynamic> r = await _kChannel.invokeMethod(
        'getBounds', _args(getCurrentId(context))) as Map;
    return Rect.fromLTWH(
      (r['x'] as num).toDouble(),
      (r['y'] as num).toDouble(),
      (r['width'] as num).toDouble(),
      (r['height'] as num).toDouble(),
    );
  }

  static Future<Size> getSize(BuildContext context) async =>
      (await getBounds(context)).size;

  static Future<Offset> getPosition(BuildContext context) async =>
      (await getBounds(context)).topLeft;

  static Future<void> setSize(BuildContext context, Size size) async {
    await _kChannel.invokeMethod<void>(
      'setSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setPosition(
    BuildContext context,
    Offset position,
  ) async {
    await _kChannel.invokeMethod<void>(
      'setPosition',
      _args(getCurrentId(context), {'x': position.dx, 'y': position.dy}),
    );
  }

  static Future<void> center(BuildContext context) async {
    await _kChannel.invokeMethod<void>('center', _args(getCurrentId(context)));
  }

  static Future<void> setMinimumSize(BuildContext context, Size size) async {
    await _kChannel.invokeMethod<void>(
      'setMinimumSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setMaximumSize(BuildContext context, Size size) async {
    await _kChannel.invokeMethod<void>(
      'setMaximumSize',
      _args(getCurrentId(context), {'width': size.width, 'height': size.height}),
    );
  }

  static Future<void> setAspectRatio(
    BuildContext context,
    double ratio,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setAspectRatio',
        _args(getCurrentId(context), {'aspectRatio': ratio}));
  }

  // -------------------------------------------------------------------------
  // Visibility & focus
  // -------------------------------------------------------------------------

  static Future<void> show(BuildContext context) async {
    await _kChannel.invokeMethod<void>('show', _args(getCurrentId(context)));
  }

  static Future<void> hide(BuildContext context) async {
    await _kChannel.invokeMethod<void>('hide', _args(getCurrentId(context)));
  }

  static Future<bool> isVisible(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isVisible', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> focus(BuildContext context) async {
    await _kChannel.invokeMethod<void>('focus', _args(getCurrentId(context)));
  }

  static Future<void> blur(BuildContext context) async {
    await _kChannel.invokeMethod<void>('blur', _args(getCurrentId(context)));
  }

  static Future<bool> isFocused(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isFocused', _args(getCurrentId(context))) ??
        false;
  }

  // -------------------------------------------------------------------------
  // Maximize / minimize / full-screen
  // -------------------------------------------------------------------------

  static Future<bool> isMaximized(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isMaximized', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> maximize(
    BuildContext context, {
    bool vertically = false,
  }) async {
    await _kChannel.invokeMethod<void>(
        'maximize',
        _args(getCurrentId(context), {'vertically': vertically}));
  }

  static Future<void> unmaximize(BuildContext context) async {
    await _kChannel.invokeMethod<void>(
        'unmaximize', _args(getCurrentId(context)));
  }

  static Future<bool> isMinimized(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isMinimized', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> minimize(BuildContext context) async {
    await _kChannel.invokeMethod<void>('minimize', _args(getCurrentId(context)));
  }

  static Future<void> restore(BuildContext context) async {
    await _kChannel.invokeMethod<void>('restore', _args(getCurrentId(context)));
  }

  static Future<bool> isFullScreen(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isFullScreen', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> setFullScreen(
    BuildContext context,
    bool isFullScreen,
  ) async {
    await _kChannel.invokeMethod<void>(
      'setFullScreen',
      _args(getCurrentId(context), {'isFullScreen': isFullScreen}),
    );
  }

  // -------------------------------------------------------------------------
  // Resizability & movability
  // -------------------------------------------------------------------------

  static Future<bool> isResizable(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isResizable', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setResizable(
    BuildContext context,
    bool isResizable,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setResizable',
        _args(getCurrentId(context), {'isResizable': isResizable}));
  }

  static Future<bool> isMovable(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isMovable', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setMovable(BuildContext context, bool isMovable) async {
    await _kChannel.invokeMethod<void>(
        'setMovable', _args(getCurrentId(context), {'isMovable': isMovable}));
  }

  static Future<bool> isMinimizable(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isMinimizable', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setMinimizable(
    BuildContext context,
    bool isMinimizable,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setMinimizable',
        _args(getCurrentId(context), {'isMinimizable': isMinimizable}));
  }

  static Future<bool> isMaximizable(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isMaximizable', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setMaximizable(
    BuildContext context,
    bool isMaximizable,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setMaximizable',
        _args(getCurrentId(context), {'isMaximizable': isMaximizable}));
  }

  static Future<bool> isClosable(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isClosable', _args(getCurrentId(context))) ??
        true;
  }

  static Future<void> setClosable(BuildContext context, bool isClosable) async {
    await _kChannel.invokeMethod<void>(
        'setClosable',
        _args(getCurrentId(context), {'isClosable': isClosable}));
  }

  // -------------------------------------------------------------------------
  // Always-on-top / taskbar
  // -------------------------------------------------------------------------

  static Future<bool> isAlwaysOnTop(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isAlwaysOnTop', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> setAlwaysOnTop(
    BuildContext context,
    bool isAlwaysOnTop,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setAlwaysOnTop',
        _args(getCurrentId(context), {'isAlwaysOnTop': isAlwaysOnTop}));
  }

  static Future<bool> isSkipTaskbar(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isSkipTaskbar', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> setSkipTaskbar(
    BuildContext context,
    bool isSkipTaskbar,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setSkipTaskbar',
        _args(getCurrentId(context), {'isSkipTaskbar': isSkipTaskbar}));
  }

  // -------------------------------------------------------------------------
  // Drag & resize (used by DragToMoveArea / DragToResizeArea)
  // -------------------------------------------------------------------------

  static Future<void> startDragging(BuildContext context) async {
    await _kChannel.invokeMethod<void>(
        'startDragging', _args(getCurrentId(context)));
  }

  static Future<void> startResizing(
    BuildContext context,
    ResizeEdge edge,
  ) async {
    await _kChannel.invokeMethod<void>(
      'startResizing',
      _args(getCurrentId(context), {
        'resizeEdge': edge.name,
        'top': edge == ResizeEdge.top ||
            edge == ResizeEdge.topLeft ||
            edge == ResizeEdge.topRight,
        'bottom': edge == ResizeEdge.bottom ||
            edge == ResizeEdge.bottomLeft ||
            edge == ResizeEdge.bottomRight,
        'right': edge == ResizeEdge.right ||
            edge == ResizeEdge.topRight ||
            edge == ResizeEdge.bottomRight,
        'left': edge == ResizeEdge.left ||
            edge == ResizeEdge.topLeft ||
            edge == ResizeEdge.bottomLeft,
      }),
    );
  }

  // -------------------------------------------------------------------------
  // macOS-specific
  // -------------------------------------------------------------------------

  static Future<bool> isVisibleOnAllWorkspaces(BuildContext context) async {
    return await _kChannel.invokeMethod<bool>(
            'isVisibleOnAllWorkspaces', _args(getCurrentId(context))) ??
        false;
  }

  static Future<void> setVisibleOnAllWorkspaces(
    BuildContext context,
    bool visible, {
    bool visibleOnFullScreen = false,
  }) async {
    await _kChannel.invokeMethod<void>(
      'setVisibleOnAllWorkspaces',
      _args(getCurrentId(context),
          {'visible': visible, 'visibleOnFullScreen': visibleOnFullScreen}),
    );
  }

  static Future<void> setBadgeLabel(
    BuildContext context, [
    String? label,
  ]) async {
    await _kChannel.invokeMethod<void>(
        'setBadgeLabel', _args(getCurrentId(context), {'label': label ?? ''}));
  }

  // -------------------------------------------------------------------------
  // Progress bar (Windows / macOS)
  // -------------------------------------------------------------------------

  static Future<void> setProgressBar(
    BuildContext context,
    double progress,
  ) async {
    await _kChannel.invokeMethod<void>(
        'setProgressBar',
        _args(getCurrentId(context), {'progress': progress}));
  }

  // -------------------------------------------------------------------------
  // Mouse events
  // -------------------------------------------------------------------------

  static Future<void> setIgnoreMouseEvents(
    BuildContext context,
    bool ignore, {
    bool forward = false,
  }) async {
    await _kChannel.invokeMethod<void>(
      'setIgnoreMouseEvents',
      _args(getCurrentId(context), {'ignore': ignore, 'forward': forward}),
    );
  }

  static Future<void> popUpWindowMenu(BuildContext context) async {
    await _kChannel.invokeMethod<void>(
        'popUpWindowMenu', _args(getCurrentId(context)));
  }
}
