import 'package:material_ui/material_ui.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'e2e_harness.dart';

/// Default open/close fade in example is 150ms; pad for raster/GTK settle.
const int kE2eAnimOpenMs = 150;
const int kE2eAnimCloseMs = 150;
const int kE2eSettlePadMs = 120;
const int kE2eHostRegisterMs = 80;

Duration e2eOpenSettle({int? animationMs}) {
  final anim = animationMs ?? kE2eAnimOpenMs;
  return Duration(milliseconds: anim + kE2eSettlePadMs);
}

Duration e2eCloseSettle({int? animationMs}) {
  final anim = animationMs ?? kE2eAnimCloseMs;
  return Duration(milliseconds: anim + kE2eSettlePadMs);
}

AnimationSettings? parseAnimation(E2eRequest req) {
  final ms = req.optional<num>('animationMs')?.toInt();
  if (ms == null) return null;
  return AnimationSettings(duration: Duration(milliseconds: ms));
}

int? parseSettleMs(E2eRequest req, {required int fallbackAnimMs}) {
  final explicit = req.optional<num>('settleMs')?.toInt();
  if (explicit != null) return explicit;
  final anim = req.optional<num>('animationMs')?.toInt() ?? fallbackAnimMs;
  return anim + kE2eSettlePadMs;
}

Alignment? parseAlignment(String? name) {
  if (name == null) return null;
  switch (name) {
    case 'topLeft':
      return Alignment.topLeft;
    case 'topCenter':
      return Alignment.topCenter;
    case 'topRight':
      return Alignment.topRight;
    case 'centerLeft':
      return Alignment.centerLeft;
    case 'center':
      return Alignment.center;
    case 'centerRight':
      return Alignment.centerRight;
    case 'bottomLeft':
      return Alignment.bottomLeft;
    case 'bottomCenter':
      return Alignment.bottomCenter;
    case 'bottomRight':
      return Alignment.bottomRight;
    default:
      throw ArgumentError('Unknown alignment "$name"');
  }
}

TitleBarStyle? parseTitleBarStyle(String? name) {
  if (name == null) return null;
  switch (name) {
    case 'normal':
      return TitleBarStyle.normal;
    case 'hidden':
      return TitleBarStyle.hidden;
    default:
      throw ArgumentError('Unknown titleBarStyle "$name"');
  }
}

Size? parseSize(E2eRequest req, {String w = 'width', String h = 'height'}) {
  final width = req.optional<num>(w)?.toDouble();
  final height = req.optional<num>(h)?.toDouble();
  if (width == null && height == null) return null;
  if (width == null || height == null) {
    throw ArgumentError('Both $w and $h are required together');
  }
  return Size(width, height);
}

Color? parseColorArgb(E2eRequest req, String key) {
  final raw = req.optional<num>(key)?.toInt();
  if (raw == null) return null;
  return Color(raw);
}

WindowOptions parseWindowOptions(E2eRequest req) {
  return WindowOptions(
    title: req.optional<String>('title') ?? 'E2E window',
    size: parseSize(req) ?? const Size(900, 700),
    minimumSize: parseSize(req, w: 'minWidth', h: 'minHeight') ?? const Size(400, 300),
    maximumSize: parseSize(req, w: 'maxWidth', h: 'maxHeight'),
    alignment: parseAlignment(req.optional<String>('alignment')) ?? Alignment.center,
    titleBarStyle: parseTitleBarStyle(req.optional<String>('titleBarStyle')),
    windowButtonVisibility: req.optional<bool>('windowButtonVisibility'),
    alwaysOnTop: req.optional<bool>('alwaysOnTop'),
    fullScreen: req.optional<bool>('fullScreen'),
    backgroundColor: parseColorArgb(req, 'backgroundColor'),
  );
}

DialogOptions parseDialogOptions(E2eRequest req) {
  return DialogOptions(
    title: req.optional<String>('title') ?? 'E2E OS dialog',
    size: parseSize(req) ?? const Size(420, 240),
    minimumSize: parseSize(req, w: 'minWidth', h: 'minHeight'),
    maximumSize: parseSize(req, w: 'maxWidth', h: 'maxHeight'),
    modal: req.optional<bool>('modal') ?? true,
    isResizable: req.optional<bool>('isResizable'),
    titleBarStyle: parseTitleBarStyle(req.optional<String>('titleBarStyle')),
    windowButtonVisibility: req.optional<bool>('windowButtonVisibility'),
    alwaysOnTop: req.optional<bool>('alwaysOnTop'),
    showOnInit: req.optional<bool>('showOnInit'),
    backgroundColor: parseColorArgb(req, 'backgroundColor'),
  );
}

Map<String, Object?> windowStateMap(int viewId) {
  final win = MultiViewDesktop.fromId(viewId);
  final info = win.getWindowInfo();
  final bounds = win.getBounds();
  final min = win.getMinimumSize();
  final max = win.getMaximumSize();
  return {
    'viewId': viewId,
    'title': win.getTitle(),
    'isDialog': info.isDialog,
    'isModal': info.isModal,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    },
    'minSize': {'width': min.width, 'height': min.height},
    'maxSize': {'width': max.width, 'height': max.height},
    'resizable': win.isResizable(),
    'movable': win.isMovable(),
    'minimizable': win.isMinimizable(),
    'maximizable': win.isMaximizable(),
    'closable': win.isClosable(),
    'preventClose': win.isPreventClose(),
    'alwaysOnTop': win.isAlwaysOnTop(),
    'fullScreen': win.isFullScreen(),
    'maximized': win.isMaximized(),
    'minimized': win.isMinimized(),
    'visible': win.isVisible(),
  };
}
