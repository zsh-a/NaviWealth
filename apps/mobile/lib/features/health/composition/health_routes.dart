/// HealthOS routing tree (`docs/architecture/lifeos-shell.md` §3 + `docs/domains/healthos-domain.md`
/// §5, D-2.3b).
///
/// Mirrors `features/finance/composition/finance_routes.dart`. Self-
/// contained per Plan B: every Health route lives here so adding a
/// third domain doesn't touch existing domain files. The page widgets
/// are deferred so HealthOS stays off the main bundle until the user
/// opts in or navigates into the domain.
library;

import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../core/shell/deferred_route.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/health_plan_page.dart' deferred as plan_lib;
import '../ui/health_today_page.dart' deferred as today_lib;
import '../ui/health_trend_page.dart' deferred as trend_lib;
import 'health_domain_shell.dart';
import 'health_route_paths.dart';

/// HealthOS `StatefulShellRoute`: 3 branches (Today / Trend / Plan)
/// backed by [DomainTabsShell]. HealthOS command/search entries are
/// contributed separately through `healthCommandPaletteEntries`.
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
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: HealthRoutes.plan,
            name: HealthRouteNames.plan,
            builder: (context, state) => DeferredRoute(
              load: plan_lib.loadLibrary,
              builder: (_) => plan_lib.HealthPlanPage(),
            ),
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
    plan_lib.loadLibrary(),
  ]);
}
