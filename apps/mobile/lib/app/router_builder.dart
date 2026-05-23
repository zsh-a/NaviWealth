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
import '../features/activity/ui/activity_entry_detail_page.dart';
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
import '../features/auth/presentation/onboarding_page.dart';
import '../features/cashflow/ui/cashflow_page.dart';
import '../features/cashflow/ui/dividend_center_page.dart';
import '../features/cashflow/ui/recurring_transactions_page.dart';
import '../features/expense/ui/expense_form_page.dart';
import '../features/expense/ui/expense_list_page.dart';
import '../features/expense/ui/expense_report_page.dart';
import '../features/fire/presentation/fire_page.dart' deferred as fire_lib;
import '../features/home/home_page.dart';
import '../features/ingest/ui/ingest_review_page.dart';
import '../features/investment/presentation/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import '../features/investment/presentation/dca_simulator_page.dart'
    deferred as dca_simulator_lib;
import '../features/investment/presentation/portfolio_hub_page.dart'
    deferred as portfolio_hub_lib;
import '../features/investment/presentation/trade_entry_form_page.dart';
import '../features/investment/presentation/watchlist_page.dart'
    deferred as watchlist_lib;
import '../features/liabilities/ui/liabilities_page.dart'
    deferred as liabilities_lib;
import '../features/liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import '../features/liabilities/ui/liability_form_page.dart';
import '../features/options_income/presentation/income_planner_page.dart'
    deferred as income_planner_lib;
import '../features/rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../features/settings/backup/backup_page.dart';
import '../features/settings/fx_rates/fx_rates_page.dart';
import '../features/settings/log_viewer_page.dart';
import '../features/settings/settings_page.dart' deferred as settings_lib;
import '../features/settings/ui/ai_llm_credentials_page.dart';
import '../features/settings/ui/ai_privacy_page.dart';
import '../features/settings/ui/ai_transparency_page.dart';
import '../features/settings/ui/risk_thresholds_page.dart';
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
    income_planner_lib.loadLibrary(),
    liabilities_lib.loadLibrary(),
    liability_detail_lib.loadLibrary(),
    physical_detail_lib.loadLibrary(),
    corp_action_lib.loadLibrary(),
    dca_simulator_lib.loadLibrary(),
    portfolio_hub_lib.loadLibrary(),
    watchlist_lib.loadLibrary(),
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
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRouteNames.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      // Main shell: 4-branch IndexedStack preserves tab state across switches.
      // Order matches kPrimaryTabPaths: Home / Activity / Accounts / Settings.
      // The former `/ai` tab is gone (§5.10) — AI is now an overlay (command
      // palette) + inline capsules, not a destination.
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
                    path: 'cashflow/dividends',
                    name: AppRouteNames.cashflowDividends,
                    builder: (context, state) => const DividendCenterPage(),
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
                    path: 'entry/:entryId',
                    name: AppRouteNames.activityEntryDetail,
                    builder: (context, state) {
                      final extra = state.extra;
                      if (extra is ActivityEntryDetailArgs) {
                        return ActivityEntryDetailPage(
                          entry: extra.entry,
                          accountsById: extra.accountsById,
                        );
                      }
                      return RouteErrorPage(state: state);
                    },
                  ),
                  GoRoute(
                    path: 'journal',
                    name: AppRouteNames.journalEntries,
                    builder: (context, state) => const JournalEntryListPage(),
                  ),
                  // §5.10.10 / S5a — Layer 4 ingest review queue.
                  GoRoute(
                    path: 'ingest',
                    name: AppRouteNames.activityIngest,
                    builder: (context, state) => const IngestReviewPage(),
                  ),
                ],
              ),
              GoRoute(
                path: AppRoutes.cashflow,
                name: AppRouteNames.cashflow,
                builder: (context, state) => const CashFlowPage(),
                routes: [
                  GoRoute(
                    path: 'recurring',
                    name: AppRouteNames.cashflowRecurring,
                    builder: (context, state) =>
                        const RecurringTransactionsPage(),
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 2: Accounts hub (assets + liabilities + bank list +
          //              plan dashboards: FIRE / Rebalance / Analytics) ─────
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
                    path: 'fire',
                    name: AppRouteNames.accountsFire,
                    builder: (context, state) => DeferredRoute(
                      load: fire_lib.loadLibrary,
                      builder: (_) => fire_lib.FirePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'rebalance',
                    name: AppRouteNames.accountsRebalance,
                    builder: (context, state) => DeferredRoute(
                      load: rebalance_lib.loadLibrary,
                      builder: (_) => rebalance_lib.RebalancePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'income',
                    name: AppRouteNames.accountsIncomePlanner,
                    builder: (context, state) => DeferredRoute(
                      load: income_planner_lib.loadLibrary,
                      builder: (_) => income_planner_lib.IncomePlannerPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'portfolio',
                    name: AppRouteNames.accountsPortfolioHub,
                    builder: (context, state) => DeferredRoute(
                      load: portfolio_hub_lib.loadLibrary,
                      builder: (_) => portfolio_hub_lib.PortfolioHubPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'dca',
                    name: AppRouteNames.accountsDcaSimulator,
                    builder: (context, state) => DeferredRoute(
                      load: dca_simulator_lib.loadLibrary,
                      builder: (_) => dca_simulator_lib.DcaSimulatorPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'watchlist',
                    name: AppRouteNames.accountsWatchlist,
                    builder: (context, state) => DeferredRoute(
                      load: watchlist_lib.loadLibrary,
                      builder: (_) => watchlist_lib.WatchlistPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'analytics',
                    name: AppRouteNames.accountsAnalytics,
                    builder: (context, state) => DeferredRoute(
                      load: analytics_lib.loadLibrary,
                      builder: (_) => analytics_lib.AnalyticsPage(),
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
          // ── Branch 3: Settings ───────────────────────────────────────────
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
                  GoRoute(
                    path: 'ai-history',
                    name: AppRouteNames.aiHistory,
                    builder: (context, state) => DeferredRoute(
                      load: ai_chat_lib.loadLibrary,
                      builder: (_) => ai_chat_lib.AiChatPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'ai-privacy',
                    name: AppRouteNames.aiPrivacy,
                    builder: (context, state) => const AiPrivacyPage(),
                  ),
                  GoRoute(
                    path: 'ai-llm',
                    name: AppRouteNames.aiLlm,
                    builder: (context, state) => const AiLlmCredentialsPage(),
                  ),
                  GoRoute(
                    path: 'risk-thresholds',
                    name: AppRouteNames.riskThresholds,
                    builder: (context, state) => const RiskThresholdsPage(),
                  ),
                  GoRoute(
                    path: 'ai-transparency',
                    name: AppRouteNames.aiTransparency,
                    builder: (context, state) => const AiTransparencyPage(),
                    routes: [
                      GoRoute(
                        path: ':requestId',
                        name: AppRouteNames.aiTransparencyDetail,
                        builder: (context, state) => AiTransparencyDetailPage(
                          requestId: state.pathParameters['requestId'] ?? '',
                        ),
                      ),
                    ],
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
