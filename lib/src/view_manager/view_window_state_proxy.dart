import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/resize_edge.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';

@internal
class ViewWindowStateProxy extends ViewNativeProxy {
  const ViewWindowStateProxy(super.host);

  void show(int viewId) {
    call(viewId, () => ffi.show(viewId), dialogSupports: true);
  }

  void hide(int viewId) {
    call(viewId, () => ffi.hide(viewId), dialogSupports: true);
  }

  bool isVisible(int viewId) =>
      call(viewId, () => ffi.isVisible(viewId), dialogSupports: true) ?? true;

  void focus(int viewId) {
    call(viewId, () => ffi.focus(viewId), dialogSupports: true);
  }

  void blur(int viewId) {
    call(viewId, () => ffi.blur(viewId), dialogSupports: true);
  }

  bool isFocused(int viewId) =>
      call(viewId, () => ffi.isFocused(viewId), dialogSupports: true) ?? true;

  void maximize(int viewId, {bool vertically = false}) {
    call(viewId, () => ffi.maximize(viewId, vertically: vertically));
  }

  void unmaximize(int viewId) {
    call(viewId, () => ffi.unmaximize(viewId));
  }

  bool isMaximized(int viewId) => call(viewId, () => ffi.isMaximized(viewId)) ?? false;

  void minimize(int viewId) {
    call(viewId, () => ffi.minimize(viewId));
  }

  void restore(int viewId) {
    call(viewId, () => ffi.restore(viewId));
  }

  bool isMinimized(int viewId) => call(viewId, () => ffi.isMinimized(viewId)) ?? false;

  bool isFullScreen(int viewId) => call(viewId, () => ffi.isFullScreen(viewId)) ?? false;

  void setFullScreen(int viewId, bool isFullScreen) {
    call(viewId, () => ffi.setFullScreen(viewId, isFullScreen: isFullScreen));
  }

  bool isResizable(int viewId) =>
      call(viewId, () => ffi.isResizable(viewId), dialogSupports: true) ?? true;

  void setResizable(int viewId, bool isResizable) {
    call(viewId, () => ffi.setResizable(viewId, isResizable), dialogSupports: true);
  }

  bool isMovable(int viewId) =>
      call(viewId, () => ffi.isMovable(viewId), dialogSupports: true) ?? true;

  void setMovable(int viewId, bool isMovable) {
    call(viewId, () => ffi.setMovable(viewId, isMovable), dialogSupports: true);
  }

  bool isMinimizable(int viewId) => call(viewId, () => ffi.isMinimizable(viewId)) ?? true;

  void setMinimizable(int viewId, bool isMinimizable) {
    call(viewId, () => ffi.setMinimizable(viewId, isMinimizable));
  }

  bool isMaximizable(int viewId) => call(viewId, () => ffi.isMaximizable(viewId)) ?? true;

  void setMaximizable(int viewId, bool isMaximizable) {
    call(viewId, () => ffi.setMaximizable(viewId, isMaximizable));
  }

  bool isClosable(int viewId) =>
      call(viewId, () => ffi.isClosable(viewId), dialogSupports: true) ?? true;

  void setClosable(int viewId, bool isClosable) {
    call(viewId, () => ffi.setClosable(viewId, isClosable), dialogSupports: true);
  }

  bool isAlwaysOnTop(int viewId) =>
      call(viewId, () => ffi.isAlwaysOnTop(viewId), dialogSupports: true) ?? false;

  void setAlwaysOnTop(int viewId, bool isAlwaysOnTop) {
    call(
      viewId,
      () => ffi.setAlwaysOnTop(viewId, isAlwaysOnTop: isAlwaysOnTop),
      dialogSupports: true,
    );
  }

  bool isPreventClose(int viewId) => call(viewId, () => ffi.isPreventClose(viewId)) ?? false;

  void setPreventClose(int viewId, bool isPreventClose) {
    call(viewId, () => ffi.setPreventClose(viewId, isPreventClose: isPreventClose), dialogSupports: false);
  }

  void startDragging(int viewId) {
    call(viewId, () => ffi.startDragging(viewId), dialogSupports: true);
  }

  void startResizing(int viewId, ResizeEdge edge) {
    if (Platform.isMacOS) return;
    call(viewId, () => ffi.startResizing(viewId, edge), dialogSupports: true);
  }
}
