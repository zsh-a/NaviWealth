/// FinanceOS routing tree (`docs/architecture/lifeos-shell.md` §3, D-2.3b).
///
/// Self-contained: every route (including deferred-as imports) lives in
/// this file so adding / removing domains is a single-file change in
/// `app/router_builder.dart`. The deferred imports also live here so
/// each domain owns its own `loadLibrary()` futures — see
/// [preloadFinanceDeferredRoutesForTest].
library;

import 'package:decimal/decimal.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/assets/physical/ui/physical_asset_detail_page.dart'
    deferred as physical_detail_lib;
import 'package:naviwealth/features/finance/assets/ui/asset_detail_page.dart';
import 'package:naviwealth/features/finance/assets/ui/cash_form_page.dart';
import 'package:naviwealth/features/finance/assets/ui/deposit_form_page.dart';
import 'package:naviwealth/features/finance/assets/ui/manual_asset_edit_page.dart';
import 'package:naviwealth/features/finance/assets/ui/wealth_product_form_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/budget_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/recurring_transactions_page.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_categories_page.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_form_page.dart';
import 'package:naviwealth/features/finance/expense/ui/spending_page.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_page.dart'
    deferred as fire_lib;
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/features/finance/income_strategy/ui/income_strategy_page.dart'
    deferred as income_strategy_lib;
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart'
    show TradeType;
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_prefill.dart';
import 'package:naviwealth/features/finance/investment/ui/corporate_action_entry_route.dart'
    deferred as corp_action_lib;
import 'package:naviwealth/features/finance/investment/ui/dca_simulator_page.dart'
    deferred as dca_simulator_lib;
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart'
    deferred as portfolio_hub_lib;
import 'package:naviwealth/features/finance/investment/ui/trade_entry_form_page.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart'
    deferred as watchlist_lib;
import 'package:naviwealth/features/finance/liabilities/ui/liabilities_page.dart'
    deferred as liabilities_lib;
import 'package:naviwealth/features/finance/liabilities/ui/liability_detail_page.dart'
    deferred as liability_detail_lib;
import 'package:naviwealth/features/finance/liabilities/ui/liability_form_page.dart';
import 'package:naviwealth/features/finance/life_events/ui/life_event_scenarios_page.dart';
import 'package:naviwealth/features/finance/options_income/ui/income_planner/income_planner_page.dart'
    deferred as income_planner_lib;
import 'package:naviwealth/features/finance/options_income/ui/options_trade_stats_page.dart'
    deferred as options_stats_lib;
import 'package:naviwealth/features/finance/options_income/ui/wheel_lifecycle_page.dart'
    deferred as wheel_lib;
import 'package:naviwealth/features/finance/runway/ui/money_runway_page.dart';

import '../../../core/shell/deferred_route.dart';
import '../../../core/shell/domain_tabs_shell.dart';
import '../../../core/shell/route_error_page.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../accounts/ui/account_detail_page.dart';
import '../accounts/ui/account_form_page.dart';
import '../accounts/ui/accounts_page.dart';
import '../accounts/ui/journal_entry_list_page.dart';
import '../accounts/ui/transfer_form_page.dart';
import '../activity/ui/activity_entry_detail_page.dart';
import '../activity/ui/activity_page.dart';
import '../inbox/ui/financial_inbox_page.dart';
import '../ingest/ui/ingest_review_page.dart';
import '../monthly_close/ui/monthly_close_page.dart';
import '../rebalance/ui/rebalance_execution_workspace_page.dart'
    deferred as rebalance_execution_lib;
