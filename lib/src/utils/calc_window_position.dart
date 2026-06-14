import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screen_retriever/screen_retriever.dart';

/// Calculates the window position (top-left, in Flutter logical coordinates)
/// required to place a window of [windowSize] at the given [alignment] on
/// the display that currently contains the mouse cursor.
///
/// Falls back to the primary display when the cursor cannot be located on
/// any known display.
@internal
Future<Offset> calcWindowPosition(Size windowSize, Alignment alignment) async {
  final screenRetriever = ScreenRetriever.instance;
  final Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final List<Display> allDisplays = await screenRetriever.getAllDisplays();
  final Offset cursorScreenPoint = await screenRetriever.getCursorScreenPoint();

  final Display currentDisplay = allDisplays.firstWhere(
    (display) => Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
      display.size.width,
      display.size.height,
    ).contains(cursorScreenPoint),
    orElse: () => primaryDisplay,
  );

  final num visibleWidth = currentDisplay.visibleSize?.width ?? currentDisplay.size.width;
  final num visibleHeight = currentDisplay.visibleSize?.height ?? currentDisplay.size.height;
  final num visibleStartX = currentDisplay.visiblePosition?.dx ?? 0;
  final num visibleStartY = currentDisplay.visiblePosition?.dy ?? 0;

  final Offset position;

  Offset forDefault() {
    final left = (visibleWidth - windowSize.width) / 2 + alignment.x * ((visibleWidth - windowSize.width) / 2);
    final top = (visibleHeight - windowSize.height) / 2 + alignment.y * ((visibleHeight - windowSize.height) / 2);
    return Offset(visibleStartX + left, visibleStartY + top);
  }

  position = switch (alignment) {
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

  return position;
}

int get _platformTopRectAddSize {
  if (Platform.isMacOS) {
    return 38;
  }
  return 0;
}

@internal
Future<Offset> calcWindowPositionByParent(
  Alignment alignment, {
  required Size windowSize,
  required Rect parentBounds,
}) async {
  final screenRetriever = ScreenRetriever.instance;
  final Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final List<Display> allDisplays = await screenRetriever.getAllDisplays();
  final Offset cursorScreenPoint = await screenRetriever.getCursorScreenPoint();

  final Display currentDisplay = allDisplays.firstWhere(
    (display) => Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
      display.size.width,
      display.size.height,
    ).contains(cursorScreenPoint),
    orElse: () => primaryDisplay,
  );

  final num visibleWidth = parentBounds.size.width;
  final num visibleHeight = parentBounds.size.height;
  final num visibleStartX = (currentDisplay.visiblePosition?.dx ?? 0) + parentBounds.left;
  final num visibleStartY = (currentDisplay.visiblePosition?.dy ?? 0) + parentBounds.top - _platformTopRectAddSize;

  final Offset position;

  Offset forDefault() {
    final left = (visibleWidth - windowSize.width) / 2 + alignment.x * ((visibleWidth - windowSize.width) / 2);
    final top = (visibleHeight - windowSize.height) / 2 + alignment.y * ((visibleHeight - windowSize.height) / 2);
    return Offset(visibleStartX + left, visibleStartY + top);
  }

  position = switch (alignment) {
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

  return position;
}
