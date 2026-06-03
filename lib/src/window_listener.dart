import 'package:flutter/widgets.dart';

import 'multi_view_desktop.dart';

/// Callback surface used by the library to deliver native window events.
abstract interface class WindowListenerCallbacks {
  void onWindowClose();

  void onWindowFocus();

  void onWindowBlur();

  void onWindowMaximize();

  void onWindowUnmaximize();

  void onWindowMinimize();

  void onWindowRestore();

  void onWindowResize();

  void onWindowResized();

  void onWindowMove();

  void onWindowMoved();

  void onWindowEnterFullScreen();

  void onWindowLeaveFullScreen();

  void onWindowEvent(String eventName);
}

/// Window lifecycle callbacks for a [State] under [ViewScope].
///
/// Apply on [State]; registration for the current window runs from
/// [didChangeDependencies], cleanup from [dispose] (shifted id via
/// [MultiViewDesktop.getIdByContext], no [BuildContext] in [dispose]).
///
/// ```dart
/// class _HomePageState extends State<HomePage> with WindowListener {
///   @override
///   void onWindowClose() { ... }
/// }
/// ```
mixin WindowListener<T extends StatefulWidget> on State<T> implements WindowListenerCallbacks {
  int? _mvdRegisteredViewId;

  int? get currentId => _mvdRegisteredViewId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mvdSyncWindowListenerRegistration();
  }

  @override
  void dispose() {
    _mvdUnregisterWindowListener();
    super.dispose();
  }

  void _mvdSyncWindowListenerRegistration() {
    final int shiftedViewId = MultiViewDesktop.getIdByContext(context);
    if (_mvdRegisteredViewId == shiftedViewId) return;

    _mvdUnregisterWindowListener();
    _mvdRegisteredViewId = shiftedViewId;
    MultiViewDesktop.addListenerForView(shiftedViewId, this);
  }

  void _mvdUnregisterWindowListener() {
    if(_mvdRegisteredViewId == null) return;

    MultiViewDesktop.removeListenerForView(_mvdRegisteredViewId!, this);
    _mvdRegisteredViewId = null;
  }

  @override
  void onWindowClose() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}
}
