import 'package:flutter/widgets.dart';

import '../multi_view_desktop.dart';

/// A widget that makes its child area draggable to move the current window.
///
/// Wrap a custom title bar (or any region) with this widget so the user can
/// drag the window by that area:
///
/// ```dart
/// DragToMoveArea(
///   child: SizedBox(
///     height: 32,
///     child: Text('My App'),
///   ),
/// )
/// ```
class DragToMoveArea extends StatelessWidget {
  const DragToMoveArea({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => MultiViewDesktop.startDragging(context),
      // Absorb double-tap to avoid accidental maximize on the drag area.
      onDoubleTap: () {},
      child: child,
    );
  }
}
