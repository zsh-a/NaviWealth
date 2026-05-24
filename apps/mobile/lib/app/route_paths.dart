/// Canonical route paths for NaviWealth's information architecture.
///
/// **IA authority lives in `apps/mobile/docs/design/00-information-architecture.md`.**
/// If this file and that document disagree, the document wins — update the
/// routes to match it, not the other way around.
///
/// ## Target IA (the contract, 2026-05-24)
///
/// Primary tabs:    Today / Activity / Wealth / Plan
/// Global meta:     Settings (via Today top-right ⚙, not a tab)
/// Global entry:    Search / command palette (bottom-nav center slot)
/// AI:              never a tab — palette + inline capsules + /settings/ai-history
///
/// ### Tab boundaries (the contract — apply BEFORE adding a new route)
///
/// - **Today**     = read-only operating dashboard. CTA-only, no editing.
/// - **Activity**  = immutable event history + entry (expense/trade/transfer/...).
/// - **Wealth**    = owned objects + current state (accounts/holdings/liabilities).
/// - **Plan**      = decisions + future state (FIRE/rebalance/income/scenarios).
/// - **Settings**  = global preferences only — never `/plan/settings` or
///                   `/wealth/settings`; deep-link into `/settings/<thing>` instead.
///
/// "Analytics" is NOT a section name — split per object:
///   Wealth → Portfolio Analytics, Plan → Scenario Analytics / FIRE Projection.
///
/// ## Migration phases
///
/// - **Phase A** (this file): canonical strings are now `/wealth/*` and
///   `/plan/*`. Legacy `/accounts/*` literal strings are preserved via
///   redirect routes in `router_builder.dart` so external deep links and
///   chat history continue resolving. Internal callers MUST use the new
///   constant names (e.g. `AppRoutes.planFire`, not the deprecated
///   `accountsFire` alias).
/// - **Phase B**: Plan hub real hero + decision chain (separate work).
/// - **Phase C**: Wealth hub rewrite (separate work).
abstract final class AppRoutes {
  // ── Auth ────────────────────────────────────────────────────────────────
  static const login = '/login';
  static const onboarding = '/onboarding';

  // ── Primary tabs ────────────────────────────────────────────────────────
  static const home = '/';
  static const activity = '/activity';
  static const wealth = '/wealth';
  static const plan = '/plan';

  // ── Global meta (not a tab) ────────────────────────────────────────────
  static const settings = '/settings';

  // ── Activity sub-flows (things that happen) ────────────────────────────
  static const activityExpenses = '/activity/expenses';
  static const expenseNew = '/activity/expenses/new';
  static const expenseReport = '/activity/expenses/report';
  static const cashflow = '/cashflow';
  static const cashflowRecurring = '/cashflow/recurring';
  static const cashflowDividends = '/activity/cashflow/dividends';
  static const tradeEntry = '/activity/trade';
  static const transfer = '/activity/transfer';
  static const journalEntries = '/activity/journal';
  // §5.10.10 / S5a — Layer 4 ingest review queue.
  static const activityIngest = '/activity/ingest';

  // ── Wealth sub-flows (objects you own / owe) ───────────────────────────
  static const wealthAccounts = '/wealth/accounts';
  static const wealthAccountNew = '/wealth/accounts/new';
  static const wealthNewCash = '/wealth/new/cash';
  static const wealthNewDeposit = '/wealth/new/deposit';
  static const wealthNewWealth = '/wealth/new/wealth';
  static const wealthCorporateAction = '/wealth/corporate-action';
  static const wealthLiabilities = '/wealth/liabilities';
  static const wealthLiabilityNew = '/wealth/liabilities/new';
  static const wealthPortfolio = '/wealth/portfolio';
  static const wealthWatchlist = '/wealth/watchlist';
  // §4 of IA contract: Wealth/Dividends is renamed to "Income Projection"
  // (a property of holdings) to disambiguate from Activity/Dividends-Received
  // (the event stream). Path uses the contract name.
  static const wealthIncomeProjection = '/wealth/income-projection';

