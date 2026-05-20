/// Canonical route paths for NaviWealth's information architecture.
///
/// Four primary tabs in display order:
///   Home → Activity → Accounts → Settings.
///
/// History: the old "Plan" tab was killed; its content (FIRE / Rebalance /
/// Analytics) lived briefly under `/ai/insights/*` and now lives under
/// `/accounts/*` as part of the §5.10 four-layer AI surface refactor — the
/// `/ai` tab itself is gone. AI is no longer a destination: explicit AI
/// surfaces live in the command palette overlay (Layer 1) and inline
/// capsules (Layer 2); chat session history is read-only under
/// `/settings/ai-history`.
abstract final class AppRoutes {
  // ── Auth ────────────────────────────────────────────────────────────────
  static const login = '/login';

  // ── Primary tabs ────────────────────────────────────────────────────────
  static const home = '/';
  static const activity = '/activity';
  static const accounts = '/accounts';
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

  // ── Accounts hub sub-flows (things you own / owe + plan dashboards) ────
  static const accountsList = '/accounts/list';
  static const accountListNew = '/accounts/list/new';
  static const accountNewCash = '/accounts/new/cash';
  static const accountNewDeposit = '/accounts/new/deposit';
  static const accountNewWealth = '/accounts/new/wealth';
  static const accountCorporateAction = '/accounts/corporate-action';
  static const liabilities = '/accounts/liabilities';
  static const liabilityNew = '/accounts/liabilities/new';
  // Former /ai/insights/* — these are deterministic dashboards, not AI
  // surfaces. They live under Accounts because they all operate on the
  // portfolio + net-worth picture.
  static const accountsFire = '/accounts/fire';
  static const accountsRebalance = '/accounts/rebalance';
  static const accountsAnalytics = '/accounts/analytics';
  static const accountsPortfolioHub = '/accounts/portfolio';
  static const accountsWatchlist = '/accounts/watchlist';
  static const accountsDcaSimulator = '/accounts/dca';
  static const accountsDividends = '/accounts/dividends';

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
  static String settingsAiTransparencyDetail(String requestId) =>
      '/settings/ai-transparency/${Uri.encodeComponent(requestId)}';

  // ── Detail-page builders ───────────────────────────────────────────────
  static String accountAsset(String id) =>
      '/accounts/asset/${Uri.encodeComponent(id)}';

  static String physicalAsset(String id) =>
      '/accounts/physical/${Uri.encodeComponent(id)}';

  static String liability(String id) =>
      '/accounts/liabilities/${Uri.encodeComponent(id)}';

  static String accountListItem(String id) =>
      '/accounts/list/${Uri.encodeComponent(id)}';

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

  static const accounts = 'accounts';
  static const accountsList = 'accounts-list';
  static const accountListNew = 'account-list-new';
  static const accountListItem = 'account-list-item';
  static const accountNewCash = 'account-new-cash';
  static const accountNewDeposit = 'account-new-deposit';
  static const accountNewWealth = 'account-new-wealth';
  static const accountCorporateAction = 'account-corporate-action';
  static const physicalAssetDetail = 'physicalAssetDetail';
  static const liabilities = 'liabilities';
  static const liabilityNew = 'liability-new';
  static const liabilityDetail = 'liabilityDetail';
  static const accountAssetDetail = 'account-asset-detail';
  static const accountsFire = 'accounts-fire';
  static const accountsRebalance = 'accounts-rebalance';
  static const accountsAnalytics = 'accounts-analytics';
  static const accountsPortfolioHub = 'accounts-portfolio-hub';
  static const accountsWatchlist = 'accounts-watchlist';
  static const accountsDcaSimulator = 'accounts-dca-simulator';

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

/// Primary shell tab paths in display order. See `app_shell.dart` for the
/// visual treatment.
const List<String> kPrimaryTabPaths = <String>[
  AppRoutes.home,
  AppRoutes.activity,
  AppRoutes.accounts,
  AppRoutes.settings,
];

const String kCashflowPath = AppRoutes.cashflow;
const String kCashflowRecurringPath = AppRoutes.cashflowRecurring;
const String kDividendCenterPath = AppRoutes.cashflowDividends;
const String kDividendsPath = AppRoutes.cashflowDividends;
