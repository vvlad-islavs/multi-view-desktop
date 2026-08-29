import 'dart:convert' show utf8;
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show Brightness, Color, Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/resize_edge.dart';
import 'package:multiview_desktop/src/title_bar_style.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';

// Native files: MvdFfiBridge.swift, mvd_ffi_bridge.cpp, mvd_ffi_bridge.cc
// Symbol convention: mvd_<verb>_<noun>

typedef _PtrU8N = Pointer<Uint8> Function();
typedef _PtrU8D = Pointer<Uint8> Function();
typedef _PtrI32N = Pointer<Int32> Function();
typedef _PtrI32D = Pointer<Int32> Function();
typedef _PtrFN = Pointer<Double> Function();
typedef _PtrFD = Pointer<Double> Function();

typedef _V0N = Void Function();
typedef _V0D = void Function();
typedef _V1N = Void Function(Int64);
typedef _V1D = void Function(int);
typedef _VbN = Void Function(Int64, Int32);
typedef _VbD = void Function(int, int);
typedef _VdN = Void Function(Int64, Double);
typedef _VdD = void Function(int, double);
typedef _V2dN = Void Function(Int64, Double, Double);
typedef _V2dD = void Function(int, double, double);
typedef _V4dN = Void Function(Int64, Double, Double, Double, Double);
typedef _V4dD = void Function(int, double, double, double, double);
typedef _V4iN = Void Function(Int64, Int32, Int32, Int32, Int32);
typedef _V4iD = void Function(int, int, int, int, int);
typedef _V3iN = Void Function(Int64, Int32, Int32, Int32);
typedef _V3iD = void Function(int, int, int, int);
typedef _VColorN = Void Function(Int64, Int32, Int32, Int32, Int32);
typedef _VColorD = void Function(int, int, int, int, int);
typedef _V2bN = Void Function(Int64, Int32, Int32);
typedef _V2bD = void Function(int, int, int);

typedef _I0N = Int32 Function();
typedef _I0D = int Function();
typedef _I1N = Int32 Function(Int64);
typedef _I1D = int Function(int);
typedef _D1N = Double Function(Int64);
typedef _D1D = double Function(int);

typedef _CreateWinN = Int64 Function(Int64, Double, Double, Int32, Int32, Double, Double, Int64);
typedef _CreateWinD = int Function(int, double, double, int, int, double, double, int);
typedef _CreateDlgN = Int64 Function(Int64, Int64, Double, Double, Int32, Int32, Int32, Double, Double);
typedef _CreateDlgD = int Function(int, int, double, double, int, int, int, double, double);
typedef _CreatePopN = Int64 Function(Int64, Int64, Double, Double);
typedef _CreatePopD = int Function(int, int, double, double);
typedef _DispN = Void Function(Double, Double, Double, Double);
typedef _DispD = void Function(double, double, double, double);
typedef _ProgN = Void Function(Double);
typedef _ProgD = void Function(double);
typedef _AddMenuN = Void Function(Int32);
typedef _AddMenuD = void Function(int);
typedef _VBoolN = Void Function(Int32);
typedef _VBoolD = void Function(int);
typedef _EventCbN = Void Function(Pointer<Char>, Int64, Int64);
typedef _SetEventCbN = Void Function(Pointer<NativeFunction<_EventCbN>>);
typedef _SetEventCbD = void Function(Pointer<NativeFunction<_EventCbN>>);

const _kNoViewId = -1;

const _kRectBufSymbol = 'mvd_rect_buf_ptr';
const _kStrCap = 8192;

/// Synchronous FFI surface mirroring [NativeChannel], without replacing it.
///
/// Channel handlers keep working. This bridge calls the same native functions.
@internal
abstract class FfiBridge {
  FfiBridge._() : _lib = null;

  FfiBridge._native(this._lib);

  static final FfiBridge instance = _create();

  static FfiBridge _create() {
    try {
      if (Platform.isMacOS) return FfiMacosBridge();
      if (Platform.isWindows) return FfiWinBridge();
      if (Platform.isLinux) return FfiLinuxBridge();
    } on Object {
      // Missing plugin binary or symbols: methods become no-ops.
    }
    return _UnsupportedFfiBridge();
  }

  final DynamicLibrary? _lib;

  bool get _supported => _lib != null;

