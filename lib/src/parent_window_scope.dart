import 'package:flutter/widgets.dart';


class ParentWindowScope extends InheritedWidget {
  const ParentWindowScope({
    super.key,
    required this.parentContext,
    required super.child,
  });

  final BuildContext? parentContext;

  /// Returns the [ViewScope] above [context], or `null` if the tree was not
  /// created with [runMultiApp].
  static ParentWindowScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ParentWindowScope>();
  }

  /// Returns the [ViewScope] above [context].
  ///
  /// Throws in debug mode if [runMultiApp] was not used as the entry point.
  static ParentWindowScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
    scope != null,
    'No ViewScope found in context. '
        'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(ParentWindowScope oldWidget) => parentContext != oldWidget.parentContext;
}
