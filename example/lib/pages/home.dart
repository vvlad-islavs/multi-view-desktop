// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:multiview_desktop/multiview_desktop.dart';

import '../utils/theme_config.dart';
import 'alert_view_dialog.dart';

// ---------------------------------------------------------------------------
// HomePage
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  final GlobalKey _dialogKey = GlobalKey();
  final GlobalKey _modellessDialogKey = GlobalKey();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _refreshState();
      final parentContext = ParentWindowScope.of(context).parentContext;
      final currMvd = MultiViewDesktop.of(context);
      final windowInfo = currMvd.getWindowInfo();
      unawaited(
        currMvd.setTitle(
          parentContext != null && parentContext.mounted
              ? '${windowInfo.isDialog ? 'Dialog' : 'Window'} $currentId, parent: ${MultiViewDesktop.getIdByContext(parentContext)}'
              : 'Window $currentId',
        ),
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
    debugPrint('allViews from notif: ${MultiViewDesktop.allWindowIdsNotifier.value}');
    sharedConfig.anchorId = MultiViewDesktop.getAnchorId();
  }

  @override
  void dispose() {
    MultiViewDesktop.allWindowIdsNotifier.removeListener(_viewListener);
    _commSub?.cancel();
    _broadcastSub?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<T?> _safeFuture<T>(Future<T> Function() future) async {
    if (!mounted) return null;
    return future();
  }

  Future<void> _refreshState() async {
    if (!mounted) return;
    final win = MultiViewDesktop.of(context);
    final hideTaskbar = await _safeFuture(win.isHideAppTabFromTaskbar);
    final fs = await _safeFuture(win.isFullScreen);
    final max = await _safeFuture(win.isMaximized);
    final top = await _safeFuture(win.isAlwaysOnTop);
    final res = await _safeFuture(win.isResizable);
    final mov = await _safeFuture(win.isMovable);
    final mini = await _safeFuture(win.isMinimizable);
    final maxi = await _safeFuture(win.isMaximizable);
    final clos = await _safeFuture(win.isClosable);
    final prev = await _safeFuture(win.isPreventClose);
    final skip = await _safeFuture(win.isHideFromCollection);
    final op = await _safeFuture(win.getOpacity);
    final visibleOnAllWorkspaces = await _safeFuture(win.isVisibleOnAllWorkspaces);
    final ignoreMouseEvents = await _safeFuture(win.isIgnoreMouseEvents);
    final shadow = await _safeFuture(win.hasShadow);
    final titleBarStyle = await _safeFuture(win.getTitleBarStyle);
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
  void onWindowClose() async {
    if (!mounted) return;
    final win = MultiViewDesktop.of(context);
    win.focus();
    // Show a confirmation dialog. can accept (remove preventClose and
    // close the window) or decline (explicitly cancel a pending cascade close).
    if (_dialogKey.currentContext?.mounted ?? false) return;
    final accept = await context.openDialog<bool?>(
      (ctx, id) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: AlertViewDialog(
            key: _dialogKey,
            title: 'Close window?',
            content: 'This window has preventClose enabled.',
            actions: [
              TextButton(onPressed: () => ctx.closeDialog(), child: const Text('Cancel')),
              TextButton(onPressed: () => ctx.closeDialog<bool>(true), child: const Text('Close')),
            ],
          ),
        );
      },
      options: DialogOptions(
        size: const Size(340, 220),
        title: 'Prevent close dialog',
        modal: false,
        isResizable: false,
        alwaysOnTop: false,
        blockParentCloseAndFocus: true,
        showOnInit: true,
      ),
    );

    if (!mounted) return;
    if (accept == true) {
      await win.setPreventClose(false);
      await win.closeWindow();
    } else {
      await win.cancelCascadeClose();
    }
  }

  // Helpers ------------------------------------------------------------------

  void _progressBarExample() async {
    final progressLimit = 100;
    final progressStep = 5;
    debugPrint('Progress example started');
    for (int i = 0; i < progressLimit; i += progressStep) {
      final progress = i / 100;
      debugPrint('Progress: $progress');
      await MultiViewDesktop.setProgressBar(progress);
      await Future.delayed(Duration(milliseconds: 100));
    }
    debugPrint('Progress completed');
    await Future.delayed(const Duration(milliseconds: 1000));
    await MultiViewDesktop.setProgressBar(-1);
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

  Widget _switchTile(String title, bool value, Future<void> Function(bool) onChanged) {
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

    final isDark = themeConfig.themeMode == ThemeMode.dark;

    return SafeArea(
      child: DialogModalLayer(
        showBarrierForNotModalDialog: true,
        child: Scaffold(
          appBar: _titleBarHidden
              ? null
              : AppBar(
                  title: FutureBuilder(
                    future: MultiViewDesktop.of(context).getTitle(),
                    builder: (ctx, snap) {
                      return snap.connectionState == ConnectionState.waiting
                          ? SizedBox.shrink()
                          : Text(snap.data ?? '');
                    },
                  ),
                  backgroundColor: Theme.of(context).colorScheme.inversePrimary,
                ),
          body: ListView(
            children: [
              // ----------------------------------------------------------------
              // Theme (shared across all windows - no IPC needed!)
              // ----------------------------------------------------------------
              _section('SHARED STATE (same isolate)', [
                _tile(
                  'ThemeMode',
                  subtitle: themeConfig.themeMode.name,
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) => themeConfig.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
                  ),
                ),
                if (!Platform.isLinux)
                  ListenableBuilder(
                    listenable: sharedConfig,
                    builder: (context, _) {
                      return _switchTile('hideAppFromTaskbar', sharedConfig.isHideAppFromTaskbar, (v) async {
                        await MultiViewDesktop.hideAppFromTaskbar(v);
                        if (v) await MultiViewDesktop.of(context).focus();
                        sharedConfig.isHideAppFromTaskbar = await MultiViewDesktop.isHideAppFromTaskbar();
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
                        await MultiViewDesktop.setCloseMode(picked);
                        sharedConfig.closeMode = MultiViewDesktop.getCloseMode();
                      },
                    );
                  },
                ),
                if (ParentWindowScope.of(context).parentContext == null)
                  ListenableBuilder(
                    listenable: sharedConfig,
                    builder: (context, _) => _tile(
                      'SetCurrent as anchor (only if runMultiApp->config->generalParams->enableDynamicAnchor == false)',
                      subtitle: 'Current is ${MultiViewDesktop.getAnchorId()}',
                      onTap: () async {
                        final curr = currentId;
                        if (curr == null) return;
                        await MultiViewDesktop.setAnchorId(curr);
                        sharedConfig.anchorId = MultiViewDesktop.getAnchorId();
                      },
                    ),
                  ),
              ]),
              // ----------------------------------------------------------------
              // Window management
              // ----------------------------------------------------------------
              _section('WINDOW MANAGEMENT', [
                _tile(
                  'openWindow',
                  subtitle: 'Open a new window',
                  onTap: () async {
                    openWindow(
                      (ctx, viewId) => const _SecondaryWindowRoot(),
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
                          return const _SecondaryWindowRoot();
                        },
                        options: WindowOptions(size: const Size(1000, 700), title: ' ', alignment: Alignment.center),
                        parentContext: context,
                      );
                    },
                  ),
                  _tile(
                    'openDialog',
                    subtitle: 'Open a new child window',
                    onTap: () async {
                      // if (_modellessDialogKey.currentContext?.mounted ?? false) return;
                      void doOnBuilt(int id) async {
                        final dialogView = MultiViewDesktop.fromId(id);
                        await dialogView.setDialogAlignment(Alignment.topLeft);
                        final bounds = await dialogView.getBounds();
                        await dialogView.setPosition(Offset(bounds.left, bounds.top + 38));
                        await dialogView.show();
                      }

                      await openDialog(
                        (ctx, viewId) {
                          // doOnBuilt(viewId);
                          return _SecondaryWindowRoot();
                        },
                        options: DialogOptions(
                          size: const Size(450, 300),
                          title: ' ',
                          modal: false,
                          isResizable: false,
                          alwaysOnTop: true,
                          blockParentCloseAndFocus: false,
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
                          return const _SecondaryWindowRoot();
                        },
                        options: DialogOptions(
                          size: const Size(450, 300),
                          title: ' ',
                          isResizable: false,
                          modal: true,
                          blockParentCloseAndFocus: false,
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
                if (!Platform.isLinux && !windowInfo.isModal)
                  _tile('center', onTap: () => MultiViewDesktop.of(context).center()),
                if (!Platform.isLinux && !windowInfo.isModal) ...[
                  _tile('setAlignment', subtitle: 'Tap a position on the grid below'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _AlignmentGrid(
                      onSelected: (alignment) => MultiViewDesktop.of(context).setAlignment(alignment),
                    ),
                  ),
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
                  subtitle: '760 x 560',
                  onTap: () => MultiViewDesktop.of(context).setSize(const Size(760, 560)),
                ),
                _tile(
                  'setTitle',
                  subtitle: 'Window $windowId (demo)',
                  onTap: () => MultiViewDesktop.of(context).setTitle('Window $windowId (demo)'),
                ),
                _tile(
                  'getBounds',
                  onTap: () async {
                    final b = await MultiViewDesktop.of(context).getBounds();
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
              if (!windowInfo.isModal)
                _section('TITLE BAR', [
                  _switchTile('titleBarStyle hidden', _titleBarHidden, (v) async {
                    await MultiViewDesktop.of(context).setTitleBarStyle(
                      v ? TitleBarStyle.hidden : TitleBarStyle.normal,
                      closeVisibility: _titleBarButtonVisibility,
                      minimizeVisibility: _titleBarButtonVisibility && !windowInfo.isDialog,
                      maximizeVisibility: _titleBarButtonVisibility && !windowInfo.isDialog,
                    );
                  }),
                  if (Platform.isMacOS)
                    _switchTile('titleBarButtonVisibility', _titleBarButtonVisibility, (v) async {
                      await MultiViewDesktop.of(context).setTitleBarStyle(
                        _titleBarHidden ? TitleBarStyle.hidden : TitleBarStyle.normal,
                        closeVisibility: v,
                        minimizeVisibility: v && !windowInfo.isDialog,
                        maximizeVisibility: v && !windowInfo.isDialog,
                      );
                    }),
                  _tile(
                    'setAsFrameless',
                    subtitle: 'Remove frame entirely',
                    onTap: () async {
                      await MultiViewDesktop.of(context).setAsFrameless();
                      await _refreshState();
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
                if (!Platform.isLinux)
                  _switchTile('alwaysOnTop', _isAlwaysOnTop, (v) => MultiViewDesktop.of(context).setAlwaysOnTop(v)),
                if (Platform.isMacOS && !windowInfo.isModal)
                  _switchTile(
                    'hideFromCollection',
                    _isHideFromCollection,
                    (v) => MultiViewDesktop.of(context).hideFromCollection(v),
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
                    (v) => MultiViewDesktop.of(context).setVisibleOnAllWorkspaces(v),
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
                _switchTile('ignoreMouseEvents', _ignoreMouseEvents, (v) async {
                  final win = MultiViewDesktop.of(context);
                  await win.setIgnoreMouseEvents(v, mouseMoveEvents: false);
                  if (!v) return;
                  Future.delayed(Duration(seconds: 5), () => win.setIgnoreMouseEvents(false));
                }),
                if (!windowInfo.isDialog)
                  _switchTile(
                    'preventClose',
                    _isPreventClose,
                    (v) async => await MultiViewDesktop.of(context).setPreventClose(v),
                  ),
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
                      min: 0.2,
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

/// 3x3 grid for picking one of the nine standard [Alignment] values.
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

// ---------------------------------------------------------------------------
// Secondary window root
// ---------------------------------------------------------------------------

/// The root widget shown in every secondary window.
///
/// Wraps [HomePage] in its own [MaterialApp] so it has an independent
/// navigator and theme (but shares all Dart memory with the main window).
class _SecondaryWindowRoot extends StatefulWidget {
  const _SecondaryWindowRoot({super.key});

  @override
  State<_SecondaryWindowRoot> createState() => _SecondaryWindowRootState();
}

class _SecondaryWindowRootState extends State<_SecondaryWindowRoot> {
  @override
  void initState() {
    super.initState();
    themeConfig.addListener(_onThemeChanged);
    // Also listen for broadcast theme changes to update native brightness.
    MultiViewDesktop.communicator.onBroadcast.listen((msg) {
      if (msg is! Map) return;
      if (msg['type'] != 'themeMode') return;
      if (!mounted) return;
      final mode = ThemeMode.values.firstWhere((m) => m.name == msg['value'], orElse: () => ThemeMode.light);
      MultiViewDesktop.of(context).setBrightness(mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => MultiViewDesktop.of(
        context,
      ).setBrightness(themeConfig.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light),
    );
  }

  @override
  void dispose() {
    themeConfig.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeConfig.themeMode,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
