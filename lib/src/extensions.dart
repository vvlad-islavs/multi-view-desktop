import 'package:flutter/cupertino.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'run_multi_app.dart' as run_app;

extension MvdContext on BuildContext {
  /// Opens a dialog window always associated with [parentContext].
  ///
  /// Unlike [openWindow], dialogs:
  /// - **Always require** a parent ([parentContext] is mandatory).
  /// - Are automatically closed when the parent closes, regardless of
  ///   [CloseMode] (even `CloseMode.none`).
  /// - Cannot enter full-screen mode.
  /// - Are hidden from the taskbar / Mission Control.
  /// - Are centered over the parent window at creation time.
  ///
  /// Set [options.modal] to `true` to dim the parent window while the dialog is
  /// open.  The parent must wrap its content with [DialogModalLayer]:
  ///
  /// ```dart
  /// runMultiApp(
  ///   home: (context, id) => DialogModalLayer(child: MyHomeScreen()),
  /// );
  /// ```
  ///
  /// Usage:
  /// ```dart
  /// OutlinedButton(
  ///   onPressed: () => openDialog(
  ///     (context, id) => const SettingsDialog(),
  ///     parentContext: context,
  ///     options: DialogOptions(title: 'Settings', modal: true),
  ///   ),
  ///   child: const Text('Open dialog'),
  /// )
  /// ```
  Future<T?> openDialog<T>(
    Widget Function(BuildContext context, int publicId) childBuilder, {
    DialogOptions? options,
  }) => run_app.openDialog<T>(childBuilder, parentContext: this, options: options);

  /// Closes dialog by context.
  /// Params:
  /// - [res]: optional res that return `await openDialog`
  Future<void> closeDialog<T>([T? res]) => MultiViewDesktop.of(this).closeDialog(res);

  /// View controller of this context
  MultiViewDesktop get viewController => MultiViewDesktop.of(this);
}
