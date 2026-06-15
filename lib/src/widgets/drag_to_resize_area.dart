import 'package:flutter/widgets.dart';

import '../multi_view_desktop.dart';
import '../resize_edge.dart';

/// Starts a native window resize when the user drags this area.
///
/// Used on edges and corners of frameless windows:
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
