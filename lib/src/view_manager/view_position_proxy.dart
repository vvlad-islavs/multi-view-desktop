import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/utils/calc_window_position.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewPositionProxy extends ViewNativeProxy {
  const ViewPositionProxy(super.host);

  Rect getBounds(int viewId) => call(viewId, () => ffi.getBounds(viewId), dialogSupports: true) ?? Rect.zero;

  Size getSize(int viewId) => call(viewId, () => ffi.getSize(viewId), dialogSupports: true) ?? Size.zero;

  Offset getPosition(int viewId) =>
      call(viewId, () => ffi.getPosition(viewId), dialogSupports: true) ?? Offset.zero;

  void setSize(int viewId, Size size) {
    call(viewId, () => ffi.setSize(viewId, size: size), dialogSupports: true);
  }

  void setPosition(int viewId, Offset position) {
    call(viewId, () => ffi.setPosition(viewId, pos: position), dialogSupports: true);
  }

  void setMinimumSize(int viewId, Size size) {
    call(viewId, () => ffi.setMinSize(viewId, size: size), dialogSupports: true);
  }

  void setMaximumSize(int viewId, Size size) {
    call(viewId, () => ffi.setMaxSize(viewId, size: size), dialogSupports: true);
  }

  void setAspectRatio(int viewId, double ratio) {
    call(viewId, () => ffi.setAspectRatio(viewId, ratio));
  }

  void center(int viewId) => setAlignment(viewId, Alignment.center);

  void setAlignment(int viewId, Alignment alignment, {bool insideParent = false}) {
    if (host.isDialog(viewId) && insideParent) {
      final parentId = host.dialogParentId(viewId);
      if (parentId == null) return;
      final parentBounds = ffi.getBounds(parentId);
      final windowSize = ffi.getSize(viewId);
      final pos = calcWindowPositionByParent(alignment, windowSize: windowSize, parentBounds: parentBounds);
      call(viewId, () => ffi.setPosition(viewId, pos: pos), dialogSupports: true);
      return;
    }

    call(
      viewId,
      () => ffi.setAlignment(viewId, alignment: alignment),
      dialogSupports: !host.isModalDialog(viewId),
    );
  }

  bool positionPopup(int viewId, Rect bounds) {
    if (!host.isPopup(viewId)) return false;
    return call(viewId, () => ffi.setPopupBounds(viewId, bounds: bounds), dialogSupports: true) ?? false;
  }
}
