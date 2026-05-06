/// Canonical route paths for NaviWealth's current information architecture.
///
/// Business UI should use these constants or helpers instead of spelling paths
/// inline. Legacy URLs are intentionally absent.
abstract final class AppRoutes {
  static const login = '/login';

  static const home = '/';
  static const portfolio = '/portfolio';
  static const activity = '/activity';
  static const plan = '/plan';
  static const ai = '/ai';
  static const settings = '/settings';

  static const portfolioNewCash = '/portfolio/new/cash';
  static const portfolioNewDeposit = '/portfolio/new/deposit';
  static const portfolioNewWealth = '/portfolio/new/wealth';
  static const portfolioCorporateAction = '/portfolio/corporate-action';
  static const liabilityNew = '/portfolio/liabilities/new';

  static const activityExpenses = '/activity/expenses';
  static const expenseNew = '/activity/expenses/new';
  static const expenseReport = '/activity/expenses/report';
  static const activityAccounts = '/activity/accounts';
  static const accountNew = '/activity/accounts/new';
  static const accountTransfer = '/activity/accounts/transfer';
  static const accountJournal = '/activity/accounts/journal';
  static const tradeEntry = '/activity/trade';

  static const planAnalytics = '/plan/analytics';
  static const planFire = '/plan/fire';
  static const planRebalance = '/plan/rebalance';

  static const settingsDevices = '/settings/devices';
  static const settingsFxRates = '/settings/fx-rates';
  static const settingsBackup = '/settings/backup';
  static const settingsLogs = '/settings/logs';

  static String portfolioAsset(String id) =>
      '/portfolio/${Uri.encodeComponent(id)}';

  static String physicalAsset(String id) =>
      '/portfolio/physical/${Uri.encodeComponent(id)}';

  static String liability(String id) =>
      '/portfolio/liabilities/${Uri.encodeComponent(id)}';

  static String account(String id) =>
      '/activity/accounts/${Uri.encodeComponent(id)}';

  static String expense(String id) =>
      '/activity/expenses/${Uri.encodeComponent(id)}';

  static String tradeForAsset(String id) =>
      '$tradeEntry?assetId=${Uri.encodeQueryComponent(id)}';
}