  late final _getRectBufPtr = _lib!.lookupFunction<_PtrFN, _PtrFD>(_kRectBufSymbol);
  late final _getStrBufPtr = _lib!.lookupFunction<_PtrU8N, _PtrU8D>('mvd_str_buf_ptr');
  late final _getStrBuf2Ptr = _lib!.lookupFunction<_PtrU8N, _PtrU8D>('mvd_str_buf2_ptr');
  late final _getI32BufPtr = _lib!.lookupFunction<_PtrI32N, _PtrI32D>('mvd_i32_buf_ptr');

  late final Float64List _buf = _getRectBufPtr().asTypedList(4);
  late final Uint8List _str = _getStrBufPtr().asTypedList(_kStrCap);
  late final Uint8List _str2 = _getStrBuf2Ptr().asTypedList(_kStrCap);
  late final Int32List _i32 = _getI32BufPtr().asTypedList(8);

  late final _createWindowN = _lib!.lookupFunction<_CreateWinN, _CreateWinD>('mvd_create_window');
  late final _createDialogN = _lib!.lookupFunction<_CreateDlgN, _CreateDlgD>('mvd_create_modal_dialog');
  late final _completeModalDialogN = _lib!.lookupFunction<_V1N, _V1D>('mvd_complete_modal_dialog');
  late final _createPopupN = _lib!.lookupFunction<_CreatePopN, _CreatePopD>('mvd_create_popup');
  late final _checkExistN = _lib!.lookupFunction<_I1N, _I1D>('mvd_check_exist');
  late final _setAnchorN = _lib!.lookupFunction<_V1N, _V1D>('mvd_set_anchor_view_id');
  late final _setTerminateN = _lib!.lookupFunction<_VBoolN, _VBoolD>('mvd_set_terminate_after_last');
  late final _replyTerminateN = _lib!.lookupFunction<_VBoolN, _VBoolD>('mvd_reply_terminate');
  late final _setHasTaskbarCbN = _lib!.lookupFunction<_VBoolN, _VBoolD>('mvd_set_has_taskbar_callback');
  late final _isHideAppN = _lib!.lookupFunction<_I0N, _I0D>('mvd_is_hide_app_from_taskbar');
  late final _setProgressN = _lib!.lookupFunction<_ProgN, _ProgD>('mvd_set_progress_bar');
  late final _menuClearN = _lib!.lookupFunction<_V0N, _V0D>('mvd_taskbar_menu_clear');
  late final _menuAddN = _lib!.lookupFunction<_AddMenuN, _AddMenuD>('mvd_taskbar_menu_add');
  late final _menuCommitN = _lib!.lookupFunction<_V0N, _V0D>('mvd_taskbar_menu_commit');

