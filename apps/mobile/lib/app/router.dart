import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/asset_detail_page.dart';
import '../features/assets/assets_page.dart' deferred as assets_lib;
import '../features/assets/cash_form_page.dart';
import '../features/assets/deposit_form_page.dart';
import '../features/assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import '../features/assets/wealth_product_form_page.dart';
import '../features/auth/presentation/devices_page.dart'
    deferred as devices_lib;
import '../features/auth/presentation/login_page.dart';
import '../features/expense/ui/expense_categories_page.dart';
import '../features/expense/ui/expense_form_page.dart';
import '../features/expense/ui/expense_list_page.dart';
import '../features/expense/ui/expense_report_page.dart';
import '../features/fire/presentation/fire_page.dart' deferred as fire_lib;
import '../features/home/home_page.dart';
import '../features/investment/presentation/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import '../features/investment/presentation/trade_entry_form_page.dart';
import '../features/liabilities/ui/liabilities_page.dart'
    deferred as liabilities_lib;
import '../features/liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../l10n/gen/app_localizations.dart';
import 'deferred_route.dart';
import 'route_analytics_observer.dart';
import 'route_error_page.dart';
import 'route_guard.dart';

/// Paths of the six primary tabs in the root shell, in display order.
///
/// The keyboard-shortcut layer (`core/shortcuts`) maps digits `1`-`6` to these
/// indexes — keep order in sync with `_RootShell`'s NavigationBar.
const List<String> kPrimaryTabPaths = <String>[
  '/',
  '/assets',
  '/expenses',
  '/analytics',
  '/fire',
  '/settings',
];

/// Test-only: eagerly resolve every deferred-as library the router maps to
/// a tab so subsequent [DeferredRoute] mounts see an already-completed
/// `loadLibrary()` future. Without this, widget tests sit on the loading
/// spinner — `loadLibrary()` is real-async and the fake test clock can't
/// drive it. Call from `setUpAll` inside a `runAsync` block.
@visibleForTesting
Future<void> preloadDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
    assets_lib.loadLibrary(),
    analytics_lib.loadLibrary(),
    settings_lib.loadLibrary(),
    fire_lib.loadLibrary(),
    liabilities_lib.loadLibrary(),
    liability_detail_lib.loadLibrary(),
    physical_detail_lib.loadLibrary(),
    corp_action_lib.loadLibrary(),
    devices_lib.loadLibrary(),
    rebalance_lib.loadLibrary(),
    ai_chat_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter]. Exposed (rather than inlined in the provider)
