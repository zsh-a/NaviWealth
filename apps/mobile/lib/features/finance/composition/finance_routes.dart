/// FinanceOS routing tree (`docs/architecture/lifeos-shell.md` §3, D-2.3b).
///
/// Self-contained: every route (including deferred-as imports) lives in
/// this file so adding / removing domains is a single-file change in
/// `app/router_builder.dart`. The deferred imports also live here so
/// each domain owns its own `loadLibrary()` futures — see
/// [preloadFinanceDeferredRoutesForTest].
library;

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

import '../../../core/shell/app_go_route.dart';
import '../../../core/shell/deferred_route.dart';
import '../../../core/shell/domain_tabs_shell.dart';
import '../../../core/shell/route_error_page.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../accounts/ui/account_detail_page.dart';
import '../accounts/ui/account_form_page.dart';
import '../accounts/ui/accounts_page.dart';
import '../accounts/ui/transfer_form_page.dart';
import '../activity/ui/activity_entry_detail_page.dart';
import '../activity/ui/activity_page.dart';
import '../cashflow/ui/income_form_page.dart';
import '../inbox/ui/financial_inbox_page.dart';
import '../ingest/domain/ingest_models.dart';
import '../ingest/ui/ingest_review_page.dart';
import '../investment/domain/trade_entry/trade_entry_prefill.dart';
import '../monthly_close/ui/monthly_close_page.dart';
import '../rebalance/ui/rebalance_execution_workspace_page.dart'
    deferred as rebalance_execution_lib;
import '../rebalance/ui/rebalance_page.dart' deferred as rebalance_lib;
import '../ui/finance_amount_privacy_scope.dart';
import '../ui/plan_hub_page.dart';
import '../ui/wealth/wealth_hub_page.dart';
import 'finance_domain_shell.dart';
import 'finance_route_paths.dart';
import 'route_prefill.dart';

