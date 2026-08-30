import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/lifecycle/view_animator.dart';
import 'package:multiview_desktop/src/lifecycle/view_animation_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_registry.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';

import 'lifecycle_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewAnimator', () {
    testWidgets('endOfFrame path reaches to value when fps is null', (tester) async {
      final values = <double>[];
      final animator = ViewAnimator();

      final future = animator.animate(
        onValue: values.add,
        from: 0,
        to: 1,
        duration: const Duration(milliseconds: 50),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 50));
      await future;

      expect(values.first, 0);
      expect(values.last, 1);
      expect(values.length, greaterThan(2));
    });

    test('timer path reaches to value at fixed fps', () async {
      final values = <double>[];
      final animator = ViewAnimator();

      final future = animator.animate(
        onValue: values.add,
        from: 1,
        to: 0,
        duration: const Duration(milliseconds: 40),
        fps: 50,
      );

      await future;

      expect(values.first, 1);
      expect(values.last, 0);
    });
  });

  group('ViewAnimationController force/soft', () {
    ViewAnimationController makeController(RecordingFfiBridge ffi, ViewAnimationConfig config) {
      final registry = ViewRegistry();
      final host = ViewNativeHost(
        ffi: ffi,
        invoke: <T>(int viewId, T Function() f, {bool dialogSupports = false}) => f(),
        registry: registry,
      );
      final controller = ViewAnimationController(
        config: config,
        animator: InstantViewAnimator(),
      );
      final proxies = ViewManagerProxies(host, animationController: controller);
      controller.bindProxies(proxies);
      return controller;
    }

    test('force override runs close fade even when config disables fadeOut', () async {
      final ffi = RecordingFfiBridge();
      final controller = makeController(ffi, ViewAnimationConfig.disabled);

      controller.stageForceOverride(
        7,
        ViewAnimationType.closeWindow,
        const AnimationSettings(duration: Duration(milliseconds: 20), fps: 50),
      );

      await controller.animateClose(
        7,
        type: ViewAnimationType.closeWindow,
        policy: ViewOpenCloseAnimationPolicy.disabled,
      );

      expect(ffi.callsFor('setOpacity'), isNotEmpty);
      expect(ffi.callsFor('setOpacity').last, 'setOpacity:7:0.0');
    });

    test('soft override is not staged when animation type is disabled', () async {
      final ffi = RecordingFfiBridge();
      final controller = makeController(ffi, ViewAnimationConfig.disabled);

      controller.stageSoftOverride(
        7,
        ViewAnimationType.setSize,
        const AnimationSettings(duration: Duration(milliseconds: 20)),
      );

      await controller.applyAnimatedFrame(
        7,
        ViewAnimationType.setSize,
        const Rect.fromLTWH(0, 0, 1, 1),
        const Rect.fromLTWH(0, 0, 10, 10),
      );

      // Instant set only. No animation ticks beyond the final setFrame.
      expect(ffi.callsFor('setFrame'), ['setFrame:7:0.0,0.0,10.0,10.0']);
    });

    test('force override animates geometry when geometry policy is disabled', () async {
      final ffi = RecordingFfiBridge();
      final controller = makeController(ffi, ViewAnimationConfig.disabled);

      controller.stageForceOverride(
        7,
        ViewAnimationType.setSize,
        const AnimationSettings(duration: Duration(milliseconds: 20), fps: 50),
      );

      await controller.applyAnimatedFrame(
        7,
        ViewAnimationType.setSize,
        const Rect.fromLTWH(0, 0, 1, 1),
        const Rect.fromLTWH(0, 0, 10, 10),
      );

      expect(ffi.callsFor('setFrame').length, greaterThan(1));
      expect(ffi.callsFor('setFrame').last, 'setFrame:7:0.0,0.0,10.0,10.0');
    });

    test('force timing wins over soft when both are staged', () async {
      final ffi = RecordingFfiBridge();
      final durations = <Duration>[];
      final controller = ViewAnimationController(
        config: ViewAnimationConfig.defaults,
        animator: _RecordingDurationAnimator(durations),
      );
      final registry = ViewRegistry();
      final host = ViewNativeHost(
        ffi: ffi,
        invoke: <T>(int viewId, T Function() f, {bool dialogSupports = false}) => f(),
        registry: registry,
      );
      controller.bindProxies(ViewManagerProxies(host, animationController: controller));

      controller.stageSoftOverride(
        1,
        ViewAnimationType.closeWindow,
        const AnimationSettings(duration: Duration(milliseconds: 500)),
      );
      controller.stageForceOverride(
        1,
        ViewAnimationType.closeWindow,
        const AnimationSettings(duration: Duration(milliseconds: 42)),
      );

      await controller.animateClose(
        1,
        type: ViewAnimationType.closeWindow,
        policy: ViewAnimationConfig.defaults.windowOpenClose,
      );

      expect(durations, [const Duration(milliseconds: 42)]);
    });

    test('soft timing applies when animation is enabled and no force is staged', () async {
      final ffi = RecordingFfiBridge();
      final durations = <Duration>[];
      final controller = ViewAnimationController(
        config: ViewAnimationConfig.defaults,
        animator: _RecordingDurationAnimator(durations),
      );
      final registry = ViewRegistry();
      final host = ViewNativeHost(
        ffi: ffi,
        invoke: <T>(int viewId, T Function() f, {bool dialogSupports = false}) => f(),
        registry: registry,
      );
      controller.bindProxies(ViewManagerProxies(host, animationController: controller));

      controller.stageSoftOverride(
        1,
        ViewAnimationType.closeWindow,
        const AnimationSettings(duration: Duration(milliseconds: 333)),
      );

      await controller.animateClose(
        1,
        type: ViewAnimationType.closeWindow,
        policy: ViewAnimationConfig.defaults.windowOpenClose,
      );

      expect(durations, [const Duration(milliseconds: 333)]);
    });

    test('popup soft timing applies when popup fade is enabled', () async {
      final ffi = RecordingFfiBridge();
      final durations = <Duration>[];
      final controller = ViewAnimationController(
        config: ViewAnimationConfig.defaults,
        animator: _RecordingDurationAnimator(durations),
      );
      final registry = ViewRegistry();
      final host = ViewNativeHost(
        ffi: ffi,
        invoke: <T>(int viewId, T Function() f, {bool dialogSupports = false}) => f(),
        registry: registry,
      );
      controller.bindProxies(ViewManagerProxies(host, animationController: controller));

      controller.stageSoftOverride(
        9,
        ViewAnimationType.closePopup,
        const AnimationSettings(duration: Duration(milliseconds: 80)),
      );

      await controller.animateClose(
        9,
        type: ViewAnimationType.closePopup,
        policy: ViewAnimationConfig.defaults.popupOpenClose,
      );

      expect(durations, [const Duration(milliseconds: 80)]);
    });

    test('popup soft override is not staged when popup fade is disabled', () async {
      final ffi = RecordingFfiBridge();
      final controller = makeController(ffi, ViewAnimationConfig.disabled);

      controller.stageSoftOverride(
        9,
        ViewAnimationType.closePopup,
        const AnimationSettings(duration: Duration(milliseconds: 80)),
      );

      await controller.animateClose(
        9,
        type: ViewAnimationType.closePopup,
        policy: ViewOpenCloseAnimationPolicy.disabled,
      );

      expect(ffi.callsFor('setOpacity'), isEmpty);
    });

    test('popup ignores force override', () async {
      final ffi = RecordingFfiBridge();
      final controller = makeController(ffi, ViewAnimationConfig.disabled);

      controller.stageForceOverride(
        9,
        ViewAnimationType.closePopup,
        const AnimationSettings(duration: Duration(milliseconds: 20), fps: 50),
      );

      await controller.animateClose(
        9,
        type: ViewAnimationType.closePopup,
        policy: ViewOpenCloseAnimationPolicy.disabled,
      );

      expect(ffi.callsFor('setOpacity'), isEmpty);
    });

    test('cancelAnimations stops further open-fade opacity ticks', () async {
      final ffi = RecordingFfiBridge();
      final controller = ViewAnimationController(
        config: ViewAnimationConfig.defaults,
        animator: ViewAnimator(),
      );
      final registry = ViewRegistry();
      final host = ViewNativeHost(
        ffi: ffi,
        invoke: <T>(int viewId, T Function() f, {bool dialogSupports = false}) => f(),
        registry: registry,
      );
      controller.bindProxies(ViewManagerProxies(host, animationController: controller));

      controller.stageSoftOverride(
        9,
        ViewAnimationType.createPopup,
        const AnimationSettings(duration: Duration(milliseconds: 200), fps: 50),
      );

      final future = controller.animateOpen(
        9,
        type: ViewAnimationType.createPopup,
        policy: ViewAnimationConfig.defaults.popupOpenClose,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      final ticksBeforeCancel = ffi.callsFor('setOpacity').length;
      expect(ticksBeforeCancel, greaterThan(1));

      controller.cancelAnimations(9);
      await future;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(ffi.callsFor('setOpacity').length, ticksBeforeCancel);
    });
  });
}

class _RecordingDurationAnimator extends ViewAnimator {
  _RecordingDurationAnimator(this.durations);

  final List<Duration> durations;

  @override
  Future<void> animate({
    required void Function(double value) onValue,
    double from = 0.0,
    double to = 1.0,
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
    int? fps,
  }) async {
    durations.add(duration);
    onValue(from);
    onValue(to);
  }
}
