import 'dart:convert' show utf8;
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

const _kStrCap = 8192;
const _kRectBufSymbol = 'mvd_screen_rect_buf_ptr';
const _kStrBufSymbol = 'mvd_screen_str_buf_ptr';

typedef _PtrFN = Pointer<Double> Function();
typedef _PtrFD = Pointer<Double> Function();
typedef _PtrU8N = Pointer<Uint8> Function();
typedef _PtrU8D = Pointer<Uint8> Function();
typedef _CursorN = Int32 Function(Double);
typedef _CursorD = int Function(double);
typedef _I0N = Int32 Function();
typedef _I0D = int Function();
typedef _ScreenEventN = Void Function(Pointer<Char>);
typedef _SetScreenEventN = Void Function(Pointer<NativeFunction<_ScreenEventN>>);
typedef _SetScreenEventD = void Function(Pointer<NativeFunction<_ScreenEventN>>);

/// Synchronous FFI for [ScreenRetriever]. Independent of [FfiBridge].
///
/// Native: ScreenRetrieverPlugin.swift, mvd_windows_screen.cpp, mvd_linux_screen.cc
@internal
class ScreenFfi {
  ScreenFfi._() : _lib = null;

  ScreenFfi._native(this._lib) {
    clearOldNativeCallbacks();
  }

  static final ScreenFfi instance = _create();

  static ScreenFfi _create() {
    try {
      if (Platform.isMacOS) return ScreenFfi._native(DynamicLibrary.process());
      if (Platform.isWindows) {
        return ScreenFfi._native(DynamicLibrary.open('multiview_desktop_plugin.dll'));
      }
      if (Platform.isLinux) return ScreenFfi._native(_openLinux());
    } on Object {
      // Missing plugin binary or symbols.
    }
    return ScreenFfi._();
  }

  static DynamicLibrary _openLinux() {
    final process = DynamicLibrary.process();
    try {
      process.lookup(_kRectBufSymbol);
      return process;
    } on ArgumentError {
      return DynamicLibrary.open('libmultiview_desktop_plugin.so');
    }
  }

  final DynamicLibrary? _lib;

  bool get _supported => _lib != null;

  late final _getRectBufPtr = _lib!.lookupFunction<_PtrFN, _PtrFD>(_kRectBufSymbol);
  late final _getStrBufPtr = _lib!.lookupFunction<_PtrU8N, _PtrU8D>(_kStrBufSymbol);
  late final Float64List _buf = _getRectBufPtr().asTypedList(4);
  late final Uint8List _str = _getStrBufPtr().asTypedList(_kStrCap);

  _CursorD? _cursorFn;
  _I0D? _primaryFn;
  _I0D? _allFn;
  _SetScreenEventD? _setEventFn;
  bool _missing = false;

  NativeCallable<_ScreenEventN>? _eventCallable;
  final List<void Function(String)> _listeners = [];

  Offset? getCursorScreenPoint({double devicePixelRatio = 1}) {
    final fn = _lookupCursor();
    if (fn == null || fn(devicePixelRatio) == 0) return null;
    return Offset(_buf[0], _buf[1]);
  }

  String? primaryDisplayJson() {
    final fn = _lookupPrimary();
    if (fn == null || fn() == 0) return null;
    final json = _readStr(_str);
    return json.isEmpty ? null : json;
  }

  String? allDisplaysJson() {
    final fn = _lookupAll();
    if (fn == null || fn() == 0) return null;
    final json = _readStr(_str);
    return json.isEmpty ? null : json;
  }

  /// Drops a previous isolate's screen-event NativeCallable after hot restart.
  void clearOldNativeCallbacks() {
    if (!_supported) return;
    final setFn = _lookupSetEvent();
    if (setFn == null) return;
    setFn(nullptr);
    _eventCallable?.close();
    _eventCallable = null;
  }

  void addEventListener(void Function(String type) listener) {
    _listeners.add(listener);
    _ensureEventCallable();
  }

  void removeEventListener(void Function(String type) listener) {
    _listeners.remove(listener);
  }

  void _ensureEventCallable() {
    if (!_supported || _eventCallable != null) return;
    final setFn = _lookupSetEvent();
    if (setFn == null) return;
    try {
      _eventCallable = NativeCallable<_ScreenEventN>.isolateLocal(_dispatch);
      setFn(_eventCallable!.nativeFunction);
    } on ArgumentError {
      _eventCallable?.close();
      _eventCallable = null;
    }
  }

  void _dispatch(Pointer<Char> namePtr) {
    final name = _readCString(namePtr);
    for (final listener in List<void Function(String)>.from(_listeners)) {
      listener(name);
    }
  }

  _CursorD? _lookupCursor() => _lookup(() {
        _cursorFn ??= _lib!.lookupFunction<_CursorN, _CursorD>('mvd_get_cursor_screen_point');
        return _cursorFn;
      });

  _I0D? _lookupPrimary() => _lookup(() {
        _primaryFn ??= _lib!.lookupFunction<_I0N, _I0D>('mvd_get_primary_display');
        return _primaryFn;
      });

  _I0D? _lookupAll() => _lookup(() {
        _allFn ??= _lib!.lookupFunction<_I0N, _I0D>('mvd_get_all_displays');
        return _allFn;
      });

  _SetScreenEventD? _lookupSetEvent() => _lookup(() {
        _setEventFn ??=
            _lib!.lookupFunction<_SetScreenEventN, _SetScreenEventD>('mvd_set_screen_event_callback');
        return _setEventFn;
      });

  T? _lookup<T>(T? Function() fn) {
    if (!_supported || _missing) return null;
    try {
      return fn();
    } on ArgumentError {
      _missing = true;
      return null;
    }
  }

  String _readStr(Uint8List buf) {
    var n = 0;
    while (n < buf.length && buf[n] != 0) {
      n++;
    }
    return utf8.decode(buf.sublist(0, n));
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
}
