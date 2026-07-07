import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../l10n/example_localizations.dart';
import '../routing/auto_router/app_router.dart';
import '../routing/go_router_config.dart';

/// Opens secondary windows and dialogs that demonstrate `ViewShellOverrides`.
abstract final class ShellDemoActions {
  static void openGoRouterWindow(BuildContext context) {
    final router = createDemoGoRouter();
    openWindow(
      (_, id) => const SizedBox.shrink(),
      parentContext: context,
      options: WindowOptions(
        minimumSize: const Size(720, 520),
        size: const Size(720, 520),
        title: 'GoRouter window',
        shellOverrides: ViewShellOverrides(
          routerConfig: router,
          appearance: AppShellPatch(
            // theme: secondaryLightTheme(),
            // darkTheme: secondaryDarkTheme(),
            // themeMode: themeConfig.themeMode,
            localizationsDelegates: exampleLocalizationDelegates(),
            supportedLocales: ExampleLocalizations.supportedLocales,
          ),
        ),
      ),
    );
  }

  static Future<void> openAutoRouteDialog(BuildContext context) async {
    final router = AutoDemoRouter();
    await openDialog<void>(
      (_, id) => const SizedBox.shrink(),
      parentContext: context,
      options: DialogOptions(
        minimumSize: const Size(300, 200),
        size: const Size(520, 420),
        title: 'AutoRoute dialog',
        modal: false,
        isResizable: true,
        showOnInit: true,
        shellOverrides: ViewShellOverrides(
          routerConfig: router.config(),
          appearance: AppShellPatch(
            localizationsDelegates: exampleLocalizationDelegates(),
            supportedLocales: ExampleLocalizations.supportedLocales,
          ),
        ),
      ),
    );
  }

  static void openLocalizedWindow(BuildContext context) {
    openWindow(
      (_, id) => const _LocalizedPreviewPage(),
      parentContext: context,
      options: WindowOptions(
        minimumSize: const Size(640, 400),
        size: const Size(640, 400),
        title: 'Localized window',
        shellOverrides: ViewShellOverrides(
          appearance: AppShellPatch(
            locale: const Locale('de'),
            localizationsDelegates: exampleLocalizationDelegates(),
            supportedLocales: ExampleLocalizations.supportedLocales,
          ),
        ),
      ),
    );
  }
}

class _LocalizedPreviewPage extends StatelessWidget {
  const _LocalizedPreviewPage();

  void _toggleLocale(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    MultiViewDesktop.of(context).patchViewShell(
      ViewShellOverrides.appearance(
        AppShellPatch(
          locale: l10n.toggledLocale,
          localizationsDelegates: exampleLocalizationDelegates(),
          supportedLocales: ExampleLocalizations.supportedLocales,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.openLocalizedWindow)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.currentLocaleLabel}: ${locale.languageCode}'),
            const SizedBox(height: 8),
            Text('${l10n.todayLabel}: ${l10n.formatToday(DateTime.now())}'),
            const SizedBox(height: 12),
            Text(l10n.openLocalizedWindowSub),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => _toggleLocale(context), child: Text(l10n.localeToggleLabel)),
          ],
        ),
      ),
    );
  }
}

/// List tiles for the home page shell demo section.
List<Widget> shellDemoTiles(BuildContext context) {
  final l10n = ExampleLocalizations.of(context);
  return [
    ListTile(
      dense: true,
      title: Text(l10n.openGoRouterWindow),
      subtitle: Text(l10n.openGoRouterWindowSub),
      onTap: () => ShellDemoActions.openGoRouterWindow(context),
    ),
    ListTile(
      dense: true,
      title: Text(l10n.openAutoRouteDialog),
      subtitle: Text(l10n.openAutoRouteDialogSub),
      onTap: () => ShellDemoActions.openAutoRouteDialog(context),
    ),
    ListTile(
      dense: true,
      title: Text(l10n.openLocalizedWindow),
      subtitle: Text(l10n.openLocalizedWindowSub),
      onTap: () => ShellDemoActions.openLocalizedWindow(context),
    ),
  ];
}
