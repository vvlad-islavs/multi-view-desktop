// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
  bool _isSkipTaskbar = false;
  double _opacity = 1.0;
  bool _hasShadow = true;
  bool _titleBarHidden = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshState();
      debugPrint('Init homePage');
      MultiViewDesktop.addListener(context, this);
      final myId = MultiViewDesktop.getCurrentId(context);

      _commSub = WindowCommunicator.listen(myId).listen((msg) {
        if (!mounted) return;
        setState(() => _messageLog.insert(0, '[direct] $msg'));
      });

      _broadcastSub = WindowCommunicator.onBroadcast.listen((msg) {
        if (!mounted) return;
        // Theme changes are handled separately.
        if (msg is Map && msg['type'] == 'themeMode') return;
        setState(() => _messageLog.insert(0, '[broadcast] $msg'));
      });
    });
  }

  @override
  void dispose() {
    _commSub?.cancel();
    _broadcastSub?.cancel();
    _msgController.dispose();
    try {
      MultiViewDesktop.removeListener(context, this);
    } catch (_) {}
    super.dispose();
  }

  Future<T?> _mountedFuture<T>(FutureOr<T> Function(BuildContext) future, BuildContext context) async {
    if (!mounted) return null;
    return  future(context);
  }

  Future<void> _refreshState() async {
    if (!mounted) return;
    final contextLocal = context;
    final fs = await _mountedFuture(MultiViewDesktop.isFullScreen, contextLocal);
    final max = await _mountedFuture(MultiViewDesktop.isMaximized, contextLocal);
    final top = await _mountedFuture(MultiViewDesktop.isAlwaysOnTop, contextLocal);
    final res = await _mountedFuture(MultiViewDesktop.isResizable, contextLocal);
    final mov = await _mountedFuture(MultiViewDesktop.isMovable, contextLocal);
    final mini = await _mountedFuture(MultiViewDesktop.isMinimizable, contextLocal);
    final maxi = await _mountedFuture(MultiViewDesktop.isMaximizable, contextLocal);
    final clos = await _mountedFuture(MultiViewDesktop.isClosable, contextLocal);
    final prev = await _mountedFuture(MultiViewDesktop.isPreventClose, contextLocal);
    final skip = await _mountedFuture(MultiViewDesktop.isSkipTaskbar, contextLocal);
    final op = await _mountedFuture(MultiViewDesktop.getOpacity, contextLocal);
    final shadow = await _mountedFuture(MultiViewDesktop.hasShadow, contextLocal);
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
      _isSkipTaskbar = skip ?? _isSkipTaskbar;
      _opacity = op ?? _opacity;
      _hasShadow = shadow ?? _hasShadow;
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
    setState(() => _eventLog.insert(0, 'close (blocked by preventClose)'));

    // Show a confirmation dialog. The user can accept (remove preventClose and
    // close the window) or decline (explicitly cancel a pending cascade close).
    if (_dialogKey.currentContext?.mounted ?? false) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          key: _dialogKey,
          title: const Text('Close window?'),
          content: const Text('This window has preventClose enabled.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close')),
          ],
        );
      },
    );

    if (!mounted) return;
    if (accept == true) {
      await MultiViewDesktop.setPreventClose(context, false);
      // if (MultiViewDesktop.getCurrentId(context) == 1) {
        // await MultiViewDesktop.closeAllWindowsCascade();
        // await MultiViewDesktop.closeWindow(context);
      // } else {
        await MultiViewDesktop.closeWindow(context);
      // }
    } else {
      // Explicitly cancel any pending cascade close so the main window stays
      // open and no stale completers fire later.
      // MultiViewDesktop.cancelCascadeClose(context);
    }
  }

  // Helpers ------------------------------------------------------------------

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
    final windowId = MultiViewDesktop.getCurrentId(context);
    final isDark = themeConfig.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: _titleBarHidden
          ? null
          : AppBar(title: Text('Window $windowId'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
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
                onChanged: (_) {
                  themeConfig.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
                  // Brightness is applied by each window via its own listener.
                  final mode = themeConfig.themeMode;
                  MultiViewDesktop.setBrightness(context, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
                },
              ),
            ),
          ]),

          // ----------------------------------------------------------------
          // Window management
          // ----------------------------------------------------------------
          _section('WINDOW MANAGEMENT', [
            _tile(
              'addWindow',
              subtitle: 'Open a new OS window (same engine)',
              onTap: () => addWindow(
                const _SecondaryWindowRoot(),
                options: const WindowOptions(size: Size(760, 560), center: true),
              ),
            ),
            if (windowId != 0)
              _tile('closeWindow', subtitle: 'Close this window', onTap: () => MultiViewDesktop.closeWindow(context)),
            _tile('center', onTap: () => MultiViewDesktop.center(context)),
            _tile(
              'setSize',
              subtitle: '760 x 560',
              onTap: () => MultiViewDesktop.setSize(context, const Size(760, 560)),
            ),
            _tile(
              'setTitle',
              subtitle: 'Window $windowId (demo)',
              onTap: () => MultiViewDesktop.setTitle(context, 'Window $windowId (demo)'),
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
              await MultiViewDesktop.setTitleBarStyle(context, v ? TitleBarStyle.hidden : TitleBarStyle.normal);
              setState(() => _titleBarHidden = v);
            }),
            _tile(
              'setAsFrameless',
              subtitle: 'Remove frame entirely',
              onTap: () {
                MultiViewDesktop.setAsFrameless(context);
                setState(() => _titleBarHidden = true);
              },
            ),
          ]),

          // ----------------------------------------------------------------
          // Visibility states
          // ----------------------------------------------------------------
          _section('VISIBILITY', [
            _switchTile('fullScreen', _isFullScreen, (v) => MultiViewDesktop.setFullScreen(context, v)),
            _switchTile(
              'maximized',
              _isMaximized,
              (v) => v ? MultiViewDesktop.maximize(context) : MultiViewDesktop.unmaximize(context),
            ),
            if (!Platform.isMacOS) _tile('minimize', onTap: () => MultiViewDesktop.minimize(context)),
            _switchTile('alwaysOnTop', _isAlwaysOnTop, (v) => MultiViewDesktop.setAlwaysOnTop(context, v)),
            _switchTile('skipTaskbar', _isSkipTaskbar, (v) => MultiViewDesktop.setSkipTaskbar(context, v)),
          ]),

          // ----------------------------------------------------------------
          // Capabilities
          // ----------------------------------------------------------------
          _section('WINDOW CAPABILITIES', [
            _switchTile('resizable', _isResizable, (v) => MultiViewDesktop.setResizable(context, v)),
            if (Platform.isMacOS) _switchTile('movable', _isMovable, (v) => MultiViewDesktop.setMovable(context, v)),
            _switchTile('minimizable', _isMinimizable, (v) => MultiViewDesktop.setMinimizable(context, v)),
            _switchTile('maximizable', _isMaximizable, (v) => MultiViewDesktop.setMaximizable(context, v)),
            _switchTile('closable', _isClosable, (v) => MultiViewDesktop.setClosable(context, v)),
            _switchTile('preventClose', _isPreventClose, (v) async {
              await MultiViewDesktop.setPreventClose(context, v);
              // When disabling preventClose, reset confirmClose so the
              // next closeWindow() goes through the confirm-close flow.
              // if (!v) await MultiViewDesktop.confirmClose(context, confirmed: false);
            }),
          ]),

          // ----------------------------------------------------------------
          // Appearance
          // ----------------------------------------------------------------
          _section('APPEARANCE', [
            if (Platform.isMacOS)
              _switchTile('hasShadow', _hasShadow, (v) => MultiViewDesktop.setHasShadow(context, v)),
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
              onTap: () => MultiViewDesktop.setBackgroundColor(context, Colors.transparent),
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
                WindowCommunicator.broadcast({'from': windowId, 'text': _msgController.text});
              },
            ),
            _tile(
              'send to specific window',
              subtitle: _targetViewId != null ? 'target: window $_targetViewId' : 'tap to pick target window',
              onTap: () async {
                final picked = await _showWindowPicker(context, windowId);
                if (picked == null) return;
                setState(() => _targetViewId = picked);
                WindowCommunicator.send(picked, {'from': windowId, 'text': _msgController.text});
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
            _tile('Message log', subtitle: _messageLog.isEmpty ? '(no messages yet)' : _messageLog.take(6).join('\n')),
            _tile('clear log', onTap: () => setState(() => _messageLog.clear())),
          ]),

          // ----------------------------------------------------------------
          // WindowListener event log
          // ----------------------------------------------------------------
          _section('WINDOW EVENTS (WindowListener)', [
            _tile(
              'Event log',
              subtitle: _eventLog.isEmpty ? '(no events yet - interact with the window)' : _eventLog.take(8).join('\n'),
            ),
            _tile('clear log', onTap: () => setState(() => _eventLog.clear())),
          ]),

          const SizedBox(height: 32),
        ],
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

class _WindowPickerDialog extends StatelessWidget {
  const _WindowPickerDialog({required this.excludeId});

  final int excludeId;

  @override
  Widget build(BuildContext context) {
    // All open view IDs are accessible via PlatformDispatcher since we share
    // one engine.  We filter out the calling window.
    final allIds = ui.PlatformDispatcher.instance.views.map((v) => v.viewId).where((id) => id != excludeId && id != 0).toList()
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
                    .map((id) => ListTile(title: Text('Window $id'), onTap: () => Navigator.of(context).pop(id)))
                    .toList(),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
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
    WindowCommunicator.onBroadcast.listen((msg) {
      if (msg is! Map) return;
      if (msg['type'] != 'themeMode') return;
      if (!mounted) return;
      final mode = ThemeMode.values.firstWhere((m) => m.name == msg['value'], orElse: () => ThemeMode.light);
      MultiViewDesktop.setBrightness(context, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    });
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