  late final _getFrameN = _lib!.lookupFunction<_V1N, _V1D>('mvd_get_frame');
  late final _setFrameN = _lib!.lookupFunction<_V4dN, _V4dD>('mvd_set_frame');
  late final _getDisplayRectN = _lib!.lookupFunction<_DispN, _DispD>('mvd_get_display_rect');
  late final _setSizeN = _lib!.lookupFunction<_V2dN, _V2dD>('mvd_set_size');
  late final _setPositionN = _lib!.lookupFunction<_V2dN, _V2dD>('mvd_set_position');
  late final _setMinSizeN = _lib!.lookupFunction<_V2dN, _V2dD>('mvd_set_min_size');
  late final _setMaxSizeN = _lib!.lookupFunction<_V2dN, _V2dD>('mvd_set_max_size');
  late final _setBgN = _lib!.lookupFunction<_VColorN, _VColorD>('mvd_set_background_color');
  late final _setTitleN = _lib!.lookupFunction<_V1N, _V1D>('mvd_set_title');
  late final _getTitleN = _lib!.lookupFunction<_I1N, _I1D>('mvd_get_title');
  late final _setTitleBarN = _lib!.lookupFunction<_V3iN, _V3iD>('mvd_set_title_bar_style');
  late final _getTitleBarN = _lib!.lookupFunction<_I1N, _I1D>('mvd_get_title_bar_style');
  late final _setFramelessN = _lib!.lookupFunction<_V1N, _V1D>('mvd_set_as_frameless');
  late final _setAlwaysOnTopN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_always_on_top');
  late final _isAlwaysOnTopN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_always_on_top');
  late final _setFullScreenN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_full_screen');
  late final _isFullScreenN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_full_screen');
  late final _hideAppFromTaskbarN = _lib!.lookupFunction<_VbN, _VbD>('mvd_hide_app_from_taskbar');
  late final _isHideTabN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_hide_app_tab_from_taskbar');
  late final _closeN = _lib!.lookupFunction<_V1N, _V1D>('mvd_close_window');
  late final _destroyN = _lib!.lookupFunction<_V1N, _V1D>('mvd_destroy_window');
  late final _focusN = _lib!.lookupFunction<_V1N, _V1D>('mvd_focus');
  late final _blurN = _lib!.lookupFunction<_V1N, _V1D>('mvd_blur');
  late final _setPreConfirmN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_pre_confirm');
  late final _setConfirmN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_confirm');
  late final _setPreventN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_prevent_close');
  late final _isPreventN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_prevent_close');
  late final _setBrightnessN = _lib!.lookupFunction<_V1N, _V1D>('mvd_set_brightness');
  late final _setOpacityN = _lib!.lookupFunction<_VdN, _VdD>('mvd_set_opacity');
  late final _getOpacityN = _lib!.lookupFunction<_D1N, _D1D>('mvd_get_opacity');
  late final _hasShadowN = _lib!.lookupFunction<_I1N, _I1D>('mvd_has_shadow');
  late final _setHasShadowN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_has_shadow');
  late final _setAspectN = _lib!.lookupFunction<_VdN, _VdD>('mvd_set_aspect_ratio');
  late final _showN = _lib!.lookupFunction<_V1N, _V1D>('mvd_show');
  late final _hideN = _lib!.lookupFunction<_V1N, _V1D>('mvd_hide');
  late final _isVisibleN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_visible');
  late final _isFocusedN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_focused');
  late final _isOnActiveSpaceN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_on_active_space');
  late final _maximizeN = _lib!.lookupFunction<_VbN, _VbD>('mvd_maximize');
  late final _unmaximizeN = _lib!.lookupFunction<_V1N, _V1D>('mvd_unmaximize');
  late final _isMaximizedN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_maximized');
  late final _minimizeN = _lib!.lookupFunction<_V1N, _V1D>('mvd_minimize');
  late final _restoreN = _lib!.lookupFunction<_V1N, _V1D>('mvd_restore');
  late final _isMinimizedN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_minimized');
  late final _isResizableN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_resizable');
  late final _setResizableN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_resizable');
  late final _isMovableN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_movable');
  late final _setMovableN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_movable');
  late final _isMinimizableN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_minimizable');
  late final _setMinimizableN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_minimizable');
  late final _isMaximizableN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_maximizable');
  late final _setMaximizableN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_maximizable');
  late final _isClosableN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_closable');
  late final _setClosableN = _lib!.lookupFunction<_VbN, _VbD>('mvd_set_closable');
  late final _startDraggingN = _lib!.lookupFunction<_V1N, _V1D>('mvd_start_dragging');
  late final _startResizingN = _lib!.lookupFunction<_V4iN, _V4iD>('mvd_start_resizing');
  late final _isHideFromCollectionN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_hide_from_collection');
  late final _hideFromCollectionN = _lib!.lookupFunction<_VbN, _VbD>('mvd_hide_from_collection');
  late final _isVisibleOnAllWsN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_visible_on_all_workspaces');
  late final _setVisibleOnAllWsN = _lib!.lookupFunction<_V2bN, _V2bD>('mvd_set_visible_on_all_workspaces');
  late final _setBadgeN = _lib!.lookupFunction<_V1N, _V1D>('mvd_set_badge_label');
  late final _setIgnoreN = _lib!.lookupFunction<_V2bN, _V2bD>('mvd_set_ignore_mouse_events');
  late final _isIgnoreN = _lib!.lookupFunction<_I1N, _I1D>('mvd_is_ignore_mouse_events');
  late final _popupMenuN = _lib!.lookupFunction<_V1N, _V1D>('mvd_pop_up_window_menu');
  late final _setEventCallbackN = _lib!.lookupFunction<_SetEventCbN, _SetEventCbD>('mvd_set_event_callback');

  NativeCallable<_EventCbN>? _eventCallable;
  dynamic Function(MethodCall)? _eventHandler;

  void _writeStr(Uint8List buf, String s) {
    final units = utf8.encode(s);
    final n = units.length < _kStrCap - 1 ? units.length : _kStrCap - 1;
    buf.setRange(0, n, units);
    buf[n] = 0;
  }

  String _readStr(Uint8List buf) {
    var n = 0;
    while (n < buf.length && buf[n] != 0) {
      n++;
    }
    return utf8.decode(buf.sublist(0, n));
  }

  bool _b(int Function(int) fn, int viewId, {bool fallback = false}) {
    if (!_supported) return fallback;
    return fn(viewId) != 0;
  }

