import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'impl/cascade_close_service_impl.dart';
import 'impl/modal_state_service.dart';
import 'impl/window_communicator_impl.dart';
import 'shared_entry_app.dart';
import 'app_shell/app_shell_registry.dart';
import 'view_shell_brightness_sync.dart';
import 'utils/window_position_calculator.dart';
import 'utils/mapped_value_notifier.dart';
import 'view_manager/view_manager_proxies.dart';
import 'view_animation_config.dart' show ViewOpenCloseAnimationPolicy;
import 'lifecycle/lifecycle_views_controller.dart';
import 'lifecycle/create_view_error.dart';
import 'lifecycle/view_registry.dart';

part 'views_manager_impl.dart';

// ---------------------------------------------------------------------------
// Global accessor for MultiViewDesktop and openWindow().
// ---------------------------------------------------------------------------

_MultiViewRootState? _rootState;
final FfiBridge _ffiBridge = FfiBridge.instance;
bool _hasInitView = true;

/// Returns the live `_MultiViewRootState` after `runMultiApp` has started.
// ignore: library_private_types_in_public_api
_MultiViewRootState get globalRootState {
  if (_rootState == null) {
    throw Exception('globalRootState not initialized. Use runMultiApp instead of runApp or runWidget');
  }
  return _rootState!;
}

int get _initPlatformId => !Platform.isMacOS ? 0 : 1;

Widget createMultiViewRoot(
  Widget Function(BuildContext, int) home,
  Widget Function(Widget)? scope,
  MultiAppConfig config,
) {
  _hasInitView = _ffiBridge.checkWindowExist(_initPlatformId);

  // Reset native behavioral flags before the widget tree is built
  if (_hasInitView) {
    _ffiBridge.resetWindowToDefaults(_initPlatformId, config);
  }

  final mainRoot = _MultiViewRoot(homeBuilder: home, config: config);
  return scope?.call(mainRoot) ?? mainRoot;
}

// ---------------------------------------------------------------------------
// _MultiViewRoot
// ---------------------------------------------------------------------------

/// The invisible root widget placed at the top of the tree by `runMultiApp`.
///
/// Manages a `ViewCollection` whose entries grow/shrink as windows are
/// opened or closed.  Each child is wrapped in a `ViewScope` so that any
/// descendant can call `MultiViewDesktop.getIdByContext`.
class _MultiViewRoot extends StatefulWidget {
  const _MultiViewRoot({required this.homeBuilder, required this.config});

  final Widget Function(BuildContext, int) homeBuilder;
  final MultiAppConfig config;

  @override
  State<_MultiViewRoot> createState() => _MultiViewRootState();
}

// ---------------------------------------------------------------------------
// _MultiViewRootState
// ---------------------------------------------------------------------------

class _MultiViewRootState extends State<_MultiViewRoot> with WidgetsBindingObserver {
  late final _ViewsManagerImpl _viewsManagerImpl;

  WindowCommunicator get communicator => _viewsManagerImpl.communicator;

  ViewsManager get manager => _viewsManagerImpl;

  ViewManagerProxies get proxies => _viewsManagerImpl.proxies;

  List<int> get allShiftedViewsId => _viewsManagerImpl.allShiftedWindowIds;

  ValueNotifier<List<int>> get windowsIdsNotif => _viewsManagerImpl.windowsNotifier;

  ValueNotifier<List<int>> get dialogsIdsNotif => _viewsManagerImpl.dialogsNotifier;

  /// Returns the modal-dialog counter notifier for the window with `realViewId`.
  ValueNotifier<List<DialogInfo>> getDialogModalNotifier(int realViewId) =>
      _viewsManagerImpl.getDialogModalPublicIdsFromRealParentIdNotifier(realViewId);

  final AppShellRegistry _appShellRegistry = AppShellRegistry();

  late final AppShellController appShell = AppShellController(_appShellRegistry);

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _rootState = this;
    _viewsManagerImpl = _ViewsManagerImpl(
      config: widget.config,
      cascadeCloseService: CascadeCloseService(),
      communicator: WindowCommunicatorImpl(),
    );
    WidgetsBinding.instance.addObserver(this);

