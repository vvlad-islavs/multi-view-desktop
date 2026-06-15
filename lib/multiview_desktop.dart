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
/// **Control the current window**: obtain an instance from [BuildContext] or a view ID:
/// ```dart
/// final win = MultiViewDesktop.of(context);
/// await win.closeWindow();
/// await win.setTitleBarStyle(TitleBarStyle.hidden);
///
/// // Or by shifted view ID:
/// await MultiViewDesktop.fromId(viewId).setTitle('Settings');
/// ```
///
/// See also [WindowListener], [WindowCommunicator], and [WindowOptions].
library;

export 'src/multi_view_desktop.dart';
export 'src/resize_edge.dart';
export 'src/run_multi_app.dart';
export 'src/app_shell/app_shell.dart';
export 'src/title_bar_style.dart';
export 'src/parent_window_scope.dart';
export 'src/window_communicator.dart';
export 'src/window_listener.dart';
export 'src/window_observer.dart';
export 'src/window_options.dart';
export 'src/widgets/dialog_modal_layer.dart';
export 'src/widgets/drag_to_move_area.dart';
export 'src/widgets/drag_to_resize_area.dart';
export 'src/widgets/window_caption.dart';
export 'src/extensions.dart';