  void _v(void Function(int) fn, int viewId) {
    if (!_supported) return;
    fn(viewId);
  }

  /// Native -> Dart events (`onEvent`). Same handler shape as [NativeChannel.setMethodCallHandler].
  void setMethodCallHandler(dynamic Function(MethodCall) handler) {
    _eventHandler = handler;
    _ensureEventCallable();
  }

  void _ensureEventCallable() {
    if (!_supported || _eventCallable != null) return;
    try {
      _eventCallable = NativeCallable<_EventCbN>.isolateLocal(_dispatchNativeEvent);
      _setEventCallbackN(_eventCallable!.nativeFunction);
    } on ArgumentError {
      _eventCallable?.close();
      _eventCallable = null;
    }
  }

  /// Drops the native event pointer before [NativeCallable.close].
  ///
  /// Closing first leaves a dangling C function in `_eventCb`; Cmd+Q then
  /// crashes in `windowShouldClose` with "Callback invoked after it has been deleted".
  void closeIsolateLocal() {
    _eventHandler = null;
    if (_supported) {
      _setEventCallbackN(nullptr);
    }
    _eventCallable?.close();
    _eventCallable = null;
  }

  void _dispatchNativeEvent(Pointer<Char> namePtr, int viewId, int arg) {
    final handler = _eventHandler;
    if (handler == null) return;
    final eventName = _readCString(namePtr);
    final args = <String, dynamic>{'eventName': eventName};
    if (viewId != _kNoViewId) args['viewId'] = viewId;
    if (eventName == 'viewCreated') args['token'] = arg;
    if (eventName == 'taskbarMenuItemSelected') args['id'] = arg;
    handler(MethodCall('onEvent', args));
  }

  String _readCString(Pointer<Char> p) {
    if (p == nullptr) return '';
    final bytes = p.cast<Uint8>();
    var n = 0;
    while (bytes[n] != 0) {
      n++;
    }
    return utf8.decode(bytes.asTypedList(n));
  }

  // Create — native returns the new Flutter view id, or -1 on failure.

  int createWindow({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    int? parentId,
  }) {
    if (!_supported) return _kNoViewId;
    _writeStr(_str, title);
    _writeStr(_str2, titleBarStyleStr);
    return _createWindowN(
      token,
      windowSize.width,
      windowSize.height,
      windowButtonVisibility ? 1 : 0,
      pos != null ? 1 : 0,
      pos?.dx ?? 0,
      pos?.dy ?? 0,
      parentId ?? -1,
    );
  }

  int createDialog({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    required int parentId,
    required bool isModal,
  }) {
    if (!_supported) return _kNoViewId;
    _writeStr(_str, title);
    _writeStr(_str2, titleBarStyleStr);
    return _createDialogN(
      token,
      parentId,
      windowSize.width,
      windowSize.height,
      isModal ? 1 : 0,
      windowButtonVisibility ? 1 : 0,
      pos != null ? 1 : 0,
      pos?.dx ?? 0,
      pos?.dy ?? 0,
    );
  }

  int createPopupWindow({required int token, required int parentId, required Size windowSize}) {
    if (!_supported) return _kNoViewId;
    return _createPopupN(token, parentId, windowSize.width, windowSize.height);
  }

  void completeModalDialogCreate(int viewId) {
    if (!_supported) return;
    _completeModalDialogN(viewId);
  }

  void setAlignment(int viewId, {required Alignment alignment}) {
    final pos = _calculateOffFromAlign(viewId, alignment: alignment);
    if (pos != null) {
      setPosition(viewId, pos: pos);
    }
  }

  Offset? _calculateOffFromAlign(int viewId, {required Alignment alignment}) {
    final sizeResult = getBounds(viewId).size;
    final windowSize = Size(sizeResult.width, sizeResult.height);
    return WindowPositionCalculator.instance.calcWindowPosition(windowSize, alignment);
  }

  Size getSize(int viewId) => getBounds(viewId).size;

  Offset getPosition(int viewId) => getBounds(viewId).topLeft;

  bool checkWindowExist(int viewId) => _b(_checkExistN, viewId);

  void forceCloseView(int viewId) {
    setPreventClose(viewId, isPreventClose: false);
    softCloseWindow(viewId);
  }

  void setAnchorViewId(int viewId) => _v(_setAnchorN, viewId);

  void setSize(int viewId, {required Size size}) {
    if (!_supported) return;
    _setSizeN(viewId, size.width, size.height);
  }

