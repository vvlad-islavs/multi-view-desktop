/// Single-engine multi-window library for Flutter desktop.
///
/// All OS windows share one Flutter engine and one Dart isolate.
///
/// **Entry point**: replace [runApp] with [runMultiApp]:
/// ```dart
/// void main() => runMultiApp(const MyApp());
/// ```
///
/// **Open another window**: from anywhere, without [BuildContext]:
/// ```dart
/// openWindow(const SettingsPage(), options: WindowOptions(title: 'Settings'));
/// ```
///
/// **Control the current window**: pass [BuildContext] from the target view:
/// ```dart
/// final id = MultiViewDesktop.getCurrentId(context);
/// await MultiViewDesktop.closeWindow(context);
/// await MultiViewDesktop.setTitleBarStyle(context, TitleBarStyle.hidden);
/// ```
///
/// See also [WindowListener], [WindowCommunicator], and [WindowOptions].
library;

export 'src/multi_view_desktop.dart';
export 'src/resize_edge.dart';
export 'src/run_multi_app.dart';
export 'src/title_bar_style.dart';
export 'src/parent_window_scope.dart';
export 'src/window_communicator.dart';
export 'src/window_listener.dart';
export 'src/window_options.dart';
export 'src/widgets/drag_to_move_area.dart';
export 'src/widgets/drag_to_resize_area.dart';
export 'src/widgets/window_caption.dart';
