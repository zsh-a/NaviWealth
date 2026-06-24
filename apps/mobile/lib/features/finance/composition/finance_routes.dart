/// FinanceOS routing tree (`docs/lifeos-shell.md` §3, D-2.3b).
///
/// Self-contained: every route (including deferred-as imports) lives in
/// this file so adding / removing domains is a single-file change in
/// `app/router_builder.dart`. The deferred imports also live here so
/// each domain owns its own `loadLibrary()` futures — see
/// [preloadFinanceDeferredRoutesForTest].
library;

import 'package:go_router/go_router.dart';

import '../../../app/deferred_route.dart';
import '../../../app/domain_tabs_shell.dart';
import '../../../app/page_transitions.dart';
import '../../../app/route_error_page.dart';
import '../../../app/route_paths.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/account_form_page.dart';
import '../../accounts/accounts_page.dart';
import '../../accounts/journal_entry_list_page.dart';
import '../../accounts/transfer_form_page.dart';
import '../../activity/activity_page.dart';
import '../../activity/ui/activity_entry_detail_page.dart';
import '../../assets/asset_detail_page.dart';
import '../../assets/cash_form_page.dart';
import '../../assets/deposit_form_page.dart';
import '../../assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import '../../assets/wealth_product_form_page.dart';
import '../../cashflow/ui/budget_page.dart';
import '../../cashflow/ui/cashflow_page.dart';
import '../../cashflow/ui/dividend_center_page.dart';
import '../../cashflow/ui/recurring_transactions_page.dart';
import '../../expense/ui/expense_form_page.dart';
import '../../expense/ui/expense_list_page.dart';
import '../../expense/ui/expense_report_page.dart';
import '../../finance_domain_shell.dart';
import '../../fire/presentation/fire_page.dart' deferred as fire_lib;
import '../../home/home_page.dart';
import '../../ingest/ui/ingest_review_page.dart';
import '../../investment/presentation/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import '../../investment/presentation/dca_simulator_page.dart'
    deferred as dca_simulator_lib;
import '../../investment/presentation/portfolio_hub_page.dart'
    deferred as portfolio_hub_lib;
import '../../investment/presentation/trade_entry_form_page.dart';
import '../../investment/presentation/watchlist_page.dart'
    deferred as watchlist_lib;
import '../../liabilities/ui/liabilities_page.dart' deferred as liabilities_lib;
import '../../liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import '../../liabilities/ui/liability_form_page.dart';
import '../../options_income/presentation/income_planner_page.dart'
    deferred as income_planner_lib;
import '../../options_income/presentation/options_trade_stats_page.dart'
    deferred as options_stats_lib;
import '../../options_income/presentation/wheel_lifecycle_page.dart';
import '../../plan/ui/plan_hub_page.dart';
import '../../rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../../wealth/ui/wealth_hub_page.dart';

