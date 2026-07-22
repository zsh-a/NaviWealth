/// HealthOS routing tree — Today + Trends; `/health/plan` redirects to Today.
library;

import 'package:go_router/go_router.dart';

import '../../../core/shell/deferred_route.dart';
import '../../../core/shell/domain_tabs_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/health_today_page.dart' deferred as today_lib;
import '../ui/health_trend_page.dart' deferred as trend_lib;
import 'health_domain_shell.dart';
import 'health_route_paths.dart';

/// HealthOS shell: Today / Trends.
StatefulShellRoute healthShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => DomainTabsShell(
      shell: shell,
      spec: healthDomainShell(AppLocalizations.of(context)),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: HealthRoutes.today,
            name: HealthRouteNames.today,
            builder: (context, state) => DeferredRoute(
              load: today_lib.loadLibrary,
              builder: (_) => today_lib.HealthTodayPage(),
            ),
            routes: [
              // Legacy Plan deep-link → Today (plan content lives on hero).
              GoRoute(
                path: 'plan',
                name: HealthRouteNames.plan,
                redirect: (context, state) => HealthRoutes.today,
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: HealthRoutes.trend,
            name: HealthRouteNames.trend,
            builder: (context, state) {
              final query = state.uri.queryParameters;
              return DeferredRoute(
                load: trend_lib.loadLibrary,
                builder: (_) => trend_lib.HealthTrendPage.fromQuery(query),
              );
            },
          ),
        ],
      ),
    ],
  );
}

Future<void> preloadHealthDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
    today_lib.loadLibrary(),
    trend_lib.loadLibrary(),
  ]);
}