import '../rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../ui/plan_hub_page.dart';
import '../ui/wealth/wealth_hub_page.dart';
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
                path: 'inbox',
                name: FinanceRouteNames.activityInbox,
                builder: (context, state) => const FinancialInboxPage(),
              ),
              GoRoute(
                path: 'monthly-close',
                name: FinanceRouteNames.activityMonthlyClose,
                builder: (context, state) => const MonthlyClosePage(),
              ),
              GoRoute(
                path: 'spending',
                name: FinanceRouteNames.spending,
                builder: (context, state) => const SpendingPage(),
              ),
              GoRoute(
                path: 'expense/new',
                name: FinanceRouteNames.expenseNew,
                builder: (context, state) => const ExpenseFormPage(),
              ),
              GoRoute(
                path: 'expense/:expenseId',
                name: FinanceRouteNames.expenseDetail,
                builder: (context, state) => ExpenseFormPage(
                  expenseId: state.pathParameters['expenseId'],
                ),
              ),
              GoRoute(
                path: 'cashflow',
                name: FinanceRouteNames.cashflow,
                builder: (context, state) => const CashFlowPage(),
                routes: [
                  GoRoute(
                    path: 'recurring',
                    name: FinanceRouteNames.cashflowRecurring,
                    builder: (context, state) =>
                        const RecurringTransactionsPage(),
                  ),
                ],
              ),
              GoRoute(
                path: 'trade',
                name: FinanceRouteNames.tradeEntry,
                builder: (context, state) {
                  final assetId = state.uri.queryParameters['assetId'];
                  final accountId = state.uri.queryParameters['accountId'];
                  final initialType =
                      switch (state.uri.queryParameters['side']) {
                        'buy' => TradeType.buy,
                        'sell' => TradeType.sell,
                        _ => null,
                      };
                  final params = state.uri.queryParameters;
                  final ingestPrefill = params['ingest'] == '1'
                      ? TradeEntryPrefill(
                          type: initialType ?? TradeType.buy,
                          quantity:
                              Decimal.tryParse(params['quantity'] ?? '') ??
                              Decimal.zero,
                          price: Decimal.tryParse(params['price'] ?? ''),
                          currency: params['currency'] ?? 'USD',
                          tradeDate: DateTime.tryParse(params['date'] ?? ''),
                          note: params['note'],
                          symbol: params['symbol'],
                        )
                      : null;
                  return TradeEntryFormPage(
                    assetId: assetId,
                    accountId: accountId,
                    prefill: ingestPrefill,
                    initialType: initialType,
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
                    path: ':accountId/edit',
                    builder: (context, state) => AccountFormPage(
                      accountId: state.pathParameters['accountId'],
                    ),
                  ),
                  GoRoute(
                    path: ':accountId',
                    name: FinanceRouteNames.wealthAccount,
                    builder: (context, state) => AccountDetailPage(
                      accountId: state.pathParameters['accountId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'new/cash',
                name: FinanceRouteNames.wealthNewCash,
                builder: (context, state) => CashFormPage(
                  initialAccountId: state.uri.queryParameters['accountId'],
                ),
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
                routes: [
                  GoRoute(
                    path: 'dividends',
                    name: FinanceRouteNames.cashflowDividends,
                    builder: (context, state) => DividendCenterPage(
                      focusAssetId: state.uri.queryParameters['assetId'],
                    ),
                  ),
                ],
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
                path: 'assets/:assetId/edit',
                builder: (context, state) => ManualAssetEditRoute(
                  assetId: state.pathParameters['assetId']!,
                ),
              ),
              GoRoute(
                path: 'assets/:assetId',
                name: FinanceRouteNames.wealthAssetDetail,
                builder: (context, state) =>
                    AssetDetailPage(assetId: state.pathParameters['assetId']!),
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
                routes: [
                  GoRoute(
                    path: 'execution/:sessionId',
                    name: FinanceRouteNames.planRebalanceExecution,
                    builder: (context, state) {
                      final sessionId = state.pathParameters['sessionId']!;
                      return DeferredRoute(
                        load: rebalance_execution_lib.loadLibrary,
                        builder: (_) =>
                            rebalance_execution_lib.RebalanceExecutionWorkspacePage(
                              sessionId: sessionId,
                            ),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'income',
                name: FinanceRouteNames.planIncome,
                builder: (context, state) => DeferredRoute(
                  load: income_strategy_lib.loadLibrary,
                  builder: (_) => income_strategy_lib.IncomeStrategyPage(),
                ),
              ),
              GoRoute(
                path: 'income/options',
                name: FinanceRouteNames.planIncomeOptions,
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
                path: 'income/wheel',
                name: FinanceRouteNames.planWheel,
                builder: (context, state) => DeferredRoute(
                  load: wheel_lib.loadLibrary,
                  builder: (_) => wheel_lib.WheelLifecyclePage(),
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
                path: 'runway',
                name: FinanceRouteNames.planRunway,
                builder: (context, state) => const MoneyRunwayPage(),
              ),
              GoRoute(
                path: 'life-events',
                name: FinanceRouteNames.planLifeEvents,
                builder: (context, state) => const LifeEventScenariosPage(),
              ),
              GoRoute(
                path: 'budget',
                name: FinanceRouteNames.planBudget,
                builder: (context, state) => const PlanBudgetPage(),
              ),
              GoRoute(
                path: 'expense-categories',
                name: FinanceRouteNames.planExpenseCategories,
                builder: (context, state) => const ExpenseCategoriesPage(),
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
    income_strategy_lib.loadLibrary(),
    income_planner_lib.loadLibrary(),
    options_stats_lib.loadLibrary(),
    wheel_lib.loadLibrary(),
    liabilities_lib.loadLibrary(),
    liability_detail_lib.loadLibrary(),
    physical_detail_lib.loadLibrary(),
    corp_action_lib.loadLibrary(),
    dca_simulator_lib.loadLibrary(),
    portfolio_hub_lib.loadLibrary(),
    watchlist_lib.loadLibrary(),
    rebalance_lib.loadLibrary(),
    rebalance_execution_lib.loadLibrary(),
  ]);
}
