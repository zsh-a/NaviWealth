import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/domain_scope.dart';
import '../core/lifeos/domain_pack.dart';
import '../features/execution/composition/execution_route_paths.dart';
import '../features/finance/composition/finance_route_paths.dart';
import '../features/health/composition/health_route_paths.dart';
import '../features/knowledge/composition/knowledge_route_paths.dart';

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
  static const home = FinanceRoutes.home;
  static const activity = FinanceRoutes.activity;
  static const wealth = FinanceRoutes.wealth;
  static const plan = FinanceRoutes.plan;

  // ── HealthOS (Phase D-2.3) — gated by domain opt-in (Health OFF by
  // default). Tabs mirror healthos-domain.md §5: Today / Trend / Plan.
  static const healthToday = HealthRoutes.today;
  static const healthTrend = HealthRoutes.trend;
  static const healthPlan = HealthRoutes.plan;

  // ── KnowledgeOS (`docs/domains/knowledgeos-domain.md` §5) — gated by domain
  // opt-in. 3 tabs: Inbox / Library / Review.
  static const knowledgeInbox = KnowledgeRoutes.inbox;
  static const knowledgeLibrary = KnowledgeRoutes.library;
  static const knowledgeReview = KnowledgeRoutes.review;
  // Detail pages live under Library. Decision has its own editable page;
  // the other typed objects (concept / experiment / principle / assumption)
  // share one read-only object page keyed by `:kind`.
  static const knowledgeDecisionDetail = KnowledgeRoutes.decisionDetail;
  static const knowledgeObjectDetail = KnowledgeRoutes.objectDetail;

  // ── ExecutionOS — optional personal action / commitment loop.
  static const executionToday = ExecutionRoutes.today;
  static const executionCommitments = ExecutionRoutes.commitments;
  static const executionReview = ExecutionRoutes.review;
  static const executionActionDetail = ExecutionRoutes.actionDetail;
  static const executionCommitmentDetail = ExecutionRoutes.commitmentDetail;

  // ── Global meta (not a tab) ────────────────────────────────────────────
  static const settings = '/settings';

  // ── Activity sub-flows (things that happen) ────────────────────────────
  static const activityExpenses = FinanceRoutes.activityExpenses;
  static const expenseNew = FinanceRoutes.expenseNew;
  static const expenseReport = FinanceRoutes.expenseReport;
  static const cashflow = FinanceRoutes.cashflow;
  static const cashflowRecurring = FinanceRoutes.cashflowRecurring;
  static const cashflowDividends = FinanceRoutes.cashflowDividends;
  static const tradeEntry = FinanceRoutes.tradeEntry;
  static const transfer = FinanceRoutes.transfer;
  static const journalEntries = FinanceRoutes.journalEntries;
  // §5.10.10 / S5a — Layer 4 ingest review queue.
  static const activityIngest = FinanceRoutes.activityIngest;

  // ── Wealth sub-flows (objects you own / owe) ───────────────────────────
  static const wealthAccounts = FinanceRoutes.wealthAccounts;
  static const wealthAccountNew = FinanceRoutes.wealthAccountNew;
  static const wealthNewCash = FinanceRoutes.wealthNewCash;
  static const wealthNewDeposit = FinanceRoutes.wealthNewDeposit;
  static const wealthNewWealth = FinanceRoutes.wealthNewWealth;
  static const wealthCorporateAction = FinanceRoutes.wealthCorporateAction;
  static const wealthLiabilities = FinanceRoutes.wealthLiabilities;
  static const wealthLiabilityNew = FinanceRoutes.wealthLiabilityNew;
  static const wealthPortfolio = FinanceRoutes.wealthPortfolio;
  static const wealthWatchlist = FinanceRoutes.wealthWatchlist;

  // ── Plan sub-flows (decisions + future state) ──────────────────────────
  static const planFire = FinanceRoutes.planFire;
  static const planRebalance = FinanceRoutes.planRebalance;
  static const planIncome = FinanceRoutes.planIncome;
  static const planIncomeStats = FinanceRoutes.planIncomeStats;
  static const planDca = FinanceRoutes.planDca;
  static const planBudget = FinanceRoutes.planBudget;
  static const planWheel = FinanceRoutes.planWheel;

  // ── Settings sub-flows ─────────────────────────────────────────────────
  static const settingsDevices = '/settings/devices';
  static const settingsFxRates = '/settings/fx-rates';
  static const settingsBackup = '/settings/backup';
  static const settingsNotifications = '/settings/notifications';
  static const settingsLogs = '/settings/logs';
  static const settingsPerformance = '/settings/performance';
  static const settingsSync = '/settings/sync';
  static const settingsAiTransparency = '/settings/ai-transparency';
  // §5.10.2 — AI chat is no longer a tab; sessions are read/replay-only
  // under Settings as part of the AI audit surface.
  static const settingsAiHistory = '/settings/ai-history';
  // §5.10.5 — user-facing privacy posture for provider-direct AI requests.
  static const settingsAiPrivacy = '/settings/ai-privacy';
  // Bring-your-own LLM key for the on-device AI runtime.
  static const settingsAiLlm = '/settings/ai-llm';
  // Investment preferences — risk appetite SSOT + advanced
  // concentration thresholds.
  static const settingsRiskThresholds = '/settings/risk-thresholds';
  // Stress-test parameters for the FIRE engine.
  static const settingsStressTest = '/settings/stress-test';
  // Monthly-expense window / override editor (powers FIRE projection).
  static const settingsMonthlyExpense = '/settings/monthly-expense';
  // LifeOS domain console — per-user opt-in toggles + per-domain ops.
  static const settingsDomains = '/settings/domains';
  static const settingsDomainsHealth = '/settings/domains/health';
  static const settingsDomainsKnowledge = '/settings/domains/knowledge';
  static const settingsDomainsExecution = '/settings/domains/execution';
  // Target allocation editor is reachable via the rebalance Custom
  // chip; settings overview links to it through a deep link for
  // discoverability.
  static const rebalanceTargetAllocation = '/rebalance/target-allocation';
  static String settingsAiTransparencyDetail(String requestId) =>
      '/settings/ai-transparency/${Uri.encodeComponent(requestId)}';

  // ── Detail-page builders ───────────────────────────────────────────────
  static String wealthAsset(String id) => FinanceRoutes.wealthAsset(id);

  static String wealthPhysical(String id) => FinanceRoutes.wealthPhysical(id);

  static String wealthLiability(String id) => FinanceRoutes.wealthLiability(id);

  static String wealthLiabilityEdit(String id) =>
      FinanceRoutes.wealthLiabilityEdit(id);

  static String wealthAccount(String id) => FinanceRoutes.wealthAccount(id);

  static String expense(String id) => FinanceRoutes.expense(id);

  static String activityEntry(String id) => FinanceRoutes.activityEntry(id);

  static String tradeForAsset(String id) => FinanceRoutes.tradeForAsset(id);

  static String executionAction(String id) => ExecutionRoutes.action(id);

  static String executionCommitment(String id) =>
      ExecutionRoutes.commitment(id);
}

