// Phase A guard tests: legacy /accounts/* URLs must redirect to the
// canonical /wealth/* and /plan/* paths so external deep links and
// AI-chat history (which embed full paths in routeHint payloads) keep
// resolving after the IA migration.
//
// IA contract reference:
// apps/mobile/docs/design/00-information-architecture.md §7 (Phase A)
//
// Approach: we build a *test-only* GoRouter that uses the same
// redirect-route table as production, but routes every destination to
// a placeholder widget. That isolates the redirect URL contract from
// the destination pages' own provider/Drift dependencies — production
// destinations are exercised in `router_test.dart` instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';

GoRouter _buildTestRouter(String initialLocation) {
  // Mirror the redirect table from `router_builder.dart::_legacyAccountsRedirects`.
  // Kept in sync manually — if a redirect is added there, add it here too.
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      // Stub destinations for canonical paths so the redirect has a
      // valid landing route. Each renders a Text widget whose body is
      // the path it received — useful for human debug only.
      ..._stubRoute(AppRoutes.wealth),
      ..._stubRoute(AppRoutes.wealthAccounts),
      ..._stubRoute(AppRoutes.wealthAccountNew),
      ..._stubRoute('/wealth/accounts/:id'),
      ..._stubRoute(AppRoutes.wealthNewCash),
      ..._stubRoute(AppRoutes.wealthNewDeposit),
      ..._stubRoute(AppRoutes.wealthNewWealth),
      ..._stubRoute(AppRoutes.wealthCorporateAction),
      ..._stubRoute(AppRoutes.wealthPortfolio),
      ..._stubRoute(AppRoutes.wealthWatchlist),
      ..._stubRoute(AppRoutes.wealthIncomeProjection),
      ..._stubRoute('/wealth/assets/:assetId'),
      ..._stubRoute('/wealth/physical/:id'),
      ..._stubRoute(AppRoutes.wealthLiabilities),
      ..._stubRoute(AppRoutes.wealthLiabilityNew),
      ..._stubRoute('/wealth/liabilities/:id'),
      ..._stubRoute(AppRoutes.planFire),
      ..._stubRoute(AppRoutes.planRebalance),
      ..._stubRoute(AppRoutes.planIncome),
      ..._stubRoute(AppRoutes.planDca),
      ..._stubRoute(AppRoutes.planProjection),
      // Redirect routes (same table as production).
      GoRoute(path: '/accounts', redirect: (_, _) => AppRoutes.wealth),
      GoRoute(
        path: '/accounts/list',
        redirect: (_, _) => AppRoutes.wealthAccounts,
      ),
      GoRoute(
        path: '/accounts/list/new',
        redirect: (_, _) => AppRoutes.wealthAccountNew,
      ),
      GoRoute(
        path: '/accounts/list/:accountId',
        redirect: (_, state) =>
            AppRoutes.wealthAccount(state.pathParameters['accountId'] ?? ''),
      ),
      GoRoute(
        path: '/accounts/new/cash',
        redirect: (_, _) => AppRoutes.wealthNewCash,
      ),
      GoRoute(
        path: '/accounts/new/deposit',
        redirect: (_, _) => AppRoutes.wealthNewDeposit,
      ),
      GoRoute(
        path: '/accounts/new/wealth',
        redirect: (_, _) => AppRoutes.wealthNewWealth,
      ),
      GoRoute(
        path: '/accounts/corporate-action',
        redirect: (_, _) => AppRoutes.wealthCorporateAction,
      ),
      GoRoute(
        path: '/accounts/portfolio',
        redirect: (_, _) => AppRoutes.wealthPortfolio,
      ),
      GoRoute(
        path: '/accounts/watchlist',
        redirect: (_, _) => AppRoutes.wealthWatchlist,
      ),
      GoRoute(
        path: '/accounts/dividends',
        redirect: (_, _) => AppRoutes.wealthIncomeProjection,
      ),
      GoRoute(
        path: '/accounts/asset/:assetId',
        redirect: (_, state) =>
            AppRoutes.wealthAsset(state.pathParameters['assetId'] ?? ''),
      ),
      GoRoute(
        path: '/accounts/physical/:id',
        redirect: (_, state) =>
            AppRoutes.wealthPhysical(state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/accounts/liabilities',
        redirect: (_, _) => AppRoutes.wealthLiabilities,
      ),
      GoRoute(
        path: '/accounts/liabilities/new',
        redirect: (_, _) => AppRoutes.wealthLiabilityNew,
      ),
      GoRoute(
        path: '/accounts/liabilities/:id',
        redirect: (_, state) =>
            AppRoutes.wealthLiability(state.pathParameters['id'] ?? ''),
      ),
      GoRoute(path: '/accounts/fire', redirect: (_, _) => AppRoutes.planFire),
      GoRoute(
        path: '/accounts/rebalance',
        redirect: (_, _) => AppRoutes.planRebalance,
      ),
      GoRoute(
        path: '/accounts/analytics',
        redirect: (_, _) => AppRoutes.planProjection,
      ),
      GoRoute(
        path: '/accounts/income',
        redirect: (_, _) => AppRoutes.planIncome,
      ),
      GoRoute(path: '/accounts/dca', redirect: (_, _) => AppRoutes.planDca),
    ],
  );
}