  // ── Plan sub-flows (decisions + future state) ──────────────────────────
  static const planFire = '/plan/fire';
  static const planRebalance = '/plan/rebalance';
  static const planIncome = '/plan/income';
  static const planDca = '/plan/dca';
  // §4 of IA contract: was "Analytics" (top-level dashboard); split per
  // object — this one is "Scenario Analytics / FIRE Projection".
  static const planProjection = '/plan/projection';
  static const planScenarios = '/plan/scenarios';
  static const planGoals = '/plan/goals';

  // ── Settings sub-flows ─────────────────────────────────────────────────
  static const settingsDevices = '/settings/devices';
  static const settingsFxRates = '/settings/fx-rates';
  static const settingsBackup = '/settings/backup';
  static const settingsLogs = '/settings/logs';
  static const settingsSync = '/settings/sync';
  static const settingsAiTransparency = '/settings/ai-transparency';
  // §5.10.2 — AI chat is no longer a tab; sessions are read/replay-only
  // under Settings as part of the AI audit surface.
  static const settingsAiHistory = '/settings/ai-history';
  // §5.10.5 — user-facing privacy posture for cloud-bound AI requests.
  static const settingsAiPrivacy = '/settings/ai-privacy';
  // §4.6 W-D1 — bring-your-own LLM key for the on-device AI runtime.
  static const settingsAiLlm = '/settings/ai-llm';
  // Investment preferences — risk appetite SSOT + advanced
  // concentration thresholds.
  static const settingsRiskThresholds = '/settings/risk-thresholds';
  // Stress-test parameters for the FIRE engine.
  static const settingsStressTest = '/settings/stress-test';
  // Monthly-expense window / override editor (powers FIRE projection).
  static const settingsMonthlyExpense = '/settings/monthly-expense';
  // Target allocation editor is reachable via the rebalance Custom
  // chip; settings overview links to it through a deep link for
  // discoverability.
  static const rebalanceTargetAllocation = '/rebalance/target-allocation';
  static String settingsAiTransparencyDetail(String requestId) =>
      '/settings/ai-transparency/${Uri.encodeComponent(requestId)}';

  // ── Detail-page builders ───────────────────────────────────────────────
  static String wealthAsset(String id) =>
      '/wealth/assets/${Uri.encodeComponent(id)}';

  static String wealthPhysical(String id) =>
      '/wealth/physical/${Uri.encodeComponent(id)}';

  static String wealthLiability(String id) =>
      '/wealth/liabilities/${Uri.encodeComponent(id)}';

  static String wealthAccount(String id) =>
      '/wealth/accounts/${Uri.encodeComponent(id)}';

  static String expense(String id) =>
      '/activity/expenses/${Uri.encodeComponent(id)}';

  static String activityEntry(String id) =>
      '/activity/entry/${Uri.encodeComponent(id)}';

  static String tradeForAsset(String id) =>
      '$tradeEntry?assetId=${Uri.encodeQueryComponent(id)}';