  bool setPopupBounds(int viewId, {required Rect bounds}) {
    setFrame(viewId, bounds);
    return _supported;
  }

  void setMinSize(int viewId, {required Size size}) {
    if (!_supported) return;
    _setMinSizeN(viewId, size.width, size.height);
  }

  void setMaxSize(int viewId, {required Size size}) {
    if (!_supported) return;
    _setMaxSizeN(viewId, size.width, size.height);
  }

  void setPosition(int viewId, {required Offset pos}) {
    if (!_supported) return;
    _setPositionN(viewId, pos.dx, pos.dy);
  }

  /// Frame of the OS window [viewId] in Flutter logical coords.
  Rect? getFrame(int viewId) {
    if (!_supported) return null;
    _getFrameN(viewId);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  Rect getBounds(int viewId) => getFrame(viewId) ?? Rect.zero;

  /// Moves/resizes window [viewId] synchronously.
  void setFrame(int viewId, Rect rect) {
    if (!_supported) return;
    _setFrameN(viewId, rect.left, rect.top, rect.width, rect.height);
  }

  Rect? getDisplayRect(Rect query) {
    if (!_supported) return null;
    _getDisplayRectN(query.left, query.top, query.width, query.height);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  void setBackgroundColor(int viewId, {required Color color}) {
    if (!_supported) return;
    _setBgN(viewId, (color.a * 255).round(), (color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round());
  }

  void setTitle(int viewId, {required String title}) {
    if (!_supported) return;
    _writeStr(_str, title);
    _setTitleN(viewId);
  }

  String getTitle(int viewId) {
    if (!_supported) return '';
    if (_getTitleN(viewId) == 0) return '';
    return _readStr(_str);
  }

  void setTitleBarStyle(
    int viewId, {
    required TitleBarStyle style,
    required bool closeVisibility,
    required bool maximizeVisibility,
    required bool minimizeVisibility,
  }) {
    if (!_supported) return;
    _writeStr(_str, style.name);
    _setTitleBarN(viewId, closeVisibility ? 1 : 0, maximizeVisibility ? 1 : 0, minimizeVisibility ? 1 : 0);
  }

  ({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility}) getTitleBarStyle(
    int viewId,
  ) {
    if (!_supported || _getTitleBarN(viewId) == 0) {
      return (style: null, closeVisibility: null, maximizeVisibility: null, minimizeVisibility: null);
    }
    final name = _readStr(_str);
    return (
      style: name == 'hidden' ? TitleBarStyle.hidden : TitleBarStyle.normal,
      closeVisibility: _i32[0] != 0,
      maximizeVisibility: _i32[1] != 0,
      minimizeVisibility: _i32[2] != 0,
    );
  }

  void setAsFrameless(int viewId) => _v(_setFramelessN, viewId);

  void setAlwaysOnTop(int viewId, {required bool isAlwaysOnTop}) {
    if (!_supported) return;
    _setAlwaysOnTopN(viewId, isAlwaysOnTop ? 1 : 0);
  }

  void setFullScreen(int viewId, {required bool isFullScreen}) {
    if (!_supported) return;
    _setFullScreenN(viewId, isFullScreen ? 1 : 0);
  }

  void hideAppFromTaskbar(int viewId, {required bool isHideAppFromTaskbar}) {
    if (!_supported) return;
    _hideAppFromTaskbarN(viewId, isHideAppFromTaskbar ? 1 : 0);
  }

  void softCloseWindow(int viewId) => _v(_closeN, viewId);

  void destroyModalDialog(int viewId) => _v(_destroyN, viewId);

  void focus(int viewId) => _v(_focusN, viewId);

  void setPreConfirmClose(int viewId, bool isPreConfirm) {
    if (!_supported) return;
    _setPreConfirmN(viewId, isPreConfirm ? 1 : 0);
  }

  void setConfirmClose(int viewId, {required bool isConfirm}) {
    if (!_supported) return;
    _setConfirmN(viewId, isConfirm ? 1 : 0);
  }

  void setPreventClose(int viewId, {required bool isPreventClose}) {
    if (!_supported) return;
    _setPreventN(viewId, isPreventClose ? 1 : 0);
  }

  bool isPreventClose(int viewId) => _b(_isPreventN, viewId);

  void setBrightness(int viewId, Brightness brightness) {
    if (!_supported) return;
    _writeStr(_str, brightness.name);
    _setBrightnessN(viewId);
  }

  void setOpacity(int viewId, double opacity) {
    if (!_supported) return;
    _setOpacityN(viewId, opacity);
  }

  double getOpacity(int viewId) {
    if (!_supported) return 1.0;
    return _getOpacityN(viewId);
  }

  bool hasShadow(int viewId) => _b(_hasShadowN, viewId, fallback: true);

  void setHasShadow(int viewId, bool value) {
    if (!_supported) return;
    _setHasShadowN(viewId, value ? 1 : 0);
  }

  void setAspectRatio(int viewId, double ratio) {
    if (!_supported) return;
    _setAspectN(viewId, ratio);
  }

  void show(int viewId) => _v(_showN, viewId);

  void hide(int viewId) => _v(_hideN, viewId);

  bool isVisible(int viewId) => _b(_isVisibleN, viewId, fallback: true);

  void blur(int viewId) => _v(_blurN, viewId);

  bool isFocused(int viewId) => _b(_isFocusedN, viewId);

  bool isOnActiveSpace(int viewId) => _b(_isOnActiveSpaceN, viewId, fallback: true);

  bool isMaximized(int viewId) => _b(_isMaximizedN, viewId);

  void maximize(int viewId, {bool vertically = false}) {
    if (!_supported) return;
    _maximizeN(viewId, vertically ? 1 : 0);
  }

  void unmaximize(int viewId) => _v(_unmaximizeN, viewId);

  bool isMinimized(int viewId) => _b(_isMinimizedN, viewId);

  void minimize(int viewId) => _v(_minimizeN, viewId);

  void restore(int viewId) => _v(_restoreN, viewId);

  bool isFullScreen(int viewId) => _b(_isFullScreenN, viewId);

  bool isResizable(int viewId) => _b(_isResizableN, viewId, fallback: true);

  void setResizable(int viewId, bool isResizable) {
    if (!_supported) return;
    _setResizableN(viewId, isResizable ? 1 : 0);
  }

  bool isMovable(int viewId) => _b(_isMovableN, viewId, fallback: true);

  void setMovable(int viewId, bool isMovable) {
    if (!_supported) return;
    _setMovableN(viewId, isMovable ? 1 : 0);
  }

  bool isMinimizable(int viewId) => _b(_isMinimizableN, viewId, fallback: true);

  void setMinimizable(int viewId, bool isMinimizable) {
    if (!_supported) return;
    _setMinimizableN(viewId, isMinimizable ? 1 : 0);
  }

  bool isMaximizable(int viewId) => _b(_isMaximizableN, viewId, fallback: true);

  void setMaximizable(int viewId, bool isMaximizable) {
    if (!_supported) return;
    _setMaximizableN(viewId, isMaximizable ? 1 : 0);
  }

  bool isClosable(int viewId) => _b(_isClosableN, viewId, fallback: true);

  void setClosable(int viewId, bool isClosable) {
    if (!_supported) return;
    _setClosableN(viewId, isClosable ? 1 : 0);
  }

  bool isAlwaysOnTop(int viewId) => _b(_isAlwaysOnTopN, viewId);

  bool isHideAppFromTaskbar() {
    if (!_supported) return false;
    return _isHideAppN() != 0;
  }

  bool isHideAppTabFromTaskbar(int viewId) => _b(_isHideTabN, viewId);

  void startDragging(int viewId) => _v(_startDraggingN, viewId);

  void startResizing(int viewId, ResizeEdge edge) {
    if (!_supported) return;
    _writeStr(_str, edge.name);
    _startResizingN(
      viewId,
      edge == ResizeEdge.top || edge == ResizeEdge.topLeft || edge == ResizeEdge.topRight ? 1 : 0,
      edge == ResizeEdge.bottom || edge == ResizeEdge.bottomLeft || edge == ResizeEdge.bottomRight ? 1 : 0,
      edge == ResizeEdge.left || edge == ResizeEdge.topLeft || edge == ResizeEdge.bottomLeft ? 1 : 0,
      edge == ResizeEdge.right || edge == ResizeEdge.topRight || edge == ResizeEdge.bottomRight ? 1 : 0,
    );
  }

  bool isHideFromCollection(int viewId) => _b(_isHideFromCollectionN, viewId);

  void hideFromCollection(int viewId, bool isHideFromCollection) {
    if (!_supported) return;
    _hideFromCollectionN(viewId, isHideFromCollection ? 1 : 0);
  }

  bool isVisibleOnAllWorkspaces(int viewId) => _b(_isVisibleOnAllWsN, viewId);

  void setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) {
    if (!_supported) return;
    _setVisibleOnAllWsN(viewId, visible ? 1 : 0, visibleOnFullScreen ? 1 : 0);
  }

  void setBadgeLabel(int viewId, {required String? label}) {
    if (!_supported) return;
    _writeStr(_str, label ?? '');
    _setBadgeN(viewId);
  }

  void setProgressBar(double progress) {
    if (!_supported) return;
    _setProgressN(progress);
  }

  void setTaskbarMenu(List<Map<String, dynamic>> items) {
    if (!_supported) return;
    _menuClearN();
    for (final item in items) {
      _writeStr(_str, item['title'] as String? ?? '');
      _writeStr(_str2, item['icon'] as String? ?? '');
      _menuAddN((item['id'] as num?)?.toInt() ?? 0);
    }
    _menuCommitN();
  }

  void setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) {
    if (!_supported) return;
    _setIgnoreN(viewId, ignore ? 1 : 0, forward ? 1 : 0);
  }

  ({bool mouseMoveEvents, bool ignore}) isIgnoreMouseEvents(int viewId) {
    if (!_supported) return (mouseMoveEvents: false, ignore: false);
    final ignore = _isIgnoreN(viewId) != 0;
    return (mouseMoveEvents: _i32[0] != 0, ignore: ignore);
  }

  void popUpWindowMenu(int viewId) => _v(_popupMenuN, viewId);

  void setTerminateAfterLastWindowClosed(bool terminate) {
    if (!_supported) return;
    _setTerminateN(terminate ? 1 : 0);
  }

  void replyToApplicationShouldTerminate(bool terminate) {
    if (!_supported) return;
    _replyTerminateN(terminate ? 1 : 0);
  }

  void setHasTaskbarCallback(bool hasCallback) {
    if (!_supported) return;
    _setHasTaskbarCbN(hasCallback ? 1 : 0);
  }

  void resetWindowToDefaults(int viewId, MultiAppConfig config) {
    setPreventClose(viewId, isPreventClose: false);
    setPreConfirmClose(viewId, false);
    setConfirmClose(viewId, isConfirm: false);
    setResizable(viewId, true);
    setMovable(viewId, true);
    setMinimizable(viewId, true);
    setMaximizable(viewId, true);
    setClosable(viewId, true);
    setAlwaysOnTop(viewId, isAlwaysOnTop: config.globalWindowOptions.alwaysOnTop ?? false);
    setOpacity(viewId, 1);
    setAspectRatio(viewId, 0);
    setIgnoreMouseEvents(viewId, false);
    setTitleBarStyle(
      viewId,
      style: config.globalWindowOptions.titleBarStyle ?? TitleBarStyle.normal,
      closeVisibility: config.globalWindowOptions.windowButtonVisibility ?? false,
      minimizeVisibility: config.globalWindowOptions.windowButtonVisibility ?? false,
      maximizeVisibility: config.globalWindowOptions.windowButtonVisibility ?? false,
    );
  }
}

@internal
class FfiMacosBridge extends FfiBridge {
  FfiMacosBridge() : super._native(DynamicLibrary.process());
}

@internal
class FfiWinBridge extends FfiBridge {
  FfiWinBridge() : super._native(DynamicLibrary.open('multiview_desktop_plugin.dll'));
}

@internal
class FfiLinuxBridge extends FfiBridge {
  FfiLinuxBridge() : super._native(_open());

