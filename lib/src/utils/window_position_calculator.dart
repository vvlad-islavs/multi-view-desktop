import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screen_retriever/screen_retriever.dart';

/// macOS title-bar inset. Without it parent-relative dialogs sit too low.
const int _macTopRectInset = 38;

/// Computes window/dialog offsets from display geometry or a parent frame.
///
/// Inject into lifecycle / proxies so unit tests can substitute a fake without
/// calling [ScreenRetriever].
@internal
class WindowPositionCalculator {
  WindowPositionCalculator({Display Function()? resolveDisplay})
    : _resolveDisplay = resolveDisplay ?? _displayUnderCursorOrPrimary;

  /// Shared production instance for low-level callers ([FfiBridge], [NativeChannel]).
  static final WindowPositionCalculator instance = WindowPositionCalculator();

  final Display Function() _resolveDisplay;

  /// Position [windowSize] on the display under the cursor (fallback: primary).
  Offset calcWindowPosition(Size windowSize, Alignment alignment) {
    final currentDisplay = _resolveDisplay();
    final num visibleWidth = currentDisplay.visibleSize?.width ?? currentDisplay.size.width;
    final num visibleHeight = currentDisplay.visibleSize?.height ?? currentDisplay.size.height;
    final num visibleStartX = currentDisplay.visiblePosition?.dx ?? 0;
    final num visibleStartY = currentDisplay.visiblePosition?.dy ?? 0;

    return calcPosition(
      alignment: alignment,
      windowSize: windowSize,
      visibleWidth: visibleWidth,
      visibleHeight: visibleHeight,
      visibleStartX: visibleStartX,
      visibleStartY: visibleStartY,
    );
  }

  /// Position [windowSize] relative to [parentBounds] (modeless dialogs).
  Offset calcWindowPositionByParent(
    Alignment alignment, {
    required Size windowSize,
    required Rect parentBounds,
  }) {
    const defaultMaxSidebarLinuxSize = 150;
    const defaultMaxTopbarLinuxSize = 100;
    final currentDisplay = _resolveDisplay();
    Offset currDisplayLinuxCorrectPos = Offset.zero;
    if (Platform.isLinux) {
      final dy = currentDisplay.visiblePosition?.dy ?? 0;
      final dx = currentDisplay.visiblePosition?.dx ?? 0;
      if (dy > 1 && dy < defaultMaxTopbarLinuxSize || dx > 1 && dx < defaultMaxSidebarLinuxSize) {
        currDisplayLinuxCorrectPos = Offset(dx, dy);
      }
    }

    final num visibleWidth = parentBounds.size.width;
    final num visibleHeight = parentBounds.size.height;
    final num visibleStartX =
        (currentDisplay.visiblePosition?.dx ?? 0) + parentBounds.left - currDisplayLinuxCorrectPos.dx;
    final num visibleStartY =
        (currentDisplay.visiblePosition?.dy ?? 0) +
        parentBounds.top -
        _platformTopRectAddSize -
        currDisplayLinuxCorrectPos.dy;

    return calcPosition(
      alignment: alignment,
      windowSize: windowSize,
      visibleWidth: visibleWidth,
      visibleHeight: visibleHeight,
      visibleStartX: visibleStartX,
      visibleStartY: visibleStartY,
    );
  }

  /// Pure alignment math over an already-resolved visible rect.
  @visibleForTesting
  Offset calcPosition({
    required Alignment alignment,
    required Size windowSize,
    required num visibleWidth,
    required num visibleHeight,
    required num visibleStartX,
    required num visibleStartY,
  }) {
    Offset forDefault() {
      final left = (visibleWidth - windowSize.width) / 2 + alignment.x * ((visibleWidth - windowSize.width) / 2);
      final top = (visibleHeight - windowSize.height) / 2 + alignment.y * ((visibleHeight - windowSize.height) / 2);
      return Offset(visibleStartX + left, visibleStartY + top);
    }

    return switch (alignment) {
      Alignment.topLeft => Offset(visibleStartX.toDouble(), visibleStartY.toDouble()),
      Alignment.topCenter => Offset(
        visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
        visibleStartY.toDouble(),
      ),
      Alignment.topRight => Offset(visibleStartX + visibleWidth - windowSize.width, visibleStartY.toDouble()),
      Alignment.centerLeft => Offset(
        visibleStartX.toDouble(),
        visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
      ),
      Alignment.center => Offset(
        visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
        visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
      ),
      Alignment.centerRight => Offset(
        visibleStartX + visibleWidth - windowSize.width,
        visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
      ),
      Alignment.bottomLeft => Offset(visibleStartX.toDouble(), visibleStartY + visibleHeight - windowSize.height),
      Alignment.bottomCenter => Offset(
        visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
        visibleStartY + visibleHeight - windowSize.height,
      ),
      Alignment.bottomRight => Offset(
        visibleStartX + visibleWidth - windowSize.width,
        visibleStartY + visibleHeight - windowSize.height,
      ),
      _ => forDefault(),
    };
  }
}

int get _platformTopRectAddSize {
  if (Platform.isMacOS) {
    return _macTopRectInset;
  }
  return 0;
}

Display _displayUnderCursorOrPrimary() {
  final screenRetriever = ScreenRetriever.instance;
  final Display primaryDisplay = screenRetriever.getPrimaryDisplay();
  final List<Display> allDisplays = screenRetriever.getAllDisplays();
  final Offset cursorScreenPoint = screenRetriever.getCursorScreenPoint();

  return allDisplays.firstWhere(
    (display) => Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
      display.size.width,
      display.size.height,
    ).contains(cursorScreenPoint),
    orElse: () => primaryDisplay,
  );
}
