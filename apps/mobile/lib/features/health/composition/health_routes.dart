/// HealthOS routing tree — Today + Trends.
library;

import 'package:go_router/go_router.dart';

import '../../../core/shell/deferred_route.dart';
import '../../../core/shell/domain_tabs_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/health_meal_entry_page.dart' deferred as meal_entry_lib;
import '../ui/health_meals_page.dart' deferred as meals_lib;
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
              GoRoute(
                path: 'meals',
                name: HealthRouteNames.meals,
                builder: (context, state) => DeferredRoute(
                  load: meals_lib.loadLibrary,
                  builder: (_) => meals_lib.HealthMealsPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: HealthRouteNames.mealNew,
                    builder: (context, state) => DeferredRoute(
                      load: meal_entry_lib.loadLibrary,
                      builder: (_) => meal_entry_lib.HealthMealEntryPage(
                        initialDay: DateTime.tryParse(
                          state.uri.queryParameters['day'] ?? '',
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: ':mealId',
                    name: HealthRouteNames.mealEdit,
                    builder: (context, state) => DeferredRoute(
                      load: meal_entry_lib.loadLibrary,
                      builder: (_) => meal_entry_lib.HealthMealEntryPage(
                        mealId: state.pathParameters['mealId'],
                      ),
                    ),
                  ),
                ],
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
    meals_lib.loadLibrary(),
    meal_entry_lib.loadLibrary(),
  ]);
}
