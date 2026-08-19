import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Tracks a pending native view until [LifecycleViewsController.firstFrameCbComplete].
@internal
class ViewCreateCompleter<T> {
  final Completer<T?> completer;
  final int token;
  final bool isDialog;
  final int? parentId;

  const ViewCreateCompleter({
    required this.completer,
    required this.token,
    required this.isDialog,
    required this.parentId,
  });

  factory ViewCreateCompleter.window(int token, {int? parentId}) {
    return ViewCreateCompleter(
      completer: Completer<T?>(),
      token: token,
      isDialog: false,
      parentId: parentId,
    );
  }

  factory ViewCreateCompleter.dialog(int token, {required int parentId}) {
    return ViewCreateCompleter(
      completer: Completer<T?>(),
      token: token,
      isDialog: true,
      parentId: parentId,
    );
  }

  void complete([T? value]) => completer.complete(value);

  bool get isCompleted => completer.isCompleted;

  Future<T?> get future => completer.future;
}
