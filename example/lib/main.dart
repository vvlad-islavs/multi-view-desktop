import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:tray_manager/tray_manager.dart';
import 'e2e/e2e.dart';
import 'pages/home.dart';
import 'l10n/example_localizations.dart';
import 'theme/app_themes.dart';
import 'utils/theme_config.dart';

Future<void> initSystemTray() async {
  String path = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png';

  await trayManager.setIcon(path);
  if (!Platform.isLinux) {
    await trayManager.setToolTip('toolTip');
  }

  // create context menu
  final Menu menu = Menu(
    items: [
      if (MultiViewDesktop.allWindowViewIds.isNotEmpty) ...[
        MenuItem(label: 'Hide first', key: 'hide_window'),
        MenuItem(label: 'Show first', key: 'show_window'),
      ],
      if (MultiViewDesktop.allWindowViewIds.isEmpty) MenuItem(label: 'Open', key: 'open_window'),
      MenuItem(label: 'Exit', key: 'exit_app'),
    ],
  );

  await trayManager.setContextMenu(menu);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional surface-layer E2E harness (Python scripts). Disabled unless
  // `--dart-define=MVD_E2E=true`.
  final e2eStore = E2eContextStore();
  await maybeStartE2eHarness(handlers: buildExampleE2eHandlers(ExampleE2eHandlerDeps(contexts: e2eStore)));

  runMultiApp(
    home: (globalScopeContext, id) {
      final mvd = MultiViewDesktop.fromId(id);
      WidgetsBinding.instance.endOfFrame.then((_) => mvd.completeShow());
      // force anim for init window for example
      mvd.setForceAnimation(
        ViewAnimationType.createWindow,
        AnimationSettings(duration: Duration(milliseconds: 400), curve: Curves.linear, fps: 120),
      );
      // mvd.setForceAnimation(
      //   ViewAnimationType.closeWindow,
      //   AnimationSettings(duration: Duration(seconds: 1), curve: Curves.linear, fps: 120),
      // );
      // E2eHost must sit *inside* MaterialApp (see MainWindowRoot) so overlay /
      // MaterialLocalizations work for primary-window RPC.
      return MainWindowRoot(e2eStore: e2eEnabledFromEnvironment() ? e2eStore : null);
    },
    globalScope: (child) {
      //any providers...
      return child;
    },
    config: MultiAppConfig(
      fileLogParams: const LogParams(enable: true, sizeKb: 1024 * 10),
      generalParams: MultiPlatformParams(
        animation: ViewAnimationConfig.all(modalFadeInOnOpen: true, modalFadeOutOnClose: true),
        enableDynamicAnchor: false,
        closeMode: CloseMode.softCascade,
        closeAppAfterLastWindowClosed: true,
        menuItems: [
          TaskbarMenuItem(
            title: 'Open new window',
            iconAsset: 'assets/icons/new_window.png',
            onPressed: () => openWindow((ctx, id) => HomePage()),
          ),
        ],
      ),
      macosParams: MacosPlatformParams(
        // Defaults match example dock behavior; cascade-exit E2E overrides via
        // MVD_E2E_CLOSE_APP_AFTER_LAST / MVD_E2E_SAVE_LAST_WINDOW.
        saveLastWindowToReopen: e2eSaveLastWindowToReopenFromEnvironment(),
        onTerminate: () async {
          // do something before terminate
          // for example soft close instead of destroy
          final isAllClosed = await MultiViewDesktop.closeApp(closeMode: CloseMode.softCascade);
          // destroy app if all closed
          return isAllClosed;
        },
        onTaskbarTap: () async {
          // do something when tap taskbar icon
          // for example two ways:
          // 1) emptyViews - open new window
          // 2) notEmptyViews - focus one by one for all views
          final allWindows = MultiViewDesktop.allWindowViewIds;
          if (allWindows.length <= 1) {
            // when saveLastWindowToReopen == true last window hides instead of close and stay in stack
            // so you should to detect it
            final lastView = allWindows.isNotEmpty ? MultiViewDesktop.fromId(allWindows.first) : null;
            if (!(lastView?.isVisible() ?? true)) {
              // if saveLastWindowToReopen == true and last window is hide, a tap on taskbar will be open last view and focus it.
              // don't focus secondly at this time else focus may be broken, so just return
              return;
            }
            if (allWindows.isEmpty) {
              openWindow((ctx, id) => HomePage());
              return;
            }
          }

          int idWithFocus = -1;
          for (final id in allWindows) {
            final mvd = MultiViewDesktop.fromId(id);
            if (mvd.isFocused()) {
              idWithFocus = id;
              break;
            }
          }
          final nextFocusId = allWindows.firstWhere((e) => e > idWithFocus, orElse: () => allWindows.first);
          if (allWindows.length == 1 && idWithFocus != -1) {
            return;
          }
          MultiViewDesktop.fromId(nextFocusId).focus();
          return;
        },
      ),
      globalWindowOptions: WindowOptions(
        minimumSize: Size(1000, 700),
        // maximumSize: Size(1400, 900),
        size: Size(1000, 700),
        alignment: Alignment.center,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
        showOnInit: true,
        fullScreen: false,
        title: 'Window N...',
        backgroundColor: Colors.transparent,
      ),
      mainWindowOptions: WindowOptions(
        minimumSize: Size(1000, 700),
        size: Size(1200, 800),
        alignment: Alignment.center,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
        maximize: false,
        showOnInit: false,
        fullScreen: false,
        title: 'Window 1',
        backgroundColor: Colors.transparent,
      ),
      globalDialogOptions: DialogOptions(modal: false, windowButtonVisibility: true),
      observers: [AppWindowObserver()],
    ),
  );
}

