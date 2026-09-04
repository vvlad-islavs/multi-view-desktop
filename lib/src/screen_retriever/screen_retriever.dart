import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'display.dart';
import 'screen_ffi.dart';
import 'screen_listener.dart';

export 'display.dart';
export 'screen_listener.dart';

/// Queries connected displays and cursor position via native desktop APIs.
///
/// Coordinates are in Flutter logical space (Y-down, origin at primary top-left).
@internal
class ScreenRetriever {
  ScreenRetriever._();

  static final ScreenRetriever instance = ScreenRetriever._();

  final ObserverList<ScreenListener> _listeners = ObserverList<ScreenListener>();

  bool get hasListeners => _listeners.isNotEmpty;

  void _handleScreenEvent(String type) {
    for (final listener in _listeners) {
      listener.onScreenEvent(type);
    }
  }

  /// Subscribes to display hot-plug events (`display-added`, `display-removed`).
  void addListener(ScreenListener listener) {
    if (!hasListeners) {
      ScreenFfi.instance.addEventListener(_handleScreenEvent);
    }
    _listeners.add(listener);
  }

  void removeListener(ScreenListener listener) {
    _listeners.remove(listener);
    if (!hasListeners) {
      ScreenFfi.instance.removeEventListener(_handleScreenEvent);
    }
  }

  double get _devicePixelRatio {
    final mediaQueryData = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first);
    return mediaQueryData.devicePixelRatio;
  }

  /// Returns the current cursor position in Flutter logical coordinates
  /// (Y-down, origin at top-left of the primary screen).
  Offset getCursorScreenPoint() {
    final result = ScreenFfi.instance.getCursorScreenPoint(devicePixelRatio: _devicePixelRatio);
    if (result == null) throw Exception('Unable to get cursor screen point.');
    return result;
  }

  /// Cursor in device pixels. On Windows pass through virtual-desktop coords.
  /// On Linux native coords are already physical. On macOS same as logical points.
  Offset getCursorPhysicalPoint() {
    final ratio = Platform.isMacOS ? _devicePixelRatio : 1.0;
    final result = ScreenFfi.instance.getCursorScreenPoint(devicePixelRatio: ratio);
    if (result == null) throw Exception('Unable to get cursor screen point.');
    return result;
  }

  /// Returns the primary display (first entry in the system screen list).
  Display getPrimaryDisplay() {
    final json = ScreenFfi.instance.primaryDisplayJson();
    if (json == null) throw Exception('Unable to get primary display.');
    return Display.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
  }

  /// Returns every connected display.
  List<Display> getAllDisplays() {
    final json = ScreenFfi.instance.allDisplaysJson();
    if (json == null) throw Exception('Unable to get all displays.');
    final decoded = jsonDecode(json);
    final raw = decoded is List ? decoded : (decoded as Map)['displays'] as List?;
    if (raw == null) throw Exception('Unable to get all displays.');
    final displays = raw
        .map((item) => Display.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    if (displays.isEmpty) throw Exception('Unable to get all displays.');
    return displays;
  }
}
