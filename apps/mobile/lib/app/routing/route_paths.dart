import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/agents/agent_artifact_routes.dart';
import '../../core/ai/composition/assistant_route_paths.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/auth_route_paths.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../features/execution/composition/execution_route_paths.dart';
import '../../features/finance/composition/finance_route_paths.dart';
import '../../features/health/composition/health_route_paths.dart';
import '../../features/knowledge/composition/knowledge_route_paths.dart';
import '../../features/life/composition/life_route_paths.dart';

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
/// Assistant:       one workspace — palette + inline sheets + /assistant
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
  static const login = AuthRoutes.login;
  static const onboarding = AuthRoutes.onboarding;

  // ── Life hub (cross-domain spatial layer) ───────────────────────────────
  static const life = LifeRoutes.home;

  // ── Cross-domain Assistant ───────────────────────────────────────────────
  static const assistant = AssistantRoutes.home;

  // ── Cross-domain Agent result detail ───────────────────────────────────
  static const agentArtifactDetail = AgentArtifactRoutes.detailPath;
  static String agentArtifact(String id) => AgentArtifactRoutes.detail(id);

  // ── Primary tabs ────────────────────────────────────────────────────────
  static const home = FinanceRoutes.home;
  static const activity = FinanceRoutes.activity;
  static const wealth = FinanceRoutes.wealth;
  static const plan = FinanceRoutes.plan;

  // ── HealthOS (Phase D-2.3) — gated by domain opt-in (Health OFF by
  // default). Tabs: Today / Trend.
  static const healthToday = HealthRoutes.today;
  static const healthTrend = HealthRoutes.trend;

  // ── KnowledgeOS (`docs/domains/knowledgeos-domain.md` §5) — gated by domain
  // opt-in. Primary tabs: Inbox / Library; Review is contextual.
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
  static const executionProjectDetail = ExecutionRoutes.projectDetail;

  // ── Global meta (not a tab) ────────────────────────────────────────────
  static const settings = SettingsRoutes.root;

  // ── Activity sub-flows (things that happen) ────────────────────────────
  static const expenseNew = FinanceRoutes.expenseNew;
  static const spending = FinanceRoutes.spending;
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
  static const planRebalanceExecution = FinanceRoutes.planRebalanceExecution;
  static const planIncome = FinanceRoutes.planIncome;
  static const planIncomeOptions = FinanceRoutes.planIncomeOptions;
  static const planIncomeStats = FinanceRoutes.planIncomeStats;
  static const planDca = FinanceRoutes.planDca;
  static const planBudget = FinanceRoutes.planBudget;
  static const planWheel = FinanceRoutes.planWheel;

  // ── Settings sub-flows ─────────────────────────────────────────────────
  static const settingsDevices = SettingsRoutes.devices;
  static const settingsFxRates = SettingsRoutes.fxRates;
  static const settingsBackup = SettingsRoutes.backup;
  static const settingsDataManagement = SettingsRoutes.dataManagement;
  static const settingsNotifications = SettingsRoutes.notifications;
  static const settingsLogs = SettingsRoutes.logs;
  static const settingsPerformance = SettingsRoutes.performance;
  static const settingsSync = SettingsRoutes.sync;
  static const settingsAi = SettingsRoutes.ai;
  static const settingsAdvanced = SettingsRoutes.advanced;
  static const settingsDataMaintenance = SettingsRoutes.dataMaintenance;
  static const settingsAiTransparency = SettingsRoutes.aiTransparency;
  static const settingsAiPrivacy = SettingsRoutes.aiPrivacy;
  static const settingsAiLlm = SettingsRoutes.aiLlm;
  static const settingsRiskThresholds = SettingsRoutes.riskThresholds;
  static const settingsStressTest = SettingsRoutes.stressTest;
  static const settingsMonthlyExpense = SettingsRoutes.monthlyExpense;
  static const settingsDomains = SettingsRoutes.domains;
  static const settingsDomainsHealth = SettingsRoutes.domainsHealth;
  // Target allocation editor is reachable via the rebalance Custom
  // chip; settings overview links to it through a deep link for
  // discoverability.
  static const rebalanceTargetAllocation = '/rebalance/target-allocation';
  static String settingsAiTransparencyDetail(String requestId) =>
      SettingsRoutes.aiTransparencyDetail(requestId);

  // ── Detail-page builders ───────────────────────────────────────────────
  static String wealthAsset(String id) => FinanceRoutes.wealthAsset(id);

  static String wealthPhysical(String id) => FinanceRoutes.wealthPhysical(id);

  static String wealthLiability(String id) => FinanceRoutes.wealthLiability(id);

  static String wealthLiabilityEdit(String id) =>
      FinanceRoutes.wealthLiabilityEdit(id);

  static String wealthAccount(String id) => FinanceRoutes.wealthAccount(id);

  static String expense(String id) => FinanceRoutes.expense(id);

  static String activityEntry(String id) => FinanceRoutes.activityEntry(id);

  static String planRebalanceExecutionSession(String sessionId) =>
      FinanceRoutes.planRebalanceExecutionSession(sessionId);

  static String tradeForAsset(String id) => FinanceRoutes.tradeForAsset(id);

  static String executionAction(String id) => ExecutionRoutes.action(id);

  static String executionCommitment(String id) =>
      ExecutionRoutes.commitment(id);
}

