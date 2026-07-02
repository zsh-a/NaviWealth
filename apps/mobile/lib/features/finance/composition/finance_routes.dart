/// FinanceOS routing tree (`docs/architecture/lifeos-shell.md` §3, D-2.3b).
///
/// Self-contained: every route (including deferred-as imports) lives in
/// this file so adding / removing domains is a single-file change in
/// `app/router_builder.dart`. The deferred imports also live here so
/// each domain owns its own `loadLibrary()` futures — see
/// [preloadFinanceDeferredRoutesForTest].
library;

import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../core/shell/deferred_route.dart';
import '../../../core/shell/page_transitions.dart';
import '../../../core/shell/route_error_page.dart';
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
import 'finance_domain_shell.dart';
import 'finance_route_paths.dart';

/// FinanceOS `StatefulShellRoute`: 4 branches (Today / Activity / Wealth /
/// Plan) backed by [DomainTabsShell]. Search + Settings are surfaced by the
/// shared header chrome (`core/shell/shell_chrome.dart`), not a bottom-nav slot.
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
            path: FinanceRoutes.home,
            name: FinanceRouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
        ],
      ),
      // ── Branch 1: Activity ───────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: FinanceRoutes.activity,
            name: FinanceRouteNames.activity,
            builder: (context, state) => const ActivityPage(),
            routes: [
              GoRoute(
                path: 'expenses',
                name: FinanceRouteNames.expenses,
                builder: (context, state) => const ExpenseListPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: FinanceRouteNames.expenseNew,
                    builder: (context, state) => const ExpenseFormPage(),
                  ),
                  GoRoute(
                    path: 'report',
                    name: FinanceRouteNames.expenseReport,
                    builder: (context, state) => const ExpenseReportPage(),
                  ),
                  GoRoute(
                    path: ':expenseId',
                    name: FinanceRouteNames.expenseDetail,
                    builder: (context, state) => ExpenseFormPage(
                      expenseId: state.pathParameters['expenseId'],
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'cashflow/dividends',
                name: FinanceRouteNames.cashflowDividends,
                builder: (context, state) => const DividendCenterPage(),
              ),
              GoRoute(
                path: 'trade',
                name: FinanceRouteNames.tradeEntry,
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
                name: FinanceRouteNames.transfer,
                builder: (context, state) => const TransferFormPage(),
              ),
              GoRoute(
                path: 'entry/:entryId',
                name: FinanceRouteNames.activityEntryDetail,
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
                name: FinanceRouteNames.journalEntries,
                builder: (context, state) => const JournalEntryListPage(),
              ),
              // §5.10.10 / S5a — Layer 4 ingest review queue.
              GoRoute(
                path: 'ingest',
                name: FinanceRouteNames.activityIngest,
                builder: (context, state) => const IngestReviewPage(),
              ),
            ],
          ),
          GoRoute(
            path: FinanceRoutes.cashflow,
            name: FinanceRouteNames.cashflow,
            builder: (context, state) => const CashFlowPage(),
            routes: [
              GoRoute(
                path: 'recurring',
                name: FinanceRouteNames.cashflowRecurring,
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
            path: FinanceRoutes.wealth,
            name: FinanceRouteNames.wealth,
            builder: (context, state) => const WealthHubPage(),
            routes: [
              GoRoute(
                path: 'accounts',
                name: FinanceRouteNames.wealthAccounts,
                builder: (context, state) => const AccountsPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: FinanceRouteNames.wealthAccountNew,
                    builder: (context, state) => const AccountFormPage(),
                  ),
                  GoRoute(
                    path: ':accountId',
                    name: FinanceRouteNames.wealthAccount,
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
                name: FinanceRouteNames.wealthNewCash,
                builder: (context, state) => const CashFormPage(),
              ),
              GoRoute(
                path: 'new/deposit',
                name: FinanceRouteNames.wealthNewDeposit,
                builder: (context, state) => const DepositFormPage(),
              ),
              GoRoute(
                path: 'new/wealth',
                name: FinanceRouteNames.wealthNewWealth,
                builder: (context, state) => const WealthProductFormPage(),
              ),
              GoRoute(
                path: 'corporate-action',
                name: FinanceRouteNames.wealthCorporateAction,
                builder: (context, state) => DeferredRoute(
                  load: corp_action_lib.loadLibrary,
                  builder: (_) => corp_action_lib.CorporateActionEntryRoute(),
                ),
              ),
              GoRoute(
                path: 'portfolio',
                name: FinanceRouteNames.wealthPortfolio,
                builder: (context, state) => DeferredRoute(
                  load: portfolio_hub_lib.loadLibrary,
                  builder: (_) => portfolio_hub_lib.PortfolioHubPage(),
                ),
              ),
              GoRoute(
                path: 'watchlist',
                name: FinanceRouteNames.wealthWatchlist,
                builder: (context, state) => DeferredRoute(
                  load: watchlist_lib.loadLibrary,
                  builder: (_) => watchlist_lib.WatchlistPage(),
                ),
              ),
              GoRoute(
                path: 'assets/:assetId',
                name: FinanceRouteNames.wealthAssetDetail,
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
                name: FinanceRouteNames.wealthPhysicalDetail,
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
                name: FinanceRouteNames.wealthLiabilities,
                builder: (context, state) => DeferredRoute(
                  load: liabilities_lib.loadLibrary,
                  builder: (_) => liabilities_lib.LiabilitiesPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: FinanceRouteNames.wealthLiabilityNew,
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
                    name: FinanceRouteNames.wealthLiabilityDetail,
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
            path: FinanceRoutes.plan,
            name: FinanceRouteNames.plan,
            builder: (context, state) => const PlanHubPage(),
            routes: [
              GoRoute(
                path: 'fire',
                name: FinanceRouteNames.planFire,
                builder: (context, state) => DeferredRoute(
                  load: fire_lib.loadLibrary,
                  builder: (_) => fire_lib.FirePage(),
                ),
              ),
              GoRoute(
                path: 'rebalance',
                name: FinanceRouteNames.planRebalance,
                builder: (context, state) => DeferredRoute(
                  load: rebalance_lib.loadLibrary,
                  builder: (_) => rebalance_lib.RebalancePage(),
                ),
              ),
              GoRoute(
                path: 'income',
                name: FinanceRouteNames.planIncome,
                builder: (context, state) => DeferredRoute(
                  load: income_planner_lib.loadLibrary,
                  builder: (_) => income_planner_lib.IncomePlannerPage(),
                ),
              ),
              GoRoute(
                path: 'income/stats',
                name: FinanceRouteNames.planIncomeStats,
                builder: (context, state) => DeferredRoute(
                  load: options_stats_lib.loadLibrary,
                  builder: (_) => options_stats_lib.OptionsTradeStatsPage(),
                ),
              ),
              GoRoute(
                path: 'dca',
                name: FinanceRouteNames.planDca,
                builder: (context, state) => DeferredRoute(
                  load: dca_simulator_lib.loadLibrary,
                  builder: (_) => dca_simulator_lib.DcaSimulatorPage(),
                ),
              ),
              GoRoute(
                path: 'budget',
                name: FinanceRouteNames.planBudget,
                builder: (context, state) => const PlanBudgetPage(),
              ),
              GoRoute(
                path: 'wheel',
                name: FinanceRouteNames.planWheel,
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
