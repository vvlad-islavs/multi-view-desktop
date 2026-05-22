import 'package:flutter/widgets.dart';

/// Provides the numeric OS-view identifier for the current window.
///
/// Automatically injected by [runMultiApp] around every view in the
/// [ViewCollection].  Read it with [MultiViewDesktop.getCurrentId] or
/// directly:
///
/// ```dart
/// final id = ViewScope.of(context).viewId;
/// ```
class ViewScope extends InheritedWidget {
  const ViewScope({
    super.key,
    required this.viewId,
    required super.child,
  });

  final int viewId;

  static ViewScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ViewScope>();
  }

  static ViewScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'No ViewScope found in context. '
      'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(ViewScope oldWidget) => viewId != oldWidget.viewId;
}