/// Canonical GoRouter route names. Used by tests and named navigation
/// helpers; mirrors the [AppRoutes] structure.
abstract final class AppRouteNames {
  static const login = 'login';
  static const onboarding = 'onboarding';
  static const home = FinanceRouteNames.home;
  static const settings = 'settings';
  static const devices = 'devices';
  static const fxRates = 'fx-rates';
  static const backup = 'backup';
  static const notifications = 'notifications';
  static const logs = 'logs';
  static const performance = 'performance';
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
  static const domains = 'domains';
  static const domainsHealth = 'domains-health';
  static const domainsKnowledge = 'domains-knowledge';
  static const domainsExecution = 'domains-execution';

  // ── Wealth ──────────────────────────────────────────────────────────────
  static const wealth = FinanceRouteNames.wealth;
  static const wealthAccounts = FinanceRouteNames.wealthAccounts;
  static const wealthAccountNew = FinanceRouteNames.wealthAccountNew;
  static const wealthAccount = FinanceRouteNames.wealthAccount;
  static const wealthNewCash = FinanceRouteNames.wealthNewCash;
  static const wealthNewDeposit = FinanceRouteNames.wealthNewDeposit;
  static const wealthNewWealth = FinanceRouteNames.wealthNewWealth;
  static const wealthCorporateAction = FinanceRouteNames.wealthCorporateAction;
  static const wealthAssetDetail = FinanceRouteNames.wealthAssetDetail;
  static const wealthPhysicalDetail = FinanceRouteNames.wealthPhysicalDetail;
  static const wealthLiabilities = FinanceRouteNames.wealthLiabilities;
  static const wealthLiabilityNew = FinanceRouteNames.wealthLiabilityNew;
  static const wealthLiabilityDetail = FinanceRouteNames.wealthLiabilityDetail;
  static const wealthPortfolio = FinanceRouteNames.wealthPortfolio;
  static const wealthWatchlist = FinanceRouteNames.wealthWatchlist;

