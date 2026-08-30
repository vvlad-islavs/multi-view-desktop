part of 'view_root.dart';

// ---------------------------------------------------------------------------
// _ViewsManagerImpl
// ---------------------------------------------------------------------------

/// Default `ViewsManager`: native channel, window registry, listeners, and close modes.
class _ViewsManagerImpl implements ViewsManager {
  // ===========================================================================
  // Dependencies
  // ===========================================================================

  final CascadeCloseService cascadeCloseService;
  final WindowCommunicatorImpl communicator;
  final MultiAppConfig config;
  final ModalStateService _modalStateService = ModalStateService();

  // ===========================================================================
  // Lifecycle & native host (late init)
  // ===========================================================================

  late final LifecycleViewsController _lifecycle;
  late final ViewNativeHost _nativeHost;
  late final ViewManagerProxies _proxies;

  ViewManagerProxies get proxies => _proxies;

  ViewRegistry get _registry => _lifecycle.registry;

  // ===========================================================================
  // State
  // ===========================================================================

  /// Active strategy when the main window's close button is pressed.
  late CloseMode closeMode;

  late bool _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;

  /// Anchor window: receives app-level close policy (`CloseMode`) from the native close button.
  int? _realAnchorId;

  int? get realAnchorId => _realAnchorId;

  int _initRealId = _initPlatformId;

  int get mainRealViewId => _initRealId;

  // Hot-restart view id shift.
  int _hotRestartShift = 0;
  bool _isInitFirstSecondaryView = false;

  final Map<int, ValueNotifier<List<DialogInfo>>> _dialogModalPublicNotifiers = {};
  final Map<int, dynamic> _dialogsResults = {};
  final Map<int, ObserverList<WindowListenerCallbacks>> _listeners = {};

  final ValueNotifier<List<int>> _windowsNotifier = ValueNotifier([]);
  final ValueNotifier<List<int>> _dialogsNotifier = ValueNotifier([]);

  ValueNotifier<List<int>> get windowsNotifier => _windowsNotifier;

  ValueNotifier<List<int>> get dialogsNotifier => _dialogsNotifier;

  Iterable<MapEntry<int, ViewWindowEntry>> get windowEntries => _registry.windows.entries;

  Iterable<MapEntry<int, ViewDialogEntry>> get dialogEntries => _registry.dialogs.entries;

  List<int> get allRealWindowIds => _registry.windows.keys.toList();

  List<int> get allShiftedWindowIds => _registry.windows.keys.map((e) => _realToShifted(e)).toList();

  List<WindowObserver> get _observers => config.observers;

  // ===========================================================================
  // Constructor
  // ===========================================================================

  _ViewsManagerImpl({required this.config, required this.cascadeCloseService, required this.communicator}) {
    _ffiBridge.setMethodCallHandler(_onStaticCall);
    closeMode = config.generalParams.closeMode;
    final registry = ViewRegistry();
    final closeDelegate = ViewCloseDelegate(
      disposeView: _disposeView,
      anchorCandidatesExcluding: ({excludingViewId}) => _anchorCandidates(excludingViewId: excludingViewId),
      enableDynamicAnchor: config.generalParams.enableDynamicAnchor,
      isLastMacosRootView: _isLastMacosRootView,
      invoke: _viewExistChecker,
    );
    final viewAnimator = ViewAnimator();
    final animationController = ViewAnimationController(config: config.generalParams.animation, animator: viewAnimator);
    final positionCalculator = WindowPositionCalculator.instance;
    _nativeHost = ViewNativeHost(ffi: _ffiBridge, invoke: _viewExistChecker, registry: registry);
    _proxies = ViewManagerProxies(
      _nativeHost,
      animationController: animationController,
      positionCalculator: positionCalculator,
    );
    animationController.bindProxies(_proxies);
    _lifecycle = LifecycleViewsController(
      registry: registry,
      proxies: _proxies,
      ffiBridge: _ffiBridge,
      animationController: animationController,
      positionCalculator: positionCalculator,
      animation: config.generalParams.animation,
      closeDelegate: closeDelegate,
      cascadeCloseService: cascadeCloseService,
      registerDialog: (parentId, {required dialogId, required isModal}) {
        _modalStateService.registerDialog(parentId, dialogId: dialogId, isModal: isModal);
      },
      hasPendingDialogCreate: (parentId) =>
          _lifecycle.createCompleters.values.any((e) => !e.isCompleted && e.isDialog && e.parentId == parentId),
      hasModalDialog: (parentId) =>
          _modalStateService.getNotifier(parentId).value.firstWhereOrNull((e) => e.isModal) != null,
      onDialogCloseResult: (viewId, res) => _dialogsResults[viewId] = res,
      onPopupDestroyed: _unregisterPopup,
      onBeforeCloseApp: () {
        _saveLastWindowToReopen = false;
        applyNativeLifecyclePolicy();
      },
      onCloseAppAborted: () {
        if (Platform.isMacOS) {
          _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;
          applyNativeLifecyclePolicy();
        }
      },
      onBeforeForceCloseApp: () {
        _saveLastWindowToReopen = false;
        applyNativeLifecyclePolicy();
      },
    );
    _lifecycle.closeService.closeMode = closeMode;
    _lifecycle.closeService.anchorViewId = _realAnchorId;
  }

