/// HealthOS routing tree (`docs/lifeos-shell.md` §3 + `docs/healthos-domain.md`
/// §5, D-2.3b).
///
/// Mirrors `features/finance/composition/finance_routes.dart`. Self-
/// contained per Plan B: every Health route lives here so adding a
/// third domain doesn't touch existing domain files. No deferred
/// libraries today — placeholder pages ship in the main bundle.
library;

import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../app/route_paths.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/health_placeholder_page.dart';
import 'health_domain_shell.dart';

/// HealthOS `StatefulShellRoute`: 3 branches (Today / Trend / Plan)
/// backed by [DomainTabsShell] (no mobile search slot — Health doesn't
/// use the command palette today).
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
            path: AppRoutes.healthToday,
            name: AppRouteNames.healthToday,
            builder: (context, state) =>
                const HealthPlaceholderPage(tab: HealthTab.today),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.healthTrend,
            name: AppRouteNames.healthTrend,
            builder: (context, state) =>
                const HealthPlaceholderPage(tab: HealthTab.trend),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.healthPlan,
            name: AppRouteNames.healthPlan,
            builder: (context, state) =>
                const HealthPlaceholderPage(tab: HealthTab.plan),
          ),
        ],
      ),
    ],
  );
}