  // ── HealthOS — gated by opt-in. 3 tabs per healthos-domain.md §5. ─────
  static const healthToday = HealthRouteNames.today;
  static const healthTrend = HealthRouteNames.trend;
  static const healthPlan = HealthRouteNames.plan;

  // ── KnowledgeOS — gated by opt-in. 3 tabs per knowledgeos-domain.md §5.
  static const knowledgeInbox = KnowledgeRouteNames.inbox;
  static const knowledgeLibrary = KnowledgeRouteNames.library;
  static const knowledgeReview = KnowledgeRouteNames.review;
  static const knowledgeDecisionDetail = KnowledgeRouteNames.decisionDetail;
  static const knowledgeObjectDetail = KnowledgeRouteNames.objectDetail;

  // ── ExecutionOS — gated by opt-in. ─────────────────────────────────────
  static const executionToday = ExecutionRouteNames.today;
  static const executionCommitments = ExecutionRouteNames.commitments;
  static const executionReview = ExecutionRouteNames.review;
  static const executionActionDetail = ExecutionRouteNames.actionDetail;
  static const executionCommitmentDetail = ExecutionRouteNames.commitmentDetail;

  // ── Plan ────────────────────────────────────────────────────────────────
  static const plan = FinanceRouteNames.plan;
  static const planFire = FinanceRouteNames.planFire;
  static const planRebalance = FinanceRouteNames.planRebalance;
  static const planIncome = FinanceRouteNames.planIncome;
  static const planIncomeStats = FinanceRouteNames.planIncomeStats;
  static const planDca = FinanceRouteNames.planDca;
  static const planBudget = FinanceRouteNames.planBudget;
  static const planWheel = FinanceRouteNames.planWheel;

  // ── Activity ────────────────────────────────────────────────────────────
  static const activity = FinanceRouteNames.activity;
  static const activityEntryDetail = FinanceRouteNames.activityEntryDetail;
  static const expenses = FinanceRouteNames.expenses;
  static const expenseNew = FinanceRouteNames.expenseNew;
  static const expenseReport = FinanceRouteNames.expenseReport;
  static const cashflow = FinanceRouteNames.cashflow;
  static const cashflowRecurring = FinanceRouteNames.cashflowRecurring;
  static const expenseDetail = FinanceRouteNames.expenseDetail;
  static const cashflowDividends = FinanceRouteNames.cashflowDividends;
  static const tradeEntry = FinanceRouteNames.tradeEntry;
  static const transfer = FinanceRouteNames.transfer;
  static const journalEntries = FinanceRouteNames.journalEntries;
  static const activityIngest = FinanceRouteNames.activityIngest;
}

/// Resolve a route path to its owning LifeOS domain. Returns `null` for
/// shell-level routes (login, onboarding, /settings/*) that don't belong
/// to a single domain — callers that need a concrete domain default
/// should fall back to [DomainScope.finance] (the always-on seed
/// domain) at the call site.
///
/// Iterates [packs] (typically [domainPackRegistryProvider]) and
/// returns the first pack whose [DomainPack.tabPaths] or
/// [DomainPack.additionalPathPrefixes] owns [path]. Adding a new
/// domain therefore touches only `domain_packs.dart` — this function
/// stays domain-blind.
DomainScope? domainForRoute(List<DomainPack> packs, String path) {
  bool ownedBy(String prefix) => path == prefix || path.startsWith('$prefix/');
  for (final p in packs) {
    for (final tab in p.tabPaths) {
      if (ownedBy(tab)) return p.scope;
    }
    for (final extra in p.additionalPathPrefixes) {
      if (ownedBy(extra)) return p.scope;
    }
  }
  return null;
}

/// Primary shell tab paths in display order across active domains. Used by
/// root-tab affordances and by the global Cmd-1..N tab switcher in `app.dart`.
/// Settings is not a tab (IA contract §1).
///
/// Reads [activeDomainPacksProvider] so optional-domain tabs do not become
/// keyboard targets before the user opts in.
final primaryTabPathsProvider = Provider<List<String>>((ref) {
  final packs = ref.watch(activeDomainPacksProvider);
  return [for (final p in packs) ...p.tabPaths];
});