class AppWindowObserver extends WindowObserver {
  @override
  void onWindowOpened(int viewId, {int? parentViewId}) {
    log('window $viewId opened, parent $parentViewId', name: 'MVD');
    initSystemTray();
  }

  @override
  void onWindowClosed(int viewId) {
    log('window $viewId closed', name: 'MVD');
    initSystemTray();
  }

  @override
  void onDialogClose(int dialogId) {
    log('Dialog $dialogId closed', name: 'MVD');
  }

  @override
  void onDialogOpened(int dialogId, {required int parentViewId}) {
    log('dialog $dialogId opened, parent $parentViewId', name: 'MVD');
  }

  @override
  void onAnchorChanged(int? previousViewId, int? newViewId) {
    log('anchor: $previousViewId -> $newViewId', name: 'MVD');
  }

  @override
  void onWindowEvent(int viewId, String eventName) {
    log('window event for view $viewId: $eventName', name: 'MVD');
  }

  @override
  void onDialogEvent(int viewId, String eventName) {
    log('dialog event for view $viewId: $eventName', name: 'MVD');
  }
}

// ---------------------------------------------------------------------------
// Root widget for the main window
// ---------------------------------------------------------------------------

/// Root widget for the initial (main) OS window.
///
/// Every secondary window opened via `openWindow` uses `_SecondaryWindowRoot`
/// which is defined inside pages/home.dart and shares the same `themeConfig`
/// singleton.
class MainWindowRoot extends StatefulWidget {
  const MainWindowRoot({super.key, this.e2eStore});

  /// When set, [HomePage] is wrapped so the primary view context is registered
  /// under MaterialApp (needed for overlay / popup E2E on the primary window).
  final E2eContextStore? e2eStore;

  @override
  State<MainWindowRoot> createState() => _MainWindowRootState();
}

class _MainWindowRootState extends State<MainWindowRoot> with TrayListener {
  @override
  void initState() {
    super.initState();

    themeConfig.addListener(_onThemeChanged);

    // MultiViewDesktop.communicator.onBroadcast.listen((msg) {
    //   if (msg is! Map) return;
    //   if (msg['type'] != 'themeMode') return;
    //   if (!mounted) return;
    //   final mode = ThemeMode.values.firstWhere((m) => m.name == msg['value'], orElse: () => ThemeMode.light);
    //   MultiViewDesktop.of(context).setBrightness(mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    // });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      MultiViewDesktop.setGlobalBrightness(
        themeConfig.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );

      sharedConfig.isHideAppFromTaskbar = MultiViewDesktop.isHideAppFromTaskbar();
      sharedConfig.closeMode = MultiViewDesktop.getCloseMode();
      sharedConfig.anchorId = MultiViewDesktop.getAnchorId();

      trayManager.addListener(this);
    });
  }

  @override
  void dispose() {
    // trayManager.removeListener(this);

    themeConfig.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void onTrayIconMouseDown() {
    // do something, for example pop up the menu
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    // do something
  }

  @override
  void onTrayIconRightMouseUp() {
    // do something
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final allViews = MultiViewDesktop.allWindowViewIds;
    if (allViews.isNotEmpty) {
      final mvd = MultiViewDesktop.fromId(MultiViewDesktop.allWindowViewIds.first);
      if (menuItem.key == 'show_window') {
        mvd.show();
      }
      if (menuItem.key == 'hide_window') {
        mvd.hide();
      }
    }
    if (menuItem.key == 'open_window' && allViews.isEmpty) {
      openWindow((ctx, id) => HomePage());
    }

    if (menuItem.key == 'exit_app') {
      // first step - soft close all windows. Close app if genParams->closeAppAfterLastWindowClosed == true
      // second - destroy app if genParams->closeAppAfterLastWindowClosed == false and all windows was closed by softClose (res==true)
      MultiViewDesktop.closeApp().then((res) {
        if (res) MultiViewDesktop.closeApp(closeMode: CloseMode.destroy);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeConfig.themeMode,
      theme: mainLightTheme(),
      darkTheme: mainDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: exampleLocalizationDelegates(),
      supportedLocales: ExampleLocalizations.supportedLocales,
      home: widget.e2eStore != null ? E2eHost(store: widget.e2eStore!, child: const HomePage()) : const HomePage(),
    );
  }
}
