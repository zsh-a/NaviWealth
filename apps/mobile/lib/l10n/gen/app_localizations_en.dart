// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NaviWealth';

  @override
  String get navHome => 'Today';

  @override
  String get navToday => 'Today';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navSettings => 'Settings';

  @override
  String get navActivity => 'Activity';

  @override
  String get navAccounts => 'Wealth';

  @override
  String get navWealth => 'Wealth';

  @override
  String get navPlan => 'Plan';

  @override
  String get navSearch => 'Search';

  @override
  String get navSettingsTooltip => 'Settings';

  @override
  String get shellSwitchDomainTitle => 'Switch domain';

  @override
  String get shellExpandSidebarShortcut => 'Expand sidebar  (⌘B)';

  @override
  String get shellCollapseSidebarShortcut => 'Collapse sidebar  (⌘B)';

  @override
  String get planHubTitle => 'Plan';

  @override
  String get planHubSubtitle => 'Decisions, models, and goals.';

  @override
  String get planFireSectionTitle => 'FIRE';

  @override
  String get planFireSectionSubtitle => 'Years to financial independence';

  @override
  String get planRebalanceSectionTitle => 'Rebalance';

  @override
  String get planRebalanceSectionSubtitle => 'Drift from target allocation';

  @override
  String get planIncomeSectionTitle => 'Income strategy';

  @override
  String get planIncomeSectionSubtitle => 'Covered calls & cash-secured puts';

  @override
  String get planDcaSectionTitle => 'DCA simulator';

  @override
  String get planDcaSectionSubtitle => 'Recurring buy plan';

  @override
  String get planProjectionSectionTitle => 'Scenario analytics';

  @override
  String get planProjectionSectionSubtitle => 'Allocation & FIRE projection';

  @override
  String get planScenariosSectionTitle => 'Scenarios';

  @override
  String get planScenariosSectionSubtitle => 'Compare what-ifs';

  @override
  String get planScenariosComingSoon => 'Scenario builder is not yet wired up.';

  @override
  String get planGoalsSectionTitle => 'Goals';

  @override
  String get planGoalsSectionSubtitle => 'Saving targets & milestones';

  @override
  String get planGoalsComingSoon => 'Goal tracker is not yet wired up.';

  @override
  String get planBudgetSectionTitle => 'Budget';

  @override
  String get planBudgetSectionSubtitle => 'Monthly category caps';

  @override
  String get planBudgetTitle => 'Budget';

  @override
  String get planBudgetEmptyTitle => 'No budgets yet';

  @override
  String get planBudgetEmptyBody =>
      'Set a monthly cap for any category to track spending against it here.';

  @override
  String planBudgetMonthHeader(String month) {
    return '$month budgets';
  }

  @override
  String get planBudgetTotalLabel => 'Total monthly budget';

  @override
  String get planWheelSectionTitle => 'Wheel cycles';

  @override
  String get planWheelSectionSubtitle => 'Sell-put + covered-call review';

  @override
  String get planWheelTitle => 'Wheel cycles';

  @override
  String get planWheelEmptyTitle => 'No active cycles';

  @override
  String get planWheelEmptyBody =>
      'Record a sell-put or covered-call trade and the cycle will surface here.';

  @override
  String get investmentEventTimelineTitle => 'Upcoming events';

  @override
  String get investmentEventTimelineEmpty =>
      'No upcoming dividends or splits in the next 90 days.';

  @override
  String get investmentEventDividend => 'Dividend';

  @override
  String investmentEventSplit(String ratio) {
    return 'Split $ratio';
  }

  @override
  String get investmentEventRights => 'Rights offering';

  @override
  String get investmentEventDrip => 'DRIP';

  @override
  String get planHeroEmpty => 'Set up your FIRE plan to see progress here.';

  @override
  String planHeroYearsToFire(String years) {
    return '$years years to FIRE';
  }

  @override
  String get planHeroProgressLabel => 'Progress';

  @override
  String get planHeroNextRebalance => 'Next: review rebalance';

  @override
  String get planHeroSeePlan => 'See plan';

  @override
  String get wealthHubTitle => 'Wealth';

  @override
  String get wealthHubSubtitle => 'What you own, what you owe.';

  @override
  String get wealthAccountsSectionTitle => 'Accounts';

  @override
  String get wealthAccountsSectionSubtitle => 'Cash, banks, brokers, crypto';

  @override
  String get wealthHoldingsSectionTitle => 'Holdings';

  @override
  String get wealthHoldingsSectionSubtitle => 'Positions across all accounts';

  @override
  String get wealthWatchlistSectionTitle => 'Watchlist';

  @override
  String get wealthWatchlistSectionSubtitle => 'Symbols you\'re tracking';

  @override
  String get wealthLiabilitiesSectionTitle => 'Liabilities';

  @override
  String get wealthLiabilitiesSectionSubtitle => 'Loans, mortgages, credit';

  @override
  String get wealthIncomeProjectionTitle => 'Income projection';

  @override
  String get wealthIncomeProjectionSubtitle =>
      'Projected yield from your holdings';

  @override
  String get wealthIncomeProjectionComingSoon =>
      'Income projection from holdings is not yet wired up.';

  @override
  String get wealthPerspectiveSectionTitle => 'Allocation';

  @override
  String get wealthPerspectiveByCategory => 'By category';

  @override
  String get wealthPerspectiveByCurrency => 'By currency';

  @override
  String wealthPerspectiveItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings',
      one: '1 holding',
    );
    return '$_temp0';
  }

  @override
  String get wealthPerspectiveEmpty =>
      'No holdings yet. Add assets from the Wealth quick actions to see the breakdown.';

  @override
  String get cashFlowTitle => 'Cash flow';

  @override
  String get cashFlowCommandOpen => 'Open cash flow';

  @override
  String get cashFlowCommandViewIncome => 'View income';

  @override
  String get cashFlowPeriodMonth => 'Month';

  @override
  String get cashFlowPeriodQuarter => 'Quarter';

  @override
  String get cashFlowPeriodYear => 'Year';

  @override
  String get cashFlowKpiInflow => 'Inflow';

  @override
  String get cashFlowKpiOutflow => 'Outflow';

  @override
  String get cashFlowKpiNet => 'Net';

  @override
  String get cashFlowIncomeExpenseTitle => 'Income vs expense';

  @override
  String get cashFlowNetTrendTitle => 'Net cash-flow trend';

  @override
  String get cashFlowCategoryTitle => 'Category mix';

  @override
  String get cashFlowViewDividendCenter => 'View dividend center';

  @override
  String get cashFlowEmptyTitle => 'No cash flow yet';

  @override
  String get cashFlowEmptyBody =>
      'Income and expenses appear here once you record transactions.';

  @override
  String cashFlowLoadError(String error) {
    return 'Cash flow failed to load: $error';
  }

  @override
  String get recurringListTitle => 'Recurring';

  @override
  String get recurringCommandOpen => 'Recurring transactions';

  @override
  String get commandKeywordRecurringCn => '周期';

  @override
  String recurringLoadError(String error) {
    return 'Recurring rules failed to load: $error';
  }

  @override
  String get recurringEmptyTitle => 'No recurring rules';

  @override
  String get recurringEmptyBody =>
      'Set up rules for salary, subscriptions or other repeating cash flow.';

  @override
  String get recurringEmptyCta => 'Add recurring rule';

  @override
  String recurringNextDue(String date) {
    return 'Next: $date';
  }

  @override
  String get recurringTemplateCorrupt => 'Template unreadable';

  @override
  String get recurringRowActionsTitle => 'Recurring rule';

  @override
  String get recurringActionEdit => 'Edit';

  @override
  String get recurringActionEditHint => 'Change amount or schedule';

  @override
  String get recurringActionDisable => 'Disable';

  @override
  String get recurringActionDisableHint => 'Stop generating new entries';

  @override
  String get recurringActionDeleteHint => 'Remove this rule permanently';

  @override
  String get recurringDisableTitle => 'Disable rule?';

  @override
  String get recurringDisableBody =>
      'It will stop creating new entries. You can recreate it later.';

  @override
  String get recurringDeleteTitle => 'Delete rule?';

  @override
  String get recurringDeleteBody =>
      'This recurring rule will be removed. This cannot be undone.';

  @override
  String get recurringDisabled => 'Rule disabled';

  @override
  String get recurringDeleted => 'Rule deleted';

  @override
  String get recurringActionFailed => 'Action failed';

  @override
  String recurringEveryDay(int n) {
    return 'Every $n day(s)';
  }

  @override
  String recurringEveryWeek(int n) {
    return 'Every $n week(s)';
  }

  @override
  String recurringEveryMonth(int n) {
    return 'Every $n month(s)';
  }

  @override
  String recurringEveryYear(int n) {
    return 'Every $n year(s)';
  }

  @override
  String recurringByMonthDay(int day) {
    return 'on day $day';
  }

  @override
  String recurringUntil(String date) {
    return 'until $date';
  }

  @override
  String get recurringFormNewTitle => 'New recurring rule';

  @override
  String get recurringFormEditTitle => 'Edit recurring rule';

  @override
  String get recurringFormSubtitle =>
      'Generates a journal entry on each occurrence';

  @override
  String get recurringFormSave => 'Save';

  @override
  String get recurringFieldKind => 'Type';

  @override
  String get recurringKindIncome => 'Income';

  @override
  String get recurringKindExpense => 'Expense';

  @override
  String get recurringFieldAmount => 'Amount';

  @override
  String get recurringFieldCashAccount => 'Cash account';

  @override
  String get recurringFieldCategoryAccount => 'Category account';

  @override
  String get recurringFieldNote => 'Note';

  @override
  String get recurringFieldStart => 'Starts on';

  @override
  String get recurringFieldFrequency => 'Frequency';

  @override
  String get recurringFreqDaily => 'Daily';

  @override
  String get recurringFreqWeekly => 'Weekly';

  @override
  String get recurringFreqMonthly => 'Monthly';

  @override
  String get recurringFreqYearly => 'Yearly';

  @override
  String get recurringFieldInterval => 'Every N periods';

  @override
  String get recurringFieldByMonthDay => 'Day of month';

  @override
  String get recurringFieldByMonthDayHelper => 'Optional, 1–31';

  @override
  String get recurringFieldUntil => 'End date';

  @override
  String get recurringFieldUntilHelper => 'Optional';

  @override
  String get recurringValidationRequired => 'Required';

  @override
  String get recurringValidationPositive => 'Enter an amount greater than 0';

  @override
  String get recurringValidationInterval => 'Enter a positive whole number';

  @override
  String get recurringValidationByMonthDay => 'Day must be 1–31';

  @override
  String get recurringValidationAccounts => 'Pick both accounts';

  @override
  String get recurringValidationSameAccount =>
      'Cash and category accounts must differ';

  @override
  String get recurringValidationCurrency => 'Pick a currency';

  @override
  String get recurringDefaultNarration => 'Recurring transaction';

  @override
  String get recurringSaveFailed => 'Could not save the rule';

  @override
  String get cashFlowKindSalary => 'Salary';

  @override
  String get cashFlowKindDividend => 'Dividend';

  @override
  String get cashFlowKindInterest => 'Interest';

  @override
  String get cashFlowKindCapitalGains => 'Capital gains';

  @override
  String get cashFlowKindOtherIncome => 'Other income';

  @override
  String get cashFlowKindExpense => 'Expense';

  @override
  String get cashFlowKindTransfer => 'Transfer';

  @override
  String get cashFlowKindOpening => 'Opening';

  @override
  String get cashFlowKindOther => 'Other';

  @override
  String get dividendCenterTitle => 'Dividend Center';

  @override
  String get dividendCenterMetricYtd => 'Year to date';

  @override
  String get dividendCenterMetricTtm => 'Trailing 12 months';

  @override
  String get dividendCenterMetricYoy => 'YoY same period';

  @override
  String get dividendCenterMetricWithholding => 'Withholding tax';

  @override
  String get dividendCenterHoldingRanking => 'Holding ranking';

  @override
  String get dividendCenterHistoryTimeline => 'History timeline';

  @override
  String get dividendCenterForecastTitle => 'Next 12 months';

  @override
  String get dividendCenterForecastUnavailable =>
      'Forecasting is not enabled yet.';

  @override
  String dividendCenterForecastSource(String source) {
    return 'Source: $source';
  }

  @override
  String get dividendCenterEmptyTitle => 'No dividend records yet';

  @override
  String get dividendCenterEmptyBody =>
      'Record a cash dividend or corporate action to start the timeline.';

  @override
  String get dividendCenterRecordAction => 'Record dividend';

  @override
  String dividendCenterLoadError(String error) {
    return 'Dividend center failed to load: $error';
  }

  @override
  String get dividendEventActionsTitle => 'Dividend entry';

  @override
  String get dividendEventViewInActivity => 'View in activity';

  @override
  String get dividendEventViewInActivityHint =>
      'Open the underlying journal entry';

  @override
  String get dividendEventEdit => 'Edit (re-record)';

  @override
  String get dividendEventEditHint => 'Record a corrected corporate action';

  @override
  String get dividendEventDeleteHint => 'Remove this dividend entry';

  @override
  String get dividendEventDeleteTitle => 'Delete dividend?';

  @override
  String dividendEventDeleteBody(String asset) {
    return 'Delete the dividend for $asset? This cannot be undone.';
  }

  @override
  String get dividendEventDeleted => 'Dividend deleted';

  @override
  String get dividendEventDeleteFailed => 'Could not delete the dividend';

  @override
  String get dividendEventOpenFailed => 'Could not open this entry';

  @override
  String get dividendForecastStrategyDeclared => 'Declared';

  @override
  String get dividendForecastStrategyDps => 'DPS';

  @override
  String get dividendForecastStrategyTtm => 'TTM';

  @override
  String get dividendForecastStrategyComposite => 'Composite';

  @override
  String get dividendForecastStrategyUnknown => 'Forecast';

  @override
  String get commonNotAvailable => 'N/A';

  @override
  String get commandKeywordCashFlowCn => '现金流';

  @override
  String get commandKeywordIncomeCn => '收入';

  @override
  String get commandKeywordDividendCn => '股息';

  @override
  String get commandKeywordSalaryCn => '工资';

  @override
  String get commandKeywordDividendCenterCn => '股息中心';

  @override
  String get commandKeywordMyDividendsCn => '我的股息';

  @override
  String get commandKeywordPassiveIncomeCn => '被动收入';

  @override
  String get commandKeywordBonusDividendCn => '分红';

  @override
  String get commandKeywordWithholdingTaxCn => '代扣税';

  @override
  String get commandKeywordCorporateActionCn => '公司行动';

  @override
  String get commandKeywordSplitCn => '拆股';

  @override
  String get commandKeywordRightsIssueCn => '配股';

  @override
  String get commandKeywordRebalanceCn => '再平衡';

  @override
  String get commandKeywordTargetAllocationCn => '目标配置';

  @override
  String get accountsHubSectionCashDeposits => 'Cash & Deposits';

  @override
  String get accountsHubSectionInvestments => 'Investments';

  @override
  String get accountsHubSectionPhysical => 'Physical';

  @override
  String get accountsHubSectionLiabilities => 'Liabilities';

  @override
  String get accountsHubManageBankAccounts => 'Manage bank accounts';

  @override
  String get portfolioHubTitle => 'Portfolio';

  @override
  String get portfolioHubAccountsEntrySubtitle =>
      'Holdings, returns, and allocation views';

  @override
  String get portfolioHubMarketValueLabel => 'Market value';

  @override
  String get portfolioHubYtdXirrLabel => 'YTD XIRR';

  @override
  String get portfolioHubAbsoluteReturnLabel => 'Absolute return';

  @override
  String get portfolioHubViewAccount => 'Account';

  @override
  String get portfolioHubViewCurrency => 'Currency';

  @override
  String get portfolioHubViewAssetClass => 'Class';

  @override
  String get portfolioHubHoldingsTitle => 'Allocation';

  @override
  String get portfolioHubPositionsTitle => 'Positions';

  @override
  String portfolioHubHoldingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings',
      one: '1 holding',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubUnknownAccount => 'Unknown account';

  @override
  String get portfolioHubAccountGroupSubtitle => 'Brokerage account';

  @override
  String get portfolioHubCurrencyGroupSubtitle => 'Settlement currency';

  @override
  String get portfolioHubAssetClassGroupSubtitle => 'Asset class';

  @override
  String get portfolioHubEmpty => 'No investment holdings yet.';

  @override
  String portfolioHubLoadError(String error) {
    return 'Portfolio failed to load: $error';
  }

  @override
  String get portfolioHubAssetTypeStock => 'Stock';

  @override
  String get portfolioHubAssetTypeEtf => 'ETF';

  @override
  String get portfolioHubAssetTypeMutualFund => 'Mutual fund';

  @override
  String get portfolioHubAssetTypeBond => 'Bond';

  @override
  String get portfolioHubAssetTypeCrypto => 'Crypto';

  @override
  String get portfolioHubAssetTypeCash => 'Cash';

  @override
  String get portfolioHubAssetTypeCommodity => 'Commodity';

  @override
  String get portfolioHubAssetTypeCustom => 'Custom';

  @override
  String get portfolioHubAssetTypeBankDepositTerm => 'Term deposit';

  @override
  String get portfolioHubAssetTypeBankDepositDemand => 'Demand deposit';

  @override
  String get portfolioHubAssetTypeWealthProduct => 'Wealth product';

  @override
  String get portfolioHubEnginesTitle => 'Engine views';

  @override
  String get portfolioHubRealizedPnlTitle => 'Realized P/L';

  @override
  String portfolioHubRealizedPnlCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lots',
      one: '1 lot',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubRealizedPnlEmpty => 'No closed lots yet.';

  @override
  String portfolioHubHoldingPeriod(String period) {
    return 'Held $period';
  }

  @override
  String portfolioHubHoldingYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years',
      one: '1 year',
    );
    return '$_temp0';
  }

  @override
  String portfolioHubHoldingMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String portfolioHubHoldingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubDividendForecastTitle => 'Dividend forecast';

  @override
  String get portfolioHubDividendForecastEmpty => 'No projected dividends yet.';

  @override
  String get portfolioHubDividendForecastEvent => 'Projected payout';

  @override
  String get portfolioHubForecastConfidenceHigh => 'High confidence';

  @override
  String get portfolioHubForecastConfidenceMedium => 'Medium confidence';

  @override
  String get portfolioHubForecastConfidenceLow => 'Low confidence';

  @override
  String get portfolioHubEventTimelineTitle => 'Event timeline';

  @override
  String portfolioHubEventTimelineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events',
      one: '1 event',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubEventTimelineEmpty =>
      'No dividend or corporate-action events yet.';

  @override
  String get dcaSimulatorTitle => 'DCA simulator';

  @override
  String get dcaSimulatorAccountsEntrySubtitle =>
      'Backtest recurring buys with cached monthly prices';

  @override
  String get dcaSimulatorSymbolField => 'Symbol or basket';

  @override
  String get dcaSimulatorSymbolHint => 'VOO or VOO, QQQ';

  @override
  String get dcaSimulatorAmountField => 'Amount';

  @override
  String get dcaSimulatorCurrencyField => 'Currency';

  @override
  String get dcaSimulatorMarketField => 'Market';

  @override
  String get dcaSimulatorMarketUs => 'US';

  @override
  String get dcaSimulatorMarketHk => 'Hong Kong';

  @override
  String get dcaSimulatorMarketCn => 'China A';

  @override
  String get dcaSimulatorMarketCrypto => 'Crypto';

  @override
  String get dcaSimulatorFrequencyField => 'Frequency';

  @override
  String get dcaSimulatorFrequencyMonthly => 'Monthly';

  @override
  String get dcaSimulatorFrequencyQuarterly => 'Quarterly';

  @override
  String get dcaSimulatorWindowField => 'Window';

  @override
  String get dcaSimulatorWindow1y => '1 year';

  @override
  String get dcaSimulatorWindow3y => '3 years';

  @override
  String get dcaSimulatorWindow5y => '5 years';

  @override
  String get dcaSimulatorRunAction => 'Run simulation';

  @override
  String get dcaSimulatorDraftAction => 'Draft next buys';

  @override
  String get dcaSimulatorFreshnessLive => 'Live';

  @override
  String get dcaSimulatorFreshnessCache => 'Cache';

  @override
  String get dcaSimulatorFreshnessStale => 'Stale';

  @override
  String get dcaSimulatorResultTitle => 'Backtest result';

  @override
  String get dcaSimulatorTotalInvested => 'Invested';

  @override
  String get dcaSimulatorEndingValue => 'Ending value';

  @override
  String get dcaSimulatorCumulativeReturn => 'Total return';

  @override
  String get dcaSimulatorAverageCost => 'Avg cost';

  @override
  String get dcaSimulatorMaxDrawdown => 'Max drawdown';

  @override
  String get dcaSimulatorChartTitle => 'Portfolio value';

  @override
  String get dcaSimulatorChartSeries => 'DCA value';

  @override
  String get dcaSimulatorEmpty => 'No monthly market data matched this window.';

  @override
  String get dcaSimulatorInvalidSymbols => 'Enter at least one symbol.';

  @override
  String get dcaSimulatorInvalidAmount => 'Enter a positive amount.';

  @override
  String get dcaSimulatorInvalidCurrency => 'Use a currency code.';

  @override
  String dcaSimulatorLoadError(String error) {
    return 'DCA simulation failed: $error';
  }

  @override
  String dcaSimulatorDraftNote(String symbol, String amount, String currency) {
    return 'DCA plan: buy $symbol for $amount $currency';
  }

  @override
  String dcaSimulatorPositionAverageCost(String currency, String averageCost) {
    return '$currency $averageCost avg cost';
  }

  @override
  String get assetDetailFxPnlTitle => 'Price vs FX contribution';

  @override
  String get assetDetailFxPnlMarketLeg => 'Price movement';

  @override
  String get assetDetailFxPnlCurrencyLeg => 'FX movement';

  @override
  String get assetDetailFxPnlTotal => 'Total base P/L';

  @override
  String assetDetailFxPnlLoadError(String error) {
    return 'FX P/L failed to load: $error';
  }

  @override
  String get dashboardAiInsightsTitle => 'Insights for you';

  @override
  String get dashboardActivityPreviewTitle => 'Recent activity';

  @override
  String get dashboardActivityPreviewViewAll => 'View all';

  @override
  String get dashboardAllocationSummaryTitle => 'Allocation';

  @override
  String get dashboardAllocationViewBreakdown => 'View breakdown';

  @override
  String get homeGreetingMorning => 'Good morning';

  @override
  String get homeGreetingAfternoon => 'Good afternoon';

  @override
  String get homeGreetingEvening => 'Good evening';

  @override
  String get homeGreetingNight => 'Good night';

  @override
  String homeGreetingNetWorthFragment(String pct) {
    return 'Net worth $pct this month';
  }

  @override
  String homeGreetingInsightsFragment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count insights available',
      one: '1 insight available',
    );
    return '$_temp0';
  }

  @override
  String get activityFilterChipAll => 'All';

  @override
  String get activityFilterChipIncome => 'Income';

  @override
  String get activityFilterChipExpense => 'Expense';

  @override
  String get activityFilterChipTransfer => 'Transfer';

  @override
  String get activityFilterChipTrade => 'Trade';

  @override
  String get activityEntryDetailTitle => 'Transaction';

  @override
  String get activityEntryDetailAiExplanation => 'AI insight';

  @override
  String get activityEntryDetailNoExplanation =>
      'No insight available for this entry.';

  @override
  String get activityEntryDetailInsightSubscription =>
      'Recurring subscription. Review whether it still fits your plan before the next renewal.';

  @override
  String get activityEntryDetailInsightHousing =>
      'Recurring housing payment. Keep it in the essential-spending baseline.';

  @override
  String get activityEntryDetailInsightIncome =>
      'Primary income inflow. Keep it stable in cash-flow projections.';

  @override
  String get activityEntryDetailInsightDining =>
      'Dining expense. Review if it aligns with your monthly food budget.';

  @override
  String get activityEntryDetailInsightTransport =>
      'Transportation cost. Consider whether it\'s a routine commute or one-off trip.';

  @override
  String get activityEntryDetailInsightShopping =>
      'Shopping purchase. Check if it was planned or impulse spending.';

  @override
  String activityEntryDetailLegCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get activityEntryDetailLedgerTitle => 'Ledger breakdown';

  @override
  String get aiContextSummaryThisMonth => 'Monthly summary';

  @override
  String aiContextSummaryNetWorthLine(String pct) {
    return 'Net worth $pct this month';
  }

  @override
  String aiContextSummaryUnusualLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unusual expenses flagged',
      one: '1 unusual expense flagged',
    );
    return '$_temp0';
  }

  @override
  String aiContextSummaryUpcomingLine(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deposits mature in ${days}d',
      one: '1 deposit matures in ${days}d',
    );
    return '$_temp0';
  }

  @override
  String get aiActionCardsTitle => 'Suggested actions';

  @override
  String get aiActionCardsOpen => 'Open →';

  @override
  String get aiInsightsPanelTitle => 'Insights';

  @override
  String get aiInsightsRebalanceTitle => 'Rebalance';

  @override
  String get aiChatSessionActionsTitle => 'Conversation';

  @override
  String get dashboardNetWorthAssetsLabel => 'Assets';

  @override
  String get dashboardNetWorthLiabilitiesLabel => 'Liabilities';

  @override
  String get dashboardValuationUpdating => 'Updating valuations…';

  @override
  String get dashboardLedgerSyncing => 'Syncing latest records…';

  @override
  String get dashboardValuationUpdated => 'Valuations updated just now';

  @override
  String get portfolioAssetsTab => 'Assets';

  @override
  String get portfolioLiabilitiesTab => 'Liabilities';

  @override
  String get activityActionsTitle => 'Record activity';

  @override
  String get activityActionExpenseHint => 'Cash out for goods or services';

  @override
  String get activityActionTradeHint => 'Buy or sell a security';

  @override
  String get activityActionTransferHint => 'Move funds between two accounts';

  @override
  String get activityActionConvertHint =>
      'Exchange currency inside one account';

  @override
  String get accountsActionsTitle => 'Add wealth container';

  @override
  String get wealthActionPanelSubtitle =>
      'Choose what you want to add to your net worth.';

  @override
  String get wealthActionPanelAccountsGroup => 'Accounts';

  @override
  String get wealthActionPanelFinancialGroup => 'Balances & products';

  @override
  String get wealthActionPanelPhysicalGroup => 'Physical assets';

  @override
  String get wealthActionPanelLiabilitiesGroup => 'Liabilities';

  @override
  String get accountsActionAccountHint => 'Bank, brokerage or crypto account';

  @override
  String get accountsActionLiabilityHint => 'Mortgage, loan or credit balance';

  @override
  String get superFabTrade => 'Trade';

  @override
  String get superFabExpense => 'Expense';

  @override
  String get superFabAsset => 'Asset';

  @override
  String get superFabTransfer => 'Transfer';

  @override
  String get superFabTransferSubtitle => 'Move funds between accounts';

  @override
  String get superFabConvert => 'Convert';

  @override
  String get superFabConvertSubtitle => 'Exchange currency inside one account';

  @override
  String get superFabLiability => 'Liability';

  @override
  String get transferConvertModeBanner =>
      'Converting inside a single account — pick the same account twice and choose two different currencies.';

  @override
  String get homeAppBarTitle => 'Overview';

  @override
  String get homeAiAssistantTooltip => 'AI assistant';

  @override
  String get homeNetWorthTitle => 'Net Worth';

  @override
  String get financePrivacyHideAmountsTooltip => 'Hide amounts';

  @override
  String get financePrivacyShowAmountsTooltip => 'Show amounts';

  @override
  String homeNetWorthSubtitle(String currency) {
    return 'Base currency $currency · shown once data is connected';
  }

  @override
  String get homePassiveIncomeTitle => 'Passive income';

  @override
  String get homePassiveIncomeSubtitle =>
      'TTM dividends, interest, and other passive income';

  @override
  String homePassiveIncomeSubtitleWithNextMonth(String amount) {
    return 'TTM passive income · next month est. $amount';
  }

  @override
  String get homePassiveIncomeEmpty =>
      'Record dividends or interest to start TTM tracking';

  @override
  String get homePassiveIncomeDeltaNew => 'New';

  @override
  String get homeMonthlyCashFlowTitle => 'This month cashflow';

  @override
  String homeMonthlyCashFlowSubtitle(String inflow, String outflow) {
    return 'In $inflow · Out $outflow';
  }

  @override
  String get homeMonthlyCashFlowEmpty =>
      'Add income or spending entries to see this month';

  @override
  String homeMonthlyCashFlowBaseline(String average) {
    return 'vs 3-month average $average';
  }

  @override
  String get homeMonthlyCashFlowBaselineEmpty =>
      '3-month average appears after entries post';

  @override
  String get homeCashFlowEmptyValue => 'No data yet';

  @override
  String get homeCashFlowCardError => 'Cashflow summary is unavailable';

  @override
  String get assetsAppBarTitle => 'Assets';

  @override
  String get assetsDetailEmpty =>
      'Select an asset on the left to see its details.';

  @override
  String get assetsEmptyHint =>
      'No assets yet. Tap the button in the bottom right to add cash, deposits, wealth products, real estate, or vehicles.';

  @override
  String get assetsAddAction => 'Add asset';

  @override
  String assetsLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get assetsAddCashTitle => 'Cash / multi-currency balance';

  @override
  String get assetsAddCashSubtitle =>
      'Track available balance in checking or cash accounts';

  @override
  String get assetsAddDepositTitle => 'Deposit (term / demand)';

  @override
  String get assetsAddDepositSubtitle =>
      'Record interest rate, value date, and maturity';

  @override
  String get assetsAddWealthTitle => 'Wealth product';

  @override
  String get assetsAddWealthSubtitle =>
      'Maintain expected return and current valuation manually';

  @override
  String get assetsAddRealEstateSubtitle =>
      'Address, purchase price, current valuation; can link a mortgage';

  @override
  String get assetsAddVehicleSubtitle =>
      'Purchase price, annual residual rate, automatic depreciation';

  @override
  String assetsChipInterestRate(String rate) {
    return 'Rate $rate%';
  }

  @override
  String assetsChipExpectedReturn(String rate) {
    return 'Expected $rate%';
  }

  @override
  String assetsChipMaturityDate(String date) {
    return 'Matures $date';
  }

  @override
  String get assetTypeCash => 'Cash';

  @override
  String get assetTypeBankDepositTerm => 'Term deposit';

  @override
  String get assetTypeBankDepositDemand => 'Demand deposit';

  @override
  String get assetTypeWealthProduct => 'Wealth product';

  @override
  String get assetTypeStock => 'Stock';

  @override
  String get assetTypeEtf => 'ETF';

  @override
  String get assetTypeMutualFund => 'Mutual fund';

  @override
  String get assetTypeBond => 'Bond';

  @override
  String get assetTypeCrypto => 'Crypto';

  @override
  String securitiesHoldingQuantity(String quantity) {
    return 'Qty $quantity';
  }

  @override
  String get securitiesHoldingFlat => 'Not held';

  @override
  String get corpActionTitle => 'Corporate Action';

  @override
  String get corpActionSelectAsset => 'Asset';

  @override
  String get corpActionSelectAssetHint =>
      'Choose which holding the action applies to.';

  @override
  String get corpActionEventTypeTitle => 'Event type';

  @override
  String get corpActionTypeCashDividend => 'Cash dividend';

  @override
  String get corpActionTypeStockDividend => 'Stock dividend';

  @override
  String get corpActionTypeSplit => 'Split / reverse split';

  @override
  String get corpActionTypeRightsIssue => 'Rights issue';

  @override
  String get corpActionTypeDrip => 'DRIP (reinvest)';

  @override
  String get corpActionEffectiveDate => 'Effective date';

  @override
  String get corpActionAmountPerShare => 'Amount per share';

  @override
  String get corpActionWithholdingTax => 'Withholding tax (total)';

  @override
  String get corpActionBonusRatio =>
      'Bonus ratio (extra shares per held share)';

  @override
  String get corpActionSplitRatio => 'Split ratio';

  @override
  String get corpActionSplitRatioHelp =>
      '2 = 2-for-1 forward split · 0.1 = 1-for-10 reverse split';

  @override
  String get corpActionSubscribedQuantity => 'Subscribed quantity';

  @override
  String get corpActionPricePerUnit => 'Price per share';

  @override
  String get corpActionFee => 'Fee';

  @override
  String get corpActionPreviewAction => 'Preview impact';

  @override
  String get corpActionSubmitAction => 'Submit';

  @override
  String get corpActionPreviewHeading => 'Preview';

  @override
  String get corpActionNoEligibleHolding =>
      'No eligible holding for this asset and account on the effective date.';

  @override
  String get corpActionPreviewSharesOnRecord => 'Shares on record';

  @override
  String get corpActionPreviewGross => 'Gross';

  @override
  String get corpActionPreviewTax => 'Tax';

  @override
  String get corpActionPreviewNet => 'Net';

  @override
  String get corpActionPreviewCashFlow => 'Cash flow';

  @override
  String corpActionPreviewLotChange(
    String id,
    String beforeQty,
    String afterQty,
    String beforeCost,
    String afterCost,
  ) {
    return 'Lot $id: $beforeQty → $afterQty @ $beforeCost → $afterCost';
  }

  @override
  String corpActionPreviewNewLot(String qty, String cost) {
    return 'New lot: $qty @ $cost';
  }

  @override
  String get corpActionSubmitted => 'Recorded.';

  @override
  String get corpActionInvalidNumber => 'Enter a positive number';

  @override
  String get corpActionInvalidNumberNonNegative =>
      'Enter a non-negative number';

  @override
  String get assetsLiabilitiesLink => 'Liabilities & repayment plans';

  @override
  String get liabilitiesAppBarTitle => 'Liabilities';

  @override
  String get liabilitiesEmptyHint =>
      'No liabilities yet. Add a mortgage, car loan, credit card or consumer loan to track repayment.';

  @override
  String get liabilitiesAddAction => 'Add liability';

  @override
  String get liabilityTypeMortgage => 'Mortgage';

  @override
  String get liabilityTypeCarLoan => 'Car loan';

  @override
  String get liabilityTypeCreditCard => 'Credit card';

  @override
  String get liabilityTypeConsumerLoan => 'Consumer loan';

  @override
  String get liabilityTypeStudentLoan => 'Student loan';

  @override
  String get liabilityTypeMarginLoan => 'Margin loan';

  @override
  String get liabilityTypeOther => 'Other';

  @override
  String get liabilityRateTypeFixed => 'Fixed rate';

  @override
  String get liabilityRateTypeLpr => 'LPR floating';

  @override
  String get liabilityMethodEqualInstallment => 'Equal installment';

  @override
  String get liabilityMethodEqualPrincipal => 'Equal principal';

  @override
  String get liabilityFieldName => 'Name';

  @override
  String get liabilityFieldType => 'Type';

  @override
  String get liabilityFieldPrincipal => 'Principal';

  @override
  String get liabilityFieldInterestRate => 'Annual rate (%)';

  @override
  String get liabilityFieldRateType => 'Rate type';

  @override
  String get liabilityFieldTerm => 'Term (months)';

  @override
  String get liabilityFieldStartDate => 'Start date';

  @override
  String get liabilityFieldMethod => 'Repayment method';

  @override
  String get liabilityFieldCurrency => 'Currency';

  @override
  String get liabilityFieldStatementDay => 'Statement day';

  @override
  String get liabilityFieldPaymentDueDay => 'Payment due day';

  @override
  String get liabilitySaveAction => 'Save';

  @override
  String get liabilityValidationRequired => 'Required';

  @override
  String get liabilityValidationPositive => 'Must be greater than zero';

  @override
  String get liabilityValidationDayOfMonth => 'Must be 1–31';

  @override
  String get liabilitySummaryRemaining => 'Remaining principal';

  @override
  String get liabilitySummaryInterestPaid => 'Interest paid so far';

  @override
  String get liabilitySummaryInterestTotal => 'Total interest cost';

  @override
  String get liabilitySummaryInterestRatio =>
      'Interest as share of total payments';

  @override
  String liabilitySummaryProgress(int paid, int total) {
    return 'Paid $paid of $total periods';
  }

  @override
  String get liabilityScheduleHeading => 'Amortization schedule';

  @override
  String get liabilityScheduleColPeriod => '#';

  @override
  String get liabilityScheduleColDue => 'Due';

  @override
  String get liabilityScheduleColPrincipal => 'Principal';

  @override
  String get liabilityScheduleColInterest => 'Interest';

  @override
  String get liabilityScheduleColRemaining => 'Balance';

  @override
  String get liabilityScheduleColStatus => 'Status';

  @override
  String get liabilityScheduleStatusPaid => 'Paid';

  @override
  String get liabilityScheduleStatusDue => 'Pending';

  @override
  String get liabilityScheduleMarkPaid => 'Mark paid';

  @override
  String liabilityScheduleMarkPaidConfirmTitle(int period) {
    return 'Mark period $period paid?';
  }

  @override
  String liabilityScheduleMarkPaidConfirmBody(String amount) {
    return 'This records a $amount liability-payment transaction dated today and cannot be undone from this screen.';
  }

  @override
  String get liabilityScheduleMarkPaidNoAccount =>
      'Assign a payer account before marking periods paid.';

  @override
  String get liabilityNotFound => 'Liability not found';

  @override
  String get liabilityRevolvingNoSchedule =>
      'Credit-card / revolving lines have no fixed amortization schedule.';

  @override
  String get physicalAssetsSectionTitle => 'Real estate & vehicles';

  @override
  String get physicalAssetsEmpty =>
      'No real estate or vehicles yet. Tap + to add one.';

  @override
  String get physicalAssetTypeRealEstate => 'Real estate';

  @override
  String get physicalAssetTypeVehicle => 'Vehicle';

  @override
  String get physicalAssetAddRealEstate => 'Add real estate';

  @override
  String get physicalAssetAddVehicle => 'Add vehicle';

  @override
  String get physicalAssetFieldName => 'Name';

  @override
  String get physicalAssetFieldAddress => 'Address';

  @override
  String get physicalAssetFieldPurchaseDate => 'Purchase date';

  @override
  String get physicalAssetFieldPurchasePrice => 'Purchase price';

  @override
  String get physicalAssetFieldCurrentValuation => 'Current valuation';

  @override
  String get physicalAssetFieldCurrency => 'Currency';

  @override
  String get physicalAssetFieldAnnualResidualRate => 'Annual residual rate';

  @override
  String get physicalAssetFieldAutoDepreciation =>
      'Auto-depreciate between updates';

  @override
  String get physicalAssetFieldLinkedLiability => 'Linked mortgage / loan id';

  @override
  String get physicalAssetFieldNote => 'Note';

  @override
  String get physicalAssetCreateSubmit => 'Save';

  @override
  String get physicalAssetUpdateValuationAction => 'Update valuation';

  @override
  String get physicalAssetUpdateValuationTitle => 'Update valuation';

  @override
  String get physicalAssetUpdateValuationDate => 'As-of date';

  @override
  String get physicalAssetUpdateValuationAmount => 'New valuation';

  @override
  String get physicalAssetUpdateValuationSubmit => 'Save valuation';

  @override
  String get physicalAssetDeleteAction => 'Delete';

  @override
  String get physicalAssetDeleteConfirmTitle => 'Delete this asset?';

  @override
  String get physicalAssetDeleteConfirmBody =>
      'Valuation history will be tombstoned but recoverable on devices that have already synced.';

  @override
  String get physicalAssetDetailValuationTitle => 'Current valuation';

  @override
  String get physicalAssetDetailHistoryTitle => 'Valuation history';

  @override
  String get physicalAssetDetailDepreciationProjection =>
      'Depreciation projection';

  @override
  String get physicalAssetDetailPurchaseLabel => 'Purchase';

  @override
  String get physicalAssetDetailManualUpdateLabel => 'Manual update';

  @override
  String get physicalAssetDetailAutoEstimateLabel => 'Auto-estimate';

  @override
  String physicalAssetDetailEstimatedToday(String value) {
    return 'Estimated value today: $value';
  }

  @override
  String get physicalAssetValidationRequired => 'Required';

  @override
  String get physicalAssetValidationPositive => 'Must be greater than 0';

  @override
  String get physicalAssetValidationResidualRange => 'Must be between 0 and 1';

  @override
  String get physicalAssetNotFound => 'Asset not found';

  @override
  String get settingsAppBarTitle => 'Settings';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsAccountSubtitle => 'Sign-in & multi-device sync';

  @override
  String get settingsBaseCurrencyTitle => 'Base currency';

  @override
  String settingsBaseCurrencySubtitle(String currency) {
    return '$currency (default)';
  }

  @override
  String get settingsBaseCurrencyHint =>
      'Totals on the dashboard, allocation chart, and trend chart are shown in this currency.';

  @override
  String get settingsBaseCurrencySheetTitle => 'Pick base currency';

  @override
  String get settingsFxRatesTitle => 'FX rates';

  @override
  String get settingsFxRatesSubtitle =>
      'Exchange rates are auto-synced from Yahoo Finance. Manual entry available as fallback.';

  @override
  String get fxRatesAppBarTitle => 'FX rates';

  @override
  String get fxRatesEmpty =>
      'No FX rates recorded yet. Rates are auto-synced on app launch — add accounts in different currencies to get started.';

  @override
  String get fxRatesRefreshing => 'Syncing rates…';

  @override
  String get fxRatesSyncedFrom => 'Source';

  @override
  String get fxRatesAddAction => 'Add rate';

  @override
  String get fxRatesEntrySheetTitle => 'Add an FX rate';

  @override
  String get fxRatesFromLabel => 'From';

  @override
  String get fxRatesToLabel => 'To';

  @override
  String get fxRatesRateLabel => 'Rate';

  @override
  String get fxRatesAsOfLabel => 'As of';

  @override
  String get fxRatesSamePairError =>
      'Source and target currencies must differ.';

  @override
  String get fxRatesInvalidRateError => 'Rate must be a positive number.';

  @override
  String dashboardCurrencyMismatchBanner(int count, String currency) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings excluded — missing FX rates to $currency',
      one: '1 holding excluded — missing FX rate to $currency',
    );
    return '$_temp0';
  }

  @override
  String get dashboardCurrencyMismatchAction => 'View';

  @override
  String get dashboardCurrencyMismatchSheetTitle =>
      'Holdings excluded from totals';

  @override
  String get settingsAboutTitle => 'About NaviWealth';

  @override
  String settingsAboutSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeModeTitle => 'Theme';

  @override
  String get themeModeSystem => 'Follow system';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get settingsMarketColorTitle => 'Up / down colors';

  @override
  String get marketColorRedUpGreenDown => 'Red up / green down (CN)';

  @override
  String get marketColorGreenUpRedDown => 'Green up / red down (Intl)';

  @override
  String get marketColorColorblind => 'Color-blind safe (blue / orange)';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get langSystem => 'System default';

  @override
  String get langEnglish => 'English';

  @override
  String get langChinese => '中文';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonClose => 'Close';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonError => 'Something went wrong';

  @override
  String commonLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get commonLoadFailed => 'Couldn\'t load this view. Please try again.';

  @override
  String get commonSaveFailed => 'Couldn\'t save your changes. Tap retry.';

  @override
  String get commonUndo => 'Undo';

  @override
  String get deferredLoadFailedTitle => 'Couldn\'t load this section';

  @override
  String get deferredLoadRetry => 'Retry';

  @override
  String get routeNotFoundTitle => 'Page not found';

  @override
  String routeNotFoundMessage(String path) {
    return 'We couldn\'t find $path. It may have been moved or never existed.';
  }

  @override
  String get routeErrorTitle => 'Something went wrong';

  @override
  String get routeGoHome => 'Back to overview';

  @override
  String get routeGoBack => 'Go back';

  @override
  String get shortcutsHelpTitle => 'Keyboard shortcuts';

  @override
  String get shortcutCommandPalette => 'Open command palette';

  @override
  String get shortcutShowHelp => 'Show keyboard shortcut help';

  @override
  String get shortcutDismissOverlay => 'Close current dialog';

  @override
  String get shortcutToggleSidebar => 'Collapse / expand sidebar';

  @override
  String shortcutSwitchTab(int position, String label) {
    return 'Switch to tab $position ($label)';
  }

  @override
  String get shortcutOpenAiChat => 'Open AI chat';

  @override
  String shortcutVimGoto(String target) {
    return 'Vim-style go to $target';
  }

  @override
  String get shortcutListSearch => 'Focus list search';

  @override
  String get shortcutListNext => 'Select next item';

  @override
  String get shortcutListPrevious => 'Select previous item';

  @override
  String get commandPaletteSearchHint => 'Search commands…';

  @override
  String get commandPaletteMobileEntryHint => 'Search, jump, ask…';

  @override
  String get commandPaletteEmpty => 'No commands match your search';

  @override
  String commandPaletteAskAi(String query) {
    return 'Ask AI: $query';
  }

  @override
  String get askAiResultLocalBadge => 'Local';

  @override
  String get askAiResultNoLocalMatch =>
      'Can\'t answer this here. Continue in AI history for a full chat.';

  @override
  String get askAiResultContinueInChat => 'Continue in AI history →';

  @override
  String get askAiResultIrreversibleBlocked =>
      'The command palette doesn\'t execute transfers, orders, or account deletion. Use the corresponding page.';

  @override
  String askAiResultError(String error) {
    return 'Could not run this query: $error';
  }

  @override
  String get askAiResultEmpty => 'No matching records.';

  @override
  String askAiResultMoreRows(int count) {
    return '+$count more';
  }

  @override
  String askAiResultRowCount(int count) {
    return '$count rows';
  }

  @override
  String get askAiResultTitleSpending => 'Spending by category';

  @override
  String get askAiResultTitleTransactions => 'Transactions';

  @override
  String get askAiResultTitleNetWorth => 'Net worth trend';

  @override
  String get askAiResultTitleSubscriptions => 'Subscriptions';

  @override
  String get askAiResultTitleRefunds => 'Refund matches';

  @override
  String get askAiResultTitleGeneric => 'Result';

  @override
  String get commandPaletteGoOverview => 'Go to Overview';

  @override
  String get commandPaletteGoSettings => 'Go to Settings';

  @override
  String get commandPaletteNewTrade => 'New trade';

  @override
  String get commandPaletteNewExpense => 'New expense';

  @override
  String get commandPaletteOpenAi => 'Ask AI';

  @override
  String get commandPaletteAiHistory => 'AI history';

  @override
  String get commandPaletteToggleTheme => 'Toggle theme (light / dark)';

  @override
  String get commandPaletteToggleColorMode => 'Toggle market color mode';

  @override
  String get commandPaletteToggleLanguage => 'Toggle language';

  @override
  String get commandPaletteShortcutHelp => 'Show keyboard shortcuts';

  @override
  String get pwaUpdateAvailable => 'A new version of NaviWealth is ready.';

  @override
  String get pwaUpdateApply => 'Refresh';

  @override
  String get pwaUpdateDismiss => 'Later';

  @override
  String get authLoginTitle => 'Welcome back';

  @override
  String get authRegisterTitle => 'Create account';

  @override
  String get authLoginSubmit => 'Sign in';

  @override
  String get authRegisterSubmit => 'Create account';

  @override
  String get authRegisterSwitch => 'Create an account';

  @override
  String get authLoginSwitch => 'Sign in instead';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordShowTooltip => 'Show password';

  @override
  String get authPasswordHideTooltip => 'Hide password';

  @override
  String get authEmailErrorEmpty => 'Enter your email address.';

  @override
  String get authEmailErrorInvalid => 'That doesn\'t look like a valid email.';

  @override
  String get authPasswordErrorEmpty => 'Enter your password.';

  @override
  String get authPasswordErrorTooShort =>
      'Password must be at least 8 characters.';

  @override
  String get authLoginErrorInvalidCredentials =>
      'Email or password is incorrect.';

  @override
  String get authLoginErrorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get authLoginErrorServer =>
      'The server is having trouble. Please try again in a minute.';

  @override
  String get authLoginErrorGeneric => 'Sign-in failed. Please try again.';

  @override
  String get authRegisterErrorAccountExists =>
      'An account already exists. Sign in instead.';

  @override
  String get authLoginNoticeSessionExpired =>
      'Your session expired. Please sign in again.';

  @override
  String get settingsDevicesTitle => 'Devices';

  @override
  String get settingsDevicesSubtitle =>
      'View signed-in devices and revoke access';

  @override
  String get authDevicesTitle => 'Signed-in devices';

  @override
  String get authDeviceUnnamed => 'Unnamed device';

  @override
  String get authDeviceCurrent => 'This device';

  @override
  String authDeviceLastSeen(String timestamp) {
    return 'Last seen $timestamp';
  }

  @override
  String get authDeviceRevokeTooltip => 'Sign this device out';

  @override
  String get authDeviceRevokeDialogTitle => 'Sign this device out?';

  @override
  String authDeviceRevokeDialogBody(String device) {
    return 'Sign $device out? It will need to log in again to sync.';
  }

  @override
  String get authDeviceRevokeConfirm => 'Sign out';

  @override
  String get authDeviceRevokeError =>
      'Couldn\'t revoke that device. Please try again.';

  @override
  String get authDevicesLoadError => 'Couldn\'t load your devices.';

  @override
  String get authLogoutCurrentTooltip => 'Sign out';

  @override
  String get authLogoutDialogTitle => 'Sign out?';

  @override
  String get authLogoutDialogBody =>
      'You\'ll need to sign in again on this device.';

  @override
  String get authLogoutDialogConfirm => 'Sign out';

  @override
  String get dashboardAllocationTitle => 'Asset allocation';

  @override
  String get dashboardTrendTitle => 'Net worth trend';

  @override
  String get dashboardCategoryStock => 'Stocks';

  @override
  String get dashboardCategoryEtf => 'ETFs';

  @override
  String get dashboardCategoryBondsAndFunds => 'Bonds & funds';

  @override
  String get dashboardCategoryCash => 'Cash';

  @override
  String get dashboardCategoryCrypto => 'Crypto';

  @override
  String get dashboardCategoryRealEstate => 'Real estate';

  @override
  String get dashboardCategoryVehicle => 'Vehicles';

  @override
  String get dashboardCategoryLiability => 'Liabilities';

  @override
  String get dashboardRange1M => '1M';

  @override
  String get dashboardRange3M => '3M';

  @override
  String get dashboardRange6M => '6M';

  @override
  String get dashboardRange1Y => '1Y';

  @override
  String get dashboardRange3Y => '3Y';

  @override
  String get dashboardRangeAll => 'All';

  @override
  String get dashboardRangeCustom => 'Custom';

  @override
  String dashboardDrillDownItemCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String dashboardNetWorthBreakdown(
    String assets,
    String liabilities,
    String currency,
  ) {
    return 'Assets $assets − Liabilities $liabilities ($currency)';
  }

  @override
  String dashboardSnapshotError(String error) {
    return 'Couldn\'t load your dashboard: $error';
  }

  @override
  String dashboardTrendError(String error) {
    return 'Couldn\'t load the trend chart: $error';
  }

  @override
  String get dashboardTrendFlatHint =>
      'Trend line is flat — no historical valuation snapshots yet for the assets in this window.';

  @override
  String get dashboardHeaderDeltaTodayLabel => 'Today';

  @override
  String get dashboardHeaderDeltaMonthLabel => 'MTD';

  @override
  String get dashboardHeaderDeltaYtdLabel => 'YTD';

  @override
  String get analyticsAppBarTitle => 'Analytics';

  @override
  String get analyticsEquityTitle => 'Equity Allocation';

  @override
  String get analyticsEquitySubtitle =>
      'Slice your stock & ETF holdings by sector, region, or market cap.';

  @override
  String get analyticsDimensionSector => 'Sector';

  @override
  String get analyticsDimensionRegion => 'Region';

  @override
  String get analyticsDimensionMarketCap => 'Market Cap';

  @override
  String analyticsTotalValueLabel(String currency) {
    return 'Total $currency';
  }

  @override
  String get analyticsBucketUnclassified => 'Unclassified';

  @override
  String get analyticsBucketRegionCnA => 'A-shares';

  @override
  String get analyticsBucketRegionHk => 'Hong Kong';

  @override
  String get analyticsBucketRegionUs => 'United States';

  @override
  String get analyticsBucketRegionCrypto => 'Crypto';

  @override
  String get analyticsBucketRegionFx => 'FX';

  @override
  String get analyticsBucketRegionUnknown => 'Other';

  @override
  String get analyticsBucketMarketCapLarge => 'Large cap';

  @override
  String get analyticsBucketMarketCapMid => 'Mid cap';

  @override
  String get analyticsBucketMarketCapSmall => 'Small cap';

  @override
  String analyticsHoldingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings',
      one: '$count holding',
    );
    return '$_temp0';
  }

  @override
  String analyticsUnclassifiedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings are missing classification metadata.',
      one: '1 holding is missing classification metadata.',
    );
    return '$_temp0';
  }

  @override
  String get analyticsUnclassifiedAction => 'Complete';

  @override
  String get analyticsUnclassifiedRowCta =>
      'Tap a holding to fill in its metadata.';

  @override
  String get analyticsEmptyTitle => 'No equity holdings yet';

  @override
  String get analyticsEmptyHint =>
      'Once you record stock or ETF trades, the breakdown will show up here.';

  @override
  String get analyticsLoadError => 'Couldn\'t load the allocation view.';

  @override
  String get analyticsRetry => 'Retry';

  @override
  String analyticsBucketSheetTitle(String label) {
    return 'Holdings in $label';
  }

  @override
  String analyticsHoldingTooltip(String symbol, String value, String weight) {
    return '$symbol · $value · $weight';
  }

  @override
  String get fireAppBarTitle => 'FIRE';

  @override
  String fireLoadError(String detail) {
    return 'Could not load FIRE dashboard. $detail';
  }

  @override
  String get fireRetry => 'Retry';

  @override
  String get fireEmptyTitle => 'Set your FIRE goal';

  @override
  String get fireEmptyHint =>
      'Enter your target net worth, monthly expenses and savings to see how far you are from financial independence.';

  @override
  String get fireEmptySetGoalCta => 'Set goal';

  @override
  String get fireEditGoal => 'Edit goal';

  @override
  String get fireGoalSheetTitle => 'FIRE goal';

  @override
  String get fireGoalSheetSubtitle =>
      'Inputs are stored on this device only and are inflation-adjusted with the rate below.';

  @override
  String get fireGoalSheetCancel => 'Cancel';

  @override
  String get fireGoalSheetSave => 'Save';

  @override
  String get fireGoalFieldTarget => 'Target net worth';

  @override
  String get fireGoalFieldTargetHelper =>
      'Net worth required to retire, in today\'s purchasing power.';

  @override
  String get fireGoalFieldMonthlyExpenses => 'Monthly expenses at FIRE';

  @override
  String get fireGoalFieldMonthlyExpensesHelper =>
      'Used by the 4% rule to check if your target supports your lifestyle.';

  @override
  String get fireGoalFieldMonthlySurplus => 'Monthly surplus (savings)';

  @override
  String get fireGoalFieldMonthlySurplusHelper =>
      'How much you save each month — drives the projection\'s contribution.';

  @override
  String fireGoalFieldInflation(String rate) {
    return 'Inflation: $rate%';
  }

  @override
  String get fireGoalValidationRequired => 'Required';

  @override
  String get fireGoalValidationInvalidNumber => 'Enter a valid number';

  @override
  String get fireGoalValidationNonNegative => 'Must be zero or positive';

  @override
  String get fireGoalValidationPositive => 'Must be greater than zero';

  @override
  String get fireProgressTitle => 'Progress to FIRE';

  @override
  String get fireProgressGaugeCaption => 'of FIRE target';

  @override
  String get fireProgressCurrent => 'Current net worth';

  @override
  String get fireProgressTarget => 'Target';

  @override
  String get fireProgressGap => 'Gap to FIRE';

  @override
  String fireCountdownTitle(String scenario) {
    return 'Time to FIRE · $scenario';
  }

  @override
  String get fireCountdownReachedTitle => 'You\'ve reached FIRE';

  @override
  String get fireCountdownReachedSubtitle =>
      'Net worth already meets the target — focus on sustaining the safe-withdrawal rate.';

  @override
  String get fireCountdownUnreachable =>
      'Unreachable within 100 years at the current surplus and return rate. Increase savings or your return assumption.';

  @override
  String get fireCountdownUnreachableShort => '100y+';

  @override
  String fireCountdownYearsOnly(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years',
      one: '1 year',
    );
    return '$_temp0';
  }

  @override
  String fireCountdownMonthsOnly(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String fireCountdownYearsMonths(int years, int months) {
    return '${years}y ${months}m';
  }

  @override
  String fireCountdownDaysAprox(int days) {
    return '≈ $days days';
  }

  @override
  String get fireProjectionTitle => 'Projection';

  @override
  String get fireProjectionSubtitle =>
      'Net worth path under each return scenario; dashed line is the inflation-adjusted target.';

  @override
  String get fireProjectionTargetLineLegend => 'Target (inflation-adjusted)';

  @override
  String get fireScenariosTableTitle => 'Scenarios';

  @override
  String get fireScenarioConservative => 'Conservative';

  @override
  String get fireScenarioNeutral => 'Neutral';

  @override
  String get fireScenarioAggressive => 'Aggressive';

  @override
  String get fireScenarioLive => 'Live (XIRR)';

  @override
  String fireScenarioRateLabel(String rate) {
    return '$rate% annualized';
  }

  @override
  String get fireScenarioReachedNow => 'Now';

  @override
  String get fireSafeWithdrawalTitle => '4% rule';

  @override
  String get fireSafeWithdrawalSubtitle =>
      'Trinity-study safe withdrawal: 4% of the target each year, in today\'s purchasing power.';

  @override
  String get fireSafeWithdrawalMonthly => 'Safe monthly withdrawal';

  @override
  String get fireSafeWithdrawalAnnual => 'Safe annual withdrawal';

  @override
  String get fireSafeWithdrawalNoExpenses =>
      'Set monthly expenses to compare with this withdrawal.';

  @override
  String fireSafeWithdrawalCovers(String amount) {
    return 'Covers planned expenses with $amount to spare each month.';
  }

  @override
  String fireSafeWithdrawalShortfall(String amount) {
    return 'Falls short of planned expenses by $amount per month.';
  }

  @override
  String get fireSensitivityTitle => 'Sensitivity';

  @override
  String get fireSensitivitySubtitle =>
      'How time-to-FIRE shifts when monthly surplus changes by ±20%.';

  @override
  String get fireSensitivityHigherSurplus => '+20% surplus';

  @override
  String get fireSensitivityBaseline => 'Current surplus';

  @override
  String get fireSensitivityLowerSurplus => '-20% surplus';

  @override
  String get fireOsHeroTitle => 'Freedom status';

  @override
  String get fireOsHeroSubtitle =>
      'Whether today\'s portfolio still supports the lifestyle you planned for.';

  @override
  String get fireOsHeroNetWorthLabel => 'Net worth';

  @override
  String get fireOsHeroInvestableLabel => 'Investable';

  @override
  String get fireOsHeroLiquidLabel => 'Liquid';

  @override
  String get fireOsHeroWithdrawalRateLabel => 'Withdrawal rate';

  @override
  String fireOsHeroWithdrawalRateValue(String rate, String swr) {
    return '$rate% / SWR $swr%';
  }

  @override
  String get fireOsHeroWithdrawalRateInfinite =>
      'Spend without investable assets';

  @override
  String get fireOsHeroCashBucketLabel => 'Cash bucket';

  @override
  String fireOsHeroCashBucketValue(String months, int target) {
    return '$months mo / target $target mo';
  }

  @override
  String get fireOsHeroCashBucketInfinite => 'No recorded monthly expense';

  @override
  String get fireOsHeroEtaLabel => 'FIRE ETA';

  @override
  String get fireOsHeroEtaReached => 'Already reached';

  @override
  String get fireOsHeroEtaUnreachable => 'Not within 100 years';

  @override
  String get fireOsHeroAnnualSpendLabel => 'Annual spend';

  @override
  String get fireOsAnnualSpendSourceTrailing => 'Trailing 12 months';

  @override
  String get fireOsAnnualSpendSourcePlan => 'Plan input';

  @override
  String get fireOsSafetySafe => 'Safe';

  @override
  String get fireOsSafetyCautious => 'Cautious';

  @override
  String get fireOsSafetyDanger => 'Danger';

  @override
  String get fireOsSafetyUnconfigured => 'Plan not set';

  @override
  String get fireOsSuggestedActionsTitle => 'Suggested next steps';

  @override
  String get fireOsSuggestedActionsEmpty =>
      'No actions right now — the plan is steady.';

  @override
  String get fireOsActionConfigurePlanTitle => 'Set up your FIRE plan';

  @override
  String get fireOsActionConfigurePlanDetail =>
      'Tell NaviWealth your target, expenses, and savings so it can judge safety.';

  @override
  String get fireOsActionHoldSteadyTitle => 'On track — keep it steady';

  @override
  String get fireOsActionHoldSteadyDetail =>
      'Withdrawal rate is below SWR and the cash bucket is healthy.';

  @override
  String get fireOsActionTopUpCashBucketTitle => 'Top up the cash bucket';

  @override
  String fireOsActionTopUpCashBucketDetail(String amount, int months) {
    return 'Add $amount to reach $months months of runway.';
  }

  @override
  String get fireOsActionReduceSpendingTitle => 'Reduce spending';

  @override
  String fireOsActionReduceSpendingDetailPct(String pct) {
    return 'Withdrawal rate is $pct percentage points above your SWR.';
  }

  @override
  String get fireOsActionReduceSpendingDetailGeneric =>
      'Spending has outrun the investable base — review the monthly burn.';

  @override
  String get fireOsActionDelayDiscretionaryTitle => 'Delay discretionary spend';

  @override
  String get fireOsActionDelayDiscretionaryDetail =>
      'Push travel, upgrades, or big purchases out until the withdrawal rate cools down.';

  @override
  String get fireOsActionRebalanceTitle => 'Rebalance toward target';

  @override
  String get fireOsActionRebalanceDetail =>
      'Allocation has drifted — bring sleeves back in line.';

  @override
  String get fireOsActionBuildRiskReserveTitle => 'Build a risk reserve';

  @override
  String get fireOsActionBuildRiskReserveDetail =>
      'Net worth is negative or thin — set aside emergency / medical reserves.';

  @override
  String get fireOsActionRunReviewTitle => 'Open the latest review';

  @override
  String get fireOsActionRunReviewDetail =>
      'Check the monthly or quarterly review for context.';

  @override
  String get fireOsActionFixCurrencyGapTitle => 'Fix missing FX rates';

  @override
  String fireOsActionFixCurrencyGapDetail(int count) {
    return '$count holdings are missing a rate into your base currency.';
  }

  @override
  String get fireOsPlanFormAdvancedTitle => 'Advanced';

  @override
  String get fireOsPlanFormSwrLabel => 'Safe withdrawal rate';

  @override
  String fireOsPlanFormSwrValue(String rate) {
    return '$rate%';
  }

  @override
  String get fireOsPlanFormSwrHelper =>
      'Trinity-study default is 4%. Lean FIRE typically aims lower; Fat FIRE leaves more buffer.';

  @override
  String get fireOsPlanFormCashBucketLabel => 'Cash bucket target (months)';

  @override
  String get fireOsPlanFormCashBucketHelper =>
      'How many months of expenses to keep in liquid cash.';

  @override
  String get fireOsPlanFormLifestyleLabel => 'Lifestyle mode';

  @override
  String get fireOsPlanFormLifestyleLean => 'Lean';

  @override
  String get fireOsPlanFormLifestyleStandard => 'Standard';

  @override
  String get fireOsPlanFormLifestyleFat => 'Fat';

  @override
  String get fireOsPlanFormLifestyleCoast => 'Coast';

  @override
  String get fireOsPlanFormLifestyleBarista => 'Barista';

  @override
  String get fireOsBucketsTitle => 'Buckets';

  @override
  String get fireOsBucketsSubtitle =>
      'Each holding is interpreted as one of cash, defensive, growth, risk reserve, or dream.';

  @override
  String get fireOsBucketRoleCash => 'Cash';

  @override
  String get fireOsBucketRoleDefensive => 'Defensive';

  @override
  String get fireOsBucketRoleGrowth => 'Growth';

  @override
  String get fireOsBucketRoleRiskReserve => 'Risk reserve';

  @override
  String get fireOsBucketRoleDream => 'Dream';

  @override
  String get fireOsBucketStatusOnTrack => 'On track';

  @override
  String get fireOsBucketStatusUnder => 'Below target';

  @override
  String get fireOsBucketStatusOver => 'Over target';

  @override
  String get fireOsBucketStatusEmpty => 'Empty';

  @override
  String get fireOsBucketNoTarget => 'No formal target';

  @override
  String fireOsBucketCoverage(String current, String target) {
    return '$current / $target';
  }

  @override
  String fireOsBucketAssets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings',
      one: '1 holding',
    );
    return '$_temp0';
  }

  @override
  String get fireOsBucketsManageCta => 'Manage bucket rules';

  @override
  String get fireOsBucketsMappingTitle => 'Bucket rules';

  @override
  String get fireOsBucketsMappingSubtitle =>
      'Pick the bucket each holding belongs to. Defaults are applied to anything you leave unset.';

  @override
  String get fireOsBucketsMappingSave => 'Save';

  @override
  String get fireOsBucketsMappingCancel => 'Cancel';

  @override
  String get fireOsBucketsMappingDefault => 'Default';

  @override
  String get fireOsBucketsMappingEmpty =>
      'No holdings to map yet. Add accounts or assets first.';

  @override
  String get fireOsUnmappedTitle => 'Unmapped holdings';

  @override
  String get fireOsUnmappedSubtitle =>
      'These assets aren\'t part of any bucket. Map them if they should fund the plan.';

  @override
  String get fireOsInsightBucketDeviation => 'Bucket below target';

  @override
  String fireOsInsightBucketDeviationValue(
    String role,
    String current,
    String target,
  ) {
    return '$role: $current / $target';
  }

  @override
  String get fireOsInsightUnmappedHoldings => 'Unmapped holdings';

  @override
  String fireOsInsightUnmappedHoldingsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings',
      one: '1 holding',
    );
    return '$_temp0 not assigned to any bucket';
  }

  @override
  String get fireOsSimulationsTitle => 'Simulations';

  @override
  String get fireOsSimulationsSubtitle =>
      'Press a preset to see how a change to the plan moves WR / cash bucket coverage / safety level. Nothing is saved.';

  @override
  String get fireOsSimulationsBaselineLabel => 'Baseline';

  @override
  String get fireOsSimulationsPresetExpenseUp20 => 'Spending +20%';

  @override
  String get fireOsSimulationsPresetExpenseDown10 => 'Spending −10%';

  @override
  String get fireOsSimulationsPresetSurplusUp30 => 'Surplus +30%';

  @override
  String get fireOsSimulationsPresetHalfRetireIncome => 'Half-retire +¥5k/mo';

  @override
  String get fireOsSimulationsPresetInflationUp1pp => 'Inflation +1 pp';

  @override
  String get fireOsSimulationsPresetSwrTight => 'SWR 3.5%';

  @override
  String get fireOsSimulationsPresetCashBucketUp24 => 'Cash bucket 24 mo';

  @override
  String fireOsSimulationsDeltaWrPp(String sign, String pp) {
    return 'WR $sign$pp pp';
  }

  @override
  String get fireOsSimulationsDeltaWrUnavailable => 'WR —';

  @override
  String fireOsSimulationsDeltaCash(String sign, String months) {
    return 'Cash $sign$months mo';
  }

  @override
  String get fireOsSimulationsDeltaCashUnavailable => 'Cash —';

  @override
  String get fireOsStressTitle => 'Stress tests';

  @override
  String get fireOsStressSubtitle =>
      'How the plan holds up under bear markets, expense surges, one-off shocks, FX swings, and cash depletion.';

  @override
  String get fireOsStressEmpty => 'Configure a FIRE plan to run stress tests.';

  @override
  String fireOsStressScenarioMarketDrawdown(String pct) {
    return 'Market drawdown −$pct%';
  }

  @override
  String fireOsStressScenarioExpenseSurge(String pct) {
    return 'Expenses +$pct%';
  }

  @override
  String fireOsStressScenarioOneOffShock(String amount) {
    return 'One-off shock $amount';
  }

  @override
  String fireOsStressScenarioFxShock(String pct) {
    return 'FX shock ±$pct%';
  }

  @override
  String fireOsStressScenarioCashDepletion(int months) {
    return 'Cash drawdown over $months months';
  }

  @override
  String get fireOsStressVerdictSafe => 'Safe';

  @override
  String get fireOsStressVerdictCautious => 'Cautious';

  @override
  String get fireOsStressVerdictDanger => 'Danger';

  @override
  String fireOsStressMetricWr(String rate) {
    return 'WR $rate%';
  }

  @override
  String get fireOsStressMetricWrInfinite => 'WR ∞';

  @override
  String fireOsStressMetricCash(String months) {
    return 'Cash $months mo';
  }

  @override
  String fireOsStressMetricNetWorth(String amount) {
    return 'NW $amount';
  }

  @override
  String get fireOsReviewTitle => 'Periodic review';

  @override
  String get fireOsReviewSubtitle =>
      'Deterministic monthly / quarterly / annual snapshots; the AI explains them, never invents them.';

  @override
  String get fireOsReviewKindMonthly => 'Monthly';

  @override
  String get fireOsReviewKindQuarterly => 'Quarterly';

  @override
  String get fireOsReviewKindAnnual => 'Annual';

  @override
  String fireOsReviewGeneratedAt(String date) {
    return 'Generated $date';
  }

  @override
  String fireOsReviewDiffTitle(String key) {
    return 'Compared to $key';
  }

  @override
  String get fireOsReviewDiffNoBaseline =>
      'No prior snapshot to diff against — save one to see month-over-month deltas.';

  @override
  String fireOsReviewDiffWr(String sign, String pp) {
    return 'WR $sign$pp pp';
  }

  @override
  String get fireOsReviewDiffWrUnavailable =>
      'WR delta unavailable (infinite either side)';

  @override
  String fireOsReviewDiffNetWorth(String sign, String amount) {
    return 'Net worth $sign$amount';
  }

  @override
  String get fireOsReviewDiffNetWorthCurrencyChanged =>
      'Net worth currency changed — delta skipped.';

  @override
  String fireOsReviewDiffSafetyChanged(String from, String to) {
    return 'Safety $from → $to';
  }

  @override
  String fireOsReviewDiffSafetyHeld(String level) {
    return 'Safety held at $level';
  }

  @override
  String get fireOsReviewSaveSnapshot => 'Save snapshot';

  @override
  String fireOsReviewSaved(String key) {
    return 'Saved · $key';
  }

  @override
  String get fireOsReviewFindingsTitle => 'Findings';

  @override
  String get fireOsReviewFindingNetWorthHealthy => 'Net worth is positive.';

  @override
  String get fireOsReviewFindingNetWorthBroken =>
      'Net worth is at or below zero.';

  @override
  String fireOsReviewFindingWithdrawalRateBelowSwr(String pct) {
    return 'Withdrawal rate is below SWR by $pct pp.';
  }

  @override
  String fireOsReviewFindingWithdrawalRateAboveSwr(String pct) {
    return 'Withdrawal rate is above SWR by $pct pp.';
  }

  @override
  String get fireOsReviewFindingWithdrawalRateInfinite =>
      'Spend exists with no investable assets.';

  @override
  String fireOsReviewFindingWithinTargetCashBucket(int months) {
    return 'Cash bucket covers $months months — at target.';
  }

  @override
  String fireOsReviewFindingBelowTargetCashBucket(int months) {
    return 'Cash bucket below the $months-month target.';
  }

  @override
  String get fireOsReviewFindingFireEtaReached =>
      'FIRE target already reached.';

  @override
  String get fireOsReviewFindingFireEtaUnreachable =>
      'FIRE target not reached within 100 years.';

  @override
  String fireOsReviewFindingFireEtaProgressing(int months) {
    return 'FIRE ETA at $months months.';
  }

  @override
  String fireOsReviewFindingCurrencyGap(int count) {
    return '$count holdings without an FX rate to base currency.';
  }

  @override
  String fireOsReviewFindingUnmappedHoldings(int count) {
    return '$count holdings not assigned to a bucket.';
  }

  @override
  String fireOsReviewFindingStressDanger(String scenario) {
    return 'Stress test \"$scenario\" lands at danger.';
  }

  @override
  String fireOsReviewFindingStressCautious(String scenario) {
    return 'Stress test \"$scenario\" lands at cautious.';
  }

  @override
  String get fireOsReviewFindingStressSafe =>
      'All stress tests are safe under current assumptions.';

  @override
  String get fireOsInsightHighWithdrawalRate => 'Withdrawal rate above SWR';

  @override
  String fireOsInsightHighWithdrawalRateValue(String rate, String swr) {
    return '$rate% / SWR $swr%';
  }

  @override
  String get fireOsInsightLowCashBucket => 'Cash bucket below target';

  @override
  String fireOsInsightLowCashBucketValue(String months, int target) {
    return '$months of $target months';
  }

  @override
  String get benchmarkComparisonTitle => 'Benchmark comparison';

  @override
  String get benchmarkComparisonSubtitle =>
      'Pin major indices against your net worth and read off the excess return.';

  @override
  String benchmarkComparisonError(String error) {
    return 'Couldn\'t load the benchmark comparison: $error';
  }

  @override
  String get benchmarkSeriesPortfolio => 'Portfolio';

  @override
  String get benchmarkPortfolioAnnualizedLabel => 'Portfolio annualized';

  @override
  String benchmarkAnnualizedSubtitle(String value) {
    return 'Annualized $value';
  }

  @override
  String get benchmarkIndexHs300 => 'CSI 300';

  @override
  String get benchmarkIndexSp500 => 'S&P 500';

  @override
  String get benchmarkIndexNasdaq => 'NASDAQ';

  @override
  String get benchmarkIndexHsi => 'Hang Seng';

  @override
  String get rebalanceTitle => 'Rebalance';

  @override
  String get rebalanceSchemeTitle => 'Target scheme';

  @override
  String get rebalanceSchemeConservative => 'Conservative';

  @override
  String get rebalanceSchemeBalanced => 'Balanced';

  @override
  String get rebalanceSchemeAggressive => 'Aggressive';

  @override
  String get rebalanceSchemeCustom => 'Custom';

  @override
  String get rebalanceDriftTitle => 'Allocation drift';

  @override
  String rebalanceOverallDrift(String value) {
    return 'Overall drift: $value';
  }

  @override
  String get rebalanceBalanced => 'On target';

  @override
  String get rebalanceTradeTitle => 'Suggested trades';

  @override
  String get rebalanceBuy => 'Buy';

  @override
  String get rebalanceSell => 'Sell';

  @override
  String get rebalanceEstimatedFees => 'Estimated fees';

  @override
  String get rebalanceEstimatedTaxes => 'Estimated taxes';

  @override
  String get rebalanceDriftAfter => 'Drift after rebalance';

  @override
  String get rebalanceExecuteAction => 'Rebalance now';

  @override
  String get rebalanceExecutionSheetTitle => 'Confirm rebalance';

  @override
  String rebalanceExecutionSheetSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review $count draft trades before continuing.',
      one: 'Review 1 draft trade before continuing.',
    );
    return '$_temp0';
  }

  @override
  String get rebalanceExecutionCreateDrafts => 'Create drafts';

  @override
  String get rebalanceExecutionTradeValue => 'Suggested value';

  @override
  String rebalanceExecutionDraftNote(
    Object direction,
    Object category,
    Object amount,
    Object currency,
  ) {
    return 'Rebalance suggestion: $direction $category for $amount $currency';
  }

  @override
  String get rebalanceEmptyTitle => 'No data yet';

  @override
  String get rebalanceEmptyHint =>
      'Add assets to see your allocation drift and rebalance suggestions.';

  @override
  String get rebalanceSettingsTooltip => 'Rebalance settings';

  @override
  String get rebalanceSettingsTitle => 'Drift thresholds';

  @override
  String get rebalanceWarningThreshold => 'Warning threshold';

  @override
  String get rebalanceCriticalThreshold => 'Critical threshold';

  @override
  String get rebalanceNavLink => 'Rebalance';

  @override
  String get rebalanceCommandOpen => 'Go to Rebalance';

  @override
  String get rebalanceCommandAdjustTarget => 'Adjust target allocation';

  @override
  String get targetAllocationEditorTitle => 'Custom target';

  @override
  String get targetAllocationEditorSubtitle =>
      'Tune category weights; the total must equal 100%.';

  @override
  String get targetAllocationEditorEditAction => 'Custom target';

  @override
  String get targetAllocationEditorTotalLabel => 'Total allocation';

  @override
  String targetAllocationEditorTotalHint(String value) {
    return 'Total must be 100%. Current total: $value%.';
  }

  @override
  String get targetAllocationEditorPercentLabel => 'Weight';

  @override
  String get targetAllocationEditorRequiredError => 'Required';

  @override
  String get targetAllocationEditorRangeError => 'Use 0-100';

  @override
  String get targetAllocationEditorPreviewTitle => 'Target mix';

  @override
  String get riskAlertTitle => 'Concentration Alerts';

  @override
  String riskAlertAssetTitle(String name) {
    return '$name overweight';
  }

  @override
  String riskAlertSectorTitle(String sector) {
    return '$sector overweight';
  }

  @override
  String riskAlertRegionTitle(String region) {
    return '$region overweight';
  }

  @override
  String riskAlertCurrencyTitle(String currency) {
    return '$currency exposure';
  }

  @override
  String riskAlertThresholdBreached(String dimension, String threshold) {
    return '$dimension threshold: $threshold';
  }

  @override
  String get riskDimensionAsset => 'Asset';

  @override
  String get riskDimensionSector => 'Sector';

  @override
  String get riskDimensionRegion => 'Region';

  @override
  String get riskDimensionCurrency => 'Currency';

  @override
  String get settingsRiskSection => 'Investment Preferences';

  @override
  String get settingsRiskAssetLabel => 'Single asset limit';

  @override
  String get settingsRiskAssetSubtitle =>
      'Alert when one asset exceeds this share of total portfolio.';

  @override
  String get settingsRiskSectorLabel => 'Sector limit';

  @override
  String get settingsRiskSectorSubtitle =>
      'Alert when one sector exceeds this share.';

  @override
  String get settingsRiskRegionLabel => 'Region limit';

  @override
  String get settingsRiskRegionSubtitle =>
      'Alert when one market / region exceeds this share.';

  @override
  String get settingsRiskCurrencyLabel => 'Currency limit';

  @override
  String get settingsRiskCurrencySubtitle =>
      'Alert when one currency exposure exceeds this share.';

  @override
  String get settingsRiskResetDefaults => 'Reset to defaults';

  @override
  String get settingsRiskAppetiteLabel => 'Risk appetite';

  @override
  String get settingsRiskAppetiteConservative => 'Conservative';

  @override
  String get settingsRiskAppetiteModerate => 'Balanced';

  @override
  String get settingsRiskAppetiteAggressive => 'Aggressive';

  @override
  String get settingsRiskAppetiteCustom => 'Custom';

  @override
  String get settingsRiskAppetiteCustomBadge => 'Custom target weights';

  @override
  String get settingsTargetAllocationLabel => 'Target allocation';

  @override
  String settingsTargetAllocationSubtitlePreset(String preset) {
    return '$preset preset';
  }

  @override
  String get settingsTargetAllocationSubtitleCustom => 'Hand-tuned weights';

  @override
  String get settingsRiskThresholdsLabel => 'Concentration alert thresholds';

  @override
  String get settingsRiskThresholdsSubtitleAuto =>
      'Auto-tuned by your risk appetite';

  @override
  String get settingsRiskThresholdsSubtitleCustom => 'Custom thresholds set';

  @override
  String get settingsRiskThresholdsTitle => 'Concentration alert thresholds';

  @override
  String get settingsRiskThresholdsHint =>
      'These thresholds decide when the Risk Alerts panel flags a position as concentrated. They\'re auto-tuned based on your risk appetite — tweak only if you want to override the defaults.';

  @override
  String get settingsStressTestLabel => 'FIRE stress-test parameters';

  @override
  String get settingsStressTestSubtitleAuto => 'Using defaults';

  @override
  String get settingsStressTestSubtitleCustom => 'Custom assumptions set';

  @override
  String get settingsStressTestTitle => 'FIRE stress-test parameters';

  @override
  String get settingsStressTestHint =>
      'Stress tests on the FIRE page run a few \"what if\" scenarios against your plan. These knobs decide how harsh each scenario assumes the world gets — only worth tweaking if you want a more conservative (higher) or relaxed (lower) test.';

  @override
  String get settingsStressTestMarketDrawdownLabel => 'Market drawdown';

  @override
  String get settingsStressTestMarketDrawdownSubtitle =>
      'Bear-market drop applied to growth assets';

  @override
  String get settingsStressTestExpenseShockLabel => 'Expense shock';

  @override
  String get settingsStressTestExpenseShockSubtitle =>
      'Sustained living-cost increase';

  @override
  String get settingsStressTestFxShockLabel => 'FX shock';

  @override
  String get settingsStressTestFxShockSubtitle => 'Currency swing magnitude';

  @override
  String get settingsStressTestLumpSumLabel => 'One-off lump-sum outlay';

  @override
  String get settingsStressTestLumpSumSubtitle =>
      'Medical / family-support shock, in your base currency';

  @override
  String get settingsStressTestLumpSumHint => '0 = test disabled';

  @override
  String get settingsStressTestResetDefaults => 'Reset to defaults';

  @override
  String get settingsMonthlyExpenseLabel => 'Monthly expense model';

  @override
  String settingsMonthlyExpenseSubtitleAuto(int months) {
    return '$months-month rolling average';
  }

  @override
  String get settingsMonthlyExpenseSubtitleOverride => 'Manual override set';

  @override
  String get settingsMonthlyExpenseHint =>
      'Your FIRE projection needs a monthly-expense figure. By default we average your past spending over a rolling window; flip on the manual override if you\'d rather hand-pick a number.';

  @override
  String get settingsMonthlyExpenseWindowLabel => 'Rolling window';

  @override
  String get settingsMonthlyExpenseWindowSubtitle =>
      'Months of history averaged into the auto-derived expense.';

  @override
  String settingsMonthlyExpenseWindowValue(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String get settingsMonthlyExpenseOverrideLabel => 'Manual override';

  @override
  String get settingsMonthlyExpenseOverrideSubtitle =>
      'Bypass the auto-derivation. Leave blank to use the rolling average.';

  @override
  String get settingsMonthlyExpenseOverrideHint => 'Leave blank for auto';

  @override
  String get settingsMonthlyExpenseResetDefaults => 'Reset to defaults';

  @override
  String get tradeEntryAppBarTitle => 'Record trade';

  @override
  String get tradeEntrySuccess => 'Trade recorded';

  @override
  String tradeEntryFailure(String error) {
    return 'Couldn\'t record trade: $error';
  }

  @override
  String get tradeEntryQuantityLabel => 'Quantity';

  @override
  String get tradeEntryPriceLabel => 'Price';

  @override
  String get tradeEntryPriceHelper => 'Leave blank to fetch from market data';

  @override
  String get tradeEntryDateLabel => 'Trade date & time';

  @override
  String get tradeEntryFeeLabel => 'Fee';

  @override
  String get tradeEntryTaxLabel => 'Tax';

  @override
  String get tradeEntryCashAccountLabel => 'Cash account';

  @override
  String tradeEntryCatalogLoadError(String error) {
    return 'Couldn\'t load catalog: $error';
  }

  @override
  String get tradeEntryDecimalScaleHintGeneric =>
      'Up to 8 decimals for stocks/ETFs, 18 for crypto';

  @override
  String tradeEntryDecimalScaleHint(int scale) {
    return 'Up to $scale decimal places';
  }

  @override
  String get tradeTypeBuy => 'Buy';

  @override
  String get tradeTypeSell => 'Sell';

  @override
  String get tradeTypeTransferIn => 'Transfer in';

  @override
  String get tradeTypeTransferOut => 'Transfer out';

  @override
  String get tradeTypeValuationAdjust => 'Valuation adjust';

  @override
  String get tradeTypeDividend => 'Dividend';

  @override
  String get tradeTypeReinvest => 'Reinvest';

  @override
  String get tradeTypeInterest => 'Interest';

  @override
  String get tradeTypeDeposit => 'Deposit';

  @override
  String get tradeTypeWithdraw => 'Withdraw';

  @override
  String get tradeTypeFee => 'Fee';

  @override
  String get tradeTypeTax => 'Tax';

  @override
  String get tradeTypeSplit => 'Split';

  @override
  String get tradeTypeLiabilityPayment => 'Loan payment';

  @override
  String get tradeTypeExpense => 'Expense';

  @override
  String get expensesReportTooltip => 'Monthly report';

  @override
  String get expenseFormCreateTitle => 'New expense';

  @override
  String get expenseFormEditTitle => 'Edit expense';

  @override
  String get expenseFormDeleteTooltip => 'Delete';

  @override
  String get expenseFormAmountLabel => 'Amount';

  @override
  String get expenseFormAmountInvalid => 'Amount must be greater than 0';

  @override
  String get expenseFormCategoryAccountRequired =>
      'Pick a category, account, and currency';

  @override
  String get expenseFormCategoriesLoading =>
      'Setting up default categories, please wait…';

  @override
  String expenseFormCategoriesLoadError(String error) {
    return 'Couldn\'t load categories: $error';
  }

  @override
  String get expenseFormAccountLabel => 'Account';

  @override
  String expenseFormAccountsLoadError(String error) {
    return 'Couldn\'t load accounts: $error';
  }

  @override
  String get expenseFormDateLabel => 'Date & time';

  @override
  String get expenseFormDeleteDialogTitle => 'Delete expense';

  @override
  String get expenseFormDeleteDialogBody =>
      'Delete this expense? This change syncs to your other devices.';

  @override
  String get expenseFormNoAccountsTitle => 'Create an account first';

  @override
  String get expenseFormNoAccountsBody =>
      'Expenses need a funding account. Create one under Accounts, then come back here.';

  @override
  String get expenseFormNoAccountsCta => 'Create account';

  @override
  String get expenseHistorySectionTitle => 'Change history';

  @override
  String get expenseHistoryEmpty => 'No changes recorded yet.';

  @override
  String expenseHistoryLoadError(String error) {
    return 'Couldn\'t load history: $error';
  }

  @override
  String get expenseHistoryEventCreated => 'Created';

  @override
  String get expenseHistoryEventChanged => 'Updated';

  @override
  String get expenseHistoryEventDeleted => 'Deleted';

  @override
  String get expenseHistoryEventRestored => 'Restored';

  @override
  String get expenseHistoryCreatedBody => 'Expense recorded.';

  @override
  String get expenseHistoryDeletedBody => 'Expense deleted.';

  @override
  String get expenseHistoryRestoredBody => 'Expense restored.';

  @override
  String get expenseHistoryFieldAmount => 'Amount';

  @override
  String get expenseHistoryFieldCurrency => 'Currency';

  @override
  String get expenseHistoryFieldAccount => 'Account';

  @override
  String get expenseHistoryFieldCategory => 'Category';

  @override
  String get expenseHistoryFieldDate => 'Date';

  @override
  String get expenseHistoryFieldNote => 'Note';

  @override
  String get expenseHistoryFieldTags => 'Tags';

  @override
  String get expenseHistoryEmptyValue => '—';

  @override
  String get expenseHistoryUnknownReference => '(unknown)';

  @override
  String expenseHistoryReasonLabel(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get aiChatAppBarTitle => 'AI assistant';

  @override
  String get aiChatHistoryTooltip => 'Conversation history';

  @override
  String get aiChatNewSessionTooltip => 'New conversation';

  @override
  String get aiChatLoginRequired => 'Sign in to use the AI assistant.';

  @override
  String get aiChatEmptyTitle => 'Your Life OS assistant';

  @override
  String get aiChatEmptyBody =>
      'Ask across finance, knowledge, health, and plans. Answers are grounded in local data and enabled domain tools; when key fields are missing, the assistant asks before assuming.';

  @override
  String get aiChatEmptySuggestion1 => 'What needs my attention right now?';

  @override
  String get aiChatEmptySuggestion2 =>
      'Summarize recent finance, knowledge, and health signals.';

  @override
  String get aiChatEmptySuggestion3 =>
      'What risks show up in my plans and reviews?';

  @override
  String get aiChatEmptySuggestion4 =>
      'What is the highest-value next step right now?';

  @override
  String get aiChatEmptySuggestionsHeader => 'Try these';

  @override
  String get aiChatEmptyDynamicNetWorth =>
      'Explain this month\'s net worth change';

  @override
  String aiChatEmptyDynamicAnomaly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Look at the $count flagged expenses',
      one: 'Look at the flagged expense',
    );
    return '$_temp0';
  }

  @override
  String aiChatEmptyDynamicMaturity(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deposits mature in ${days}d — what should I do?',
      one: '1 deposit matures in ${days}d — what should I do?',
    );
    return '$_temp0';
  }

  @override
  String get aiChatBootstrappingLabel => 'Preparing conversation…';

  @override
  String get aiIntentDefaultTimeframe => 'the last 30 days';

  @override
  String get aiIntentCurrentObject => 'the current object';

  @override
  String aiIntentFallbackPrompt(Object objectLabel) {
    return 'Please analyze $objectLabel.';
  }

  @override
  String get aiIntentExplainChangeLabel => 'Why it changed';

  @override
  String aiIntentExplainChangePrompt(Object objectLabel, Object timeframe) {
    return 'Explain why $objectLabel changed during $timeframe, and call out the relevant trends.';
  }

  @override
  String get aiIntentSummarizeAccountLabel => 'Account overview';

  @override
  String aiIntentSummarizeAccountPrompt(Object objectLabel, Object timeframe) {
    return 'Summarize account $objectLabel during $timeframe in concise bullets.';
  }

  @override
  String get aiIntentStressTestPlanLabel => 'Improve resilience';

  @override
  String aiIntentStressTestPlanPrompt(Object objectLabel) {
    return 'Evaluate how resilient $objectLabel is under adverse conditions, then give 2–3 concrete improvements.';
  }

  @override
  String get aiIntentComparePeriodLabel => 'Compare';

  @override
  String aiIntentComparePeriodPrompt(Object objectLabel) {
    return 'Compare $objectLabel across two periods and explain the drivers.';
  }

  @override
  String get aiIntentExplainInsightLabel => 'Expand';

  @override
  String aiIntentExplainInsightPrompt(Object objectLabel) {
    return 'Explain this insight ($objectLabel) in detail, including trigger, severity, and possible actions.';
  }

  @override
  String get aiIntentExplainChartLabel => 'Ask about chart';

  @override
  String aiIntentExplainChartPrompt(Object objectLabel, Object timeframe) {
    return 'Explain the key changes in this chart ($objectLabel) during $timeframe, including likely drivers.';
  }

  @override
  String get aiIntentTransactionsExplainSelectionLabel => 'Interpret';

  @override
  String aiIntentTransactionsExplainSelectionPrompt(Object objectLabel) {
    return 'Interpret these selected transactions ($objectLabel); identify common patterns, anomalies, and possible categorization.';
  }

  @override
  String get aiIntentExplainFireStateLabel => 'Explain FIRE state';

  @override
  String aiIntentExplainFireStatePrompt(Object objectLabel) {
    return 'Use get_fire_state to explain the current safety level, withdrawal rate, cash-bucket coverage, and FIRE ETA for $objectLabel; call out the one or two suggested_actions that matter most.';
  }

  @override
  String get aiIntentReviewCashBucketLabel => 'Check cash bucket';

  @override
  String aiIntentReviewCashBucketPrompt(Object objectLabel) {
    return 'Use get_fire_buckets to check current cash-bucket coverage. If it is below the target for $objectLabel, give the refill amount and prepare a propose_fire_plan_update or propose_fire_bucket_rule suggestion.';
  }

  @override
  String get aiIntentSimulateFireChangeLabel => 'Simulate';

  @override
  String aiIntentSimulateFireChangePrompt(Object objectLabel) {
    return 'Use simulate_fire_plan to model how changes to $objectLabel affect FIRE status, including expenses, balance, SWR, and cash-bucket months. Make clear this is a simulation and does not write to the plan.';
  }

  @override
  String get aiIntentExplainStressTestLabel => 'Explain stress test';

  @override
  String aiIntentExplainStressTestPrompt(Object objectLabel) {
    return 'Use get_fire_stress_tests to explain how market drawdown, higher expenses, one-off shocks, FX shocks, and cash-bucket depletion affect $objectLabel. Emphasize that this is a resilience check, not a forecast.';
  }

  @override
  String get aiIntentSuggestFireActionsLabel => 'Next steps';

  @override
  String get aiIntentSuggestFireActionsPrompt =>
      'Use get_fire_state suggested_actions to give the three highest-value next steps. If a plan change is involved, use propose_fire_plan_update so I can confirm.';

  @override
  String get aiChatSessionsHeader => 'Conversations';

  @override
  String get aiChatSessionsEmpty =>
      'Tap the + button to start your first conversation.';

  @override
  String get aiChatSessionMoreTooltip => 'More';

  @override
  String get aiChatSessionRenameAction => 'Rename';

  @override
  String get aiChatSessionRenameTitle => 'Rename';

  @override
  String get aiChatSessionTitleLabel => 'Title';

  @override
  String get aiChatSessionDeleteTitle => 'Delete conversation?';

  @override
  String aiChatSessionDeleteBody(String title) {
    return 'All messages in \"$title\" will be deleted.';
  }

  @override
  String get aiChatRelativeJustNow => 'just now';

  @override
  String aiChatRelativeMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String aiChatRelativeHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String aiChatRelativeDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get aiChatComposerHintIdle =>
      'Ask NaviWealth about finance, knowledge, health, or plans';

  @override
  String get aiChatComposerHintStreaming => 'Generating answer…';

  @override
  String get aiChatComposerSendTooltip => 'Send (⌘/Ctrl + Enter)';

  @override
  String get aiChatComposerStopTooltip => 'Stop generating';

  @override
  String get aiChatThinking => 'Thinking…';

  @override
  String aiChatRunningTool(String tool) {
    return 'Running $tool';
  }

  @override
  String get aiChatJumpToLatestTooltip => 'Jump to latest';

  @override
  String get aiChatMessageCopy => 'Copy';

  @override
  String get aiChatMessageCopied => 'Copied to clipboard';

  @override
  String get aiChatLinkConfirmTitle => 'Open link?';

  @override
  String get aiChatLinkConfirmBody =>
      'Confirm the destination — AI replies are untrusted and may contain unexpected URLs.';

  @override
  String get aiChatLinkOpen => 'Open';

  @override
  String get aiChatLinkOpenFailed => 'Could not open the link.';

  @override
  String get aiChatMessageRegenerate => 'Regenerate';

  @override
  String get aiChatSemanticsUserMessage => 'You said:';

  @override
  String get aiChatSemanticsAssistantMessage => 'Assistant reply';

  @override
  String get aiChatSemanticsAssistantError => 'Assistant reply failed';

  @override
  String get aiChatSemanticsSystemNotice => 'System notice:';

  @override
  String get aiChatToolDebugTooltip => 'View raw tool input/output';

  @override
  String get aiChatTransparencyOpenDetail => 'View full transparency trace';

  @override
  String get aiChatProfileChipTooltip => 'Switch model profile';

  @override
  String get aiChatEditUserMessage => 'Edit';

  @override
  String get aiChatEditUserMessageTitle => 'Edit and resend';

  @override
  String get aiChatEditUserMessageWarning =>
      'Saving discards the existing reply and any later turns, then re-runs your edited prompt.';

  @override
  String get aiChatEditUserMessageSubmit => 'Save and resend';

  @override
  String get aiChatProposalEditMoreFields => 'More fields';

  @override
  String get aiChatProposalEditStandardFields => 'Standard fields';

  @override
  String get aiChatSessionsSearchHint => 'Search conversations…';

  @override
  String aiChatSessionsSearchEmpty(String query) {
    return 'No conversations match \"$query\"';
  }

  @override
  String get aiChatSessionsGroupToday => 'Today';

  @override
  String get aiChatSessionsGroupYesterday => 'Yesterday';

  @override
  String get aiChatSessionsGroupThisWeek => 'This week';

  @override
  String get aiChatSessionsGroupThisMonth => 'This month';

  @override
  String get aiChatSessionsGroupOlder => 'Older';

  @override
  String get aiChatTruncatedMaxTokens =>
      'Reply was cut off — output length limit reached';

  @override
  String get aiChatTruncatedToolBudget =>
      'Stopped — tool-call budget exhausted';

  @override
  String get aiChatTruncatedRefusal => 'The model declined to answer';

  @override
  String get aiChatTruncatedNetwork =>
      'Connection dropped before the reply finished';

  @override
  String get aiChatTruncatedUnknown => 'Reply ended unexpectedly';

  @override
  String get aiChatTruncatedContinue => 'Continue';

  @override
  String get aiChatTruncatedContinuePrompt => 'Please continue.';

  @override
  String get aiChatProposalKindTrade => 'Trade';

  @override
  String get aiChatProposalKindExpense => 'Expense';

  @override
  String get aiChatProposalKindLiabilityPayment => 'Repayment';

  @override
  String get aiChatProposalKindAccountCreate => 'New account';

  @override
  String get aiChatProposalKindAssetValuation => 'Valuation update';

  @override
  String get aiChatProposalKindFirePlanUpdate => 'FIRE plan update';

  @override
  String get aiChatProposalKindFireBucketRule => 'FIRE bucket rule';

  @override
  String get aiChatProposalKindUnknown => 'Unknown';

  @override
  String aiChatProposalPendingHeader(String kind) {
    return 'Awaiting confirmation · $kind';
  }

  @override
  String aiChatProposalNeedsClarificationHeader(String kind) {
    return 'Needs clarification · $kind';
  }

  @override
  String get aiChatProposalCandidatesHeading => 'Options:';

  @override
  String aiChatProposalSummaryEdited(String summary) {
    return '$summary (edited)';
  }

  @override
  String get aiChatProposalConfirm => 'Confirm';

  @override
  String get aiChatProposalApplying => 'Recording…';

  @override
  String get aiChatProposalEdit => 'Edit';

  @override
  String aiChatProposalEditKindTitle(String kind) {
    return 'Edit $kind';
  }

  @override
  String get aiChatProposalSaveEdits => 'Save changes';

  @override
  String aiChatProposalFailure(String error) {
    return 'Failed: $error';
  }

  @override
  String aiChatProposalUndoFailure(String error) {
    return 'Undo failed: $error';
  }

  @override
  String aiChatProposalAppliedFallback(String summary) {
    return 'Recorded $summary';
  }

  @override
  String aiChatProposalUndoneLabel(String summary) {
    return 'Undid $summary';
  }

  @override
  String aiChatProposalCancelledLabel(String summary) {
    return 'Cancelled: $summary';
  }

  @override
  String aiChatProposalUndoCountdown(int seconds) {
    return 'Undo (${seconds}s)';
  }

  @override
  String aiChatProposalBatchPending(int count) {
    return '$count items awaiting confirmation in this turn';
  }

  @override
  String get aiChatProposalBatchConfirmAll => 'Confirm all';

  @override
  String aiChatProposalBatchResultAllOk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Applied $count items',
      one: 'Applied 1 item',
    );
    return '$_temp0';
  }

  @override
  String aiChatProposalBatchResultMixed(int applied, int failed) {
    return 'Applied $applied · $failed failed';
  }

  @override
  String aiChatProposalBatchResultAllFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count items failed',
      one: 'Failed to apply',
    );
    return '$_temp0';
  }

  @override
  String aiChatProposalConfirmTokenWarning(String token) {
    return 'High-risk action. Type \"$token\" to enable Confirm.';
  }

  @override
  String aiChatProposalConfirmTokenPending(String token) {
    return 'Confirm is disabled until you type \"$token\".';
  }

  @override
  String get aiChatFieldQuantity => 'Quantity';

  @override
  String get aiChatFieldPrice => 'Price (leave blank to backfill from market)';

  @override
  String get aiChatFieldFee => 'Fee';

  @override
  String get aiChatFieldTax => 'Tax';

  @override
  String get aiChatFieldNote => 'Note';

  @override
  String get aiChatFieldAmount => 'Amount';

  @override
  String get aiChatFieldDate => 'Date (RFC3339)';

  @override
  String get aiChatFieldDateHint => '2026-04-30T12:00:00Z';

  @override
  String get aiChatFieldAccountName => 'Account name';

  @override
  String get aiChatFieldInstitution => 'Institution (optional)';

  @override
  String get aiChatFieldNewValuation => 'New valuation';

  @override
  String get aiChatRowOperation => 'Operation';

  @override
  String get aiChatRowAsset => 'Asset';

  @override
  String get aiChatRowAccount => 'Account';

  @override
  String get aiChatRowQuantity => 'Quantity';

  @override
  String get aiChatRowPrice => 'Price';

  @override
  String get aiChatRowFee => 'Fee';

  @override
  String get aiChatRowDate => 'Date';

  @override
  String get aiChatRowNote => 'Note';

  @override
  String get aiChatRowAmount => 'Amount';

  @override
  String get aiChatRowCategory => 'Category';

  @override
  String get aiChatRowLiability => 'Liability';

  @override
  String get aiChatRowRepayAccount => 'Repayment account';

  @override
  String get aiChatRowName => 'Name';

  @override
  String get aiChatRowType => 'Type';

  @override
  String get aiChatRowCurrency => 'Currency';

  @override
  String get aiChatRowInstitution => 'Institution';

  @override
  String get aiChatRowNewValue => 'New valuation';

  @override
  String get aiChatToolGetHoldings => 'Query holdings';

  @override
  String get aiChatToolComputeXirr => 'Compute XIRR';

  @override
  String get aiChatToolComputeNetWorth => 'Compute net worth';

  @override
  String get aiChatToolGetIndustryBreakdown => 'Industry breakdown';

  @override
  String get aiChatToolGetGeoBreakdown => 'Region breakdown';

  @override
  String get aiChatToolGetMarketCapBreakdown => 'Market-cap breakdown';

  @override
  String get aiChatToolGetRiskAlerts => 'Risk alerts';

  @override
  String get aiChatToolFallback => 'Tool';

  @override
  String get aiChatToolInputLabel => 'Input';

  @override
  String get aiChatToolOutputLabel => 'Output';

  @override
  String aiChatToolJumpAsset(String id) {
    return 'Asset $id';
  }

  @override
  String aiChatToolJumpAccount(String id) {
    return 'Account $id';
  }

  @override
  String aiChatToolJumpLiability(String id) {
    return 'Liability $id';
  }

  @override
  String aiChatToolJumpJournalEntry(String id) {
    return 'Entry $id';
  }

  @override
  String aiChatToolJumpTradeJournal(String id) {
    return 'Trade $id';
  }

  @override
  String get aiChatToolEvidenceLabel => 'Evidence';

  @override
  String get aiChatToolShowRawJson => 'View raw JSON';

  @override
  String get aiChatToolShowCompactView => 'Back to compact view';

  @override
  String get aiFloatingPillLabel => 'Ask AI';

  @override
  String get aiChatSheetTitle => 'AI assistant';

  @override
  String get aiChatSheetEmpty => 'Ask anything about your Life OS.';

  @override
  String get aiChatSheetExpandTooltip => 'Expand to full screen';

  @override
  String get aiChatSheetNewTooltip => 'New conversation';

  @override
  String get chartEmptyDefault => 'No data yet';

  @override
  String get formAmountFieldLabelDefault => 'Amount';

  @override
  String get formAmountFieldRequired => 'Enter an amount';

  @override
  String get formAmountFieldInvalid => 'Invalid amount format';

  @override
  String get formAmountFieldNegativeNotAllowed => 'Amount cannot be negative';

  @override
  String get formNoteFieldLabelDefault => 'Notes';

  @override
  String get formDateFieldClearTooltip => 'Clear';

  @override
  String get formDateFieldRequired => 'Pick a date';

  @override
  String get formAccountPickerLabelDefault => 'Account';

  @override
  String get formAccountPickerRequired => 'Pick an account';

  @override
  String get formCurrencyPickerLabelDefault => 'Currency';

  @override
  String get formCurrencyPickerRequired => 'Pick a currency';

  @override
  String currencyOptionLabel(String code, String name) {
    return '$code · $name';
  }

  @override
  String get currencyNameCNY => 'Chinese Yuan';

  @override
  String get currencyNameUSD => 'US Dollar';

  @override
  String get currencyNameHKD => 'Hong Kong Dollar';

  @override
  String get currencyNameEUR => 'Euro';

  @override
  String get currencyNameJPY => 'Japanese Yen';

  @override
  String get currencyNameGBP => 'British Pound';

  @override
  String get currencyNameSGD => 'Singapore Dollar';

  @override
  String get currencyNameAUD => 'Australian Dollar';

  @override
  String get currencyNameCAD => 'Canadian Dollar';

  @override
  String get currencyNameTWD => 'New Taiwan Dollar';

  @override
  String get expenseCategoryPickerLabelDefault => 'Category';

  @override
  String get expenseCategoryPickerRequired => 'Pick a category';

  @override
  String get systemAccountIncome => 'Income';

  @override
  String get systemAccountIncomeSalary => 'Salary';

  @override
  String get systemAccountIncomeDividend => 'Dividend';

  @override
  String get systemAccountIncomeInterest => 'Interest';

  @override
  String get systemAccountIncomeCapitalGains => 'Capital Gains';

  @override
  String get systemAccountIncomeOther => 'Other Income';

  @override
  String get systemAccountExpense => 'Expenses';

  @override
  String get systemAccountExpenseDining => 'Dining';

  @override
  String get systemAccountExpenseGroceries => 'Groceries';

  @override
  String get systemAccountExpenseCoffee => 'Coffee';

  @override
  String get systemAccountExpenseTransport => 'Transport';

  @override
  String get systemAccountExpenseRideHailing => 'Ride Hailing';

  @override
  String get systemAccountExpenseHousing => 'Housing';

  @override
  String get systemAccountExpenseUtilities => 'Utilities';

  @override
  String get systemAccountExpenseHousehold => 'Household';

  @override
  String get systemAccountExpenseShopping => 'Shopping';

  @override
  String get systemAccountExpenseSubscriptions => 'Subscriptions';

  @override
  String get systemAccountExpenseEntertainment => 'Entertainment';

  @override
  String get systemAccountExpenseMedical => 'Medical';

  @override
  String get systemAccountExpenseFitness => 'Fitness';

  @override
  String get systemAccountExpenseEducation => 'Education';

  @override
  String get systemAccountExpenseTravel => 'Travel';

  @override
  String get systemAccountExpenseCommunication => 'Communication';

  @override
  String get systemAccountExpenseGift => 'Gift';

  @override
  String get systemAccountExpenseFamilySupport => 'Family Support';

  @override
  String get systemAccountExpensePets => 'Pets';

  @override
  String get systemAccountExpenseTrading => 'Trading';

  @override
  String get systemAccountExpenseTradingFee => 'Trading Fee';

  @override
  String get systemAccountExpenseTradingTax => 'Trading Tax';

  @override
  String get systemAccountExpenseTradingInterest => 'Trading Interest';

  @override
  String get systemAccountExpenseTax => 'Tax';

  @override
  String get systemAccountExpenseTaxWithholding => 'Withholding Tax';

  @override
  String get systemAccountExpenseOther => 'Other Expense';

  @override
  String get systemAccountEquity => 'Equity';

  @override
  String get systemAccountEquityOpeningBalance => 'Opening Balance';

  @override
  String get systemAccountEquitySplits => 'Stock Splits';

  @override
  String get systemAccountEquityAdjustments => 'Adjustments';

  @override
  String get physicalAssetValuationProjected => 'Projected valuation';

  @override
  String get physicalAssetValuationHistorical => 'Historical valuation';

  @override
  String get physicalAssetValuationTrendSemanticLabel => 'Valuation trend';

  @override
  String get accountsDetailEmpty =>
      'Select an account on the left to edit its details.';

  @override
  String get accountsCreateAction => 'New account';

  @override
  String accountsLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get accountsEmptyHint =>
      'No accounts yet. Tap the bottom-right button to add one, then come back to record assets.';

  @override
  String get accountCategoryCash => 'Cash';

  @override
  String get accountCategoryBank => 'Bank';

  @override
  String get accountCategoryBroker => 'Brokerage';

  @override
  String get accountCategoryCrypto => 'Crypto wallet';

  @override
  String get accountCategoryCredit => 'Credit';

  @override
  String get accountCategoryLoan => 'Loan';

  @override
  String get accountCategoryAsset => 'Other asset';

  @override
  String get accountCategoryLiability => 'Other liability';

  @override
  String get accountCategoryCashHint => 'Wallets, e-wallets, physical bills';

  @override
  String get accountCategoryBankHint => 'Checking, savings, deposits';

  @override
  String get accountCategoryBrokerHint => 'Stocks, ETFs, mutual funds';

  @override
  String get accountCategoryCryptoHint => 'On-chain wallets, exchanges';

  @override
  String get accountCategoryCreditHint => 'Credit cards, revolving credit';

  @override
  String get accountCategoryLoanHint => 'Mortgage, car loan, student loan';

  @override
  String get accountCategoryAssetHint => 'Real estate, vehicles, collectibles';

  @override
  String get accountCategoryLiabilityHint =>
      'Anything you owe that isn\'t credit or loan';

  @override
  String get accountSideAsset => 'Asset';

  @override
  String get accountSideLiability => 'Liability';

  @override
  String get accountSideIncome => 'Income';

  @override
  String get accountSideExpense => 'Expense';

  @override
  String get accountSideEquity => 'Equity';

  @override
  String get accountFormCreateTitle => 'New account';

  @override
  String get accountFormEditTitle => 'Edit account';

  @override
  String get accountFormDeleteTooltip => 'Delete';

  @override
  String get accountFormDeleteTitle => 'Delete account';

  @override
  String accountFormDeleteContent(String name) {
    return 'Delete “$name”? This sync to other devices.';
  }

  @override
  String get accountFormCancelAction => 'Cancel';

  @override
  String get accountFormDeleteAction => 'Delete';

  @override
  String get accountFormTypeLabel => 'Account type';

  @override
  String get accountFormCategoryLabel => 'Accounting category';

  @override
  String get accountFormCategoryHelper =>
      'Where this account sits in the accounting identity. Defaults from the account type — change it if the suggestion doesn\'t match.';

  @override
  String get accountFormNameLabel => 'Account name';

  @override
  String get accountFormNameRequired => 'Enter the account name';

  @override
  String get accountFormInstitutionLabel => 'Institution';

  @override
  String get accountFormInstitutionHelper =>
      'Bank / brokerage / platform (optional)';

  @override
  String get accountFormAccountNumberLabel =>
      'Account number / last digits (optional)';

  @override
  String get accountFormArchivedTitle => 'Archived';

  @override
  String get accountFormArchivedSubtitle =>
      'Archived accounts are hidden from the main list.';

  @override
  String get accountFormSaving => 'Saving…';

  @override
  String get accountFormSave => 'Save';

  @override
  String get cashFormCreateTitle => 'Record cash balance';

  @override
  String get cashFormEditTitle => 'Edit cash balance';

  @override
  String get cashFormDeleteTooltip => 'Delete';

  @override
  String cashFormLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get cashFormNeedAccountHint =>
      'Please create a bank / cash account first.';

  @override
  String get cashFormCreateAccountAction => 'New account';

  @override
  String get cashFormAccountLockedHint =>
      'This cash balance is linked to the account above. To move it, delete this balance and record it under another account.';

  @override
  String get cashFormMissingAccount => 'Linked account unavailable';

  @override
  String get cashFormBalanceLabel => 'Balance';

  @override
  String get cashFormNicknameLabel => 'Nickname (optional)';

  @override
  String get cashFormNicknameHelper => 'e.g. CMB HKD demand, Yu’e Bao';

  @override
  String get cashFormSaving => 'Saving…';

  @override
  String get cashFormSave => 'Save';

  @override
  String get manualAssetDeleteTitle => 'Delete asset';

  @override
  String get manualAssetDeleteContent => 'Delete this asset record?';

  @override
  String get manualAssetDeleteCancel => 'Cancel';

  @override
  String get manualAssetDeleteConfirm => 'Delete';

  @override
  String get activityFeedTab => 'Activity';

  @override
  String get activityFeedEmpty =>
      'No activity yet — record a transfer, expense, or trade and it will appear here.';

  @override
  String get tradeEntryCashOverdrawTitle => 'Cash balance will go negative';

  @override
  String tradeEntryCashOverdrawMessage(Object amount) {
    return 'After this purchase, your cash account balance will be $amount. Do you want to proceed?';
  }

  @override
  String get tradeEntryCashOverdrawProceed => 'Proceed';

  @override
  String get activityFeedToday => 'Today';

  @override
  String get activityFeedYesterday => 'Yesterday';

  @override
  String get activityFeedThisWeek => 'This week';

  @override
  String get activityFeedEarlier => 'Earlier';

  @override
  String get accountsTransferAction => 'Transfer';

  @override
  String get accountsJournalAction => 'Journal';

  @override
  String get expenseReportTitle => 'Expense Report';

  @override
  String get planFireTitle => 'FIRE';

  @override
  String get planFireSubtitle => 'Financial independence calculator';

  @override
  String get planAnalyticsTitle => 'Analytics';

  @override
  String get planAnalyticsSubtitle => 'Portfolio allocation analysis';

  @override
  String get planRebalanceTitle => 'Rebalance';

  @override
  String get planRebalanceSubtitle => 'Portfolio drift & rebalancing';

  @override
  String get planSummaryLoadError => 'Needs attention';

  @override
  String get planSummaryConfigureGoal => 'Set a target';

  @override
  String planSummaryProgress(String value) {
    return 'Progress $value';
  }

  @override
  String planSummaryEta(String value) {
    return 'ETA $value';
  }

  @override
  String get planSummaryNoRiskAlerts => 'No concentration alerts';

  @override
  String planSummaryRiskAlerts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alerts',
      one: '1 alert',
    );
    return '$_temp0';
  }

  @override
  String planSummaryCriticalAlerts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count critical',
      one: '1 critical',
    );
    return '$_temp0';
  }

  @override
  String get planSummaryNoPortfolio => 'No portfolio data';

  @override
  String get planSummaryBalanced => 'Balanced';

  @override
  String planSummaryDrift(String value) {
    return 'Drift $value';
  }

  @override
  String planSummaryTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0';
  }

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsNumbersAndMoneySection => 'Numbers & Money';

  @override
  String get settingsPlanningSection => 'Planning';

  @override
  String get settingsAiSection => 'AI';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsDataSection => 'Data';

  @override
  String get settingsDomainsSection => 'LifeOS Domains';

  @override
  String get settingsDomainsTitle => 'Domain management';

  @override
  String get settingsDomainsSubtitle =>
      'FinanceOS / HealthOS / KnowledgeOS toggles and settings';

  @override
  String get settingsAdvancedSection => 'Advanced';

  @override
  String get settingsAiModelsTitle => 'AI Models';

  @override
  String get settingsAiModelsSubtitle =>
      'Download and manage the local EmbeddingGemma model';

  @override
  String get settingsBadgeAuto => 'Auto';

  @override
  String get settingsBadgeCustom => 'Custom';

  @override
  String get settingsDataTitle => 'Backup & Restore';

  @override
  String get settingsDataSubtitle => 'Export or import encrypted data backups';

  @override
  String get settingsCrashReportingTitle => 'Crash reporting';

  @override
  String get settingsCrashReportingSubtitle =>
      'Send anonymous error reports to help fix bugs. Off by default.';

  @override
  String get settingsAiPrivacyTitle => 'AI privacy';

  @override
  String get settingsAiPrivacySubtitle =>
      'Pick what the AI can send to the cloud';

  @override
  String get aiPrivacyTitle => 'AI privacy';

  @override
  String get aiPrivacyIntro =>
      'Choose how much detail the AI can see when it leaves the device. You can change this at any time.';

  @override
  String get aiPrivacyModeAmountsAllowedLabel => 'Amounts allowed';

  @override
  String get aiPrivacyModeAmountsAllowedDescription =>
      'Send exact amounts and account context. Best answer quality.';

  @override
  String get aiPrivacyModeAmountsBucketedLabel => 'Amounts bucketed';

  @override
  String get aiPrivacyModeAmountsBucketedDescription =>
      'Round amounts to the nearest order of magnitude before sending. Cloud sees patterns but not exact numbers.';

  @override
  String get aiPrivacyModeAmountsLocalLabel => 'Amounts stay local';

  @override
  String get aiPrivacyModeAmountsLocalDescription =>
      'Only intent and category names leave the device. Cloud answers narrow to qualitative tips.';

  @override
  String get aiPrivacyMaskAccountsLabel => 'Mask account / institution names';

  @override
  String get aiPrivacyMaskAccountsDescription =>
      'Replace bank and broker names with anonymous IDs before they\'re sent.';

  @override
  String get aiPrivacyOnboardingTitle => 'Pick your AI privacy posture';

  @override
  String get aiPrivacyOnboardingBody =>
      'NaviWealth\'s AI is local-first. When it needs to use the cloud, this setting decides what it can send. You can change it later in Settings.';

  @override
  String get aiPrivacyOnboardingConfirm => 'Got it';

  @override
  String get aiTransparencyUndoSectionTitle => 'Pending AI changes';

  @override
  String get aiTransparencyUndoEmpty => 'No pending AI changes.';

  @override
  String get aiTransparencyUndoAction => 'Undo';

  @override
  String get settingsDeveloperSection => 'Developer';

  @override
  String get settingsLogsTitle => 'App Logs';

  @override
  String get settingsLogsSubtitle => 'View real-time diagnostic logs';

  @override
  String get settingsLogsCopiedToast => 'Logs copied';

  @override
  String get settingsPerfTitle => 'Performance';

  @override
  String get settingsPerfSubtitle => 'Inspect recent frame timing and jank';

  @override
  String get settingsPerfRecentFrames => 'Recent frames';

  @override
  String get settingsPerfJankFrames => 'Jank frames';

  @override
  String get settingsPerfFrameBudget => 'Frame budget';

  @override
  String get settingsPerfTimingTitle => 'Frame timing';

  @override
  String get settingsPerfTotalP50 => 'Total p50';

  @override
  String get settingsPerfTotalP95 => 'Total p95';

  @override
  String get settingsPerfBuildP95 => 'Build p95';

  @override
  String get settingsPerfRasterP95 => 'Raster p95';

  @override
  String get settingsDomainsIntro =>
      'Each domain is enabled independently. Turning one on activates its AI tools, Memory indexing, and navigation entry.';

  @override
  String get settingsDomainsFinanceSubtitle => 'Always enabled (seed domain)';

  @override
  String get settingsDomainsEnabledBadge => 'Enabled';

  @override
  String get settingsDomainsHealthEnabledSubtitle =>
      'Preview — AI tools and Memory indexing are enabled';

  @override
  String get settingsDomainsHealthDisabledSubtitle =>
      'Preview — turn on AI tools and Memory indexing';

  @override
  String get settingsDomainsHealthTodaySubtitle =>
      'View recovery, metrics, and the morning briefing';

  @override
  String get settingsDomainsKnowledgeEnabledSubtitle =>
      'Preview — Inbox, Library, Review, AI tools, and Memory indexing are enabled';

  @override
  String get settingsDomainsKnowledgeDisabledSubtitle =>
      'Preview — personal decisions and cognitive memory';

  @override
  String get settingsDomainsKnowledgeInboxSubtitle =>
      'Capture notes, write decisions, and review the library';

  @override
  String get settingsDomainsHealthPermissionDenied =>
      'Permission denied — try again in system Health settings';

  @override
  String get settingsDomainsHealthSyncRunning => 'Syncing…';

  @override
  String get settingsDomainsHealthSyncIdle =>
      'Import the last 30 days from the system health platform';

  @override
  String get settingsDomainsHealthSyncFailed => 'Last sync failed';

  @override
  String settingsDomainsHealthSyncSummary(
    int upserted,
    int unchanged,
    int total,
  ) {
    return 'Last sync: $upserted new / $unchanged unchanged · fetched $total items';
  }

  @override
  String get settingsDomainsHealthSyncTitle => 'Sync health data';

  @override
  String get settingsDomainsBriefingRunning => 'Generating morning briefing…';

  @override
  String settingsDomainsBriefingFailed(String error) {
    return 'Briefing failed: $error';
  }

  @override
  String get settingsDomainsBriefingIdle =>
      'Runs automatically each day; tap to generate and send now';

  @override
  String settingsDomainsBriefingCompleted(String summary) {
    return 'Last run: $summary';
  }

  @override
  String settingsDomainsBriefingSkipped(String summary) {
    return 'Last skipped: $summary';
  }

  @override
  String settingsDomainsBriefingRunFailed(String error) {
    return 'Last failed: $error';
  }

  @override
  String get settingsDomainsBriefingFallbackDone => 'Done';

  @override
  String get settingsDomainsBriefingFallbackNoSignals => 'No signals';

  @override
  String get settingsDomainsBriefingFallbackUnknown => 'Unknown error';

  @override
  String get settingsDomainsBriefingRunTitle => 'Generate morning briefing now';

  @override
  String get settingsDomainsBriefingTimeHelp => 'Morning briefing time';

  @override
  String get settingsDomainsBriefingTimeTitle => 'Briefing time';

  @override
  String settingsDomainsBriefingTimeSubtitle(String hour) {
    return 'Runs around $hour:00 each day (background scheduling may drift)';
  }

  @override
  String get settingsAiModelsCheckingRuntime =>
      'Checking the embedder path for next launch…';

  @override
  String settingsAiModelsRuntimeCheckFailed(String error) {
    return 'Embedder path check failed: $error';
  }

  @override
  String get settingsAiModelsRuntimeReady =>
      'Next launch will load Rust EmbeddingGemma';

  @override
  String get settingsAiModelsRuntimeStub =>
      'Next launch will still use the stub embedder';

  @override
  String get settingsAiModelsModelLabel => 'Model';

  @override
  String get settingsAiModelsModelMissing =>
      'Missing: EmbeddingGemma model dir';

  @override
  String get settingsAiModelsOrtMissing => 'Missing: ONNX Runtime dylib';

  @override
  String get settingsAiModelsNativeLibLabel => 'native lib';

  @override
  String get settingsAiModelsNativeLibPlatform =>
      'Loaded by the platform plugin';

  @override
  String get settingsAiModelsInstalledSource => 'Installed';

  @override
  String get settingsAiModelsMissingSource => 'Missing';

  @override
  String get settingsAiModelsHint =>
      'AI memory retrieval uses the lightweight stub by default. Download EmbeddingGemma and restart the app to enable local multilingual sentence vectors (768-d). Files stay on this device and are never uploaded. ONNX Runtime is bundled with the app.';

  @override
  String get settingsAiModelsFootnote =>
      'After download, restart the app so Memory Runtime uses the new embedder. Existing memory records will be re-indexed with the new model in the next indexer cycle; original typed records stay unchanged.';

  @override
  String settingsAiModelsStateLoadFailed(String error) {
    return 'Failed to load state: $error';
  }

  @override
  String get settingsAiModelsStatusInstalled => 'Installed';

  @override
  String get settingsAiModelsStatusDownloading => 'Downloading…';

  @override
  String get settingsAiModelsStatusFailed => 'Failed';

  @override
  String get settingsAiModelsStatusNotInstalled => 'Not installed';

  @override
  String get settingsAiModelsCancel => 'Cancel';

  @override
  String get settingsAiModelsDelete => 'Delete';

  @override
  String get settingsAiModelsRedownload => 'Redownload';

  @override
  String get settingsAiModelsDownload => 'Download';

  @override
  String get settingsAiModelsDeleteTitle => 'Delete model?';

  @override
  String get settingsAiModelsDeleteBody =>
      'After deletion, AI retrieval will fall back to the stub embedder. Redownloading requires network access again.';

  @override
  String get knowledgeAiSuggestionsTitle => 'AI suggestions';

  @override
  String knowledgeAiSuggestionsTitleWithCount(int count) {
    return 'AI suggestions ($count)';
  }

  @override
  String get knowledgeAiSuggestionsEmpty =>
      'No pending AI suggestions. New notes are triaged within 15 minutes.';

  @override
  String knowledgeLoadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String knowledgeNoteDeleted(String noteId) {
    return 'Note $noteId was deleted';
  }

  @override
  String get knowledgeUntitled => 'Untitled';

  @override
  String get knowledgeMarkdownEdit => 'Edit';

  @override
  String get knowledgeMarkdownPreview => 'Preview';

  @override
  String get knowledgeMarkdownPreviewEmpty =>
      'No preview yet. Switch back to edit mode to enter content.';

  @override
  String get knowledgeDecisionNotFound =>
      'Decision does not exist or was deleted';

  @override
  String get knowledgeObjectNotFound => 'Item does not exist or was deleted';

  @override
  String get knowledgeDeletedToast => 'Deleted';

  @override
  String get backupExportTitle => 'Export Backup';

  @override
  String get backupExportSubtitle =>
      'Create an encrypted backup of all your data';

  @override
  String get backupImportTitle => 'Import Backup';

  @override
  String get backupImportSubtitle => 'Restore data from a backup file';

  @override
  String get backupPassphraseLabel => 'Passphrase';

  @override
  String get backupPassphraseHint => 'Enter a passphrase to encrypt the backup';

  @override
  String get backupPassphraseRequired => 'Passphrase is required';

  @override
  String get backupConfirmRestoreTitle => 'Restore Backup';

  @override
  String get backupConfirmRestoreMessage =>
      'This will replace ALL local data with the contents of the backup. This cannot be undone. Continue?';

  @override
  String get backupConfirmRestoreAction => 'Restore';

  @override
  String get backupExportAction => 'Export';

  @override
  String get backupCancelAction => 'Cancel';

  @override
  String get backupExportProgress => 'Encrypting backup…';

  @override
  String get backupImportProgress => 'Restoring backup…';

  @override
  String get backupExportSuccess => 'Backup exported successfully';

  @override
  String backupImportSuccess(int count) {
    return 'Backup restored successfully. $count rows imported.';
  }

  @override
  String get backupWrongPassphrase => 'Wrong passphrase or corrupt backup file';

  @override
  String get backupSchemaTooNew =>
      'This backup was created with a newer version of NaviWealth. Please update the app first.';

  @override
  String get backupInvalidFile => 'Invalid backup file';

  @override
  String get backupFilePickerError => 'Could not read the selected file';

  @override
  String get backupRestorePassphraseHint => 'Enter the backup passphrase';

  @override
  String get logViewerClearTooltip => 'Clear';

  @override
  String activityFeedLoadError(String error) {
    return 'Failed to load feed: $error';
  }

  @override
  String get expenseFormLoadError =>
      'Couldn\'t load expense. Create a new entry instead.';

  @override
  String get accountsJournalTooltip => 'Journal';

  @override
  String get accountsTransferTooltip => 'New transfer';

  @override
  String get accountFormParentLabel => 'Parent account (optional)';

  @override
  String get accountFormParentHelper =>
      'Group this account under another in the tree.';

  @override
  String get accountFormMakeTopLevelTooltip => 'Make top-level';

  @override
  String get accountFormIconHeading => 'Icon';

  @override
  String get accountFormNoIconTooltip => 'No icon';

  @override
  String get accountFormColorHeading => 'Color';

  @override
  String get accountFormNoColorTooltip => 'No color';

  @override
  String get transferTitle => 'New transfer';

  @override
  String transferLoadError(String error) {
    return 'Failed to load accounts: $error';
  }

  @override
  String get transferFromLabel => 'From account';

  @override
  String get transferToLabel => 'To account';

  @override
  String get transferValidationRequired => 'Required';

  @override
  String get transferValidationDifferentAccount => 'Pick a different account';

  @override
  String get transferAmountLabel => 'Amount';

  @override
  String transferAmountWithCurrencyLabel(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String transferToAmountLabel(String currency) {
    return 'To amount ($currency)';
  }

  @override
  String get transferFxRateHelper =>
      'No FX rate on file — enter the converted amount.';

  @override
  String get transferFxRateEditHelper =>
      'Edit to override the auto-filled rate.';

  @override
  String get transferDateLabel => 'Date & time';

  @override
  String get transferPreviewTitle => 'Transfer';

  @override
  String get transferSubmitAction => 'Transfer';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return 'Rate: 1 $from = $rate $to';
  }

  @override
  String transferRejectedError(String message) {
    return 'Transfer rejected: $message';
  }

  @override
  String transferFailedError(String error) {
    return 'Transfer failed: $error';
  }

  @override
  String get transferRetryLabel => 'Retry';

  @override
  String get journalTitle => 'Journal';

  @override
  String journalLoadError(String error) {
    return 'Failed to load journal: $error';
  }

  @override
  String get journalEmptyHint =>
      'No journal entries yet — record a transfer, expense, or trade and it will land here.';

  @override
  String get entryKindTrade => 'Trade';

  @override
  String get entryKindTransfer => 'Transfer';

  @override
  String get entryKindIncome => 'Income';

  @override
  String get entryKindExpense => 'Expense';

  @override
  String get entryKindPayment => 'Payment';

  @override
  String get entryKindAdjustment => 'Adjustment';

  @override
  String get entryKindOpening => 'Opening';

  @override
  String get entryKindOther => 'Other';

  @override
  String get entryKindEntry => 'Entry';

  @override
  String entryKindSemanticLabel(String kind) {
    return 'Journal entry · $kind';
  }

  @override
  String get chatCancelled => 'Cancelled';

  @override
  String get chatNewSession => 'New conversation';

  @override
  String chatContextTruncated(int count) {
    return '$count earlier messages were folded to stay within the context limit.';
  }

  @override
  String get expenseReportAppBarTitle => 'Expense Report';

  @override
  String expenseReportLoadError(String error) {
    return 'Failed to load report: $error';
  }

  @override
  String get expenseReportRangeThisMonth => 'This month';

  @override
  String get expenseReportRangeLast3Months => 'Last 3 months';

  @override
  String get expenseReportRangeLast6Months => 'Last 6 months';

  @override
  String get expenseReportRangeLast12Months => 'Last 12 months';

  @override
  String get expenseReportRangeCustom => 'Custom';

  @override
  String get expenseReportTotalExpenses => 'Total expenses';

  @override
  String get expenseReportMonthlyAverage => 'Monthly avg';

  @override
  String get expenseReportEntryCount => 'Entries';

  @override
  String get expenseReportCategoryCount => 'Categories';

  @override
  String expenseReportSkippedFx(int count) {
    return '$count expenses excluded — missing FX rate.';
  }

  @override
  String expenseReportBaseCurrency(String currency, int months) {
    return 'Base currency $currency · monthly avg over $months months';
  }

  @override
  String get expenseReportCategoryShare => 'Category share';

  @override
  String get expenseReportUncategorized => 'Uncategorized';

  @override
  String get expenseReportNoExpenses => 'No expenses in this period.';

  @override
  String expenseReportMonthLabel(int month) {
    return '$month月';
  }

  @override
  String get expenseReportMonthlyTrend => 'Monthly trend';

  @override
  String get expenseReportSeriesExpenses => 'Expenses';

  @override
  String get expenseReportMonthlyTrendSemantic => 'Monthly expense trend';

  @override
  String get expenseReportCategoryDetail => 'Category detail';

  @override
  String expenseReportItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get expenseListSearchHint => 'Search by note';

  @override
  String get expenseListAllCategories => 'All categories';

  @override
  String get expenseListGroupMonth => 'Month';

  @override
  String get expenseListGroupWeek => 'Week';

  @override
  String expenseListTotal(String amount) {
    return 'Total $amount';
  }

  @override
  String get expenseListUncategorized => 'Uncategorized';

  @override
  String get expenseListEmptyFiltered => 'No matching expenses.';

  @override
  String get expenseListEmptyDefault =>
      'No expenses yet. Tap the + button to start tracking.';

  @override
  String expenseListMonthGroup(int year, int month) {
    return '$year 年 $month 月';
  }

  @override
  String expenseListWeekGroup(int year, int week) {
    return '$year 年第 $week 周';
  }

  @override
  String assetDetailLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get assetDetailNotFound => 'Asset not found or deleted';

  @override
  String get assetDetailUnsupportedType =>
      'This asset type does not support manual editing';

  @override
  String get assetDetailNoMetadataMatch => 'No matching metadata found';

  @override
  String get assetDetailMetadataSynced => 'Metadata synced';

  @override
  String get assetDetailMetadataUpToDate => 'Metadata is up to date';

  @override
  String get assetDetailNetworkUnavailable =>
      'Network unavailable — cannot sync metadata';

  @override
  String get assetDetailSyncMetadataTooltip => 'Sync metadata';

  @override
  String get assetDetailNewTradeLabel => 'New trade';

  @override
  String get assetDetailUnknown => 'Unknown';

  @override
  String assetDetailHoldingsLoadError(String error) {
    return 'Holdings load failed: $error';
  }

  @override
  String get assetDetailHoldingsTitle => 'Holdings';

  @override
  String get assetDetailCurrentQuantity => 'Current qty';

  @override
  String get assetDetailAverageCost => 'Avg cost';

  @override
  String get assetDetailCurrentMarketValue => 'Market value';

  @override
  String get assetDetailPriceUnavailable =>
      'Price unavailable — market value shows as zero';

  @override
  String assetDetailPnLLoadError(String error) {
    return 'P&L load failed: $error';
  }

  @override
  String get assetDetailPnLTitle => 'Profit & Loss';

  @override
  String get assetDetailUnrealizedPnL => 'Unrealized P&L';

  @override
  String assetDetailBaseCurrency(String currency) {
    return 'Base currency: $currency';
  }

  @override
  String get assetDetailTodayChange => 'Today';

  @override
  String get assetDetailQuoteStale => 'Quote stale';

  @override
  String get assetDetailQuoteUnavailable => 'Quote unavailable';

  @override
  String get assetDetailTrend30d => '30-day trend';

  @override
  String get assetDetailNoMarketLinked =>
      'This asset is not linked to a market — no trend to display';

  @override
  String assetDetailTrendLoadError(String error) {
    return 'Could not load quote: $error';
  }

  @override
  String get assetDetailSeriesClosePrice => 'Close';

  @override
  String get assetDetailSeriesCostBasis => 'Cost basis';

  @override
  String get assetDetailTrendSemanticLabel => '30-day close price trend';

  @override
  String get assetDetailStaleBadge => 'Stale';

  @override
  String get assetDetailCategoryShareSemantic => 'Category share';

  @override
  String get depositMaturityRequired => 'Term deposits require a maturity date';

  @override
  String get depositDeleteTitle => 'Delete deposit';

  @override
  String get depositDeleteBody => 'Delete this deposit record?';

  @override
  String get depositCreateTitle => 'Record deposit';

  @override
  String get depositEditTitle => 'Edit deposit';

  @override
  String get depositDeleteTooltip => 'Delete';

  @override
  String get depositTypeTerm => 'Term';

  @override
  String get depositTypeDemand => 'Demand';

  @override
  String get depositNameLabel => 'Name';

  @override
  String get depositNameHelper => 'e.g. CMB 1-year term, ICBC demand savings';

  @override
  String get depositNameRequired => 'Enter a name';

  @override
  String get depositPrincipalLabel => 'Principal';

  @override
  String get depositRateLabel => 'Annual rate (%)';

  @override
  String get depositRateHelper => 'e.g. 3.25 means 3.25%';

  @override
  String get depositRateRequired => 'Enter the interest rate';

  @override
  String get depositRateInvalid => 'Invalid rate format';

  @override
  String get depositRateNegative => 'Rate cannot be negative';

  @override
  String get depositValueDateLabel => 'Value date';

  @override
  String get depositMaturityDateLabel => 'Maturity date';

  @override
  String get depositCurrentValuationLabel => 'Current valuation (optional)';

  @override
  String get depositCurrentValuationHelper =>
      'Leave blank to use principal as current valuation';

  @override
  String get depositAutoRenewTitle => 'Auto-renew';

  @override
  String get depositAutoRenewSubtitle =>
      'On maturity you\'ll be prompted to re-register; no new deposit is created automatically';

  @override
  String get depositNoAccountHint => 'Please create a bank account first.';

  @override
  String get depositCreateAccountAction => 'New account';

  @override
  String get wealthProductDeleteTitle => 'Delete wealth product';

  @override
  String get wealthProductDeleteBody => 'Delete this wealth product record?';

  @override
  String get wealthProductCreateTitle => 'Record wealth product';

  @override
  String get wealthProductEditTitle => 'Edit wealth product';

  @override
  String get wealthProductDeleteTooltip => 'Delete';

  @override
  String get wealthProductNoAccountHint =>
      'Please create a bank / brokerage account first.';

  @override
  String get wealthProductCreateAccountAction => 'New account';

  @override
  String get wealthProductNameLabel => 'Product name';

  @override
  String get wealthProductNameRequired => 'Enter the product name';

  @override
  String get wealthProductIssuerLabel => 'Issuer (optional)';

  @override
  String get wealthProductCodeLabel => 'Product code (optional)';

  @override
  String get wealthProductAmountLabel => 'Subscription amount';

  @override
  String get wealthProductExpectedReturnLabel => 'Expected annual return (%)';

  @override
  String get wealthProductExpectedReturnHelper => 'e.g. 4.5 means 4.5%';

  @override
  String get wealthProductExpectedReturnRequired => 'Enter expected return';

  @override
  String get wealthProductInvalidFormat => 'Invalid format';

  @override
  String get wealthProductValueDateLabel => 'Value date';

  @override
  String get wealthProductMaturityDateLabel => 'Maturity date (optional)';

  @override
  String get wealthProductValuationLabel => 'Current valuation (manual)';

  @override
  String get wealthProductValuationHelper =>
      'Leave blank to use subscription amount as current valuation';

  @override
  String get manualSecurityMarketCnA => 'A-shares';

  @override
  String get manualSecurityMarketHk => 'HK stocks';

  @override
  String get manualSecurityMarketUs => 'US stocks';

  @override
  String get manualSecurityMarketCrypto => 'Crypto';

  @override
  String get manualSecurityTypeStock => 'Stock';

  @override
  String get manualSecurityTypeEtf => 'ETF';

  @override
  String get manualSecurityTypeMutualFund => 'Mutual fund';

  @override
  String get manualSecurityTypeBond => 'Bond';

  @override
  String get manualSecurityTypeCrypto => 'Crypto';

  @override
  String get manualSecurityEnterCodeOrName => 'Enter a code or name first';

  @override
  String get manualSecurityNetworkUnavailable =>
      'Network unavailable — use manual entry';

  @override
  String get manualSecurityNoMatch => 'No matches found — use manual entry';

  @override
  String get manualSecurityImported => 'Metadata imported from network';

  @override
  String get manualSecuritySelectMatchTitle => 'Select a match';

  @override
  String get manualSecuritySheetTitle => 'Add security manually';

  @override
  String get manualSecuritySheetDescription =>
      'Saved locally. Tap \'Import from network\' to optionally fill fields from Yahoo / CoinGecko metadata.';

  @override
  String get manualSecurityCodeLabel => 'Code';

  @override
  String get manualSecurityCodeRequired => 'Enter the code';

  @override
  String get manualSecurityCodeNoColon => 'Code cannot contain \':\'';

  @override
  String get manualSecurityImportAction => 'Import from network';

  @override
  String get manualSecurityImporting => 'Importing…';

  @override
  String get manualSecurityNameLabel => 'Name (optional)';

  @override
  String get manualSecurityMarketLabel => 'Market';

  @override
  String get manualSecurityTypeLabel => 'Type';

  @override
  String get manualSecurityIsinLabel => 'ISIN (optional)';

  @override
  String get manualSecurityAddAction => 'Add';

  @override
  String get localSecuritiesSearchLabel => 'Asset search';

  @override
  String get localSecuritiesSearchHint => 'Enter code, name, or pinyin';

  @override
  String get localSecuritiesValidationRequired => 'Select an asset';

  @override
  String get localSecuritiesMyAssets => 'My assets';

  @override
  String get localSecuritiesCatalog => 'Local catalog';

  @override
  String get localSecuritiesManualAdd => 'Not found? Add manually';

  @override
  String localSecuritiesUseQueryAsCode(String query) {
    return 'Use \"$query\" as code';
  }

  @override
  String get localSecuritiesMarketLabel => 'Market';

  @override
  String get dashboardInsightFireLabel => 'FIRE';

  @override
  String dashboardInsightFireToGoYears(int years, int months) {
    return '${years}y ${months}m to go';
  }

  @override
  String dashboardInsightFireToGoMonths(int months) {
    return '${months}m to go';
  }

  @override
  String get dashboardInsightFireReached => 'Goal reached';

  @override
  String get dashboardInsightDriftLabel => 'Portfolio drift';

  @override
  String get dashboardInsightDriftOver => 'over';

  @override
  String get dashboardInsightDriftUnder => 'under';

  @override
  String dashboardInsightDriftValue(
    String category,
    String direction,
    int points,
  ) {
    return '$category $direction ${points}pp';
  }

  @override
  String get dashboardInsightMaturityLabel => 'Maturities';

  @override
  String dashboardInsightMaturityValue(int count, int days) {
    return '$count deposits due in ${days}d';
  }

  @override
  String get dashboardInsightAnomalyLabel => 'Expense trend';

  @override
  String dashboardInsightAnomalyValue(String percent) {
    return 'Projected $percent';
  }

  @override
  String get dashboardInsightDuplicateChargeLabel =>
      'Possible duplicate charge';

  @override
  String dashboardInsightDuplicateChargeValue(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pairs',
      one: '1 pair',
    );
    return '$_temp0 totaling $amount';
  }

  @override
  String get dashboardInsightMonthlySummaryLabel => 'Last month recap';

  @override
  String dashboardInsightMonthlySummaryUp(String amount) {
    return 'Net worth grew $amount';
  }

  @override
  String dashboardInsightMonthlySummaryDown(String amount) {
    return 'Net worth shrank $amount';
  }

  @override
  String get dashboardInsightMonthlySummaryFlat => 'Net worth was flat';

  @override
  String get dashboardInsightActionExpand => 'Expand';

  @override
  String get dashboardInsightActionAsk => 'Ask';

  @override
  String get dashboardInsightActionDismiss => 'Dismiss';

  @override
  String get portfolioViewAssets => 'Assets';

  @override
  String get portfolioViewAccount => 'Account';

  @override
  String get portfolioViewCurrency => 'Currency';

  @override
  String get portfolioViewClass => 'Class';

  @override
  String portfolioAggregateItems(int count) {
    return '$count items';
  }

  @override
  String portfolioCurrencyNative(String amount) {
    return 'Native $amount';
  }

  @override
  String get portfolioUnassignedAccount => 'Unassigned';

  @override
  String get activityAddAction => 'Add';

  @override
  String get activityFeedFilterTitle => 'Filter';

  @override
  String get activityFeedFilterClear => 'Clear';

  @override
  String get activityFeedFilterKind => 'Kind';

  @override
  String get activityFeedFilterAccount => 'Account';

  @override
  String get activityFeedFilterAccountEmpty =>
      'No accounts yet — add one from the Accounts tab.';

  @override
  String get activityFeedFilterDateRange => 'Date range';

  @override
  String get activityFeedFilterRangeThisWeek => 'This week';

  @override
  String get activityFeedFilterRangeThisMonth => 'This month';

  @override
  String get activityFeedFilterRangeLastMonth => 'Last month';

  @override
  String get activityFeedFilterRangeThisYear => 'This year';

  @override
  String get activityFeedFilterRangeCustom => 'Custom…';

  @override
  String get activityFeedFilterThisMonth => 'This month';

  @override
  String get activityFeedFilteredEmpty => 'No activity matches these filters.';

  @override
  String get activityFeedLoadMore => 'Load more';

  @override
  String get activityFeedAllLoaded => 'All activity loaded';

  @override
  String get backupWebSecurityWarning =>
      'Web local storage is not SQLCipher-encrypted. Backup files are encrypted with your password; avoid long-term storage of sensitive accounts in the web app.';

  @override
  String get formSaving => 'Saving…';

  @override
  String get formSave => 'Save';

  @override
  String get settingsSyncTitle => 'Sync';

  @override
  String get settingsSyncSubtitle => 'View sync state and last activity';

  @override
  String get syncStatusTitle => 'Sync Status';

  @override
  String get syncStatusRefreshNow => 'Sync now';

  @override
  String syncStatusBusError(String error) {
    return 'Could not read sync status: $error';
  }

  @override
  String get syncStatusHeadlineIdle => 'Not synced yet';

  @override
  String get syncStatusHeadlineSyncing => 'Syncing…';

  @override
  String get syncStatusHeadlineOnline => 'All synced';

  @override
  String get syncStatusHeadlineOffline => 'Offline';

  @override
  String get syncStatusHeadlineFailed => 'Sync failed';

  @override
  String get syncStatusSubtitleNeverSynced =>
      'No successful sync yet on this device';

  @override
  String syncStatusSubtitleLastSynced(String when) {
    return 'Last synced $when';
  }

  @override
  String get syncStatusJustNow => 'just now';

  @override
  String syncStatusMinutesAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String syncStatusHoursAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String syncStatusDaysAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get syncStatusPendingHeader => 'Pending changes';

  @override
  String get syncStatusPendingLoading => 'Counting…';

  @override
  String get syncStatusPendingNone => 'Up to date';

  @override
  String syncStatusPendingCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n changes waiting',
      one: '1 change waiting',
    );
    return '$_temp0';
  }

  @override
  String get syncStatusPendingCaption => 'Local edits queued for the next push';

  @override
  String get syncStatusPendingCaptionEmpty =>
      'All local edits have been pushed to the server';

  @override
  String get syncStatusActionSyncNow => 'Sync now';

  @override
  String get syncStatusErrorHeader => 'Last error';

  @override
  String get syncStatusConflictsHeader => 'Conflict diagnostics';

  @override
  String syncStatusConflictsLocalWins(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n remote rows were older than local state',
      one: '1 remote row was older than local state',
      zero: 'No remote rows were blocked by local state',
    );
    return '$_temp0';
  }

  @override
  String syncStatusConflictsIgnored(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$n remote rows were ignored because their namespace is not supported here',
      one:
          '1 remote row was ignored because its namespace is not supported here',
    );
    return '$_temp0';
  }

  @override
  String get syncStatusDetailsHeader => 'Details';

  @override
  String get syncStatusDetailState => 'State';

  @override
  String get syncStatusDetailUpdatedAt => 'Updated';

  @override
  String get syncStatusDetailDevice => 'Device';

  @override
  String get syncStatusDetailCursor => 'Pull cursor';

  @override
  String get syncStatusDetailCursorUnset => 'not set';

  @override
  String get syncStatusDetailRemoteRows => 'Remote rows';

  @override
  String get syncStatusDetailEndpoint => 'Endpoint';

  @override
  String get syncStatusLocalCountsHeader => 'Local row counts (debug)';

  @override
  String get syncStatusLocalAccountsUser => 'Accounts (user)';

  @override
  String get syncStatusLocalAccountsSystem => 'Accounts (system)';

  @override
  String get syncStatusLocalJournalEntries => 'Journal entries';

  @override
  String get syncStatusLocalPostings => 'Postings';

  @override
  String get syncStatusLocalAssets => 'Assets';

  @override
  String get syncStatusLocalPrices => 'Prices';

  @override
  String get syncStatusLocalLiabilities => 'Liabilities';

  @override
  String get syncStatusLocalTags => 'Tags';

  @override
  String get syncStatusHeroSyncing => 'Syncing changes…';

  @override
  String get syncStatusStatPending => 'Pending';

  @override
  String get syncStatusStatLocal => 'Local rows';

  @override
  String get syncStatusStatLastSync => 'Last sync';

  @override
  String get syncStatusStatNever => 'Never';

  @override
  String get syncStatusStatJustNow => 'now';

  @override
  String get aiReplyChipCompareLastPeriod => 'Compare to previous period';

  @override
  String get aiReplyChipFindKeyDrivers => 'Find the key drivers';

  @override
  String get aiReplyChipHowControlSpending => 'How do I rein in spending?';

  @override
  String get aiReplyChipViewHoldings => 'View holdings detail';

  @override
  String get aiReplyChipComputeXirr => 'Compute XIRR';

  @override
  String get aiReplyChipCompareLastMonth => 'Compare to last month';

  @override
  String get aiReplyChipMarketDrop20 => 'What if the market drops 20%?';

  @override
  String get aiReplyChipMonthlySaveDelta => 'How much more to save each month?';

  @override
  String get aiReplyChipRebalanceAdvice => 'Rebalancing advice';

  @override
  String get aiReplyChipCompareAnotherPeriod => 'Compare another period';

  @override
  String get aiReplyChipBiggestCategoryChange =>
      'Which categories changed most?';

  @override
  String get aiReplyChipTrendSummary => 'Give a trend summary';

  @override
  String get aiReplyChipHandleInsight => 'How should I handle this?';

  @override
  String get aiReplyChipSimilarHistory => 'Show similar past cases';

  @override
  String get aiReplyChipActionPlan => 'Give me a concrete action plan';

  @override
  String get aiReplyChipRiskConcentration => 'Risk concentration check';

  @override
  String get aiReplyChipUnusedSubscriptions => 'Which subscriptions go unused?';

  @override
  String get aiReplyChipCancelPriciestSub =>
      'Cancel the priciest subscription?';

  @override
  String get aiReplyChipUnmatchedRefunds => 'Unmatched refunds';

  @override
  String get aiReplyChipCompareBenchmark => 'Compare with benchmark';

  @override
  String get aiReplyChipForecast12mo => '12-month forecast';

  @override
  String get aiReplyChipExpandDetails => 'Expand details';

  @override
  String get aiReplyChipActionPlanGeneric => 'Give an action plan';

  @override
  String get aiReplyChipVsLastMonth => 'Compare with last month';

  @override
  String get aiCapsuleExpandFallback => 'Expand';

  @override
  String get dashboardInsightIngestQueueLabel => 'Records to confirm';

  @override
  String dashboardInsightIngestQueueValue(int count, int fresh) {
    return '$count parsed · $fresh ready to add';
  }

  @override
  String get dashboardInsightCashFlowDeficitLabel => 'Cashflow gap';

  @override
  String dashboardInsightCashFlowDeficitValue(String amount) {
    return 'This month is short $amount';
  }

  @override
  String get ingestReviewTitle => 'Review entries';

  @override
  String ingestAccountsLoadError(String error) {
    return 'Failed to load accounts: $error';
  }

  @override
  String ingestQueueLoadError(String error) {
    return 'Failed to load the queue: $error';
  }

  @override
  String get ingestExpenseAccountLabel => 'Paid from';

  @override
  String ingestConfirmAllFresh(int count) {
    return 'Confirm all · new only ($count)';
  }

  @override
  String get ingestSelectAccountFirst => 'Pick a paying account first';

  @override
  String get ingestServiceNotReady => 'Service not ready yet';

  @override
  String get ingestRecorded => 'Recorded';

  @override
  String ingestRecordedN(int count) {
    return 'Recorded $count';
  }

  @override
  String get ingestPasteTitle => 'Paste statement text';

  @override
  String get ingestPasteHint =>
      'Paste Alipay / WeChat Pay / bank CSV text\ne.g. 2026-05-10,Starbucks,-38.00,CNY';

  @override
  String get ingestParseAction => 'Parse';

  @override
  String get ingestNoTransactions => 'No recognizable transactions';

  @override
  String ingestParseSummary(int total, int fresh, int dup) {
    return 'Parsed $total · $fresh new · $dup possible dup';
  }

  @override
  String get ingestProcessingTitle => 'Parsing import';

  @override
  String ingestProcessingBody(String source) {
    return 'Reading $source, extracting expenses, and checking duplicates against your ledger and pending imports.';
  }

  @override
  String get ingestRecordingTitle => 'Recording entries';

  @override
  String get ingestRecordingBody =>
      'Writing confirmed entries and refreshing the queue.';

  @override
  String get ingestSourceCsv => 'CSV file';

  @override
  String get ingestSourcePaste => 'Pasted text';

  @override
  String get ingestSourceImage => 'Receipt image';

  @override
  String get ingestSourcePdf => 'PDF statement';

  @override
  String get ingestSourceEmail => 'Email';

  @override
  String ingestDraftConfidence(int percent) {
    return '$percent% confidence';
  }

  @override
  String get ingestUncategorized => 'Uncategorized';

  @override
  String get ingestSkip => 'Skip';

  @override
  String get ingestConfirm => 'Record';

  @override
  String get ingestVerdictNew => 'New';

  @override
  String get ingestVerdictLikely => 'Likely dup';

  @override
  String get ingestVerdictDuplicate => 'Duplicate';

  @override
  String get ingestEmptyTitle => 'Nothing to confirm';

  @override
  String get ingestEmptyBody =>
      'Import Alipay, WeChat Pay, or bank statement CSV/text regularly.\nOverlapping periods are flagged before confirmation.';

  @override
  String get ingestPasteAction => 'Paste text';

  @override
  String get ingestImportFileAction => 'Import file';

  @override
  String get ingestCameraAction => 'Take photo';

  @override
  String get settingsAiTransparencyTitle => 'AI transparency';

  @override
  String get settingsAiTransparencySubtitle =>
      'View detailed traces from recent AI calls';

  @override
  String get settingsAiLlmTitle => 'On-device AI · Bring your own key';

  @override
  String get settingsAiLlmSubtitle =>
      'Manage multiple provider keys and switch local direct connections';

  @override
  String get aiLlmMissingApiKey => 'Enter an API key first';

  @override
  String get aiLlmSaved => 'Saved to secure device storage';

  @override
  String get aiLlmSwitched => 'Switched';

  @override
  String get aiLlmRemoved => 'Removed from this device';

  @override
  String get aiLlmEmpty =>
      'No providers yet. Add an API key to run AI through a local direct connection.';

  @override
  String get aiLlmAddProvider => 'Add provider';

  @override
  String get aiLlmEditProvider => 'Edit provider';

  @override
  String get aiLlmActiveTag => 'Active';

  @override
  String get aiLlmTapToSwitch => 'Tap to switch';

  @override
  String get aiLlmNameLabel => 'Name (optional)';

  @override
  String get aiLlmNameHint => 'Anthropic official / company gateway …';

  @override
  String get aiLlmProviderLabel => 'Provider';

  @override
  String get aiLlmStoredKeyHint => 'Configured · leave blank to keep unchanged';

  @override
  String get aiLlmBaseUrlLabel => 'Custom Base URL (optional)';

  @override
  String get aiLlmModelLabel => 'Model (optional; blank uses default)';

  @override
  String get aiLlmTestConnectivity => 'Test connectivity';

  @override
  String get aiLlmTesting => 'Testing…';

  @override
  String get aiLlmSaving => 'Saving…';

  @override
  String get aiLlmIntro =>
      'Use your own LLM API key so AI runs through a local direct connection to the provider. You can save multiple providers and switch anytime. Keys stay in this device\'s secure storage (Keychain/Keystore); they are not uploaded, synced, or backed up. Your provider account owns cost and rate limits.';

  @override
  String get aiLlmUnsupportedTitle =>
      'This platform does not support on-device direct connections';

  @override
  String get aiLlmUnsupportedBody =>
      'Bring-your-own-key on-device AI works on native platforms (iOS / Android / macOS / Windows / Linux) with system secure storage. Web continues to use cloud AI.';

  @override
  String aiLlmStatusActive(String name) {
    return 'Active: $name · local direct connection';
  }

  @override
  String get aiLlmStatusSavedNoActive => 'Providers saved, but none selected';

  @override
  String get aiLlmStatusReadFailed => 'Could not read secure storage';

  @override
  String get aiLlmStatusNotConfigured =>
      'Not configured · no on-device AI available';

  @override
  String aiLlmAnthropicProtocol(String provider) {
    return '$provider (Anthropic Messages protocol)';
  }

  @override
  String aiLlmOpenAiProtocol(String provider) {
    return '$provider (Chat Completions protocol)';
  }

  @override
  String get aiTransparencyFilteredEmpty =>
      'No records match the current filter';

  @override
  String aiTransparencyLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get aiTransparencyVerboseTitle => 'Detailed capture';

  @override
  String get aiTransparencyVerboseSubtitle =>
      'Record each step\'s input and output (local only; cleaned after 30 days)';

  @override
  String get aiTransparencyToggleOn => 'On';

  @override
  String get aiTransparencyToggleOff => 'Off';

  @override
  String aiTransparencyRecentCalls(int count) {
    return 'Last $count calls';
  }

  @override
  String aiTransparencyErrors(int count) {
    return 'Errors $count';
  }

  @override
  String get aiTransparencyEmpty =>
      'No AI call records yet.\nAfter the next conversation, the full trace will appear here.';

  @override
  String aiTransparencyToolsCount(int count) {
    return 'Tools $count';
  }

  @override
  String get aiTransparencyUnnamedTurn => '(unnamed turn)';

  @override
  String get aiTransparencyDetailTitle => 'Call chain';

  @override
  String get aiTransparencyTraceNotFound => 'This call record was not found';

  @override
  String get aiTransparencyNoSpans =>
      'This record has no execution chain (it predates the span model and will be cleaned automatically within 30 days).';

  @override
  String aiTransparencyEventSummary(int count, String time) {
    return '$count events · started $time';
  }

  @override
  String aiTraceRoundsCount(int count) {
    return '$count rounds';
  }

  @override
  String get aiTraceNoPayloadCaptured =>
      'input/output was not captured (compact mode). Turn on Detailed capture on the AI transparency page; new calls will record each step\'s parameters and return values for debugging.';

  @override
  String get aiChatDeviceUnavailable =>
      'AI requires your own API key in Settings before it can run. The model connection is made directly from this device, and requests/data do not pass through our servers. On-device AI is not supported on web yet.';

  @override
  String get expenseFormAiTimeframeRecent90Days => 'Last 90 days';

  @override
  String get unsavedChangesTitle => 'Discard changes?';

  @override
  String get unsavedChangesBody => 'Your edits will be lost if you leave now.';

  @override
  String get unsavedChangesDiscard => 'Discard';

  @override
  String get unsavedChangesKeepEditing => 'Keep editing';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String get watchlistTitle => 'Watchlist';

  @override
  String get watchlistAccountsEntrySubtitle =>
      'Track symbols and local price alerts';

  @override
  String get watchlistAddAction => 'Add symbol';

  @override
  String get watchlistAddTitle => 'Add to watchlist';

  @override
  String watchlistEditAlertTitle(String symbol) {
    return 'Alerts for $symbol';
  }

  @override
  String get watchlistEmptyTitle => 'No watchlist symbols';

  @override
  String get watchlistEmptyBody =>
      'Add a ticker to poll prices cache-first and trigger threshold alerts while the page is open.';

  @override
  String get watchlistSymbolField => 'Symbol';

  @override
  String get watchlistMarketField => 'Market';

  @override
  String get watchlistAlertAboveField => 'Alert above';

  @override
  String get watchlistAlertBelowField => 'Alert below';

  @override
  String get watchlistSaveAlertsAction => 'Save alerts';

  @override
  String get watchlistEditAlertsAction => 'Alerts';

  @override
  String get watchlistRemoveAction => 'Remove';

  @override
  String get watchlistPriceUnavailable => 'No price';

  @override
  String get watchlistFreshnessLive => 'Live';

  @override
  String get watchlistFreshnessCache => 'Cached';

  @override
  String get watchlistFreshnessStale => 'Stale cache';

  @override
  String watchlistAlertAboveChip(String price) {
    return 'Above $price';
  }

  @override
  String watchlistAlertBelowChip(String price) {
    return 'Below $price';
  }

  @override
  String watchlistAlertTriggeredAbove(String symbol, String price) {
    return '$symbol is at $price, above your alert';
  }

  @override
  String watchlistAlertTriggeredBelow(String symbol, String price) {
    return '$symbol is at $price, below your alert';
  }

  @override
  String get watchlistSymbolRequired => 'Enter a symbol';

  @override
  String get watchlistInvalidNumber => 'Enter a positive price';

  @override
  String get watchlistMarketCnA => 'A-share';

  @override
  String get watchlistMarketHkStock => 'Hong Kong';

  @override
  String get watchlistMarketUsStock => 'US';

  @override
  String get watchlistMarketCrypto => 'Crypto';

  @override
  String get watchlistMarketFx => 'FX';

  @override
  String get watchlistMarketUnknown => 'Unknown';

  @override
  String get masterDetailBackToList => 'Back to list';

  @override
  String get incomePlannerTitle => 'Income Planner';

  @override
  String get incomePlannerAccountsEntrySubtitle =>
      'Screen sell-put and covered-call income opportunities';

  @override
  String get commandKeywordOptionsCn => '期权';

  @override
  String get commandKeywordSellPutCn => '卖看跌';

  @override
  String get commandKeywordCoveredCallCn => '备兑';

  @override
  String get incomePlannerUnsupportedOnWeb =>
      'Income Planner is only available on mobile.';

  @override
  String get incomePlannerOccTitle => 'Options risk disclosure';

  @override
  String get incomePlannerOccSubtitle => 'Read before using';

  @override
  String get incomePlannerOccBody =>
      'Selling cash-secured puts and covered calls have defined and undefined risks. Sell-puts can require you to buy 100 shares at strike if assigned; covered calls cap upside above strike. Income Planner only screens opportunities that match your stated risk preferences — it does not predict prices and does not place orders. By continuing you acknowledge you have read OCC Characteristics and Risks of Standardized Options.';

  @override
  String get incomePlannerOccAccept => 'I have read and accept';

  @override
  String get incomePlannerOccCancel => 'Not now';

  @override
  String get incomePlannerOccLearnMore => 'Open OCC ODD';

  @override
  String get incomePlannerStartTitle => 'Set up your stance';

  @override
  String get incomePlannerStartBody =>
      'Tell Income Planner which strategies and risk level you want, then approve the underlyings you would be happy to own or sell.';

  @override
  String get incomePlannerStartCta => 'Configure preferences';

  @override
  String get incomePlannerNoApprovedTitle => 'No approved underlyings yet';

  @override
  String get incomePlannerNoApprovedBody =>
      'Add the stocks or ETFs you would be willing to long-term hold (for sell puts) or sell at a higher price (for covered calls). Income Planner only scans symbols on this list.';

  @override
  String get incomePlannerAddApprovedCta => 'Add underlying';

  @override
  String get incomePlannerProfileTitle => 'Preferences';

  @override
  String get incomePlannerProfileMode => 'Risk mode';

  @override
  String get incomePlannerProfileModeConservative => 'Conservative';

  @override
  String get incomePlannerProfileModeBalanced => 'Balanced';

  @override
  String get incomePlannerProfileModeAggressive => 'Aggressive';

  @override
  String get incomePlannerProfileModeCustom => 'Custom';

  @override
  String get incomePlannerProfileAvoidEarnings =>
      'Skip candidates within 7 days of earnings';

  @override
  String get incomePlannerProfileAvoidMacroEvents =>
      'Skip candidates within 7 days of CPI / FOMC';

  @override
  String get incomePlannerProfileOnlyApproved =>
      'Only scan symbols on the approved list (recommended)';

  @override
  String get incomePlannerProfileAllowedStrategies => 'Strategies';

  @override
  String get incomePlannerProfileAllowPut => 'Cash-secured puts';

  @override
  String get incomePlannerProfileAllowCall => 'Covered calls';

  @override
  String get incomePlannerProfileSave => 'Save';

  @override
  String get incomePlannerProfileCancel => 'Cancel';

  @override
  String get incomePlannerAddUnderlyingTitle => 'Add approved underlying';

  @override
  String get incomePlannerEditUnderlyingTitle => 'Edit underlying';

  @override
  String get incomePlannerSymbolLabel => 'Symbol';

  @override
  String get incomePlannerSymbolHint => 'AAPL';

  @override
  String get incomePlannerMarketLabel => 'Market';

  @override
  String get incomePlannerAllowPutLabel => 'Allow cash-secured puts';

  @override
  String get incomePlannerAllowCallLabel => 'Allow covered calls';

  @override
  String get incomePlannerSaveAction => 'Save';

  @override
  String get incomePlannerDeleteAction => 'Delete';

  @override
  String get incomePlannerCancelAction => 'Cancel';

  @override
  String get incomePlannerApprovedSectionTitle => 'Approved underlyings';

  @override
  String get incomePlannerOpportunitiesSectionTitle => 'Opportunities';

  @override
  String get incomePlannerOpportunitiesEmpty =>
      'No cached opportunities yet. Tap \"Refresh opportunities\" to scan your approved underlyings.';

  @override
  String get incomePlannerRefreshAction => 'Refresh opportunities';

  @override
  String get incomePlannerRefreshRunning => 'Scanning…';

  @override
  String get incomePlannerRefreshFailedTitle => 'Scan failed';

  @override
  String get incomePlannerRefreshUniverseEmpty =>
      'No symbols are eligible. Add at least one approved underlying with put/call enabled, or check that you own ≥100 shares for covered calls.';

  @override
  String get incomePlannerLastScanLabel => 'Last scan';

  @override
  String get incomePlannerLastScanStale =>
      'Cached results are older than 24h — refresh for fresher data.';

  @override
  String get incomePlannerOpportunitiesAllRejected =>
      'No candidates passed your hard filters this scan. Loosen your preferences (e.g. lower yield floor, wider DTE) and try again.';

  @override
  String get incomePlannerNoMatchesTitle =>
      'No matching opportunities this scan';

  @override
  String get incomePlannerScanNoMatchesToast =>
      'Scan finished: no opportunities matched your current filters.';

  @override
  String incomePlannerScanSummary(int symbols, int rejected, int errors) {
    return 'Scanned $symbols symbols · rejected $rejected contracts · $errors fetch errors';
  }

  @override
  String get incomePlannerChipCashSecuredPut => 'Sell put';

  @override
  String get incomePlannerChipCoveredCall => 'Covered call';

  @override
  String get incomePlannerRiskLow => 'Low risk';

  @override
  String get incomePlannerRiskModerate => 'Moderate';

  @override
  String get incomePlannerRiskElevated => 'Elevated';

  @override
  String get incomePlannerMetricAnnualized => 'Annualized';

  @override
  String get incomePlannerMetricCash => 'Cash required';

  @override
  String get incomePlannerMetricBreakeven => 'Breakeven';

  @override
  String get incomePlannerMetricDte => 'DTE';

  @override
  String get incomePlannerMetricStrike => 'Strike';

  @override
  String get incomePlannerMetricMargin => 'Cushion';

  @override
  String get incomePlannerCardDetailsCta => 'Details';

  @override
  String get incomePlannerDetailWhyGood => 'Why this looks good';

  @override
  String get incomePlannerDetailWhyRisky => 'Why this is risky';

  @override
  String get incomePlannerDetailWorstCase => 'Worst case';

  @override
  String get incomePlannerDetailBestFor => 'Best for';

  @override
  String get incomePlannerDetailAvoidIf => 'Avoid if';

  @override
  String get incomePlannerDetailScoreBreakdown => 'Score breakdown';

  @override
  String get incomePlannerDetailLogTrade => 'Log this trade';

  @override
  String get incomePlannerJournalSectionTitle => 'Trade journal';

  @override
  String get incomePlannerJournalEmpty =>
      'Closed and open positions you log will appear here.';

  @override
  String get incomePlannerJournalAddCta => 'Log trade';

  @override
  String get incomePlannerJournalEditTitle => 'Edit trade journal entry';

  @override
  String get incomePlannerJournalCreditLabel => 'Credit received';

  @override
  String get incomePlannerJournalDebitLabel => 'Debit paid to close';

  @override
  String get incomePlannerJournalOptionSymbolLabel => 'Option symbol';

  @override
  String get incomePlannerJournalOptionSymbolHint => 'AAPL250620P00190000';

  @override
  String get incomePlannerJournalAmountHint => '0.00';

  @override
  String get incomePlannerJournalNotesLabel => 'Notes';

  @override
  String get incomePlannerJournalStatusOpen => 'Open';

  @override
  String get incomePlannerJournalStatusClosed => 'Closed';

  @override
  String get incomePlannerJournalStatusAssigned => 'Assigned';

  @override
  String get incomePlannerJournalStatusExpired => 'Expired';

  @override
  String get incomePlannerSymbolRequired => 'Symbol is required';

  @override
  String get incomePlannerDuplicateSymbol =>
      'This symbol is already on the list';

  @override
  String get incomePlannerProfileSaveError => 'Could not save preferences';

  @override
  String get incomePlannerUnderlyingSaveError => 'Could not save underlying';

  @override
  String get incomePlannerPreferencesAction => 'Preferences';

  @override
  String get incomePlannerEditAction => 'Edit';

  @override
  String incomePlannerLastScanMinutes(int n) {
    return '${n}m ago';
  }

  @override
  String incomePlannerLastScanHours(int n) {
    return '${n}h ago';
  }

  @override
  String incomePlannerLastScanDays(int n) {
    return '${n}d ago';
  }

  @override
  String incomePlannerLastScanFresh(String label, String ago, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count candidates',
      one: '1 candidate',
    );
    return '$label: $ago · $_temp0';
  }

  @override
  String incomePlannerLastScanStaleSummary(
    String label,
    String ago,
    String stale,
  ) {
    return '$label: $ago · $stale';
  }

  @override
  String get onboardingTitle => 'Welcome to NaviWealth';

  @override
  String get onboardingSubtitle => 'Choose how you want to use the app';

  @override
  String get onboardingCloudTitle => 'Cloud account';

  @override
  String get onboardingCloudDescription => 'Sync data across devices';

  @override
  String get onboardingLocalOnlyTitle => 'Local only';

  @override
  String get onboardingLocalOnlyDescription =>
      'Data stays on this device, no sync';

  @override
  String get settingsAccountLocalOnlyBadge => 'Local mode';

  @override
  String get settingsAccountLocalOnlyHint =>
      'Data is stored only on this device';

  @override
  String get commonDate => 'Date';

  @override
  String get commonNote => 'Note';

  @override
  String get commonOk => 'OK';

  @override
  String get healthTodayTitle => 'Today · HealthOS';

  @override
  String get healthRecordBodyMetricAction => 'Record body metric';

  @override
  String get healthBodyMeasurementTitle => 'Record body metric';

  @override
  String get healthBodyMeasurementSubtitle =>
      'For low-frequency manual metrics like weight and body fat';

  @override
  String get healthMetricWeight => 'Weight';

  @override
  String get healthMetricBodyFat => 'Body fat';

  @override
  String get healthBodyMeasurementWeightHelper => 'Unit: kg';

  @override
  String get healthBodyMeasurementBodyFatHelper => 'Unit: %, for example 18.5';

  @override
  String get healthBodyFatMaxError => 'Body fat cannot exceed 100%';

  @override
  String healthBodyMeasurementSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String get knowledgeInboxTitle => 'Inbox · KnowledgeOS';

  @override
  String get knowledgeCaptureAction => 'New capture';

  @override
  String get knowledgeAiPromptHint => 'Capture something or ask a question...';

  @override
  String get knowledgeAiDedupeAction => 'Deduplicate';

  @override
  String get knowledgeAiDedupePrompt =>
      'Check whether my knowledge base has similar or duplicate notes or concepts, and suggest merges where useful.';

  @override
  String get knowledgeAiWeeklyAction => 'Weekly review';

  @override
  String get knowledgeAiWeeklyPrompt =>
      'Give me this week\'s knowledge review: decisions due for review, stale assumptions, routines due this week, and orphan notes without tags or links.';

  @override
  String get knowledgeAiSearchAction => 'Search knowledge';

  @override
  String get knowledgeAiSearchPrompt => 'Search my knowledge base: ';

  @override
  String get knowledgeLibraryTitle => 'Library · KnowledgeOS';

  @override
  String get knowledgeSegmentDecisions => 'Decisions';

  @override
  String get knowledgeSegmentNotes => 'Notes';

  @override
  String get knowledgeSegmentConcepts => 'Concepts';

  @override
  String get knowledgeSegmentExperiments => 'Experiments';

  @override
  String get knowledgeSegmentRoutines => 'Routines';

  @override
  String get knowledgeNewDecision => 'New Decision';

  @override
  String get knowledgeNewNote => 'New Note';

  @override
  String get knowledgeNewConcept => 'New Concept';

  @override
  String get knowledgeNewExperiment => 'New Experiment';

  @override
  String get knowledgeNewRoutine => 'New Routine';

  @override
  String get knowledgeNewChooserTitle => 'New...';

  @override
  String get knowledgeNewChooserSubtitle =>
      'Decision, Principle, and Assumption share the same capture flow';

  @override
  String get knowledgeNewDecisionHint =>
      'Primary path: question, options, rationale';

  @override
  String get knowledgeNewPrincipleHint =>
      'A worldview primitive, for example \"edge-first\"';

  @override
  String get knowledgeNewAssumptionHint =>
      'A falsifiable belief with confidence';

  @override
  String get knowledgeNotesHintTitle => 'Notes are captured in Inbox';

  @override
  String get knowledgeNotesHintBody =>
      'The Notes segment is for browsing. Close this panel, switch to Inbox, and use the create action there.';

  @override
  String get amountHidden => 'Amount hidden';
}
