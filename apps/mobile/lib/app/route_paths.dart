/// Canonical route paths for NaviWealth's information architecture.
///
/// Five primary tabs in display order:
///   Home → Activity → AI (centered, accent) → Accounts → Settings.
///
/// "Plan" is gone — its content (FIRE / Rebalance / Analytics) lives under
/// `/ai/insights/*` so the AI Assistant page becomes the single context +
/// action layer. "Portfolio" is renamed to "Accounts" — the new hub
/// surfaces every asset class plus liabilities in one place.
abstract final class AppRoutes {
  // ── Auth ────────────────────────────────────────────────────────────────
  static const login = '/login';

  // ── Primary tabs ────────────────────────────────────────────────────────
  static const home = '/';
  static const activity = '/activity';
  static const ai = '/ai';
  static const accounts = '/accounts';
  static const settings = '/settings';

  // ── AI insights (FIRE / Rebalance / Analytics now live under /ai) ──────
  static const aiInsights = '/ai/insights';
  static const aiInsightsFire = '/ai/insights/fire';
  static const aiInsightsRebalance = '/ai/insights/rebalance';
  static const aiInsightsAnalytics = '/ai/insights/analytics';

  // ── Activity sub-flows (things that happen) ────────────────────────────
  static const activityExpenses = '/activity/expenses';
  static const expenseNew = '/activity/expenses/new';
  static const expenseReport = '/activity/expenses/report';
  static const tradeEntry = '/activity/trade';
  static const transfer = '/activity/transfer';
  static const journalEntries = '/activity/journal';

  // ── Accounts hub sub-flows (things you own / owe) ──────────────────────
  static const accountsList = '/accounts/list';
  static const accountListNew = '/accounts/list/new';
  static const accountNewCash = '/accounts/new/cash';
  static const accountNewDeposit = '/accounts/new/deposit';
  static const accountNewWealth = '/accounts/new/wealth';
  static const accountCorporateAction = '/accounts/corporate-action';
  static const liabilities = '/accounts/liabilities';
  static const liabilityNew = '/accounts/liabilities/new';

  // ── Settings sub-flows ─────────────────────────────────────────────────
  static const settingsDevices = '/settings/devices';
  static const settingsFxRates = '/settings/fx-rates';
  static const settingsBackup = '/settings/backup';
  static const settingsLogs = '/settings/logs';
  static const settingsSync = '/settings/sync';

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

  static String tradeForAsset(String id) =>
      '$tradeEntry?assetId=${Uri.encodeQueryComponent(id)}';
}

/// Canonical GoRouter route names. Used by tests and named navigation
/// helpers; mirrors the [AppRoutes] structure.
abstract final class AppRouteNames {
  static const login = 'login';
  static const home = 'home';
  static const aiChat = 'ai-chat';
  static const aiInsightsFire = 'ai-insights-fire';
  static const aiInsightsRebalance = 'ai-insights-rebalance';
  static const aiInsightsAnalytics = 'ai-insights-analytics';
  static const settings = 'settings';
  static const devices = 'devices';
  static const fxRates = 'fx-rates';
  static const backup = 'backup';
  static const logs = 'logs';
  static const sync = 'sync';

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

  static const activity = 'activity';
  static const expenses = 'expenses';
  static const expenseNew = 'expense-new';
  static const expenseReport = 'expense-report';
  static const expenseDetail = 'expense-detail';
  static const tradeEntry = 'trade-entry';
  static const transfer = 'transfer';
  static const journalEntries = 'journal-entries';
}

/// Primary shell tab paths in display order. Index 2 (AI) is the centered
/// accent tab — see `app_shell.dart` for the visual treatment.
const List<String> kPrimaryTabPaths = <String>[
  AppRoutes.home,
  AppRoutes.activity,
  AppRoutes.ai,
  AppRoutes.accounts,
  AppRoutes.settings,
];
