import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Tabs other than home are split into their own dart2js part files; each part
// is loaded the first time the user navigates to that route. Home ships in
// main.dart.js to avoid a part-file fetch on first paint. See
// docs/web-bundle.md for the resulting bundle layout.
import '../core/logging/providers.dart';
import '../core/logging/talker_route_observer.dart';
import '../features/accounts/account_form_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/accounts/journal_entry_list_page.dart';
import '../features/accounts/transfer_form_page.dart';
import '../features/activity/activity_page.dart';
import '../features/ai_chat/ui/ai_chat_page.dart' deferred as ai_chat_lib;
import '../features/analytics/analytics_page.dart' deferred as analytics_lib;
import '../features/assets/asset_detail_page.dart';
import '../features/assets/cash_form_page.dart';
import '../features/assets/deposit_form_page.dart';
import '../features/assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import '../features/assets/wealth_product_form_page.dart';
import '../features/auth/presentation/devices_page.dart'
    deferred as devices_lib;
import '../features/auth/presentation/login_page.dart';
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
import '../features/liabilities/ui/liability_form_page.dart';
import '../features/plan/plan_page.dart';
import '../features/portfolio/portfolio_page.dart' deferred as portfolio_lib;
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/backup/backup_page.dart';
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/log_viewer_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import 'app_shell.dart';
import 'deferred_route.dart';
import 'page_transitions.dart';
import 'route_analytics_observer.dart';
import 'route_error_page.dart';
import 'route_guard.dart';
import 'route_paths.dart';

/// Test-only: eagerly resolve every deferred-as library the router maps to
/// a tab so subsequent [DeferredRoute] mounts see an already-completed
/// `loadLibrary()` future. Without this, widget tests sit on the loading
/// spinner — `loadLibrary()` is real-async and the fake test clock can't
/// drive it. Call from `setUpAll` inside a `runAsync` block.
@visibleForTesting
Future<void> preloadDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
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
    portfolio_lib.loadLibrary(),
  ]);
}

