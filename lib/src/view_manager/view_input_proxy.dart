// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewInputProxy extends ViewNativeProxy {
  const ViewInputProxy(super.host);

  void setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) {
    call(
      viewId,
      () => ffi.setIgnoreMouseEvents(viewId, ignore, forward: forward),
      dialogSupports: true,
    );
  }

  ({bool mouseMoveEvents, bool ignore}) isIgnoreMouseEvents(int viewId) {
    return call(viewId, () => ffi.isIgnoreMouseEvents(viewId), dialogSupports: true) ??
        (mouseMoveEvents: false, ignore: false);
  }
}