/// so tests can construct a router seeded at an arbitrary deep-link location
/// and inject their own observers / guards through the [Ref].
GoRouter buildAppRouter(Ref ref, {String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: <NavigatorObserver>[ref.read(routeAnalyticsObserverProvider)],
    refreshListenable: ref.read(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(ref, context, state),
    errorBuilder: (context, state) => RouteErrorPage(state: state),
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => _RootShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/assets',
            name: 'assets',
            builder: (context, state) => DeferredRoute(
              load: assets_lib.loadLibrary,
              builder: (_) => assets_lib.AssetsPage(),
            ),
            routes: [
              GoRoute(
                path: 'new/cash',
                name: 'asset-new-cash',
                builder: (context, state) => const CashFormPage(),
              ),
              GoRoute(
                path: 'new/deposit',
                name: 'asset-new-deposit',
                builder: (context, state) => const DepositFormPage(),
              ),
              GoRoute(
                path: 'new/wealth',
                name: 'asset-new-wealth',
                builder: (context, state) => const WealthProductFormPage(),
              ),
              GoRoute(
                path: 'corporate-action',
                name: 'corporate-action',
                builder: (context, state) => DeferredRoute(
                  load: corp_action_lib.loadLibrary,
                  builder: (_) => corp_action_lib.CorporateActionEntryRoute(),
                ),
              ),
              GoRoute(
                path: 'trade',
                name: 'trade-entry',
                builder: (context, state) {
                  final assetId = state.uri.queryParameters['assetId'];
                  final accountId = state.uri.queryParameters['accountId'];
                  return TradeEntryFormPage(
                    assetId: assetId,
                    accountId: accountId,
                  );
                },
              ),
              GoRoute(
                path: 'physical/:id',
                name: 'physicalAssetDetail',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DeferredRoute(
                    load: physical_detail_lib.loadLibrary,
                    builder: (_) =>
                        physical_detail_lib.PhysicalAssetDetailPage(id: id),
                  );
                },
              ),
              GoRoute(
                path: 'liabilities',
                name: 'liabilities',
                builder: (context, state) => DeferredRoute(
                  load: liabilities_lib.loadLibrary,
                  builder: (_) => liabilities_lib.LiabilitiesPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'liabilityDetail',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return DeferredRoute(
                        load: liability_detail_lib.loadLibrary,
                        builder: (_) =>
                            liability_detail_lib.LiabilityDetailPage(id: id),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: ':assetId',
                name: 'asset-detail',
                builder: (context, state) =>
                    AssetDetailPage(assetId: state.pathParameters['assetId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/accounts',
            name: 'accounts',
            builder: (context, state) => const AccountsPage(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'account-new',
                builder: (context, state) => const AccountFormPage(),
              ),
              GoRoute(
                path: ':accountId',
                name: 'account-detail',
                builder: (context, state) => AccountFormPage(
                  accountId: state.pathParameters['accountId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/expenses',
            name: 'expenses',
            builder: (context, state) => const ExpenseListPage(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'expense-new',
                builder: (context, state) => const ExpenseFormPage(),
              ),
              GoRoute(
                path: 'categories',
                name: 'expense-categories',
                builder: (context, state) => const ExpenseCategoriesPage(),
              ),
              GoRoute(
                path: 'report',
                name: 'expense-report',
                builder: (context, state) => const ExpenseReportPage(),
              ),
              GoRoute(
                path: ':expenseId',
                name: 'expense-detail',
                builder: (context, state) => ExpenseFormPage(
                  expenseId: state.pathParameters['expenseId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (context, state) => DeferredRoute(
              load: analytics_lib.loadLibrary,
              builder: (_) => analytics_lib.AnalyticsPage(),
            ),
          ),
          GoRoute(
            path: '/fire',
            name: 'fire',
            builder: (context, state) => DeferredRoute(
              load: fire_lib.loadLibrary,
              builder: (_) => fire_lib.FirePage(),
            ),
          ),
          GoRoute(
            path: '/rebalance',
            name: 'rebalance',
            builder: (context, state) => DeferredRoute(
              load: rebalance_lib.loadLibrary,
              builder: (_) => rebalance_lib.RebalancePage(),
            ),
          ),
          GoRoute(
            path: '/ai',
            name: 'ai-chat',
            builder: (context, state) => DeferredRoute(
              load: ai_chat_lib.loadLibrary,
              builder: (_) => ai_chat_lib.AiChatPage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => DeferredRoute(
              load: settings_lib.loadLibrary,
              builder: (_) => settings_lib.SettingsPage(),
            ),
            routes: [
              GoRoute(
                path: 'devices',
                name: 'devices',
                builder: (context, state) => DeferredRoute(
                  load: devices_lib.loadLibrary,
                  builder: (_) => devices_lib.DevicesPage(),
                ),
              ),
              GoRoute(
                path: 'fx-rates',
                name: 'fx-rates',
                builder: (context, state) => const FxRatesPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));

class _RootShell extends StatelessWidget {
  const _RootShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    // Sub-routes under `/assets` and `/accounts` keep the Assets tab
    // highlighted: e.g. `/assets/new/cash` is "still" assets-tab content.
    final int index;
    if (location.startsWith('/assets') || location.startsWith('/accounts')) {
      index = 1;
    } else if (location.startsWith('/expenses')) {
      index = 2;
    } else if (location.startsWith('/analytics')) {
      index = 3;
    } else if (location.startsWith('/fire')) {
      index = 4;
    } else if (location.startsWith('/settings')) {
      index = 5;
    } else {
      index = 0;
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.navAssets,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.navExpenses,
          ),
          NavigationDestination(
            icon: const Icon(Icons.pie_chart_outline),
            selectedIcon: const Icon(Icons.pie_chart),
            label: l10n.navAnalytics,
          ),
          NavigationDestination(
            icon: const Icon(Icons.flag_outlined),
            selectedIcon: const Icon(Icons.flag),
            label: l10n.navFire,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.goNamed('home');
            case 1:
              context.goNamed('assets');
            case 2:
              context.goNamed('expenses');
            case 3:
              context.goNamed('analytics');
            case 4:
              context.goNamed('fire');
            case 5:
              context.goNamed('settings');
          }
        },
      ),
    );
  }
}
