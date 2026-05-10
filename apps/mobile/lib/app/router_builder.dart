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
import '../features/accounts/accounts_hub_page.dart';
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
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/backup/backup_page.dart';
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/log_viewer_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../features/settings/ui/sync_status_page.dart';
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
      // Main shell: 5-branch IndexedStack preserves tab state across switches.
      // Order matches kPrimaryTabPaths: Home / Activity / AI / Accounts /
      // Settings — AI is the centered accent tab in the bottom nav.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppRootShell(shell: shell),
        branches: [
          // ── Branch 0: Home ───────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: AppRouteNames.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          // ── Branch 1: Activity (timeline + per-entry sub-flows) ─────────
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
                  GoRoute(
                    path: 'transfer',
                    name: AppRouteNames.transfer,
                    builder: (context, state) => const TransferFormPage(),
                  ),
                  GoRoute(
                    path: 'journal',
                    name: AppRouteNames.journalEntries,
                    builder: (context, state) => const JournalEntryListPage(),
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 2: AI Assistant + Insights (FIRE/Rebalance/Analytics) ─
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.ai,
                name: AppRouteNames.aiChat,
                builder: (context, state) => DeferredRoute(
                  load: ai_chat_lib.loadLibrary,
                  builder: (_) => ai_chat_lib.AiChatPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'insights/fire',
                    name: AppRouteNames.aiInsightsFire,
                    builder: (context, state) => DeferredRoute(
                      load: fire_lib.loadLibrary,
                      builder: (_) => fire_lib.FirePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'insights/rebalance',
                    name: AppRouteNames.aiInsightsRebalance,
                    builder: (context, state) => DeferredRoute(
                      load: rebalance_lib.loadLibrary,
                      builder: (_) => rebalance_lib.RebalancePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'insights/analytics',
                    name: AppRouteNames.aiInsightsAnalytics,
                    builder: (context, state) => DeferredRoute(
                      load: analytics_lib.loadLibrary,
                      builder: (_) => analytics_lib.AnalyticsPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 3: Accounts hub (assets + liabilities + bank list) ───
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.accounts,
                name: AppRouteNames.accounts,
                builder: (context, state) => const AccountsHubPage(),
                routes: [
                  GoRoute(
                    path: 'list',
                    name: AppRouteNames.accountsList,
                    builder: (context, state) => const AccountsPage(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: AppRouteNames.accountListNew,
                        builder: (context, state) => const AccountFormPage(),
                      ),
                      GoRoute(
                        path: ':accountId',
                        name: AppRouteNames.accountListItem,
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
                    path: 'new/cash',
                    name: AppRouteNames.accountNewCash,
                    builder: (context, state) => const CashFormPage(),
                  ),
                  GoRoute(
                    path: 'new/deposit',
                    name: AppRouteNames.accountNewDeposit,
                    builder: (context, state) => const DepositFormPage(),
                  ),
                  GoRoute(
                    path: 'new/wealth',
                    name: AppRouteNames.accountNewWealth,
                    builder: (context, state) => const WealthProductFormPage(),
                  ),
                  GoRoute(
                    path: 'corporate-action',
                    name: AppRouteNames.accountCorporateAction,
                    builder: (context, state) => DeferredRoute(
                      load: corp_action_lib.loadLibrary,
                      builder: (_) =>
                          corp_action_lib.CorporateActionEntryRoute(),
                    ),
                  ),
                  GoRoute(
                    path: 'asset/:assetId',
                    name: AppRouteNames.accountAssetDetail,
                    pageBuilder: (context, state) =>
                        buildHeroAwareTransitionPage<void>(
                          context: context,
                          state: state,
                          child: AssetDetailPage(
                            assetId: state.pathParameters['assetId']!,
                          ),
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
                ],
              ),
            ],
          ),
          // ── Branch 4: Settings ───────────────────────────────────────────
          StatefulShellBranch(
            routes: [
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
                  GoRoute(
                    path: 'sync',
                    name: AppRouteNames.sync,
                    builder: (context, state) => const SyncStatusPage(),
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
