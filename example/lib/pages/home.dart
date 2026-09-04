// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../utils/theme_config.dart';
import 'alert_view_dialog.dart';
import 'shell_demo.dart';
import '../l10n/example_localizations.dart';

// ---------------------------------------------------------------------------
// HomePage
// ---------------------------------------------------------------------------
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({super.key});

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  @override
  Widget build(BuildContext ctx) {
    return AlertViewDialog(
      title: 'Close window?',
      content: 'This window has preventClose enabled.',
      actions: [
        TextButton(onPressed: () => ctx.closeDialog(), child: const Text('Cancel')),
        TextButton(onPressed: () => ctx.closeDialog<bool>(true), child: const Text('Close')),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  final GlobalKey _dialogKey = GlobalKey();

  final PopupController _popupController = PopupController();

  static const _popupCurves = <String, Curve>{
    'linear': Curves.linear,
    'decelerate': Curves.decelerate,
    'fastLinearToSlowEaseIn': Curves.fastLinearToSlowEaseIn,
    'fastEaseInToSlowEaseOut': Curves.fastEaseInToSlowEaseOut,
    'ease': Curves.ease,
    'easeIn': Curves.easeIn,
    'easeInToLinear': Curves.easeInToLinear,
    'easeInSine': Curves.easeInSine,
    'easeInQuad': Curves.easeInQuad,
    'easeInCubic': Curves.easeInCubic,
    'easeInQuart': Curves.easeInQuart,
    'easeInQuint': Curves.easeInQuint,
    'easeInExpo': Curves.easeInExpo,
    'easeInCirc': Curves.easeInCirc,
    'easeInBack': Curves.easeInBack,
    'easeOut': Curves.easeOut,
    'linearToEaseOut': Curves.linearToEaseOut,
    'easeOutSine': Curves.easeOutSine,
    'easeOutQuad': Curves.easeOutQuad,
    'easeOutCubic': Curves.easeOutCubic,
    'easeOutQuart': Curves.easeOutQuart,
    'easeOutQuint': Curves.easeOutQuint,
    'easeOutExpo': Curves.easeOutExpo,
    'easeOutCirc': Curves.easeOutCirc,
    'easeOutBack': Curves.easeOutBack,
    'easeInOut': Curves.easeInOut,
    'easeInOutSine': Curves.easeInOutSine,
    'easeInOutQuad': Curves.easeInOutQuad,
    'easeInOutCubic': Curves.easeInOutCubic,
    'easeInOutCubicEmphasized': Curves.easeInOutCubicEmphasized,
    'easeInOutQuart': Curves.easeInOutQuart,
    'easeInOutQuint': Curves.easeInOutQuint,
    'easeInOutExpo': Curves.easeInOutExpo,
    'easeInOutCirc': Curves.easeInOutCirc,
    'easeInOutBack': Curves.easeInOutBack,
    'fastOutSlowIn': Curves.fastOutSlowIn,
    'slowMiddle': Curves.slowMiddle,
    'bounceIn': Curves.bounceIn,
    'bounceOut': Curves.bounceOut,
    'bounceInOut': Curves.bounceInOut,
    'elasticIn': Curves.elasticIn,
    'elasticOut': Curves.elasticOut,
    'elasticInOut': Curves.elasticInOut,
  };

  static const _popupDurationsMs = <int>[100, 150, 300, 500, 1000, 2000];

  String _popupCurveName = 'easeOutCubic';
  int _popupDurationMs = 150;

  AnimationSettings get _popupAnimation {
    return AnimationSettings(
      duration: Duration(milliseconds: _popupDurationMs),
      curve: _popupCurves[_popupCurveName],
    );
  }

  // final GlobalKey _modelessDialogKey = GlobalKey();

  // Window state mirrors
  bool _isFullScreen = false;
  bool _isMaximized = false;
  bool _isAlwaysOnTop = false;
  bool _isResizable = true;
  bool _isMovable = true;
  bool _isMinimizable = true;
  bool _isMaximizable = true;
  bool _isClosable = true;
  bool _isPreventClose = false;
  bool _isHideFromCollection = false;
  bool _isHideFromTaskBar = false;
  bool _visibleOnAllWorkspaces = false;
  bool _ignoreMouseEvents = false;
  double _opacity = 1.0;
  bool _hasShadow = true;
  bool _titleBarHidden = false;
  bool _titleBarButtonVisibility = true;

  // Communication log
  final List<String> _messageLog = [];
  final _msgController = TextEditingController(text: 'Hello from window');
  int? _targetViewId;

  StreamSubscription<dynamic>? _commSub;
  StreamSubscription<dynamic>? _broadcastSub;

  // Event log
  final List<String> _eventLog = [];

  bool get _isLinux => Platform.isLinux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshState();
      final parentContext = ParentWindowScope.of(context).parentContext;
      final currMvd = MultiViewDesktop.of(context);
      final windowInfo = currMvd.getWindowInfo();
      currMvd.setTitle(
        parentContext != null && parentContext.mounted
            ? '${windowInfo.isDialog ? 'Dialog' : 'Window'} $currentId, parent: ${MultiViewDesktop.getIdByContext(parentContext)}'
            : 'Window $currentId',
      );
      MultiViewDesktop.allWindowIdsNotifier.addListener(_viewListener);

      _commSub = MultiViewDesktop.communicator.onDirect(context).listen((msg) {
        if (!mounted) return;
        setState(() => _messageLog.insert(0, '[direct] $msg'));
      });

      _broadcastSub = MultiViewDesktop.communicator.onBroadcast.listen((msg) {
        if (!mounted) return;
        // Theme changes are handled separately.
        if (msg is Map && msg['type'] == 'themeMode') return;
        setState(() => _messageLog.insert(0, '[broadcast] $msg'));
      });
    });
  }

  void _viewListener() {
    sharedConfig.anchorId = MultiViewDesktop.getAnchorId();
  }

  @override
  void dispose() {
    MultiViewDesktop.allWindowIdsNotifier.removeListener(_viewListener);
    _commSub?.cancel();
    _broadcastSub?.cancel();
    _msgController.dispose();
    _popupController.dispose();
    super.dispose();
  }

  T? _safe<T>(T Function() get) {
    if (!mounted) return null;
    return get();
  }

  void _refreshState() {
    if (!mounted) return;
    final win = MultiViewDesktop.of(context);
    final hideTaskbar = _safe(win.isHideAppTabFromTaskbar);
    final fs = _safe(win.isFullScreen);
    final max = _safe(win.isMaximized);
    final top = _safe(win.isAlwaysOnTop);
    final res = _safe(win.isResizable);
    final mov = _safe(win.isMovable);
    final mini = _safe(win.isMinimizable);
    final maxi = _safe(win.isMaximizable);
    final clos = _safe(win.isClosable);
    final prev = _safe(win.isPreventClose);
    final skip = _safe(win.macos.isHideFromCollection);
    final op = _safe(win.getOpacity);
    final visibleOnAllWorkspaces = _safe(win.macos.isVisibleOnAllWorkspaces);
    final ignoreMouseEvents = _safe(win.isIgnoreMouseEvents);
    final shadow = _safe(win.hasShadow);
    final titleBarStyle = _safe(win.getTitleBarStyle);
    if (!mounted) return;
    setState(() {
      _isFullScreen = fs ?? _isFullScreen;
      _isMaximized = max ?? _isMaximized;
      _isAlwaysOnTop = top ?? _isAlwaysOnTop;
      _isResizable = res ?? _isResizable;
      _isMovable = mov ?? _isMovable;
      _isMinimizable = mini ?? _isMinimizable;
      _isMaximizable = maxi ?? _isMaximizable;
      _isClosable = clos ?? _isClosable;
      _isPreventClose = prev ?? _isPreventClose;
      _isHideFromCollection = skip ?? _isHideFromCollection;
      _opacity = op ?? _opacity;
      _hasShadow = shadow ?? _hasShadow;
      _isHideFromTaskBar = hideTaskbar ?? _isHideFromTaskBar;
      _ignoreMouseEvents = ignoreMouseEvents?.ignore ?? _ignoreMouseEvents;
      _visibleOnAllWorkspaces = visibleOnAllWorkspaces ?? _visibleOnAllWorkspaces;
      _titleBarHidden = titleBarStyle?.style == TitleBarStyle.hidden;
      _titleBarButtonVisibility =
          (titleBarStyle?.closeVisibility ?? _titleBarButtonVisibility) ||
          (titleBarStyle?.maximizeVisibility ?? _titleBarButtonVisibility) ||
          (titleBarStyle?.minimizeVisibility ?? _titleBarButtonVisibility);
    });
  }

  // WindowListener -----------------------------------------------------------

  @override
  void onWindowEvent(String eventName) {
    setState(() => _eventLog.insert(0, 'unsortedEvent: $eventName'));
  }

  @override
  void onWindowFocus() => _refreshState();

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  void onWindowEnterFullScreen() => setState(() => _isFullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _isFullScreen = false);

  @override
  Future<bool> onWindowClose() async {
    if (!mounted) return true;
    final win = MultiViewDesktop.of(context);
    win.focus();
    // Show a confirmation dialog. can accept (remove preventClose and
    // close the window) or decline (explicitly cancel a pending cascade close).

    if (_dialogKey.currentContext?.mounted ?? false) {
      _dialogKey.currentContext?.viewController.focus();
      return true;
    }

    // close all other dialogs
    final allDialogs = DialogScope.of(context).value;
    if (allDialogs.isNotEmpty) {
      for (final dialog in allDialogs) {
        // if (dialog.isModal) {
        MultiViewDesktop.fromId(dialog.id).closeDialog();
        // }
      }
    }
    // you may get entry with id and future result right after dialog created
    final entry = await context.openDialogEntry<bool?>(
      // or only result after dialog close
      // final result = await context.openDialog<bool?>(
      (ctx, id) {
        return ConfirmDialog(key: _dialogKey);
      },
      options: DialogOptions(
        size: const Size(340, 220),
        title: 'Prevent close dialog',
        modal: false,
        isResizable: false,
        alwaysOnTop: false,
        showOnInit: true,
      ),
    );

    final accept = await entry.result;
    if (!mounted) return true;
    if (accept == true) {
      win.setPreventClose(false);
      win.closeWindow();
    } else {
      // win.cancelCascadeClose();
    }

    return accept == true;
  }

  // Helpers ------------------------------------------------------------------

  void _progressBarExample() async {
    final progressLimit = 100;
    final progressStep = 5;
    for (int i = 0; i < progressLimit; i += progressStep) {
      final progress = i / 100;
      MultiViewDesktop.setProgressBar(progress);
      await Future.delayed(Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    MultiViewDesktop.setProgressBar(-1);
  }

  void _log(String entry) => setState(() => _messageLog.insert(0, '[self] $entry'));

  Widget _section(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const Divider(height: 1),
        ...items,
        const Divider(height: 1),
      ],
    );
  }

  Widget _tile(String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _switchTile(String title, bool value, FutureOr<void> Function(bool) onChanged) {
    return _tile(
      title,
      trailing: Switch(
        value: value,
        onChanged: (v) async {
          await onChanged(v);
          _refreshState();
        },
      ),
    );
  }

  // Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final windowId = MultiViewDesktop.of(context).id;
    final windowInfo = MultiViewDesktop.of(context).getWindowInfo();

    return SafeArea(
      child: DialogModalLayer(
        showBarrierForNotModalDialog: true,
        child: Scaffold(
          appBar: _titleBarHidden
              ? null
              : AppBar(
                  title: Text(MultiViewDesktop.of(context).getTitle()),
                  backgroundColor: Theme.of(context).colorScheme.inversePrimary,
                ),
          body: ListView(
            children: [
              // ----------------------------------------------------------------
              // Theme (shared across all windows - no IPC needed!)
              // ----------------------------------------------------------------
              _section('SHARED STATE (same isolate)', [
                ListenableBuilder(
                  listenable: themeConfig,
                  builder: (context, _) {
                    final dark = themeConfig.themeMode == ThemeMode.dark;
                    return _tile(
                      'ThemeMode',
                      subtitle: themeConfig.themeMode.name,
                      trailing: Switch(
                        value: dark,
                        onChanged: (_) => themeConfig.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
                      ),
                    );
                  },
                ),
                if (!Platform.isLinux)
                  ListenableBuilder(
                    listenable: sharedConfig,
                    builder: (context, _) {
                      return _switchTile('hideAppFromTaskbar', sharedConfig.isHideAppFromTaskbar, (v) {
                        MultiViewDesktop.hideAppFromTaskbar(v);
                        if (v) MultiViewDesktop.of(context).focus();
                        sharedConfig.isHideAppFromTaskbar = MultiViewDesktop.isHideAppFromTaskbar();
                      });
                    },
                  ),
                ListenableBuilder(
                  listenable: sharedConfig,
                  builder: (context, _) {
                    return _tile(
                      'Set app closeMode',
                      subtitle: 'Current mode: ${sharedConfig.closeMode.name}',
                      onTap: () async {
                        final picked = await _showModePicker(context, sharedConfig.closeMode);
                        if (picked == null) return;
                        MultiViewDesktop.setCloseMode(picked);
                        sharedConfig.closeMode = MultiViewDesktop.getCloseMode();
                      },
                    );
                  },
                ),
                if (ParentWindowScope.of(context).parentContext == null && !MultiViewDesktop.isEnabledDynamicAnchor)
                  ListenableBuilder(
                    listenable: sharedConfig,
                    builder: (context, _) => _tile(
                      'SetCurrent as anchor (only if runMultiApp->config->generalParams->enableDynamicAnchor == false)',
                      subtitle: 'Current is ${MultiViewDesktop.getAnchorId()}',
                      onTap: () async {
                        final curr = currentId;
                        if (curr == null) return;
                        MultiViewDesktop.setAnchorId(curr);
                        sharedConfig.anchorId = MultiViewDesktop.getAnchorId();
                      },
                    ),
                  ),
              ]),
              // ----------------------------------------------------------------
              // Shell demo
              // ----------------------------------------------------------------
              if (!windowInfo.isDialog)
                _section(ExampleLocalizations.of(context).shellDemoSection, shellDemoTiles(context)),
              // ----------------------------------------------------------------
              // Window management
              // ----------------------------------------------------------------
              _section('WINDOW MANAGEMENT', [
                _tile(
                  'openWindow',
                  subtitle: 'Open a new window',
                  onTap: () async {
                    openWindow(
                      (ctx, viewId) => const HomePage(),
                      options: WindowOptions(size: const Size(1000, 700), alignment: Alignment.center, title: ' '),
                    );
                  },
                ),
                if (!windowInfo.isDialog) ...[
                  _tile(
                    'openChildWindow',
                    subtitle: 'Open a new child window',
                    onTap: () async {
                      openWindow(
                        (ctx, viewId) {
                          return const HomePage();
                        },
                        options: WindowOptions(size: const Size(1000, 700), title: ' ', alignment: Alignment.center),
                        parentContext: context,
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Popup curve', isDense: true),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
                                value: _popupCurveName,
                                items: [
                                  for (final name in _popupCurves.keys)
                                    DropdownMenuItem(value: name, child: Text(name)),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _popupCurveName = value);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Popup duration', isDense: true),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                isDense: true,
                                isExpanded: true,
                                value: _popupDurationMs,
                                items: [
                                  for (final ms in _popupDurationsMs)
                                    DropdownMenuItem(value: ms, child: Text('${ms}ms')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _popupDurationMs = value);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupView(
                    controller: _popupController,
                    positioner: PopupPositioner(
                      parentAnchor: PopupPositionerAnchor.bottomLeft,
                      childAnchor: PopupPositionerAnchor.top,
                    ),
                    builder: (ctx) => _PopupDemoBody(
                      controller: _popupController,
                      windowLabel: 'Popup of window $currentId',
                      animationOf: () => _popupAnimation,
                    ),
                    child: _tile(
                      'popupView',
                      subtitle: 'Native popup; open/close uses the curve and duration above',
                      onTap: () => _popupController.toggle(animation: _popupAnimation),
                    ),
                  ),
                  _tile(
                    'openDialog',
                    subtitle: 'Open a new child window',
                    onTap: () async {
                      // if (_modellessDialogKey.currentContext?.mounted ?? false) return;
                      // void doOnBuilt(int id) async {
                      //   final dialogView = MultiViewDesktop.fromId(id);
                      //   await dialogView.setDialogAlignment(Alignment.topLeft);
                      //   final bounds = await dialogView.getBounds();
                      //   await dialogView.setPosition(Offset(bounds.left, bounds.top + 38));
                      //   await dialogView.show();
                      // }

                      await openDialog(
                        (ctx, viewId) {
                          // doOnBuilt(viewId);
                          return HomePage();
                        },
                        options: DialogOptions(
                          size: const Size(450, 300),
                          title: ' ',
                          modal: false,
                          isResizable: true,
                          alwaysOnTop: true,
                          showOnInit: true,
                        ),
                        parentContext: context,
                      );
                    },
                  ),
                  _tile(
                    'openModalDialog',
                    subtitle: 'Open a new child window',
                    onTap: () async {
                      openDialog(
                        (ctx, viewId) {
                          return const HomePage();
                        },
                        options: DialogOptions(
                          size: const Size(900, 300),
                          title: ' ',
                          isResizable: false,
                          modal: true,
                          windowButtonVisibility: false,
                          // is ignoring in modal dialog
                          showOnInit: false,
                        ),
                        parentContext: context,
                      );
                    },
                  ),
                ],
                _tile(
                  'closeWindow',
                  subtitle: 'Close this window',
                  onTap: () => MultiViewDesktop.of(context).closeWindow(),
                ),
                if (!windowInfo.isModal || Platform.isWindows)
                  _tile('center', onTap: () => MultiViewDesktop.of(context).center()),
                if (!windowInfo.isModal || Platform.isWindows) ...[
                  if (!(windowInfo.isModal && Platform.isWindows)) ...[
                    _tile(
                      'setAlignment${_isLinux ? '. Only on X11' : ''}',
                      subtitle: 'Tap a position on the grid below',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _AlignmentGrid(
                        onSelected: (alignment) => MultiViewDesktop.of(context).setAlignment(alignment),
                      ),
                    ),
                  ],
                  if (windowInfo.isDialog) ...[
                    _tile(
                      'setAlignment ${windowInfo.isDialog ? 'inside parent' : ''}',
                      subtitle: 'Tap a position on the grid below',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _AlignmentGrid(
                        onSelected: (alignment) => MultiViewDesktop.of(context).setDialogAlignment(alignment),
                      ),
                    ),
                  ],
                ],
                _tile(
                  'setSize',
                  subtitle: '1000 x 850',
                  onTap: () => MultiViewDesktop.of(context).setSize(const Size(1000, 850)),
                ),
                _tile(
                  'setAspectRatio',
                  subtitle: '16:9',
                  onTap: () => MultiViewDesktop.of(context).setAspectRatio(16 / 9),
                ),
                _tile(
                  'clearAspectRatio',
                  subtitle: 'Pass 0 to unlock',
                  onTap: () => MultiViewDesktop.of(context).setAspectRatio(0),
                ),
                _tile(
                  'setTitle',
                  subtitle: 'Window $windowId (demo)',
                  onTap: () => MultiViewDesktop.of(context).setTitle('Window $windowId (demo)'),
                ),
                _tile(
                  'getBounds',
                  onTap: () {
                    final b = MultiViewDesktop.of(context).getBounds();
                    if (!context.mounted) return;
                    _log(
                      'bounds: ${b.left.toInt()},${b.top.toInt()} '
                      '${b.width.toInt()}x${b.height.toInt()}',
                    );
                  },
                ),
              ]),

              // ----------------------------------------------------------------
              // Title bar
              // ----------------------------------------------------------------
              _section('TITLE BAR', [
                _switchTile('titleBarStyle hidden', _titleBarHidden, (v) {
                  MultiViewDesktop.of(context).setTitleBarStyle(
                    v ? TitleBarStyle.hidden : TitleBarStyle.normal,
                    closeVisibility: _titleBarButtonVisibility,
                    minimizeVisibility: _titleBarButtonVisibility && !windowInfo.isDialog,
                    maximizeVisibility: _titleBarButtonVisibility && !windowInfo.isDialog,
                  );
                }),
                if (windowInfo.isModal || Platform.isMacOS)
                  _switchTile('titleBarButtonVisibility', _titleBarButtonVisibility, (v) {
                    MultiViewDesktop.of(context).setTitleBarStyle(
                      _titleBarHidden ? TitleBarStyle.hidden : TitleBarStyle.normal,
                      closeVisibility: v,
                      minimizeVisibility: v && !windowInfo.isDialog,
                      maximizeVisibility: v && !windowInfo.isDialog,
                    );
                  }),
                _tile(
                  'setAsFrameless',
                  subtitle: 'Remove frame entirely',
                  onTap: () {
                    MultiViewDesktop.of(context).setAsFrameless();
                    _refreshState();
                  },
                ),
              ]),

              // ----------------------------------------------------------------
              // Visibility states
              // ----------------------------------------------------------------
              _section('VISIBILITY', [
                if (!windowInfo.isDialog) ...[
                  _switchTile('fullScreen', _isFullScreen, (v) => MultiViewDesktop.of(context).setFullScreen(v)),
                  _switchTile(
                    'maximized',
                    _isMaximized,
                    (v) => v ? MultiViewDesktop.of(context).maximize() : MultiViewDesktop.of(context).unmaximize(),
                  ),
                  _tile('minimize', onTap: () => MultiViewDesktop.of(context).minimize()),
                ],

                _switchTile(
                  'alwaysOnTop${_isLinux ? '. Only on X11' : ''}',
                  _isAlwaysOnTop,
                  (v) => MultiViewDesktop.of(context).setAlwaysOnTop(v),
                ),
                if (Platform.isMacOS && !windowInfo.isModal)
                  _switchTile(
                    'hideFromCollection',
                    _isHideFromCollection,
                    (v) => MultiViewDesktop.of(context).macos.hideFromCollection(v),
                  ),
                if (Platform.isWindows)
                  _switchTile(
                    'hideCurrentTabFromTaskbar',
                    _isHideFromTaskBar,
                    (v) => MultiViewDesktop.of(context).hideCurrentAppTabFromTaskbar(v),
                  ),
                if (Platform.isMacOS && !windowInfo.isModal)
                  _switchTile(
                    'visibleOnAllWorkspaces',
                    _visibleOnAllWorkspaces,
                    (v) => MultiViewDesktop.of(context).macos.setVisibleOnAllWorkspaces(v),
                  ),
                if (!Platform.isLinux) _tile('progressBarExample', onTap: () => _progressBarExample()),
              ]),

              // ----------------------------------------------------------------
              // Capabilities
              // ----------------------------------------------------------------
              _section('WINDOW CAPABILITIES', [
                _switchTile('resizable', _isResizable, (v) => MultiViewDesktop.of(context).setResizable(v)),
                if (Platform.isMacOS && !windowInfo.isModal)
                  _switchTile('movable', _isMovable, (v) => MultiViewDesktop.of(context).setMovable(v)),
                if (!windowInfo.isDialog) ...[
                  _switchTile('minimizable', _isMinimizable, (v) => MultiViewDesktop.of(context).setMinimizable(v)),
                  if (!Platform.isLinux)
                    _switchTile('maximizable', _isMaximizable, (v) => MultiViewDesktop.of(context).setMaximizable(v)),
                ],
                if (!windowInfo.isModal)
                  _switchTile('closable', _isClosable, (v) => MultiViewDesktop.of(context).setClosable(v)),
                _switchTile('ignoreMouseEvents', _ignoreMouseEvents, (v) {
                  final win = MultiViewDesktop.of(context);
                  win.setIgnoreMouseEvents(v, mouseMoveEvents: false);
                  if (!v) return;
                  Future.delayed(Duration(seconds: 5), () => win.setIgnoreMouseEvents(false));
                }),
                if (!windowInfo.isDialog)
                  _switchTile('preventClose', _isPreventClose, (v) => MultiViewDesktop.of(context).setPreventClose(v)),
              ]),

              // ----------------------------------------------------------------
              // Appearance
              // ----------------------------------------------------------------
              _section('APPEARANCE', [
                if (Platform.isMacOS)
                  _switchTile('hasShadow', _hasShadow, (v) => MultiViewDesktop.of(context).setHasShadow(v)),
                _tile(
                  'opacity',
                  subtitle: _opacity.toStringAsFixed(2),
                  trailing: SizedBox(
                    width: 180,
                    child: Slider(
                      value: _opacity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 8,
                      onChanged: (v) {
                        setState(() => _opacity = v);
                        MultiViewDesktop.of(context).setOpacity(v);
                      },
                    ),
                  ),
                ),
                _tile(
                  'setBackgroundColor',
                  subtitle: 'Set window background transparent',
                  onTap: () => MultiViewDesktop.of(context).setBackgroundColor(Colors.transparent),
                ),
                _tile('Pop up menu', onTap: () => MultiViewDesktop.of(context).popUpWindowMenu()),
              ]),

              // ----------------------------------------------------------------
              // WindowCommunicator
              // ----------------------------------------------------------------
              _section('WINDOW COMMUNICATOR', [
                _tile(
                  'broadcast to all windows',
                  subtitle: '"${_msgController.text}"',
                  onTap: () {
                    MultiViewDesktop.communicator.broadcast({'from': windowId, 'text': _msgController.text});
                  },
                ),
                _tile(
                  'send to specific window',
                  subtitle: _targetViewId != null ? 'target: window $_targetViewId' : 'tap to pick target window',
                  onTap: () async {
                    final picked = await _showWindowPicker(context, windowId);
                    if (picked == null) return;
                    setState(() => _targetViewId = picked);
                    MultiViewDesktop.communicator.send(picked, {'from': windowId, 'text': _msgController.text});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      labelText: 'Message text',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                _tile(
                  'Message log',
                  subtitle: _messageLog.isEmpty ? '(no messages yet)' : _messageLog.take(6).join('\n'),
                ),
                _tile('clear log', onTap: () => setState(() => _messageLog.clear())),
              ]),

              // ----------------------------------------------------------------
              // WindowListener event log
              // ----------------------------------------------------------------
              _section('WINDOW EVENTS (WindowListener)', [
                _tile(
                  'Event log',
                  subtitle: _eventLog.isEmpty
                      ? '(no events yet - interact with the window)'
                      : _eventLog.take(8).join('\n'),
                ),
                _tile('clear log', onTap: () => setState(() => _eventLog.clear())),
              ]),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Window picker dialog
// ---------------------------------------------------------------------------

Future<int?> _showWindowPicker(BuildContext context, int currentId) async {
  final id = await showDialog<int>(
    context: context,
    builder: (ctx) => _WindowPickerDialog(excludeId: currentId),
  );
  return id;
}

Future<CloseMode?> _showModePicker(BuildContext context, CloseMode currentMode) async {
  final mode = await showDialog<CloseMode>(
    context: context,
    builder: (ctx) => _CloseModePickerDialog(excludeMode: currentMode),
  );
  return mode;
}

class _WindowPickerDialog extends StatelessWidget {
  const _WindowPickerDialog({required this.excludeId});

  final int excludeId;

  @override
  Widget build(BuildContext context) {
    final allIds = MultiViewDesktop.allWindowViewIds.where((id) => id != excludeId).toList()..sort();

    return AlertDialog(
      title: const Text('Select target window'),
      content: SizedBox(
        width: 280,
        child: allIds.isEmpty
            ? const Text('No other windows open. Open one first.')
            : ListView(
                shrinkWrap: true,
                children: allIds
                    .map((id) => ListTile(title: Text('Window $id'), onTap: () => Navigator.of(context).pop(id)))
                    .toList(),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

class _CloseModePickerDialog extends StatelessWidget {
  const _CloseModePickerDialog({required this.excludeMode});

  final CloseMode excludeMode;

  @override
  Widget build(BuildContext context) {
    final allModes = CloseMode.values.where((e) => e != excludeMode).toList();

    return AlertDialog(
      title: const Text('Select mode'),
      content: SizedBox(
        width: 280,
        child: ListView(
          shrinkWrap: true,
          children: allModes
              .map((mode) => ListTile(title: Text('Mode ${mode.name}'), onTap: () => Navigator.of(context).pop(mode)))
              .toList(),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

// ---------------------------------------------------------------------------
// Alignment grid widget
// ---------------------------------------------------------------------------

/// 3x3 grid for picking one of the nine standard `Alignment` values.
class _AlignmentGrid extends StatefulWidget {
  const _AlignmentGrid({required this.onSelected});

  final ValueChanged<Alignment> onSelected;

  @override
  State<_AlignmentGrid> createState() => _AlignmentGridState();
}

class _AlignmentGridState extends State<_AlignmentGrid> {
  Alignment? _active;

  static const _alignments = [
    (Alignment.topLeft, 'TL'),
    (Alignment.topCenter, 'TC'),
    (Alignment.topRight, 'TR'),
    (Alignment.centerLeft, 'CL'),
    (Alignment.center, 'C'),
    (Alignment.centerRight, 'CR'),
    (Alignment.bottomLeft, 'BL'),
    (Alignment.bottomCenter, 'BC'),
    (Alignment.bottomRight, 'BR'),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisExtent: 40,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 2.6,
        children: _alignments.map((entry) {
          final (alignment, label) = entry;
          final selected = _active == alignment;
          return FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: selected ? color.withValues(alpha: 0.2) : null,
              side: selected ? BorderSide(color: color) : null,
            ),
            onPressed: () {
              setState(() => _active = alignment);
              widget.onSelected(alignment);
            },
            child: Text(label, style: const TextStyle(fontSize: 12)),
          );
        }).toList(),
      ),
    );
  }
}

/// Lives in the popup child tree. Kept across ListView unmount of [PopupView]
/// because [PopupController] hosts that tree until [PopupController.close].
class _PopupDemoBody extends StatefulWidget {
  const _PopupDemoBody({required this.controller, required this.windowLabel, required this.animationOf});

  final PopupController controller;
  final String windowLabel;
  final AnimationSettings Function() animationOf;

  @override
  State<_PopupDemoBody> createState() => _PopupDemoBodyState();
}

class _PopupDemoBodyState extends State<_PopupDemoBody> {
  double _opacity = 1;
  bool _hasShadow = true;
  Color? _background;
  bool _ignoreMouse = false;

  PopupViewController get _view => widget.controller.viewController;

  void _setOpacity(double value) {
    setState(() => _opacity = value);
    _view.setOpacity(value);
  }

  void _setShadow(bool value) {
    setState(() => _hasShadow = value);
    _view.setHasShadow(value);
  }

  void _setBackground(Color? color) {
    setState(() => _background = color);
    _view.setBackgroundColor(color ?? const Color(0x00000000));
  }

  Future<void> _clickThroughBriefly() async {
    setState(() => _ignoreMouse = true);
    _view.setIgnoreMouseEvents(true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    _view.setIgnoreMouseEvents(false);
    setState(() => _ignoreMouse = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PopupDemoTimer(),
              const SizedBox(height: 8),
              Text(widget.windowLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'controller.viewController: opacity, shadow, background, click-through.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text('Opacity ${_opacity.toStringAsFixed(2)}', style: theme.textTheme.labelMedium),
              Slider(value: _opacity, min: 0.2, max: 1, onChanged: _setOpacity),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Native shadow'),
                value: _hasShadow,
                onChanged: _setShadow,
              ),
              if (!Platform.isMacOS) ...[
                Text('Background', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('clear'),
                      selected: _background == null,
                      onSelected: (_) => _setBackground(null),
                    ),
                    ChoiceChip(
                      label: const Text('amber'),
                      selected: _background == const Color(0x66FFC107),
                      onSelected: (_) => _setBackground(const Color(0x66FFC107)),
                    ),
                    ChoiceChip(
                      label: const Text('blue'),
                      selected: _background == const Color(0x662196F3),
                      onSelected: (_) => _setBackground(const Color(0x662196F3)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _ignoreMouse ? null : _clickThroughBriefly,
                child: Text(_ignoreMouse ? 'Click-through for 2s...' : 'Ignore mouse 2s'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.controller.close(animation: widget.animationOf()),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopupDemoTimer extends StatefulWidget {
  const _PopupDemoTimer();

  @override
  State<_PopupDemoTimer> createState() => _PopupDemoTimerState();
}

class _PopupDemoTimerState extends State<_PopupDemoTimer> {
  int _seconds = 120;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = _seconds < 1 ? 120 : _seconds - 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('Timer: $_seconds');
  }
}
