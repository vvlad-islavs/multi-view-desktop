// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/lifecycle/view_registry.dart';

typedef ViewNativeInvoke =
    T? Function<T>(int viewId, T Function() action, {bool dialogSupports});

/// Registry + FFI access surface for view native proxies.
@internal
class ViewNativeHost {
  ViewNativeHost({
    required this.ffi,
    required this.invoke,
    required this.registry,
    required this.lifecycleViewId,
  });

  final FfiBridge ffi;
  final ViewNativeInvoke invoke;
  final ViewRegistry registry;
  final int? Function() lifecycleViewId;

  bool isWindow(int viewId) => registry.isWindow(viewId);

  bool isDialog(int viewId) => registry.isDialog(viewId);

  bool isPopup(int viewId) => registry.isPopup(viewId);

  bool isModalDialog(int viewId) => registry.isModalDialog(viewId);

  int? dialogParentId(int viewId) => registry.dialogParentId(viewId);

  Iterable<int> allManagedViewIds() => registry.allManagedViewIds;

  Iterable<int> windowViewIds() => registry.windowViewIds;

  bool isManaged(int viewId) => registry.isManaged(viewId);
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