  // ===========================================================================
  // ViewsManager: ID mapping
  // ===========================================================================

  @override
  int shiftedToRealId(int viewId) => _shiftedToReal(viewId);

  @override
  int realToShiftedId(int viewId) => _realToShifted(viewId);

  // ===========================================================================
  // ViewsManager: create
  // ===========================================================================

  @override
  Future<int> createWindow({
    WindowOptions? newOpts,
    required void Function(int) onCreated,
    int? parent,
    AnimationSettings? animation,
  }) {
    if (parent != null && !_registry.windows.containsKey(parent)) {
      MvdLog.instance.error('create', 'createWindow: parent is not registered', {
        'parentRealId': parent,
        'windows': allRealWindowIds.join(','),
      });
      throw ArgumentError.value(parent, 'Parent error', 'Parent window is not registered');
    }

    final comparedOpts = _compareGlobalAndNewOpts(preferred: newOpts, global: config.globalWindowOptions);

    MvdLog.instance.info('create', parent == null ? 'createWindow (independent)' : 'createWindow (child)', {
      'parentRealId': parent,
      'title': comparedOpts.title,
      'hasShellOverrides': newOpts?.shellOverrides != null,
      'shell': _shellLog(newOpts?.shellOverrides),
    });

    if (parent == null) {
      return _lifecycle.openWindow(options: comparedOpts, onCreated: onCreated, animation: animation);
    }
    return _lifecycle.openChildWindow(
      parentId: parent,
      options: comparedOpts,
      onCreated: onCreated,
      animation: animation,
    );
  }

