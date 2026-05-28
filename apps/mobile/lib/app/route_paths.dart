import '../core/auth/domain_scope.dart';

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
/// ## Migration status
///
/// Phases A / B / C / D all shipped. Legacy `/accounts/*` routes,
/// redirects, and `@Deprecated` aliases have been removed — there is
/// only one canonical IA now. External callers (browser history, AI
/// chat `routeHint` payloads minted before the migration) that still
/// reference `/accounts/*` will 404; rebuild affected sessions or
/// re-introduce a targeted redirect.
abstract final class AppRoutes {
  // ── Auth ────────────────────────────────────────────────────────────────
  static const login = '/login';
  static const onboarding = '/onboarding';

  // ── Primary tabs ────────────────────────────────────────────────────────
  static const home = '/';
  static const activity = '/activity';
  static const wealth = '/wealth';
  static const plan = '/plan';

  // ── HealthOS (Phase D-2.3) — gated by domain opt-in (Health OFF by
  // default). Tabs mirror healthos-domain.md §5: Today / Trend / Plan.
  static const healthToday = '/health';
  static const healthTrend = '/health/trend';
  static const healthPlan = '/health/plan';

  // ── KnowledgeOS (`docs/knowledgeos-domain.md` §5) — gated by domain
  // opt-in. 3 tabs: Inbox / Library / Review.
  static const knowledgeInbox = '/knowledge';
  static const knowledgeLibrary = '/knowledge/library';
  static const knowledgeReview = '/knowledge/review';
  // Detail pages live under Library — only Decision exists today;
  // other types' details land per §14.2 P0 follow-ups.
  static const knowledgeDecisionDetail = '/knowledge/library/decision/:id';

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
  static const planBudget = '/plan/budget';
  static const planWheel = '/plan/wheel';
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
  static const aiModels = 'ai-models';
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

  // ── HealthOS (Phase D-2.3 placeholder, real pages in D-2.2) ────────────
  static const healthToday = 'health-today';
  static const healthTrend = 'health-trend';
  static const healthPlan = 'health-plan';

  // ── KnowledgeOS — gated by opt-in. 3 tabs per knowledgeos-domain.md §5.
  static const knowledgeInbox = 'knowledge-inbox';
  static const knowledgeLibrary = 'knowledge-library';
  static const knowledgeReview = 'knowledge-review';
  static const knowledgeDecisionDetail = 'knowledge-decision-detail';

  // ── Plan ────────────────────────────────────────────────────────────────
  static const plan = 'plan';
  static const planFire = 'plan-fire';
  static const planRebalance = 'plan-rebalance';
  static const planIncome = 'plan-income';
  static const planDca = 'plan-dca';
  static const planBudget = 'plan-budget';
  static const planWheel = 'plan-wheel';
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
}

/// Resolve a route path to its owning LifeOS domain. Returns `null` for
/// shell-level routes (login, onboarding, /settings/*) that don't belong
/// to a single domain — callers that need a concrete domain default
/// should fall back to [DomainScope.finance] (the always-on seed
/// domain) at the call site.
///
/// Used by `aiContextProvider` so any AI invocation can derive its
/// domain from the current route without each call site re-implementing
/// the rule. Tabs already register canonically here, so adding a new
/// domain is one prefix line.
DomainScope? domainForRoute(String path) {
  if (path.startsWith('/health')) return DomainScope.health;
  if (path.startsWith('/knowledge')) return DomainScope.knowledge;
  if (path == AppRoutes.home ||
      path.startsWith('/activity') ||
      path.startsWith('/wealth') ||
      path.startsWith('/plan') ||
      path.startsWith('/cashflow')) {
    return DomainScope.finance;
  }
  return null;
}

/// Primary shell tab paths in display order across all active domains.
/// Used by the system-back handler in `app_dock_shell.dart` to detect
/// "at a primary tab root" (where back jumps to Home instead of popping
/// up). Settings is not a tab (IA contract §1). D-2.3b: Health paths
/// join Finance — they're equally "primary" inside the dock shell.
const List<String> kPrimaryTabPaths = <String>[
  // Finance
  AppRoutes.home,
  AppRoutes.activity,
  AppRoutes.wealth,
  AppRoutes.plan,
  // Health (D-2.3b)
  AppRoutes.healthToday,
  AppRoutes.healthTrend,
  AppRoutes.healthPlan,
  // KnowledgeOS
  AppRoutes.knowledgeInbox,
  AppRoutes.knowledgeLibrary,
  AppRoutes.knowledgeReview,
];

const String kCashflowPath = AppRoutes.cashflow;
const String kCashflowRecurringPath = AppRoutes.cashflowRecurring;
const String kDividendCenterPath = AppRoutes.cashflowDividends;
const String kDividendsPath = AppRoutes.cashflowDividends;
