/// FinanceOS route path and route name contract.
library;

enum PortfolioStudioSection { overview, structure, assets, rules }

class CapitalTransferIntent {
  const CapitalTransferIntent({
    required this.fromPortfolioId,
    required this.toPortfolioId,
    required this.amount,
    required this.currency,
    this.fromGroupId,
    this.toGroupId,
  });

  final String fromPortfolioId;
  final String toPortfolioId;
  final String amount;
  final String currency;
  final String? fromGroupId;
  final String? toGroupId;

  bool get isGroupTransfer => fromGroupId != null || toGroupId != null;

  Map<String, String> get queryParameters => {
    'transferFrom': fromPortfolioId,
    'transferTo': toPortfolioId,
    'transferAmount': amount,
    'transferCurrency': currency,
    'transferFromGroup': ?fromGroupId,
    'transferToGroup': ?toGroupId,
  };

  static CapitalTransferIntent? fromQuery(Map<String, String> query) {
    final from = query['transferFrom'];
    final to = query['transferTo'];
    final amount = query['transferAmount'];
    final currency = query['transferCurrency'];
    if (from == null || to == null || amount == null || currency == null) {
      return null;
    }
    return CapitalTransferIntent(
      fromPortfolioId: from,
      toPortfolioId: to,
      amount: amount,
      currency: currency,
      fromGroupId: query['transferFromGroup'],
      toGroupId: query['transferToGroup'],
    );
  }
}

abstract final class FinanceRoutes {
  static const home = '/';
  static const activity = '/activity';
  static const wealth = '/wealth';
  static const plan = '/plan';

  static const spending = '/activity/spending';
  static const expenseNew = '/activity/expense/new';
  static const cashflow = '/activity/cashflow';
  static const cashflowRecurring = '/activity/cashflow/recurring';
  static const cashflowDividends = '/wealth/portfolio/dividends';
  static const tradeEntry = '/activity/trade';
  static const transfer = '/activity/transfer';
  static const journalEntries = '/activity/journal';
  static const activityIngest = '/activity/ingest';
  static const activityInbox = '/activity/inbox';
  static const activityMonthlyClose = '/activity/monthly-close';

  static const wealthAccounts = '/wealth/accounts';
  static const wealthAccountNew = '/wealth/accounts/new';
  static const wealthNewCash = '/wealth/new/cash';
  static const wealthNewDeposit = '/wealth/new/deposit';
  static const wealthNewWealth = '/wealth/new/wealth';
  static const wealthCorporateAction = '/wealth/corporate-action';
  static const wealthLiabilities = '/wealth/liabilities';
  static const wealthLiabilityNew = '/wealth/liabilities/new';
  static const wealthPortfolio = '/wealth/portfolio';
  static const wealthPortfolioStudio = '/wealth/portfolio/:portfolioId/studio';
  static const wealthWatchlist = '/wealth/watchlist';

  static const planFire = '/plan/fire';
  static const planRebalance = '/plan/rebalance';
  static const planRebalanceExecution = '/plan/rebalance/execution/:sessionId';
  static const planIncome = '/plan/income';
  static const planIncomeOptions = '/plan/income/options';
  static const planIncomeStats = '/plan/income/stats';
  static const planWheel = '/plan/income/wheel';
  static const planDca = '/plan/dca';
  static const planBudget = '/plan/budget';
  static const planExpenseCategories = '/plan/expense-categories';
  static const planRunway = '/plan/runway';
  static const planLifeEvents = '/plan/life-events';

  static String wealthAsset(String id) =>
      '/wealth/assets/${Uri.encodeComponent(id)}';

  static String wealthPortfolioStudioFor(
    String portfolioId, {
    PortfolioStudioSection? section,
    CapitalTransferIntent? transfer,
  }) {
    final path = '/wealth/portfolio/${Uri.encodeComponent(portfolioId)}/studio';
    final query = <String, String>{
      if (section != null) 'section': section.name,
      if (transfer != null) ...transfer.queryParameters,
    };
    return query.isEmpty
        ? path
        : Uri(path: path, queryParameters: query).toString();
  }