  @override
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required void Function(int) onCreated,
    AnimationSettings? animation,
  }) async {
    if (!_registry.windows.containsKey(parentRealId)) {
      MvdLog.instance.error('create', 'createDialog: parent is not registered', {
        'parentRealId': parentRealId,
        'windows': allRealWindowIds.join(','),
      });
      throw ArgumentError.value(parentRealId, 'Parent error', 'Parent window is not registered');
    }

    if (_lifecycle.hasPendingDialogCreate(parentRealId)) {
      MvdLog.instance.error('create', 'createDialog while another dialog is creating', {
        'parentRealId': parentRealId,
      });
      throw Exception('Create error: "Create dialog" was called while another dialog is creating in the same window');
    }

    final comparedOpts = _compareDialogGlobalAndNewOpts(preferred: newOpts, global: config.globalDialogOptions);
    if (comparedOpts.modal == true && _lifecycle.hasModalDialog(parentRealId)) {
      MvdLog.instance.error('create', 'createDialog: modal already open on parent', {
        'parentRealId': parentRealId,
      });
      throw Exception('Create error: One window can has only one modal dialog');
    }

    MvdLog.instance.info('create', 'createDialog', {
      'parentRealId': parentRealId,
      'modal': comparedOpts.modal,
      'title': comparedOpts.title,
      'hasShellOverrides': newOpts?.shellOverrides != null,
      'shell': _shellLog(newOpts?.shellOverrides),
    });

    if (comparedOpts.modal ?? false) {
      return _lifecycle.openModalDialog(
        parentId: parentRealId,
        options: comparedOpts,
        onCreated: onCreated,
        animation: animation,
      );
    }
    return _lifecycle.openModelessDialog(
      parentId: parentRealId,
      options: comparedOpts,
      onCreated: onCreated,
      animation: animation,
    );
  }

  @override
  Future<int> createPopup({required int parentRealId, required Size size, AnimationSettings? animation}) async {
    if (!_registry.windows.containsKey(parentRealId) && !_registry.dialogs.containsKey(parentRealId)) {
      MvdLog.instance.error('create', 'createPopup: parent is not registered', {
        'parentRealId': parentRealId,
      });
      throw ArgumentError.value(parentRealId, 'Parent error', 'Parent window is not registered');
    }

    MvdLog.instance.info('create', 'createPopup', {
      'parentRealId': parentRealId,
      'size': '${size.width}x${size.height}',
    });

    return _lifecycle.openPopup(
      parentId: parentRealId,
      size: size,
      animation: animation,
      onCreated: (viewId) {
        _updateHotRestartShiftBySecondary(viewId);
        _registry.popups[viewId] = ViewPopupEntry(parentId: parentRealId);
        MvdLog.instance.ids(
          'create',
          'popup registered',
          realId: viewId,
          parentRealId: parentRealId,
          extra: {'popups': _registry.popups.keys.join(',')},
        );
      },
    );
  }

  // ===========================================================================
  // ViewsManager: close
  // ===========================================================================

  @override
  Future<bool> closeView<T>(int viewId, {T? dialogRes, AnimationSettings? animation}) {
    MvdLog.instance.ids(
      'close',
      'closeView requested',
      realId: viewId,
      publicId: _realToShifted(viewId),
      extra: {
        'isDialog': _registry.isDialog(viewId),
        'isPopup': _registry.isPopup(viewId),
        'closeMode': closeMode.name,
      },
    );
    if (!_registry.isModalDialog(viewId)) {
      _lifecycle.animationController.stageSoftOverride(
        viewId,
        _registry.isDialog(viewId) ? ViewAnimationType.closeDialog : ViewAnimationType.closeWindow,
        animation,
      );
    }
    return _lifecycle.closeService.closeView<T>(viewId, dialogRes: dialogRes);
  }

  @override
  void stageForceViewAnimation(int viewId, ViewAnimationType type, {AnimationSettings? animation}) {
    _lifecycle.animationController.stageForceOverride(viewId, type, animation);
  }

  @override
  Future<bool> closeApp({CloseMode? closeMode}) {
    final mode = closeMode ?? config.generalParams.closeMode;
    MvdLog.instance.info('close', 'closeApp', {'mode': mode.name, 'windows': allRealWindowIds.join(',')});
    return _lifecycle.closeService.closeApp(mode: mode);
  }

  @override
  void cancelCascadeClose(int viewId) {
    MvdLog.instance.info('close', 'cancelCascadeClose', {
      'realId': viewId,
      'publicId': _realToShifted(viewId),
    });
    _lifecycle.closeService.cancelCascade(viewId);
  }

  @override
  CloseMode getAppCloseMode() => closeMode;

  @override
  void setAppCloseMode(CloseMode closeMode) {
    MvdLog.instance.info('close', 'setAppCloseMode', {
      'from': this.closeMode.name,
      'to': closeMode.name,
    });
    this.closeMode = closeMode;
    _lifecycle.closeService.closeMode = closeMode;
    applyNativeLifecyclePolicy();
  }

  // ===========================================================================
  // ViewsManager: popups
  // ===========================================================================

  @override
  Future<void> showPopup(int viewId, {bool animate = true}) {
    if (!_registry.isPopup(viewId)) return Future.value();
    if (!animate) {
      _proxies.state.show(viewId);
      return Future.value();
    }
    return _lifecycle.popupOwner.showWithFadeIn(viewId);
  }

  @override
  Future<void> closePopup(int viewId, {AnimationSettings? animation}) async {
    if (!_registry.isPopup(viewId)) return;
    _lifecycle.animationController.stageSoftOverride(viewId, ViewAnimationType.closePopup, animation);
    await _lifecycle.popupOwner.close(viewId);
  }

  @override
  Future<void> destroyPopup(int viewId) async {
    _lifecycle.closeService.destroyPopup(viewId);
  }

  @override
  Future<bool> positionPopup(int viewId, Rect bounds, {AnimationSettings? animation}) async {
    if (!_hasLiveFlutterView(viewId)) return false;
    return _proxies.position.positionPopup(viewId, bounds, animation: animation);
  }

  // ===========================================================================
  // ViewsManager: anchor
  // ===========================================================================

  @override
  bool get isEnabledDynamicAnchor => config.generalParams.enableDynamicAnchor;

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

  // ===========================================================================
  // ViewsManager: listeners and introspection
  // ===========================================================================

  @override
  void addListener(int viewId, WindowListenerCallbacks listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListenerCallbacks>()).add(listener);
  }

  @override
  void removeListener(int viewId, WindowListenerCallbacks listener) {
    _listeners[viewId]?.remove(listener);
  }

  @override
  WindowInfo windowType(int viewId) {
    final dialog = _registry.dialogs[viewId];
    return (isDialog: dialog != null, isModal: dialog?.isModal ?? false);
  }

  // ===========================================================================
  // ViewsManager: view shell overrides
  // ===========================================================================

  @override
  void patchViewShell(int viewId, ViewShellOverrides overrides) {
    final entry = _viewEntryFor(viewId);
    if (entry == null) {
      MvdLog.instance.warn('shell', 'patchViewShell: no entry', {'realId': viewId});
      return;
    }
    final notifier = entry.viewShellOverrides;
    final merged = ViewShellOverrides.merge(notifier.value, overrides);
    MvdLog.instance.info('shell', 'patchViewShell', {
      'realId': viewId,
      'publicId': _realToShifted(viewId),
      'before': _shellLog(notifier.value),
      'delta': _shellLog(overrides),
      'after': _shellLog(merged),
    });
    notifier.value = merged;
  }

  @override
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides) {
    MvdLog.instance.info('shell', 'setViewShellOverrides', {
      'realId': viewId,
      'publicId': _realToShifted(viewId),
      'before': _shellLog(_viewEntryFor(viewId)?.viewShellOverrides.value),
      'after': _shellLog(overrides),
    });
    _viewEntryFor(viewId)?.viewShellOverrides.value = overrides;
  }

  @override
  ViewShellOverrides? getViewShellOverrides(int viewId) => _viewEntryFor(viewId)?.viewShellOverrides.value;

  // ===========================================================================
  // Internal API: root widget and startup
  // ===========================================================================

  /// Returns the `ValueNotifier<List<DialogInfo>>` tracking modal dialogs blocking `realViewId`.
  ValueNotifier<List<DialogInfo>> getDialogModalPublicIdsFromRealParentIdNotifier(int realViewId) =>
      _dialogModalPublicNotifiers.putIfAbsent(
        realViewId,
        () => MappedValueNotifier(
          source: _modalStateService.getNotifier(realViewId),
          transform: (dialogs) => [for (final d in dialogs) (id: _realToShifted(d.id), isModal: d.isModal)],
        ),
      );

  void registerInitialWindow({required int viewId, required Widget Function(BuildContext) homeBuilder}) {
    // Win & linux by default init from 0 id but macos from 1
    _hotRestartShift = !Platform.isMacOS ? -1 : 0;
    MvdLog.instance.info('shift', 'registerInitialWindow begin', {
      'incomingViewId': viewId,
      'hasInitView': _hasInitView,
      'initPlatformId': _initPlatformId,
      'preShift': _hotRestartShift,
    });
    if (!_hasInitView) {
      viewId = _createNextMainWindowAfterRestart(homeBuilder);
      MvdLog.instance.ids('shift', 'created replacement main window after restart', realId: viewId);
    }

    _hotRestartShift = viewId - 1;
    _initRealId = viewId;
    MvdLog.instance.ids(
      'shift',
      'registerInitialWindow',
      realId: viewId,
      publicId: 1,
      shift: _hotRestartShift,
      extra: {'initRealId': _initRealId},
    );
    _setAnchor(viewId, force: true);

    globalRootState.addWindowView(viewId, homeBuilder, parentContext: null, parentId: null);
    _applyOptionsToInitialAnchor();
  }

  void registerWindow(
    int viewId,
    Widget Function(BuildContext) widgetBuilder, {
    required BuildContext? parentContext,
    int? parentId,
    ViewShellOverrides? shellOverrides,
  }) {
    if (parentId != null && !_registry.windows.containsKey(parentId)) {
      MvdLog.instance.error('create', 'registerWindow: parent is not registered', {
        'realId': viewId,
        'parentRealId': parentId,
        'windows': allRealWindowIds.join(','),
      });
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addWindow(
      viewId,
      ViewWindowEntry(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        parentId: parentId,
        initialShellOverrides: shellOverrides,
      ),
    );
    final publicId = _realToShifted(viewId);
    final parentPublicId = parentId != null ? _realToShifted(parentId) : null;
    MvdLog.instance.ids(
      'create',
      'window registered',
      realId: viewId,
      publicId: publicId,
      parentRealId: parentId,
      parentPublicId: parentPublicId,
      shift: _hotRestartShift,
      extra: {
        'hasParentContext': parentContext != null,
        'shell': _shellLog(shellOverrides),
        'windows': allRealWindowIds.join(','),
      },
    );
    _notifyObservers(
      (o) => o.onWindowOpened(publicId, parentViewId: parentPublicId),
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
    if (!_registry.windows.containsKey(parentId)) {
      MvdLog.instance.error('create', 'registerDialog: parent is not registered', {
        'realId': viewId,
        'parentRealId': parentId,
      });
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addDialog(
      viewId,
      ViewDialogEntry(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        initialShellOverrides: shellOverrides,
        parentId: parentId,
        isModal: isModal,
        closeCompleter: closeCompleter as Completer<Object?>,
      ),
    );

    final publicId = _realToShifted(viewId);
    final parentPublicId = _realToShifted(parentId);
    MvdLog.instance.ids(
      'create',
      'dialog registered',
      realId: viewId,
      publicId: publicId,
      parentRealId: parentId,
      parentPublicId: parentPublicId,
      extra: {'isModal': isModal, 'shell': _shellLog(shellOverrides)},
    );
    _notifyObservers((o) => o.onDialogOpened(publicId, parentViewId: parentPublicId));
  }

  void firstFrameCbComplete(int viewId) => _lifecycle.firstFrameCbComplete(viewId);

  void applyOptions(int viewId, {required WindowOptions opts}) {
    _lifecycle.optionsApplier.applyWindow(viewId, opts);
  }

  /// Applies `MultiPlatformParams.menuItems` from startup config.
  void applyInitialTaskbarMenu() {
    final items = config.generalParams.menuItems;
    if (items.isEmpty) return;
    unawaited(_proxies.taskbar.setTaskbarMenu(items: items));
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

  Future<void> removeOrphanViewsForceAfterRestart(List<int> ids) async {
    cascadeCloseService.clear();
    for (final id in ids) {
      try {
        _ffiBridge.forceCloseView(id);
        _ffiBridge.destroyModalDialog(id);
      } catch (_) {}
    }
  }

  /// When the anchor `FlutterView` disappears, pick another root window.
  void reconcileAnchor(PlatformDispatcher dispatcher) {
    final anchor = _realAnchorId;
    if (anchor == null) return;
    if (dispatcher.view(id: anchor) != null) return;
    _setAnchor(_realAnchorId);
    _promoteAnchor();
  }

  // ===========================================================================
  // Registry mutations
  // ===========================================================================

  void _addWindow(int viewId, ViewWindowEntry entry) {
    _registry.windows[viewId] = entry;
    _windowsNotifier.value = _registry.windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _addDialog(int dialogId, ViewDialogEntry entry) {
    _registry.dialogs[dialogId] = entry;
    _dialogsNotifier.value = _registry.dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeWindow(int viewId) {
    _registry.windows.remove(viewId)?.disposeEntryResources();
    _windowsNotifier.value = _registry.windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeDialog(int dialogId) {
    final dialog = _registry.dialogs[dialogId];
    if (dialog == null) return;
    dialog.completeResult(_dialogsResults.remove(dialogId));
    dialog.disposeEntryResources();
    _registry.dialogs.remove(dialogId);
    _dialogsNotifier.value = _registry.dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _disposeView(int viewId) {
    final dialogEntry = _registry.dialogs[viewId];
    final shiftedViewId = _realToShifted(viewId);
    final isDialog = dialogEntry != null;
    final parentRealId = isDialog ? dialogEntry.parentId : _registry.windowParentId(viewId);
    final children = _registry.directChildWindowIds(viewId);

    MvdLog.instance.ids(
      'close',
      isDialog ? 'dispose dialog' : 'dispose window',
      realId: viewId,
      publicId: shiftedViewId,
      parentRealId: parentRealId,
      extra: {
        'wasAnchor': viewId == _realAnchorId,
        'children': children.join(','),
        'closeMode': closeMode.name,
      },
    );

    if (!isDialog &&
        closeMode == CloseMode.softCascade &&
        children.isNotEmpty) {
      MvdLog.instance.error('close', 'cascade: parent closed while children still registered', {
        'realId': viewId,
        'publicId': shiftedViewId,
        'children': children.join(','),
      });
    }
    if (!isDialog &&
        closeMode == CloseMode.softCascade &&
        parentRealId != null &&
        !_registry.isWindow(parentRealId)) {
      MvdLog.instance.error('close', 'cascade: child closed after parent was already destroyed', {
        'realId': viewId,
        'publicId': shiftedViewId,
        'parentRealId': parentRealId,
      });
    }

    if (isDialog) {
      _notifyObservers((o) => o.onDialogClose(shiftedViewId));
    } else if (_registry.windows.containsKey(viewId)) {
      _notifyObservers((o) => o.onWindowClosed(shiftedViewId));
    }
    if (isDialog) {
      _modalStateService.unregisterDialog(dialogEntry.parentId, realDialogId: viewId);
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

  void _unregisterPopup(int viewId) {
    final parentId = _registry.popups[viewId]?.parentId;
    _registry.popups.remove(viewId);
    MvdLog.instance.info('create', 'popup unregistered', {
      'realId': viewId,
      'parentRealId': parentId,
    });
  }

  void _destroyPopupsByParent(int parentId) {
    final ids = _registry.directPopupChildIds(parentId);
    for (final id in ids) {
      destroyPopup(id);
    }
  }

  // ===========================================================================
  // Anchor management
  // ===========================================================================

  void _setAnchor(int? viewId, {bool force = false}) {
    if (!config.generalParams.enableDynamicAnchor && !force) return;
    final previousShifted = _realAnchorId != null ? _realToShifted(_realAnchorId!) : null;
    _realAnchorId = viewId;
    _lifecycle.closeService.anchorViewId = viewId;
    final newShifted = viewId != null ? _realToShifted(viewId) : null;
    if (previousShifted != newShifted) {
      MvdLog.instance.ids(
        'anchor',
        'anchor changed',
        realId: viewId,
        publicId: newShifted,
        extra: {'previousPublicId': previousShifted, 'force': force},
      );
      _notifyObservers((o) => o.onAnchorChanged(previousShifted, newShifted));
    }
    if (viewId == null) return;
    _ffiBridge.setAnchorViewId(viewId);
  }

  void _promoteAnchor({int? excludingViewId}) {
    final candidates = _anchorCandidates(excludingViewId: excludingViewId);
    if (candidates.isEmpty) {
      _setAnchor(null);
      return;
    }
    _setAnchor(candidates.first);
  }

  List<int> _anchorCandidates({int? excludingViewId}) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates =
        _registry.windows.entries
            .where((e) => e.value.parentId == null && e.key != excludingViewId)
            .map((e) => e.key)
            .where((id) => dispatcher.view(id: id) != null)
            .toList()
          ..sort();
    return candidates;
  }

  bool _isLastMacosRootView(int id) =>
      ((_anchorCandidates(excludingViewId: id).isEmpty) && _saveLastWindowToReopen && _realAnchorId == id);

  // ===========================================================================
  // Hot-restart ID shift
  // ===========================================================================

  int _realToShifted(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == _initRealId) {
      return 1;
    }

    final shifted = viewId - _hotRestartShift;
    if (shifted < 1) {
      MvdLog.instance.error('shift', 'realToShifted produced public id < 1', {
        'realId': viewId,
        'publicId': shifted,
        'shift': _hotRestartShift,
        'initRealId': _initRealId,
        'initPlatformId': _initPlatformId,
        'isWindow': _registry.isWindow(viewId),
        'isDialog': _registry.isDialog(viewId),
        'isPopup': _registry.isPopup(viewId),
        'windows': allRealWindowIds.join(','),
      });
    }
    return shifted;
  }

  int _shiftedToReal(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == 1) {
      return _initRealId;
    }

    if (viewId < 1) {
      MvdLog.instance.error('shift', 'shiftedToReal received public id < 1', {
        'publicId': viewId,
        'shift': _hotRestartShift,
        'initRealId': _initRealId,
      });
    }
    return viewId + _hotRestartShift;
  }

  void _updateHotRestartShiftBySecondary(int viewId) {
    if (viewId == 2) {
      _isInitFirstSecondaryView = true;
    }
    if (allShiftedWindowIds.length == 1 && allShiftedWindowIds.first == 1 && viewId > 2 && !_isInitFirstSecondaryView) {
      final previous = _hotRestartShift;
      _hotRestartShift = viewId - allShiftedWindowIds.first - 1;
      MvdLog.instance.info('shift', 'shift updated by first secondary view', {
        'realId': viewId,
        'previousShift': previous,
        'shift': _hotRestartShift,
        'initRealId': _initRealId,
      });

      _isInitFirstSecondaryView = true;
    }
  }

  int _createNextMainWindowAfterRestart(Widget Function(BuildContext) homeBuilder) {
    final opts = config.globalWindowOptions;

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = WindowPositionCalculator.instance.calcWindowPosition(windowSize, opts.alignment!);
    }
    int? newViewId;
    try {
      newViewId = _ffiBridge.createWindow(
        token: 0000,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
      );
    } catch (e, st) {
      MvdLog.instance.error('shift', 'create replacement main window threw', {'error': e, 'stack': st});
      throw Exception('Failed to create new window, tokenId: 0000. Error: $e, stack: $st');
    }

    if (CreateViewError.isErrorCode(newViewId)) {
      MvdLog.instance.error('shift', 'create replacement main window failed', {'code': newViewId});
      final error = CreateViewError.fromCode(newViewId);
      if (error == CreateViewError.forceClose) {
        // do nothing
      }
      throw Exception(error.message(0));
    }

    return newViewId;
  }

  void _applyOptionsToInitialAnchor() {
    if (realAnchorId == null) return;
    applyOptions(realAnchorId!, opts: config.globalWindowOptions);

    final viewId = realAnchorId!;
    _lifecycle.windowOwner.trackUntilFirstFrame(viewId, parentId: null, isDialog: false);
    unawaited(_showInitialAnchorAfterFirstFrame(viewId));
  }

  Future<void> _showInitialAnchorAfterFirstFrame(int viewId) async {
    await _lifecycle.windowOwner.waitFirstFrame(viewId);
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
    }
    if (realAnchorId != viewId || !_registry.windows.containsKey(viewId)) return;
    _proxies.state.show(viewId);
  }

  // ===========================================================================
  // Native FFI events
  // ===========================================================================

  /// Defers close orchestration until after the current frame fully completes.
  ///
  /// [SchedulerBinding.endOfFrame] completes only when draw + all post-frame
  /// callbacks are done - then `step` runs with scheduler back at [SchedulerPhase.idle].
  ///
  /// Do not use [SchedulerBinding.addPostFrameCallback] here: that callback runs
  /// during [SchedulerPhase.postFrameCallbacks], still inside the frame pipeline.
  ///
  /// Do not call [SchedulerBinding.scheduleFrame] here: from the native event
  /// callback it can synchronously re-enter `beginFrame` while a frame is active.
  /// [endOfFrame] already schedules a frame when [SchedulerPhase.idle].
  void _deferCloseServiceStep(Future<void> Function() step) {
    WidgetsBinding.instance.endOfFrame.then((_) {
      unawaited(step());
    });
  }

  dynamic _onStaticCall(MethodCall call) {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;
    final int? eventViewId = call.arguments['viewId'] as int?;
    if (eventName != 'move' && eventName != 'resize') {
      MvdLog.instance.info('event', eventName, {
        'realId': eventViewId,
        if (eventViewId != null) 'publicId': _realToShifted(eventViewId),
        if (eventViewId != null) 'isWindow': _registry.isWindow(eventViewId),
        if (eventViewId != null) 'isDialog': _registry.isDialog(eventViewId),
        if (eventViewId != null) 'isPopup': _registry.isPopup(eventViewId),
      });
    }

    if (eventName == 'popup-closed') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        _unregisterPopup(viewId);
      }
    } else if (eventName == 'viewCreated') {
      // do nothing. now create is sync
    } else if (eventName == 'taskbar-callback') {
      config.macosParams.onTaskbarTap?.call();
    } else if (eventName == 'preconfirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        _deferCloseServiceStep(() => _lifecycle.closeService.handeFirstCloseStep(viewId));
      }
    } else if (eventName == 'confirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        _deferCloseServiceStep(() => _lifecycle.closeService.handleLastCloseStep(viewId));
      }
    } else if (eventName == 'applicationShouldTerminateRequest') {
      unawaited(_macosOnShouldAppTerminate());
    } else if (eventName == 'taskbarMenuItemSelected') {
      final id = call.arguments['id'] as int?;
      if (id != null) {
        _proxies.taskbar.invokeMenuCallback(id);
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
    MvdLog.instance.info('lifecycle', 'applicationShouldTerminateRequest');
    final confirmTerminate = await config.macosParams.onTerminate?.call() ?? true;
    MvdLog.instance.info('lifecycle', 'applicationShouldTerminate reply', {'confirm': confirmTerminate});
    if (confirmTerminate) {
      _ffiBridge.closeIsolateLocal();
    }
    _ffiBridge.replyToApplicationShouldTerminate(confirmTerminate);
  }

  void _dispatchViewEvent(int viewId, String eventName) {
    if (_registry.windows.keys.contains(viewId)) {
      _notifyObservers((o) => o.onWindowEvent(_realToShifted(viewId), eventName));
    }
    if (_registry.dialogs.keys.contains(viewId)) {
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
    await _lifecycle.closeService.handleWindowCloseListenerResult(res, viewId);
  }

  // ===========================================================================
  // Options merge
  // ===========================================================================

  WindowOptions _compareGlobalAndNewOpts({WindowOptions? preferred, required WindowOptions global}) {
    if (preferred == null) return global;
    return WindowOptions(
      size: preferred.size ?? global.size,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      alignment: preferred.alignment ?? global.alignment,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
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

  // ===========================================================================
  // Helpers
  // ===========================================================================

  void _notifyObservers(void Function(WindowObserver) action) {
    for (final observer in _observers) {
      action(observer);
    }
  }

  ViewEntryBase? _viewEntryFor(int viewId) => _registry.entryFor(viewId);

  String _shellLog(ViewShellOverrides? o) {
    if (o == null) return 'none';
    return 'appearance=${o.appearance != null} router=${o.usesRouter} '
        'home=${o.home != null} title=${o.title} locale=${o.appearance?.locale} '
        'themeMode=${o.appearance?.themeMode}';
  }

  T? _viewExistChecker<T>(int viewId, Function() func, {bool dialogSupports = false}) {
    final isManaged =
        _registry.windows.containsKey(viewId) ||
        _registry.dialogs.containsKey(viewId) ||
        _registry.popups.containsKey(viewId);
    if (dialogSupports) {
      if (!isManaged) return null;
    } else {
      if (!_registry.windows.containsKey(viewId)) return null;
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