/// FinanceOS `StatefulShellRoute`: 4 branches (Today / Activity / Wealth /
/// Plan) backed by [DomainTabsShell]. Search + Settings are surfaced by the
/// shared header chrome (`core/shell/shell_chrome.dart`), not a bottom-nav slot.
StatefulShellRoute financeShellRoute() {
  return StatefulShellRoute.indexedStack(
    pageBuilder: (context, state, shell) => NoTransitionPage<void>(
      key: state.pageKey,
      child: FinanceAmountPrivacyScope(
        child: DomainTabsShell(
          shell: shell,
          spec: financeDomainShell(AppLocalizations.of(context)),
        ),
      ),
    ),
    branches: [
      // ── Branch 0: Today ──────────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          AppGoRoute(
            path: FinanceRoutes.home,
            name: FinanceRouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
        ],
      ),
      // ── Branch 1: Activity ───────────────────────────────────────────
      StatefulShellBranch(
        routes: [
          AppGoRoute(
            path: FinanceRoutes.activity,
            name: FinanceRouteNames.activity,
            builder: (context, state) => const ActivityPage(),
            routes: [
              AppGoRoute(
                path: 'inbox',
                name: FinanceRouteNames.activityInbox,
                builder: (context, state) => const FinancialInboxPage(),
              ),
              AppGoRoute(
                path: 'monthly-close',
                name: FinanceRouteNames.activityMonthlyClose,
                builder: (context, state) => const MonthlyClosePage(),
              ),
              AppGoRoute(
                path: 'spending',
                name: FinanceRouteNames.spending,
                builder: (context, state) => const SpendingPage(),
              ),
              AppGoRoute(
                path: 'expense/new',
                name: FinanceRouteNames.expenseNew,
                builder: (context, state) => const ExpenseFormPage(),
              ),
              AppGoRoute(
                path: 'income/new',
                name: FinanceRouteNames.incomeNew,
                builder: (context, state) => const IncomeFormPage(),
              ),
              AppGoRoute(
                path: 'expense/:expenseId',
                name: FinanceRouteNames.expenseDetail,
                builder: (context, state) => ExpenseFormPage(
                  expenseId: state.pathParameters['expenseId'],
                ),
              ),
              AppGoRoute(
                path: 'cashflow',
                name: FinanceRouteNames.cashflow,
                builder: (context, state) => const CashFlowPage(),
                routes: [
                  AppGoRoute(
                    path: 'recurring',
                    name: FinanceRouteNames.cashflowRecurring,
                    builder: (context, state) =>
                        const RecurringTransactionsPage(),
                  ),
                ],
              ),
              AppGoRoute(
                path: 'trade',
                name: FinanceRouteNames.tradeEntry,
                builder: (context, state) {
                  final params = state.uri.queryParameters;
                  final extra = state.extra;
                  final initialType = tradeTypeFromSideQuery(params);
                  return TradeEntryFormPage(
                    assetId: params['assetId'],
                    accountId: params['accountId'],
                    ingestDraft: extra is IngestDraft ? extra : null,
                    // Upstream workflows (DCA batch, rebalance) hand off a
                    // fully-built prefill via extra; the ingest queue uses
                    // query params instead (§5.10.10 / S5a).
                    prefill: extra is TradeEntryPrefill
                        ? extra
                        : tradeEntryPrefillFromQuery(
                            params,
                            initialType: initialType,
                          ),
                    initialType: initialType,
                  );
                },
              ),
              AppGoRoute(
                path: 'transfer',
                name: FinanceRouteNames.transfer,
                builder: (context, state) {
                  final extra = state.extra;
                  return TransferFormPage(
                    ingestDraft: extra is IngestDraft ? extra : null,
                  );
                },
              ),
              AppGoRoute(
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
              AppGoRoute(
                path: 'journal',
                name: FinanceRouteNames.journalEntries,
                // Activity is the canonical ledger. Keep the old URL without
                // maintaining a second list for the same journal entries.
                redirect: (context, state) => FinanceRoutes.activity,
              ),
              // §5.10.10 / S5a — Layer 4 ingest review queue.
              AppGoRoute(
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
          AppGoRoute(
            path: FinanceRoutes.wealth,
            name: FinanceRouteNames.wealth,
            builder: (context, state) => const WealthHubPage(),
            routes: [
              AppGoRoute(
                path: 'accounts',
                name: FinanceRouteNames.wealthAccounts,
                builder: (context, state) => const AccountsPage(),
                routes: [
                  AppGoRoute(
                    path: 'new',
                    name: FinanceRouteNames.wealthAccountNew,
                    builder: (context, state) => const AccountFormPage(),
                  ),
                  AppGoRoute(
                    path: ':accountId/edit',
                    builder: (context, state) => AccountFormPage(
                      accountId: state.pathParameters['accountId'],
                    ),
                  ),
                  AppGoRoute(
                    path: ':accountId',
                    name: FinanceRouteNames.wealthAccount,
                    builder: (context, state) => AccountDetailPage(
                      accountId: state.pathParameters['accountId']!,
                    ),
                  ),
                ],
              ),
              AppGoRoute(
                path: 'new/cash',
                name: FinanceRouteNames.wealthNewCash,
                builder: (context, state) => CashFormPage(
                  initialAccountId: state.uri.queryParameters['accountId'],
                ),
              ),
              AppGoRoute(
                path: 'new/deposit',
                name: FinanceRouteNames.wealthNewDeposit,
                builder: (context, state) => const DepositFormPage(),
              ),
              AppGoRoute(
                path: 'new/wealth',
                name: FinanceRouteNames.wealthNewWealth,
                builder: (context, state) => const WealthProductFormPage(),
              ),
              AppGoRoute(
                path: 'corporate-action',
                name: FinanceRouteNames.wealthCorporateAction,
                builder: (context, state) => DeferredRoute(
                  load: corp_action_lib.loadLibrary,
                  builder: (_) => corp_action_lib.CorporateActionEntryRoute(),
                ),
              ),
              AppGoRoute(
                path: 'portfolio',
                name: FinanceRouteNames.wealthPortfolio,
                builder: (context, state) => DeferredRoute(
                  load: portfolio_hub_lib.loadLibrary,
                  builder: (_) => portfolio_hub_lib.PortfolioHubPage(),
                ),
                routes: [
                  AppGoRoute(
                    path: 'plan',
                    name: FinanceRouteNames.wealthPortfolioPlan,
                    builder: (context, state) => DeferredRoute(
                      load: portfolio_hub_lib.loadLibrary,
                      builder: (_) => portfolio_hub_lib.PortfolioPlanPage(),
                    ),
                  ),
                  AppGoRoute(
                    path: 'assign/positions',
                    name: FinanceRouteNames.wealthPortfolioAssignLots,
                    builder: (context, state) => DeferredRoute(
                      load: portfolio_hub_lib.loadLibrary,
                      builder: (_) =>
                          portfolio_hub_lib.PortfolioLotAssignmentPage(
                            preferredGroupId:
                                state.uri.queryParameters['group'],
                          ),
                    ),
                  ),
                  AppGoRoute(
                    path: 'assign/cash',
                    name: FinanceRouteNames.wealthPortfolioAssignCash,
                    builder: (context, state) => DeferredRoute(
                      load: portfolio_hub_lib.loadLibrary,
                      builder: (_) =>
                          portfolio_hub_lib.PortfolioCashAssignmentPage(
                            preferredGroupId:
                                state.uri.queryParameters['group'],
                            suggestedAmount: decimalFromQuery(
                              state.uri.queryParameters,
                              'amount',
                            ),
                          ),
                    ),
                  ),
                  AppGoRoute(
                    path: 'dividends',
                    name: FinanceRouteNames.cashflowDividends,
                    builder: (context, state) => DividendCenterPage(
                      focusAssetId: state.uri.queryParameters['assetId'],
                    ),
                  ),
                  AppGoRoute(
                    path: ':portfolioId/studio',
                    name: FinanceRouteNames.wealthPortfolioStudio,
                    builder: (context, state) => DeferredRoute(
                      load: portfolio_hub_lib.loadLibrary,
                      builder: (_) => portfolio_hub_lib.PortfolioStudioPage(
                        portfolioId: state.pathParameters['portfolioId']!,
                        initialSection: PortfolioStudioSection.values
                            .firstWhere(
                              (section) =>
                                  section.name ==
                                  state.uri.queryParameters['section'],
                              orElse: () => PortfolioStudioSection.overview,
                            ),
                        transferIntent: CapitalTransferIntent.fromQuery(
                          state.uri.queryParameters,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AppGoRoute(
                path: 'watchlist',
                name: FinanceRouteNames.wealthWatchlist,
                builder: (context, state) => DeferredRoute(
                  load: watchlist_lib.loadLibrary,
                  builder: (_) => watchlist_lib.WatchlistPage(),
                ),
                routes: [
                  AppGoRoute(
                    path: 'collections/:collectionId/simulations',
                    builder: (context, state) => DeferredRoute(
                      load: watchlist_lib.loadLibrary,
                      builder: (_) => watchlist_lib.WatchlistSimulationsPage(
                        collectionId: state.pathParameters['collectionId']!,
                        initialSimulationId:
                            state.uri.queryParameters['simulationId'],
                      ),
                    ),
                  ),
                ],
              ),
              AppGoRoute(
                path: 'assets/:assetId/edit',
                builder: (context, state) => ManualAssetEditRoute(
                  assetId: state.pathParameters['assetId']!,
                ),
              ),
              AppGoRoute(
                path: 'assets/:assetId',
                name: FinanceRouteNames.wealthAssetDetail,
                builder: (context, state) =>
                    AssetDetailPage(assetId: state.pathParameters['assetId']!),
              ),
              AppGoRoute(
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
              AppGoRoute(
                path: 'liabilities',
                name: FinanceRouteNames.wealthLiabilities,
                builder: (context, state) => DeferredRoute(
                  load: liabilities_lib.loadLibrary,
                  builder: (_) => liabilities_lib.LiabilitiesPage(),
                ),
                routes: [
                  AppGoRoute(
                    path: 'new',
                    name: FinanceRouteNames.wealthLiabilityNew,
                    builder: (context, state) => const LiabilityFormPage(),
                  ),
                  AppGoRoute(
                    path: ':id/edit',
                    builder: (context, state) => LiabilityFormPage(
                      liabilityId: state.pathParameters['id'],
                    ),
                  ),
                  AppGoRoute(
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
          AppGoRoute(
            path: FinanceRoutes.plan,
            name: FinanceRouteNames.plan,
            builder: (context, state) => const PlanHubPage(),
            routes: [
              AppGoRoute(
                path: 'fire',
                name: FinanceRouteNames.planFire,
                builder: (context, state) => DeferredRoute(
                  load: fire_lib.loadLibrary,
                  builder: (_) => fire_lib.FirePage(),
                ),
              ),
              AppGoRoute(
                path: 'rebalance',
                name: FinanceRouteNames.planRebalance,
                builder: (context, state) => DeferredRoute(
                  load: rebalance_lib.loadLibrary,
                  builder: (_) => rebalance_lib.RebalancePage(),
                ),
                routes: [
                  AppGoRoute(
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
              AppGoRoute(
                path: 'income',
                name: FinanceRouteNames.planIncome,
                builder: (context, state) => DeferredRoute(
                  load: income_strategy_lib.loadLibrary,
                  builder: (_) => income_strategy_lib.IncomeStrategyPage(),
                ),
              ),
              AppGoRoute(
                path: 'income/options',
                name: FinanceRouteNames.planIncomeOptions,
                builder: (context, state) => DeferredRoute(
                  load: income_planner_lib.loadLibrary,
                  builder: (_) => income_planner_lib.IncomePlannerPage(),
                ),
              ),
              AppGoRoute(
                path: 'income/stats',
                name: FinanceRouteNames.planIncomeStats,
                builder: (context, state) => DeferredRoute(
                  load: options_stats_lib.loadLibrary,
                  builder: (_) => options_stats_lib.OptionsTradeStatsPage(),
                ),
              ),
              AppGoRoute(
                path: 'income/wheel',
                name: FinanceRouteNames.planWheel,
                builder: (context, state) => DeferredRoute(
                  load: wheel_lib.loadLibrary,
                  builder: (_) => wheel_lib.WheelLifecyclePage(),
                ),
              ),
              AppGoRoute(
                path: 'dca',
                name: FinanceRouteNames.planDca,
                builder: (context, state) => DeferredRoute(
                  load: dca_simulator_lib.loadLibrary,
                  builder: (_) => dca_simulator_lib.DcaSimulatorPage(),
                ),
              ),
              AppGoRoute(
                path: 'runway',
                name: FinanceRouteNames.planRunway,
                builder: (context, state) => const MoneyRunwayPage(),
              ),
              AppGoRoute(
                path: 'life-events',
                name: FinanceRouteNames.planLifeEvents,
                builder: (context, state) => const LifeEventScenariosPage(),
              ),
              AppGoRoute(
                path: 'budget',
                name: FinanceRouteNames.planBudget,
                builder: (context, state) => const PlanBudgetPage(),
              ),
              AppGoRoute(
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