  // ── Deprecated aliases (Phase A bridge) ────────────────────────────────
  // Keep these so older code paths (and the AI tool catalog that ships
  // route hints in trace payloads) keep compiling during the migration.
  // Internal new code must use the canonical names above. These can be
  // deleted in Phase D after all callers and tests are clean.
  @Deprecated('Use AppRoutes.wealth')
  static const accounts = wealth;
  @Deprecated('Use AppRoutes.wealthAccounts')
  static const accountsList = wealthAccounts;
  @Deprecated('Use AppRoutes.wealthAccountNew')
  static const accountListNew = wealthAccountNew;
  @Deprecated('Use AppRoutes.wealthNewCash')
  static const accountNewCash = wealthNewCash;
  @Deprecated('Use AppRoutes.wealthNewDeposit')
  static const accountNewDeposit = wealthNewDeposit;
  @Deprecated('Use AppRoutes.wealthNewWealth')
  static const accountNewWealth = wealthNewWealth;
  @Deprecated('Use AppRoutes.wealthCorporateAction')
  static const accountCorporateAction = wealthCorporateAction;
  @Deprecated('Use AppRoutes.wealthLiabilities')
  static const liabilities = wealthLiabilities;
  @Deprecated('Use AppRoutes.wealthLiabilityNew')
  static const liabilityNew = wealthLiabilityNew;
  @Deprecated('Use AppRoutes.planFire')
  static const accountsFire = planFire;
  @Deprecated('Use AppRoutes.planRebalance')
  static const accountsRebalance = planRebalance;
  @Deprecated('Use AppRoutes.planProjection')
  static const accountsAnalytics = planProjection;
  @Deprecated('Use AppRoutes.planIncome')
  static const accountsIncomePlanner = planIncome;
  @Deprecated('Use AppRoutes.wealthPortfolio')
  static const accountsPortfolioHub = wealthPortfolio;
  @Deprecated('Use AppRoutes.wealthWatchlist')
  static const accountsWatchlist = wealthWatchlist;
  @Deprecated('Use AppRoutes.planDca')
  static const accountsDcaSimulator = planDca;
  @Deprecated('Use AppRoutes.wealthIncomeProjection')
  static const accountsDividends = wealthIncomeProjection;

  @Deprecated('Use AppRoutes.wealthAsset()')
  static String accountAsset(String id) => wealthAsset(id);
  @Deprecated('Use AppRoutes.wealthPhysical()')
  static String physicalAsset(String id) => wealthPhysical(id);
  @Deprecated('Use AppRoutes.wealthLiability()')
  static String liability(String id) => wealthLiability(id);
  @Deprecated('Use AppRoutes.wealthAccount()')
  static String accountListItem(String id) => wealthAccount(id);
}

/// Canonical GoRouter route names. Used by tests and named navigation
/// helpers; mirrors the [AppRoutes] structure.
abstract final class AppRouteNames {
  static const login = 'login';
  static const onboarding = 'onboarding';
  static const home = 'home';
  static const settings = 'settings';
  static const devices = 'devices';
  static const fxRates = 'fx-rates';
  static const backup = 'backup';
  static const logs = 'logs';
  static const sync = 'sync';
  static const aiTransparency = 'ai-transparency';
  static const aiTransparencyDetail = 'ai-transparency-detail';
  static const aiHistory = 'ai-history';
  static const aiPrivacy = 'ai-privacy';
  static const aiLlm = 'ai-llm';
  static const riskThresholds = 'risk-thresholds';
  static const stressTest = 'stress-test';
  static const monthlyExpense = 'monthly-expense';

  // ── Wealth ──────────────────────────────────────────────────────────────
  static const wealth = 'wealth';
  static const wealthAccounts = 'wealth-accounts';
  static const wealthAccountNew = 'wealth-account-new';
  static const wealthAccount = 'wealth-account';
  static const wealthNewCash = 'wealth-new-cash';
  static const wealthNewDeposit = 'wealth-new-deposit';
  static const wealthNewWealth = 'wealth-new-wealth';
  static const wealthCorporateAction = 'wealth-corporate-action';
  static const wealthAssetDetail = 'wealth-asset-detail';
  static const wealthPhysicalDetail = 'wealth-physical-detail';
  static const wealthLiabilities = 'wealth-liabilities';
  static const wealthLiabilityNew = 'wealth-liability-new';
  static const wealthLiabilityDetail = 'wealth-liability-detail';
  static const wealthPortfolio = 'wealth-portfolio';
  static const wealthWatchlist = 'wealth-watchlist';
  static const wealthIncomeProjection = 'wealth-income-projection';

