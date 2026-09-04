// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/src/lifecycle/view_animation_controller.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_manager/view_appearance_proxy.dart';
import 'package:multiview_desktop/src/view_manager/view_input_proxy.dart';
import 'package:multiview_desktop/src/view_manager/view_native_host.dart';
import 'package:multiview_desktop/src/view_manager/view_platform_proxy.dart';
import 'package:multiview_desktop/src/view_manager/view_position_proxy.dart';
import 'package:multiview_desktop/src/view_manager/view_size_constraints.dart';
import 'package:multiview_desktop/src/view_manager/view_taskbar_proxy.dart';
import 'package:multiview_desktop/src/view_manager/view_window_state_proxy.dart';

export 'view_appearance_proxy.dart' show ViewAppearanceProxy;
export 'view_input_proxy.dart' show ViewInputProxy;
export 'view_native_host.dart' show ViewNativeHost, ViewNativeProxy;
export 'view_platform_proxy.dart' show ViewPlatformProxy;
export 'view_position_proxy.dart' show ViewPositionProxy;
export 'view_taskbar_proxy.dart' show ViewTaskbarProxy;
export 'view_window_state_proxy.dart' show ViewWindowStateProxy;

/// Groups native FFI proxies. Exposed via [globalRootState.proxies] for [MultiViewDesktop].
@internal
class ViewManagerProxies {
  ViewManagerProxies(
    ViewNativeHost host, {
    required ViewAnimationController animationController,
    WindowPositionCalculator? positionCalculator,
    ViewSizeConstraints? sizeConstraints,
  })  : position = ViewPositionProxy(
          host,
          animationController: animationController,
          positionCalculator: positionCalculator,
          sizeConstraints: sizeConstraints,
        ),
        appearance = ViewAppearanceProxy(host),
        state = ViewWindowStateProxy(host),
        taskbar = ViewTaskbarProxy(host),
        platform = ViewPlatformProxy(host),
        input = ViewInputProxy(host);

  final ViewPositionProxy position;
  final ViewAppearanceProxy appearance;
  final ViewWindowStateProxy state;
  final ViewTaskbarProxy taskbar;
  final ViewPlatformProxy platform;
  final ViewInputProxy input;
}
