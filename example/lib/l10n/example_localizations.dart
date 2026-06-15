import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// Small demo catalog for secondary windows and dialogs.
class ExampleLocalizations {
  ExampleLocalizations(this.locale);

  final Locale locale;

  static ExampleLocalizations of(BuildContext context) {
    return Localizations.of<ExampleLocalizations>(context, ExampleLocalizations)!;
  }

  static const LocalizationsDelegate<ExampleLocalizations> delegate = _ExampleLocalizationsDelegate();

  static const supportedLocales = <Locale>[Locale('en'), Locale('de')];

  static const _strings = <String, Map<String, String>>{
    'en': {
      'appTitle': 'MultiView Demo',
      'shellDemoSection': 'Entry shell demo',
      'openGoRouterWindow': 'Open GoRouter window',
      'openGoRouterWindowSub': 'Teal theme, GoRouter tree',
      'openAutoRouteDialog': 'Open AutoRoute dialog',
      'openAutoRouteDialogSub': 'AutoRoute tree in dialog',
      'openLocalizedWindow': 'Open localized window',
      'openLocalizedWindowSub': 'German locale on this view only',
      'todayLabel': 'Today',
      'goBrowseTitle': 'GoRouter catalog',
      'goBrowseBody': 'Browse route in a secondary window.',
      'goItemTitle': 'GoRouter item',
      'goItemBody': 'Detail route (/browse/item).',
      'autoCatalogTitle': 'AutoRoute catalog',
      'autoCatalogBody': 'Catalog route inside AutoRoute dialog.',
      'autoItemTitle': 'AutoRoute item',
      'autoItemBody': 'Nested item route.',
      'nextRoute': 'Next route',
      'backRoute': 'Back',
      'currentLocaleLabel': 'Current locale',
      'localeToggleToDe': 'Switch to German',
      'localeToggleToEn': 'Switch to English',
    },
    'de': {
      'appTitle': 'MultiView Demo',
      'shellDemoSection': 'Entry-Shell Demo',
      'openGoRouterWindow': 'GoRouter-Fenster öffnen',
      'openGoRouterWindowSub': 'Türkis, GoRouter-Baum',
      'openAutoRouteDialog': 'AutoRoute-Dialog öffnen',
      'openAutoRouteDialogSub': 'AutoRoute-Baum im Dialog',
      'openLocalizedWindow': 'Lokalisiertes Fenster öffnen',
      'openLocalizedWindowSub': 'Deutsch nur in diesem Fenster',
      'todayLabel': 'Heute',
      'goBrowseTitle': 'GoRouter Katalog',
      'goBrowseBody': 'Browse-Route in einem Secondary-Fenster.',
      'goItemTitle': 'GoRouter Artikel',
      'goItemBody': 'Detail-Route (/browse/item).',
      'autoCatalogTitle': 'AutoRoute Katalog',
      'autoCatalogBody': 'Katalog-Route im AutoRoute-Dialog.',
      'autoItemTitle': 'AutoRoute Artikel',
      'autoItemBody': 'Verschachtelte Item-Route.',
      'nextRoute': 'Nächste Route',
      'backRoute': 'Zurück',
      'currentLocaleLabel': 'Aktuelle Sprache',
      'localeToggleToDe': 'Auf Deutsch wechseln',
      'localeToggleToEn': 'Auf Englisch wechseln',
    },
  };

  String _t(String key) => _strings[locale.languageCode]?[key] ?? _strings['en']![key]!;

  String get appTitle => _t('appTitle');
  String get shellDemoSection => _t('shellDemoSection');
  String get openGoRouterWindow => _t('openGoRouterWindow');
  String get openGoRouterWindowSub => _t('openGoRouterWindowSub');
  String get openAutoRouteDialog => _t('openAutoRouteDialog');
  String get openAutoRouteDialogSub => _t('openAutoRouteDialogSub');
  String get openLocalizedWindow => _t('openLocalizedWindow');
  String get openLocalizedWindowSub => _t('openLocalizedWindowSub');
  String get todayLabel => _t('todayLabel');
  String get goBrowseTitle => _t('goBrowseTitle');
  String get goBrowseBody => _t('goBrowseBody');
  String get goItemTitle => _t('goItemTitle');
  String get goItemBody => _t('goItemBody');
  String get autoCatalogTitle => _t('autoCatalogTitle');
  String get autoCatalogBody => _t('autoCatalogBody');
  String get autoItemTitle => _t('autoItemTitle');
  String get autoItemBody => _t('autoItemBody');
  String get nextRoute => _t('nextRoute');
  String get backRoute => _t('backRoute');
  String get currentLocaleLabel => _t('currentLocaleLabel');
  String get localeToggleToDe => _t('localeToggleToDe');
  String get localeToggleToEn => _t('localeToggleToEn');

  /// Label for the button that switches this view to the other locale.
  String get localeToggleLabel =>
      locale.languageCode == 'de' ? localeToggleToEn : localeToggleToDe;

  String formatToday(DateTime date) => DateFormat.yMMMMd(locale.toString()).format(date);

  Locale get toggledLocale =>
      locale.languageCode == 'de' ? const Locale('en') : const Locale('de');
}

class _ExampleLocalizationsDelegate extends LocalizationsDelegate<ExampleLocalizations> {
  const _ExampleLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ExampleLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<ExampleLocalizations> load(Locale locale) {
    return SynchronousFuture<ExampleLocalizations>(ExampleLocalizations(locale));
  }

  @override
  bool shouldReload(_ExampleLocalizationsDelegate old) => false;
}

/// Delegates shared by main and per-view shell overrides.
List<LocalizationsDelegate<dynamic>> exampleLocalizationDelegates() => [
  ExampleLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
