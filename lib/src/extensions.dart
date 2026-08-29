import 'package:flutter/cupertino.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'run_multi_app.dart' as run_app;

extension MvdContext on BuildContext {
  /// Opens a dialog with this context as the parent window.
  ///
  /// Same as `openDialog` from `run_multi_app.dart`. See that function for
  /// dialog behavior and `DialogOptions`.
  ///
  /// ```dart
  /// OutlinedButton(
  ///   onPressed: () => context.openDialog(
  ///     (context, id) => const SettingsDialog(),
  ///     options: DialogOptions(title: 'Settings', modal: true),
  ///   ),
  ///   child: const Text('Open dialog'),
  /// )
  /// ```
  Future<T?> openDialog<T>(
    Widget Function(BuildContext context, int publicId) childBuilder, {
    DialogOptions? options,
    AnimationSettings? animation,
  }) =>
      run_app.openDialog<T>(
        childBuilder,
        parentContext: this,
        options: options,
        animation: animation,
      );

  /// Opens a dialog with this context as the parent window.
  ///
  /// Same as `openDialogEntry` from `run_multi_app.dart`. See that function for
  /// dialog behavior and `DialogOptions`.
  ///
  /// ```dart
  /// OutlinedButton(
  ///   onPressed: () => context.openDialogEntry(
  ///     (context, id) => const SettingsDialog(),
  ///     options: DialogOptions(title: 'Settings', modal: true),
  ///   ),
  ///   child: const Text('Open dialog'),
  /// )
  /// ```
  Future<DialogEntry<T?>> openDialogEntry<T>(
    Widget Function(BuildContext context, int publicId) childBuilder, {
    DialogOptions? options,
    AnimationSettings? animation,
  }) =>
      run_app.openDialogEntry<T>(
        childBuilder,
        parentContext: this,
        options: options,
        animation: animation,
      );

  /// Closes the dialog for this context.
  ///
  /// `res` completes the `await openDialog<T>()` future on the caller side.
  ///
  /// ```dart
  /// ElevatedButton(
  ///   onPressed: () => context.closeDialog('ok'),
  ///   child: const Text('Save'),
  /// )
  /// ```
  Future<bool> closeDialog<T>([T? res, AnimationSettings? animation]) =>
      MultiViewDesktop.of(this).closeDialog(res, animation);

  /// `MultiViewDesktop` instance for the window that owns this context.
  ///
  /// Same as `MultiViewDesktop.of`(this).
  MultiViewDesktop get viewController => MultiViewDesktop.of(this);
}
