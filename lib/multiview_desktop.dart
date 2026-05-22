// Single-engine multi-window library for Flutter desktop.
//
// Entry point:
//   void main() => runMultiApp(const MyApp());
//
// Open a new window from anywhere:
//   addWindow(const SettingsPage());
//
// Work with the current window via context:
//   MultiViewDesktop.getCurrentId(context)
//   MultiViewDesktop.closeWindow(context)
//   MultiViewDesktop.setTitleBarStyle(context, TitleBarStyle.hidden)
export 'src/multi_view_desktop.dart';
export 'src/resize_edge.dart';
export 'src/run_multi_app.dart';
export 'src/title_bar_style.dart';
export 'src/view_scope.dart';
export 'src/window_communicator.dart';
export 'src/window_listener.dart';
export 'src/window_options.dart';
export 'src/widgets/drag_to_move_area.dart';
export 'src/widgets/drag_to_resize_area.dart';
export 'src/widgets/window_caption.dart';
