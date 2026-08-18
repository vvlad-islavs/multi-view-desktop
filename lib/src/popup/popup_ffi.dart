import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data' show Float64List;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

// ─── Native function typedefs ─────────────────────────────────────────────────

// Returns the stable pointer to the shared Double[4] output buffer.
typedef _GetRectBufPtrNative = Pointer<Double> Function();
typedef _GetRectBufPtrDart = Pointer<Double> Function();

// Fills the shared buffer with the window frame of `viewId`.
typedef _GetParentFrameNative = Void Function(Int64 viewId);
typedef _GetParentFrameDart = void Function(int viewId);

// Sets the popup window frame (uses setFrameOrigin when size is unchanged).
typedef _SetFrameNative = Void Function(Int64, Double, Double, Double, Double);
typedef _SetFrameDart = void Function(int, double, double, double, double);

// Fills the shared buffer with the best display's visible frame.
typedef _GetDisplayRectNative = Void Function(Double, Double, Double, Double);
typedef _GetDisplayRectDart = void Function(double, double, double, double);

typedef _SetIgnoreMouseEventsNative = Void Function(Int64, Int32);
typedef _SetIgnoreMouseEventsDart = void Function(int, int);

// ─── Public API ───────────────────────────────────────────────────────────────

/// Synchronous FFI bridge to the macOS popup positioning functions defined in
/// `MvdPopupFfi.swift`.
///
/// All calls run on the Dart/UI thread, which IS the macOS main thread, so
/// `NSWindow` APIs are safe to invoke without any dispatch hop.
///
/// The two "get" functions share a single native `Double[4]` buffer allocated
/// once in Swift. Dart wraps it with [Pointer.asTypedList] to get a zero-copy
/// [Float64List] — no `package:ffi` / `calloc` required.
///
/// On non-macOS platforms every method is a no-op and returns `null`.
@internal
class PopupFfi {
  PopupFfi._();

  static final PopupFfi instance = PopupFfi._();

  static final bool _supported = Platform.isMacOS;

  late final DynamicLibrary _lib = DynamicLibrary.process();

  late final _GetRectBufPtrDart _getRectBufPtr =
      _lib.lookupFunction<_GetRectBufPtrNative, _GetRectBufPtrDart>(
          'mvd_popup_get_rect_buf_ptr');

  late final _GetParentFrameDart _getParentFrame =
      _lib.lookupFunction<_GetParentFrameNative, _GetParentFrameDart>(
          'mvd_popup_get_parent_frame');

  late final _SetFrameDart _setFrame =
      _lib.lookupFunction<_SetFrameNative, _SetFrameDart>(
          'mvd_popup_set_frame');

  late final _GetDisplayRectDart _getDisplayRect =
      _lib.lookupFunction<_GetDisplayRectNative, _GetDisplayRectDart>(
          'mvd_popup_get_display_rect');

  late final _SetIgnoreMouseEventsDart _setIgnoreMouseEvents =
      _lib.lookupFunction<_SetIgnoreMouseEventsNative, _SetIgnoreMouseEventsDart>(
          'mvd_popup_set_ignore_mouse_events');

  // Zero-copy Float64List view over the Swift-owned Double[4] buffer.
  // Layout: [0]=x  [1]=y  [2]=w  [3]=h
  late final Float64List _buf = _getRectBufPtr().asTypedList(4);

  // ─── Public methods ────────────────────────────────────────────────────────

  /// Returns the frame of the OS window [viewId] in Flutter logical coords.
  /// Returns `null` on non-macOS or when the view is not found.
  Rect? getParentFrame(int viewId) {
    if (!_supported) return null;
    _getParentFrame(viewId);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  /// Moves/resizes popup window [viewId] synchronously.
  ///
  /// Position-only moves (size unchanged within 0.5 pt) use `setFrameOrigin`
  /// on the native side, bypassing `ResizeSynchronizer` → no Impeller crash.
  void setFrame(int viewId, Rect rect) {
    if (!_supported) return;
    _setFrame(viewId, rect.left, rect.top, rect.width, rect.height);
  }

  /// Returns the visible display rect best containing [parentFrame] in Flutter
  /// logical coords. Returns `null` on non-macOS.
  Rect? getDisplayRect(Rect parentFrame) {
    if (!_supported) return null;
    _getDisplayRect(
        parentFrame.left, parentFrame.top, parentFrame.width, parentFrame.height);
    if (_buf[2] == 0 && _buf[3] == 0) return null;
    return Rect.fromLTWH(_buf[0], _buf[1], _buf[2], _buf[3]);
  }

  /// Click-through for popup [viewId]. Sync FFI — no channel delay.
  void setIgnoreMouseEvents(int viewId, bool ignore) {
    if (!_supported) return;
    _setIgnoreMouseEvents(viewId, ignore ? 1 : 0);
  }
}
