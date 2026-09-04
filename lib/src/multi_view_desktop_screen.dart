import 'dart:ui';

import 'screen_retriever/display_matcher.dart';
import 'screen_retriever/screen_retriever.dart';

export 'screen_retriever/display.dart';
export 'screen_retriever/screen_listener.dart';

/// Connected-display queries. Access via [MultiViewDesktop.screen].
///
/// Logical coordinates use Flutter space (Y-down, origin at the primary
/// top-left). Physical coordinates are device pixels in the virtual desktop
/// (reliable for mixed-DPI layouts on Windows).
class MultiViewDesktopScreen {
  MultiViewDesktopScreen._();

  /// Shared instance used by [MultiViewDesktop.screen].
  static final MultiViewDesktopScreen instance = MultiViewDesktopScreen._();

  /// Primary display (first entry in the system screen list).
  Display primary() => ScreenRetriever.instance.getPrimaryDisplay();

  /// Every connected display.
  List<Display> all() => ScreenRetriever.instance.getAllDisplays();

  /// Cursor position in Flutter logical coordinates.
  Offset cursorPoint() => ScreenRetriever.instance.getCursorScreenPoint();

  /// Cursor position in device pixels (Y-down).
  ///
  /// On Windows this is the virtual-desktop point. On Linux it matches the
  /// native coordinate space used for window frames. On macOS it is the same
  /// as [cursorPoint] (points).
  Offset cursorPhysicalPoint() => ScreenRetriever.instance.getCursorPhysicalPoint();

  /// Display that best matches the given hints.
  ///
  /// Mixes physical overlap, DPI, panel diagonal, and logical overlap.
  /// DPI alone is not unique: two 1080p panels at 100% look the same.
  Display resolve({
    Offset? physicalPoint,
    Rect? physicalBounds,
    Offset? logicalPoint,
    Rect? logicalBounds,
    num? dpi,
    double? diagonalMm,
  }) {
    final displays = all();
    return DisplayMatcher.pick(
      displays: displays,
      fallback: primary(),
      physicalPoint: physicalPoint,
      physicalRect: physicalBounds,
      logicalPoint: logicalPoint,
      logicalBounds: logicalBounds,
      dpi: dpi,
      diagonalMm: diagonalMm,
    );
  }

  /// Display under the cursor, falling back to [primary].
  Display underCursor() {
    final displays = all();
    return DisplayMatcher.pick(
      displays: displays,
      fallback: primary(),
      physicalPoint: cursorPhysicalPoint(),
      logicalPoint: cursorPoint(),
    );
  }

  /// Subscribes to display hot-plug events (`display-added`, `display-removed`).
  void addListener(ScreenListener listener) => ScreenRetriever.instance.addListener(listener);

  void removeListener(ScreenListener listener) => ScreenRetriever.instance.removeListener(listener);
}
