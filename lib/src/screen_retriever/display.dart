import 'dart:math' as math;
import 'dart:ui';

/// Description of a user display screen.
class Display {
  const Display({
    required this.id,
    this.name,
    required this.size,
    this.visiblePosition,
    this.visibleSize,
    this.scaleFactor,
    this.dpi,
    this.physicalBounds,
    this.physicalWorkArea,
    this.physicalWidthMm,
    this.physicalHeightMm,
  });

  factory Display.fromJson(Map<String, dynamic> json) {
    final sizeMap = json['size'] as Map;
    final visiblePositionMap = json['visiblePosition'] as Map?;
    final visibleSizeMap = json['visibleSize'] as Map?;

    return Display(
      id: json['id'] as String,
      name: json['name'] as String?,
      size: Size((sizeMap['width'] as num).toDouble(), (sizeMap['height'] as num).toDouble()),
      visiblePosition: visiblePositionMap != null
          ? Offset((visiblePositionMap['dx'] as num).toDouble(), (visiblePositionMap['dy'] as num).toDouble())
          : null,
      visibleSize: visibleSizeMap != null
          ? Size((visibleSizeMap['width'] as num).toDouble(), (visibleSizeMap['height'] as num).toDouble())
          : null,
      scaleFactor: json['scaleFactor'] as num?,
      dpi: json['dpi'] as num?,
      physicalBounds: _rectFromJson(json['physicalBounds']),
      physicalWorkArea: _rectFromJson(json['physicalWorkArea']),
      physicalWidthMm: (json['physicalWidthMm'] as num?)?.toDouble(),
      physicalHeightMm: (json['physicalHeightMm'] as num?)?.toDouble(),
    );
  }

  static Rect? _rectFromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = raw['x'] as num?;
    final y = raw['y'] as num?;
    final w = raw['width'] as num?;
    final h = raw['height'] as num?;
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
  }

  /// Unique identifier associated with the display.
  final String id;

  /// The name of the display.
  final String? name;

  /// The size of the display in logical pixels.
  final Size size;

  /// The visible area position of the display in logical pixels.
  /// Uses Flutter coordinate space (Y-down, origin at top-left of primary screen).
  final Offset? visiblePosition;

  /// The visible area size of the display in logical pixels.
  final Size? visibleSize;

  /// The scale factor of the display.
  final num? scaleFactor;

  /// Effective DPI of the display, when the platform reports it.
  ///
  /// On Windows this is the monitor DPI (96 at 100% scale). On macOS and Linux
  /// it is `96 * scaleFactor`. Two monitors can share the same DPI.
  final num? dpi;

  /// Full display rectangle in device pixels (Y-down).
  ///
  /// On Windows this is the virtual-desktop rect and can be used to cover the
  /// monitor with [MultiViewDesktop.setPhysicalBounds]. On macOS it is the
  /// screen frame converted through that screen's backing scale.
  final Rect? physicalBounds;

  /// Work area (excludes taskbar / dock / menu bar) in device pixels.
  final Rect? physicalWorkArea;

  /// Physical panel width in millimetres, when the OS reports it.
  final double? physicalWidthMm;

  /// Physical panel height in millimetres, when the OS reports it.
  final double? physicalHeightMm;

  /// Panel diagonal in millimetres, when width and height are known.
  double? get diagonalMm {
    final w = physicalWidthMm;
    final h = physicalHeightMm;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return math.sqrt(w * w + h * h);
  }

  /// Visible work area in logical pixels.
  Rect get visibleRect {
    return Rect.fromLTWH(
      visiblePosition?.dx ?? 0,
      visiblePosition?.dy ?? 0,
      visibleSize?.width ?? size.width,
      visibleSize?.height ?? size.height,
    );
  }

  /// Full display rectangle in logical pixels.
  Rect get logicalBounds {
    return Rect.fromLTWH(
      visiblePosition?.dx ?? 0,
      visiblePosition?.dy ?? 0,
      size.width,
      size.height,
    );
  }
}
