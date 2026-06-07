import 'package:flutter/widgets.dart';

import '../multi_view_desktop.dart';
import '../resize_edge.dart';

/// A widget that triggers a native window resize when the user presses and
/// drags on its area.
///
/// Place instances at each edge / corner of the window content area when
/// using a frameless window:
///
/// ```dart
/// DragToResizeArea(
///   resizeEdge: ResizeEdge.bottomRight,
///   child: const SizedBox(width: 8, height: 8),
/// )
/// ```
class DragToResizeArea extends StatelessWidget {
  const DragToResizeArea({
    super.key,
    required this.resizeEdge,
    required this.child,
    this.enableResizeEdge,
  });

  final ResizeEdge resizeEdge;
  final Widget child;

  /// When non-null, [child] is only interactive for resizing when this value
  /// is `true`.
  final bool? enableResizeEdge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        if (enableResizeEdge == false) return;
        MultiViewDesktop.of(context).startResizing(resizeEdge);
      },
      child: child,
    );
  }
}
