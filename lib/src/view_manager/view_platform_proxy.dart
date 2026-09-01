import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

/// macOS- and platform-specific native window flags.
@internal
class ViewPlatformProxy extends ViewNativeProxy {
  const ViewPlatformProxy(super.host);

  bool isOnActiveSpace(int viewId) {
    if (!Platform.isMacOS) return true;
    return call(viewId, () => ffi.isOnActiveSpace(viewId), dialogSupports: true) ?? true;
  }

  bool isHideFromCollection(int viewId) {
    if (!Platform.isMacOS) return false;
    return call(viewId, () => ffi.isHideFromCollection(viewId), dialogSupports: true) ?? false;
  }

  void hideFromCollection(int viewId, bool isHideFromCollection) {
    if (!Platform.isMacOS) return;
    call(viewId, () => ffi.hideFromCollection(viewId, isHideFromCollection), dialogSupports: true);
  }

  bool isVisibleOnAllWorkspaces(int viewId) {
    return call(viewId, () => ffi.isVisibleOnAllWorkspaces(viewId), dialogSupports: true) ?? true;
  }

  void setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) {
    if (!Platform.isMacOS) return;
    call(
      viewId,
      () => ffi.setVisibleOnAllWorkspaces(viewId, visible, visibleOnFullScreen: visibleOnFullScreen),
      dialogSupports: true,
    );
  }

  void setBadgeLabel(int viewId, String? label) {
    if (!Platform.isMacOS) return;
    call(viewId, () => ffi.setBadgeLabel(viewId, label: label), dialogSupports: true);
  }
}
