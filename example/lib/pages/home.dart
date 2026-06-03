// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:multiview_desktop/multiview_desktop.dart';

import '../utils/theme_config.dart';

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
      unawaited(
        MultiViewDesktop.setTitle(
          context,
          parentContext != null && parentContext.mounted
              ? 'Window $currentId, parent: ${MultiViewDesktop.getIdByContext(parentContext)}'
              : 'Window $currentId',
        ),
      );
      MultiViewDesktop.allViewsIdsNotifier.addListener(_viewListener);

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
    MultiViewDesktop.allViewsIdsNotifier.removeListener(_viewListener);
    _commSub?.cancel();
    _broadcastSub?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<T?> _mountedFuture<T>(
    FutureOr<T> Function(BuildContext) future,
    BuildContext context,
  ) async {
    if (!mounted) return null;
    return future(context);
  }

  Future<void> _refreshState() async {
    if (!mounted) return;
    final contextLocal = context;
    final hideTaskbar = await _mountedFuture(
      MultiViewDesktop.isHideAppTabFromTaskbar,
      contextLocal,
    );
    final fs = await _mountedFuture(
      MultiViewDesktop.isFullScreen,
      contextLocal,
    );
    final max = await _mountedFuture(
      MultiViewDesktop.isMaximized,
      contextLocal,
    );
    final top = await _mountedFuture(
      MultiViewDesktop.isAlwaysOnTop,
      contextLocal,
    );
    final res = await _mountedFuture(
      MultiViewDesktop.isResizable,
      contextLocal,
    );
    final mov = await _mountedFuture(MultiViewDesktop.isMovable, contextLocal);
    final mini = await _mountedFuture(
      MultiViewDesktop.isMinimizable,
      contextLocal,
    );
    final maxi = await _mountedFuture(
      MultiViewDesktop.isMaximizable,
      contextLocal,
    );
    final clos = await _mountedFuture(
      MultiViewDesktop.isClosable,
      contextLocal,
    );
    final prev = await _mountedFuture(
      MultiViewDesktop.isPreventClose,
      contextLocal,
    );
    final skip = await _mountedFuture(
      MultiViewDesktop.isHideFromCollection,
      contextLocal,
    );
    final op = await _mountedFuture(MultiViewDesktop.getOpacity, contextLocal);
    final visibleOnAllWorkspaces = await _mountedFuture(
      MultiViewDesktop.isVisibleOnAllWorkspaces,
      contextLocal,
    );
    final ignoreMouseEvents = await _mountedFuture(
      MultiViewDesktop.isIgnoreMouseEvents,
      contextLocal,
    );
    final shadow = await _mountedFuture(
      MultiViewDesktop.hasShadow,
      contextLocal,
    );
    final titleBarStyle = await _mountedFuture(
      MultiViewDesktop.getTitleBarStyle,
      contextLocal,
    );
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
      _visibleOnAllWorkspaces =
          visibleOnAllWorkspaces ?? _visibleOnAllWorkspaces;
      _titleBarHidden = titleBarStyle?.style == TitleBarStyle.hidden;
      _titleBarButtonVisibility =
          titleBarStyle?.buttonVisibility ?? _titleBarButtonVisibility;
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

    // Show a confirmation dialog. can accept (remove preventClose and
    // close the window) or decline (explicitly cancel a pending cascade close).
    if (_dialogKey.currentContext?.mounted ?? false) return;
    MultiViewDesktop.focus(context);
    final accept = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          key: _dialogKey,
          title: const Text('Close window?'),
          content: const Text('This window has preventClose enabled.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (accept == true) {
      await MultiViewDesktop.setPreventClose(context, false);
      await MultiViewDesktop.closeWindow(context);
    } else {
      await MultiViewDesktop.cancelCascadeClose(context);
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

  void _log(String entry) =>
      setState(() => _messageLog.insert(0, '[self] $entry'));

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

  Widget _tile(
    String title, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _switchTile(
    String title,
    bool value,
    Future<void> Function(bool) onChanged,
  ) {
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
    final windowId = MultiViewDesktop.getIdByContext(context);

    final isDark = themeConfig.themeMode == ThemeMode.dark;

    return SafeArea(
      child: Scaffold(
        appBar: _titleBarHidden
            ? null
            : AppBar(
                title: Text('Window $windowId'),
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
                  onChanged: (_) => themeConfig.setThemeMode(
                    isDark ? ThemeMode.light : ThemeMode.dark,
                  ),
                ),
              ),
              if (!Platform.isLinux)
                ListenableBuilder(
                  listenable: sharedConfig,
                  builder: (context, _) {
                    return _switchTile(
                      'hideAppFromTaskbar',
                      sharedConfig.isHideAppFromTaskbar,
                      (v) async {
                        await MultiViewDesktop.hideAppFromTaskbar(v);
                        if (v) await MultiViewDesktop.focus(context);
                        sharedConfig.isHideAppFromTaskbar =
                            await MultiViewDesktop.isHideAppFromTaskbar();
                      },
                    );
                  },
                ),
              ListenableBuilder(
                listenable: sharedConfig,
                builder: (context, _) {
                  return _tile(
                    'Set app closeMode',
                    subtitle: 'Current mode: ${sharedConfig.closeMode.name}',
                    onTap: () async {
                      final picked = await _showModePicker(
                        context,
                        sharedConfig.closeMode,
                      );
                      if (picked == null) return;
                      await MultiViewDesktop.setCloseMode(picked);
                      sharedConfig.closeMode = MultiViewDesktop.getCloseMode();
                    },
                  );
                },
              ),
              ListenableBuilder(
                listenable: sharedConfig,
                builder: (context, _) => _tile(
                  'SetCurrent as anchor (only if runMultiApp->config->generalParams->enableDynamicAnchor == false)',
                  subtitle: 'Current is ${MultiViewDesktop.getAnchorId()}',
                  onTap: () async {
                    final curr = currentId;
                    if (curr == null) return;
                    final isSuccess = await MultiViewDesktop.setAnchorId(curr);
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
                    const _SecondaryWindowRoot(),
                    options: WindowOptions(
                      size: const Size(1000, 700),
                      alignment: Alignment.center,
                    ),
                  );
                },
              ),
              _tile(
                'openChildWindow',
                subtitle: 'Open a new child window',
                onTap: () async {
                  final currId = MultiViewDesktop.getIdByContext(context);
                  openWindow(
                    const _SecondaryWindowRoot(),
                    options: WindowOptions(
                      size: const Size(1000, 700),
                      title: 'Window title parent $currId',
                    ),
                    parentContext: context,
                  );
                },
              ),
              if (windowId != 0)
                _tile(
                  'closeWindow',
                  subtitle: 'Close this window',
                  onTap: () => MultiViewDesktop.closeWindow(context),
                ),
              _tile('center', onTap: () => MultiViewDesktop.center(context)),
              _tile(
                'setAlignment',
                subtitle: 'Tap a position on the grid below',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _AlignmentGrid(
                  onSelected: (alignment) =>
                      MultiViewDesktop.setAlignment(context, alignment),
                ),
              ),
              _tile(
                'setSize',
                subtitle: '760 x 560',
                onTap: () =>
                    MultiViewDesktop.setSize(context, const Size(760, 560)),
              ),
              _tile(
                'setTitle',
                subtitle: 'Window $windowId (demo)',
                onTap: () => MultiViewDesktop.setTitle(
                  context,
                  'Window $windowId (demo)',
                ),
              ),
              _tile(
                'getBounds',
                onTap: () async {
                  final b = await MultiViewDesktop.getBounds(context);
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
              _switchTile('titleBarStyle hidden', _titleBarHidden, (v) async {
                await MultiViewDesktop.setTitleBarStyle(
                  context,
                  v ? TitleBarStyle.hidden : TitleBarStyle.normal,
                  windowButtonVisibility: !_titleBarButtonVisibility,
                );
              }),
              if (!Platform.isWindows)
                _switchTile(
                  'titleBarButtonVisibility',
                  !_titleBarButtonVisibility,
                  (v) async {
                    await MultiViewDesktop.setTitleBarStyle(
                      context,
                      _titleBarHidden
                          ? TitleBarStyle.hidden
                          : TitleBarStyle.normal,
                      windowButtonVisibility: v,
                    );
                  },
                ),
              _tile(
                'setAsFrameless',
                subtitle: 'Remove frame entirely',
                onTap: () async {
                  await MultiViewDesktop.setAsFrameless(context);
                  await _refreshState();
                },
              ),
            ]),

            // ----------------------------------------------------------------
            // Visibility states
            // ----------------------------------------------------------------
            _section('VISIBILITY', [
              _switchTile(
                'fullScreen',
                _isFullScreen,
                (v) => MultiViewDesktop.setFullScreen(context, v),
              ),
              _switchTile(
                'maximized',
                _isMaximized,
                (v) => v
                    ? MultiViewDesktop.maximize(context)
                    : MultiViewDesktop.unmaximize(context),
              ),
              _tile(
                'minimize',
                onTap: () => MultiViewDesktop.minimize(context),
              ),
              _switchTile(
                'alwaysOnTop',
                _isAlwaysOnTop,
                (v) => MultiViewDesktop.setAlwaysOnTop(context, v),
              ),
              if (Platform.isMacOS)
                _switchTile(
                  'hideFromCollection',
                  _isHideFromCollection,
                  (v) => MultiViewDesktop.hideFromCollection(context, v),
                ),
              if (Platform.isWindows)
                _switchTile(
                  'hideCurrentTabFromTaskbar',
                  _isHideFromTaskBar,
                  (v) =>
                      MultiViewDesktop.hideCurrentAppTabFromTaskbar(context, v),
                ),
              if (Platform.isMacOS)
                _switchTile(
                  'visibleOnAllWorkspaces',
                  _visibleOnAllWorkspaces,
                  (v) => MultiViewDesktop.setVisibleOnAllWorkspaces(context, v),
                ),
              if (!Platform.isLinux)
                _tile('progressBarExample', onTap: () => _progressBarExample()),
            ]),

            // ----------------------------------------------------------------
            // Capabilities
            // ----------------------------------------------------------------
            _section('WINDOW CAPABILITIES', [
              _switchTile(
                'resizable',
                _isResizable,
                (v) => MultiViewDesktop.setResizable(context, v),
              ),
              if (Platform.isMacOS)
                _switchTile(
                  'movable',
                  _isMovable,
                  (v) => MultiViewDesktop.setMovable(context, v),
                ),
              _switchTile(
                'minimizable',
                _isMinimizable,
                (v) => MultiViewDesktop.setMinimizable(context, v),
              ),
              if (!Platform.isLinux)
                _switchTile(
                  'maximizable',
                  _isMaximizable,
                  (v) => MultiViewDesktop.setMaximizable(context, v),
                ),
              _switchTile(
                'closable',
                _isClosable,
                (v) => MultiViewDesktop.setClosable(context, v),
              ),
              _switchTile('ignoreMouseEvents', _ignoreMouseEvents, (v) async {
                await MultiViewDesktop.setIgnoreMouseEvents(
                  context,
                  v,
                  mouseMoveEvents: false,
                );
                if (!v) return;
                Future.delayed(
                  Duration(seconds: 5),
                  () => MultiViewDesktop.setIgnoreMouseEvents(context, false),
                );
              }),
              _switchTile(
                'preventClose',
                _isPreventClose,
                (v) async => await MultiViewDesktop.setPreventClose(context, v),
              ),
            ]),

            // ----------------------------------------------------------------
            // Appearance
            // ----------------------------------------------------------------
            _section('APPEARANCE', [
              if (Platform.isMacOS)
                _switchTile(
                  'hasShadow',
                  _hasShadow,
                  (v) => MultiViewDesktop.setHasShadow(context, v),
                ),
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
                      MultiViewDesktop.setOpacity(context, v);
                    },
                  ),
                ),
              ),
              _tile(
                'setBackgroundColor',
                subtitle: 'Set window background transparent',
                onTap: () => MultiViewDesktop.setBackgroundColor(
                  context,
                  Colors.transparent,
                ),
              ),
              _tile(
                'Pop up menu',
                onTap: () => MultiViewDesktop.popUpWindowMenu(context),
              ),
            ]),

            // ----------------------------------------------------------------
            // WindowCommunicator
            // ----------------------------------------------------------------
            _section('WINDOW COMMUNICATOR', [
              _tile(
                'broadcast to all windows',
                subtitle: '"${_msgController.text}"',
                onTap: () {
                  MultiViewDesktop.communicator.broadcast({
                    'from': windowId,
                    'text': _msgController.text,
                  });
                },
              ),
              _tile(
                'send to specific window',
                subtitle: _targetViewId != null
                    ? 'target: window $_targetViewId'
                    : 'tap to pick target window',
                onTap: () async {
                  final picked = await _showWindowPicker(context, windowId);
                  if (picked == null) return;
                  setState(() => _targetViewId = picked);
                  MultiViewDesktop.communicator.send(picked, {
                    'from': windowId,
                    'text': _msgController.text,
                  });
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                subtitle: _messageLog.isEmpty
                    ? '(no messages yet)'
                    : _messageLog.take(6).join('\n'),
              ),
              _tile(
                'clear log',
                onTap: () => setState(() => _messageLog.clear()),
              ),
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
              _tile(
                'clear log',
                onTap: () => setState(() => _eventLog.clear()),
              ),
            ]),

            const SizedBox(height: 32),
          ],
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

Future<CloseMode?> _showModePicker(
  BuildContext context,
  CloseMode currentMode,
) async {
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
    final allIds =
        MultiViewDesktop.allViewsIds.where((id) => id != excludeId).toList()
          ..sort();

    return AlertDialog(
      title: const Text('Select target window'),
      content: SizedBox(
        width: 280,
        child: allIds.isEmpty
            ? const Text('No other windows open. Open one first.')
            : ListView(
                shrinkWrap: true,
                children: allIds
                    .map(
                      (id) => ListTile(
                        title: Text('Window $id'),
                        onTap: () => Navigator.of(context).pop(id),
                      ),
                    )
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
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
              .map(
                (mode) => ListTile(
                  title: Text('Mode ${mode.name}'),
                  onTap: () => Navigator.of(context).pop(mode),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
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
  const _SecondaryWindowRoot();

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
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == msg['value'],
        orElse: () => ThemeMode.light,
      );
      MultiViewDesktop.setBrightness(
        context,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => MultiViewDesktop.setBrightness(
        context,
        themeConfig.themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