/// Builds the app's [GoRouter]. Exposed (rather than inlined in the provider)
/// so tests can construct a router seeded at an arbitrary deep-link location
/// and inject their own observers / guards through the [Ref].
GoRouter buildAppRouter(Ref ref, {String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: <NavigatorObserver>[
      ref.read(routeAnalyticsObserverProvider),
      TalkerRouteObserver(ref.read(talkerProvider)),
    ],
    refreshListenable: ref.read(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(ref.container, context, state),
    errorBuilder: (context, state) => RouteErrorPage(state: state),
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: AppRouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      // ── Main shell: IndexedStack preserves tab state across switches ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppRootShell(shell: shell),
        branches: [
          // ── Branch 0: Home (+ AI Chat, Settings — no dedicated tab) ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: AppRouteNames.home,
                builder: (context, state) => const HomePage(),
              ),
              GoRoute(
                path: AppRoutes.ai,
                name: AppRouteNames.aiChat,
                builder: (context, state) => DeferredRoute(
                  load: ai_chat_lib.loadLibrary,
                  builder: (_) => ai_chat_lib.AiChatPage(),
                ),
              ),
              GoRoute(
                path: AppRoutes.settings,
                name: AppRouteNames.settings,
                builder: (context, state) => DeferredRoute(
                  load: settings_lib.loadLibrary,
                  builder: (_) => settings_lib.SettingsPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'devices',
                    name: AppRouteNames.devices,
                    builder: (context, state) => DeferredRoute(
                      load: devices_lib.loadLibrary,
                      builder: (_) => devices_lib.DevicesPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'fx-rates',
                    name: AppRouteNames.fxRates,
                    builder: (context, state) => const FxRatesPage(),
                  ),
                  GoRoute(
                    path: 'backup',
                    name: AppRouteNames.backup,
                    builder: (context, state) => const BackupPage(),
                  ),
                  GoRoute(
                    path: 'logs',
                    name: AppRouteNames.logs,
                    builder: (context, state) => const LogViewerPage(),
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 1: Portfolio (assets + liabilities) ──────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.portfolio,
                name: AppRouteNames.portfolio,
                builder: (context, state) => DeferredRoute(
                  load: portfolio_lib.loadLibrary,
                  builder: (_) => portfolio_lib.PortfolioPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'new/cash',
                    name: AppRouteNames.assetNewCash,
                    builder: (context, state) => const CashFormPage(),
                  ),
                  GoRoute(
                    path: 'new/deposit',
                    name: AppRouteNames.assetNewDeposit,
                    builder: (context, state) => const DepositFormPage(),
                  ),
                  GoRoute(
                    path: 'new/wealth',
                    name: AppRouteNames.assetNewWealth,
                    builder: (context, state) => const WealthProductFormPage(),
                  ),
                  GoRoute(
                    path: 'corporate-action',
                    name: AppRouteNames.corporateAction,
                    builder: (context, state) => DeferredRoute(
                      load: corp_action_lib.loadLibrary,
                      builder: (_) =>
                          corp_action_lib.CorporateActionEntryRoute(),
                    ),
                  ),
                  GoRoute(
                    path: 'physical/:id',
                    name: AppRouteNames.physicalAssetDetail,
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
                    name: AppRouteNames.liabilities,
                    builder: (context, state) => DeferredRoute(
                      load: liabilities_lib.loadLibrary,
                      builder: (_) => liabilities_lib.LiabilitiesPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: AppRouteNames.liabilityNew,
                        builder: (context, state) => const LiabilityFormPage(),
                      ),
                      GoRoute(
                        path: ':id',
                        name: AppRouteNames.liabilityDetail,
                        builder: (context, state) {
                          final id = state.pathParameters['id']!;
                          return DeferredRoute(
                            load: liability_detail_lib.loadLibrary,
                            builder: (_) =>
                                liability_detail_lib.LiabilityDetailPage(
                                  id: id,
                                ),
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: ':assetId',
                    name: AppRouteNames.assetDetail,
                    pageBuilder: (context, state) =>
                        buildHeroAwareTransitionPage<void>(
                          context: context,
                          state: state,
                          child: AssetDetailPage(
                            assetId: state.pathParameters['assetId']!,
                          ),
                        ),
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 2: Activity (expenses, accounts, trades) ─────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                name: AppRouteNames.activity,
                builder: (context, state) => const ActivityPage(),
                routes: [
                  GoRoute(
                    path: 'expenses',
                    name: AppRouteNames.expenses,
                    builder: (context, state) => const ExpenseListPage(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: AppRouteNames.expenseNew,
                        builder: (context, state) => const ExpenseFormPage(),
                      ),
                      GoRoute(
                        path: 'report',
                        name: AppRouteNames.expenseReport,
                        builder: (context, state) => const ExpenseReportPage(),
                      ),
                      GoRoute(
                        path: ':expenseId',
                        name: AppRouteNames.expenseDetail,
                        builder: (context, state) => ExpenseFormPage(
                          expenseId: state.pathParameters['expenseId'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'accounts',
                    name: AppRouteNames.accounts,
                    builder: (context, state) => const AccountsPage(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: AppRouteNames.accountNew,
                        builder: (context, state) => const AccountFormPage(),
                      ),
                      GoRoute(
                        path: 'transfer',
                        name: AppRouteNames.accountTransfer,
                        builder: (context, state) => const TransferFormPage(),
                      ),
                      GoRoute(
                        path: 'journal',
                        name: AppRouteNames.accountJournal,
                        builder: (context, state) =>
                            const JournalEntryListPage(),
                      ),
                      GoRoute(
                        path: ':accountId',
                        name: AppRouteNames.accountDetail,
                        pageBuilder: (context, state) =>
                            buildHeroAwareTransitionPage<void>(
                              context: context,
                              state: state,
                              child: AccountFormPage(
                                accountId: state.pathParameters['accountId'],
                              ),
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'trade',
                    name: AppRouteNames.tradeEntry,
                    pageBuilder: (context, state) {
                      final assetId = state.uri.queryParameters['assetId'];
                      final accountId = state.uri.queryParameters['accountId'];
                      return buildHeroAwareTransitionPage<void>(
                        context: context,
                        state: state,
                        child: TradeEntryFormPage(
                          assetId: assetId,
                          accountId: accountId,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 3: Plan (analytics, FIRE, rebalance) ─────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                name: AppRouteNames.plan,
                builder: (context, state) => const PlanPage(),
                routes: [
                  GoRoute(
                    path: 'analytics',
                    name: AppRouteNames.analytics,
                    builder: (context, state) => DeferredRoute(
                      load: analytics_lib.loadLibrary,
                      builder: (_) => analytics_lib.AnalyticsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'fire',
                    name: AppRouteNames.fire,
                    builder: (context, state) => DeferredRoute(
                      load: fire_lib.loadLibrary,
                      builder: (_) => fire_lib.FirePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'rebalance',
                    name: AppRouteNames.rebalance,
                    builder: (context, state) => DeferredRoute(
                      load: rebalance_lib.loadLibrary,
                      builder: (_) => rebalance_lib.RebalancePage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));