  static DynamicLibrary _open() {
    final process = DynamicLibrary.process();
    try {
      process.lookup(_kRectBufSymbol);
      return process;
    } on ArgumentError {
      return DynamicLibrary.open('libmultiview_desktop_plugin.so');
    }
  }
}

class _UnsupportedFfiBridge extends FfiBridge {
  _UnsupportedFfiBridge() : super._();
}

/// Test double that records FFI calls without loading the native plugin.
///
/// Lives in this library so it can use [FfiBridge._] (private constructor).
@visibleForTesting
class RecordingFfiBridge extends FfiBridge {
  RecordingFfiBridge() : super._();

  final List<String> calls = [];
  int nextViewId = 100;

  /// When non-null, the next create* call returns this id (e.g. error code) once.
  int? nextCreateResult;

  /// Optional canned bounds for [getFrame] / [getBounds].
  final Map<int, Rect> frames = {};

  /// Optional canned opacity for [getOpacity].
  final Map<int, double> opacities = {};

  void _rec(String call) => calls.add(call);

  bool hasCall(String prefix) => calls.any((c) => c.startsWith(prefix));

  List<String> callsFor(String method) => calls.where((c) => c.startsWith('$method:')).toList();

  int _nextCreateId() {
    final forced = nextCreateResult;
    if (forced != null) {
      nextCreateResult = null;
      return forced;
    }
    return nextViewId++;
  }

