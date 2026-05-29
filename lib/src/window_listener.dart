/// Mixin for listening to window lifecycle events.
///
/// Register via [MultiViewDesktop.addListener] /
/// [MultiViewDesktop.removeListener].
abstract mixin class WindowListener {
  /// Emitted when the user requests close while [MultiViewDesktop.setPreventClose] is `true`,
  /// or when the native close button is blocked by prevent-close.
  void onWindowClose() {}

  /// Emitted when the window becomes the key (focused) window.
  void onWindowFocus() {}

  /// Emitted when the window resigns key focus.
  void onWindowBlur() {}

  /// Emitted when the window is zoomed / maximized.
  void onWindowMaximize() {}

  /// Emitted when the window leaves the zoomed / maximized state.
  void onWindowUnmaximize() {}

  /// Emitted when the window is miniaturized to the dock.
  void onWindowMinimize() {}

  /// Emitted when the window is restored from miniaturized state.
  void onWindowRestore() {}

  /// Emitted continuously while the window frame is being resized.
  void onWindowResize() {}

  /// Emitted once when a live resize operation finishes.
  void onWindowResized() {}

  /// Emitted continuously while the window is being dragged.
  void onWindowMove() {}

  /// Emitted once when a move operation finishes.
  void onWindowMoved() {}

  /// Emitted when the window enters native full-screen mode.
  void onWindowEnterFullScreen() {}

  /// Emitted when the window leaves native full-screen mode.
  void onWindowLeaveFullScreen() {}

  /// Fallback for any event name not mapped to a dedicated callback above.
  void onWindowEvent(String eventName) {}
}
