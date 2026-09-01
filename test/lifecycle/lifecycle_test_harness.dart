import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';
import 'package:multiview_desktop/src/lifecycle/lifecycle_views_controller.dart';
import 'package:multiview_desktop/src/lifecycle/view_registry.dart';
import 'package:multiview_desktop/src/utils/window_position_calculator.dart';
import 'package:multiview_desktop/src/view_animation_config.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

/// Instant no-op animator for unit tests.
class InstantViewAnimator extends ViewAnimator {
  InstantViewAnimator();

  @override
  Future<void> animate({
    required void Function(double value) onValue,
    double from = 0.0,
    double to = 1.0,
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
    int? fps,
    bool Function()? isCurrent,
  }) async {
    onValue(from);
    if (isCurrent != null && !isCurrent()) return;
    onValue(to);
  }
}

/// Avoids [ScreenRetriever] in unit tests.
class FakeWindowPositionCalculator extends WindowPositionCalculator {
  FakeWindowPositionCalculator({
    this.byParentResult = const Offset(40, 60),
    this.byDisplayResult = Offset.zero,
  }) : super(resolveDisplay: () => throw StateError('FakeWindowPositionCalculator has no display'));

  Offset byParentResult;
  Offset byDisplayResult;
  final byParentCalls = <({Alignment alignment, Size windowSize, Rect parentBounds})>[];
  final byDisplayCalls = <({Size windowSize, Alignment alignment})>[];

  @override
  Offset calcWindowPosition(Size windowSize, Alignment alignment) {
    byDisplayCalls.add((windowSize: windowSize, alignment: alignment));
    return byDisplayResult;
  }

  @override
  Offset calcWindowPositionByParent(
    Alignment alignment, {
    required Size windowSize,
    required Rect parentBounds,
  }) {
    byParentCalls.add((alignment: alignment, windowSize: windowSize, parentBounds: parentBounds));
    return byParentResult;
  }
}

class LifecycleTestHarness {
  LifecycleTestHarness({
    bool enableDynamicAnchor = true,
    bool Function(int viewId)? isLastMacosRootView,
    List<int> Function({int? excludingViewId})? anchorCandidates,
    bool Function(int parentId)? hasPendingDialogCreate,
    ViewAnimationConfig animation = ViewAnimationConfig.disabled,
    WindowPositionCalculator? positionCalculator,
  }) {
    TestWidgetsFlutterBinding.ensureInitialized();
    ffi = RecordingFfiBridge();
    registry = ViewRegistry();
    cascade = CascadeCloseService();
    disposed = [];
    dialogResults = [];
    popupDestroyed = [];
    beforeCloseApp = 0;
    closeAppAborted = 0;
    beforeForceCloseApp = 0;
    pendingDialogParents = <int>{};
    this.positionCalculator = positionCalculator ?? FakeWindowPositionCalculator();

    // Mirrors `_ViewsManagerImpl._viewExistChecker` without the Flutter-view liveness check.
    T? invoke<T>(int viewId, T Function() func, {bool dialogSupports = false}) {
      final isManaged = registry.isManaged(viewId);
      if (dialogSupports) {
        if (!isManaged) return null;
      } else {
        if (!registry.isWindow(viewId)) return null;
      }
      return func();
    }

    final animator = InstantViewAnimator();
    final animationController = ViewAnimationController(
      config: animation,
      animator: animator,
    );
    host = ViewNativeHost(ffi: ffi, invoke: invoke, registry: registry);
    proxies = ViewManagerProxies(
      host,
      animationController: animationController,
      positionCalculator: this.positionCalculator,
    );
    animationController.bindProxies(proxies);

    final delegate = ViewCloseDelegate(
      disposeView: (id) {
        disposed.add(id);
        registry.windows.remove(id);
        registry.dialogs.remove(id);
        registry.popups.remove(id);
      },
      invoke: invoke,
      anchorCandidatesExcluding: anchorCandidates ??
          ({int? excludingViewId}) => registry.rootWindowIds(excludingId: excludingViewId),
      isLastMacosRootView: isLastMacosRootView ?? (_) => false,
      enableDynamicAnchor: enableDynamicAnchor,
    );

    lifecycle = LifecycleViewsController(
      registry: registry,
      proxies: proxies,
      ffiBridge: ffi,
      closeDelegate: delegate,
      positionCalculator: this.positionCalculator,
      registerDialog: (parentId, {required int dialogId, required bool isModal}) {
        registry.dialogs[dialogId] = ViewDialogEntry(
          widgetBuilder: (_) => const SizedBox.shrink(),
          parentContext: null,
          parentId: parentId,
          isModal: isModal,
          closeCompleter: Completer<Object?>(),
        );
      },
      hasPendingDialogCreate: hasPendingDialogCreate ?? (parentId) => pendingDialogParents.contains(parentId),
      hasModalDialog: (parentId) =>
          registry.dialogs.values.any((d) => d.parentId == parentId && d.isModal),
      animation: animation,
      animationController: animationController,
      cascadeCloseService: cascade,
      onDialogCloseResult: (id, res) => dialogResults.add((id, res)),
      onPopupDestroyed: (id) => popupDestroyed.add(id),
      onBeforeCloseApp: () => beforeCloseApp++,
      onCloseAppAborted: () => closeAppAborted++,
      onBeforeForceCloseApp: () => beforeForceCloseApp++,
    );

    closeService = lifecycle.closeService;
  }

  late final RecordingFfiBridge ffi;
  late final ViewRegistry registry;
  late final CascadeCloseService cascade;
  late final ViewNativeHost host;
  late final ViewManagerProxies proxies;
  late final LifecycleViewsController lifecycle;
  late final ViewCloseService closeService;
  late final WindowPositionCalculator positionCalculator;

  late final List<int> disposed;
  late final List<(int, dynamic)> dialogResults;
  late final List<int> popupDestroyed;
  late final Set<int> pendingDialogParents;
  late int beforeCloseApp;
  late int closeAppAborted;
  late int beforeForceCloseApp;

  FakeWindowPositionCalculator get fakePositionCalculator =>
      positionCalculator as FakeWindowPositionCalculator;

  void seedWindow(int id, {int? parentId}) {
    registry.windows[id] = ViewWindowEntry(
      widgetBuilder: (_) => const SizedBox.shrink(),
      parentContext: null,
      parentId: parentId,
    );
  }

  void seedDialog(int id, {required int parentId, bool isModal = false}) {
    registry.dialogs[id] = ViewDialogEntry(
      widgetBuilder: (_) => const SizedBox.shrink(),
      parentContext: null,
      parentId: parentId,
      isModal: isModal,
      closeCompleter: Completer<Object?>(),
    );
  }

  void seedPopup(int id, {required int parentId}) {
    registry.popups[id] = ViewPopupEntry(parentId: parentId);
  }

  /// Completes cascade wait for [viewId] as if native teardown finished.
  void completeClose(int viewId) => cascade.completeWindow(viewId);
}