/// Canonical GoRouter route names. Used by tests and named navigation
/// helpers; mirrors the [AppRoutes] structure.
abstract final class AppRouteNames {
  static const login = AuthRouteNames.login;
  static const onboarding = AuthRouteNames.onboarding;
  static const life = LifeRouteNames.home;
  static const assistant = AssistantRouteNames.home;
  static const home = FinanceRouteNames.home;
  static const settings = SettingsRouteNames.root;
  static const devices = SettingsRouteNames.devices;
  static const fxRates = SettingsRouteNames.fxRates;
  static const backup = SettingsRouteNames.backup;
  static const dataManagement = SettingsRouteNames.dataManagement;
  static const notifications = SettingsRouteNames.notifications;
  static const logs = SettingsRouteNames.logs;
  static const performance = SettingsRouteNames.performance;
  static const sync = SettingsRouteNames.sync;
  static const ai = SettingsRouteNames.ai;
  static const advanced = SettingsRouteNames.advanced;
  static const dataMaintenance = SettingsRouteNames.dataMaintenance;
  static const aiTransparency = SettingsRouteNames.aiTransparency;
  static const aiTransparencyDetail = SettingsRouteNames.aiTransparencyDetail;
  static const aiPrivacy = SettingsRouteNames.aiPrivacy;
  static const aiLlm = SettingsRouteNames.aiLlm;
  static const aiModels = SettingsRouteNames.aiModels;
  static const riskThresholds = SettingsRouteNames.riskThresholds;
  static const stressTest = SettingsRouteNames.stressTest;
  static const monthlyExpense = SettingsRouteNames.monthlyExpense;
  static const domains = SettingsRouteNames.domains;
  static const domainsHealth = SettingsRouteNames.domainsHealth;

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

  // ── HealthOS — gated by opt-in. Tabs: Today / Trend. ──────────────────
  static const healthToday = HealthRouteNames.today;
  static const healthTrend = HealthRouteNames.trend;

  // ── KnowledgeOS — gated by opt-in. Review is contextual, not a tab.
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
  static const planRebalanceExecution =
      FinanceRouteNames.planRebalanceExecution;
  static const planIncome = FinanceRouteNames.planIncome;
  static const planIncomeOptions = FinanceRouteNames.planIncomeOptions;
  static const planIncomeStats = FinanceRouteNames.planIncomeStats;
  static const planDca = FinanceRouteNames.planDca;
  static const planBudget = FinanceRouteNames.planBudget;
  static const planWheel = FinanceRouteNames.planWheel;

  // ── Activity ────────────────────────────────────────────────────────────
  static const activity = FinanceRouteNames.activity;
  static const activityEntryDetail = FinanceRouteNames.activityEntryDetail;
  static const expenseNew = FinanceRouteNames.expenseNew;
  static const spending = FinanceRouteNames.spending;
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
/// root-tab affordances. Settings is not a tab (IA contract §1).
///
/// Reads [activeDomainPacksProvider] so optional-domain tabs do not become
/// keyboard targets before the user opts in.
final primaryTabPathsProvider = Provider<List<String>>((ref) {
  final packs = ref.watch(activeDomainPacksProvider);
  return [for (final p in packs) ...p.tabPaths];
});

/// Tab paths for the domain that owns [path] — the Cmd/Ctrl-1..N targets.
///
/// The old flat concatenation permanently bound Cmd-1..4 to the first
/// domain's (Finance's) tabs, teleporting users out of whatever domain they
/// were in and leaving every other domain keyboard-unreachable (blueprint
/// doc 15 §7.4). Outside any domain (e.g. `/life`) this falls back to the
/// first active domain, preserving the old behavior there.
List<String> domainTabPathsForLocation(List<DomainPack> packs, String path) {
  if (packs.isEmpty) return const [];
  final scope = domainForRoute(packs, path);
  for (final p in packs) {
    if (p.scope == scope) return p.tabPaths;
  }
  return packs.first.tabPaths;
}
