/// Mixin for listening to window lifecycle events.
///
/// Register via [MultiViewDesktop.addListener] /
/// [MultiViewDesktop.removeListener].
abstract mixin class WindowListener {
  void onWindowClose() {}

  void onWindowFocus() {}

  void onWindowBlur() {}

  void onWindowMaximize() {}

  void onWindowUnmaximize() {}

  void onWindowMinimize() {}

  void onWindowRestore() {}

  void onWindowResize() {}

  void onWindowResized() {}

  void onWindowMove() {}

  void onWindowMoved() {}

  void onWindowEnterFullScreen() {}

  void onWindowLeaveFullScreen() {}

  void onWindowEvent(String eventName) {}
}
