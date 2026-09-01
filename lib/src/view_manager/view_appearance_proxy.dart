import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewAppearanceProxy extends ViewNativeProxy {
  const ViewAppearanceProxy(super.host);

  String getTitle(int viewId) =>
      call(viewId, () => ffi.getTitle(viewId), dialogSupports: true) ?? '';

  void setTitle(int viewId, String title) {
    call(viewId, () => ffi.setTitle(viewId, title: title), dialogSupports: true);
  }

  ({
    TitleBarStyle? style,
    bool? closeVisibility,
    bool? maximizeVisibility,
    bool? minimizeVisibility,
  }) getTitleBarStyle(int viewId) {
    return call(viewId, () => ffi.getTitleBarStyle(viewId), dialogSupports: true) ??
        (style: TitleBarStyle.normal, closeVisibility: true, maximizeVisibility: true, minimizeVisibility: true);
  }

  void setTitleBarStyle(
    int viewId,
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) {
    call(
      viewId,
      () => ffi.setTitleBarStyle(
        viewId,
        style: style,
        closeVisibility: closeVisibility,
        maximizeVisibility: maximizeVisibility,
        minimizeVisibility: minimizeVisibility,
      ),
      dialogSupports: true,
    );
  }

  void setAsFrameless(int viewId) {
    call(
      viewId,
      () => ffi.setAsFrameless(viewId),
      dialogSupports: !host.isModalDialog(viewId),
    );
  }

  void setBackgroundColor(int viewId, Color color) {
    call(viewId, () => ffi.setBackgroundColor(viewId, color: color), dialogSupports: true);
  }

  void setBrightness(int viewId, Brightness brightness) {
    call(viewId, () => ffi.setBrightness(viewId, brightness), dialogSupports: true);
  }

  void setGlobalBrightness(Brightness brightness) {
    for (final viewId in host.allManagedViewIds()) {
      call(viewId, () => ffi.setBrightness(viewId, brightness), dialogSupports: true);
    }
  }

  void setOpacity(int viewId, double opacity) {
    call(viewId, () => ffi.setOpacity(viewId, opacity), dialogSupports: true);
  }

  double getOpacity(int viewId) =>
      call(viewId, () => ffi.getOpacity(viewId), dialogSupports: true) ?? 1;

  bool hasShadow(int viewId) =>
      call(viewId, () => ffi.hasShadow(viewId), dialogSupports: true) ?? true;

  void setHasShadow(int viewId, bool value) {
    call(viewId, () => ffi.setHasShadow(viewId, value), dialogSupports: true);
  }
}