List<GoRoute> _stubRoute(String path) {
  return [
    GoRoute(path: path, builder: (_, _) => Scaffold(body: Text(path))),
  ];
}

void main() {
  group('legacy /accounts/* → canonical /wealth/* + /plan/* redirects', () {
    Future<String> resolve(WidgetTester tester, String initial) async {
      final router = _buildTestRouter(initial);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      return router.routeInformationProvider.value.uri.path;
    }

    final cases = <String, String>{
      '/accounts': AppRoutes.wealth,
      '/accounts/list': AppRoutes.wealthAccounts,
      '/accounts/list/new': AppRoutes.wealthAccountNew,
      '/accounts/new/cash': AppRoutes.wealthNewCash,
      '/accounts/new/deposit': AppRoutes.wealthNewDeposit,
      '/accounts/new/wealth': AppRoutes.wealthNewWealth,
      '/accounts/corporate-action': AppRoutes.wealthCorporateAction,
      '/accounts/portfolio': AppRoutes.wealthPortfolio,
      '/accounts/watchlist': AppRoutes.wealthWatchlist,
      '/accounts/dividends': AppRoutes.wealthIncomeProjection,
      '/accounts/liabilities': AppRoutes.wealthLiabilities,
      '/accounts/liabilities/new': AppRoutes.wealthLiabilityNew,
      '/accounts/fire': AppRoutes.planFire,
      '/accounts/rebalance': AppRoutes.planRebalance,
      '/accounts/analytics': AppRoutes.planProjection,
      '/accounts/income': AppRoutes.planIncome,
      '/accounts/dca': AppRoutes.planDca,
    };

    cases.forEach((legacy, canonical) {
      testWidgets('$legacy → $canonical', (tester) async {
        expect(await resolve(tester, legacy), canonical);
      });
    });

    testWidgets('/accounts/list/:id preserves the id', (tester) async {
      expect(
        await resolve(tester, '/accounts/list/acc_123'),
        '/wealth/accounts/acc_123',
      );
    });

    testWidgets('/accounts/asset/:id → /wealth/assets/:id', (tester) async {
      expect(
        await resolve(tester, '/accounts/asset/aapl'),
        '/wealth/assets/aapl',
      );
    });

    testWidgets('/accounts/physical/:id → /wealth/physical/:id', (tester) async {
      expect(
        await resolve(tester, '/accounts/physical/home'),
        '/wealth/physical/home',
      );
    });

    testWidgets('/accounts/liabilities/:id → /wealth/liabilities/:id', (
      tester,
    ) async {
      expect(
        await resolve(tester, '/accounts/liabilities/mortgage1'),
        '/wealth/liabilities/mortgage1',
      );
    });
  });
}
