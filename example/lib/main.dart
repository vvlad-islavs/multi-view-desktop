import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:multiview_desktop/multiview_desktop.dart';
import 'pages/home.dart';
import 'l10n/example_localizations.dart';
import 'theme/app_themes.dart';
import 'utils/theme_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runMultiApp(
    home: (globalScopeContext, id) => const MainWindowRoot(),
    globalScope: (child){
      //any providers...
      return child;
    },
    config: MultiAppConfig(
      generalParams: MultiPlatformParams(enableDynamicAnchor: true, closeMode: CloseMode.softCascade),
      macosParams: MacosPlatformParams(
        saveLastWindowToReopen: true,
        closeAppAfterLastWindowClosed: false,
        // onTaskbarTap: null,
      ),
      globalWindowOptions: WindowOptions(
        minimumSize: Size(1000, 700),
        maximumSize: Size(1200, 800),
        size: Size(1000, 700),
        alignment: Alignment.center,
        hideAppFromTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
        title: 'Window 1',
      ),
      globalDialogOptions: DialogOptions(modal: false,  windowButtonVisibility: true),
      observers: [AppWindowObserver()],
    ),
  );
}

class AppWindowObserver extends WindowObserver {
  @override
  void onWindowOpened(int viewId, {int? parentViewId}) {
    log('window $viewId opened, parent $parentViewId', name: 'MVD');
  }

  @override
  void onWindowClosed(int viewId) {
    log('window $viewId closed', name: 'MVD');
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
  const MainWindowRoot({super.key});

  @override
  State<MainWindowRoot> createState() => _MainWindowRootState();
}

class _MainWindowRootState extends State<MainWindowRoot> {
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
      await MultiViewDesktop.setGlobalBrightness(themeConfig.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);

      sharedConfig.isHideAppFromTaskbar = await MultiViewDesktop.isHideAppFromTaskbar();
      sharedConfig.closeMode = MultiViewDesktop.getCloseMode();
      sharedConfig.anchorId = MultiViewDesktop.getAnchorId();
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
      theme: mainLightTheme(),
      darkTheme: mainDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: exampleLocalizationDelegates(),
      supportedLocales: ExampleLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}