  // ── Plan ────────────────────────────────────────────────────────────────
  static const plan = 'plan';
  static const planFire = 'plan-fire';
  static const planRebalance = 'plan-rebalance';
  static const planIncome = 'plan-income';
  static const planDca = 'plan-dca';
  static const planProjection = 'plan-projection';
  static const planScenarios = 'plan-scenarios';
  static const planGoals = 'plan-goals';

  // ── Activity ────────────────────────────────────────────────────────────
  static const activity = 'activity';
  static const activityEntryDetail = 'activity-entry-detail';
  static const expenses = 'expenses';
  static const expenseNew = 'expense-new';
  static const expenseReport = 'expense-report';
  static const cashflow = 'cashflow';
  static const cashflowRecurring = 'cashflow-recurring';
  static const expenseDetail = 'expense-detail';
  static const cashflowDividends = 'cashflow-dividends';
  static const tradeEntry = 'trade-entry';
  static const transfer = 'transfer';
  static const journalEntries = 'journal-entries';
  static const activityIngest = 'activity-ingest';

  // ── Deprecated aliases (Phase A bridge) ────────────────────────────────
  @Deprecated('Use AppRouteNames.wealth')
  static const accounts = wealth;
  @Deprecated('Use AppRouteNames.wealthAccounts')
  static const accountsList = wealthAccounts;
  @Deprecated('Use AppRouteNames.wealthAccountNew')
  static const accountListNew = wealthAccountNew;
  @Deprecated('Use AppRouteNames.wealthAccount')
  static const accountListItem = wealthAccount;
  @Deprecated('Use AppRouteNames.wealthNewCash')
  static const accountNewCash = wealthNewCash;
  @Deprecated('Use AppRouteNames.wealthNewDeposit')
  static const accountNewDeposit = wealthNewDeposit;
  @Deprecated('Use AppRouteNames.wealthNewWealth')
  static const accountNewWealth = wealthNewWealth;
  @Deprecated('Use AppRouteNames.wealthCorporateAction')
  static const accountCorporateAction = wealthCorporateAction;
  @Deprecated('Use AppRouteNames.wealthAssetDetail')
  static const accountAssetDetail = wealthAssetDetail;
  @Deprecated('Use AppRouteNames.wealthPhysicalDetail')
  static const physicalAssetDetail = wealthPhysicalDetail;
  @Deprecated('Use AppRouteNames.wealthLiabilities')
  static const liabilities = wealthLiabilities;
  @Deprecated('Use AppRouteNames.wealthLiabilityNew')
  static const liabilityNew = wealthLiabilityNew;
  @Deprecated('Use AppRouteNames.wealthLiabilityDetail')
  static const liabilityDetail = wealthLiabilityDetail;
  @Deprecated('Use AppRouteNames.planFire')
  static const accountsFire = planFire;
  @Deprecated('Use AppRouteNames.planRebalance')
  static const accountsRebalance = planRebalance;
  @Deprecated('Use AppRouteNames.planProjection')
  static const accountsAnalytics = planProjection;
  @Deprecated('Use AppRouteNames.planIncome')
  static const accountsIncomePlanner = planIncome;
  @Deprecated('Use AppRouteNames.wealthPortfolio')
  static const accountsPortfolioHub = wealthPortfolio;
  @Deprecated('Use AppRouteNames.wealthWatchlist')
  static const accountsWatchlist = wealthWatchlist;
  @Deprecated('Use AppRouteNames.planDca')
  static const accountsDcaSimulator = planDca;
}

/// Primary shell tab paths in display order. See `app_shell.dart` for the
/// visual treatment. Settings is no longer a tab (IA contract §1).
const List<String> kPrimaryTabPaths = <String>[
  AppRoutes.home,
  AppRoutes.activity,
  AppRoutes.wealth,
  AppRoutes.plan,
];

const String kCashflowPath = AppRoutes.cashflow;
const String kCashflowRecurringPath = AppRoutes.cashflowRecurring;
const String kDividendCenterPath = AppRoutes.cashflowDividends;
const String kDividendsPath = AppRoutes.cashflowDividends;