  static String wealthAssetEdit(String id) =>
      '/wealth/assets/${Uri.encodeComponent(id)}/edit';

  static String wealthPhysical(String id) =>
      '/wealth/physical/${Uri.encodeComponent(id)}';

  static String wealthLiability(String id) =>
      '/wealth/liabilities/${Uri.encodeComponent(id)}';

  static String wealthLiabilityEdit(String id) =>
      '/wealth/liabilities/${Uri.encodeComponent(id)}/edit';

  static String wealthAccount(String id) =>
      '/wealth/accounts/${Uri.encodeComponent(id)}';

  static String wealthAccountEdit(String id) =>
      '/wealth/accounts/${Uri.encodeComponent(id)}/edit';

  static String transferFromAccount(String id) =>
      '$transfer?from=${Uri.encodeQueryComponent(id)}';

  static String wealthNewCashForAccount(String id) =>
      '$wealthNewCash?accountId=${Uri.encodeQueryComponent(id)}';

  static String expense(String id) =>
      '/activity/expense/${Uri.encodeComponent(id)}';

  static String activityFeed({
    DateTime? from,
    DateTime? to,
    Iterable<String> kinds = const <String>[],
    Iterable<String> accountIds = const <String>[],
    String? query,
  }) {
    String day(DateTime value) {
      final utc = value.toUtc();
      return '${utc.year.toString().padLeft(4, '0')}-'
          '${utc.month.toString().padLeft(2, '0')}-'
          '${utc.day.toString().padLeft(2, '0')}';
    }

    final sortedKinds = kinds.toList(growable: false)..sort();
    final sortedAccounts = accountIds.toList(growable: false)..sort();
    return Uri(
      path: activity,
      queryParameters: <String, String>{
        if (from != null) 'from': day(from),
        if (to != null) 'to': day(to),
        if (sortedKinds.isNotEmpty) 'kinds': sortedKinds.join(','),
        if (sortedAccounts.isNotEmpty) 'accounts': sortedAccounts.join(','),
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
      },
    ).toString();
  }

  static String get expenseActivity => activityFeed(kinds: const ['expense']);

  static String activityEntry(String id) =>
      '/activity/entry/${Uri.encodeComponent(id)}';

  static String planRebalanceExecutionSession(String sessionId) =>
      '/plan/rebalance/execution/${Uri.encodeComponent(sessionId)}';

  static String tradeForAsset(String id, {String? side}) {
    final asset = Uri.encodeQueryComponent(id);
    final tradeSide = side == null
        ? ''
        : '&side=${Uri.encodeQueryComponent(side)}';
    return '$tradeEntry?assetId=$asset$tradeSide';
  }
}

abstract final class FinanceRouteNames {
  static const home = 'home';
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
  static const wealthPortfolioStudio = 'wealth-portfolio-studio';
  static const wealthWatchlist = 'wealth-watchlist';

  static const plan = 'plan';
  static const planFire = 'plan-fire';
  static const planRebalance = 'plan-rebalance';
  static const planRebalanceExecution = 'plan-rebalance-execution';
  static const planIncome = 'plan-income';
  static const planIncomeOptions = 'plan-income-options';
  static const planIncomeStats = 'plan-income-stats';
  static const planWheel = 'plan-wheel';
  static const planDca = 'plan-dca';
  static const planBudget = 'plan-budget';
  static const planExpenseCategories = 'plan-expense-categories';
  static const planRunway = 'plan-runway';
  static const planLifeEvents = 'plan-life-events';

  static const activity = 'activity';
  static const activityEntryDetail = 'activity-entry-detail';
  static const spending = 'spending';
  static const expenseNew = 'expense-new';
  static const cashflow = 'cashflow';
  static const cashflowRecurring = 'cashflow-recurring';
  static const expenseDetail = 'expense-detail';
  static const cashflowDividends = 'cashflow-dividends';
  static const tradeEntry = 'trade-entry';
  static const transfer = 'transfer';
  static const journalEntries = 'journal-entries';
  static const activityIngest = 'activity-ingest';
  static const activityInbox = 'activity-inbox';
  static const activityMonthlyClose = 'activity-monthly-close';
}