  @override
  int createWindow({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    int? parentId,
  }) {
    final id = _nextCreateId();
    _rec('createWindow:$id:parent=${parentId ?? -1}');
    return id;
  }

  @override
  int createDialog({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    required int parentId,
    required bool isModal,
  }) {
    final id = _nextCreateId();
    _rec('createDialog:$id:parent=$parentId:modal=$isModal');
    return id;
  }

  @override
  int createPopupWindow({required int token, required int parentId, required Size windowSize}) {
    final id = _nextCreateId();
    _rec('createPopup:$id:parent=$parentId');
    return id;
  }

  @override
  void softCloseWindow(int viewId) => _rec('softCloseWindow:$viewId');

  @override
  void forceCloseView(int viewId) {
    _rec('forceCloseView:$viewId');
    setPreventClose(viewId, isPreventClose: false);
    softCloseWindow(viewId);
  }

  @override
  void destroyModalDialog(int viewId) => _rec('destroyModalDialog:$viewId');

  @override
  void setPreConfirmClose(int viewId, bool isPreConfirm) => _rec('setPreConfirmClose:$viewId:$isPreConfirm');

  @override
  void setConfirmClose(int viewId, {required bool isConfirm}) => _rec('setConfirmClose:$viewId:$isConfirm');

  @override
  void setPreventClose(int viewId, {required bool isPreventClose}) =>
      _rec('setPreventClose:$viewId:$isPreventClose');

