import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

// ─── Native C ABI (macOS / Windows / Linux) ───────────────────────────────────
//
// Native files: MvdFfiBridge.swift, mvd_ffi_bridge.cpp, mvd_ffi_bridge.cc
// Symbol convention: mvd_<verb>_<noun>
// Shared buffer: mvd_rect_buf_ptr → Double[4] = {x, y, w, h}

typedef _GetRectBufPtrNative = Pointer<Double> Function();
typedef _GetRectBufPtrDart = Pointer<Double> Function();

typedef _GetFrameNative = Void Function(Int64 viewId);
typedef _GetFrameDart = void Function(int viewId);

typedef _SetFrameNative = Void Function(Int64, Double, Double, Double, Double);
typedef _SetFrameDart = void Function(int, double, double, double, double);

typedef _GetDisplayRectNative = Void Function(Double, Double, Double, Double);
typedef _GetDisplayRectDart = void Function(double, double, double, double);

typedef _SetIgnoreMouseEventsNative = Void Function(Int64, Int32);
typedef _SetIgnoreMouseEventsDart = void Function(int, int);

const _kRectBufSymbol = 'mvd_rect_buf_ptr';

// ─── Public API ───────────────────────────────────────────────────────────────

/// Synchronous FFI surface to native window APIs.
///
/// Native exports (`mvd_*`) share one C ABI on macOS, Windows, and Linux.
/// Platform subclasses only differ in how the process library is opened.
///
/// Calls run on the Dart UI isolate, which is the platform UI thread
/// (AppKit / Win32 / GTK), so window APIs need no dispatch hop.
///
/// "Get" functions share a native `Double[4]` buffer. Dart wraps it with
/// [Pointer.asTypedList] — no `package:ffi` / `calloc`.
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
      // Missing plugin binary or symbols — methods become no-ops.
    }
    return _UnsupportedFfiBridge();
  }

  final DynamicLibrary? _lib;

  bool get _supported => _lib != null;

  late final _GetRectBufPtrDart _getRectBufPtr =
      _lib!.lookupFunction<_GetRectBufPtrNative, _GetRectBufPtrDart>(_kRectBufSymbol);

  late final _GetFrameDart _getFrame =
      _lib!.lookupFunction<_GetFrameNative, _GetFrameDart>('mvd_get_frame');

  late final _SetFrameDart _setFrame = _lib!.lookupFunction<_SetFrameNative, _SetFrameDart>('mvd_set_frame');

  late final _GetDisplayRectDart _getDisplayRect =
      _lib!.lookupFunction<_GetDisplayRectNative, _GetDisplayRectDart>('mvd_get_display_rect');

  late final _SetIgnoreMouseEventsDart _setIgnoreMouseEvents =
      _lib!.lookupFunction<_SetIgnoreMouseEventsNative, _SetIgnoreMouseEventsDart>('mvd_set_ignore_mouse_events');

  // Layout: [0]=x  [1]=y  [2]=w  [3]=h
  late final Float64List _buf = _getRectBufPtr().asTypedList(4);

  /// Frame of the OS window [viewId] in Flutter logical coords.
  /// Returns `null` when FFI is unavailable or the view is not found.
  Rect? getFrame(int viewId) {
    if (!_supported) return null;
    _getFrame(viewId);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  /// Moves/resizes window [viewId] synchronously.
  ///
  /// Position-only moves (size unchanged within 0.5 pt) skip the engine resize
  /// path on the native side.
  void setFrame(int viewId, Rect rect) {
    if (!_supported) return;
    _setFrame(viewId, rect.left, rect.top, rect.width, rect.height);
  }

  /// Visible display rect best containing [query] in Flutter logical coords.
  Rect? getDisplayRect(Rect query) {
    if (!_supported) return null;
    _getDisplayRect(query.left, query.top, query.width, query.height);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  /// Click-through for window [viewId]. Sync FFI — no channel delay.
  void setIgnoreMouseEvents(int viewId, bool ignore) {
    if (!_supported) return;
    _setIgnoreMouseEvents(viewId, ignore ? 1 : 0);
  }
}

/// macOS: plugin symbols are in the process image (`@_cdecl` in Swift).
@internal
class FfiMacosBridge extends FfiBridge {
  FfiMacosBridge() : super._native(DynamicLibrary.process());
}

/// Windows: plugin lives in a separate DLL, not the runner EXE.
@internal
class FfiWinBridge extends FfiBridge {
  FfiWinBridge() : super._native(DynamicLibrary.open('multiview_desktop_plugin.dll'));
}

/// Linux: plugin is a `DT_NEEDED` of the runner; fall back to opening the .so.
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
