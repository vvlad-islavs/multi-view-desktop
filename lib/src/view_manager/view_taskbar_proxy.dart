import 'dart:io';

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewTaskbarProxy extends ViewNativeProxy {
  ViewTaskbarProxy(super.host);

  List<VoidCallback?> _menuCallbacks = [];

  Future<void> setTaskbarMenu({required List<TaskbarMenuItem> items}) async {
    _menuCallbacks = [for (final item in items) item.onPressed];
    final encoded = <Map<String, dynamic>>[for (var i = 0; i < items.length; i++) await items[i].toJson(i)];
    ffi.setTaskbarMenu(encoded);
  }

  void invokeMenuCallback(int id) {
    if (id < 0 || id >= _menuCallbacks.length) return;
    _menuCallbacks[id]?.call();
  }

  void setProgressBar(double progress) {
    if (Platform.isLinux) return;
    final id = firstAvailableId;
    if (id == null) return;
    call(id, () => ffi.setProgressBar(progress), dialogSupports: true);
  }

  void popUpWindowMenu(int viewId) {
    call(viewId, () => ffi.popUpWindowMenu(viewId), dialogSupports: true);
  }

  bool isHideAppFromTaskbar() {
    if (Platform.isWindows || Platform.isLinux) {
      return ffi.isHideAppFromTaskbar();
    }
    final id = firstAvailableId;
    if (id == null) return false;
    return call(id, () => ffi.isHideAppFromTaskbar(), dialogSupports: true) ?? false;
  }

  bool isHideAppTabFromTaskbar(int viewId) {
    if (!Platform.isWindows) {
      return isHideAppFromTaskbar();
    }
    return call(viewId, () => ffi.isHideAppTabFromTaskbar(viewId), dialogSupports: true) ?? false;
  }

  void hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId}) {
    if (Platform.isMacOS) {
      final id = firstAvailableId;
      if (id == null) return;
      call(id, () => ffi.hideAppFromTaskbar(id, isHideAppFromTaskbar: isHideAppFromTaskbar), dialogSupports: true);
      return;
    }

    if (viewId == null) {
      for (final id in host.windowViewIds()) {
        call(id, () => ffi.hideAppFromTaskbar(id, isHideAppFromTaskbar: isHideAppFromTaskbar), dialogSupports: true);
      }
      return;
    }

    call(
      viewId,
      () => ffi.hideAppFromTaskbar(viewId, isHideAppFromTaskbar: isHideAppFromTaskbar),
      dialogSupports: true,
    );
  }

  /// Real native view id. [MultiViewDesktop.allWindowViewIds] is public/shifted
  /// (1 on Windows) and would fail [_viewExistChecker] (registry key is 0).
  @visibleForTesting
  int? get firstAvailableId => host.windowViewIds().firstOrNull;
}
