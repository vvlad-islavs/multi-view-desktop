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
    globalScope: (child) {
      //any providers...
      return child;
    },
    config: MultiAppConfig(
      generalParams: MultiPlatformParams(
        animation: ViewAnimationConfig.all(),
        enableDynamicAnchor: true,
        closeMode: CloseMode.softCascade,
        menuItems: [
          TaskbarMenuItem(
            title: 'Open new window',
            iconAsset: 'assets/icons/new_window.png',
            onPressed: () => openWindow((ctx, id) => HomePage()),
          ),
        ],
      ),
      macosParams: MacosPlatformParams(
        closeAppAfterLastWindowClosed: false,
        saveLastWindowToReopen: false,
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
        maximumSize: Size(1200, 800),
        size: Size(1000, 700),
        alignment: Alignment.center,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
        title: 'Window 1',
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      MultiViewDesktop.setGlobalBrightness(
        themeConfig.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );

      sharedConfig.isHideAppFromTaskbar = MultiViewDesktop.isHideAppFromTaskbar();
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