    _initMainView();
  }

  void _initMainView() {
    // Snapshot to avoid concurrent-modification errors on the live views set.
    final initial = WidgetsBinding.instance.platformDispatcher.views.toList();
    final excludeId = !Platform.isMacOS ? -1 : 0;
    final live = initial.where((v) => v.viewId != excludeId).toList();
    if (live.isEmpty) return;

    // After hot restart the lowest live view id may not be 1 (e.g. if view 1 was closed).
    live.sort((a, b) => a.viewId.compareTo(b.viewId));
    _viewsManagerImpl.registerInitialWindow(
      viewId: live.first.viewId,
      homeBuilder: (context) => widget.homeBuilder(context, 1),
    );
    _viewsManagerImpl.applyNativeLifecyclePolicy();
    _viewsManagerImpl.applyInitialTaskbarMenu();
    // Only for debug. Closes all windows from past session on hot restart
    if (!kReleaseMode) {
      final registered = _viewsManagerImpl.allRealWindowIds.toSet();
      final orphaned = live.where((v) => !registered.contains(v.viewId)).toList();
      _viewsManagerImpl.removeOrphanViewsForceAfterRestart(orphaned.map((e) => e.viewId).toList());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_rootState, this)) _rootState = null;
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // WidgetsBindingObserver
  // --------------------------------------------------------------------------

  @override
  void didChangeMetrics() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _viewsManagerImpl.reconcileAnchor(dispatcher);

    final gone = _viewsManagerImpl.allRealWindowIds.where((id) => dispatcher.view(id: id) == null).toList();
    if (gone.isNotEmpty) {
      setState(() {
        for (final id in gone) {
          _handleClose(id);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Linux/Windows: lifecycle is driven only by the implicit view (view 0).
    // When the anchor/main window is hidden or closed while other independent
    // windows remain, the embedder emits AppLifecycleState.hidden and Flutter
    // disables frames for the whole engine. Re-emit inactive to keep rendering
    // (same workaround as multi_window_manager on macOS).
    if (state != AppLifecycleState.hidden) return;
    // if (!Platform.isLinux && !Platform.isWindows) return;
    if (_viewsManagerImpl.allRealWindowIds.isEmpty) return;

    // ignore: invalid_use_of_protected_member
    SchedulerBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  void _handleClose(int viewId) {
    if (!mounted) return;
    _viewsManagerImpl._disposeView(viewId);
    setState(() {});
  }

  void addWindowView(
    int viewId,
    Widget Function(BuildContext) childBuilder, {
    required BuildContext? parentContext,
    int? parentId,
    ViewShellOverrides? shellOverrides,
  }) {
    setState(() {
      _viewsManagerImpl.registerWindow(
        viewId,
        childBuilder,
        parentContext: parentContext,
        parentId: parentId,
        shellOverrides: shellOverrides,
      );
    });
    _syncViewShellBrightness(viewId, shellOverrides);
  }

  void addDialogView<T>(
    int viewId,
    Widget Function(BuildContext) childBuilder, {
    required BuildContext parentContext,
    required int parentId,
    required Completer<T?> closeCompleter,
    bool isModalDialog = false,
    ViewShellOverrides? shellOverrides,
  }) {
    setState(() {
      _viewsManagerImpl.registerDialog<T>(
        viewId,
        childBuilder,
        parentContext: parentContext,
        parentId: parentId,
        isModal: isModalDialog,
        closeCompleter: closeCompleter,
        shellOverrides: shellOverrides,
      );
      return;
    });
    _syncViewShellBrightness(viewId, shellOverrides);
  }

  void _syncViewShellBrightness(int viewId, ViewShellOverrides? shellOverrides) {
    final brightness = resolveViewShellBrightness(_appShellRegistry, shellOverrides);
    if (brightness == null) return;
    _viewsManagerImpl.proxies.appearance.setBrightness(viewId, brightness);
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = <Widget>[];
    final entries = [..._viewsManagerImpl.windowEntries, ..._viewsManagerImpl.dialogEntries];
    final ids = entries.map((e) => e.key).toList()..sort();
    for (int i = 0; i < ids.length; i++) {
      final entry = entries.firstWhere((e) => e.key == ids[i]);
      final id = entry.key;
      final parentContext = entry.value.parentContext;
      final flutterView = dispatcher.view(id: id);
      if (flutterView != null) {
        final modalNotifier = _viewsManagerImpl.getDialogModalPublicIdsFromRealParentIdNotifier(id);
        views.add(
          View(
            key: ValueKey('view_$id'),
            view: flutterView,
            child: DialogScope(
              notifier: modalNotifier,
              child: ParentWindowScope(
                parentContext: parentContext,
                child: ViewScope(
                  viewId: id,
                  child: Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _viewsManagerImpl.firstFrameCbComplete(id);
                      });
                      final content = entry.value.widgetBuilder(context);
                      if (id == _viewsManagerImpl.mainRealViewId) {
                        return MainAppShellCapture(registry: _appShellRegistry, child: content);
                      }

                      return ViewShellBrightnessSync(
                        registry: _appShellRegistry,
                        viewShellOverrides: entry.value.viewShellOverrides,
                        onBrightnessChanged: (brightness) =>
                            _viewsManagerImpl.proxies.appearance.setBrightness(id, brightness),
                        child: SharedEntryApp(
                          registry: _appShellRegistry,
                          viewShellOverrides: entry.value.viewShellOverrides,
                          child: content,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return ViewCollection(views: views);
  }
}
