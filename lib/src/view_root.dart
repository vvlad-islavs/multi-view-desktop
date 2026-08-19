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
import 'utils/calc_window_position.dart';
import 'utils/mapped_value_notifier.dart';

enum _CreateViewError {
  timeout(code: -1),
  forceClose(code: -2),
  unhandled(code: null);

  final int? code;

  String message(int token) => switch (this) {
    _CreateViewError.timeout => 'Failed to create dialog window, tokenId: $token. Error: timeout',
    _CreateViewError.forceClose => 'Failed to create dialog window, tokenId: $token. Error: force close',
    _CreateViewError.unhandled => 'Failed to create dialog window, tokenId: $token. Unhandled error',
  };

  const _CreateViewError({required this.code});
}

// ---------------------------------------------------------------------------
// Per-window registration (widget tree + optional parent link).
// ---------------------------------------------------------------------------
abstract class _ViewEntry {
  _ViewEntry({required this.widgetBuilder, required this.parentContext, ViewShellOverrides? initialShellOverrides})
    : viewShellOverrides = ValueNotifier<ViewShellOverrides?>(initialShellOverrides);

  final Widget Function(BuildContext) widgetBuilder;
  final BuildContext? parentContext;

  final ValueNotifier<ViewShellOverrides?> viewShellOverrides;

  void disposeEntryResources() => viewShellOverrides.dispose();
}

class _WindowEntry extends _ViewEntry {
  _WindowEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    this.parentId,
  });

  final int? parentId;
}

class _DialogEntry<T> extends _ViewEntry {
  _DialogEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    required this.parentId,
    required this.isModal,
    required this.closeCompleter,
  });

  final int parentId;
  final bool isModal;
  final Completer<T?> closeCompleter;

  void completeResult(dynamic result) {
    if (result != null && result is! T) {
      throw ArgumentError.value(result, 'MVD', 'Expected dialog result of type $T, got ${result.runtimeType}');
    }
    if (!closeCompleter.isCompleted) {
      closeCompleter.complete(result as T?);
    }
  }
}

class _PopupEntry {
  _PopupEntry({required this.parentId});

