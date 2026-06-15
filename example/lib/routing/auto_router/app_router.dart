import 'package:auto_route/auto_route.dart';

import 'auto_router_pages.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AutoDemoRouter extends RootStackRouter {
  AutoDemoRouter();

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: AutoCatalogRoute.page, initial: true),
    AutoRoute(page: AutoItemRoute.page),
  ];
}