/// FinanceOS `StatefulShellRoute`: 4 branches (Today / Activity / Wealth /
/// Plan) backed by [DomainTabsShell]. Search + Settings are surfaced by the
/// shared header chrome (`app/shell_chrome.dart`), not a bottom-nav slot.
StatefulShellRoute financeShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => DomainTabsShell(
      shell: shell,
      spec: financeDomainShell(AppLocalizations.of(context)),
    ),
    branches: [
      // ── Branch 0: Today ──────────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: AppRouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
        ],
      ),
      // ── Branch 1: Activity ───────────────────────────────────────────
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
                  final entryId = state.pathParameters['entryId'];
                  if (entryId == null || entryId.isEmpty) {
                    return RouteErrorPage(state: state);
                  }
                  return ActivityEntryDetailRoute(entryId: entryId);
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
                builder: (context, state) => const RecurringTransactionsPage(),
              ),
            ],
          ),
        ],
      ),
      // ── Branch 2: Wealth ─────────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.wealth,
            name: AppRouteNames.wealth,
            builder: (context, state) => const WealthHubPage(),
            routes: [
              GoRoute(
                path: 'accounts',
                name: AppRouteNames.wealthAccounts,
                builder: (context, state) => const AccountsPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: AppRouteNames.wealthAccountNew,
                    builder: (context, state) => const AccountFormPage(),
                  ),
                  GoRoute(
                    path: ':accountId',
                    name: AppRouteNames.wealthAccount,
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
                name: AppRouteNames.wealthNewCash,
                builder: (context, state) => const CashFormPage(),
              ),
              GoRoute(
                path: 'new/deposit',
                name: AppRouteNames.wealthNewDeposit,
                builder: (context, state) => const DepositFormPage(),
              ),
              GoRoute(
                path: 'new/wealth',
                name: AppRouteNames.wealthNewWealth,
                builder: (context, state) => const WealthProductFormPage(),
              ),
              GoRoute(
                path: 'corporate-action',
                name: AppRouteNames.wealthCorporateAction,
                builder: (context, state) => DeferredRoute(
                  load: corp_action_lib.loadLibrary,
                  builder: (_) => corp_action_lib.CorporateActionEntryRoute(),
                ),
              ),
              GoRoute(
                path: 'portfolio',
                name: AppRouteNames.wealthPortfolio,
                builder: (context, state) => DeferredRoute(
                  load: portfolio_hub_lib.loadLibrary,
                  builder: (_) => portfolio_hub_lib.PortfolioHubPage(),
                ),
              ),
              GoRoute(
                path: 'watchlist',
                name: AppRouteNames.wealthWatchlist,
                builder: (context, state) => DeferredRoute(
                  load: watchlist_lib.loadLibrary,
                  builder: (_) => watchlist_lib.WatchlistPage(),
                ),
              ),
              GoRoute(
                path: 'assets/:assetId',
                name: AppRouteNames.wealthAssetDetail,
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
                name: AppRouteNames.wealthPhysicalDetail,
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
                name: AppRouteNames.wealthLiabilities,
                builder: (context, state) => DeferredRoute(
                  load: liabilities_lib.loadLibrary,
                  builder: (_) => liabilities_lib.LiabilitiesPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: AppRouteNames.wealthLiabilityNew,
                    builder: (context, state) => const LiabilityFormPage(),
                  ),
                  GoRoute(
                    path: ':id/edit',
                    builder: (context, state) => LiabilityFormPage(
                      liabilityId: state.pathParameters['id'],
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    name: AppRouteNames.wealthLiabilityDetail,
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
            ],
          ),
        ],
      ),
      // ── Branch 3: Plan ───────────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.plan,
            name: AppRouteNames.plan,
            builder: (context, state) => const PlanHubPage(),
            routes: [
              GoRoute(
                path: 'fire',
                name: AppRouteNames.planFire,
                builder: (context, state) => DeferredRoute(
                  load: fire_lib.loadLibrary,
                  builder: (_) => fire_lib.FirePage(),
                ),
              ),
              GoRoute(
                path: 'rebalance',
                name: AppRouteNames.planRebalance,
                builder: (context, state) => DeferredRoute(
                  load: rebalance_lib.loadLibrary,
                  builder: (_) => rebalance_lib.RebalancePage(),
                ),
              ),
              GoRoute(
                path: 'income',
                name: AppRouteNames.planIncome,
                builder: (context, state) => DeferredRoute(
                  load: income_planner_lib.loadLibrary,
                  builder: (_) => income_planner_lib.IncomePlannerPage(),
                ),
              ),
              GoRoute(
                path: 'income/stats',
                name: AppRouteNames.planIncomeStats,
                builder: (context, state) => DeferredRoute(
                  load: options_stats_lib.loadLibrary,
                  builder: (_) => options_stats_lib.OptionsTradeStatsPage(),
                ),
              ),
              GoRoute(
                path: 'dca',
                name: AppRouteNames.planDca,
                builder: (context, state) => DeferredRoute(
                  load: dca_simulator_lib.loadLibrary,
                  builder: (_) => dca_simulator_lib.DcaSimulatorPage(),
                ),
              ),
              GoRoute(
                path: 'budget',
                name: AppRouteNames.planBudget,
                builder: (context, state) => const PlanBudgetPage(),
              ),
              GoRoute(
                path: 'wheel',
                name: AppRouteNames.planWheel,
                builder: (context, state) => const WheelLifecyclePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Test-only: eagerly resolve every FinanceOS deferred-as library so
/// subsequent [DeferredRoute] mounts see a completed `loadLibrary()`
/// future. Forwarded into by `app/router_builder.dart`'s top-level
/// preloader (which carries the `@visibleForTesting` annotation —
/// keeping it here would block that forwarding call).
Future<void> preloadFinanceDeferredRoutesForTest() async {
  await Future.wait<void>(<Future<void>>[
    fire_lib.loadLibrary(),
    income_planner_lib.loadLibrary(),
    options_stats_lib.loadLibrary(),
    liabilities_lib.loadLibrary(),
    liability_detail_lib.loadLibrary(),
    physical_detail_lib.loadLibrary(),
    corp_action_lib.loadLibrary(),
    dca_simulator_lib.loadLibrary(),
    portfolio_hub_lib.loadLibrary(),
    watchlist_lib.loadLibrary(),
    rebalance_lib.loadLibrary(),
  ]);
}
