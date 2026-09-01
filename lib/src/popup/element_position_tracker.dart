import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tracks the global rect of an [Element] inside a Flutter view.
///
/// Independent of Flutter's experimental windowing flag. Used by [PopupView]
/// to keep a popup aligned with its trigger widget.
@internal
class LocalElementPositionTracker {
  LocalElementPositionTracker({required this.element}) {
    _ElementPositionTrackerManager.instance.add(this);
  }

  void dispose() {
    _ElementPositionTrackerManager.instance.remove(this);
  }

  /// Returns current global rect for the tracked element, or `null` if not available.
  Rect? getGlobalRect() {
    final Rect? rect = _getGlobalRect();
    _lastReportedRect = rect;
    return rect;
  }

  /// Invoked when the global position of the tracked element changes.
  void Function(Rect rect)? onGlobalRectChange;

  final BuildContext element;
  Rect? _lastReportedRect;

  Rect? _getGlobalRect() {
    if (!element.mounted) {
      return null;
    }
    final RenderObject? renderBox = element.findRenderObject();
    if (renderBox is! RenderBox) {
      return null;
    }

    final Matrix4 transform = renderBox.getTransformTo(null);
    final Rect rect = Offset.zero & renderBox.size;
    return MatrixUtils.transformRect(transform, rect);
  }

  void _updateSelf() {
    final Rect? rect = _getGlobalRect();
    if (rect == null) {
      _ElementPositionTrackerManager.instance.remove(this);
      return;
    }
    if (_lastReportedRect != rect) {
      _lastReportedRect = rect;
      onGlobalRectChange?.call(rect);
    }
  }
}

class _ElementPositionTrackerManager {
  _ElementPositionTrackerManager._() {
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      final trackersCopy = List<LocalElementPositionTracker>.from(_trackers, growable: false);
      for (final tracker in trackersCopy) {
        tracker._updateSelf();
      }
    });
  }

  static final _instance = _ElementPositionTrackerManager._();

  static _ElementPositionTrackerManager get instance => _instance;
  final List<LocalElementPositionTracker> _trackers = <LocalElementPositionTracker>[];

  void add(LocalElementPositionTracker tracker) {
    _trackers.add(tracker);
  }

  void remove(LocalElementPositionTracker tracker) {
    _trackers.remove(tracker);
  }
}
