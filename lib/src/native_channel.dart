import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'utils/calc_window_position.dart';

class NativeChannel {
  static const MethodChannel _staticChannel = MethodChannel('multiview_desktop');

  int? mainId;

  /// Builds an argument map that always includes the [viewId] so the native
  /// side can route the call to the right OS window.
  static Map<String, dynamic> _args(int viewId, [Map<String, dynamic>? extra]) {
    final map = <String, dynamic>{'viewId': viewId};
    if (extra != null) map.addAll(extra);
    return map;
  }

  void setMethodCallHandler(Future<dynamic> Function(MethodCall) handler) =>
      _staticChannel.setMethodCallHandler(handler);

  Future<void> createWindowRequest({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
  }) async {
    await _staticChannel.invokeMethod<void>('createWindow', {
      'token': token,
      'width': windowSize.width,
      'height': windowSize.height,
      'title': title,
      'position': pos == null ? null : {'x': pos.dx, 'y': pos.dy},
      'titleBarStyle': titleBarStyleStr,
      'windowButtonVisibility': windowButtonVisibility,
    });
  }

  Future<void> setSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>('setSize', _args(viewId, {'width': size.width, 'height': size.height}));
  }

  Future<void> setMinSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>(
      'setMinimumSize',
      _args(viewId, {'width': size.width, 'height': size.height}),
    );
  }

  Future<void> setMaxSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>(
      'setMaximumSize',
      _args(viewId, {'width': size.width, 'height': size.height}),
    );
  }

  Future<void> setAlignment(int viewId, {required Alignment alignment}) async {
    final pos = await _calculateOffFromAlign(viewId, alignment: alignment);
    if (pos != null) {
      await setPosition(viewId, pos: pos);
    }
  }

  Future<Offset?> _calculateOffFromAlign(int viewId, {required Alignment alignment}) async {
    final sizeResult = await _staticChannel.invokeMethod<Map>('getBounds', _args(viewId));
    if (sizeResult != null) {
      final windowSize = Size((sizeResult['width'] as num).toDouble(), (sizeResult['height'] as num).toDouble());
      return calcWindowPosition(windowSize, alignment);
    }
    return null;
  }

  Future<void> setPosition(int viewId, {required Offset pos}) async =>
      await _staticChannel.invokeMethod<void>('setPosition', _args(viewId, {'x': pos.dx, 'y': pos.dy}));

  Future<Rect> getBounds(int viewId) async {
    final Map<dynamic, dynamic> r = await _staticChannel.invokeMethod('getBounds', _args(viewId));
    return Rect.fromLTWH(
      (r['x'] as num).toDouble(),
      (r['y'] as num).toDouble(),
      (r['width'] as num).toDouble(),
      (r['height'] as num).toDouble(),
    );
  }

  Future<void> setBackgroundColor(int viewId, {required Color color}) async {
    await _staticChannel.invokeMethod<void>(
      'setBackgroundColor',
      _args(viewId, {
        'backgroundColorA': (color.a * 255).round(),
        'backgroundColorR': (color.r * 255).round(),
        'backgroundColorG': (color.g * 255).round(),
        'backgroundColorB': (color.b * 255).round(),
      }),
    );
  }

  Future<void> setTitle(int viewId, {required String title}) async {
    await _staticChannel.invokeMethod<void>('setTitle', _args(viewId, {'title': title}));
  }

  Future<String> getTitle(int viewId) async {
    return await _staticChannel.invokeMethod<String>('getTitle', _args(viewId)) ?? '';
  }

  Future<void> setTitleBarStyle(int viewId, {required TitleBarStyle style, required bool buttonVisibility}) async {
    await _staticChannel.invokeMethod<void>(
      'setTitleBarStyle',
      _args(viewId, {'titleBarStyle': style.name, 'windowButtonVisibility': buttonVisibility}),
    );
  }

  Future<({TitleBarStyle? style, bool? buttonVisibility})> getTitleBarStyle(int viewId) async {
    final mapResult = await _staticChannel.invokeMethod<Map<Object?, Object?>>('getTitleBarStyle', _args(viewId));

    return (
      style: _barStyleFromJson(mapResult?['style'] as String?),
      buttonVisibility: mapResult?['windowButtonVisibility'] as bool?,
    );
  }

  Future<void> setAsFrameless(int viewId) async {
    await _staticChannel.invokeMethod<void>('setAsFrameless', _args(viewId));
  }

  TitleBarStyle _barStyleFromJson(String? styleStr) {
    if (styleStr == 'hidden') return TitleBarStyle.hidden;
    return TitleBarStyle.normal;
  }

  Future<void> setAlwaysOnTop(int viewId, {required bool isAlwaysOnTop}) async {
    await _staticChannel.invokeMethod<void>('setAlwaysOnTop', _args(viewId, {'isAlwaysOnTop': isAlwaysOnTop}));
  }

  Future<void> setFullScreen(int viewId, {required bool isFullScreen}) async {
    await _staticChannel.invokeMethod<void>('setFullScreen', _args(viewId, {'isFullScreen': isFullScreen}));
  }

  Future<void> hideAppFromTaskbar({required bool isHideAppFromTaskbar}) async {
    await _staticChannel.invokeMethod<void>(
      'hideAppFromTaskbar',
      _args(1, {'isHideAppFromTaskbar': isHideAppFromTaskbar}),
    );
  }

  Future<void> softCloseWindow(int viewId) async {
    await _staticChannel.invokeMethod<void>('closeWindow', _args(viewId));
  }

  Future<void> forceCloseWindow(int viewId) async {
    if (viewId == mainId) {
      await setMainPreConfirmClose(true);
    }
    await setPreventClose(viewId, isPreventClose: false);
    await softCloseWindow(viewId);
  }

  Future<void> focus(int viewId) async {
    await _staticChannel.invokeMethod<void>('focus', _args(viewId));
  }

  Future<void> setMainPreConfirmClose(bool isPreConfirm) async {
    if (mainId == null) return;

    return _staticChannel.invokeMethod<void>(
      'mainPreConfirmClose',
      _args(mainId!, {'mainPreConfirmClose': isPreConfirm}),
    );
  }

  Future<void> setConfirmClose(int viewId, {required bool isConfirm}) async =>
      await _staticChannel.invokeMethod<void>('confirmClose', _args(viewId, {'confirmClose': isConfirm}));

  Future<void> setPreventClose(int viewId, {required bool isPreventClose}) async =>
      await _staticChannel.invokeMethod<void>('setPreventClose', _args(viewId, {'isPreventClose': isPreventClose}));

  Future<bool> isPreventClose(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isPreventClose', _args(viewId)) ?? false;
  }

  Future<void> setBrightness(int viewId, Brightness brightness) async {
    await _staticChannel.invokeMethod<void>('setBrightness', _args(viewId, {'brightness': brightness.name}));
  }

  Future<void> setOpacity(int viewId, double opacity) async {
    await _staticChannel.invokeMethod<void>('setOpacity', _args(viewId, {'opacity': opacity}));
  }

  Future<double> getOpacity(int viewId) async {
    return await _staticChannel.invokeMethod<double>('getOpacity', _args(viewId)) ?? 1.0;
  }

  Future<bool> hasShadow(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('hasShadow', _args(viewId)) ?? true;
  }

  Future<void> setHasShadow(int viewId, bool value) async {
    await _staticChannel.invokeMethod<void>('setHasShadow', _args(viewId, {'hasShadow': value}));
  }

  Future<Size> getSize(int viewId) async => (await getBounds(viewId)).size;

  Future<Offset> getPosition(int viewId) async => (await getBounds(viewId)).topLeft;

  Future<void> setAspectRatio(int viewId, double ratio) async {
    await _staticChannel.invokeMethod<void>('setAspectRatio', _args(viewId, {'aspectRatio': ratio}));
  }

  Future<void> show(int viewId) async {
    await _staticChannel.invokeMethod<void>('show', _args(viewId));
  }

  Future<void> hide(int viewId) async {
    await _staticChannel.invokeMethod<void>('hide', _args(viewId));
  }

  Future<bool> isVisible(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isVisible', _args(viewId)) ?? true;
  }

  Future<void> blur(int viewId) async {
    await _staticChannel.invokeMethod<void>('blur', _args(viewId));
  }

  Future<bool> isFocused(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isFocused', _args(viewId)) ?? false;
  }

  Future<bool> isMaximized(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isMaximized', _args(viewId)) ?? false;
  }

  Future<void> maximize(int viewId, {bool vertically = false}) async {
    await _staticChannel.invokeMethod<void>('maximize', _args(viewId, {'vertically': vertically}));
  }

  Future<void> unmaximize(int viewId) async {
    await _staticChannel.invokeMethod<void>('unmaximize', _args(viewId));
  }

  Future<bool> isMinimized(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isMinimized', _args(viewId)) ?? false;
  }

  Future<void> minimize(int viewId) async {
    await _staticChannel.invokeMethod<void>('minimize', _args(viewId));
  }

  Future<void> restore(int viewId) async {
    await _staticChannel.invokeMethod<void>('restore', _args(viewId));
  }

  Future<bool> isFullScreen(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isFullScreen', _args(viewId)) ?? false;
  }

  Future<bool> isResizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isResizable', _args(viewId)) ?? true;
  }

  Future<void> setResizable(int viewId, bool isResizable) async {
    await _staticChannel.invokeMethod<void>('setResizable', _args(viewId, {'isResizable': isResizable}));
  }

  Future<bool> isMovable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isMovable', _args(viewId)) ?? true;
  }

  Future<void> setMovable(int viewId, bool isMovable) async {
    await _staticChannel.invokeMethod<void>('setMovable', _args(viewId, {'isMovable': isMovable}));
  }

  Future<bool> isMinimizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isMinimizable', _args(viewId)) ?? true;
  }

  Future<void> setMinimizable(int viewId, bool isMinimizable) async {
    await _staticChannel.invokeMethod<void>('setMinimizable', _args(viewId, {'isMinimizable': isMinimizable}));
  }

  Future<bool> isMaximizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isMaximizable', _args(viewId)) ?? true;
  }

  Future<void> setMaximizable(int viewId, bool isMaximizable) async {
    await _staticChannel.invokeMethod<void>('setMaximizable', _args(viewId, {'isMaximizable': isMaximizable}));
  }

  Future<bool> isClosable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isClosable', _args(viewId)) ?? true;
  }

  Future<void> setClosable(int viewId, bool isClosable) async {
    await _staticChannel.invokeMethod<void>('setClosable', _args(viewId, {'isClosable': isClosable}));
  }

  Future<bool> isAlwaysOnTop(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isAlwaysOnTop', _args(1)) ?? false;
  }

  Future<bool> isHideAppFromTaskbar() async {
    final res = await _staticChannel.invokeMethod('isHideAppFromTaskbar', _args(1));
    return res ?? false;
  }

  Future<void> startDragging(int viewId) async {
    await _staticChannel.invokeMethod<void>('startDragging', _args(viewId));
  }

  Future<void> startResizing(int viewId, ResizeEdge edge) async {
    await _staticChannel.invokeMethod<void>(
      'startResizing',
      _args(viewId, {
        'resizeEdge': edge.name,
        'top': edge == ResizeEdge.top || edge == ResizeEdge.topLeft || edge == ResizeEdge.topRight,
        'bottom': edge == ResizeEdge.bottom || edge == ResizeEdge.bottomLeft || edge == ResizeEdge.bottomRight,
        'right': edge == ResizeEdge.right || edge == ResizeEdge.topRight || edge == ResizeEdge.bottomRight,
        'left': edge == ResizeEdge.left || edge == ResizeEdge.topLeft || edge == ResizeEdge.bottomLeft,
      }),
    );
  }

  Future<bool> isHideFromCollection(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isHideFromCollection', _args(viewId)) ?? false;
  }

  Future<void> hideFromCollection(int viewId, bool isHideFromCollection) async {
    await _staticChannel.invokeMethod<void>(
      'hideFromCollection',
      _args(viewId, {'isHideFromCollection': isHideFromCollection}),
    );
  }

  Future<bool> isVisibleOnAllWorkspaces(int viewId) async {
    return await _staticChannel.invokeMethod<bool>('isVisibleOnAllWorkspaces', _args(viewId)) ?? false;
  }

  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) async {
    await _staticChannel.invokeMethod<void>(
      'setVisibleOnAllWorkspaces',
      _args(viewId, {'visible': visible, 'visibleOnFullScreen': visibleOnFullScreen}),
    );
  }

  Future<void> setBadgeLabel(int viewId, {required String? label}) async {
    await _staticChannel.invokeMethod<void>('setBadgeLabel', _args(viewId, {'label': label ?? ''}));
  }

  Future<void> setProgressBar(double progress) async {
    await _staticChannel.invokeMethod<void>('setProgressBar', _args(1, {'progress': progress}));
  }

  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) async {
    await _staticChannel.invokeMethod<void>(
      'setIgnoreMouseEvents',
      _args(viewId, {'ignore': ignore, 'forward': forward}),
    );
  }

  Future<void> popUpWindowMenu(int viewId) async {
    await _staticChannel.invokeMethod<void>('popUpWindowMenu', _args(viewId));
  }
}
