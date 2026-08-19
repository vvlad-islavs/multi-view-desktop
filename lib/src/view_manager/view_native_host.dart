import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';

typedef ViewNativeInvoke =
    T? Function<T>(int viewId, T Function() action, {bool dialogSupports});

/// Registry + FFI access surface for view native proxies.
@internal
class ViewNativeHost {
  ViewNativeHost({
    required this.ffi,
    required this.invoke,
    required this.isWindow,
    required this.isDialog,
    required this.isPopup,
    required this.isModalDialog,
    required this.dialogParentId,
    required this.allManagedViewIds,
    required this.lifecycleViewId,
    required this.windowViewIds,
  });

  final FfiBridge ffi;
  final ViewNativeInvoke invoke;

  final bool Function(int viewId) isWindow;
  final bool Function(int viewId) isDialog;
  final bool Function(int viewId) isPopup;
  final bool Function(int viewId) isModalDialog;
  final int? Function(int viewId) dialogParentId;

  final Iterable<int> Function() allManagedViewIds;
  final int? Function() lifecycleViewId;
  final Iterable<int> Function() windowViewIds;

  bool isManaged(int viewId) => isWindow(viewId) || isDialog(viewId) || isPopup(viewId);
}

/// Base type for FFI proxy groups.
@internal
abstract class ViewNativeProxy {
  const ViewNativeProxy(this.host);

  final ViewNativeHost host;

  FfiBridge get ffi => host.ffi;

  T? call<T>(int viewId, T Function() action, {bool dialogSupports = false}) =>
      host.invoke<T>(viewId, action, dialogSupports: dialogSupports);
}