  final int parentId;
}

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
    _viewsManagerImpl.setBrightness(viewId, brightness);
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
                      final content = entry.value.widgetBuilder(context);
                      if (id == _viewsManagerImpl.mainRealViewId) {
                        return MainAppShellCapture(registry: _appShellRegistry, child: content);
                      }

                      return ViewShellBrightnessSync(
                        registry: _appShellRegistry,
                        viewShellOverrides: entry.value.viewShellOverrides,
                        onBrightnessChanged: (brightness) => _viewsManagerImpl.setBrightness(id, brightness),
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

// ---------------------------------------------------------------------------
// ViewsManager impl
// ---------------------------------------------------------------------------

class _CreateCompleter<T> {
  final Completer<T?> completer;
  final int token;
  final bool isDialog;
  final int? parentId;

  const _CreateCompleter({
    required this.completer,
    required this.token,
    required this.isDialog,
    required this.parentId,
  });

  // factory _CreateCompleter.window(int token, {int? parentId}) {
  //   return _CreateCompleter(completer: Completer<T?>(), token: token, isDialog: false, parentId: parentId);
  // }

  // factory _CreateCompleter.popup(int token, {required int parentId}) {
  //   return _CreateCompleter(completer: Completer<T?>(), token: token, isDialog: false, parentId: parentId);
  // }

  factory _CreateCompleter.dialog(int token, {required int parentId}) {
    return _CreateCompleter(completer: Completer<T?>(), token: token, isDialog: true, parentId: parentId);
  }

  void complete([T? resId]) => completer.complete(resId);

  bool get isCompleted => completer.isCompleted;

  Future<T?> get future => completer.future;
}

/// Default `ViewsManager`: native channel, window registry, listeners, and close modes.
class _ViewsManagerImpl implements ViewsManager {
  final CascadeCloseService cascadeCloseService;
  final WindowCommunicatorImpl communicator;
  final MultiAppConfig config;

  final ModalStateService _modalStateService = ModalStateService();

  /// Active strategy when the main window's close button is pressed.
  late CloseMode closeMode;

  _ViewsManagerImpl({required this.config, required this.cascadeCloseService, required this.communicator}) {
    _ffiBridge.setMethodCallHandler(_onStaticCall);
    closeMode = config.generalParams.closeMode;
  }

  late bool _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;

  List<VoidCallback?> _taskbarMenuCallbacks = [];

  /// Applies `MultiPlatformParams.menuItems` from startup config.
  void applyInitialTaskbarMenu() {
    final items = config.generalParams.menuItems;
    if (items.isEmpty) return;
    setTaskbarMenu(items: items);
  }

  /// Pushes lifecycle quit policy to the native embedder.
  void applyNativeLifecyclePolicy() {
    if (Platform.isMacOS) {
      _ffiBridge.setTerminateAfterLastWindowClosed(
        config.macosParams.closeAppAfterLastWindowClosed && !_saveLastWindowToReopen,
      );
      _ffiBridge.setHasTaskbarCallback(config.macosParams.onTaskbarTap != null);
    } else if (Platform.isLinux) {
      _ffiBridge.setTerminateAfterLastWindowClosed(true);
    }
  }

  /// Returns the `ValueNotifier<List<DialogInfo>>` tracking modal dialogs blocking `realViewId`.
  ValueNotifier<List<DialogInfo>> getDialogModalPublicIdsFromRealParentIdNotifier(int realViewId) =>
      _dialogModalPublicNotifiers.putIfAbsent(
        realViewId,
        () => MappedValueNotifier(
          source: _modalStateService.getNotifier(realViewId),
          transform: (dialogs) => [for (final d in dialogs) (id: _realToShifted(d.id), isModal: d.isModal)],
        ),
      );

  @override
  int shiftedToRealId(int viewId) => _shiftedToReal(viewId);

  @override
  int realToShiftedId(int viewId) => _realToShifted(viewId);

  // token -> widget, entries waiting for the native "viewCreated" event.
  int _nextToken = 0;

  // id shift after hot restart
  int _hotRestartShift = 0;

  final Map<int, ValueNotifier<List<DialogInfo>>> _dialogModalPublicNotifiers = {};

  final Map<int, dynamic> _dialogsResults = {};

  // token -> Completer<int?> for pending views.
  final Map<int, _CreateCompleter<int?>> _createCompleters = {};

  final Map<int, int> _childCreatePending = {};

  // viewId -> listener list.
  final Map<int, ObserverList<WindowListenerCallbacks>> _listeners = {};

  /// Anchor window: receives app-level close policy (`CloseMode`) from the native close button.
  int? _realAnchorId;

  int? get realAnchorId => _realAnchorId;

  /// Back-compat alias used by native channel app-wide calls.
  int? get mainId => _realAnchorId;

  List<WindowObserver> get _observers => config.observers;

  /// View id for app-wide native calls (dock badge, taskbar, etc.).
  int? get _lifecycleViewId {
    if (_realAnchorId != null && _windows.containsKey(_realAnchorId)) return _realAnchorId;
    if (_windows.isEmpty) return null;
    return _windows.keys.reduce((a, b) => a < b ? a : b);
  }

  int _initRealId = _initPlatformId;

  int get mainRealViewId => _initRealId;
  bool _isInitFirstSecondaryView = false;

  final Map<int, _WindowEntry> _windows = {};
  final Map<int, _DialogEntry> _dialogs = {};
  final Map<int, _PopupEntry> _popups = {};

  final ValueNotifier<List<int>> _windowsNotifier = ValueNotifier([]);
  final ValueNotifier<List<int>> _dialogsNotifier = ValueNotifier([]);

  ValueNotifier<List<int>> get windowsNotifier => _windowsNotifier;

  ValueNotifier<List<int>> get dialogsNotifier => _dialogsNotifier;

  Iterable<MapEntry<int, _WindowEntry>> get windowEntries => _windows.entries;

  Iterable<MapEntry<int, _DialogEntry>> get dialogEntries => _dialogs.entries;

  List<int> get allRealWindowIds => _windows.keys.toList();

  List<int> get allShiftedWindowIds => _windows.keys.map((e) => _realToShifted(e)).toList();

  void registerInitialWindow({required int viewId, required Widget Function(BuildContext) homeBuilder}) {
    // Win & linux by default init from 0 id but macos from 1
    _hotRestartShift = !Platform.isMacOS ? -1 : 0;
    if (!_hasInitView) {
      viewId = _createNextMainWindowAfterRestart(homeBuilder);
    }

    _hotRestartShift = viewId - 1;
    _initRealId = viewId;
    _setAnchor(viewId, force: true);
    _applyOptionsToInitialAnchor();

    globalRootState.addWindowView(viewId, homeBuilder, parentContext: null, parentId: null);
  }

  int _createNextMainWindowAfterRestart(Widget Function(BuildContext) homeBuilder) {
    final opts = config.globalOptions;

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = calcWindowPosition(windowSize, opts.alignment!);
    }
    int? newViewId;
    try {
      newViewId = _ffiBridge.createWindowRequest(
        token: 0000,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
      );
    } catch (e, st) {
      throw Exception('Failed to create new window, tokenId: 0000. Error: $e, stack: $st');
    }

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      if (error == _CreateViewError.forceClose) {
        // do nothing
      }
      throw Exception(error.message(0000));
    }

    return newViewId;
  }

  void _applyOptionsToInitialAnchor() {
    if (realAnchorId == null) return;
    applyOptions(realAnchorId!, opts: config.globalOptions);
    _ffiBridge.show(realAnchorId!);
  }

  void _updateHotRestartShiftBySecondary(int viewId) {
    if (viewId == 2) {
      _isInitFirstSecondaryView = true;
    }
    if (allShiftedWindowIds.length == 1 && allShiftedWindowIds.first == 1 && viewId > 2 && !_isInitFirstSecondaryView) {
      _hotRestartShift = viewId - allShiftedWindowIds.first - 1;

      _isInitFirstSecondaryView = true;
    }
  }

  void registerWindow(
    int viewId,
    Widget Function(BuildContext) widgetBuilder, {
    required BuildContext? parentContext,
    int? parentId,
    ViewShellOverrides? shellOverrides,
  }) {
    if (parentId != null && !_windows.containsKey(parentId)) {
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addWindow(
      viewId,
      _WindowEntry(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        parentId: parentId,
        initialShellOverrides: shellOverrides,
      ),
    );
    _notifyObservers(
      (o) => o.onWindowOpened(_realToShifted(viewId), parentViewId: parentId != null ? _realToShifted(parentId) : null),
    );
    if (_realAnchorId == null) {
      _setAnchor(viewId);
    }
  }

  void registerDialog<T>(
    int viewId,
    Widget Function(BuildContext) widgetBuilder, {
    required BuildContext? parentContext,
    required int parentId,
    required bool isModal,
    required Completer<T?> closeCompleter,
    ViewShellOverrides? shellOverrides,
  }) {
    if (!_windows.containsKey(parentId)) {
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addDialog(
      viewId,
      _DialogEntry<T>(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        initialShellOverrides: shellOverrides,
        parentId: parentId,
        isModal: isModal,
        closeCompleter: closeCompleter,
      ),
    );

    _notifyObservers((o) => o.onDialogOpened(_realToShifted(viewId), parentViewId: _realToShifted(parentId)));
  }

  void _notifyObservers(void Function(WindowObserver) action) {
    for (final observer in _observers) {
      action(observer);
    }
  }

  void _setAnchor(int? viewId, {bool force = false}) {
    if (!config.generalParams.enableDynamicAnchor && !force) return;
    final previousShifted = _realAnchorId != null ? _realToShifted(_realAnchorId!) : null;
    _realAnchorId = viewId;
    final newShifted = viewId != null ? _realToShifted(viewId) : null;
    if (previousShifted != newShifted) {
      _notifyObservers((o) => o.onAnchorChanged(previousShifted, newShifted));
    }
    if (viewId == null) return;
    _ffiBridge.setAnchorViewId(viewId);
  }

  /// When the anchor `FlutterView` disappears, pick another root window.
  void reconcileAnchor(PlatformDispatcher dispatcher) {
    final anchor = _realAnchorId;
    if (anchor == null) return;
    if (dispatcher.view(id: anchor) != null) return;
    _setAnchor(_realAnchorId);
    _promoteAnchor();
  }

  List<int> _anchorCandidates({int? excludingViewId}) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates =
        _windows.entries
            .where((e) => e.value.parentId == null && e.key != excludingViewId)
            .map((e) => e.key)
            .where((id) => dispatcher.view(id: id) != null)
            .toList()
          ..sort();
    return candidates;
  }

  /// Picks another root window as anchor (lowest live view id), optionally skipping `excludingViewId`.
  void _promoteAnchor({int? excludingViewId}) {
    final candidates = _anchorCandidates(excludingViewId: excludingViewId);
    if (candidates.isEmpty) {
      _setAnchor(null);
      return;
    }
    _setAnchor(candidates.first);
  }

  int _realToShifted(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == _initRealId) {
      return 1;
    }

    return viewId - _hotRestartShift;
  }

  int _shiftedToReal(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == 1) {
      return _initRealId;
    }

    return viewId + _hotRestartShift;
  }

  List<int> _directChildIds(int parentId) =>
      _windows.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  /// Direct children of `parentId` that are dialogs (`_WindowEntry.isDialog`).
  List<int> _directDialogChildIds(int parentId) =>
      _dialogs.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  List<int> _descendantIdsDeepestFirst(int rootId) {
    final result = <int>[];
    void walk(int id) {
      for (final child in _directChildIds(id)) {
        walk(child);
        result.add(child);
      }
    }

    walk(rootId);
    return result;
  }

  List<int> _rootWindowIds({int? excludingId}) =>
      _windows.entries.where((e) => e.value.parentId == null && e.key != excludingId).map((e) => e.key).toList();

  dynamic _onStaticCall(MethodCall call) {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;

    if (eventName == 'popup-closed') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        _unregisterPopup(viewId);
      }
    } else if (eventName == 'viewCreated') {
      final int viewId = call.arguments['viewId'] as int;
      final int token = call.arguments['token'] as int;
      final maybeParentId = _childCreatePending[token];
      _createComplete(token, viewId);
      if (maybeParentId == null) return;
      _childCreatePending.remove(token);
      _ffiBridge.setPreConfirmClose(maybeParentId, false);
    } else if (eventName == 'taskbar-callback') {
      config.macosParams.onTaskbarTap?.call();
    } else if (eventName == 'preconfirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        // debugPrint('preconfirm: $viewId');
        unawaited(_handlePreConfirmClose(viewId));
      }
    } else if (eventName == 'confirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        // debugPrint('confirm: $viewId');
        _onConfirmClose(viewId);
      }
    } else if (eventName == 'applicationShouldTerminateRequest') {
      unawaited(_macosOnShouldAppTerminate());
    } else if (eventName == 'taskbarMenuItemSelected') {
      final id = call.arguments['id'] as int?;
      if (id != null) {
        _invokeTaskbarMenuCallback(id);
      }
    } else {
      final int? viewId = call.arguments['viewId'] as int?;

      if (viewId != null) {
        _dispatchViewEvent(viewId, eventName);
      }
    }

    return null;
  }

  Future<void> _macosOnShouldAppTerminate() async {
    final confirmTerminate = await config.macosParams.onTerminate?.call() ?? true;
    if (confirmTerminate) {
      _ffiBridge.closeIsolateLocal();
    }
    _ffiBridge.replyToApplicationShouldTerminate(confirmTerminate);
  }

  void _onConfirmClose(int viewId) {
    final isDialog = _dialogs.containsKey(viewId);
    final isModalDialog = isDialog && (_dialogs[viewId]?.isModal ?? false);
    _destroyPopupsByParent(viewId);
    _removeAllDialogsByParent(viewId);

    _disposeView(viewId);

    _ffiBridge.setConfirmClose(viewId, isConfirm: true);
    if (isModalDialog) {
      _ffiBridge.destroyModalDialog(viewId);
    } else {
      _ffiBridge.forceCloseView(viewId);
    }
    cascadeCloseService.completeWindow(viewId);
  }

  /// Runs before `isPreventClose` / `isConfirmClose`; subtree closes per `closeMode`.
  Future<void> _handlePreConfirmClose(int viewId) async {
    final nextAnchorCandidates = _anchorCandidates(excludingViewId: viewId)..sort();
    // debugPrint('nextAnchorCandidates: $nextAnchorCandidates');
    if (viewId == _realAnchorId && nextAnchorCandidates.isNotEmpty && !config.generalParams.enableDynamicAnchor) {
      for (final candidate in nextAnchorCandidates.reversed) {
        cascadeCloseService.abort(candidate);
        cascadeCloseService.attachWindow(candidate);
        await _closeSubtreeByMode(candidate, closeMode);
        final closed = await cascadeCloseService.waitWindow(candidate);
        if (!closed) {
          return;
        }
      }
    }
    // debugPrint('close $viewId subtree');

    await _closeSubtreeByMode(viewId, closeMode);
  }

  Future<void> _closeSubtreeByMode(int rootId, CloseMode mode) async {
    if (_hasPendingCreatingViews()) {
      await _waitAllCreatingViews();
    }

    switch (mode) {
      case CloseMode.none:
        _removeViewsNone(rootId);
        break;
      case CloseMode.softCascade:
        await _removeViewsCascade(rootId);
        break;
      case CloseMode.forceSecondary:
        await _removeSecondaryViewsForce(rootId);
        break;
      case CloseMode.destroy:
        await _destroyAllViewsForce(rootId);
        break;
    }
  }

  /// Aborts the cascade close that is waiting on `viewId`.
  ///
  /// Completing the completer with `false` causes the cascade loop to `return`
  /// early, leaving the main window open. All other pending completers are
  /// also cleared so that a later independent close of those windows does not
  /// unexpectedly resume the (already aborted) cascade.
  void _cancelCascade(int viewId) {
    final parentsRecurs = [..._parentsId(viewId), ..._dialogParentIds(viewId), viewId];
    for (final parent in parentsRecurs) {
      _ffiBridge.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  int? _directParentId(int childId) {
    final entry = _windows[childId];
    return entry?.parentId;
  }

  List<int> _parentsId(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = _directParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  int? _directDialogParentId(int childId) {
    final entry = _dialogs[childId];
    return entry?.parentId;
  }

  List<int> _dialogParentIds(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = _directDialogParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  // --------------------------------------------------------------------------
  // Per-view event dispatch
  // --------------------------------------------------------------------------

  void _dispatchViewEvent(int viewId, String eventName) {
    if (_windows.keys.contains(viewId)) {
      _notifyObservers((o) => o.onWindowEvent(_realToShifted(viewId), eventName));
    }
    if (_dialogs.keys.contains(viewId)) {
      _notifyObservers((o) => o.onDialogEvent(_realToShifted(viewId), eventName));
    }
    final list = _listeners[viewId];
    if (list == null) return;
    for (final l in List<WindowListenerCallbacks>.from(list)) {
      l.onWindowEvent(eventName);
      _dispatchListenerEvent(l, eventName, viewId);
    }
  }

  void _dispatchListenerEvent(WindowListenerCallbacks listener, String eventName, int viewId) {
    switch (eventName) {
      case 'focus':
        listener.onWindowFocus();
      case 'blur':
        listener.onWindowBlur();
      case 'maximize':
        listener.onWindowMaximize();
      case 'unmaximize':
        listener.onWindowUnmaximize();
      case 'minimize':
        listener.onWindowMinimize();
      case 'restore':
        listener.onWindowRestore();
      case 'resize':
        listener.onWindowResize();
      case 'resized':
        listener.onWindowResized();
      case 'move':
        listener.onWindowMove();
      case 'moved':
        listener.onWindowMoved();
      case 'enter-full-screen':
        listener.onWindowEnterFullScreen();
      case 'leave-full-screen':
        listener.onWindowLeaveFullScreen();
      case 'close':
        _handleOnWindowClose(listener.onWindowClose(), viewId);
    }
  }

  void _handleOnWindowClose(FutureOr<bool> futureOr, int viewId) async {
    final res = await futureOr;
    if (!res) {
      _cancelCascade(viewId);
    }
  }

  bool _isLastMacosRootView(int id) =>
      ((_anchorCandidates(excludingViewId: id).isEmpty) && _saveLastWindowToReopen && _realAnchorId == id);

  void _preConfirmCloseCallable(int viewId, {bool isForce = false}) {
    _ffiBridge.setPreConfirmClose(viewId, true);

    if (isForce) {
      _saveLastWindowToReopen = false;
      applyNativeLifecyclePolicy();
      _ffiBridge.forceCloseView(viewId);
    } else {
      if (Platform.isMacOS) {
        // Hide the anchor instead of closing it when macOS dock restore is enabled and taskbar callback is null.
        if (_isLastMacosRootView(viewId)) {
          _destroyPopupsByParent(viewId);
          _removeAllDialogsByParent(viewId);
          _ffiBridge.hide(viewId);
          _ffiBridge.setPreConfirmClose(viewId, false);
          cascadeCloseService.completeWindow(viewId);
          return;
        }
      }
      _ffiBridge.softCloseWindow(viewId);
    }
  }

  bool _removeAllDialogsByParent(int parentId) {
    final allDialogs = _directDialogChildIds(parentId)..sort();
    for (final dialogId in allDialogs.reversed) {
      _ffiBridge.destroyModalDialog(dialogId);

      _disposeView(dialogId);
    }
    return true;
  }

  void _removeViewsNone(int rootId) {
    _preConfirmCloseCallable(rootId);
  }

  Future<void> _removeViewsCascade(int rootId) async {
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();

    // debugPrint('cascade for $rootId');
    for (final id in descendants.reversed) {
      final wait = _viewExistChecker<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        _ffiBridge.softCloseWindow(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
    if (descendantsAfter.isNotEmpty) {
      // do nothing because softClose cycle
      return;
    }

    _viewExistChecker(rootId, () => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _removeSecondaryViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final wait = _viewExistChecker<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        _ffiBridge.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    if (loopCycle < maxLoopCycles) {
      final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
      if (descendantsAfter.isNotEmpty) {
        // repeat cycle because forceClose cycle
        unawaited(_removeSecondaryViewsForce(rootId, loopCycle: loopCycle + 1));
        return;
      }
    }
    _viewExistChecker(rootId, () => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _destroyAllViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final wait = _viewExistChecker<Future<bool>>(id, () {
        cascadeCloseService.attachWindow(id);
        _ffiBridge.forceCloseView(id);
        return cascadeCloseService.waitWindow(id);
      });
      final closed = wait == null ? false : await wait;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    if (loopCycle < maxLoopCycles) {
      final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
      if (descendantsAfter.isNotEmpty) {
        // repeat cycle because forceClose cycle
        unawaited(_destroyAllViewsForce(rootId, loopCycle: loopCycle + 1));
        return;
      }
    }

    _viewExistChecker(rootId, () => _preConfirmCloseCallable(rootId, isForce: true), dialogSupports: true);
  }

  Future<void> removeOrphanViewsForceAfterRestart(List<int> ids) async {
    cascadeCloseService.clear();
    for (final id in ids) {
      try {
        _ffiBridge.forceCloseView(id);
        _ffiBridge.destroyModalDialog(id);
      } catch (_) {}
    }
  }

  void applyOptions(int viewId, {required WindowOptions opts}) => _applyOptions(viewId, opts);

  void _applyOptions(int viewId, WindowOptions opts) {
    if (opts.size != null) {
      _ffiBridge.setSize(viewId, size: opts.size!);
    }
    if (opts.alignment != null) {
      _ffiBridge.setAlignment(viewId, alignment: opts.alignment!);
    }
    if (opts.backgroundColor != null) {
      _ffiBridge.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.minimumSize != null) {
      _ffiBridge.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      _ffiBridge.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.title != null) _ffiBridge.setTitle(viewId, title: opts.title!);
    if (opts.titleBarStyle != null) {
      _ffiBridge.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility!,
        maximizeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: opts.windowButtonVisibility!,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffiBridge.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
    if (opts.fullScreen != null) {
      _ffiBridge.setFullScreen(viewId, isFullScreen: opts.fullScreen!);
    }
    if (opts.hideAppFromTaskbar ?? false) {
      hideAppFromTaskbar(true);
    }
  }

  void _applyDialogOptions(int viewId, DialogOptions opts) {
    if (!Platform.isWindows) {
      if (opts.size != null) {
        _ffiBridge.setSize(viewId, size: opts.size!);
      }
    }
    if (opts.backgroundColor != null) {
      _ffiBridge.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.showOnInit == true || opts.showOnInit == null) {
      _ffiBridge.show(viewId);
    }
    if (opts.minimumSize != null) {
      _ffiBridge.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      _ffiBridge.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.isResizable != null) {
      _ffiBridge.setResizable(viewId, opts.isResizable!);
    }
    if (opts.title != null) _ffiBridge.setTitle(viewId, title: opts.title!);
    if (opts.titleBarStyle != null) {
      _ffiBridge.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: false,
        maximizeVisibility: false,
      );
    }
    if (opts.alwaysOnTop != null) {
      _ffiBridge.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
  }

  void _addWindow(int viewId, _WindowEntry entry) {
    _windows[viewId] = entry;
    _windowsNotifier.value = _windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _addDialog<T>(int dialogId, _DialogEntry<T> entry) {
    _dialogs[dialogId] = entry;
    _dialogsNotifier.value = _dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeWindow(int viewId) {
    _windows.remove(viewId)?.disposeEntryResources();
    _windowsNotifier.value = _windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeDialog(int dialogId) {
    final dialog = _dialogs[dialogId];
    if (dialog == null) return;
    dialog.completeResult(_dialogsResults.remove(dialogId));
    dialog.disposeEntryResources();
    _dialogs.remove(dialogId);
    _dialogsNotifier.value = _dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  _ViewEntry? _viewEntryFor(int viewId) => _windows[viewId] ?? _dialogs[viewId];

  @override
  void patchViewShell(int viewId, ViewShellOverrides overrides) {
    final entry = _viewEntryFor(viewId);
    if (entry == null) return;
    final notifier = entry.viewShellOverrides;
    notifier.value = ViewShellOverrides.merge(notifier.value, overrides);
  }

  @override
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides) {
    _viewEntryFor(viewId)?.viewShellOverrides.value = overrides;
  }

  @override
  ViewShellOverrides? getViewShellOverrides(int viewId) => _viewEntryFor(viewId)?.viewShellOverrides.value;

  void _disposeView(int viewId) {
    final entry = [..._windows.entries, ..._dialogs.entries].where((e) => e.key == viewId).firstOrNull;
    final shiftedViewId = _realToShifted(viewId);
    final isDialog = entry?.value is _DialogEntry;

    if (isDialog) {
      if (_dialogs.keys.contains(viewId)) {
        _notifyObservers((o) => o.onDialogClose(shiftedViewId));
      }
    } else {
      if (_windows.keys.contains(viewId)) {
        _notifyObservers((o) => o.onWindowClosed(shiftedViewId));
      }
    }
    // If this dialog had a modal flag, unblock its parent window.
    if (isDialog) {
      _modalStateService.unregisterDialog((entry?.value as _DialogEntry).parentId, realDialogId: viewId);
    }
    _destroyPopupsByParent(viewId);
    // Clean up the modal notifier for this view (it may have been a parent itself).
    _modalStateService.disposeView(viewId);
    _dialogModalPublicNotifiers.remove(viewId)?.dispose();

    final wasAnchor = viewId == _realAnchorId;
    if (wasAnchor && !isDialog) {
      _setAnchor(null);
    }
    _listeners.remove(viewId);
    if (isDialog) {
      _removeDialog(viewId);
    } else {
      _removeWindow(viewId);
    }
    communicator.disposeViewByShiftedId(shiftedViewId);
    if (wasAnchor && !isDialog) {
      _promoteAnchor();
    }
  }

  @override
  int createWindow({WindowOptions? newOpts, required void Function(int) onCreated, int? parent}) {
    if (parent != null && !_windows.containsKey(parent)) {
      throw ArgumentError.value(parent, 'Parent error', 'Parent window is not registered');
    }

    final comparedOpts = _compareGlobalAndNewOpts(preferred: newOpts, global: config.globalOptions);

    return _createWindow(opts: comparedOpts, parentId: parent, onCreated: onCreated);
  }

  @override
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required void Function(int) onCreated,
  }) async {
    if (!_windows.containsKey(parentRealId)) {
      throw ArgumentError.value(parentRealId, 'Parent error', 'Parent window is not registered');
    }

    if (_createCompleters.values.any((e) => !e.completer.isCompleted && e.isDialog && e.parentId == parentRealId)) {
      throw Exception('Create error: "Create dialog" was called while another dialog is creating in the same window');
    }

    final comparedOpts = _compareDialogGlobalAndNewOpts(preferred: newOpts, global: config.globalDialogOptions);
    if (comparedOpts.modal == true) {
      final hasModal = _modalStateService.getNotifier(parentRealId).value.firstWhereOrNull((e) => e.isModal) != null;
      if (hasModal) {
        throw Exception('Create error: One window can has only one modal dialog');
      }
    }
    final dialogId = await _createDialog(opts: comparedOpts, parentId: parentRealId, onCreated: onCreated);

    return dialogId;
  }

  @override
  int createPopup({required int parentRealId, required Size size}) {
    if (!_windows.containsKey(parentRealId) && !_dialogs.containsKey(parentRealId)) {
      throw ArgumentError.value(parentRealId, 'Parent error', 'Parent window is not registered');
    }

    int? newViewId;
    try {
      newViewId = _ffiBridge.createPopupWindow(token: 0000, parentId: parentRealId, windowSize: size);
    } catch (e, st) {
      throw Exception('Failed to create popup window, tokenId: 0000. Error: $e, stack: $st');
    }

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      throw Exception(error.message(0000));
    }

    _popups[newViewId] = _PopupEntry(parentId: parentRealId);
    _ffiBridge.setPreConfirmClose(newViewId, true);
    _ffiBridge.setPreventClose(newViewId, isPreventClose: false);
    _ffiBridge.setConfirmClose(newViewId, isConfirm: true);
    // will be shown after positioned
    // _ffiBridge.show(newViewId);
    return newViewId;
  }

  @override
  void destroyPopup(int viewId) {
    if (!_popups.containsKey(viewId)) return;
    try {
      _ffiBridge.destroyModalDialog(viewId);
    } on PlatformException catch (e) {
      if (e.code != 'NO_WINDOW') rethrow;
    }
    _unregisterPopup(viewId);
  }

  @override
  bool positionPopup(int viewId, Rect bounds) {
    if (!_popups.containsKey(viewId) || !_hasLiveFlutterView(viewId)) return false;
    try {
      return _ffiBridge.setPopupBounds(viewId, bounds: bounds);
    } on PlatformException catch (e) {
      if (e.code != 'NO_WINDOW') rethrow;
    }
    return false;
  }

  void _unregisterPopup(int viewId) {
    _popups.remove(viewId);
  }

  List<int> _directPopupChildIds(int parentId) =>
      _popups.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  void _destroyPopupsByParent(int parentId) {
    final ids = _directPopupChildIds(parentId);
    for (final id in ids) {
      destroyPopup(id);
    }
  }

  Future<void> _createComplete(int token, int newViewId) async {
    _createCompleters[token]?.complete(newViewId);
    _ffiBridge.setPreConfirmClose(newViewId, false);
  }

  bool _hasPendingCreatingViews({List<int> excludeTokens = const []}) {
    return _createCompleters.entries.any((e) => !excludeTokens.contains(e.key) && !e.value.isCompleted);
  }

  /// `excludeTokens` - current view tokens, so don't wait yourself
  Future<void> _waitAllCreatingViews({List<int> excludeTokens = const []}) async {
    if (!_hasPendingCreatingViews(excludeTokens: excludeTokens)) return;
    try {
      for (final key in _createCompleters.keys.toList()..sort()) {
        if (excludeTokens.contains(key)) continue;

        final completer = _createCompleters[key];
        if (!(completer?.isCompleted ?? true)) {
          await completer?.future;
        }
      }
    } catch (_) {
      // error in _createCompleters map is non-critical, do nothing
    }
  }

  Future<int?> _waitCompleter(int token, {int timeoutMs = 10000}) async {
    return await _createCompleters[token]?.future.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () {
        _createCompleters[token]?.complete(_CreateViewError.timeout.code);
        return _CreateViewError.timeout.code;
      },
    );
  }

  int _createWindow({required WindowOptions opts, int? parentId, required void Function(int) onCreated}) {
    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = calcWindowPosition(windowSize, opts.alignment!);
    }
    int? newViewId;
    try {
      newViewId = _ffiBridge.createWindowRequest(
        token: 0000,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
        parentId: parentId,
      );
      if (parentId != null) {
        _ffiBridge.setPreConfirmClose(parentId, false);
      }
    } catch (e, st) {
      throw Exception('Failed to create new window, tokenId: 0000. Error: $e, stack: $st');
    }

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      throw Exception(error.message(0000));
    }

    _applyOptions(newViewId, opts);

    onCreated(newViewId);

    return newViewId;
  }

  WindowOptions _compareGlobalAndNewOpts({WindowOptions? preferred, required WindowOptions global}) {
    if (preferred == null) return global;
    return WindowOptions(
      size: preferred.size ?? global.size,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      alignment: preferred.alignment ?? global.alignment,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
      hideAppFromTaskbar: preferred.hideAppFromTaskbar ?? global.hideAppFromTaskbar,
      titleBarStyle: preferred.titleBarStyle ?? global.titleBarStyle,
      windowButtonVisibility: preferred.windowButtonVisibility ?? global.windowButtonVisibility,
      title: preferred.title ?? global.title,
      fullScreen: preferred.fullScreen ?? global.fullScreen,
      alwaysOnTop: preferred.alwaysOnTop ?? global.alwaysOnTop,
    );
  }

  DialogOptions _compareDialogGlobalAndNewOpts({DialogOptions? preferred, required DialogOptions global}) {
    if (preferred == null) return global;
    return DialogOptions(
      size: preferred.size ?? global.size,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      isResizable: preferred.isResizable ?? global.isResizable,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
      titleBarStyle: preferred.titleBarStyle ?? global.titleBarStyle,
      modal: preferred.modal ?? global.modal,
      windowButtonVisibility: preferred.windowButtonVisibility ?? global.windowButtonVisibility,
      title: preferred.title ?? global.title,
      alwaysOnTop: preferred.alwaysOnTop ?? global.alwaysOnTop,
      showOnInit: preferred.showOnInit ?? global.showOnInit,
    );
  }

  /// Creates a native dialog and waits for the `viewCreated` event.
  ///
  /// Modal dialogs block the parent at the OS level (macOS sheet, Windows owner
  /// chain, Linux transient + input lock). Modeless dialogs are positioned over
  /// the parent and do not block it natively.
  Future<int> _createDialog({
    required DialogOptions opts,
    required int parentId,
    required void Function(int) onCreated,
  }) async {
    final int token = _nextToken++;
    _createCompleters[token] = _CreateCompleter.dialog(token, parentId: parentId);
    final int modalFinishedToken = _nextToken++;
    _createCompleters[modalFinishedToken] = _CreateCompleter.dialog(token, parentId: parentId);

    // wait all other creating views
    await _waitAllCreatingViews(excludeTokens: [token, modalFinishedToken]);

    _childCreatePending.putIfAbsent(token, () => parentId);

    final windowSize = Size(opts.size?.width ?? 400.0, opts.size?.height ?? 300.0);

    try {
      final modal = opts.modal ?? false;
      Offset? pos;
      if (!modal) {
        final parentBounds = _ffiBridge.getBounds(parentId);
        pos = calcWindowPositionByParent(Alignment.center, windowSize: windowSize, parentBounds: parentBounds);
        // Native sheet - positioned by the OS; no Dart-side alignment needed.
      }
      _ffiBridge.createModalDialogRequest(
        token: token,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        isModal: modal,
        pos: pos,
        parentId: parentId,
      );
    } catch (e, st) {
      _createCompleters[modalFinishedToken]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(modalFinishedToken);

      _createCompleters[token]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(token);
      throw Exception('Failed to create dialog window, tokenId: $token. Error: $e, stack: $st');
    }

    final newViewId = await _waitCompleter(token);

    _createCompleters.remove(token);
    _childCreatePending.remove(token);

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      throw Exception(error.message(token));
    }

    _modalStateService.registerDialog(parentId, dialogId: newViewId!, isModal: opts.modal ?? false);

    _applyDialogOptions(newViewId, opts);

    onCreated(newViewId);

    if (opts.modal == true) {
      // delay so modal shows correct
      await Future.delayed(Duration(milliseconds: 35));
    }
    _createCompleters[modalFinishedToken]?.complete();
    _createCompleters.remove(modalFinishedToken);
    return newViewId;
  }

  @override
  void addListener(int viewId, WindowListenerCallbacks listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListenerCallbacks>()).add(listener);
  }

  @override
  void removeListener(int viewId, WindowListenerCallbacks listener) {
    _listeners[viewId]?.remove(listener);
  }

  @override
  bool get isEnabledDynamicAnchor => config.generalParams.enableDynamicAnchor;

  @override
  void setTaskbarMenu({required List<TaskbarMenuItem> items}) {
    _taskbarMenuCallbacks = [for (final item in items) item.onPressed];
    unawaited(_encodeAndSetTaskbarMenu(items));
  }

  Future<void> _encodeAndSetTaskbarMenu(List<TaskbarMenuItem> items) async {
    final encoded = <Map<String, dynamic>>[for (var i = 0; i < items.length; i++) await items[i].toJson(i)];
    _ffiBridge.setTaskbarMenu(encoded);
  }

  void _invokeTaskbarMenuCallback(int id) {
    if (id < 0 || id >= _taskbarMenuCallbacks.length) return;
    _taskbarMenuCallbacks[id]?.call();
  }

  @override
  bool setPublicAnchorId(int viewId) {
    if (config.generalParams.enableDynamicAnchor) return false;

    final realView = _shiftedToReal(viewId);
    if (_anchorCandidates().contains(realView)) {
      _setAnchor(realView, force: true);
      return true;
    }

    return false;
  }

  @override
  int? getPublicAnchorId() {
    if (_realAnchorId == null) return null;

    return _realToShifted(_realAnchorId!);
  }

  @override
  void blur(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.blur(viewId), dialogSupports: true);
  }

  @override
  void cancelCascadeClose(int viewId) {
    _cancelCascade(viewId);
  }

  @override
  void center(int viewId) {
    setAlignment(viewId, Alignment.center);
  }

  @override
  WindowInfo windowType(int viewId) {
    final dialog = _dialogs[viewId];
    return (isDialog: dialog != null, isModal: dialog?.isModal ?? false);
  }

  @override
  void closeView<T>(int viewId, {T? dialogRes}) {
    if (_dialogs.containsKey(viewId)) {
      _dialogsResults[viewId] = dialogRes;
      _viewExistChecker(viewId, () => _ffiBridge.destroyModalDialog(viewId), dialogSupports: true);
      _disposeView(viewId);
    } else {
      _viewExistChecker(viewId, () => _ffiBridge.softCloseWindow(viewId));
    }
  }

  @override
  void focus(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.focus(viewId), dialogSupports: true);
  }

  @override
  Rect getBounds(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.getBounds(viewId), dialogSupports: true) ?? Rect.zero;
  }

  @override
  double getOpacity(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.getOpacity(viewId), dialogSupports: true) ?? 1;
  }

  @override
  Offset getPosition(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.getPosition(viewId), dialogSupports: true) ?? Offset.zero;
  }

  @override
  Size getSize(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.getSize(viewId), dialogSupports: true) ?? Size.zero;
  }

  @override
  String getTitle(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.getTitle(viewId), dialogSupports: true) ?? '';
  }

  @override
  ({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility}) getTitleBarStyle(
    int viewId,
  ) {
    return _viewExistChecker(viewId, () => _ffiBridge.getTitleBarStyle(viewId), dialogSupports: true) ??
        (style: TitleBarStyle.normal, closeVisibility: true, maximizeVisibility: true, minimizeVisibility: true);
  }

  @override
  bool hasShadow(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.hasShadow(viewId), dialogSupports: true) ?? true;
  }

  @override
  void hide(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.hide(viewId), dialogSupports: true);
  }

  @override
  void hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId}) {
    if (Platform.isMacOS) {
      final id = _lifecycleViewId;
      if (id == null) return;
      _viewExistChecker(
        id,
        () => _ffiBridge.hideAppFromTaskbar(id, isHideAppFromTaskbar: isHideAppFromTaskbar),
        dialogSupports: true,
      );
    } else {
      if (viewId == null) {
        for (final view in windowEntries) {
          _viewExistChecker(
            view.key,
            () => _ffiBridge.hideAppFromTaskbar(view.key, isHideAppFromTaskbar: isHideAppFromTaskbar),
            dialogSupports: true,
          );
        }
        return;
      }
      _viewExistChecker(
        viewId,
        () => _ffiBridge.hideAppFromTaskbar(viewId, isHideAppFromTaskbar: isHideAppFromTaskbar),
        dialogSupports: true,
      );
    }
  }

  @override
  void hideFromCollection(int viewId, bool isHideFromCollection) {
    if (!Platform.isMacOS) return;
    _viewExistChecker(viewId, () => _ffiBridge.hideFromCollection(viewId, isHideFromCollection), dialogSupports: true);
  }

  @override
  bool isAlwaysOnTop(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isAlwaysOnTop(viewId), dialogSupports: true) ?? false;
  }

  @override
  bool isClosable(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isClosable(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isFocused(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isFocused(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isOnActiveSpace(int viewId) {
    if (!Platform.isMacOS) return true;
    return _viewExistChecker(viewId, () => _ffiBridge.isOnActiveSpace(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isFullScreen(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isFullScreen(viewId)) ?? false;
  }

  @override
  bool isHideAppFromTaskbar() {
    if (Platform.isWindows || Platform.isLinux) {
      return _ffiBridge.isHideAppFromTaskbar();
    }
    final id = _lifecycleViewId;
    if (id == null) return false;
    return _viewExistChecker(id, () => _ffiBridge.isHideAppFromTaskbar(), dialogSupports: true) ?? false;
  }

  @override
  bool isHideAppTabFromTaskbar(int viewId) {
    if (!Platform.isWindows) {
      return isHideAppFromTaskbar();
    }
    return _viewExistChecker(viewId, () => _ffiBridge.isHideAppTabFromTaskbar(viewId), dialogSupports: true) ?? false;
  }

  @override
  bool isHideFromCollection(int viewId) {
    if (!Platform.isMacOS) return false;
    return _viewExistChecker(viewId, () => _ffiBridge.isHideFromCollection(viewId), dialogSupports: true) ?? false;
  }

  @override
  bool isMaximizable(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isMaximizable(viewId)) ?? true;
  }

  @override
  bool isMaximized(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isMaximized(viewId)) ?? false;
  }

  @override
  bool isMinimizable(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isMinimizable(viewId)) ?? true;
  }

  @override
  bool isMinimized(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isMinimized(viewId)) ?? false;
  }

  @override
  bool isMovable(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isMovable(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isPreventClose(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isPreventClose(viewId)) ?? false;
  }

  @override
  bool isResizable(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isResizable(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isVisible(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isVisible(viewId), dialogSupports: true) ?? true;
  }

  @override
  bool isVisibleOnAllWorkspaces(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isVisibleOnAllWorkspaces(viewId), dialogSupports: true) ?? true;
  }

  @override
  void maximize(int viewId, {bool vertically = false}) {
    _viewExistChecker(viewId, () => _ffiBridge.maximize(viewId));
  }

  @override
  void minimize(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.minimize(viewId));
  }

  @override
  void popUpWindowMenu(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.popUpWindowMenu(viewId), dialogSupports: true);
  }

  @override
  void restore(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.restore(viewId));
  }

  @override
  void setAlignment(int viewId, Alignment alignment, {bool insideParent = false}) {
    final dialog = _dialogs[viewId];
    if (dialog != null && insideParent) {
      final parentBounds = _ffiBridge.getBounds(dialog.parentId);
      final windowSize = _ffiBridge.getSize(viewId);
      final pos = calcWindowPositionByParent(alignment, windowSize: windowSize, parentBounds: parentBounds);
      _viewExistChecker(viewId, () => _ffiBridge.setPosition(viewId, pos: pos), dialogSupports: true);
      return;
    }
    _viewExistChecker(
      viewId,
      () => _ffiBridge.setAlignment(viewId, alignment: alignment),
      dialogSupports: !(dialog?.isModal ?? false),
    );
  }

  @override
  void setAlwaysOnTop(int viewId, bool isAlwaysOnTop) {
    _viewExistChecker(
      viewId,
      () => _ffiBridge.setAlwaysOnTop(viewId, isAlwaysOnTop: isAlwaysOnTop),
      dialogSupports: true,
    );
  }

  @override
  void setAsFrameless(int viewId) {
    _viewExistChecker(
      viewId,
      () => _ffiBridge.setAsFrameless(viewId),
      dialogSupports: !(_dialogs[viewId]?.isModal ?? true),
    );
  }

  @override
  void setAspectRatio(int viewId, double ratio) {
    _viewExistChecker(viewId, () => _ffiBridge.setAspectRatio(viewId, ratio));
  }

  @override
  void setBackgroundColor(int viewId, Color color) {
    _viewExistChecker(viewId, () => _ffiBridge.setBackgroundColor(viewId, color: color), dialogSupports: true);
  }

  @override
  void setBadgeLabel(int viewId, String? label) {
    if (!Platform.isMacOS) return;
    _viewExistChecker(viewId, () => _ffiBridge.setBadgeLabel(viewId, label: label), dialogSupports: true);
  }

  @override
  void setBrightness(int viewId, Brightness brightness) {
    _viewExistChecker(viewId, () => _ffiBridge.setBrightness(viewId, brightness), dialogSupports: true);
  }

  @override
  void setGlobalBrightness(Brightness brightness) {
    final allViewIds = [..._dialogs.keys, ..._windows.keys]..sort();
    for (final viewId in allViewIds) {
      _viewExistChecker(viewId, () => _ffiBridge.setBrightness(viewId, brightness), dialogSupports: true);
    }
  }

  @override
  void setClosable(int viewId, bool isClosable) {
    _viewExistChecker(viewId, () => _ffiBridge.setClosable(viewId, isClosable), dialogSupports: true);
  }

  @override
  CloseMode getAppCloseMode() => closeMode;

  @override
  void setAppCloseMode(CloseMode closeMode) {
    this.closeMode = closeMode;
    applyNativeLifecyclePolicy();
  }

  @override
  void setFullScreen(int viewId, bool isFullScreen) {
    _viewExistChecker(viewId, () => _ffiBridge.setFullScreen(viewId, isFullScreen: isFullScreen));
  }

  @override
  void setHasShadow(int viewId, bool value) {
    _viewExistChecker(viewId, () => _ffiBridge.setHasShadow(viewId, value), dialogSupports: true);
  }

  @override
  void setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) {
    _viewExistChecker(
      viewId,
      () => _ffiBridge.setIgnoreMouseEvents(viewId, ignore, forward: forward),
      dialogSupports: true,
    );
  }

  @override
  ({bool mouseMoveEvents, bool ignore}) isIgnoreMouseEvents(int viewId) {
    return _viewExistChecker(viewId, () => _ffiBridge.isIgnoreMouseEvents(viewId), dialogSupports: true) ??
        (mouseMoveEvents: false, ignore: false);
  }

  @override
  void setMaximizable(int viewId, bool isMaximizable) {
    _viewExistChecker(viewId, () => _ffiBridge.setMaximizable(viewId, isMaximizable));
  }

  @override
  void setMaximumSize(int viewId, Size size) {
    _viewExistChecker(viewId, () => _ffiBridge.setMaxSize(viewId, size: size), dialogSupports: true);
  }

  @override
  void setMinimizable(int viewId, bool isMinimizable) {
    _viewExistChecker(viewId, () => _ffiBridge.setMinimizable(viewId, isMinimizable));
  }

  @override
  void setMinimumSize(int viewId, Size size) {
    _viewExistChecker(viewId, () => _ffiBridge.setMinSize(viewId, size: size), dialogSupports: true);
  }

  @override
  void setMovable(int viewId, bool isMovable) {
    _viewExistChecker(viewId, () => _ffiBridge.setMovable(viewId, isMovable), dialogSupports: true);
  }

  @override
  void setOpacity(int viewId, double opacity) {
    _viewExistChecker(viewId, () => _ffiBridge.setOpacity(viewId, opacity), dialogSupports: true);
  }

  @override
  void setPosition(int viewId, Offset position) {
    _viewExistChecker(viewId, () => _ffiBridge.setPosition(viewId, pos: position), dialogSupports: true);
  }

  @override
  void setPreventClose(int viewId, bool isPreventClose) {
    _viewExistChecker(viewId, () => _ffiBridge.setPreventClose(viewId, isPreventClose: isPreventClose));
  }

  @override
  void setProgressBar(double progress) {
    if (Platform.isLinux) return;
    final id = _lifecycleViewId;
    if (id == null) return;
    _viewExistChecker(id, () => _ffiBridge.setProgressBar(progress), dialogSupports: true);
  }

  @override
  void setResizable(int viewId, bool isResizable) {
    _viewExistChecker(viewId, () => _ffiBridge.setResizable(viewId, isResizable), dialogSupports: true);
  }

  @override
  void setSize(int viewId, Size size) {
    _viewExistChecker(viewId, () => _ffiBridge.setSize(viewId, size: size), dialogSupports: true);
  }

  @override
  void setTitle(int viewId, String title) {
    _viewExistChecker(viewId, () => _ffiBridge.setTitle(viewId, title: title), dialogSupports: true);
  }

  @override
  void setTitleBarStyle(
    int viewId,
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) {
    _viewExistChecker(
      viewId,
      () => _ffiBridge.setTitleBarStyle(
        viewId,
        style: style,
        closeVisibility: closeVisibility,
        maximizeVisibility: maximizeVisibility,
        minimizeVisibility: minimizeVisibility,
      ),
      dialogSupports: true,
    );
  }

  @override
  void setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) {
    if (!Platform.isMacOS) return;

    _viewExistChecker(
      viewId,
      () => _ffiBridge.setVisibleOnAllWorkspaces(viewId, visible, visibleOnFullScreen: visibleOnFullScreen),
      dialogSupports: true,
    );
  }

  @override
  void show(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.show(viewId), dialogSupports: true);
  }

  @override
  void startDragging(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.startDragging(viewId), dialogSupports: true);
  }

  @override
  void startResizing(int viewId, ResizeEdge edge) {
    if (Platform.isMacOS) return;
    _viewExistChecker(viewId, () => _ffiBridge.startResizing(viewId, edge), dialogSupports: true);
  }

  @override
  void unmaximize(int viewId) {
    _viewExistChecker(viewId, () => _ffiBridge.unmaximize(viewId));
  }

  @override
  Future<bool> closeApp({CloseMode? closeMode}) async {
    final mode = closeMode ?? config.generalParams.closeMode;
    return await _closeApp(mode);
  }

  /// Closes every registered window (all roots and their subtrees).
  /// if all views successfully closed by mode `mode` return `true` else `false`
  Future<bool> _closeApp(CloseMode mode) async {
    final allRoots = _rootWindowIds()..sort();

    _saveLastWindowToReopen = false;
    applyNativeLifecyclePolicy();
    for (final root in allRoots.reversed) {
      cascadeCloseService.attachWindow(root);
      unawaited(_closeSubtreeByMode(root, mode));
      final closed = await cascadeCloseService.waitWindow(root);
      if (!closed) {
        if (Platform.isMacOS) {
          _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;
          applyNativeLifecyclePolicy();
        }
        return false;
      }
    }

    return true;
  }

  T? _viewExistChecker<T>(int viewId, Function() func, {bool dialogSupports = false}) {
    final isManaged = _windows.containsKey(viewId) || _dialogs.containsKey(viewId) || _popups.containsKey(viewId);
    if (dialogSupports) {
      if (!isManaged) return null;
    } else {
      if (!_windows.containsKey(viewId)) return null;
    }

    if (!_hasLiveFlutterView(viewId)) return null;
    try {
      return func();
    } on PlatformException catch (e) {
      // Race during cascade close: native window gone before didChangeMetrics.
      if (e.code == 'NO_WINDOW') return null;
      rethrow;
    }
  }

  bool _hasLiveFlutterView(int viewId) {
    return WidgetsBinding.instance.platformDispatcher.view(id: viewId) != null;
  }
}