  @override
  void completeModalDialogCreate(int viewId) => _rec('completeModalDialogCreate:$viewId');

  @override
  void show(int viewId) => _rec('show:$viewId');

  @override
  void hide(int viewId) => _rec('hide:$viewId');

  @override
  void focus(int viewId) => _rec('focus:$viewId');

  @override
  void maximize(int viewId, {bool vertically = false}) =>
      _rec('maximize:$viewId:vertically=$vertically');

  @override
  void setOpacity(int viewId, double opacity) {
    opacities[viewId] = opacity;
    _rec('setOpacity:$viewId:$opacity');
  }

  @override
  void setFrame(int viewId, Rect rect) {
    frames[viewId] = rect;
    _rec('setFrame:$viewId:${rect.left},${rect.top},${rect.width},${rect.height}');
  }

  @override
  double getOpacity(int viewId) => opacities[viewId] ?? 1.0;

  @override
  Rect? getFrame(int viewId) => frames[viewId];

  @override
  Rect getBounds(int viewId) => frames[viewId] ?? Rect.zero;

  @override
  void setSize(int viewId, {required Size size}) => _rec('setSize:$viewId:${size.width}x${size.height}');

  @override
  void setMinSize(int viewId, {required Size size}) => _rec('setMinSize:$viewId:${size.width}x${size.height}');

  @override
  void setMaxSize(int viewId, {required Size size}) => _rec('setMaxSize:$viewId:${size.width}x${size.height}');

  @override
  void setPosition(int viewId, {required Offset pos}) => _rec('setPosition:$viewId:${pos.dx},${pos.dy}');

  @override
  void setTitle(int viewId, {required String title}) => _rec('setTitle:$viewId:$title');

  @override
  void setBackgroundColor(int viewId, {required Color color}) => _rec('setBackgroundColor:$viewId');

  @override
  void setAlwaysOnTop(int viewId, {required bool isAlwaysOnTop}) =>
      _rec('setAlwaysOnTop:$viewId:$isAlwaysOnTop');

  @override
  void setFullScreen(int viewId, {required bool isFullScreen}) => _rec('setFullScreen:$viewId:$isFullScreen');

  @override
  void setResizable(int viewId, bool isResizable) => _rec('setResizable:$viewId:$isResizable');

  @override
  void setTitleBarStyle(
    int viewId, {
    required TitleBarStyle style,
    required bool closeVisibility,
    required bool maximizeVisibility,
    required bool minimizeVisibility,
  }) => _rec('setTitleBarStyle:$viewId:${style.name}');

  @override
  void setAlignment(int viewId, {required Alignment alignment}) =>
      _rec('setAlignment:$viewId:${alignment.x},${alignment.y}');
}
