import 'package:flutter/material.dart';

import 'app_shell_patch.dart';

/// Per-view entry shell configuration for a secondary or dialog [View].
///
/// [appearance] overrides app-wide fields (theme, locale, shortcuts) on top of
/// the global [MultiViewDesktop.appShell] snapshot for **this view only**.
///
/// Navigation fields ([routerConfig], [home], [routes], and so on) are also
/// per-view. Each OS window gets its own navigator or router stack. They are
/// never shared through the global [AppShellController].
///
/// Simple content window (default: [openWindow] builder becomes [home]):
///
/// ```dart
/// openWindow((_, __) => SettingsPage());
/// ```
///
/// Different locale on one window, same theme as everywhere else:
///
/// ```dart
/// openWindow(
///   (_, __) => SettingsPage(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(
///       appearance: AppShellPatch(locale: const Locale('de')),
///     ),
///   ),
/// );
/// ```
///
/// Dedicated router for one secondary window:
///
/// ```dart
/// openWindow(
///   (_, __) => const SizedBox.shrink(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(
///       routerConfig: settingsRouter,
///     ),
///   ),
/// );
/// ```
@immutable
class ViewShellOverrides {
  const ViewShellOverrides({
    this.appearance,
    this.navigatorKey,
    this.scaffoldMessengerKey,
    this.home,
    this.routes,
    this.initialRoute,
    this.onGenerateRoute,
    this.onGenerateInitialRoutes,
    this.onUnknownRoute,
    this.onNavigationNotification,
    this.navigatorObservers,
    this.builder,
    this.title,
    this.onGenerateTitle,
    this.routerConfig,
    this.routeInformationProvider,
    this.routeInformationParser,
    this.routerDelegate,
    this.backButtonDispatcher,
    this.pageRouteBuilder,
    this.restorationScopeId,
  });

  /// Shorthand for appearance-only overrides.
  factory ViewShellOverrides.appearance(AppShellPatch patch) => ViewShellOverrides(appearance: patch);

  /// App-wide shell fields overridden for this view (theme, locale, and so on).
  final AppShellPatch? appearance;

  // ---------------------------------------------------------------------------
  // Navigation (per-view only)
  // ---------------------------------------------------------------------------

  final GlobalKey<NavigatorState>? navigatorKey;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
  final Widget? home;
  final Map<String, WidgetBuilder>? routes;
  final String? initialRoute;
  final RouteFactory? onGenerateRoute;
  final InitialRouteListFactory? onGenerateInitialRoutes;
  final RouteFactory? onUnknownRoute;
  final NotificationListenerCallback<NavigationNotification>? onNavigationNotification;
  final List<NavigatorObserver>? navigatorObservers;
  final TransitionBuilder? builder;
  final String? title;
  final GenerateAppTitle? onGenerateTitle;
  final RouterConfig<Object>? routerConfig;
  final RouteInformationProvider? routeInformationProvider;
  final RouteInformationParser<Object>? routeInformationParser;
  final RouterDelegate<Object>? routerDelegate;
  final BackButtonDispatcher? backButtonDispatcher;
  final PageRouteFactory? pageRouteBuilder;
  final String? restorationScopeId;

  /// Whether this view uses a router-based entry instead of [home].
  bool get usesRouter => routerConfig != null || routerDelegate != null;

  /// Combines [base] with [delta]. Non-null fields in [delta] replace [base].
  static ViewShellOverrides merge(ViewShellOverrides? base, ViewShellOverrides delta) {
    if (base == null) return delta;
    return ViewShellOverrides(
      appearance: delta.appearance != null
          ? AppShellPatch.merge(base.appearance, delta.appearance!)
          : base.appearance,
      navigatorKey: delta.navigatorKey ?? base.navigatorKey,
      scaffoldMessengerKey: delta.scaffoldMessengerKey ?? base.scaffoldMessengerKey,
      home: delta.home ?? base.home,
      routes: delta.routes ?? base.routes,
      initialRoute: delta.initialRoute ?? base.initialRoute,
      onGenerateRoute: delta.onGenerateRoute ?? base.onGenerateRoute,
      onGenerateInitialRoutes: delta.onGenerateInitialRoutes ?? base.onGenerateInitialRoutes,
      onUnknownRoute: delta.onUnknownRoute ?? base.onUnknownRoute,
      onNavigationNotification: delta.onNavigationNotification ?? base.onNavigationNotification,
      navigatorObservers: delta.navigatorObservers ?? base.navigatorObservers,
      builder: delta.builder ?? base.builder,
      title: delta.title ?? base.title,
      onGenerateTitle: delta.onGenerateTitle ?? base.onGenerateTitle,
      routerConfig: delta.routerConfig ?? base.routerConfig,
      routeInformationProvider: delta.routeInformationProvider ?? base.routeInformationProvider,
      routeInformationParser: delta.routeInformationParser ?? base.routeInformationParser,
      routerDelegate: delta.routerDelegate ?? base.routerDelegate,
      backButtonDispatcher: delta.backButtonDispatcher ?? base.backButtonDispatcher,
      pageRouteBuilder: delta.pageRouteBuilder ?? base.pageRouteBuilder,
      restorationScopeId: delta.restorationScopeId ?? base.restorationScopeId,
    );
  }
}
