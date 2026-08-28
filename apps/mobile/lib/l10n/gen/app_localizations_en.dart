// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String commonSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get rebalanceExecutionResumeInterruptedAction =>
      'Resume interrupted work';

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
  String get navActivity => 'Records';

  @override
  String get navAccounts => 'Accounts';

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
  String get planRebalanceSectionTitle => 'Rebalance';

  @override
  String get planIncomeSectionSubtitle => 'Dividends, Wheel & LEAPS';

  @override
  String get planBudgetSectionTitle => 'Budget';

  @override
  String get planAttentionTitle => 'Needs attention';

  @override
  String planAttentionShowAll(int count) {
    return 'Show $count more';
  }

  @override
  String get planAttentionCollapse => 'Show less';

  @override
  String planAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get planCashSafetyTitle => 'Cash safety';

  @override
  String get planLongTermGoalsTitle => 'Long-term goals & scenarios';

  @override
  String get planInvestmentPlanTitle => 'Investment execution';

  @override
  String get planIncomeStrategiesTitle => 'Income strategies';

  @override
  String planExploreActiveOptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count options positions active',
      one: '1 options position active',
    );
    return '$_temp0';
  }

  @override
  String get planDcaPlanTitle => 'Recurring investment plan';

  @override
  String get planFireGoalTitle => 'Financial independence';

  @override
  String get planFireGoalNotConfigured =>
      'Set a long-term target when it becomes useful';

  @override
  String get planStatusNeedsSetup => 'Needs setup';

  @override
  String get planStatusLoading => 'Loading status…';

  @override
  String get planStatusUnavailable => 'Status unavailable';

  @override
  String get planStatusPartiallyUnavailable =>
      'Some plan statuses are temporarily unavailable.';

  @override
  String get planStatusView => 'View';

  @override
  String get planStatusInProgress => 'In progress';

  @override
  String get planStatusOnTrack => 'On track';

  @override
  String get planStatusNeedsAttention => 'Review';

  @override
  String get planStatusActionRequired => 'Action needed';

  @override
  String get planStatusNoPendingReviews => 'No reviews due';

  @override
  String planStatusPendingReviews(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews due',
      one: '1 review due',
    );
    return '$_temp0';
  }

  @override
  String get planStatusRebalanceBalanced => 'On target';

  @override
  String planStatusRebalanceAttention(String percent) {
    return '$percent% drift';
  }

  @override
  String get planStatusRebalanceActive => 'Execution in progress';

  @override
  String planStatusBudgetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count category caps',
      one: '1 category cap',
    );
    return '$_temp0';
  }

  @override
  String get planStatusBudgetComfortable => 'Spending is within plan';

  @override
  String planStatusBudgetUsed(String percent) {
    return '$percent% used this month';
  }

  @override
  String get planStatusBudgetStrained => 'Approaching the monthly limit';

  @override
  String get planStatusBudgetOver => 'Monthly budget exceeded';

  @override
  String planStatusFireProgress(String percent) {
    return '$percent% toward target';
  }

  @override
  String get planStatusDcaDue => 'Contribution due';

  @override
  String planStatusDcaNext(String date) {
    return 'Next $date';
  }

  @override
  String get planStatusDcaPaused => 'All plans paused';

  @override
  String get planBudgetTitle => 'Budget';

  @override
  String get planBudgetEmptyTitle => 'No budgets yet';

  @override
  String get planBudgetEmptyBody =>
      'Set a monthly cap for any category to track spending against it here.';

  @override
  String get planBudgetEmptyCta => 'Set first budget';

  @override
  String get planBudgetAddAction => 'Add budget';

  @override
  String get planBudgetCreateTitle => 'New budget';

  @override
  String get planBudgetCategoryLabel => 'Expense category';

  @override
  String get planBudgetCategoryHelper =>
      'Choose the category whose monthly spending this cap should track.';

  @override
  String get planBudgetCategoryRequired => 'Choose an expense category.';

  @override
  String get planBudgetNoAvailableCategories =>
      'Every expense category already has a budget for this month.';

  @override
  String get planBudgetPreviousMonth => 'Previous month';

  @override
  String get planBudgetCopyPreviousAction => 'Copy previous month';

  @override
  String planBudgetCopied(int count) {
    return 'Copied $count budgets from the previous month';
  }

  @override
  String planBudgetCurrencyMismatch(int count) {
    return '$count budgets use another currency and are excluded from this summary.';
  }

  @override
  String get planBudgetNextMonth => 'Next month';

  @override
  String planBudgetPeriodCurrency(String month, String currency) {
    return '$month · $currency';
  }

  @override
  String planBudgetMonthHeader(String month) {
    return '$month budgets';
  }

  @override
  String get planBudgetTotalLabel => 'Total monthly budget';

  @override
  String planBudgetSpentOf(String spent, String budgeted, String currency) {
    return 'Spent $spent of $budgeted $currency';
  }

  @override
  String planBudgetRemaining(String amount, String currency) {
    return '$amount $currency left';
  }

  @override
  String planBudgetOverBy(String amount, String currency) {
    return '$amount $currency over';
  }

  @override
  String get planBudgetEditTitle => 'Edit budget';

  @override
  String get planBudgetDeleteAction => 'Delete budget';

  @override
  String get planBudgetDeleteTitle => 'Delete this budget?';

  @override
  String get planBudgetDeleteBody =>
      'This removes the category cap for the selected month. Recorded expenses are not affected.';

  @override
  String planBudgetAmountLabel(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String get planBudgetNoteLabel => 'Note';

  @override
  String get planBudgetInvalidAmount => 'Enter a non-negative amount.';

  @override
  String planBudgetSaveFailed(String error) {
    return 'Could not save budget: $error';
  }

  @override
  String get planWheelTitle => 'Wheel cycles';

  @override
  String get planWheelEmptyTitle => 'No active cycles';

  @override
  String get planWheelEmptyBody =>
      'Record a sell-put or covered-call trade and the cycle will surface here.';

  @override
  String get planWheelHistoryTitle => 'Cycle history';

  @override
  String get planWheelStageBetween => 'Between cycles';

  @override
  String get planWheelStageCashWaiting => 'Cash waiting';

  @override
  String get planWheelStageShortPut => 'Short put (open)';

  @override
  String get planWheelStagePutExpired => 'Put expired';

  @override
  String get planWheelStagePutAssigned => 'Put assigned';

  @override
  String get planWheelStageSharesHeld => 'Shares held';

  @override
  String get planWheelStageShortCall => 'Short call (open)';

  @override
  String get planWheelStageCallExpired => 'Call expired';

  @override
  String get planWheelStageCallCalled => 'Called away';

  @override
  String get investmentEventTimelineTitle => 'Upcoming events';

  @override
  String get investmentEventTimelineEmpty =>
      'No upcoming dividends or splits in the next 90 days.';

  @override
  String get investmentEventTimelineError => 'Couldn\'t load upcoming events.';

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
  String get planHeroConfigure => 'Set up plan';

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
  String get wealthEmptyTitle => 'Start with an account';

  @override
  String get wealthEmptyBody =>
      'Add where you keep money, then record holdings and liabilities as needed.';

  @override
  String get wealthEmptyAction => 'Add account';

  @override
  String get wealthObjectsTitle => 'Wealth items';

  @override
  String get wealthAccountsSectionTitle => 'Accounts';

  @override
  String get wealthAccountsSectionSubtitle => 'Cash, banks, brokers, crypto';

  @override
  String get wealthHoldingsSectionTitle => 'Holdings';

  @override
  String get wealthHoldingsSectionSubtitle => 'Positions across all accounts';

  @override
  String get wealthDividendSectionSubtitle =>
      'Forecasts, received income, and withholding tax';

  @override
  String get wealthWatchlistSectionTitle => 'Watchlist';

  @override
  String get wealthWatchlistSectionSubtitle => 'Symbols you\'re tracking';

  @override
  String get wealthLiabilitiesSectionTitle => 'Liabilities';

  @override
  String get wealthLiabilitiesSectionSubtitle => 'Loans, mortgages, credit';

  @override
  String get wealthTrendTitle => 'Wealth trend';

  @override
  String get wealthTrendFlatHint => 'No change in the selected period.';

  @override
  String get wealthTrendEstimatedDisclosure =>
      'Estimated from cost basis because a market price is unavailable. Period change is unavailable.';

  @override
  String get wealthTrendExcludedDisclosure =>
      'Earlier incomplete or estimated valuations are excluded from the trend and period change.';

  @override
  String get wealthTrendIncompleteDisclosure =>
      'A complete current valuation is unavailable, so no partial total is plotted.';

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
  String get cashFlowShowOriginalCurrencies => 'Show original currencies';

  @override
  String get cashFlowShowBaseCurrency => 'Show base currency';

  @override
  String get cashFlowCommandOpen => 'Open cash flow';

  @override
  String get cashFlowCommandViewIncome => 'View income';

  @override
  String get cashFlowPeriodMonth => 'Monthly';

  @override
  String get cashFlowPeriodQuarter => 'Quarterly';

  @override
  String get cashFlowPeriodYear => 'Yearly';

  @override
  String get cashFlowPreviousPeriod => 'Previous period';

  @override
  String get cashFlowNextPeriod => 'Next period';

  @override
  String cashFlowAnchorQuarter(int year, int quarter) {
    return '$year Q$quarter';
  }

  @override
  String cashFlowFxIncomplete(int count, String currencies) {
    return '$count cash-flow entries were excluded because $currencies rates are missing.';
  }

  @override
  String get cashFlowKpiInflow => 'Inflow';

  @override
  String get cashFlowKpiOutflow => 'Cash spending';

  @override
  String get cashFlowKpiNet => 'Operating net';

  @override
  String get cashFlowIncomeExpenseTitle => 'Income vs expense';

  @override
  String get cashFlowNetTrendTitle => 'Net cash-flow trend';

  @override
  String get cashFlowCategoryTitle => 'Category mix';

  @override
  String get cashFlowCategoryIncome => 'Income sources';

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
  String get recurringFilterActive => 'Active';

  @override
  String get recurringFilterPaused => 'Paused';

  @override
  String get recurringPausedEmptyTitle => 'No paused rules';

  @override
  String get recurringPausedEmptyBody =>
      'Paused and completed rules remain available here.';

  @override
  String get recurringPausedBadge => 'Paused';

  @override
  String get recurringCompletedBadge => 'Completed';

  @override
  String get recurringEmptyCta => 'Add rule';

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
  String get recurringActionEnable => 'Resume';

  @override
  String get recurringActionEnableHint => 'Start generating entries again';

  @override
  String get recurringActionDeleteHint => 'Remove this rule permanently';

  @override
  String get recurringDeleteTitle => 'Delete rule?';

  @override
  String get recurringDeleteBody =>
      'This recurring rule will be removed. You can undo it from the confirmation message.';

  @override
  String get recurringDisabled => 'Rule disabled';

  @override
  String get recurringEnabled => 'Rule resumed';

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
  String get recurringFormDetailsTitle => 'More options';

  @override
  String get recurringFormDetailsSummary => 'Interval, end date & note';

  @override
  String get recurringFormDetailsConfigured => 'Custom options configured';

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
  String get recurringValidationUntilBeforeStart =>
      'The end date must include at least one scheduled occurrence';

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
  String get dividendCenterMetricTtmNet => 'TTM after tax';

  @override
  String dividendCenterMetricTtmNetCaption(String ratio) {
    return 'Kept $ratio after withholding';
  }

  @override
  String get dividendCenterMetricYoy => 'YoY same period';

  @override
  String get dividendCenterMetricWithholding => 'Withholding tax';

  @override
  String get dividendCenterPolicyTitle => 'Dividend income watch';

  @override
  String dividendCenterPolicyBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings\' recorded dividend cash fell vs the prior year',
      one: '1 holding\'s recorded dividend cash fell vs the prior year',
    );
    return '$_temp0';
  }

  @override
  String get dividendCenterPolicySeverityWarning => 'Warning';

  @override
  String get dividendCenterPolicySeverityCritical => 'Critical';

  @override
  String dividendCenterPolicyDropLine(String percent) {
    return 'Down $percent%';
  }

  @override
  String get dividendResilienceTitle => 'Historical dividend resilience';

  @override
  String dividendResilienceConfidence(String confidence) {
    return '$confidence confidence';
  }

  @override
  String get dividendResilienceConfidenceHigh => 'High';

  @override
  String get dividendResilienceConfidenceMedium => 'Medium';

  @override
  String get dividendResilienceConfidenceLow => 'Low';

  @override
  String get dividendResilienceNoCoverage => 'No recorded history available.';

  @override
  String dividendResilienceCoverage(
    String start,
    String end,
    int months,
    int recordedMonths,
  ) {
    return '$start–$end · $months observed months · $recordedMonths payout months recorded';
  }

  @override
  String dividendResilienceCadenceCoverage(
    int expected,
    int missing,
    int irregular,
  ) {
    return 'Cadence check: $expected expected payments · $missing possibly missing · $irregular irregular assets';
  }

  @override
  String get dividendResilienceNetSeries => 'After tax';

  @override
  String get dividendResilienceChartLabel =>
      'Rolling twelve-month gross and after-tax dividend income';

  @override
  String get dividendResilienceIncomeCagr => 'After-tax income CAGR';

  @override
  String get dividendResilienceMaxDrawdown => 'Max income decline';

  @override
  String get dividendResilienceLargestSource => 'Largest income source';

  @override
  String get dividendResilienceRetention => 'After-tax retention';

  @override
  String get dividendResilienceNotRecovered => 'Not yet recovered';

  @override
  String dividendResilienceRecoveredIn(int months) {
    return 'Recovered in $months months';
  }

  @override
  String get dividendResilienceAttributionTitle =>
      'What changed vs the prior 12 months';

  @override
  String get dividendResilienceAttributionHint =>
      'Recorded cash is separated only where the ledger has enough per-share and FX evidence.';

  @override
  String dividendResilienceAttributionSplit(
    String holding,
    String unit,
    String fx,
  ) {
    return 'Holding $holding · per share $unit · FX $fx';
  }

  @override
  String dividendResilienceAttributionCombined(String local, String fx) {
    return 'Holding/per-share $local · FX $fx';
  }

  @override
  String get dividendResilienceDriverHolding => 'Main driver: holding quantity';

  @override
  String get dividendResilienceDriverUnitDividend =>
      'Main driver: dividend per share';

  @override
  String get dividendResilienceDriverFx => 'Main driver: exchange rate';

  @override
  String get dividendResilienceDriverCombined =>
      'Holding and per-share effects are combined';

  @override
  String dividendResilienceMethodology(int matchedPercent, int excludedCount) {
    return 'Based on your recorded ledger, not a backtest. $matchedPercent% of attributed entries have per-share evidence; $excludedCount entries were excluded for missing FX.';
  }

  @override
  String get financialInboxEvidencePrimaryDriver => 'Primary change driver';

  @override
  String get financialInboxEvidenceUnitDividend =>
      'Per-share evidence available';

  @override
  String get dividendCenterHoldingRanking => 'Holding ranking';

  @override
  String get dividendCenterHistoryTimeline => 'History timeline';

  @override
  String get dividendCenterGross => 'Gross';

  @override
  String get dividendCenterWithholding => 'Tax';

  @override
  String dividendCenterHistoryShowAll(int count) {
    return 'Show all $count months';
  }

  @override
  String get dividendCenterHistoryShowLess => 'Show recent months';

  @override
  String get dividendCenterRankingShare => 'Share';

  @override
  String get dividendCenterRankingYieldOnCost => 'Yield on cost';

  @override
  String get dividendCenterRankingNetYieldOnCost => 'Net yield on cost';

  @override
  String get dividendCenterRankingWithholding => 'Tax';

  @override
  String get dividendCenterForecastTitle => 'Next 12 months';

  @override
  String get dividendCenterForecastUnavailable =>
      'Not enough history or declared payments to forecast yet.';

  @override
  String dividendCenterForecastHistoricalError(String error, int count) {
    return '90-day historical error $error across $count reviews';
  }

  @override
  String dividendCenterForecastFxIncomplete(String currencies) {
    return 'Missing $currencies rates';
  }

  @override
  String dividendCenterFxIncomplete(int count, String currencies) {
    return '$count dividend entries were excluded because $currencies rates are missing.';
  }

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
    return 'Delete the dividend for $asset? You can undo it from the confirmation message.';
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
  String get portfolioAllHoldings => 'All holdings';

  @override
  String get portfolioUnassigned => 'Unassigned';

  @override
  String get portfolioManageTitle => 'Portfolio settings';

  @override
  String get portfolioCreateTitle => 'New portfolio';

  @override
  String get portfolioEditTitle => 'Edit portfolio';

  @override
  String get portfolioNameLabel => 'Portfolio name';

  @override
  String get portfolioNameRequired => 'Enter a portfolio name.';

  @override
  String get portfolioStrategyLabel => 'Strategy';

  @override
  String get portfolioCreateApproachTitle => 'Choose an approach';

  @override
  String get portfolioCreateApproachHint =>
      'Start with a clear default. You can refine allocation later.';

  @override
  String get portfolioCreateRecommendedHint =>
      'Recommended for a diversified long-term core';

  @override
  String get portfolioCreateCustomizableHint =>
      'A focused starting point you can customize later';

  @override
  String get portfolioStrategyIndexCore => 'Index core';

  @override
  String get portfolioStrategyDividendIncome => 'Dividend income';

  @override
  String get portfolioStrategyOptionsIncome => 'Options income';

  @override
  String get portfolioStrategyIncome => 'Dividend income';

  @override
  String get portfolioStrategyGrowth => 'Growth';

  @override
  String get portfolioStrategyPreservation => 'Capital preservation';

  @override
  String get portfolioStrategyGoalLinked => 'Goal linked';

  @override
  String get portfolioStrategyCustom => 'Custom';

  @override
  String get portfolioStrategyCustomCreateAction => 'Create strategy type';

  @override
  String get portfolioStrategyCustomNameLabel => 'Strategy type name';

  @override
  String get portfolioStrategyCapitalRoleLabel => 'Capital role';

  @override
  String get portfolioStrategyCapitalOwner => 'Owns a capital allocation';

  @override
  String get portfolioStrategyCapitalOverlay =>
      'Overlay without a capital weight';

  @override
  String get portfolioStrategyDefaultAssetLabel => 'Default asset category';

  @override
  String get portfolioAnnualIncomeTargetLabel =>
      'Annual income target (optional)';

  @override
  String get portfolioNoPortfolios =>
      'Create a portfolio to classify holdings by purpose.';

  @override
  String get portfolioAssignLotsTitle => 'Include positions';

  @override
  String get portfolioAssignLotsSubtitle =>
      'Choose purchase lots to include in a portfolio sleeve.';

  @override
  String get portfolioAssignCashTitle => 'Include cash';

  @override
  String get portfolioAssignCashSubtitle =>
      'Reserve cash from an asset account for one sleeve.';

  @override
  String get portfolioAssignCashAction => 'Include cash';

  @override
  String get portfolioCashAssignmentsTitle => 'Included cash';

  @override
  String get portfolioCashAccountLabel => 'Asset account';

  @override
  String get portfolioCashAmountLabel => 'Assigned amount';

  @override
  String get portfolioCashAmountInvalid => 'Enter an amount greater than zero.';

  @override
  String get portfolioCashNoAccounts =>
      'Create an asset account before assigning cash.';

  @override
  String portfolioCashAssignmentSummary(
    String amount,
    String currency,
    String group,
  ) {
    return '$amount $currency · $group';
  }

  @override
  String get portfolioAssignmentSaved => 'Included assets saved.';

  @override
  String get portfolioStudioTitle => 'Portfolio studio';

  @override
  String get portfolioStudioNotFound => 'This portfolio no longer exists.';

  @override
  String get portfolioStudioPlanTitle => 'Investment plan';

  @override
  String get portfolioStudioPlanHint =>
      'Review targets and drift here, then open a portfolio to adjust sleeves, assets, and rules.';

  @override
  String get portfolioStudioPlanEmptyHint =>
      'Create your first portfolio to define how capital should be used and rebalanced.';

  @override
  String get portfolioStudioPlanTargetLabel => 'Plan target';

  @override
  String portfolioStudioTargetSummary(String target, int count) {
    return '$target% plan target · $count sleeves';
  }

  @override
  String get portfolioStudioConfiguredStatus => 'Configured';

  @override
  String get portfolioStudioSleevesMetric => 'Sleeves';

  @override
  String get portfolioStudioAssetsMetric => 'Included assets';

  @override
  String get portfolioStudioRulesMetric => 'Rules';

  @override
  String get portfolioStudioRebalanceAction => 'Check rebalance';

  @override
  String get portfolioStudioOverviewTab => 'Overview';

  @override
  String get portfolioStudioStructureTab => 'Structure';

  @override
  String get portfolioStudioAssetsTab => 'Assets';

  @override
  String get portfolioStudioRulesTab => 'Rules';

  @override
  String get portfolioStudioConfigurationTitle => 'Portfolio setup';

  @override
  String get portfolioStudioConfigurationHint =>
      'Open only the area you want to adjust.';

  @override
  String portfolioStudioSleeveCount(int count) {
    return '$count strategies';
  }

  @override
  String portfolioStudioIncludedAssetCount(int count) {
    return '$count included assets';
  }

  @override
  String portfolioStudioRuleCount(int count) {
    return '$count optional rules';
  }

  @override
  String get portfolioStudioAllocationTitle => 'Capital path';

  @override
  String get portfolioStudioAllocationHint =>
      'Plan → portfolio → sleeve → asset target, configured in one path.';

  @override
  String get portfolioStudioNextActionTitle => 'Next step';

  @override
  String get portfolioStudioNextActionHint =>
      'Adjust sleeve weights together and always keep the total at 100%.';

  @override
  String get portfolioStudioStructureTitle => 'Strategy sleeves';

  @override
  String get portfolioStudioStructureHint =>
      'Each sleeve owns a capital target and its internal asset allocation.';

  @override
  String portfolioStudioSleeveSummary(String target, int count, String policy) {
    return '$target% target · $count asset targets · $policy';
  }

  @override
  String get portfolioStudioIncludedAssetsTitle => 'Included assets';

  @override
  String get portfolioStudioIncludedAssetsHint =>
      'Choose positions and cash for this portfolio and the sleeve that owns them.';

  @override
  String get portfolioStudioAssetTargetsHint =>
      'The asset classes and specific securities planned inside each sleeve.';

  @override
  String get portfolioStudioNoIncludedAssets =>
      'No positions or cash are included yet.';

  @override
  String get portfolioStudioIncludedPositionLabel => 'Position lot';

  @override
  String get portfolioStudioIncludePositionAction => 'Include positions';

  @override
  String get portfolioStudioIncludeCashAction => 'Include cash';

  @override
  String get portfolioStudioAddAssetsAction => 'Add assets';

  @override
  String get portfolioStudioAddAssetsHint =>
      'Choose a position or cash balance to include.';

  @override
  String get portfolioStudioRulesTitle => 'Rules and enhancements';

  @override
  String get portfolioStudioRulesHint =>
      'Rules attach to a sleeve without owning a separate capital weight.';

  @override
  String get portfolioStudioNoRules =>
      'No extra rules. Sleeves still run with their own targets.';

  @override
  String portfolioStudioAssetTargetCount(int count) {
    return '$count asset targets';
  }

  @override
  String get portfolioTrendTitle => 'Portfolio trend';

  @override
  String get portfolioTrendHint =>
      'Track value separately from capital flows, then switch to cash-flow-adjusted performance.';

  @override
  String get portfolioTrendMarketValue => 'Market value';

  @override
  String get portfolioTrendPerformance => 'Performance';

  @override
  String get portfolioTrendCurrentValue => 'Current value';

  @override
  String get portfolioTrendPeriodPerformance => 'Period return';

  @override
  String get portfolioTrendNetFlow => 'Net capital flow';

  @override
  String get portfolioTrendAwaitingData =>
      'A trend appears after assets or cash are included.';

  @override
  String get portfolioTrendEstimatedDisclosure =>
      'Some points use estimated prices or incomplete FX history.';

  @override
  String get portfolioTrendChartSemantics =>
      'Portfolio value and performance trend';

  @override
  String get portfolioTrendMonthSemantics =>
      'Portfolio performance over the last month';

  @override
  String get portfolioTrendRangeYtd => 'YTD';

  @override
  String get rebalancePortfoliosTitle => 'Portfolio allocation';

  @override
  String get rebalanceCapitalTreeHint =>
      'Portfolio transfers → strategy allocation → assets inside each strategy';

  @override
  String rebalancePortfolioWeightPair(String actual, String target) {
    return 'Actual $actual · target $target';
  }

  @override
  String get rebalancePortfolioTransfersTitle => 'Inter-portfolio transfers';

  @override
  String get rebalanceGroupsTitle => 'Rebalance groups';

  @override
  String rebalanceGroupWeight(String percent) {
    return 'Target $percent';
  }

  @override
  String get rebalanceGroupTransfersTitle => 'Capital transfers';

  @override
  String rebalanceGroupTransfer(String from, String to, String amount) {
    return '$from → $to: $amount';
  }

  @override
  String get portfolioGroupsSectionTitle => 'Strategy sleeves';

  @override
  String get portfolioAllocationSectionTitle => 'Portfolio capital allocation';

  @override
  String portfolioAllocationWeightSummary(String weight) {
    return 'Universe target $weight%';
  }

  @override
  String get portfolioAllocationEditTitle => 'Edit portfolio allocation';

  @override
  String get portfolioAllocationPlanSubtitle =>
      'Set every portfolio together. The total must equal 100%.';

  @override
  String get portfolioAllocationTargetWeightLabel => 'Universe target (%)';

  @override
  String get portfolioAllocationSingleTargetHint =>
      'A universe with one portfolio must remain at 100%. Add another portfolio before changing its target.';

  @override
  String get portfolioGroupAddAction => 'Add sleeve';

  @override
  String get portfolioStrategyAllocationEditTitle => 'Edit sleeve allocation';

  @override
  String get portfolioStrategyAllocationPlanSubtitle =>
      'Set every sleeve together. The total must equal 100%.';

  @override
  String get portfolioOverlayAddAction => 'Add rule';

  @override
  String get portfolioOverlayNoTemplates =>
      'Create a rule type before attaching one to a sleeve.';

  @override
  String get portfolioOverlayHostGroupLabel => 'Apply to sleeve';

  @override
  String get portfolioOverlaySectionTitle => 'Rules and enhancements';

  @override
  String get portfolioOverlayDeleteAction => 'Delete rule';

  @override
  String get portfolioOverlayDeleteConfirmation =>
      'This rule will be removed from its sleeve. Included assets and the accounting ledger will not change.';

  @override
  String get portfolioGroupEditTitle => 'Edit sleeve';

  @override
  String get portfolioGroupNameLabel => 'Sleeve name';

  @override
  String get portfolioStrategyDeleteAction => 'Delete sleeve';

  @override
  String get portfolioStrategyDeleteLastBlocked =>
      'A portfolio must keep at least one capital strategy. Delete the portfolio instead if it is no longer needed.';

  @override
  String get portfolioStrategyDeleteFailed =>
      'Couldn\'t delete the strategy. Try again.';

  @override
  String portfolioStrategyDeleteTransferDescription(
    String weight,
    int assignmentCount,
    int overlayCount,
  ) {
    return 'The $weight% target and $assignmentCount asset or cash assignments will move to the selected strategy. $overlayCount attached overlays will be deleted.';
  }

  @override
  String get portfolioGroupTargetWeightLabel => 'Portfolio target (%)';

  @override
  String get portfolioGroupSingleTargetHint =>
      'A portfolio with one strategy must remain at 100%. Add another strategy before changing its target.';

  @override
  String get portfolioGroupDriftBandLabel => 'Allowed deviation (%)';

  @override
  String get portfolioGroupTransferPolicyLabel => 'Capital transfer rule';

  @override
  String get portfolioGroupTransferBidirectional => 'Free transfer';

  @override
  String get portfolioGroupTransferInflowsOnly => 'Receive funds only';

  @override
  String get portfolioGroupTransferIsolated => 'Manage independently';

  @override
  String get capitalAllocationTotalLabel => 'Total allocation';

  @override
  String get capitalAllocationEditAction => 'Edit';

  @override
  String capitalAllocationTotalHint(String total) {
    return 'Allocation is $total%. Adjust all items until the total is 100%.';
  }

  @override
  String get capitalAllocationAdvancedAction => 'Funding rules and tolerance';

  @override
  String get capitalAllocationBalanceEvenlyAction => 'Distribute evenly';

  @override
  String get capitalAllocationFillRemainderAction => 'Fill remainder';

  @override
  String get capitalAllocationToleranceLabel => 'Allowed deviation (%)';

  @override
  String get capitalAllocationRuleLabel => 'Funding rule';

  @override
  String get capitalAllocationRuleBidirectional => 'Flexible transfers';

  @override
  String get capitalAllocationRuleBidirectionalDescription =>
      'Capital may move into or out of this item.';

  @override
  String get capitalAllocationRuleInflowsOnly => 'Receive funds only';

  @override
  String get capitalAllocationRuleInflowsOnlyDescription =>
      'Capital may move in but existing capital will not be moved out.';

  @override
  String get capitalAllocationRuleIsolated => 'Manage independently';

  @override
  String get capitalAllocationRuleIsolatedDescription =>
      'No automatic capital transfers in either direction.';

  @override
  String get capitalAllocationSaveFailed =>
      'Could not save the allocation plan. Try again.';

  @override
  String portfolioGroupWeightSummary(String weight, String policy) {
    return '$weight% target · $policy';
  }

  @override
  String get portfolioGroupNoTemplates =>
      'No capital strategy types are available.';

  @override
  String get portfolioSaveFailed => 'Couldn\'t save the portfolio. Try again.';

  @override
  String get portfolioDeleteFailed =>
      'Couldn\'t delete the portfolio. Try again.';

  @override
  String get portfolioDeleteAction => 'Delete portfolio';

  @override
  String get portfolioDeleteConfirmation =>
      'Asset and cash assignments will be cleared, and strategy configuration will also be deleted. The accounting ledger will not change.';

  @override
  String portfolioDeleteTransferDescription(
    String weight,
    int assignmentCount,
  ) {
    return 'The $weight% target and $assignmentCount asset or cash assignments will move to the selected strategy. The original portfolio and its strategy configuration will be deleted.';
  }

  @override
  String get portfolioRemovalTransferHint =>
      'Targets and assignments move in one transaction. The accounting ledger does not change.';

  @override
  String get portfolioRemovalTransferTargetLabel => 'Transfer to';

  @override
  String get portfolioRemovalTransferAction => 'Transfer and delete';

  @override
  String portfolioStrategyCountSummary(String strategy, int count) {
    return '$strategy · $count capital strategies';
  }

  @override
  String portfolioLotsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lots',
      one: '1 lot',
    );
    return '$_temp0';
  }

  @override
  String get portfolioScopedReturnUnavailable =>
      'Portfolio return starts after assignment history is recorded.';

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
  String get portfolioHubCostBasisLabel => 'Cost basis';

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
  String get portfolioHubShowAllPositions => 'Show all positions';

  @override
  String get portfolioHubShowFewerPositions => 'Show fewer positions';

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
  String get portfolioHubEnginesTitle => 'Insights';

  @override
  String get portfolioHubSectionPositions => 'Positions';

  @override
  String get portfolioHubSectionAllocation => 'Allocation';

  @override
  String get portfolioHubSectionInsights => 'Insights';

  @override
  String get portfolioHubConcentrationTitle => 'Concentration risk';

  @override
  String portfolioHubConcentrationSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count positions exceed your thresholds',
      one: '1 position exceeds your thresholds',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubConcentrationDimensionAsset => 'Asset';

  @override
  String get portfolioHubConcentrationDimensionSector => 'Sector';

  @override
  String get portfolioHubConcentrationDimensionRegion => 'Region';

  @override
  String get portfolioHubConcentrationDimensionCurrency => 'Currency';

  @override
  String get portfolioHubConcentrationSeverityWarning => 'Warning';

  @override
  String get portfolioHubConcentrationSeverityCritical => 'Critical';

  @override
  String portfolioHubConcentrationWeightLine(String weight, String threshold) {
    return '$weight% · cap $threshold%';
  }

  @override
  String get portfolioHubConcentrationRebalanceCta => 'Review rebalance plan';

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
  String get dcaSimulatorSymbolHint => 'VOO or VOO:60, QQQ:40';

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
  String get dcaSimulatorDraftAction => 'Save recurring plan';

  @override
  String get dcaPlanSectionTitle => 'Recurring plans';

  @override
  String get dcaPlanEmpty =>
      'Run a simulation, then save it as a recurring plan.';

  @override
  String get dcaPlanSaved => 'Recurring investment plan saved';

  @override
  String get dcaPlanActive => 'Active';

  @override
  String get dcaPlanPaused => 'Paused';

  @override
  String dcaPlanNextDue(String date, String amount, String currency) {
    return 'Next $date · $amount $currency';
  }

  @override
  String get dcaPlanExecuteNow => 'Record contribution';

  @override
  String get dcaPlanPause => 'Pause';

  @override
  String get dcaPlanResume => 'Resume';

  @override
  String get dcaPlanDeleteTitle => 'Delete recurring plan?';

  @override
  String get dcaPlanDeleteBody =>
      'This removes the schedule and its future reminders. Recorded trades are kept.';

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
  String get dashboardActivityPreviewTitle => 'Recent activity';

  @override
  String get dashboardActivityPreviewViewAll => 'View all';

  @override
  String get homeGreetingMorning => 'Good morning';

  @override
  String get homeGreetingAfternoon => 'Good afternoon';

  @override
  String get homeGreetingEvening => 'Good evening';

  @override
  String get homeGreetingNight => 'Good night';

  @override
  String get homeTodayBriefSubtitle => 'Today\'s financial overview';

  @override
  String get lifeBriefSubtitle => 'See what needs your attention today';

  @override
  String get lifeStageTitle => 'LifeOS';

  @override
  String get lifeHeroMetricAttention => 'To do';

  @override
  String get lifeHeroMetricSignals => 'New updates';

  @override
  String get lifeHeroMetricClear => 'Today';

  @override
  String get lifeHeroHeadlineCalm => 'Nothing needs your attention today';

  @override
  String get lifeHeroHeadlineSignals => 'New updates across your domains';

  @override
  String get lifeHeroHeadlineAttention => 'Some items need priority attention';

  @override
  String lifeHeroBody(int count) {
    return 'Important changes across $count active domains';
  }

  @override
  String lifeStickyAttention(int count) {
    return '$count to do';
  }

  @override
  String lifeStickySignals(int count) {
    return '$count new updates';
  }

  @override
  String get lifeStickyCalm => 'Nothing to do';

  @override
  String get lifeReviewTitle => 'Review';

  @override
  String get lifeReviewHeadline => 'Close the loop';

  @override
  String get lifeReviewSubtitle =>
      'Revisit decisions, assumptions, and follow-through in one place.';

  @override
  String get lifeReviewPickerSubtitle => 'Choose what you want to review.';

  @override
  String get lifeTimelineTitle => 'Latest updates';

  @override
  String get lifeTimelinePriorityTitle => 'Priority attention';

  @override
  String get lifeTimelineEmptyTitle => 'Quiet day';

  @override
  String get lifeTimelineEmpty =>
      'You can still open a domain to view its details.';

  @override
  String lifeTimelineShowMore(int count) {
    return 'Show $count more';
  }

  @override
  String get lifeTimelineShowLess => 'Show less';

  @override
  String get lifeDomainFinance => 'Finance';

  @override
  String get lifeDomainHealth => 'Health';

  @override
  String get lifeDomainKnowledge => 'Knowledge';

  @override
  String get lifeDomainExecution => 'Execution';

  @override
  String get lifeNavLabel => 'Overview';

  @override
  String lifeSignalFinanceDayTitle(String count) {
    return '$count finance entries today';
  }

  @override
  String lifeSignalFinanceDaySubtitle(String expense, String income) {
    return '$expense expenses · $income income';
  }

  @override
  String get lifeSignalFinanceBudgetStrainedTitle =>
      'Monthly budget needs attention';

  @override
  String get lifeSignalFinanceBudgetOverTitle => 'Monthly budget exceeded';

  @override
  String lifeSignalFinanceBudgetSubtitle(String periodMonth) {
    return '$periodMonth budget usage';
  }

  @override
  String get lifeSignalRecoveryTitle => 'Recovery needs attention';

  @override
  String get lifeSignalRecoverySubtitle =>
      'Your recovery status has a change worth reviewing';

  @override
  String lifeSignalExecBlockedTitle(String count) {
    return '$count blocked actions';
  }

  @override
  String get lifeSignalExecBlockedSubtitle =>
      'Some actions have not made progress';

  @override
  String lifeSignalExecDueTitle(String count) {
    return '$count due actions';
  }

  @override
  String get lifeSignalExecDueSubtitle => 'These actions are planned for today';

  @override
  String lifeSignalKnowledgeTitle(String count) {
    return '$count notes in inbox';
  }

  @override
  String get lifeSignalKnowledgeSubtitle =>
      'Notes are waiting to be organized or reviewed';

  @override
  String get lifeSignalAgentTitle => 'New financial insight';

  @override
  String get lifeSignalAgentSubtitle =>
      'Your financial brief has a new analysis';

  @override
  String get agentArtifactDetailTitle => 'Insight details';

  @override
  String get agentArtifactMissingTitle => 'Insight unavailable';

  @override
  String get agentArtifactMissingBody =>
      'This result may have expired, been dismissed, or belong to a domain that is not active.';

  @override
  String get lifeSignalDetailTitle => 'Update details';

  @override
  String get lifeSignalEvidenceTitle => 'Why this appeared';

  @override
  String lifeSignalRecoveryScoreEvidence(String score) {
    return 'Recovery score: $score';
  }

  @override
  String get lifeSignalCreateAction => 'Create action';

  @override
  String lifeSignalCreateActionFor(String update) {
    return 'Create action for $update';
  }

  @override
  String get lifeSignalEnableExecution => 'Enable ExecutionOS';

  @override
  String get lifeSignalOpenSource => 'Open source';

  @override
  String get lifeSignalActionConfirmTitle => 'Create this action?';

  @override
  String lifeSignalActionConfirmBody(String title, String source) {
    return '$title\n\nSource: $source';
  }

  @override
  String get lifeSignalActionCreated =>
      'Action created with its source information attached.';

  @override
  String lifeSignalActionFailed(String error) {
    return 'Could not create action: $error';
  }

  @override
  String executionOutcomeSignalCleared(String source) {
    return '$source: signal no longer detected';
  }

  @override
  String executionOutcomeSignalStillActive(String source) {
    return '$source: signal still detected';
  }

  @override
  String get lifeSignalOpenExecution => 'Open Execution';

  @override
  String get lifeSignalActionReviewFinance => 'View today\'s finance activity';

  @override
  String get lifeSignalActionReviewBudget => 'View this month\'s budget';

  @override
  String get lifeSignalActionProtectRecovery => 'Protect recovery today';

  @override
  String get lifeSignalActionReviewKnowledge => 'Review the Knowledge inbox';

  @override
  String get lifeSignalActionReviewAgent => 'View the latest financial insight';

  @override
  String lifeSignalActionNote(String source, String detail) {
    return 'From $source: $detail';
  }

  @override
  String get financeAgentResultsLoading => 'Loading financial insights';

  @override
  String get financeAgentResultsLoadingBody =>
      'Recent financial reviews are loading.';

  @override
  String get financeAgentResultsEmptyTitle => 'No financial insights yet';

  @override
  String get financeAgentResultsEmptyBody =>
      'New planning review results will appear here.';

  @override
  String get financeAgentResultsErrorTitle =>
      'Financial insights could not load';

  @override
  String financeAgentResultsErrorBody(String error) {
    return '$error';
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
  String get activityEntryDetailAiExplanation => 'Entry insight';

  @override
  String get activityEntryDetailNoExplanation =>
      'No insight available for this entry.';

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
  String get activityActionIncomeHint =>
      'Record salary, dividend or other income';

  @override
  String get activityActionTradeHint => 'Buy or sell a security';

  @override
  String get activityActionTransferHint => 'Move funds between two accounts';

  @override
  String get activityActionConvertHint =>
      'Exchange currency inside one account';

  @override
  String get accountsActionsTitle => 'Add wealth item';

  @override
  String get wealthActionPanelSubtitle =>
      'Choose what you want to add to your net worth.';

  @override
  String get wealthActionPanelAssetHint =>
      'Cash, deposits, investments, or physical assets';

  @override
  String get wealthActionPanelAssetSubtitle =>
      'Choose the type that best fits this asset.';

  @override
  String get wealthActionPanelAccountsGroup => 'Accounts';

  @override
  String get wealthActionPanelFinancialGroup => 'Deposits & products';

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
  String get superFabIncome => 'Income';

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
      'Choose two accounts with different currencies, then confirm the amount sent and received.';

  @override
  String get homeAppBarTitle => 'Overview';

  @override
  String get homeAiAssistantTooltip => 'AI assistant';

  @override
  String get homeNetWorthTitle => 'Net Worth';

  @override
  String get homeQuickAddAccount => 'Add account';

  @override
  String get homeQuickRecordEntry => 'Record entry';

  @override
  String get homeQuickImport => 'Import statements';

  @override
  String get financePrivacyHideAmountsTooltip => 'Hide amounts';

  @override
  String get financePrivacyShowAmountsTooltip => 'Show amounts';

  @override
  String homeNetWorthSubtitle(String currency) {
    return 'Add an account or import data to see net worth in $currency';
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
  String get liabilityFieldPayerAccount => 'Payer account';

  @override
  String get liabilityPayerAccountHint =>
      'Scheduled repayments will be recorded against this account.';

  @override
  String get liabilityPayerAccountEmpty =>
      'No eligible payment account is available. Create a cash or bank account first.';

  @override
  String get liabilityPayerAccountRequired =>
      'Choose a payer account before saving.';

  @override
  String get liabilityFieldStatementDay => 'Statement day';

  @override
  String get liabilityFieldPaymentDueDay => 'Payment due day';

  @override
  String get liabilityFieldNote => 'Note';

  @override
  String get liabilityDetailsTitle => 'Schedule details';

  @override
  String get liabilityDetailsLoanSummary => 'Rate type, start date & repayment';

  @override
  String get liabilityDetailsCardSummary => 'Billing dates & note';

  @override
  String get liabilityEditAction => 'Edit liability';

  @override
  String get liabilityEditMetadataOnlyHint =>
      'Name, payer account and note can be edited here. Principal, rate and term stay locked because they drive the repayment schedule.';

  @override
  String get liabilitySaveAction => 'Save';

  @override
  String get liabilityValidationRequired => 'Required';

  @override
  String get liabilityValidationPositive => 'Must be greater than zero';

  @override
  String get liabilityValidationDayOfMonth => 'Must be 1–31';

  @override
  String liabilityValidationAccountCurrency(String currency) {
    return 'Use the payer account currency: $currency';
  }

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
  String liabilityPaymentSheetTitle(int period) {
    return 'Record period $period payment';
  }

  @override
  String liabilityPaymentSheetAmount(String amount) {
    return 'Payment amount · $amount';
  }

  @override
  String get liabilityPaymentSheetDate => 'Payment date';

  @override
  String get liabilityPaymentSheetDateHint =>
      'Choose the date the money left the payer account.';

  @override
  String get liabilityPaymentSheetSubmit => 'Record payment';

  @override
  String get liabilityScheduleMarkPaidNoAccount =>
      'Assign a payer account before marking periods paid.';

  @override
  String liabilityScheduleUndoConfirmTitle(int period) {
    return 'Undo payment for period $period?';
  }

  @override
  String get liabilityScheduleUndoConfirmBody =>
      'This removes the linked ledger transaction and returns the period to pending.';

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
  String get physicalAssetDetailsTitle => 'Asset details';

  @override
  String get physicalAssetVehicleDetailsSummary => 'Valuation & depreciation';

  @override
  String get physicalAssetRealEstateDetailsSummary =>
      'Address, valuation & linked loan';

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
      'Valuation history will be marked as deleted. Devices that synced previously may still retain a recoverable copy.';

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
  String get fxRatesSyncCompleted => 'Rates updated';

  @override
  String fxRatesSyncFailed(String error) {
    return 'Could not sync rates: $error';
  }

  @override
  String fxRatesSyncPartial(int synced, int total, String error) {
    return 'Updated $synced of $total currency pairs. $error';
  }

  @override
  String get fxRatesOverviewTitle => 'Currency monitor';

  @override
  String get fxRatesOverviewSubtitle =>
      'A quiet view of the rates used across your wealth history.';

  @override
  String get fxRatesStatusSyncing => 'Syncing';

  @override
  String get fxRatesStatusFailed => 'Offline';

  @override
  String get fxRatesStatusReady => 'Up to date';

  @override
  String get fxRatesStatusLocal => 'Local history';

  @override
  String get fxRatesTrackedPairsLabel => 'Tracked pairs';

  @override
  String get fxRatesBaseCurrencyLabel => 'Base currency';

  @override
  String get fxRatesLastUpdatedLabel => 'Last updated';

  @override
  String get fxRatesLatestObservation => 'Latest observation';

  @override
  String get fxRatesHistoryTitle => 'History';

  @override
  String get fxRatesRange7D => '7D';

  @override
  String get fxRatesRange30D => '30D';

  @override
  String get fxRatesRange90D => '90D';

  @override
  String get fxRatesRangeAll => 'All';

  @override
  String get fxRatesHistoryEntries => 'Observations';

  @override
  String get fxRatesViewDetails => 'View details';

  @override
  String get fxRatesNotEnoughHistory =>
      'More observations will reveal a trend.';

  @override
  String get fxRatesRangeHint =>
      'Showing the selected window. Switch to All for the full history.';

  @override
  String fxRatesAsOfValue(String date) {
    return 'As of $date';
  }

  @override
  String fxRatesPairsTracked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pairs',
      one: '1 pair',
      zero: 'No pairs',
    );
    return '$_temp0';
  }

  @override
  String fxRatesEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

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
  String get fxRatesDeleteConfirmTitle => 'Delete this FX rate?';

  @override
  String get fxRatesDeleteConfirmBody =>
      'This removes the recorded rate for this currency pair and date.';

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
  String dashboardValuationTrustMissingFx(int count, String currency) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings excluded — missing FX to $currency',
      one: '1 holding excluded — missing FX to $currency',
    );
    return '$_temp0';
  }

  @override
  String dashboardValuationTrustWarning(
    int staleCount,
    String quality,
    String asOf,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      staleCount,
      locale: localeName,
      other: '$staleCount stale holdings · $quality · as of $asOf',
      one: '1 stale holding · $quality · as of $asOf',
      zero: '$quality valuation · as of $asOf',
    );
    return '$_temp0';
  }

  @override
  String dashboardValuationTrustReady(String quality, String asOf) {
    return '$quality valuation · as of $asOf';
  }

  @override
  String get dashboardValuationTrustAction => 'Details';

  @override
  String get dashboardValuationTrustSheetTitle => 'Valuation confidence';

  @override
  String dashboardValuationTrustQuality(String quality) {
    return 'Quality: $quality';
  }

  @override
  String dashboardValuationTrustAsOf(String asOf) {
    return 'As of $asOf';
  }

  @override
  String dashboardValuationTrustStale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings have stale prices',
      one: '1 holding has a stale price',
    );
    return '$_temp0';
  }

  @override
  String get dashboardValuationQualityRealTime => 'Real-time';

  @override
  String get dashboardValuationQualityDelayed => 'Delayed';

  @override
  String get dashboardValuationQualityDailyClose => 'Daily close';

  @override
  String get dashboardValuationQualityManual => 'Manual';

  @override
  String get dashboardValuationQualityEstimated => 'Estimated';

  @override
  String get dashboardValuationQualityStale => 'Stale';

  @override
  String get settingsAboutTitle => 'About NaviWealth';

  @override
  String settingsAboutSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsAccentSeedTitle => 'Accent color';

  @override
  String get accentSeedCyan => 'Turquoise';

  @override
  String get accentSeedViolet => 'Violet';

  @override
  String get accentSeedIndigo => 'Indigo';

  @override
  String get settingsSurfaceStyleTitle => 'Surface style';

  @override
  String get surfaceStyleStandard => 'Standard';

  @override
  String get surfaceStyleOled => 'OLED black';

  @override
  String get surfaceStyleHighContrast => 'High contrast';

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
  String get commonRefresh => 'Refresh';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonSaved => 'Saved';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDeleted => 'Deleted';

  @override
  String get commonClose => 'Close';

  @override
  String commonRevealMore(int count) {
    return 'More · $count';
  }

  @override
  String get commonRevealLess => 'Show less';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonRequiredField => 'Enter a value.';

  @override
  String get commonInvalidNumber => 'Enter a valid number.';

  @override
  String get commonSafeErrorMessage =>
      'We couldn\'t complete that. Please try again.';

  @override
  String get shellMoreActions => 'More actions';

  @override
  String commonLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get commonLoadFailed => 'Couldn\'t load this view. Please try again.';

  @override
  String get commonSaveFailed => 'Couldn\'t save your changes. Try again.';

  @override
  String get commonDeleteFailed => 'Couldn\'t delete this item. Try again.';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonUndoSucceeded => 'Change undone';

  @override
  String get commonUndoFailed => 'Couldn\'t undo the change. Try again.';

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
    return 'Assistant: $query';
  }

  @override
  String get askAiResultLocalBadge => 'Local';

  @override
  String get askAiResultNoLocalMatch =>
      'Can\'t answer this here. Continue in the AI assistant for a full conversation.';

  @override
  String get askAiResultContinueInChat => 'Continue in AI assistant';

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
  String get commandPaletteOpenAi => 'Open assistant';

  @override
  String get navAskAi => 'Assistant';

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
  String nativeUpdateAvailable(String version) {
    return 'NaviWealth $version is available.';
  }

  @override
  String get nativeUpdateCheck => 'Check for updates';

  @override
  String get nativeUpdateChecking => 'Checking…';

  @override
  String get nativeUpdateUpToDate => 'You\'re up to date.';

  @override
  String get nativeUpdateCheckFailed =>
      'Couldn\'t check for updates. Please try again later.';

  @override
  String get nativeUpdateUnavailable =>
      'Updates are unavailable for this build.';

  @override
  String get nativeUpdateNotificationTitle => 'NaviWealth update available';

  @override
  String nativeUpdateNotificationBody(String version) {
    return 'Version $version is ready to install.';
  }

  @override
  String get nativeUpdateApply => 'Update';

  @override
  String get nativeUpdateDismiss => 'Later';

  @override
  String nativeUpdateDownloading(int percent) {
    return 'Downloading update ($percent%)';
  }

  @override
  String get nativeUpdateInstallPermission =>
      'Allow NaviWealth to install updates in Android settings, then tap Update again.';

  @override
  String get nativeUpdateVerificationFailed =>
      'The downloaded update failed integrity verification.';

  @override
  String get nativeUpdatePackageMismatch =>
      'The downloaded update is not a valid NaviWealth package.';

  @override
  String get nativeUpdateInstallFailed =>
      'Android could not start the update installer.';

  @override
  String get nativeUpdateDownloadFailed =>
      'Could not download the update. Please try again later.';

  @override
  String get nativeUpdateInstallStarted =>
      'Update downloaded. Confirm installation in Android.';

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
  String get authUpgradeRegisterHint =>
      'Create a new cloud account and sync your existing data';

  @override
  String get authUpgradeConnectHint =>
      'Sign in to an existing account (local data is kept separately)';

  @override
  String get authUpgradeRegisterSubmit => 'Create & Sync';

  @override
  String get authUpgradeConnectSubmit => 'Sign In & Sync';

  @override
  String get settingsDevicesTitle => 'Devices';

  @override
  String get settingsDevicesSubtitle =>
      'View signed-in devices and revoke access';

  @override
  String get settingsSwitchToLocalTitle => 'Switch to Local Mode';

  @override
  String get settingsSwitchToLocalSubtitle =>
      'Disable cloud sync while keeping data on this device';

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
  String get dashboardTrendMetricCurrent => 'Current';

  @override
  String get dashboardTrendMetricChange => 'Change';

  @override
  String get dashboardTrendMetricRange => 'Range';

  @override
  String get dashboardHeaderDeltaTodayLabel => 'Today';

  @override
  String get dashboardHeaderDeltaMonthLabel => 'MTD';

  @override
  String get dashboardHeaderDeltaYtdLabel => 'YTD';

  @override
  String get analyticsAppBarTitle => 'Analytics';

  @override
  String get analyticsOverviewNetWorth => 'Net worth';

  @override
  String get analyticsOverviewMonthlyChange => 'Month change';

  @override
  String get analyticsOverviewCashFlow => 'Cash flow';

  @override
  String get analyticsOverviewFireEta => 'FIRE ETA';

  @override
  String analyticsOverviewFireEtaMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String get analyticsOverviewFireNotConfigured => 'Not set';

  @override
  String get analyticsOverviewUnavailable => '—';

  @override
  String get analyticsCashFlowTrendTitle => 'Cash-flow trend';

  @override
  String get analyticsCashFlowTrendSubtitle =>
      'Net operating cash flow across the last six months.';

  @override
  String get analyticsCashFlowTrendNetSeries => 'Net cash flow';

  @override
  String get analyticsCashFlowTrendAverageNet => '6M avg net';

  @override
  String get analyticsCashFlowTrendInflow => 'This month inflow';

  @override
  String get analyticsCashFlowTrendOutflow => 'This month outflow';

  @override
  String get analyticsCashFlowTrendSemantic =>
      'Recent monthly net cash-flow bar chart';

  @override
  String get analyticsCashFlowTrendLoadError =>
      'Couldn\'t load cash-flow trend.';

  @override
  String get analyticsFireProgressTitle => 'FIRE progress';

  @override
  String get analyticsFireProgressSubtitle =>
      'Investable assets against your target and current runway.';

  @override
  String analyticsFireProgressPercent(String value) {
    return '$value of target';
  }

  @override
  String get analyticsFireProgressInvestable => 'Investable';

  @override
  String get analyticsFireProgressTarget => 'Target';

  @override
  String get analyticsFireProgressWithdrawalRate => 'Withdrawal';

  @override
  String get analyticsFireProgressCashRunway => 'Cash runway';

  @override
  String get analyticsFireProgressEta => 'ETA';

  @override
  String analyticsFireProgressMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String get analyticsFireProgressUnlimited => 'Unlimited';

  @override
  String get analyticsFireProgressNotConfiguredTitle =>
      'FIRE plan not configured';

  @override
  String get analyticsFireProgressNotConfiguredBody =>
      'Set a FIRE target to track progress and runway here.';

  @override
  String get analyticsFireProgressLoadError => 'Couldn\'t load FIRE progress.';

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
  String get fireDepthTitle => 'Resilience checks';

  @override
  String get fireDepthSubtitle => 'Automatic checks for the risks that matter';

  @override
  String fireHeroProgressLine(String progress, String current, String target) {
    return '$progress · $current of $target';
  }

  @override
  String get fireHeroNextStepLabel => 'Next step';

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
  String get fireBudgetNoDataTitle => 'Budget signal not available';

  @override
  String get fireBudgetNoDataDetail =>
      'Set a monthly budget to connect current spending pressure to this FIRE plan.';

  @override
  String get fireBudgetComfortableTitle => 'Budget supports the plan';

  @override
  String get fireBudgetComfortableDetail =>
      'This month’s spending is within the comfortable range.';

  @override
  String get fireBudgetStrainedTitle => 'Budget pressure is rising';

  @override
  String get fireBudgetStrainedDetail =>
      'Spending is near the monthly limit; protect the planned surplus.';

  @override
  String get fireBudgetOverTitle => 'Monthly budget exceeded';

  @override
  String get fireBudgetOverDetail =>
      'Current spending pressure may reduce the surplus assumed by this FIRE plan.';

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
      'Review monthly, quarterly, and annual snapshots. Metrics are calculated by rules; AI only explains the results.';

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
  String get rebalanceExecutionWorkspaceTitle => 'Execution';

  @override
  String get rebalanceExecutionResumeAction => 'Resume execution';

  @override
  String get rebalanceExecutionReplaceTitle => 'Replace active execution?';

  @override
  String get rebalanceExecutionReplaceBody =>
      'Your active execution was created from a different plan. Trades already recorded remain in the ledger. Undo from the old queue is permanently disabled when this plan starts.';

  @override
  String get rebalanceExecutionReplaceAction => 'Replace and continue';

  @override
  String rebalanceExecutionProgress(int done, int total) {
    return '$done of $total resolved';
  }

  @override
  String get rebalanceExecutionApplyAction => 'Apply';

  @override
  String get rebalanceExecutionUndoAction => 'Undo';

  @override
  String get rebalanceExecutionStopAction => 'Stop after current';

  @override
  String get rebalanceExecutionStoppedToast =>
      'Stopped after the current trade.';

  @override
  String get rebalanceExecutionCompletedToast =>
      'The batch completed successfully.';

  @override
  String rebalanceExecutionPartialToast(int completed, int failed) {
    return '$completed completed; $failed need attention.';
  }

  @override
  String rebalanceExecutionFailedToast(int failed) {
    return 'The batch stopped; $failed need attention.';
  }

  @override
  String get rebalanceExecutionRecoveryToast =>
      'The batch stopped because an item needs recovery.';

  @override
  String get rebalanceExecutionArchiveAction => 'Archive execution';

  @override
  String get rebalanceExecutionArchiveTitle => 'Archive this execution?';

  @override
  String get rebalanceExecutionArchiveBody =>
      'Archiving closes this queue. Trades already recorded remain in the ledger, and Undo from this queue is permanently disabled. Reviewed details and progress remain visible, but skipped and pending trades can no longer be changed.';

  @override
  String get rebalanceExecutionArchiveAppliedBody =>
      'Applied trades will not be undone. Undo them before archiving if you need to reverse their ledger entries.';

  @override
  String get rebalanceExecutionBusyLeaveBlocked =>
      'Finish or stop the current operation before leaving.';

  @override
  String get rebalanceExecutionReviewAction => 'Review';

  @override
  String get rebalanceExecutionAddPriceAction => 'Add price';

  @override
  String get rebalanceExecutionRetryApplyAction => 'Retry execution';

  @override
  String get rebalanceExecutionRetryUndoAction => 'Retry undo';

  @override
  String get rebalanceExecutionSkipAction => 'Skip';

  @override
  String get rebalanceExecutionReopenAction => 'Reopen';

  @override
  String get rebalanceExecutionNotFound =>
      'This execution is unavailable or belongs to another user.';

  @override
  String get rebalanceExecutionEmptyQueue =>
      'This plan has no trades to execute.';

  @override
  String get rebalanceExecutionEditorTitle => 'Review trade';

  @override
  String get rebalanceExecutionSaveReviewAction => 'Save review';

  @override
  String get rebalanceExecutionAssetLabel => 'Security';

  @override
  String get rebalanceExecutionCashAccountLabel => 'Cash account (optional)';

  @override
  String get rebalanceExecutionManualPriceHelper =>
      'Automatic pricing is unavailable. Enter a price to continue without a quote.';

  @override
  String get rebalanceExecutionIssuePriceRequired =>
      'No usable price is available. Add a price to continue.';

  @override
  String get rebalanceExecutionIssueInvalidReview =>
      'Some trade details are invalid. Review them before continuing.';

  @override
  String get rebalanceExecutionIssueStaleReview =>
      'This review is out of date. Review the latest details before continuing.';

  @override
  String get rebalanceExecutionIssueHoldingsChanged =>
      'Available holdings changed. Review the quantity before continuing.';

  @override
  String get rebalanceExecutionIssueOwnerChanged =>
      'The active profile changed, so this trade cannot be executed safely.';

  @override
  String get rebalanceExecutionIssueApplyUnavailable =>
      'Price lookup or execution is temporarily unavailable. Retry the execution, or add a price if one is missing.';

  @override
  String get rebalanceExecutionIssueUndoUnavailable =>
      'Undo is temporarily unavailable. Retry the undo operation.';

  @override
  String get rebalanceExecutionIssueUnsafe =>
      'This trade cannot be continued safely. Skip it or archive the execution.';

  @override
  String get rebalanceExecutionIssueRecoveryCorrupt =>
      'Recovery data is incomplete. Verify the ledger before archiving this execution.';

  @override
  String get rebalanceExecutionIssueLegacyApplyFailure =>
      'A previous execution attempt failed. Retry the execution.';

  @override
  String get rebalanceExecutionIssueLegacyUndoFailure =>
      'A previous undo attempt failed. Retry the undo operation.';

  @override
  String get rebalanceExecutionStateNeedsDetails => 'Needs details';

  @override
  String get rebalanceExecutionStateReady => 'Ready';

  @override
  String get rebalanceExecutionStateApplying => 'Applying';

  @override
  String get rebalanceExecutionStateApplied => 'Applied';

  @override
  String get rebalanceExecutionStateApplyFailed => 'Apply failed';

  @override
  String get rebalanceExecutionStateUndoing => 'Undoing';

  @override
  String get rebalanceExecutionStateUndone => 'Undone';

  @override
  String get rebalanceExecutionStateUndoFailed => 'Undo failed';

  @override
  String get rebalanceExecutionStateSkipped => 'Skipped';

  @override
  String get rebalanceExecutionStateRecoveryBlocked => 'Needs recovery';

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
      'Tune category and asset weights; the total must equal 100%.';

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
  String get targetAllocationEditorCategoryTargets => 'Category targets';

  @override
  String get targetAllocationEditorAddCategory => 'Add asset class';

  @override
  String get targetAllocationEditorNoCategoriesAvailable =>
      'All asset classes are added';

  @override
  String get targetAllocationEditorAssetTargets => 'Asset targets';

  @override
  String get targetAllocationEditorAddAssetTarget => 'Add asset target';

  @override
  String get targetAllocationEditorNoAssetTargets =>
      'No single-asset targets yet.';

  @override
  String get targetAllocationEditorNoAssetsAvailable => 'No available assets';

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
  String get settingsRiskAppetiteConfirmTitle => 'Apply risk posture?';

  @override
  String settingsRiskAppetiteConfirmBody(String appetite) {
    return 'Switch to $appetite? This also retunes target allocation and concentration alerts while they are on automatic presets.';
  }

  @override
  String get settingsRiskAppetiteConfirmAction => 'Apply';

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
  String get tradeEntryAdvancedTitle => 'Trade details';

  @override
  String get tradeEntryAdvancedSummary => 'Now · no fees or notes';

  @override
  String get tradeEntryAdvancedConfigured => 'Custom date, costs or notes';

  @override
  String get tradeEntryCashAccountLabel => 'Cash account';

  @override
  String get tradeEntryHoldingAccountLabel => 'Holding account';

  @override
  String get tradeEntrySettlementTitle => 'Settlement';

  @override
  String tradeEntrySettlementBrokerCash(String currency) {
    return '$currency cash in holding account';
  }

  @override
  String tradeEntrySettlementExternal(String account, String currency) {
    return '$account · $currency';
  }

  @override
  String get tradeEntrySettlementAccountLabel => 'External settlement account';

  @override
  String get tradeEntrySettlementHelper =>
      'Leave the account empty to settle against cash held inside the brokerage or exchange account.';

  @override
  String tradeEntryCrossCurrencyHint(
    String assetCurrency,
    String tradeCurrency,
  ) {
    return 'This instrument quotes in $assetCurrency; price, costs, and cash will be recorded in $tradeCurrency.';
  }

  @override
  String get tradeEntryCashAccountCurrencyChanged =>
      'The previous cash account does not support this currency. Pick another cash account.';

  @override
  String get tradeEntryBrokerAccountRequiredTitle =>
      'Brokerage account required';

  @override
  String get tradeEntryBrokerAccountRequiredMessage =>
      'Create a brokerage or crypto account before recording a securities trade.';

  @override
  String get tradeEntryCashAccountInvalid =>
      'Choose a live cash account that matches the transaction currency.';

  @override
  String get tradeEntryLotCurrencyMismatch =>
      'The selected currency does not match this holding\'s lots. Change the visible Currency field. If the holding contains lots in multiple currencies, repair or split the holding first.';

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
  String get tradeTypeAdjustShort => 'Adjust';

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
  String get expenseFormAccountMissingNotice =>
      'The previous payment account is unavailable. Pick an account to continue.';

  @override
  String expenseFormCurrencyConflictNotice(
    String accountCurrency,
    String expenseCurrency,
  ) {
    return 'This expense is recorded in $expenseCurrency, but the account now uses $accountCurrency. Choose the intended currency before saving.';
  }

  @override
  String expenseFormAccountsLoadError(String error) {
    return 'Couldn\'t load accounts: $error';
  }

  @override
  String get expenseFormDateLabel => 'Date & time';

  @override
  String get expenseFormAdvancedTitle => 'Date & note';

  @override
  String get expenseFormDeleteDialogTitle => 'Delete expense';

  @override
  String get expenseFormDeleteDialogBody =>
      'Delete this expense? You can undo it from the confirmation message, and the change syncs to your other devices.';

  @override
  String get expenseFormNoAccountsTitle => 'Create an account first';

  @override
  String get expenseFormNoAccountsBody =>
      'Expenses need a funding account. Create one under Accounts, then come back here.';

  @override
  String get expenseFormNoAccountsCta => 'Create account';

  @override
  String get incomeFormCreateTitle => 'Record income';

  @override
  String get incomeFormAmountLabel => 'Amount';

  @override
  String get incomeFormAmountInvalid => 'Amount must be greater than 0';

  @override
  String get incomeFormKindLabel => 'Income type';

  @override
  String get incomeFormAccountLabel => 'Deposit account';

  @override
  String get incomeFormAccountRequired =>
      'Choose a deposit account and currency';

  @override
  String get incomeFormAdvancedTitle => 'Date & note';

  @override
  String get incomeFormDateLabel => 'Date & time';

  @override
  String get incomeFormDefaultNarration => 'Income';

  @override
  String get incomeFormNoAccountsTitle => 'Create an account first';

  @override
  String get incomeFormNoAccountsBody =>
      'Income needs a deposit account. Create one under Accounts, then come back here.';

  @override
  String get incomeFormNoAccountsCta => 'Create account';

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
  String get aiToolHoldingsEmpty => 'No holdings data yet';

  @override
  String get aiToolAssetColumn => 'Asset';

  @override
  String get aiToolQuantityColumn => 'Quantity';

  @override
  String get aiToolCostColumn => 'Cost';

  @override
  String aiToolHiddenItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more items hidden',
      one: '1 more item hidden',
    );
    return '$_temp0';
  }

  @override
  String get aiToolPaymentAccountsEmpty => 'No payment accounts available';

  @override
  String get aiToolPaymentAccountsTitle => 'Available payment accounts';

  @override
  String aiToolHiddenAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more accounts hidden',
      one: '1 more account hidden',
    );
    return '$_temp0';
  }

  @override
  String aiToolXirrAssetScope(String assetId) {
    return 'Asset $assetId';
  }

  @override
  String get aiToolXirrPortfolioScope => 'Portfolio';

  @override
  String get aiToolAllHistory => 'All history';

  @override
  String get aiToolXirrUnavailable =>
      'Cannot calculate: cash flows are one-sided or insufficient';

  @override
  String aiToolCashFlowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cash flows',
      one: '1 cash flow',
    );
    return '$_temp0';
  }

  @override
  String get aiToolNetWorthEmpty =>
      'No cumulative net cash-flow data in this range';

  @override
  String get aiToolCurrentNetWorth => 'Cumulative net cash flow';

  @override
  String get aiToolNetWorthSeriesName => 'Cumulative net cash flow';

  @override
  String get aiToolNetWorthMethodNote =>
      'Monthly cumulative net cash flow · not mark-to-market net worth';

  @override
  String get aiToolNetWorthVsStart => 'vs range start';

  @override
  String aiToolSamplePointCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sample points',
      one: '1 sample point',
    );
    return '$_temp0';
  }

  @override
  String get aiToolBreakdownCostEmpty => 'No cost basis to break down';

  @override
  String aiToolOtherCategoriesSummary(int count, String share) {
    return 'Other $count categories total $share';
  }

  @override
  String get aiToolRiskAlertsEmpty => 'No risk alerts triggered';

  @override
  String get aiToolRiskAlertTitle => 'Risk alert';

  @override
  String get aiToolHoldingsDataMalformed => 'Holdings data format is invalid';

  @override
  String aiToolTotalCostSummary(String cost, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holding classes',
      one: '1 holding class',
    );
    return 'Total cost $cost · $_temp0';
  }

  @override
  String get aiToolRecurringPatternsEmpty =>
      'No stable recurring spending detected yet';

  @override
  String aiToolMoreItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ $count more items',
      one: '+ 1 more item',
    );
    return '$_temp0';
  }

  @override
  String get aiToolCadenceMonthly => 'Monthly';

  @override
  String get aiToolCadenceWeekly => 'Weekly';

  @override
  String aiToolOccurrences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '1 time',
    );
    return '$_temp0';
  }

  @override
  String aiToolOccurrencesRecent(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '1 time',
    );
    return '$_temp0 · last $date';
  }

  @override
  String get aiToolSubscriptionChangesEmpty =>
      'No subscription price changes detected this period';

  @override
  String aiToolSinceDate(String date) {
    return ' · since $date';
  }

  @override
  String get aiToolRefundLinksEmpty => 'No refund matches detected yet';

  @override
  String get aiChatEmptyTitle => 'Your LifeOS assistant';

  @override
  String get aiChatEmptyBody =>
      'Ask about finance, knowledge, health, and plans together. Answers prioritize on-device data and enabled features; when information is missing, the assistant asks before assuming.';

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
  String get aiIntentReviewCashBucketLabel => 'Check cash runway';

  @override
  String aiIntentReviewCashBucketPrompt(Object objectLabel) {
    return 'Use get_fire_state to check cash-runway months vs target for $objectLabel. If short, give the refill amount and prepare a propose_fire_plan_update suggestion.';
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
  String get speechInputStartTooltip => 'Start voice input';

  @override
  String get speechInputStopTooltip => 'Stop and keep transcript';

  @override
  String get speechInputContinuousStartTooltip =>
      'Start continuous conversation';

  @override
  String get speechInputContinuousStopTooltip => 'Stop continuous conversation';

  @override
  String get speechInputStartingTooltip =>
      'Preparing on-device speech recognition…';

  @override
  String get speechInputPreparingStatus => 'Preparing microphone…';

  @override
  String get speechInputPermissionStatus =>
      'Waiting for microphone permission…';

  @override
  String get speechInputReadyStatus =>
      'Recognition is ready; starting microphone…';

  @override
  String get speechInputListeningStatus => 'Listening…';

  @override
  String get speechInputContinuousStatus => 'Listening continuously…';

  @override
  String get speechInputEndpointingStatus => 'Finishing recognition…';

  @override
  String get speechInputThinkingStatus => 'Thinking…';

  @override
  String get speechInputSpeakingStatus => 'Speaking · Tap the mic to interrupt';

  @override
  String get speechInputDuplexSpeakingStatus =>
      'Speaking · You can interrupt by talking';

  @override
  String get speechInputDuplexPausedStatus =>
      'Speaking paused · Keep talking to interrupt';

  @override
  String get speechInputSwitchToTextTooltip => 'Switch to text input';

  @override
  String get speechInputCancelTooltip => 'Cancel voice input';

  @override
  String get speechOutputStopTooltip => 'Stop speaking';

  @override
  String get speechInputModelMissing =>
      'Download the real-time Chinese speech model first';

  @override
  String get speechInputUnsupported =>
      'On-device voice input is unavailable on this platform';

  @override
  String get speechInputPermissionDenied =>
      'Microphone permission is required for voice input';

  @override
  String get speechInputRecorderUnavailable =>
      'The microphone or recording device is unavailable';

  @override
  String get speechInputRuntimeUnavailable =>
      'The on-device speech recognition service is unavailable';

  @override
  String get speechInputSessionBusy =>
      'The previous voice session is still closing';

  @override
  String get speechInputFailed =>
      'Speech recognition could not start. Try again later';

  @override
  String get speechInputRetry => 'Retry';

  @override
  String get speechOutputEngineUnavailable =>
      'Text-to-speech is unavailable on this device';

  @override
  String get speechOutputSynthesisFailed =>
      'Text-to-speech could not play this answer';

  @override
  String get speechOutputSessionBusy =>
      'Another answer is already being spoken';

  @override
  String get aiChatThinking => 'Thinking…';

  @override
  String aiChatToolsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tools used',
      one: '1 tool used',
    );
    return '$_temp0';
  }

  @override
  String get aiChatToolsExpand => 'Show details';

  @override
  String get aiChatToolsCollapse => 'Hide details';

  @override
  String aiChatRunningTool(String tool) {
    return 'Running $tool';
  }

  @override
  String get aiChatJumpToLatest => 'Latest';

  @override
  String aiChatJumpToLatestWithCount(int count) {
    return 'Latest · $count';
  }

  @override
  String get aiChatDateToday => 'Today';

  @override
  String get aiChatDateYesterday => 'Yesterday';

  @override
  String get aiChatMessageActionsTitle => 'Message';

  @override
  String aiChatDecisionSelected(String label) {
    return 'Selected: $label';
  }

  @override
  String get aiChatDecisionCustomHint => 'Type your own option…';

  @override
  String get aiToolOpenWealth => 'Open wealth';

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
  String get aiChatEditUserMessageHint =>
      'Edit in composer, then send to replace this turn';

  @override
  String get aiChatEditBannerTitle =>
      'Editing message — send to replace this turn';

  @override
  String get aiChatEditCancel => 'Cancel';

  @override
  String aiChatSessionMessageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String get aiChatDecisionAllowCustom => 'Or type your own option below.';

  @override
  String aiChatDecisionReply(String label) {
    return 'I choose \"$label\". Continue under this option.';
  }

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
  String get aiChatSessionsSearchClear => 'Clear search';

  @override
  String get aiChatSessionsGroupPinned => 'Pinned';

  @override
  String get aiChatSessionsGroupArchived => 'Archived';

  @override
  String aiChatSessionsShowArchived(int count) {
    return 'Show archive ($count)';
  }

  @override
  String get aiChatSessionsHideArchived => 'Hide archive';

  @override
  String get aiChatSessionsClearArchive => 'Clear archive';

  @override
  String get aiChatSessionsClearArchiveTitle => 'Clear archive?';

  @override
  String get aiChatSessionsClearArchiveBody =>
      'This permanently deletes every archived conversation. This cannot be undone.';

  @override
  String aiChatSessionsClearArchiveDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archived conversations',
      one: '1 archived conversation',
    );
    return 'Deleted $_temp0';
  }

  @override
  String get aiChatSessionsEmptyActive => 'No active conversations';

  @override
  String get aiChatSessionPinAction => 'Pin';

  @override
  String get aiChatSessionUnpinAction => 'Unpin';

  @override
  String get aiChatSessionArchiveAction => 'Archive';

  @override
  String get aiChatSessionUnarchiveAction => 'Unarchive';

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
  String get aiChatProposalKindIncome => 'Income';

  @override
  String get aiChatProposalKindTransfer => 'Transfer';

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
  String get aiChatProposalKindOptionsProfileUpdate =>
      'Income Planner preferences';

  @override
  String get aiChatProposalKindOptionsJournalEntry => 'Options journal entry';

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
  String aiChatProposalBatchProgress(int completed, int total) {
    return 'Applying $completed of $total';
  }

  @override
  String get aiChatProposalBatchRecover => 'Undo applied items';

  @override
  String aiChatProposalBatchRecoveryNeeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count applied items still need to be undone before retrying',
      one: '1 applied item still needs to be undone before retrying',
    );
    return '$_temp0';
  }

  @override
  String get aiChatProposalBatchRolledBack =>
      'Applied items were undone. The batch is safe to retry.';

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
  String get aiChatFieldNotes => 'Notes';

  @override
  String get aiChatFieldOptionPremium => 'Premium';

  @override
  String get aiChatRecommendedBadge => 'Recommended';

  @override
  String get aiChatFieldAmount => 'Amount';

  @override
  String get aiChatFieldDestinationAmount => 'Destination amount';

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
  String get aiChatRowFromAccount => 'From account';

  @override
  String get aiChatRowToAccount => 'To account';

  @override
  String get aiChatRowDestinationAmount => 'Destination amount';

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
  String get aiChatRowUnderlying => 'Underlying';

  @override
  String get aiChatRowOptionContract => 'Option contract';

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
  String get aiChatToolShowRawJson => 'View raw data';

  @override
  String get aiChatToolShowCompactView => 'Back to compact view';

  @override
  String get aiFloatingPillLabel => 'Open assistant';

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
  String get chartTotalLabel => 'Total';

  @override
  String get formAmountFieldLabelDefault => 'Amount';

  @override
  String get formAmountFieldRequired => 'Enter an amount';

  @override
  String get formAmountFieldInvalid => 'Invalid amount format';

  @override
  String get formAmountFieldNegativeNotAllowed => 'Amount cannot be negative';

  @override
  String get formAmountFieldZeroNotAllowed =>
      'Amount must be greater than zero';

  @override
  String get formNoteFieldLabelDefault => 'Notes';

  @override
  String get formDateFieldClearTooltip => 'Clear';

  @override
  String get formDateFieldTimeLabel => 'Time';

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
      'Select an account on the left to see its balance and activity.';

  @override
  String get accountsCreateAction => 'New account';

  @override
  String accountsLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get accountsEmptyHint =>
      'Add your first account to start tracking assets.';

  @override
  String get accountsOverviewTitle => 'Account overview';

  @override
  String get accountsOverviewAccountsLabel => 'Accounts';

  @override
  String get accountsOverviewInstitutionsLabel => 'Institutions';

  @override
  String get accountsOverviewCurrenciesLabel => 'Currencies';

  @override
  String accountsCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String get accountDetailEditAction => 'Edit account';

  @override
  String get accountDetailNotFound => 'Account not found';

  @override
  String get accountDetailBalanceTitle => 'Available balance';

  @override
  String get accountDetailTransferAction => 'Transfer';

  @override
  String get accountDetailAdjustBalanceAction => 'Adjust balance';

  @override
  String get accountDetailAddBalanceAction => 'Add cash balance';

  @override
  String get accountDetailRecentActivityTitle => 'Recent activity';

  @override
  String get accountDetailNoActivity =>
      'No activity recorded for this account yet.';

  @override
  String get accountDetailTypeLabel => 'Account type';

  @override
  String get accountDetailCurrencyLabel => 'Primary currency';

  @override
  String get accountDetailInstitutionLabel => 'Institution';

  @override
  String get accountDetailNumberLabel => 'Account number';

  @override
  String get accountDetailNotesLabel => 'Notes';

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
  String get accountFormAdvancedTitle => 'More account details';

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
  String get cashFormCheckingExisting =>
      'Checking this account for an existing cash balance…';

  @override
  String get cashFormExistingFoundTitle => 'Existing cash balance found';

  @override
  String get cashFormExistingFoundBody =>
      'Saving will update this account’s existing balance instead of creating a duplicate.';

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
  String get activitySelectEntry =>
      'Select an entry to inspect it without leaving the timeline';

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
  String get activityFeedSummaryExpense => 'Expense';

  @override
  String get activityFeedSummaryIncome => 'Income';

  @override
  String get activityFeedSummaryCount => 'Entries';

  @override
  String get activityFeedSummaryNet => 'Net cash flow';

  @override
  String activityFeedSummaryShown(int count) {
    return '$count shown';
  }

  @override
  String activityFeedSummaryCountValue(int count) {
    return '$count entries';
  }

  @override
  String activityFeedDayExpense(String amount) {
    return 'Out $amount';
  }

  @override
  String activityFeedDayIncome(String amount) {
    return 'In $amount';
  }

  @override
  String get activityFeedSearchAction => 'Search';

  @override
  String get activityFeedSearchHint => 'Search merchant, note, or account';

  @override
  String activityFeedSearchTag(String query) {
    return '“$query”';
  }

  @override
  String get activityEntryDeleteTitle => 'Delete this entry?';

  @override
  String get activityEntryDeleteBody =>
      'This removes the journal entry and its postings from your ledger. You can undo it from the confirmation message.';

  @override
  String get activityEntryDeleted => 'Entry deleted';

  @override
  String get activityEntryDeleteFailed =>
      'Couldn\'t delete this entry. Try again.';

  @override
  String get accountsTransferAction => 'Transfer';

  @override
  String get accountsJournalAction => 'Journal';

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
  String get settingsAiSection => 'AI';

  @override
  String get settingsAiHubTitle => 'AI & device intelligence';

  @override
  String get settingsAiHubSubtitle =>
      'Providers, local models, agents, privacy, and activity';

  @override
  String get settingsAiHubRuntimeSection => 'Runtime';

  @override
  String get settingsAiHubTrustSection => 'Privacy & transparency';

  @override
  String get settingsAiHistoryTitle => 'AI history';

  @override
  String get settingsAiHistorySubtitle => 'Review saved AI conversations';

  @override
  String get personalMemoryTitle => 'Personal memory';

  @override
  String get personalMemorySubtitle =>
      'Manage goals, preferences, constraints, and rules used by AI';

  @override
  String get personalMemorySection => 'Confirmed profile';

  @override
  String get personalMemoryEmpty => 'No confirmed profile facts yet.';

  @override
  String get personalMemoryAdd => 'Add profile fact';

  @override
  String get personalMemoryCreateTitle => 'Add profile fact';

  @override
  String get personalMemoryEditTitle => 'Edit profile fact';

  @override
  String get personalMemoryKind => 'Type';

  @override
  String get personalMemoryKindGoal => 'Goal';

  @override
  String get personalMemoryKindPreference => 'Preference';

  @override
  String get personalMemoryKindConstraint => 'Constraint';

  @override
  String get personalMemoryKindRule => 'Rule';

  @override
  String get personalMemoryKey => 'Key';

  @override
  String get personalMemoryKeyHint => 'For example: cash_buffer_months';

  @override
  String get personalMemoryValue => 'Value';

  @override
  String get personalMemoryValueHint => 'Text or JSON value';

  @override
  String get personalMemorySummary => 'Summary';

  @override
  String get personalMemorySummaryHint =>
      'A clear fact the agent may use as evidence';

  @override
  String get personalMemoryDomain => 'Domain (optional)';

  @override
  String get personalMemoryDomainHint =>
      'finance, health, knowledge, or execution';

  @override
  String get personalMemoryRequired => 'Key and summary are required';

  @override
  String get personalMemoryDeleteTitle => 'Forget this profile fact?';

  @override
  String get personalMemoryDeleteBody =>
      'It will stop appearing in future AI context. This cannot be undone from this screen.';

  @override
  String get personalMemoryInactiveDomain =>
      'Kept locally; excluded from AI while this domain is off';

  @override
  String personalMemoryLoadFailed(String error) {
    return 'Could not load personal memory: $error';
  }

  @override
  String get settingsAdvancedHubTitle => 'Advanced diagnostics';

  @override
  String get settingsAdvancedHubSubtitle => 'Logs and performance tools';

  @override
  String get settingsAboutDiagnosticsSection => 'About & diagnostics';

  @override
  String get settingsDataSection => 'Data & sync';

  @override
  String get settingsNotificationsPrivacySection => 'Notifications & privacy';

  @override
  String get settingsDataManagementTitle => 'Data & storage';

  @override
  String get settingsDataManagementSubtitle =>
      'Inspect, export, clean, and reset each OS from one place';

  @override
  String get dataManagementBackupTitle => 'Encrypted backup & restore';

  @override
  String get dataManagementBackupSubtitle =>
      'Create a backup before destructive maintenance';

  @override
  String get dataManagementSafetyNotice =>
      'Cache cleanup removes only rebuildable local data. OS reset actions require confirmation and are kept separate from cache maintenance.';

  @override
  String get dataManagementAutomaticTitle => 'Automatic maintenance';

  @override
  String get dataManagementAutomaticSubtitle =>
      'Daily cleanup of expired AI, agent, ingest, and event history';

  @override
  String get dataManagementRunMaintenanceTitle => 'Run maintenance now';

  @override
  String get dataManagementRunMaintenanceNever => 'No maintenance run recorded';

  @override
  String dataManagementRunMaintenanceLast(int count) {
    return 'Last run removed $count rows';
  }

  @override
  String get dataManagementMaintenanceRunning => 'Running…';

  @override
  String dataManagementMaintenanceSuccess(int count) {
    return 'Maintenance complete · $count rows removed';
  }

  @override
  String get dataManagementDomainEnabled => 'Enabled';

  @override
  String get dataManagementDomainDisabled => 'Disabled';

  @override
  String get dataManagementSourceRows => 'Source';

  @override
  String get dataManagementDeletedRows => 'Deleted';

  @override
  String get dataManagementCacheRows => 'Cache';

  @override
  String dataManagementTableSummary(int sourceTables, int cacheTables) {
    return '$sourceTables source tables · $cacheTables cache tables';
  }

  @override
  String get dataManagementCacheHelp =>
      'Local derived data; features rebuild it when needed.';

  @override
  String get dataManagementClearCacheAction => 'Clear cache';

  @override
  String get dataManagementClearing => 'Clearing…';

  @override
  String dataManagementClearCacheConfirmTitle(String domain) {
    return 'Clear $domain cache?';
  }

  @override
  String dataManagementClearCacheConfirmBody(int count) {
    return 'This removes $count local cache rows. Synced source data is not affected.';
  }

  @override
  String dataManagementClearCacheSuccess(int count) {
    return 'Cleared $count cache rows';
  }

  @override
  String get dataManagementExportDomainAction => 'Export OS';

  @override
  String get dataManagementResetDeviceAction => 'Reset this device';

  @override
  String get dataManagementResetEverywhereAction => 'Delete everywhere';

  @override
  String get dataManagementResetting => 'Resetting…';

  @override
  String dataManagementResetDeviceConfirmTitle(String domain) {
    return 'Reset $domain on this device?';
  }

  @override
  String get dataManagementResetDeviceConfirmBody =>
      'Data and history for this domain will be removed from this device. If cloud sync is enabled, cloud data may download again on the next sync.';

  @override
  String dataManagementResetEverywhereConfirmTitle(String domain) {
    return 'Permanently delete $domain?';
  }

  @override
  String get dataManagementResetEverywhereConfirmBody =>
      'This permanently deletes this domain\'s data from the cloud and every connected device. Offline devices cannot restore it when they reconnect. This action cannot be undone.';

  @override
  String dataManagementResetSuccess(int count) {
    return 'Reset complete · $count local rows removed';
  }

  @override
  String get dataManagementSharedTitle => 'AI & cross-domain data';

  @override
  String get dataManagementSharedSubtitle =>
      'Device-local conversations, traces, memories, event projections, and agent results';

  @override
  String get dataManagementChatRows => 'Chat';

  @override
  String get dataManagementAiRows => 'AI audit';

  @override
  String get dataManagementMemoryRows => 'Memory';

  @override
  String get dataManagementAgentRows => 'Agents';

  @override
  String dataManagementStorageUsage(String used, String reclaimable) {
    return 'Database $used · $reclaimable reclaimable';
  }

  @override
  String get dataManagementClearSharedAction => 'Clear local history';

  @override
  String get dataManagementClearSharedConfirmTitle =>
      'Clear AI and cross-domain history?';

  @override
  String dataManagementClearSharedConfirmBody(int count) {
    return 'This removes $count local chat, audit, memory, event, and agent-history rows. OS source data and preferences remain.';
  }

  @override
  String dataManagementClearSharedSuccess(int count) {
    return 'Cleared $count local history rows';
  }

  @override
  String get dataManagementCompactAction => 'Compact database';

  @override
  String get dataManagementCompacting => 'Compacting…';

  @override
  String get dataManagementCompactSuccess => 'Database compacted';

  @override
  String get dataManagementResetAllTitle => 'All OS data';

  @override
  String get dataManagementResetAllSubtitle =>
      'Use only when you want to start over across FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS. Account, device, settings, and FX configuration remain.';

  @override
  String get dataManagementResetAllDeviceAction => 'Reset all on this device';

  @override
  String get dataManagementResetAllEverywhereAction =>
      'Delete all OS data everywhere';

  @override
  String get dataManagementResetAllDeviceConfirmTitle =>
      'Reset every OS on this device?';

  @override
  String get dataManagementResetAllDeviceConfirmBody =>
      'All local OS source data, caches, AI history, memories, and agent results will be removed. Cloud data can download again during sync.';

  @override
  String get dataManagementResetAllEverywhereConfirmTitle =>
      'Permanently delete every OS?';

  @override
  String get dataManagementResetAllEverywhereConfirmBody =>
      'All OS data will be permanently deleted from the server and every device. Account, device, settings, and FX configuration remain. This cannot be undone.';

  @override
  String backupDomainPageTitle(String domain) {
    return '$domain backup';
  }

  @override
  String get settingsDomainsSection => 'Domains';

  @override
  String get settingsDomainsDeepLinkBlockedNotice =>
      'That link belongs to a domain that is not enabled yet. Turn the domain on below to open it.';

  @override
  String get settingsDomainsTitle => 'Domain management';

  @override
  String get settingsDomainsSubtitle =>
      'Manage FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS';

  @override
  String get settingsDomainsFinanceSubtitle =>
      'Always-on finance domain: currency, FX rates, risk posture, allocation, and FIRE planning assumptions';

  @override
  String get settingsDomainsFinanceAlwaysOnBadge => 'Always on';

  @override
  String settingsDomainsDisabledToast(String domain) {
    return '$domain disabled. You can re-enable it here at any time.';
  }

  @override
  String settingsDomainsEnableSuccessTitle(String domain) {
    return '$domain is ready';
  }

  @override
  String settingsDomainsEnableSuccessBody(String domain) {
    return 'Open $domain now and create the first useful item. You can also come back later.';
  }

  @override
  String get settingsDomainsOpenNow => 'Open now';

  @override
  String get settingsDomainsOpenLater => 'Later';

  @override
  String settingsDomainsDisableConfirmTitle(String domain) {
    return 'Turn off $domain?';
  }

  @override
  String settingsDomainsDisableConfirmBody(String domain) {
    return 'Your $domain data stays on this device and in sync, but its navigation, tools, background agents, and notifications will stop until you turn it on again.';
  }

  @override
  String get settingsDomainsDisableConfirmAction => 'Turn off';

  @override
  String settingsDomainsConfigure(String domain) {
    return 'Configure $domain';
  }

  @override
  String get agentSettingsTitle => 'Agents';

  @override
  String get agentSettingsSubtitle =>
      'Control scheduled LifeOS agents for active domains on this device.';

  @override
  String get agentSettingsNoActiveTitle => 'No active agents';

  @override
  String get agentSettingsNoActiveMessage =>
      'Enable a LifeOS domain to see its agents here.';

  @override
  String get agentSettingsManageDomains => 'Manage domains';

  @override
  String get agentSettingsManagedBadge => 'Managed';

  @override
  String get agentSettingsRunNow => 'Run now';

  @override
  String get agentSettingsViewResult => 'View result';

  @override
  String get agentSettingsViewHistory => 'History';

  @override
  String agentSettingsHistoryTitle(String agentName) {
    return '$agentName history';
  }

  @override
  String get agentSettingsHistoryEmptyTitle => 'No runs yet';

  @override
  String get agentSettingsHistoryEmptyMessage =>
      'Run this agent once to start its local history.';

  @override
  String get agentSettingsRunning => 'Running';

  @override
  String get agentSettingsEnabled => 'Enabled';

  @override
  String get agentSettingsDisabled => 'Disabled';

  @override
  String agentSettingsOverviewEnabled(int enabled, int total) {
    return 'Enabled $enabled/$total';
  }

  @override
  String agentSettingsOverviewReady(int count) {
    return 'Ready $count';
  }

  @override
  String agentSettingsOverviewFailed(int count) {
    return 'Failed $count';
  }

  @override
  String agentSettingsOverviewNotificationsOn(int count) {
    return 'Notifications $count';
  }

  @override
  String get agentQualityTitle => '30-day quality';

  @override
  String get agentQualityNoRuns => 'No completed runs in this window';

  @override
  String agentQualityCompletedRuns(int count) {
    return '$count completed runs';
  }

  @override
  String agentQualityReadyRate(int percent, int count, int total) {
    return 'Ready $percent% · $count/$total';
  }

  @override
  String agentQualityNoFindingRate(int percent, int count, int total) {
    return 'No finding $percent% · $count/$total';
  }

  @override
  String agentQualityFailureRate(int percent, int count, int total) {
    return 'Failed $percent% · $count/$total';
  }

  @override
  String agentQualitySuppressedRate(int percent, int count, int total) {
    return 'Hidden or delayed $percent% · $count/$total';
  }

  @override
  String agentQualityEvidenceRate(int percent, int count, int total) {
    return 'Evidence-linked $percent% · $count/$total';
  }

  @override
  String get agentQualityEvidenceNavigationNoSamples =>
      'No evidence-open samples';

  @override
  String agentQualityEvidenceNavigationRate(
    int percent,
    int successes,
    int attempts,
  ) {
    return 'Evidence opened $percent% · $successes/$attempts';
  }

  @override
  String get agentQualityPrivacyNote =>
      'Device-only aggregates · no result content, evidence ids, or routes retained';

  @override
  String get agentSettingsNeverRun => 'Never run';

  @override
  String agentSettingsLastRunAt(String date) {
    return 'Last run $date';
  }

  @override
  String agentSettingsNextRunAt(String date) {
    return 'Next $date';
  }

  @override
  String get agentSettingsNextRunOnOpen => 'Next check when the app opens';

  @override
  String get agentSettingsExecutionTitle => 'Execution';

  @override
  String get agentSettingsExecutionForeground =>
      'Checks when the app opens or returns to the foreground';

  @override
  String get agentSettingsRunNowHint =>
      'Runs once without changing the automatic schedule';

  @override
  String agentSettingsAroundTime(String time) {
    return 'around $time';
  }

  @override
  String agentSettingsEveryHours(int hours) {
    return 'Every $hours hour(s)';
  }

  @override
  String agentSettingsEveryMinutes(int minutes) {
    return 'Every $minutes min';
  }

  @override
  String agentSettingsEveryHoursMinutes(int hours, int minutes) {
    return 'Every ${hours}h ${minutes}m';
  }

  @override
  String get agentSettingsCadenceDaily => 'Daily';

  @override
  String get agentSettingsCadenceWeekly => 'Weekly';

  @override
  String get agentSettingsCadenceMonthly => 'Monthly';

  @override
  String get agentSettingsCadenceYearly => 'Yearly';

  @override
  String agentSettingsRunFinished(String agentName) {
    return '$agentName finished';
  }

  @override
  String agentSettingsRunBusy(String agentName) {
    return '$agentName is already running';
  }

  @override
  String agentSettingsRunFailed(String error) {
    return 'Couldn\'t run agent: $error';
  }

  @override
  String agentSettingsSaveFailed(String error) {
    return 'Couldn\'t update agent settings: $error';
  }

  @override
  String get agentSettingsMissingPresentationBadge => 'Metadata missing';

  @override
  String get agentSettingsMissingPresentationDescription =>
      'This agent is registered without presentation metadata.';

  @override
  String agentSettingsStatusWithDetail(String status, String detail) {
    return '$status · $detail';
  }

  @override
  String get agentSettingsTriggerManual => 'Manual';

  @override
  String get agentSettingsTriggerSchedule => 'Scheduled';

  @override
  String get agentSettingsTriggerBackgroundDue => 'Background due';

  @override
  String get agentSettingsTriggerCatchUp => 'Catch-up';

  @override
  String get settingsAdvancedSection => 'Diagnostic tools';

  @override
  String get settingsAiModelsTitle => 'AI Models';

  @override
  String get settingsAiModelsSubtitle =>
      'Download and manage local AI and speech models';

  @override
  String get aiLlmRuntimeCheckTitle => 'AI service check';

  @override
  String get aiLlmRuntimeCheckReady =>
      'Send a test request with the current model configuration to check whether the AI service is available.';

  @override
  String get aiLlmRuntimeCheckNoProfile =>
      'Save and activate a model provider before checking the AI service.';

  @override
  String get aiLlmRuntimeCheckAction => 'Start check';

  @override
  String get aiLlmRuntimeCheckRunning => 'Checking…';

  @override
  String get aiLlmRuntimeCheckPrompt =>
      'Reply with one short sentence confirming NaviWealth can reach the current AI service.';

  @override
  String aiLlmRuntimeCheckSucceeded(String status) {
    return 'AI service check completed: $status';
  }

  @override
  String aiLlmRuntimeCheckFailed(String error) {
    return 'AI service check failed: $error';
  }

  @override
  String aiLlmRuntimeCheckStatus(String status) {
    return 'On-device check: $status';
  }

  @override
  String get agentResultReviewAction => 'Review';

  @override
  String get agentResultRetryAction => 'Retry';

  @override
  String get agentResultAskAction => 'Ask';

  @override
  String get agentResultLoadingBody =>
      'Checking the latest agent results for this view.';

  @override
  String get agentResultKindBriefing => 'Briefing';

  @override
  String get agentResultKindReview => 'Review';

  @override
  String get agentResultKindAlert => 'Alert';

  @override
  String get agentResultKindReminder => 'Reminder';

  @override
  String get agentResultSeverityAttention => 'Attention';

  @override
  String get agentResultSeverityWarning => 'Warning';

  @override
  String get agentRunStatusRunning => 'Running';

  @override
  String get agentRunStatusNoFinding => 'No finding';

  @override
  String get agentRunStatusReady => 'Ready';

  @override
  String get agentRunStatusFailed => 'Failed';

  @override
  String get agentResultInsightsSection => 'Insights';

  @override
  String get agentResultEvidenceSection => 'Evidence';

  @override
  String get agentResultEvidenceMethodSection => 'Evidence & method';

  @override
  String agentResultEvidenceCount(int count) {
    return '$count sources';
  }

  @override
  String get agentResultEvidenceAvailableBody =>
      'View the data source behind this evidence.';

  @override
  String agentResultEvidenceSupportCount(int count) {
    return 'Supported by $count sources';
  }

  @override
  String get agentResultOpenRelatedPage => 'Open related page';

  @override
  String get agentResultTechnicalDetailsTitle => 'Technical details';

  @override
  String get agentResultTechnicalDetailsBody =>
      'Review the analysis steps and tool activity for this result.';

  @override
  String get agentResultTraceSection => 'Trace';

  @override
  String get agentResultTraceTitle => 'Runtime trace';

  @override
  String get agentResultTraceBody =>
      'Review the AI call chain and tool activity.';

  @override
  String get agentResultTraceAction => 'Open';

  @override
  String get agentResultActionsSection => 'Actions';

  @override
  String get agentResultAskFollowUpTitle => 'Ask Agent';

  @override
  String get agentResultAskFollowUpBody =>
      'Explain this result and its evidence.';

  @override
  String get agentResultShowEvidenceTitle => 'Show evidence';

  @override
  String get agentResultShowEvidenceBody =>
      'Map the evidence to the claims in this result.';

  @override
  String get agentResultCreatePlanTitle => 'Create plan';

  @override
  String get agentResultCreatePlanBody =>
      'Turn this result into proposed next steps.';

  @override
  String get agentResultSnoozeTitle => 'Snooze';

  @override
  String get agentResultSnoozeBody => 'Hide this result until tomorrow.';

  @override
  String get agentResultSnoozeAction => 'Snooze';

  @override
  String get agentResultDismissTitle => 'Dismiss';

  @override
  String get agentResultDismissBody => 'Hide this result from active surfaces.';

  @override
  String get agentResultDismissAction => 'Dismiss';

  @override
  String agentResultVisibilityActionFailed(String error) {
    return 'Couldn\'t update this result: $error';
  }

  @override
  String get agentResultLocalMethodTitle => 'How this result was produced';

  @override
  String get agentResultLocalMethodDeterministicBody =>
      'Calculated from local domain records using deterministic rules.';

  @override
  String get agentResultLocalMethodAssistedBody =>
      'Synthesized on device from local domain records; the supporting metrics remain source-derived.';

  @override
  String get agentResultLocalMethodSourceLabel => 'Data source';

  @override
  String get agentResultLocalMethodRuntimeLabel => 'Runtime';

  @override
  String get agentResultLocalMethodRuntimeValue => 'On device';

  @override
  String get agentResultMetricCurrent => 'Current';

  @override
  String get agentResultMetricBaseline => 'Baseline';

  @override
  String get agentResultActionFallbackBody =>
      'Open this action from the agent result.';

  @override
  String agentResultActionFallbackWithKey(String key) {
    return 'Action key: $key';
  }

  @override
  String get agentPresentationWeeklyWealthReviewLabel => 'Weekly Wealth Review';

  @override
  String get agentPresentationWeeklyWealthReviewDescription =>
      'Reviews net worth, allocation concentration, price freshness, and FX coverage.';

  @override
  String get agentPresentationCashflowAnomalyReviewLabel =>
      'Cashflow Anomaly Review';

  @override
  String get agentPresentationCashflowAnomalyReviewDescription =>
      'Reviews on-device monthly spending anomalies.';

  @override
  String get agentPresentationFirePlanDriftMonitorLabel =>
      'FIRE Plan Drift Monitor';

  @override
  String get agentPresentationFirePlanDriftMonitorDescription =>
      'Reviews withdrawal rate, cash runway, plan ETA, and stress-test drift.';

  @override
  String get agentPresentationOptionsIncomeRiskReviewLabel =>
      'Options Income Risk Review';

  @override
  String get agentPresentationOptionsIncomeRiskReviewDescription =>
      'Reviews scan freshness, quote quality, concentration, and contract risk.';

  @override
  String get agentPresentationRecoveryAlertLabel => 'Recovery Alert';

  @override
  String get agentPresentationRecoveryAlertDescription =>
      'Flags short sleep, low HRV, and recovery signals that need attention.';

  @override
  String get agentPresentationWeeklySummaryLabel => 'Weekly Summary';

  @override
  String get agentPresentationWeeklySummaryDescription =>
      'Reviews the week across sleep, activity, recovery, and trend evidence.';

  @override
  String get agentPresentationKnowledgeReviewLabel => 'Knowledge Review';

  @override
  String get agentPresentationKnowledgeReviewDescription =>
      'Reviews due decisions and stale assumptions.';

  @override
  String get agentPresentationKnowledgeAssumptionLabel => 'Assumption Review';

  @override
  String get agentPresentationKnowledgeAssumptionDescription =>
      'Finds assumptions that need revalidation.';

  @override
  String get agentPresentationKnowledgeContradictionLabel =>
      'Contradiction Review';

  @override
  String get agentPresentationKnowledgeContradictionDescription =>
      'Looks for conflicting notes, decisions, and assumptions.';

  @override
  String get agentPresentationKnowledgeInboxTriageLabel => 'Inbox Triage';

  @override
  String get agentPresentationKnowledgeInboxTriageDescription =>
      'Surfaces captured notes that need classification or follow-up.';

  @override
  String get agentPresentationExecutionReviewLabel => 'Execution Review';

  @override
  String get agentPresentationExecutionReviewDescription =>
      'Reviews today actions, blocked work, commitments, and weekly progress.';

  @override
  String aiLlmRuntimeProposalTitle(String kind) {
    return 'Ready proposal · $kind';
  }

  @override
  String aiLlmRuntimeProposalWarning(String warning) {
    return 'Warning: $warning';
  }

  @override
  String get aiLlmRuntimeProposalApply => 'Apply proposal';

  @override
  String get aiLlmRuntimeProposalApplying => 'Applying…';

  @override
  String get aiLlmRuntimeProposalConfirmTitle => 'Apply this proposal?';

  @override
  String aiLlmRuntimeProposalConfirmBody(String summary) {
    return '$summary\n\nConfirm to save this change in the same way as the AI assistant.';
  }

  @override
  String aiLlmRuntimeProposalApplied(String status) {
    return 'Proposal apply finished: $status';
  }

  @override
  String aiLlmRuntimeProposalStatus(String status) {
    return 'Proposal apply: $status';
  }

  @override
  String aiLlmRuntimeProposalFailed(String error) {
    return 'Proposal apply failed: $error';
  }

  @override
  String get settingsBadgeAuto => 'Auto';

  @override
  String get settingsBadgeCustom => 'Custom';

  @override
  String get settingsDataTitle => 'Backup & Restore';

  @override
  String get settingsDataSubtitle => 'Export or import encrypted data backups';

  @override
  String get settingsNotificationsTitle => 'Notifications';

  @override
  String get settingsNotificationsSubtitle =>
      'Permissions, agent reminders, and HealthOS briefing alerts';

  @override
  String get settingsNotificationsMasterTitle => 'Allow app notifications';

  @override
  String get settingsNotificationsMasterSubtitle =>
      'Controls local agent notifications and background reminder jobs.';

  @override
  String get settingsNotificationsPermissionChecking =>
      'Checking system notification permission…';

  @override
  String get settingsNotificationsPermissionGranted =>
      'System notifications are allowed.';

  @override
  String get settingsNotificationsPermissionDenied =>
      'System notifications are off for NaviWealth.';

  @override
  String get settingsNotificationsPermissionUnavailable =>
      'Notifications are not available on this platform.';

  @override
  String settingsNotificationsPermissionFailed(String error) {
    return 'Couldn\'t read notification permission: $error';
  }

  @override
  String get settingsNotificationsPermissionRequest => 'Enable';

  @override
  String get settingsNotificationsPermissionRequesting => 'Enabling…';

  @override
  String get settingsBiometricTitle => 'Biometric unlock';

  @override
  String get settingsBiometricSubtitle =>
      'Require Face ID or fingerprint when NaviWealth opens.';

  @override
  String get settingsBiometricChecking => 'Checking biometric availability…';

  @override
  String get settingsBiometricUnavailable =>
      'Biometric unlock is not available on this device.';

  @override
  String get settingsBiometricNotEnrolled =>
      'Set up Face ID or fingerprint on this device first.';

  @override
  String get biometricUnlockTitle => 'NaviWealth is locked';

  @override
  String get biometricUnlockSubtitle =>
      'Unlock with your device biometric to continue.';

  @override
  String get biometricUnlockButton => 'Unlock';

  @override
  String get biometricUnlockChecking => 'Unlocking…';

  @override
  String get biometricUnlockFailed => 'Biometric unlock failed.';

  @override
  String get biometricUnlockReason => 'Unlock NaviWealth';

  @override
  String get settingsCrashReportingTitle => 'Crash reporting';

  @override
  String get settingsCrashReportingSubtitle =>
      'Send anonymous error reports to help fix bugs. Off by default.';

  @override
  String get settingsAiPrivacyTitle => 'AI privacy';

  @override
  String get settingsAiPrivacySubtitle =>
      'Control what is sent to your model provider';

  @override
  String get aiPrivacyTitle => 'AI privacy';

  @override
  String get aiPrivacyIntro =>
      'Choose how much data can be sent when you use a cloud model. You can change this at any time.';

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
  String get settingsLogsCopyAction => 'Copy all logs';

  @override
  String get settingsLogsShareAction => 'Share all logs';

  @override
  String get settingsLogsClearTitle => 'Clear logs?';

  @override
  String get settingsLogsClearBody =>
      'This removes the in-memory diagnostic log history from this device.';

  @override
  String get settingsLogsClearAction => 'Clear logs';

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
  String get settingsPerfCopyEvidence => 'Copy performance evidence';

  @override
  String get settingsPerfEvidenceCopied => 'Performance evidence copied';

  @override
  String get settingsDomainsHealthEnabledSubtitle =>
      'AI tools and Memory indexing are enabled';

  @override
  String get settingsDomainsHealthDisabledSubtitle =>
      'Turn on AI tools and Memory indexing';

  @override
  String get settingsDomainsHealthTodaySubtitle =>
      'View recovery, metrics, and health trends';

  @override
  String get settingsDomainsKnowledgeEnabledSubtitle =>
      'Inbox, Library, Review, AI tools, and Memory indexing are enabled';

  @override
  String get settingsDomainsKnowledgeDisabledSubtitle =>
      'Personal decisions and cognitive memory';

  @override
  String get settingsDomainsKnowledgeInboxSubtitle =>
      'Capture notes, write decisions, and review the library';

  @override
  String get settingsDomainsKnowledgeLibrarySubtitle =>
      'Browse decisions, assumptions, routines, concepts, and notes';

  @override
  String get settingsDomainsKnowledgeReviewSubtitle =>
      'Review due decisions, stale assumptions, and due routines';

  @override
  String get settingsDomainsKnowledgeMemoryTitle => 'KnowledgeOS Memory';

  @override
  String get settingsDomainsKnowledgeMemorySubtitle =>
      'Manage the local model used for recall, dedupe, and semantic search';

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
  String get settingsAiModelsOrtMissing => 'ONNX Runtime library missing';

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
      'Model files stay on this device and are never uploaded. EmbeddingGemma powers local memory retrieval; Zipformer powers real-time Mandarin voice input. ONNX Runtime is bundled with the app.';

  @override
  String get settingsAiModelsSpeechEngineTitle => 'Voice recognition engine';

  @override
  String get settingsAiModelsSpeechEngineSubtitle =>
      'System on-device recognition is the safe default. Zipformer keeps audio local and needs its model bundle.';

  @override
  String get settingsAiModelsSpeechEngineLocalOnlySubtitle =>
      'This platform currently uses local Zipformer recognition and needs its model bundle.';

  @override
  String get settingsAiModelsSpeechEngineSystem => 'System on-device';

  @override
  String get settingsAiModelsSpeechEngineZipformer => 'Local Zipformer';

  @override
  String get settingsAiModelsSpeechEngineZipformerMissing =>
      'Download the Zipformer bundle below before using local recognition.';

  @override
  String get settingsAiModelsFootnote =>
      'The speech model is available on the next microphone tap. After downloading EmbeddingGemma, restart the app; existing memories are re-indexed in the next cycle and original records remain unchanged.';

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
      'After deletion, the corresponding on-device capability becomes unavailable or falls back to its lightweight implementation. Re-enabling it requires another download.';

  @override
  String get settingsAiModelsActiveRuntimeTitle => 'Running embedder';

  @override
  String get settingsAiModelsActiveRuntimeLoading =>
      'Checking the active embedder…';

  @override
  String settingsAiModelsActiveRuntimeFailed(String error) {
    return 'Active embedder check failed: $error';
  }

  @override
  String get settingsAiModelsActiveRuntimeNative => 'On-device';

  @override
  String get settingsAiModelsActiveRuntimeStub => 'Simulation';

  @override
  String get settingsAiModelsActiveRuntimeUnknown => 'Unavailable';

  @override
  String get settingsAiModelsFingerprintLabel => 'Model fingerprint';

  @override
  String get settingsAiModelsDimensionLabel => 'dimension';

  @override
  String get settingsAiModelsMemoryRowsLabel => 'Memories';

  @override
  String get settingsAiModelsVectorRowsLabel => 'Vectors';

  @override
  String get settingsAiModelsCurrentVectorsLabel => 'Current';

  @override
  String get settingsAiModelsStaleVectorsLabel => 'Stale';

  @override
  String get settingsAiModelsEventsLabel => 'Events';

  @override
  String get settingsAiModelsSourcesTitle => 'Indexed sources';

  @override
  String get settingsAiModelsNoSources => 'No memory sources indexed yet.';

  @override
  String get settingsAiModelsStaleVectorsHint =>
      'Some vectors were created by a different embedder fingerprint. They will be refreshed by the next indexer cycle.';

  @override
  String get knowledgeAiSuggestionsTitle => 'AI suggestions';

  @override
  String knowledgeAiSuggestionsTitleWithCount(int count) {
    return 'AI suggestions ($count)';
  }

  @override
  String knowledgeAiSuggestionsSubtitle(Object count) {
    return '$count background organization suggestions, ready for your review.';
  }

  @override
  String get knowledgeAiSuggestionsEmpty =>
      'No organization suggestions are waiting.';

  @override
  String knowledgeAiSuggestionCount(Object count) {
    return '$count items';
  }

  @override
  String get knowledgeAiSuggestionKindClassification => 'Classification';

  @override
  String get knowledgeAiSuggestionKindTags => 'Tags';

  @override
  String get knowledgeAiSuggestionKindLinkToDecision => 'Decision link';

  @override
  String get knowledgeAiSuggestionDetails => 'Details';

  @override
  String get knowledgeAiSuggestionHideDetails => 'Hide details';

  @override
  String get knowledgeAiSuggestionAccept => 'Accept suggestion';

  @override
  String get knowledgeAiSuggestionDismiss => 'Dismiss suggestion';

  @override
  String get knowledgeAiSuggestionPayloadTitle => 'Suggested fields';

  @override
  String get knowledgeAiSuggestionSnoozeOneDay => 'Remind tomorrow';

  @override
  String get knowledgeAiSuggestionSnoozedToast =>
      'Suggestion will return tomorrow.';

  @override
  String get knowledgeAiSuggestionAppliedToast =>
      'Suggestion applied to the note.';

  @override
  String get knowledgeAiSuggestionViewAction => 'View';

  @override
  String get knowledgeAiSuggestionDismissedToast => 'Suggestion dismissed.';

  @override
  String get knowledgeAiSuggestionFeedbackLabel =>
      'Was this suggestion useful?';

  @override
  String get knowledgeAiSuggestionFeedbackGood => 'Useful';

  @override
  String get knowledgeAiSuggestionFeedbackBad => 'Not useful';

  @override
  String get knowledgeAiSuggestionFeedbackToast => 'Feedback saved.';

  @override
  String get knowledgeAiSuggestionMoreActions => 'More actions';

  @override
  String knowledgeAiSuggestionClassificationSummary(String kind) {
    return 'Organize as $kind';
  }

  @override
  String knowledgeAiSuggestionTagsSummary(String tags) {
    return 'Add tags: $tags';
  }

  @override
  String knowledgeAiSuggestionDecisionLinksSummary(int count) {
    return 'Link to $count related decisions';
  }

  @override
  String get knowledgeAiSuggestionFieldTags => 'Tags';

  @override
  String get knowledgeAiSuggestionFieldDecisions => 'Related decisions';

  @override
  String get knowledgeAgentAssumptionTitle =>
      'Assumptions to verify this month';

  @override
  String get knowledgeAgentAssumptionNoStale => 'No stale active assumptions.';

  @override
  String knowledgeAgentAssumptionSummaryOne(Object days, Object first) {
    return '1 active assumption has not been verified for more than $days days: $first';
  }

  @override
  String knowledgeAgentAssumptionSummaryMany(
    Object count,
    Object days,
    Object first,
  ) {
    return '$count active assumptions have not been verified for more than $days days. First: $first';
  }

  @override
  String get knowledgeAgentReviewTitle => 'Weekly review';

  @override
  String get knowledgeAgentReviewNothingDue =>
      'Nothing is due for review this week.';

  @override
  String knowledgeAgentReviewDecisionOne(Object first) {
    return '1 decision is due for review: $first';
  }

  @override
  String knowledgeAgentReviewDecisionMany(Object count, Object first) {
    return '$count decisions are due for review. First: $first';
  }

  @override
  String knowledgeAgentReviewAssumptionOne(Object days, Object first) {
    return '1 assumption has not been verified for more than $days days: $first';
  }

  @override
  String knowledgeAgentReviewAssumptionMany(
    Object count,
    Object days,
    Object first,
  ) {
    return '$count assumptions have not been verified for more than $days days. First: $first';
  }

  @override
  String get knowledgeAgentContradictionTitle => 'Decision conflicts detected';

  @override
  String get knowledgeAgentContradictionNone =>
      'No contradictions detected in the last 90-day window.';

  @override
  String knowledgeAgentContradictionInvalidatedAssumption(Object assumptionId) {
    return 'This decision still references assumption $assumptionId, but that assumption is no longer active (possibly falsified or retired).';
  }

  @override
  String knowledgeAgentContradictionSummaryOne(Object detail, Object kind) {
    return 'Detected 1 $kind issue: $detail';
  }

  @override
  String knowledgeAgentContradictionSummaryMany(
    Object count,
    Object detail,
    Object kind,
  ) {
    return 'Detected $count conflicts. First: $kind → $detail';
  }

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
  String get knowledgeMarkdownBold => 'Bold';

  @override
  String get knowledgeMarkdownLink => 'Link';

  @override
  String get knowledgeMarkdownBulletedList => 'Bulleted list';

  @override
  String get knowledgeMarkdownQuote => 'Quote';

  @override
  String get knowledgeMarkdownInlineCode => 'Inline code';

  @override
  String knowledgeMarkdownTableLabel(int rows, int columns) {
    return 'Table, $rows rows and $columns columns';
  }

  @override
  String knowledgeMarkdownImageLabel(String description) {
    return 'Image: $description';
  }

  @override
  String get knowledgeDecisionNotFound =>
      'Decision does not exist or was deleted';

  @override
  String get knowledgeDecisionDetailTitle => 'Decision details';

  @override
  String get knowledgeDecisionActionPrompt =>
      'Turn this decision into one concrete next step.';

  @override
  String get knowledgeActionLinked => 'A follow-up action is already linked.';

  @override
  String get knowledgeActionCreate => 'Create action';

  @override
  String get knowledgeActionOpen => 'Open action';

  @override
  String get knowledgeActionCreated => 'Follow-up action created';

  @override
  String get knowledgeActionUnavailable =>
      'Enable ExecutionOS to create a follow-up action.';

  @override
  String knowledgeActionFailed(String error) {
    return 'Could not create the action: $error';
  }

  @override
  String get knowledgeNoteActionPrompt =>
      'Turn this note into one concrete follow-up.';

  @override
  String knowledgeNoteActionDraftTitle(String note) {
    return 'Follow up: $note';
  }

  @override
  String get knowledgeExperimentActionPrompt =>
      'Turn this experiment into its next concrete step.';

  @override
  String knowledgeExperimentActionDraftTitle(String experiment) {
    return 'Run experiment: $experiment';
  }

  @override
  String knowledgeDecisionActionDraftTitle(String decision) {
    return 'Follow up: $decision';
  }

  @override
  String knowledgeDecisionActionDraftNote(String choice) {
    return 'Decision: $choice';
  }

  @override
  String knowledgeDecisionDecidedAt(Object date) {
    return 'Decided on $date';
  }

  @override
  String knowledgeDecisionDecidedAtWithReview(
    Object decidedDate,
    Object reviewDate,
  ) {
    return 'Decided on $decidedDate · Review $reviewDate';
  }

  @override
  String get knowledgeNoteDetailTitle => 'Note';

  @override
  String get knowledgeNoteEditTitle => 'Edit note';

  @override
  String get knowledgeNoteEditSubtitle =>
      'Update title, content, and metadata.';

  @override
  String get knowledgeNoteSourceUrlLabel => 'Source URL';

  @override
  String get knowledgeNoteTagsHint => '\"investing\", \"fire\", \"banking\"';

  @override
  String get knowledgeNoteProjectHint => '\"fire-plan\", \"health-2026\"';

  @override
  String get knowledgeConceptDetailTitle => 'Concept';

  @override
  String get knowledgeExperimentDetailTitle => 'Experiment';

  @override
  String get knowledgePrincipleDetailTitle => 'Principle';

  @override
  String get knowledgeAssumptionDetailTitle => 'Assumption';

  @override
  String get knowledgeRoutineDetailTitle => 'Routine';

  @override
  String get knowledgeObjectDetailTitle => 'Details';

  @override
  String get knowledgeDetailOptionsTitle => 'Options';

  @override
  String get knowledgeDetailMetadataTitle => 'Metadata';

  @override
  String get knowledgeDetailRationaleTitle => 'Rationale';

  @override
  String get knowledgeDetailPrinciplesTitle => 'Referenced principles';

  @override
  String get knowledgeDetailAssumptionsTitle => 'Referenced assumptions';

  @override
  String get knowledgeDetailActualOutcomeTitle => 'Actual outcome';

  @override
  String get knowledgeDetailExpectedOutcomeTitle => 'Expected outcome';

  @override
  String get knowledgeDetailMetricsTitle => 'Metrics';

  @override
  String get knowledgeDetailEvolutionTitle => 'Cognitive trail';

  @override
  String get knowledgeDetailSummaryTitle => 'Summary';

  @override
  String get knowledgeDetailRelatedConceptsTitle => 'Related concepts';

  @override
  String get knowledgeDetailMethodTitle => 'Method';

  @override
  String get knowledgeDetailResultTitle => 'Result';

  @override
  String get knowledgeDetailConclusionTitle => 'Conclusion';

  @override
  String get knowledgeDetailEvidenceTitle => 'Evidence';

  @override
  String get knowledgeDetailBodyTitle => 'Body';

  @override
  String get knowledgeDetailSourceTitle => 'Source';

  @override
  String get knowledgeSourceOpenConfirmTitle => 'Open source link?';

  @override
  String get knowledgeSourceOpenConfirmBody =>
      'You\'ll leave NaviWealth to open this external source. Confirm the destination.';

  @override
  String get knowledgeSourceOpenAction => 'Open';

  @override
  String get knowledgeSourceOpenFailed => 'Could not open the source link.';

  @override
  String get knowledgeSourceCopyAction => 'Copy source URL';

  @override
  String knowledgeDetailAliases(Object aliases) {
    return 'Aliases: $aliases';
  }

  @override
  String knowledgeDetailRelatedConceptCount(Object count) {
    return '$count related';
  }

  @override
  String knowledgeDetailEvidenceCount(Object count) {
    return '$count references';
  }

  @override
  String knowledgeDetailScope(Object scope) {
    return 'Scope: $scope';
  }

  @override
  String knowledgeDetailConfidenceScope(Object confidence, Object scope) {
    return 'Confidence $confidence · scope $scope';
  }

  @override
  String get knowledgeDetailContextSnapshotTitle =>
      'Cross-domain state at the time';

  @override
  String knowledgeDetailContextSnapshotCaptured(Object date, Object days) {
    return 'Captured on $date · $days-day window';
  }

  @override
  String get knowledgeDetailContextSnapshotEmpty =>
      'No cross-domain events in that window.';

  @override
  String get knowledgeDetailContextSnapshotFinance => 'Finance';

  @override
  String get knowledgeDetailContextSnapshotHealth => 'Health';

  @override
  String get knowledgeDetailCreatedLabel => 'Created';

  @override
  String get knowledgeDetailUpdatedLabel => 'Updated';

  @override
  String knowledgeDetailUpdatedAt(Object date) {
    return 'Updated $date';
  }

  @override
  String get knowledgeDetailProjectLabel => 'Project';

  @override
  String get knowledgeDetailTagsLabel => 'Tags';

  @override
  String get knowledgeDetailAliasesLabel => 'Aliases';

  @override
  String get knowledgeDetailStartedLabel => 'Started';

  @override
  String get knowledgeDetailEndedLabel => 'Ended';

  @override
  String get knowledgeDetailNextDueLabel => 'Next due';

  @override
  String get knowledgeDetailLastDoneLabel => 'Last done';

  @override
  String get knowledgeDetailIntervalLabel => 'Interval';

  @override
  String get knowledgeDetailTargetAssumptionTitle => 'Target assumption';

  @override
  String get knowledgeDetailScopeLabel => 'Scope';

  @override
  String get knowledgeDetailDeclaredLabel => 'Declared';

  @override
  String get knowledgeDetailConfidenceLabel => 'Confidence';

  @override
  String get knowledgeDetailLastVerifiedLabel => 'Last verified';

  @override
  String get knowledgeDetailDecisionsTitle => 'Related decisions';

  @override
  String get knowledgeDetailExperimentsTitle => 'Related experiments';

  @override
  String get knowledgeLibraryDeleteTooltip => 'Delete';

  @override
  String get knowledgeLibraryDeleteTitle => 'Delete entry?';

  @override
  String knowledgeLibraryDeleteBody(Object title) {
    return '\"$title\" will be removed from Library and cleaned from AI memory after the next index sync.';
  }

  @override
  String knowledgeLibraryDeleteImpactBody(
    Object attachmentCount,
    Object referenceCount,
    Object relationCount,
    Object title,
  ) {
    return '\"$title\" has $relationCount relation(s), $referenceCount inline reference(s), and $attachmentCount attachment(s). Relations will be detached; referenced items and attachment files remain. You can undo this deletion.';
  }

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
  String get transferSwapAccountsAction => 'Swap accounts';

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
  String get transferDetailsTitle => 'Date & note';

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
  String get spendingTitle => 'Spending';

  @override
  String get expenseReportRangeThisMonth => 'This month';

  @override
  String get expenseReportRangeThisMonthCompact => 'MTD';

  @override
  String get expenseReportRangeLast3Months => 'Last 3 months';

  @override
  String get expenseReportRange3mCompact => '3M';

  @override
  String get expenseReportRangeLast6Months => 'Last 6 months';

  @override
  String get expenseReportRange6mCompact => '6M';

  @override
  String get expenseReportRangeLast12Months => 'Last 12 months';

  @override
  String get expenseReportRange12mCompact => '12M';

  @override
  String get expenseReportRangeCustom => 'Custom';

  @override
  String get expenseReportRangeCustomCompact => 'Range';

  @override
  String get expenseReportTotalExpenses => 'Total expenses';

  @override
  String get expenseReportDailyAverage => 'Daily avg';

  @override
  String get expenseReportEntryCount => 'Entries';

  @override
  String get expenseReportCategoryCount => 'Categories';

  @override
  String expenseReportSkippedFx(int count) {
    return '$count expenses excluded — missing FX rate.';
  }

  @override
  String expenseReportBaseCurrency(String currency, int days) {
    return 'Base currency $currency · $days calendar days';
  }

  @override
  String get expenseReportCategoryShare => 'Category share';

  @override
  String get expenseReportUncategorized => 'Uncategorized';

  @override
  String get expenseReportOtherCategories => 'Other';

  @override
  String expenseReportOtherCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count categories',
      one: '1 category',
    );
    return '$_temp0';
  }

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
  String assetDetailLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get assetDetailNotFound => 'Asset not found or deleted';

  @override
  String get assetDetailUnsupportedType =>
      'This asset type does not support manual editing';

  @override
  String get manualAssetDetailEditAction => 'Edit asset';

  @override
  String get manualAssetDetailCurrentValue => 'Current value';

  @override
  String get manualAssetDetailAccount => 'Held in';

  @override
  String get manualAssetDetailPrincipal => 'Principal';

  @override
  String get manualAssetDetailAnnualRate => 'Annual rate';

  @override
  String get manualAssetDetailExpectedReturn => 'Expected annual return';

  @override
  String get manualAssetDetailStartDate => 'Start date';

  @override
  String get manualAssetDetailMaturityDate => 'Maturity date';

  @override
  String get manualAssetDetailIssuer => 'Issuer';

  @override
  String get manualAssetDetailProductCode => 'Product code';

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
  String get assetDetailLastClose => 'Latest close';

  @override
  String get assetDetailValuationPrice => 'Valuation price';

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
  String get depositDetailsTitle => 'Dates & valuation';

  @override
  String get depositDetailsTermSummary => 'Maturity, renewal & current value';

  @override
  String get depositDetailsDemandSummary => 'Value date & current value';

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
  String get wealthProductDetailsTitle => 'Product details';

  @override
  String get wealthProductDetailsSummary => 'Issuer, dates & current value';

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
  String get activityAddAction => 'Record entry';

  @override
  String get activityFeedFilterTitle => 'Filter';

  @override
  String get activityFeedFilterClear => 'Clear';

  @override
  String get activityFeedFilterApply => 'Apply filters';

  @override
  String get activityFeedFilterAllDates => 'All dates';

  @override
  String get activityFeedFilterAllKinds => 'All kinds';

  @override
  String activityFeedFilterKindCount(int count) {
    return '$count kinds';
  }

  @override
  String activityFeedFilterAccountCount(int count) {
    return '$count accounts';
  }

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
      one: '1 remote row was ignored because its namespace is not supported here',
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
  String get syncStabilityPassing => 'Stability gate passed';

  @override
  String get syncStabilityFailing => 'Sync stability needs attention';

  @override
  String get syncStabilityCollecting => 'Collecting stability evidence';

  @override
  String syncStabilityWindow(int successful, int total, int days) {
    return '$successful/$total successful · $days days observed';
  }

  @override
  String syncStabilitySuccessRate(int percent) {
    return 'Success $percent%';
  }

  @override
  String syncStabilityFatal(int count) {
    return 'Fatal $count';
  }

  @override
  String syncStabilityResetFailures(int count) {
    return 'Reset failures $count';
  }

  @override
  String syncStabilityRecoveries(int count) {
    return 'Recoveries $count';
  }

  @override
  String get syncStabilityPassingDetail =>
      'All local release thresholds are currently met';

  @override
  String syncStabilityNeedSamples(int count) {
    return '$count more terminal cycles needed';
  }

  @override
  String syncStabilityNeedDuration(int days) {
    return '$days more observation days needed';
  }

  @override
  String syncStabilityBelowSuccess(int percent) {
    return 'Needs at least $percent% success';
  }

  @override
  String get syncStabilityFatalBlocker =>
      'Fatal protocol errors must return to zero';

  @override
  String get syncStabilityResetBlocker =>
      'Generation-reset failures must return to zero';

  @override
  String get syncStabilityPrivacyNote =>
      'Device-local aggregate · no row payloads or ids retained';

  @override
  String get syncStabilityCopyEvidence => 'Copy evidence';

  @override
  String get syncStabilityEvidenceCopied => 'Sync stability evidence copied.';

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
  String get ingestReviewTitle => 'Review entries';

  @override
  String get ingestCopyDiagnostics => 'Copy privacy-safe import diagnostics';

  @override
  String get ingestDiagnosticsCopied => 'Import diagnostics copied';

  @override
  String ingestAccountsLoadError(String error) {
    return 'Failed to load accounts: $error';
  }

  @override
  String ingestQueueLoadError(String error) {
    return 'Failed to load the queue: $error';
  }

  @override
  String get ingestExpenseAccountLabel => 'Account';

  @override
  String ingestConfirmAllFresh(int count) {
    return 'Confirm all · new only ($count)';
  }

  @override
  String get ingestSelectAccountFirst => 'Pick a statement account first';

  @override
  String get ingestServiceNotReady => 'Service not ready yet';

  @override
  String get ingestRecorded => 'Recorded';

  @override
  String ingestSummaryTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries recorded',
      one: '1 entry recorded',
    );
    return '$_temp0';
  }

  @override
  String ingestSummaryFailures(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need review',
      one: '1 item needs review',
    );
    return '$_temp0';
  }

  @override
  String get ingestSummaryBody =>
      'Entries are in your activity feed and already reflected in balances.';

  @override
  String get ingestSummaryViewActivity => 'View activity';

  @override
  String get agentResultsLoadingTitle => 'Assistant is checking in';

  @override
  String get agentResultsLoadingBody => 'Fetching the latest agent results…';

  @override
  String get agentResultsErrorTitle => 'Agent results unavailable';

  @override
  String get agentResultsEmptyTitle => 'No agent results yet';

  @override
  String get agentResultsEmptyBody =>
      'Run the agent to get a fresh readout of this domain.';

  @override
  String get agentResultsGenerateAction => 'Generate';

  @override
  String get knowledgeStatusActive => 'Active';

  @override
  String get knowledgeStatusPaused => 'Paused';

  @override
  String get knowledgeStatusRetired => 'Retired';

  @override
  String get knowledgeStatusWeakened => 'Weakened';

  @override
  String get knowledgeStatusFalsified => 'Falsified';

  @override
  String get knowledgeStatusPlanned => 'Planned';

  @override
  String get knowledgeStatusRunning => 'Running';

  @override
  String get knowledgeStatusDone => 'Done';

  @override
  String get knowledgeStatusAbandoned => 'Abandoned';

  @override
  String get knowledgeStatusArchived => 'Archived';

  @override
  String ingestRecordedN(int count) {
    return 'Recorded $count';
  }

  @override
  String ingestRecordedPartial(int success, int failed) {
    return 'Recorded $success; $failed need attention';
  }

  @override
  String ingestRecordingProgress(int completed, int total) {
    return 'Recording $completed of $total entries.';
  }

  @override
  String get ingestRecordFailed => 'Couldn’t record this entry. Try again.';

  @override
  String get ingestRecordNeedsReview =>
      'This entry may already be recorded. Resolve its review state before taking another action.';

  @override
  String get ingestNeedsReviewHint =>
      'This write may already exist in Activity. Resolve the review state instead of recording it again.';

  @override
  String get ingestRecoveryUnavailableHint =>
      'This entry may already exist in Activity, but its recovery details are unavailable. Recording it again is blocked.';

  @override
  String get ingestResolveAction => 'Resolve review state';

  @override
  String get ingestResolvingTitle => 'Resolving review state';

  @override
  String get ingestResolvingBody =>
      'Finishing the review state without recording the entry again.';

  @override
  String get ingestResolveSucceeded => 'Review state resolved';

  @override
  String get ingestResolveFailed =>
      'Couldn’t resolve the review state. Check Activity before trying again.';

  @override
  String get ingestSkipped => 'Entry skipped';

  @override
  String get ingestSkipFailed => 'Couldn’t skip this entry. Try again.';

  @override
  String get ingestRestored => 'Entry restored';

  @override
  String get ingestUndoSucceeded => 'Entry restored to review';

  @override
  String get ingestUndoingTitle => 'Restoring entries';

  @override
  String get ingestUndoFailed =>
      'Couldn’t undo every entry. Review the remaining records.';

  @override
  String ingestUndoProgress(int completed, int total) {
    return 'Restoring $completed of $total entries.';
  }

  @override
  String get ingestPasteTitle => 'Paste statement text';

  @override
  String get ingestPasteHint =>
      'Paste Alipay / WeChat Pay / bank CSV text\ne.g. 2026-05-10,Starbucks,-38.00,CNY';

  @override
  String get ingestPasteRequired => 'Paste statement text before parsing.';

  @override
  String get ingestEmptyPasteCta => 'Paste';

  @override
  String get ingestParseAction => 'Parse';

  @override
  String get ingestParseFailed => 'Couldn’t parse this import. Try again.';

  @override
  String get ingestCaptureFailed => 'Couldn’t read that source. Try again.';

  @override
  String get ingestCaptureUnsupported => 'This file type isn’t supported.';

  @override
  String get ingestCaptureEmpty => 'This source is empty.';

  @override
  String ingestCaptureTooLarge(int maxMiB) {
    return 'This file exceeds the $maxMiB MiB import limit.';
  }

  @override
  String ingestCaptureTextTooLong(int maxCharacters) {
    return 'Text exceeds the $maxCharacters-character import limit.';
  }

  @override
  String get ingestCaptureUnreadable =>
      'This source couldn’t be read. Choose it again.';

  @override
  String get ingestChooseAnotherFile => 'Choose file';

  @override
  String get ingestRetakePhoto => 'Retake';

  @override
  String ingestDroppedSourcesRejected(int count) {
    return 'Couldn’t import $count dropped files.';
  }

  @override
  String get ingestSharedParseRejected =>
      'This shared source couldn’t be parsed.';

  @override
  String get ingestSharedParseFailed =>
      'Something interrupted this shared import.';

  @override
  String get ingestNoTransactions => 'No recognizable transactions';

  @override
  String ingestParseSummary(int total, int fresh, int dup) {
    return 'Parsed $total · $fresh new · $dup possible dup';
  }

  @override
  String ingestParseSummaryWithSkipped(
    int total,
    int fresh,
    int dup,
    int skipped,
  ) {
    return 'Parsed $total · $fresh new · $dup possible dup · $skipped skipped';
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
  String get ingestEditDraft => 'Correct fields';

  @override
  String get ingestEditDescription => 'Description';

  @override
  String get ingestEditAmount => 'Amount';

  @override
  String get ingestEditCurrency => 'Currency';

  @override
  String get ingestEditDate => 'Transaction date';

  @override
  String get ingestEditCategory => 'Category hint (optional)';

  @override
  String get ingestEditInvalid =>
      'Enter a description, positive amount, and currency.';

  @override
  String get ingestEditConflict =>
      'This draft changed while you were editing. Review the latest version and try again.';

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
  String get ingestCaptureMenuAction => 'Add source';

  @override
  String get settingsAiTransparencyTitle => 'AI transparency';

  @override
  String get settingsAiTransparencySubtitle =>
      'View detailed traces from recent AI calls';

  @override
  String get settingsAiLlmTitle => 'AI services · Bring your own API key';

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
  String get aiLlmDeleteTitle => 'Delete provider?';

  @override
  String aiLlmDeleteBody(String name) {
    return 'This removes $name and its stored API key from this device.';
  }

  @override
  String get aiLlmEmpty =>
      'No model providers configured. Add an API key to connect directly from this device.';

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
      'Use your own LLM API key to connect directly from this device to a model provider. You can save multiple providers and switch at any time. API keys stay in this device\'s secure storage (Keychain/Keystore) and are never uploaded, synced, or backed up. Costs and rate limits belong to your provider account.';

  @override
  String get aiLlmUnsupportedTitle =>
      'This platform does not support on-device direct connections';

  @override
  String get aiLlmUnsupportedBody =>
      'Bring-your-own-key AI services are available on iOS, Android, macOS, Windows, and Linux and require system secure storage. Web is not supported yet.';

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
  String get watchlistSelectItem =>
      'Select a symbol to inspect its quote and alert rules';

  @override
  String get watchlistAccountsEntrySubtitle =>
      'Track symbols and local price alerts';

  @override
  String get watchlistAddAction => 'Add symbol';

  @override
  String watchlistRowActionsTitle(String symbol) {
    return 'Actions for $symbol';
  }

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
  String get incomePlannerTitle => 'Options workspace';

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
      'Selling cash-secured puts and covered calls can result in losses. If assigned, a cash-secured put may require you to buy 100 shares at the strike price; a covered call limits potential gains above the strike price. Income Planner only screens opportunities that match your risk preferences. It does not predict prices or place orders. Read OCC Characteristics and Risks of Standardized Options before using this feature.';

  @override
  String get incomePlannerOccAccept => 'I understand the risks · Continue';

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
  String get incomePlannerProfileAdvancedFilters => 'Advanced filters';

  @override
  String get incomePlannerProfileMinDte => 'Min DTE';

  @override
  String get incomePlannerProfileMaxDte => 'Max DTE';

  @override
  String get incomePlannerProfileMinYield => 'Min annual yield';

  @override
  String get incomePlannerProfileMinOpenInterest => 'Min open interest';

  @override
  String get incomePlannerProfileMinVolume => 'Min volume';

  @override
  String get incomePlannerProfileMaxSpread => 'Max spread';

  @override
  String get incomePlannerProfileMaxCapitalPerTrade => 'Max capital per trade';

  @override
  String get incomePlannerProfilePercentHelper =>
      'Enter a percent, e.g. 12 means 12%.';

  @override
  String get incomePlannerProfileValidationNumber => 'Enter a valid number.';

  @override
  String incomePlannerProfileValidationRange(int min, int max) {
    return 'Enter a value from $min to $max.';
  }

  @override
  String get incomePlannerProfileValidationDteOrder =>
      'Max DTE must be greater than or equal to min DTE.';

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
      'No candidates passed your guardrails. Review the reasons below; keeping your current limits and checking again later is a valid outcome.';

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
  String get incomePlannerChipLeaps => 'LEAPS call';

  @override
  String get incomePlannerLaneSellSection => 'Income (puts & calls)';

  @override
  String get incomePlannerLaneLeapsSection => 'LEAPS calls';

  @override
  String get incomePlannerAdjustLeapsBudget => 'Adjust LEAPS budget';

  @override
  String get incomePlannerScanLeapsCta => 'Scan candidates';

  @override
  String get incomePlannerMetricLeapsCost => 'Cost (max loss)';

  @override
  String get incomePlannerMetricLeverage => 'Leverage';

  @override
  String get incomePlannerMetricAnnualCost => 'Annualized time-value cost';

  @override
  String get incomePlannerMetricFundingCoverage => 'Income coverage';

  @override
  String get incomePlannerRiskLow => 'Lower relative risk';

  @override
  String get incomePlannerRiskModerate => 'Moderate relative risk';

  @override
  String get incomePlannerRiskElevated => 'Elevated relative risk';

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
  String get incomePlannerMetricOptionPrice => 'Option price';

  @override
  String get incomePlannerMetricBidAsk => 'Bid / Ask';

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
  String get incomePlannerDetailContractSection => 'Contract';

  @override
  String get incomePlannerDetailLiquiditySection => 'Liquidity';

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
  String get incomePlannerJournalDeleteTitle => 'Delete trade journal entry?';

  @override
  String get incomePlannerJournalDeleteBody =>
      'This removes the entry from statistics, Wheel history, and its mirrored ledger postings.';

  @override
  String get incomePlannerJournalCreditLabel =>
      'Credit received (per contract)';

  @override
  String incomePlannerJournalTotalCredit(String amount) {
    return 'Total premium: $amount';
  }

  @override
  String get incomePlannerAssignmentNeedsAccount =>
      'Link a brokerage account before recording an assignment — otherwise the share leg cannot be booked to the ledger.';

  @override
  String get incomePlannerJournalDebitLabel =>
      'Debit paid to close (per contract)';

  @override
  String get incomePlannerJournalOptionSymbolLabel => 'Option symbol';

  @override
  String get incomePlannerJournalOptionSymbolHint => 'AAPL250620P00190000';

  @override
  String get incomePlannerJournalAmountHint => '0.00';

  @override
  String get incomePlannerJournalBrokerageAccountLabel => 'Brokerage account';

  @override
  String get incomePlannerJournalCashAccountLabel => 'Cash account';

  @override
  String get incomePlannerJournalStrikeLabel => 'Strike price';

  @override
  String get incomePlannerJournalContractSizeLabel => 'Contract size';

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
  String get incomePlannerStatsAction => 'Stats';

  @override
  String get incomePlannerStatsTitle => 'Options review';

  @override
  String get incomePlannerStatsEmptyTitle => 'No trades yet';

  @override
  String get incomePlannerStatsEmptyBody =>
      'Log option trades from Income Planner to review premium, realized P&L, and assignment discipline.';

  @override
  String get incomePlannerStatsOverviewTitle => 'Journal summary';

  @override
  String get incomePlannerStatsTotalTrades => 'Trades';

  @override
  String get incomePlannerStatsOpenTrades => 'Open';

  @override
  String get incomePlannerStatsAssignedTrades => 'Assigned';

  @override
  String get incomePlannerStatsExpiredTrades => 'Expired';

  @override
  String get incomePlannerStatsPremium => 'Premium';

  @override
  String get incomePlannerStatsRealizedPnl => 'Tracked P&L';

  @override
  String get incomePlannerStatsWinRate => 'Win rate';

  @override
  String get incomePlannerStatsAvgHoldingDays => 'Avg days';

  @override
  String incomePlannerStatsMultiCurrencyNote(String currencies) {
    return 'Amounts are shown separately because this journal contains $currencies.';
  }

  @override
  String get incomePlannerStatsPremiumChartTitle => 'Premium by underlying';

  @override
  String optionsExplainYieldStrength(String yieldPct, String score) {
    return 'Annualized yield $yieldPct (score $score)';
  }

  @override
  String optionsExplainLiquidityStrength(
    String spread,
    int openInterest,
    String score,
  ) {
    return 'Good liquidity: bid/ask spread $spread, open interest $openInterest (score $score)';
  }

  @override
  String optionsExplainSafetyStrength(String margin, String score) {
    return 'Margin of safety $margin from breakeven (score $score)';
  }

  @override
  String optionsExplainIvStrength(String iv, String score) {
    return 'Implied volatility $iv is in a resilient range (score $score)';
  }

  @override
  String get optionsExplainIvUnknown => 'unknown';

  @override
  String optionsExplainFitStrength(String score) {
    return 'Fits current positions (score $score)';
  }

  @override
  String optionsExplainEventStrength(String score) {
    return 'No earnings or macro event in the next 7 days (score $score)';
  }

  @override
  String get optionsExplainEventUnavailable =>
      'Event calendar unavailable; event risk is not scored';

  @override
  String optionsExplainGenericScore(String dimension, String score) {
    return '$dimension score $score';
  }

  @override
  String optionsExplainYieldWeak(String yieldPct, String score) {
    return 'Lower annualized yield: $yieldPct (score $score)';
  }

  @override
  String optionsExplainLiquidityWeak(String spread, String score) {
    return 'Moderate liquidity: bid/ask spread $spread (score $score)';
  }

  @override
  String optionsExplainSafetyWeak(String margin, String score) {
    return 'Limited margin of safety: $margin (score $score)';
  }

  @override
  String optionsExplainIvWeak(String score) {
    return 'Implied volatility is outside the normal range (score $score)';
  }

  @override
  String optionsExplainFitWeak(String score) {
    return 'Only a moderate fit with current positions (score $score)';
  }

  @override
  String optionsExplainEventWeak(String score) {
    return 'Execution needs caution inside the event window (score $score)';
  }

  @override
  String get optionsExplainEventCheck =>
      'Check earnings and macro dates before placing the trade';

  @override
  String optionsExplainSummaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) {
    return '$symbol ${dte}DTE sell put @ $strike — annualized $yieldPct, margin of safety $margin';
  }

  @override
  String optionsExplainSummaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) {
    return '$symbol ${dte}DTE covered call @ $strike — annualized $yieldPct, margin of safety $margin';
  }

  @override
  String get optionsExplainBestForPutConservative =>
      'Best for conservative cash-flow preference: higher margin of safety and liquidity first.';

  @override
  String get optionsExplainBestForPutBalanced =>
      'Best for balanced cash-flow preference: balances yield against downside risk.';

  @override
  String get optionsExplainBestForPutAggressive =>
      'Best when you accept higher assignment probability in exchange for annualized yield.';

  @override
  String get optionsExplainBestForCallConservative =>
      'Best for conservative enhancement: sell farther OTM calls with lower assignment probability.';

  @override
  String get optionsExplainBestForCallBalanced =>
      'Best for balanced enhancement: add income without materially disrupting the position.';

  @override
  String get optionsExplainBestForCallAggressive =>
      'Best when you are willing to accept assignment to realize gains.';

  @override
  String get optionsExplainAvoidPut =>
      'Avoid if you are not willing to buy 100 shares at the strike when assigned.';

  @override
  String get optionsExplainAvoidCall =>
      'Avoid if you are not willing to sell 100 shares at the strike.';

  @override
  String optionsExplainWorstPut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  ) {
    return 'If $symbol falls below $strike, you would buy 100 shares at an effective cost of $breakeven, using $cash cash.';
  }

  @override
  String optionsExplainWorstCall(String symbol, String strike, String cap) {
    return 'If $symbol rises to $strike, you would sell 100 shares at $strike and miss upside above that level; total proceeds are capped at $cap.';
  }

  @override
  String optionsExplainLeapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  ) {
    return '$symbol ${dte}DTE LEAPS call @ $strike — cost $cost, delta $delta';
  }

  @override
  String optionsExplainLeapsWorstCase(
    String symbol,
    String strike,
    String cost,
  ) {
    return 'If $symbol closes below $strike at expiration, the entire $cost premium is lost. Maximum loss is the full cost paid.';
  }

  @override
  String get optionsExplainLeapsBestFor =>
      'Best as a funded stock substitute: long-dated deep-in-the-money exposure paid for by wheel or dividend income.';

  @override
  String get optionsExplainLeapsAvoid =>
      'Avoid if you cannot hold through a full drawdown — time value decays and the position can expire worthless.';

  @override
  String optionsExplainLeapsCostBullet(String costPct) {
    return 'Annualized time-value cost $costPct per unit of share exposure';
  }

  @override
  String optionsExplainLeapsLeverageBullet(String leverage, String delta) {
    return 'Controls ${leverage}x the share exposure per unit of capital (delta $delta)';
  }

  @override
  String optionsExplainLeapsIntrinsicBullet(String intrinsicPct) {
    return '$intrinsicPct of the premium is intrinsic value';
  }

  @override
  String optionsExplainLeapsSpreadBullet(String spread) {
    return 'Wide bid/ask spread $spread — LEAPS liquidity is thin, use limit orders';
  }

  @override
  String get optionsExplainLeapsDeltaEstimated =>
      'Delta is estimated from implied volatility — the data source provides no greeks';

  @override
  String optionsExplainLeapsThetaBullet(String extrinsic) {
    return '$extrinsic of time value will decay to zero by expiration';
  }

  @override
  String optionsExplainLeapsFundingBullet(String coverage) {
    return 'Group income already covers $coverage of this cost';
  }

  @override
  String optionsLedgerPremium(String symbol) {
    return 'Options premium $symbol';
  }

  @override
  String optionsLedgerCloseDebit(String symbol) {
    return 'Options close debit $symbol';
  }

  @override
  String optionsLedgerPutAssigned(String symbol) {
    return 'Put assigned $symbol';
  }

  @override
  String optionsLedgerCallAssigned(String symbol) {
    return 'Covered call assigned $symbol';
  }

  @override
  String optionsLedgerLeapsOpen(String symbol) {
    return 'LEAPS open $symbol';
  }

  @override
  String optionsLedgerLeapsClose(String symbol) {
    return 'LEAPS close $symbol';
  }

  @override
  String optionsLedgerLeapsExercise(String symbol) {
    return 'LEAPS exercise $symbol';
  }

  @override
  String optionsLedgerLeapsExpired(String symbol) {
    return 'LEAPS expired $symbol';
  }

  @override
  String get incomePlannerStatsStrategySectionTitle => 'By strategy';

  @override
  String get incomePlannerStatsSymbolSectionTitle => 'By underlying';

  @override
  String incomePlannerStatsTradeCount(int total, int open) {
    return '$total trades · $open open';
  }

  @override
  String incomePlannerStatsSymbolDetail(
    int total,
    int open,
    int assigned,
    int expired,
  ) {
    return '$total trades · $open open · $assigned assigned · $expired expired';
  }

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
  String get incomePlannerOccConfirmation =>
      'I understand that assignment can require buying or selling 100 shares per contract, and that this planner does not place orders or guarantee returns.';

  @override
  String get incomePlannerUnderlyingStrategyRequired =>
      'Enable at least one strategy for this underlying.';

  @override
  String get incomePlannerUnderlyingDeleteTitle =>
      'Remove approved underlying?';

  @override
  String incomePlannerUnderlyingDeleteBody(String symbol) {
    return '$symbol will no longer be included in option scans.';
  }

  @override
  String get incomePlannerSupportedMarketHelper =>
      'Current scans support US-listed stocks and ETFs.';

  @override
  String get incomePlannerMaxBuyPriceLabel =>
      'Highest acceptable assignment price';

  @override
  String get incomePlannerMaxBuyPriceHelper =>
      'Put strikes above this price are rejected. Leave blank for no additional price ceiling.';

  @override
  String get incomePlannerMinSellPriceLabel =>
      'Lowest acceptable call-away price';

  @override
  String get incomePlannerMinSellPriceHelper =>
      'Call strikes below this price are rejected. Leave blank for no additional price floor.';

  @override
  String get incomePlannerUnderlyingNotesLabel => 'Investment stance';

  @override
  String get incomePlannerUnderlyingNotesHelper =>
      'Record why you are willing to own or sell this underlying.';

  @override
  String get incomePlannerPositiveNumberValidation =>
      'Enter a number greater than zero.';

  @override
  String get incomePlannerProfileStrategyRequired =>
      'Enable at least one options strategy.';

  @override
  String incomePlannerProfileAdvancedSummary(
    int minDte,
    int maxDte,
    String capital,
  ) {
    return '$minDte–$maxDte DTE · max $capital% per trade';
  }

  @override
  String get incomePlannerProfileMaxUnderlyingExposure =>
      'Max post-assignment underlying exposure';

  @override
  String get incomePlannerProfilePutDeltaRange => 'Put absolute delta range';

  @override
  String get incomePlannerProfileLeapsSection => 'LEAPS scan';

  @override
  String get incomePlannerProfileSellFilters => 'Sell-side filters';

  @override
  String incomePlannerProfileLeapsSummary(
    int minDte,
    int maxDte,
    String low,
    String high,
  ) {
    return '$minDte–$maxDte DTE · delta $low–$high';
  }

  @override
  String get incomePlannerProfileLeapsMinDte => 'LEAPS min DTE';

  @override
  String get incomePlannerProfileLeapsMaxDte => 'LEAPS max DTE';

  @override
  String get incomePlannerProfileLeapsDeltaRange => 'LEAPS call delta range';

  @override
  String get incomePlannerProfileLeapsMaxSpread => 'LEAPS max spread (%)';

  @override
  String get incomePlannerProfileCallDeltaRange => 'Call delta range';

  @override
  String get incomePlannerProfileDeltaLow => 'Low';

  @override
  String get incomePlannerProfileDeltaHigh => 'High';

  @override
  String get incomePlannerProfileDeltaValidation =>
      'Use a decimal above 0 and at most 1.';

  @override
  String get incomePlannerProfileDeltaOrderValidation =>
      'High delta must be at least the low delta.';

  @override
  String get incomePlannerWorkspaceOpportunities => 'Opportunities';

  @override
  String get incomePlannerWorkspaceJournal => 'Journal';

  @override
  String get incomePlannerWorkspaceCandidates => 'Candidates';

  @override
  String get incomePlannerWorkspaceOpenPositions => 'Open positions';

  @override
  String get incomePlannerWorkspaceApproved => 'Approved';

  @override
  String get incomePlannerWorkspaceNeverScanned => 'not scanned yet';

  @override
  String get incomePlannerWorkspaceScanStale => 'scan is stale';

  @override
  String get incomePlannerWorkspaceScanFresh => 'scan is fresh';

  @override
  String incomePlannerWorkspaceProfileSummary(
    int minDte,
    int maxDte,
    String capital,
    String scanState,
  ) {
    return '$minDte–$maxDte DTE · max $capital per trade · $scanState';
  }

  @override
  String get incomePlannerManageApprovedAction => 'Manage underlyings';

  @override
  String incomePlannerApprovedSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count approved symbols',
      one: '1 approved symbol',
      zero: 'No approved symbols',
    );
    return '$_temp0';
  }

  @override
  String get incomePlannerScanProgressHint =>
      'Keeping cached results visible while fresh option chains are checked. This can take up to 45 seconds.';

  @override
  String incomePlannerScanCompletedToast(int count) {
    return 'Scan complete · $count candidates';
  }

  @override
  String get incomePlannerOpportunityFilterAll => 'All';

  @override
  String incomePlannerOpportunityCountSummary(int visible, int total) {
    return 'Showing $visible of $total, ordered by fit score';
  }

  @override
  String get incomePlannerOpportunityFilterEmpty =>
      'No opportunities match this strategy filter.';

  @override
  String incomePlannerOpportunityExpirySummary(String date, int dte) {
    return 'Expires $date · $dte DTE';
  }

  @override
  String get incomePlannerMetricPremiumTotal => 'Total premium';

  @override
  String get incomePlannerMetricUnderlyingPrice => 'Underlying';

  @override
  String get incomePlannerMetricExpiration => 'Expiration';

  @override
  String get incomePlannerMetricDelta => 'Delta';

  @override
  String get incomePlannerMetricIv => 'Implied volatility';

  @override
  String get incomePlannerMetricOpenInterest => 'Open interest';

  @override
  String get incomePlannerMetricVolume => 'Volume';

  @override
  String get incomePlannerMetricSpread => 'Bid/ask spread';

  @override
  String get incomePlannerScoreYield => 'Yield';

  @override
  String get incomePlannerScoreLiquidity => 'Liquidity';

  @override
  String get incomePlannerScoreSafetyMargin => 'Safety margin';

  @override
  String get incomePlannerScoreIv => 'Volatility fit';

  @override
  String get incomePlannerScorePortfolioFit => 'Portfolio fit';

  @override
  String get incomePlannerScoreEventSafety => 'Event safety';

  @override
  String get incomePlannerRejectionReasonsTitle => 'Main rejection reasons';

  @override
  String incomePlannerRejectionReasonSummary(String reason, int count) {
    return '$reason · $count contracts';
  }

  @override
  String get incomePlannerRejectCapitalLimit => 'Capital limit';

  @override
  String get incomePlannerRejectLiquidity => 'Insufficient liquidity';

  @override
  String get incomePlannerRejectSpread => 'Spread too wide';

  @override
  String get incomePlannerRejectDte => 'Outside DTE range';

  @override
  String get incomePlannerRejectDelta => 'Outside delta range';

  @override
  String get incomePlannerRejectDeltaUnavailable =>
      'Greeks unavailable from the data source';

  @override
  String get incomePlannerRejectLeapsBudget => 'Above the LEAPS budget';

  @override
  String get incomePlannerRejectQuote => 'No usable quote';

  @override
  String get incomePlannerRejectPriceIntent => 'Outside your acceptable price';

  @override
  String get incomePlannerRejectEventRisk => 'Event-risk guard';

  @override
  String get incomePlannerRejectOther => 'Other hard filters';

  @override
  String get incomePlannerApprovedPutNoLimit => 'Put enabled';

  @override
  String incomePlannerApprovedPutLimit(String price) {
    return 'Put ≤ $price';
  }

  @override
  String get incomePlannerApprovedCallNoLimit => 'Call enabled';

  @override
  String incomePlannerApprovedCallLimit(String price) {
    return 'Call ≥ $price';
  }

  @override
  String get incomePlannerJournalOpenedAtLabel => 'Opened on';

  @override
  String get incomePlannerJournalExpirationLabel => 'Expiration';

  @override
  String get incomePlannerJournalClosedAtLabel => 'Resolved on';

  @override
  String get incomePlannerJournalContractQuantityLabel => 'Number of contracts';

  @override
  String get incomePlannerJournalFeesLabel => 'Total fees';

  @override
  String get incomePlannerJournalFilterAll => 'All';

  @override
  String get incomePlannerJournalFilterOpen => 'Open';

  @override
  String get incomePlannerJournalFilterResolved => 'Resolved';

  @override
  String get incomePlannerJournalFilterEmpty =>
      'No journal entries match this filter.';

  @override
  String incomePlannerJournalExpiresIn(int days) {
    return 'expires in ${days}d';
  }

  @override
  String incomePlannerJournalQuantitySummary(int quantity, int size) {
    return '$quantity contract(s) · $size shares each';
  }

  @override
  String get incomePlannerJournalPremiumLabel => 'Premium';

  @override
  String get incomePlannerJournalNetPnlLabel => 'Net P&L';

  @override
  String get planWheelStageMixedOpen => 'Mixed open positions';

  @override
  String incomePlannerWheelOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open positions',
      one: '1 open position',
      zero: 'No open positions',
    );
    return '$_temp0';
  }

  @override
  String incomePlannerWheelDueSummary(String position, int days) {
    return '$position · $days days remaining';
  }

  @override
  String incomePlannerWheelExpiredSummary(String position, int days) {
    return '$position · expired $days days ago — record the outcome';
  }

  @override
  String get incomePlannerWheelRealizedIncome => 'Realized net income';

  @override
  String get incomePlannerWheelOpenPositionsTitle => 'Open positions';

  @override
  String get incomePlannerWheelExpirationMissing =>
      'Expiration is missing · update this journal entry';

  @override
  String get incomePlannerWheelNextReviewOpen =>
      'Review overlapping open positions and verify total exposure.';

  @override
  String get incomePlannerWheelNextWaitPut =>
      'Monitor the open put and record its outcome at expiration or close.';

  @override
  String get incomePlannerWheelNextRecordPut =>
      'Record the put outcome before starting the next leg.';

  @override
  String get incomePlannerWheelNextScanCall =>
      'Shares are held; scan for a covered call only if you are willing to sell.';

  @override
  String get incomePlannerWheelNextWaitCall =>
      'Monitor the covered call and record whether it expires, closes, or is assigned.';

  @override
  String get incomePlannerWheelNextRecordCall =>
      'Record the call-away outcome and verify shares and cash.';

  @override
  String get incomePlannerWheelNextStartPut =>
      'Cash is available; start a new put only for an approved underlying.';

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
  String get settingsUpgradeToCloudHint => 'Sync data across devices';

  @override
  String get settingsSwitchToLocal => 'Switch to Local Mode';

  @override
  String get settingsSwitchToLocalConfirmTitle => 'Switch to Local Mode?';

  @override
  String get settingsSwitchToLocalConfirmBody =>
      'Cloud sync will be disabled. Your data will remain on this device but will no longer sync to other devices.';

  @override
  String get commonDate => 'Date';

  @override
  String get commonNote => 'Note';

  @override
  String get commonOk => 'OK';

  @override
  String get healthTodayTitle => 'Today';

  @override
  String get healthTodayBriefSubtitle => 'Today\'s health overview';

  @override
  String get healthTrendTitle => 'Trends';

  @override
  String get healthPlanTitle => 'Plan';

  @override
  String get healthTabToday => 'Today';

  @override
  String get healthTabTrend => 'Trends';

  @override
  String get healthTabPlan => 'Plan';

  @override
  String get healthSourcesTitle => 'Data sources';

  @override
  String get healthSourcesSubtitle => 'HealthKit / Health Connect and Garmin';

  @override
  String get healthNoDataSyncHint =>
      'Open Sources below to sync or connect a device';

  @override
  String get healthCommandToday => 'Health · Today';

  @override
  String get healthCommandTrend => 'Health · Trends';

  @override
  String get healthCommandPlan => 'Health · Plan';

  @override
  String get healthInputMetricsTitle => 'Input metrics';

  @override
  String get healthConfidenceLabel => 'Confidence';

  @override
  String get healthConfidenceLow => 'Low';

  @override
  String get healthConfidenceMedium => 'Medium';

  @override
  String get healthRecentHrvLabel => 'HRV (recent average)';

  @override
  String get healthRecentSleepLabel => 'Sleep (recent average)';

  @override
  String get healthRecentRhrLabel => 'Resting heart rate (recent average)';

  @override
  String get healthRecentVo2MaxLabel => 'VO₂max (recent average)';

  @override
  String get healthSleepMetricLabel => 'Sleep';

  @override
  String get healthHrvMetricLabel => 'HRV';

  @override
  String get healthHeartRateMetricLabel => 'Heart rate';

  @override
  String get healthWorkoutMetricLabel => 'Workout';

  @override
  String healthWorkoutDurationHoursMinutes(Object hours, Object minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String healthWorkoutDurationMinutes(Object minutes) {
    return '$minutes min';
  }

  @override
  String healthWeeklyWorkoutValue(Object count, Object duration) {
    return '$duration · $count workouts';
  }

  @override
  String get healthStepsMetricLabel => 'Steps';

  @override
  String get healthEnergyMetricLabel => 'Energy';

  @override
  String get healthLoadingLabel => 'Loading...';

  @override
  String get healthTrendGroupRecovery => 'Recovery';

  @override
  String get healthTrendGroupActivity => 'Activity';

  @override
  String get healthTrendGroupBody => 'Body';

  @override
  String healthTrendLoadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get healthTrendNotEnoughData => 'Not enough data yet.';

  @override
  String get healthTrendHrvSubtitle => 'Heart-rate variability ';

  @override
  String get healthTrendSleepSubtitle => 'Nightly hours ';

  @override
  String get healthTrendHeartRateSubtitle => 'Daily average heart rate ';

  @override
  String get healthTrendRespiratoryTitle => 'Respiration';

  @override
  String get healthTrendRespiratorySubtitle =>
      'Daily average respiratory rate ';

  @override
  String get healthTrendRhrTitle => 'Resting HR';

  @override
  String get healthTrendRhrSubtitle => 'Daily resting heart rate ';

  @override
  String get healthTrendWorkoutSubtitle => 'Daily minutes ';

  @override
  String get healthTrendStepsSubtitle => 'Daily steps ';

  @override
  String get healthTrendWalkingDistanceTitle => 'Walking distance';

  @override
  String get healthTrendWalkingDistanceSubtitle => 'Daily kilometers ';

  @override
  String get healthTrendFlightsTitle => 'Flights climbed';

  @override
  String get healthTrendFlightsSubtitle => 'Daily flights climbed ';

  @override
  String get healthTrendWeightTitle => 'Weight';

  @override
  String get healthTrendWeightSubtitle => 'Weight records ';

  @override
  String get healthTrendBodyFatTitle => 'Body fat';

  @override
  String get healthTrendBodyFatSubtitle => 'Body fat percentage ';

  @override
  String get healthTrendVo2MaxTitle => 'VO₂max';

  @override
  String get healthTrendVo2MaxSubtitle => 'Max oxygen uptake ';

  @override
  String get healthBodyBatteryMetricLabel => 'Body Battery';

  @override
  String get healthStressMetricLabel => 'Stress';

  @override
  String get healthRhrMetricLabel => 'RHR';

  @override
  String get healthTrainingLoadMetricLabel => 'Load';

  @override
  String get healthSleepDeepLabel => 'Deep';

  @override
  String get healthSleepRemLabel => 'REM';

  @override
  String get healthSleepLightLabel => 'Light';

  @override
  String get healthSleepAwakeLabel => 'Awake';

  @override
  String get healthTrendBodyBatteryTitle => 'Body Battery';

  @override
  String get healthTrendBodyBatterySubtitle => 'Daily max level';

  @override
  String get healthTrendStressTitle => 'Stress';

  @override
  String get healthTrendStressSubtitle => 'Daily average level ';

  @override
  String get healthTrendTrainingLoadTitle => 'Training load';

  @override
  String get healthTrendTrainingLoadSubtitle => 'Weekly training load';

  @override
  String get healthTrendTrainingEffectTitle => 'Training effect';

  @override
  String get healthTrendTrainingEffectSubtitle => 'Fitness improvement signal';

  @override
  String get healthWeeklySummaryTitle => 'Weekly status';

  @override
  String get healthWeeklySummarySubtitle =>
      'Key health signals from the last 7 days';

  @override
  String get healthWeeklySummaryEmpty =>
      'Sync a few days of data to summarize steps, sleep, training, and recovery here.';

  @override
  String get healthSpo2MetricLabel => 'SpO₂';

  @override
  String get healthTrendSpo2Title => 'Blood oxygen';

  @override
  String get healthTrendSpo2Subtitle => 'Daily average SpO₂';

  @override
  String get healthTrendTotalEnergyTitle => 'Total energy';

  @override
  String get healthTrendTotalEnergySubtitle => 'Daily total calories burned';

  @override
  String get healthKitTitle => 'HealthKit / Health Connect';

  @override
  String get healthSyncAction => 'Sync';

  @override
  String get healthSyncPermissionDenied => 'Permission denied';

  @override
  String get healthSyncingData => 'Syncing health data…';

  @override
  String get healthSyncReady => 'Sync last 30 days of health data';

  @override
  String healthSyncResult(Object unchanged, Object upserted) {
    return 'Synced $upserted new · $unchanged unchanged';
  }

  @override
  String get healthSyncFailed => 'Sync failed';

  @override
  String get healthSourceChecking => 'Checking connection…';

  @override
  String get healthSourceReady => 'Ready';

  @override
  String get healthSourcePermissionRequired => 'Permission needed';

  @override
  String get healthSourceUnavailable => 'Unavailable';

  @override
  String get healthSourceSyncFailed => 'Sync failed';

  @override
  String healthSourceLastSync(String time) {
    return 'Synced $time';
  }

  @override
  String healthSourceLastAttempt(String time) {
    return 'Tried $time';
  }

  @override
  String healthSourceLastSuccess(String time) {
    return 'Last success $time';
  }

  @override
  String healthSourceDataAt(String time) {
    return 'Data $time';
  }

  @override
  String get healthSourceNoData => 'No data imported yet';

  @override
  String get healthSyncButton => 'Sync';

  @override
  String get healthSyncingButton => 'Syncing';

  @override
  String get healthRecoveryTitle => 'Today\'s Recovery';

  @override
  String get healthRecoveryRested => 'Rested';

  @override
  String get healthRecoveryBalanced => 'Balanced';

  @override
  String get healthRecoveryStrained => 'Strained';

  @override
  String get healthRecoveryInsufficient => 'Insufficient data';

  @override
  String get healthRecoveryRestedTip =>
      'Schedule high-intensity training or deep-focus work today.';

  @override
  String get healthRecoveryBalancedTip =>
      'Maintain your usual pace — don\'t push to the limit.';

  @override
  String get healthRecoveryStrainedTip =>
      'Light activity, extra sleep. Avoid stacking pressure.';

  @override
  String get healthRecoveryInsufficientTip =>
      'Sync data and track for a few days for stable recovery advice.';

  @override
  String agentResultUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String get healthNoData => 'No data yet';

  @override
  String get healthShowAllMetrics => 'Show all metrics';

  @override
  String get healthShowKeyMetrics => 'Show key metrics';

  @override
  String healthMoreMetrics(int count) {
    return 'More · $count';
  }

  @override
  String get healthCollapseMetrics => 'Show less';

  @override
  String get healthMorePlanActions => 'More actions';

  @override
  String get healthCollapsePlanActions => 'Show less';

  @override
  String get healthPlanTodayActions => 'Today\'s actions';

  @override
  String get healthPlanHighIntensity =>
      'Schedule high-intensity training or deep-focus work.';

  @override
  String get healthPlanKeepSleep =>
      'Keep normal sleep window; avoid overdrawing.';

  @override
  String get healthPlanTrainAsPlanned =>
      'Train as planned, keep 10-20% headroom.';

  @override
  String get healthPlanReduceCaffeine =>
      'Cut afternoon caffeine; protect evening recovery.';

  @override
  String get healthPlanLightActivity =>
      'Switch to walking, stretching, or Zone 2.';

  @override
  String get healthPlanAvoidPressure =>
      'Avoid back-to-back high-pressure meetings and evening training.';

  @override
  String get healthPlanSyncFirst => 'Sync Health Connect data first.';

  @override
  String get healthPlanTrackMore =>
      'Track for a few more days before judging trends.';

  @override
  String get healthPlanEnableHint =>
      'Enable HealthOS in Settings → Domains to see recovery advice.';

  @override
  String get healthPlanDisclaimerTitle => 'Health guidance only';

  @override
  String get healthPlanDisclaimer =>
      'Not a medical diagnosis. HealthOS does not auto-adjust your schedule.';

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
  String get knowledgeInboxTitle => 'Inbox';

  @override
  String knowledgeInboxSuggestionsPending(int count) {
    return '$count AI suggestions are ready for review';
  }

  @override
  String get knowledgeInboxSuggestionsLoading =>
      'Checking asynchronous AI suggestions…';

  @override
  String get knowledgeInboxSuggestionsLoadFailed =>
      'Organization status failed to load. Tap to retry.';

  @override
  String get knowledgeInboxAiUnavailable =>
      'Notes save normally. Configure a device LLM to receive asynchronous classification and tag suggestions.';

  @override
  String get knowledgeTabInbox => 'Inbox';

  @override
  String get knowledgeTabLibrary => 'Library';

  @override
  String get knowledgeTabReview => 'Review';

  @override
  String get knowledgeCommandInbox => 'Knowledge · Inbox';

  @override
  String get knowledgeCommandLibrary => 'Knowledge · Library';

  @override
  String get knowledgeCommandReview => 'Knowledge · Review';

  @override
  String get knowledgeProposalCaptureUpgrade => 'Capture upgrade';

  @override
  String get knowledgeProposalMerge => 'Merge duplicates';

  @override
  String get knowledgeProposalRoutine => 'Routine';

  @override
  String get knowledgeProposalConceptLink => 'Concept link';

  @override
  String get knowledgeProposalRowType => 'Type';

  @override
  String get knowledgeProposalRowContent => 'Content';

  @override
  String get knowledgeProposalRowScope => 'Scope';

  @override
  String get knowledgeProposalRowConfidence => 'Confidence';

  @override
  String get knowledgeProposalRowLink => 'Link';

  @override
  String get knowledgeProposalRowRelation => 'Relation';

  @override
  String get knowledgeProposalRowKeep => 'Keep';

  @override
  String get knowledgeProposalRowSoftMerge => 'Merge (soft delete)';

  @override
  String get knowledgeProposalRowMergedTags => 'Merged tags';

  @override
  String get knowledgeProposalRowItem => 'Item';

  @override
  String get knowledgeProposalRowInterval => 'Interval';

  @override
  String knowledgeProposalIntervalDays(int days) {
    return 'Every $days days';
  }

  @override
  String get knowledgeInboxEmptyTitle => 'Inbox is empty';

  @override
  String get knowledgeInboxEmptyBody =>
      'Capture the thought first. KnowledgeOS organizes it in the background, and you approve every upgrade.';

  @override
  String get knowledgeInboxLoadFailedTitle => 'Inbox failed to load';

  @override
  String get knowledgeCaptureAction => 'New capture';

  @override
  String get knowledgeCreateEntry => 'New Entry';

  @override
  String get knowledgeCaptureTitle => 'Capture a thought';

  @override
  String get knowledgeCaptureDraftRecovered =>
      'Recovered your unfinished capture from this device.';

  @override
  String get knowledgeCaptureDraftDiscard => 'Discard draft';

  @override
  String get knowledgeCaptureDraftCleared => 'Draft cleared';

  @override
  String get knowledgeCaptureTitleField => 'Title (optional)';

  @override
  String get knowledgeCaptureBodyField => 'Content';

  @override
  String get knowledgeCaptureTitleHint =>
      '\"Bank card needs regular activity\"';

  @override
  String get knowledgeCaptureBodyHint =>
      '\"Make one bank-card activity transaction every 6 months, otherwise it may become dormant\"';

  @override
  String get knowledgeCaptureSavedClassifyingTitle => 'Saved · AI is analyzing';

  @override
  String get knowledgeCaptureSavedPreviewTitle => 'Saved capture';

  @override
  String get knowledgeCaptureSuggestionTitle => 'AI suggestion';

  @override
  String get knowledgeCaptureComposeSubtitle =>
      'Write naturally. AI can shape the title and Markdown before anything is saved.';

  @override
  String get knowledgeCaptureClassifyingSubtitle =>
      'The note is saved. AI is checking whether it should become a routine, decision, or another type of knowledge.';

  @override
  String get knowledgeCaptureSuggestionSubtitle =>
      'Review the extracted type and fields before applying.';

  @override
  String get knowledgeCaptureTypeLabel => 'Save as';

  @override
  String get knowledgeCaptureKindAuto => 'Auto';

  @override
  String get knowledgeCaptureKindAutoDescription =>
      'Let KnowledgeOS classify it after saving';

  @override
  String get knowledgeCaptureKindNote => 'Note';

  @override
  String get knowledgeCaptureKindRoutine => 'Routine';

  @override
  String get knowledgeCaptureKindDecision => 'Decision';

  @override
  String get knowledgeCaptureKindAssumption => 'Assumption';

  @override
  String get knowledgeCaptureKindPrinciple => 'Principle';

  @override
  String get knowledgeCaptureKindConcept => 'Concept';

  @override
  String get knowledgeCaptureKindExperiment => 'Experiment';

  @override
  String get knowledgeCaptureSave => 'Save';

  @override
  String get knowledgeCaptureSavedToast =>
      'Saved to Inbox. Classification and links will be suggested in the background.';

  @override
  String get knowledgeCaptureOrganizeAction => 'Organize & preview';

  @override
  String get knowledgeCaptureOrganizing => 'Organizing...';

  @override
  String get knowledgeCaptureOrganizingSubtitle =>
      'AI is shaping the title, hierarchy, and Markdown while preserving your meaning.';

  @override
  String get knowledgeCaptureOrganizingBody =>
      'Creating a complete, readable draft. Your original remains unchanged until you approve it.';

  @override
  String get knowledgeCaptureOrganizedSubtitle =>
      'Review the rendered result, or switch to Edit for final adjustments before saving.';

  @override
  String get knowledgeCaptureAiOrganizationHint =>
      'AI will improve the title, structure, and reading flow without adding new facts.';

  @override
  String get knowledgeCaptureSaveWithoutAi => 'Save original';

  @override
  String get knowledgeCaptureSaveOrganized => 'Save organized note';

  @override
  String get knowledgeCaptureReviewDraftTitle => 'Organized draft';

  @override
  String get knowledgeCaptureReviewDraftSubtitle =>
      'Preview first; every field remains editable.';

  @override
  String get knowledgeCaptureOriginalVersion => 'Original';

  @override
  String get knowledgeCaptureOrganizedVersion => 'AI-organized draft';

  @override
  String get knowledgeCaptureShowOriginal => 'View original';

  @override
  String get knowledgeCaptureShowOrganized => 'View organized';

  @override
  String get knowledgeCaptureUntitledOriginal => 'Untitled original';

  @override
  String get knowledgeCaptureOrganizeFailed =>
      'AI could not produce a safe complete draft. Your original is unchanged.';

  @override
  String knowledgeCaptureSaveTyped(String kind) {
    return 'Save as $kind';
  }

  @override
  String get knowledgeCaptureSaving => 'Saving...';

  @override
  String get knowledgeCaptureCancel => 'Cancel';

  @override
  String get knowledgeCaptureClassifyingBody =>
      'Reasoning can take 20-30 seconds. The Note is already saved, so you can skip waiting.';

  @override
  String get knowledgeCaptureSkipClassification => 'Keep as Note';

  @override
  String get knowledgeCaptureApplySuggestion => 'Apply suggestion';

  @override
  String get knowledgeCaptureApplyPolish => 'Apply polish';

  @override
  String get knowledgeCaptureApplying => 'Applying...';

  @override
  String get knowledgeCaptureKeepOriginal => 'Keep original';

  @override
  String knowledgeCaptureNotePolishOnly(Object reason) {
    return 'AI classified this as a note, so it will only polish the text. Reason: $reason';
  }

  @override
  String get knowledgeCapturePolishedVersionTitle => 'Review organized note';

  @override
  String get knowledgeCaptureTitleDiffLabel => 'Title';

  @override
  String get knowledgeCaptureBodyDiffLabel => 'Body';

  @override
  String get knowledgeCaptureEmptyValue => '(empty)';

  @override
  String knowledgeCaptureOriginalDiffValue(Object value) {
    return 'Original: $value';
  }

  @override
  String get knowledgeCaptureKindRoutineDescription =>
      'Looks like a recurring item';

  @override
  String get knowledgeCaptureKindDecisionDescription =>
      'Looks like it weighs options';

  @override
  String get knowledgeCaptureKindAssumptionDescription =>
      'Looks like it states a belief';

  @override
  String get knowledgeCaptureKindPrincipleDescription =>
      'Looks like it states a principle';

  @override
  String get knowledgeCaptureKindConceptDescription =>
      'Looks like it defines a concept';

  @override
  String get knowledgeCaptureKindExperimentDescription =>
      'Looks like it describes an experiment';

  @override
  String get knowledgeCaptureKindNoteDescription => 'Keep as Note';

  @override
  String knowledgeCaptureRoutineUpgradeDetail(
    Object intervalDays,
    Object statement,
  ) {
    return 'Will create a Routine: \"$statement\", every $intervalDays days';
  }

  @override
  String knowledgeCaptureRoutineScopeDetail(Object scope) {
    return 'Scope = $scope.';
  }

  @override
  String get knowledgeCaptureRoutineReminderDetail =>
      'AI will remind you 7 days before it is due.';

  @override
  String knowledgeCaptureSuggestionReasonConfidence(
    Object confidence,
    Object reason,
  ) {
    return 'Reason: $reason · confidence $confidence';
  }

  @override
  String knowledgeCaptureSaveFailed(Object error) {
    return 'Capture failed: $error';
  }

  @override
  String knowledgeCaptureApplyFailed(Object error) {
    return 'Could not apply suggestion: $error';
  }

  @override
  String get knowledgeAiPromptHint => 'Ask or search your knowledge...';

  @override
  String get knowledgeAiAskAction => 'Ask KnowledgeOS';

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
  String get knowledgeLibraryTitle => 'Library';

  @override
  String get knowledgeLibrarySelectItem =>
      'Select an item to keep browsing while you read';

  @override
  String get knowledgeLibraryEmptyAllTitle => 'No knowledge yet';

  @override
  String get knowledgeLibraryEmptyAllBody =>
      'Capture a quick note, or create a structured Decision or Assumption.';

  @override
  String get knowledgeLibraryEmptyDecisionsTitle => 'No Decisions yet';

  @override
  String get knowledgeLibraryEmptyDecisionsBody =>
      'Use the create action to record the first decision worth reviewing.';

  @override
  String get knowledgeLibraryEmptyPrinciplesTitle => 'No Principles yet';

  @override
  String get knowledgeLibraryEmptyPrinciplesBody =>
      'Use Principles for durable worldview rules that guide decisions.';

  @override
  String get knowledgeLibraryEmptyAssumptionsTitle => 'No Assumptions yet';

  @override
  String get knowledgeLibraryEmptyAssumptionsBody =>
      'Use Assumptions for falsifiable beliefs with confidence and review cadence.';

  @override
  String get knowledgeLibraryEmptyNotesTitle => 'No Notes in the library yet';

  @override
  String get knowledgeLibraryEmptyNotesBody =>
      'Capture a note, then let KnowledgeOS suggest tags, links, or an upgrade.';

  @override
  String get knowledgeLibraryEmptyConceptsTitle => 'No Concept nodes yet';

  @override
  String get knowledgeLibraryEmptyConceptsBody =>
      'Concepts power [[soft links]] and AI associations.';

  @override
  String get knowledgeLibraryEmptyExperimentsTitle => 'No active Experiments';

  @override
  String get knowledgeLibraryEmptyExperimentsBody =>
      'Experiments usually attach to an Assumption that needs validation.';

  @override
  String get knowledgeLibraryEmptyRoutinesTitle => 'No Routines yet';

  @override
  String get knowledgeLibraryEmptyRoutinesBody =>
      'Recurring reminders. After you create one, AI can surface it near the next due date.';

  @override
  String knowledgeRoutineOverdueDays(Object days) {
    return '$days days overdue';
  }

  @override
  String get knowledgeRoutineDueToday => 'Due today';

  @override
  String knowledgeRoutineDueInDays(Object days) {
    return 'Due in $days days';
  }

  @override
  String knowledgeRoutineLibraryMeta(
    Object dueLabel,
    Object intervalDays,
    Object scope,
  ) {
    return '$dueLabel · every $intervalDays days · $scope';
  }

  @override
  String get knowledgeLibrarySearchHint => 'Search this segment';

  @override
  String knowledgeLibrarySearchSegmentHint(Object segment) {
    return 'Search $segment';
  }

  @override
  String get knowledgeLibraryTypeTitle => 'Knowledge type';

  @override
  String get knowledgeLibraryTypePickerSubtitle =>
      'Choose what to browse in your library.';

  @override
  String knowledgeLibraryTypeScope(String type, int count) {
    return '$type · $count items';
  }

  @override
  String get knowledgeLibraryTypeGroupCore => 'Core';

  @override
  String get knowledgeLibraryTypeGroupSources => 'Sources';

  @override
  String get knowledgeLibraryTypeGroupThinking => 'Thinking';

  @override
  String get knowledgeLibraryTypeGroupAction => 'Action';

  @override
  String get knowledgeLibraryTypeAllDescription =>
      'Browse every knowledge object';

  @override
  String get knowledgeLibraryTypeDecisionsDescription =>
      'Record choices, rationale, and outcomes';

  @override
  String get knowledgeLibraryTypePrinciplesDescription =>
      'Durable rules that guide judgment';

  @override
  String get knowledgeLibraryTypeAssumptionsDescription =>
      'Beliefs that still need validation';

  @override
  String get knowledgeLibraryTypeNotesDescription =>
      'Keep raw observations and sources';

  @override
  String get knowledgeLibraryTypeConceptsDescription =>
      'Organize topics, aliases, and links';

  @override
  String get knowledgeLibraryTypeExperimentsDescription =>
      'Validate assumptions through action';

  @override
  String get knowledgeLibraryTypeRoutinesDescription =>
      'Repeat actions on a cadence';

  @override
  String get knowledgeLibraryFilterAll => 'All';

  @override
  String get knowledgeLibraryFilterTitle => 'Filters';

  @override
  String get knowledgeLibrarySearchClear => 'Clear search';

  @override
  String get knowledgeLibraryItemActions => 'Knowledge item actions';

  @override
  String get knowledgeItemOrganize => 'AI organize';

  @override
  String get knowledgeItemLink => 'Link';

  @override
  String get knowledgeRelationSheetTitle => 'Link related knowledge';

  @override
  String get knowledgeRelationSearchHint => 'Search knowledge';

  @override
  String get knowledgeRelationNoTargets =>
      'Everything available is already linked';

  @override
  String knowledgeRelationLinkedToast(Object title) {
    return 'Linked to $title';
  }

  @override
  String get knowledgeRelationLinkedTitle => 'Linked';

  @override
  String get knowledgeRelationAvailableTitle => 'Available knowledge';

  @override
  String knowledgeRelationRemoveLink(Object kind) {
    return '$kind · Remove link';
  }

  @override
  String knowledgeRelationUnlinkedToast(Object title) {
    return 'Removed link to $title';
  }

  @override
  String get knowledgeItemReview => 'Review';

  @override
  String get knowledgeItemPause => 'Pause';

  @override
  String get knowledgeItemResume => 'Resume';

  @override
  String get knowledgeItemCopySummary => 'Copy summary';

  @override
  String get knowledgeItemStartExperiment => 'Start';

  @override
  String get knowledgeItemRecordResult => 'Record result';

  @override
  String get knowledgeItemCopyResult => 'Copy result';

  @override
  String get knowledgeItemRestartExperiment => 'Restart';

  @override
  String get knowledgeItemUpdatedToast => 'Knowledge updated';

  @override
  String get knowledgeItemCopiedToast => 'Copied';

  @override
  String get knowledgeLibrarySearchRecent => 'Recent';

  @override
  String get knowledgeLibrarySearchSuggestions => 'Suggestions';

  @override
  String get knowledgeLibrarySearchEmptyTitle => 'No matching knowledge';

  @override
  String get knowledgeLibrarySearchEmptyBody =>
      'Try a different keyword or switch segments.';

  @override
  String knowledgeLibrarySearchEmptyScopedBody(String segment) {
    return 'No matches in $segment. Search all knowledge or try another keyword.';
  }

  @override
  String get knowledgeLibrarySearchAllAction => 'Search all knowledge';

  @override
  String knowledgeLibraryLoadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String knowledgeLibraryDeleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get knowledgeReviewTitle => 'Review · KnowledgeOS';

  @override
  String get knowledgeReviewOverviewTitle => 'Review status';

  @override
  String get knowledgeReviewAllClearBadge => 'All clear';

  @override
  String get knowledgeReviewAllClearBody =>
      'There are no due reviews or pending suggestions. Your deterministic review remains available even without AI.';

  @override
  String get knowledgeReviewBrowseLibrary => 'Browse library';

  @override
  String get knowledgeReviewReorder => 'Drag to reorder';

  @override
  String knowledgeReviewAttentionSummary(
    int routines,
    int decisions,
    int assumptions,
    int suggestions,
    int findings,
  ) {
    return '$routines routines · $decisions decisions · $assumptions assumptions · $suggestions AI suggestions · $findings conflicts';
  }

  @override
  String get knowledgeReviewAgentNotRun =>
      'The Knowledge Review agent has not run yet.';

  @override
  String knowledgeReviewLastRun(String date) {
    return 'Last agent review: $date';
  }

  @override
  String get knowledgeReviewAiUnavailable =>
      'AI suggestions are unavailable until an active device LLM profile is configured. Due reviews still work.';

  @override
  String get knowledgeReviewRunNow => 'Run Knowledge Review';

  @override
  String get knowledgeReviewRoutinesTitle => 'Routines due this week';

  @override
  String get knowledgeReviewRoutinesEmpty =>
      'No routines are due in the next 7 days.';

  @override
  String get knowledgeReviewDecisionsTitle => 'Decisions due for review';

  @override
  String get knowledgeReviewDecisionsEmpty =>
      'No decisions are due for review.';

  @override
  String knowledgeReviewDecisionOverdueDays(Object days) {
    return '$days days';
  }

  @override
  String get knowledgeReviewDecisionReviewed => 'Reviewed';

  @override
  String get knowledgeReviewMarkAllDecisionsReviewed => 'Mark all reviewed';

  @override
  String get knowledgeReviewMarkSelectedDecisionsReviewed =>
      'Mark selected reviewed';

  @override
  String get knowledgeReviewBatchActions => 'Batch actions';

  @override
  String knowledgeReviewTotalCount(Object count) {
    return '$count total';
  }

  @override
  String knowledgeReviewVisibleCount(Object total, Object visible) {
    return 'Showing first $visible of $total';
  }

  @override
  String knowledgeReviewDecisionNextReview(Object date) {
    return 'Next review $date';
  }

  @override
  String knowledgeReviewDecisionsBulkReviewed(int count) {
    return 'Rescheduled $count decisions for review';
  }

  @override
  String knowledgeReviewDecisionReviewFailed(Object error) {
    return 'Could not update review date: $error';
  }

  @override
  String get knowledgeReviewAssumptionsTitle => 'Stale assumptions';

  @override
  String knowledgeReviewAssumptionsEmpty(Object days) {
    return 'All active assumptions were verified within $days days.';
  }

  @override
  String knowledgeReviewRoutineMeta(Object dueLabel, Object intervalDays) {
    return '$dueLabel · every $intervalDays days';
  }

  @override
  String knowledgeReviewAssumptionStaleSummary(
    Object confidence,
    Object days,
    Object statement,
  ) {
    return '· $statement ($days days, conf $confidence)';
  }

  @override
  String knowledgeReviewLoadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String knowledgeReviewRoutineDone(Object date) {
    return 'Done. Next due $date';
  }

  @override
  String knowledgeReviewRoutineDoneFailed(Object error) {
    return 'Could not mark routine done: $error';
  }

  @override
  String get knowledgeReviewMarkDone => 'Done';

  @override
  String get knowledgeReviewMarkAllDone => 'Mark all done';

  @override
  String get knowledgeReviewMarkSelectedDone => 'Mark selected done';

  @override
  String knowledgeReviewRoutinesBulkDone(int count) {
    return 'Marked $count routines done';
  }

  @override
  String get knowledgeReviewVerifyAssumption => 'Verify';

  @override
  String get knowledgeReviewVerifyAllAssumptions => 'Verify all';

  @override
  String get knowledgeReviewVerifySelectedAssumptions => 'Verify selected';

  @override
  String knowledgeReviewAssumptionsBulkVerified(int count) {
    return 'Verified $count assumptions';
  }

  @override
  String get knowledgeReviewAssumptionVerified => 'Assumption verified.';

  @override
  String get knowledgeReviewAssumptionConfirmTitle => 'Confirm this assumption';

  @override
  String knowledgeReviewAssumptionConfirmBody(String statement) {
    return 'Only verify this if it is still supported by current evidence: “$statement”';
  }

  @override
  String get knowledgeReviewAssumptionStillValid => 'Still valid';

  @override
  String knowledgeReviewAssumptionVerifyFailed(Object error) {
    return 'Could not verify assumption: $error';
  }

  @override
  String get knowledgeReviewSelectAll => 'Select all';

  @override
  String get knowledgeReviewClearSelection => 'Clear';

  @override
  String knowledgeReviewSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get knowledgeSegmentAll => 'All';

  @override
  String get knowledgeSegmentDecisions => 'Decisions';

  @override
  String get knowledgeSegmentPrinciples => 'Principles';

  @override
  String get knowledgeSegmentAssumptions => 'Assumptions';

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
  String get knowledgeNewPrinciple => 'New Principle';

  @override
  String get knowledgeNewAssumption => 'New Assumption';

  @override
  String get knowledgeNewNote => 'New Note';

  @override
  String get knowledgeNewConcept => 'New Concept';

  @override
  String get knowledgeNewExperiment => 'New Experiment';

  @override
  String get knowledgeNewRoutine => 'New Routine';

  @override
  String get knowledgeNewMoreTypes => 'More types';

  @override
  String get knowledgeNewChooserTitle => 'New...';

  @override
  String get knowledgeNewChooserSubtitle =>
      'Choose a structured knowledge object. Quick Notes are captured from Inbox.';

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
  String get knowledgeDecisionWriterTitle => 'New Decision';

  @override
  String get knowledgeDecisionWriterSubtitle =>
      'Decision as memory: question, options, rationale, review';

  @override
  String get knowledgeDecisionEditTitle => 'Edit Decision';

  @override
  String get knowledgeDecisionEditSubtitle =>
      'Update options, rationale, expected outcome, and review plan';

  @override
  String get knowledgeDecisionAddOption => 'Add option';

  @override
  String get knowledgeDecisionClear => 'Clear';

  @override
  String get knowledgeDecisionExpectedOutcomeLabel =>
      'Expected outcome (optional)';

  @override
  String get knowledgeDecisionRevisitConditionsLabel =>
      'Review when (optional)';

  @override
  String get knowledgeDecisionRevisitConditionsHint =>
      'One condition per line, for example: cash runway falls below 12 months';

  @override
  String get knowledgeDecisionRevisitConditionsTitle => 'Review conditions';

  @override
  String get knowledgeAssumptionWriterSubtitle2 =>
      'Falsifiable belief with confidence for future review';

  @override
  String get knowledgeConceptWriterSubtitle2 =>
      'Anchor for soft links and AI cross references';

  @override
  String get knowledgeExperimentWriterSubtitle2 =>
      'Validate an assumption with an explicit method';

  @override
  String get knowledgeWriterAliasLabel => 'Aliases';

  @override
  String get knowledgeRoutineMonthly => 'Monthly';

  @override
  String get knowledgeRoutineQuarterly => 'Quarterly';

  @override
  String get knowledgeRoutineSemiannual => 'Every 6 months';

  @override
  String get knowledgeRoutineYearly => 'Yearly';

  @override
  String get knowledgeDecisionQuestionLabel => 'Question';

  @override
  String get knowledgeDecisionQuestionHint =>
      '\"Upgrade to QQQ + BOXX dynamic hedging?\"';

  @override
  String get knowledgeDecisionOptionsLabel => 'Options';

  @override
  String get knowledgeDecisionOptionsRequirement =>
      'Enter at least two different options.';

  @override
  String get knowledgeDecisionSelectionRequirement =>
      'Choose the option you decided to take.';

  @override
  String knowledgeDecisionOptionLabelHint(Object index) {
    return 'Option $index';
  }

  @override
  String get knowledgeDecisionOptionRationaleHint =>
      'Why choose this option (optional)';

  @override
  String get knowledgeDecisionNoReferenceCandidates =>
      'No Principle or Assumption has been declared yet. You can save the Decision now and attach references later.';

  @override
  String get knowledgeDecisionRationaleLabel => 'Rationale (Markdown)';

  @override
  String get knowledgeDecisionRationaleHint =>
      'Why this option: constraints and the judgment at the time';

  @override
  String get knowledgeDecisionExpectedOutcomeHint =>
      'How success will be judged: metrics or signals';

  @override
  String get knowledgeDecisionReviewDateTitle => 'Review date';

  @override
  String get knowledgeDecisionReviewDateOptional => 'Review date (optional)';

  @override
  String knowledgeDecisionReviewDateScheduled(Object date) {
    return 'Review on $date';
  }

  @override
  String get knowledgeDecisionReviewDateChoose => 'Choose';

  @override
  String get knowledgeDecisionReviewDateChange => 'Change';

  @override
  String knowledgeDecisionReviewDateInDays(Object days) {
    return '+$days days';
  }

  @override
  String get knowledgeDecisionReviewDateInOneYear => '+1 year';

  @override
  String get knowledgeDecisionReviewDateCustomLabel => 'Custom date';

  @override
  String get knowledgeDecisionReviewDateCustomHint => 'YYYY-MM-DD';

  @override
  String get knowledgeDecisionReviewDateCustomApply => 'Use date';

  @override
  String get knowledgeDecisionReviewDateInvalid =>
      'Enter a valid date as YYYY-MM-DD.';

  @override
  String get knowledgeDecisionReviewDatePast =>
      'Choose today or a future date.';

  @override
  String get knowledgeDecisionLifecycleTitle => 'Update Decision';

  @override
  String get knowledgeDecisionLifecycleSubtitle =>
      'Status, actual outcome, and cognitive trail';

  @override
  String get knowledgeDecisionActualOutcomeLabel =>
      'Actual outcome (Markdown, optional)';

  @override
  String get knowledgeDecisionStatusLabel => 'Status';

  @override
  String get knowledgeDecisionStatusDraft => 'Draft';

  @override
  String get knowledgeDecisionStatusActive => 'Active';

  @override
  String get knowledgeDecisionStatusPaused => 'Paused';

  @override
  String get knowledgeDecisionStatusExpired => 'Expired';

  @override
  String get knowledgeDecisionStatusVerified => 'Verified';

  @override
  String get knowledgeDecisionStatusFalsified => 'Falsified';

  @override
  String get knowledgeDecisionStatusSuperseded => 'Superseded';

  @override
  String get knowledgeDecisionActualOutcomeHint =>
      'For review: what actually happened and how it differed from expectations';

  @override
  String get knowledgeDecisionSupersededByLabel => 'Superseded by Decision';

  @override
  String get knowledgeDecisionSupersededByEmpty =>
      'No other Decision is available yet. Record the new decision first, then come back to mark the relationship.';

  @override
  String get knowledgePrincipleWriterTitle => 'New Principle';

  @override
  String get knowledgePrincipleWriterSubtitle =>
      'Long-lived worldview primitive, not falsifiable';

  @override
  String get knowledgePrincipleStatementHint =>
      '\"Default edge-first\" / \"Avoid high-maintenance systems\"';

  @override
  String get knowledgePrincipleRationaleHint =>
      'Why this worldview should become a Principle';

  @override
  String get knowledgeAssumptionWriterTitle => 'New Assumption';

  @override
  String get knowledgeAssumptionEditTitle => 'Edit Assumption';

  @override
  String get knowledgeAssumptionEditSubtitle =>
      'Update the statement, confidence, and scope';

  @override
  String get knowledgeAssumptionWriterSubtitle =>
      'Falsifiable belief with confidence';

  @override
  String get knowledgeAssumptionStatementHint =>
      '\"Long-term index growth beats inflation\"';

  @override
  String get knowledgeConceptWriterTitle => 'New Concept';

  @override
  String get knowledgeConceptWriterSubtitle =>
      'Named node for search and soft links';

  @override
  String get knowledgeConceptNameHint =>
      'Concept name, for example \"edge-first\"';

  @override
  String get knowledgeConceptAliasesHint => 'Comma-separated aliases';

  @override
  String get knowledgeConceptSummaryHint =>
      '1-2 sentence definition for [[soft link]] tooltips';

  @override
  String get knowledgeExperimentWriterTitle => 'New Experiment';

  @override
  String get knowledgeExperimentWriterSubtitle =>
      'Test an assumption with method and metrics';

  @override
  String get knowledgeExperimentHypothesisHint =>
      '\"Covered call 60 DTE on QQQ outperforms 30 DTE\"';

  @override
  String get knowledgeExperimentMethodHint =>
      'How to run it, for how long, and with what data';

  @override
  String get knowledgeExperimentMetricsHint =>
      'Comma-separated, for example \"yield, drawdown, sharpe\"';

  @override
  String get knowledgeExperimentNoActiveAssumptions =>
      'No active Assumptions are available. You can leave this empty.';

  @override
  String get knowledgeExperimentTargetAssumptionLabel =>
      'Target Assumption (optional)';

  @override
  String get knowledgeRoutineWriterTitle => 'New Routine';

  @override
  String get knowledgeRoutineWriterSubtitle =>
      'Recurring reminder. AI can surface it near next due date.';

  @override
  String get knowledgeRoutineStatementHint =>
      '\"Activate bank card\" / \"Monthly reconciliation\"';

  @override
  String get knowledgeWriterStatementLabel => 'Statement';

  @override
  String get knowledgeWriterRationaleMarkdownLabel => 'Rationale (Markdown)';

  @override
  String get knowledgeWriterScopeLabel => 'Scope';

  @override
  String get knowledgeWriterScopeOptionalLabel => 'Scope tag (optional)';

  @override
  String get knowledgeWriterEvidenceLabel => 'Evidence IDs';

  @override
  String get knowledgeWriterConfidenceLabel => 'Confidence';

  @override
  String get knowledgeConfidenceLow => 'Low';

  @override
  String get knowledgeConfidenceMedium => 'Medium';

  @override
  String get knowledgeConfidenceHigh => 'High';

  @override
  String get knowledgeWriterScopeHint =>
      'Optional, such as investing, health, or work';

  @override
  String get knowledgeWriterStatusLabel => 'Status';

  @override
  String get knowledgeWriterNameLabel => 'Name';

  @override
  String get knowledgeWriterAliasesLabel => 'Aliases';

  @override
  String get knowledgeWriterSummaryMarkdownLabel => 'Summary (Markdown)';

  @override
  String get knowledgeWriterHypothesisLabel => 'Hypothesis';

  @override
  String get knowledgeWriterMethodMarkdownLabel => 'Method (Markdown)';

  @override
  String get knowledgeWriterMetricsLabel => 'Metrics';

  @override
  String get knowledgeWriterResultMarkdownLabel =>
      'Result (Markdown, optional)';

  @override
  String get knowledgeWriterConclusionMarkdownLabel =>
      'Conclusion (Markdown, optional)';

  @override
  String get knowledgeWriterCoreSectionTitle => 'Core';

  @override
  String get knowledgeWriterEvidenceSectionTitle => 'Evidence and rationale';

  @override
  String get knowledgeWriterContextSectionTitle => 'Additional context';

  @override
  String get knowledgeWriterReferencesSectionTitle => 'References';

  @override
  String get knowledgeWriterPlanningSectionTitle => 'Planning';

  @override
  String get knowledgeWriterCadenceSectionTitle => 'Cadence';

  @override
  String get knowledgeRoutineStatementLabel => 'What to do';

  @override
  String get knowledgeRoutineFrequencyLabel => 'Frequency';

  @override
  String get knowledgeNotesHintTitle => 'Notes are captured in Inbox';

  @override
  String get knowledgeNotesHintBody =>
      'The Notes segment is for browsing. Close this panel, switch to Inbox, and use the create action there.';

  @override
  String get knowledgeNoteTagsLabel => 'Tags (comma separated)';

  @override
  String get amountHidden => 'Amount hidden';

  @override
  String get tradeVerbBuy => 'Buy';

  @override
  String get tradeVerbSell => 'Sell';

  @override
  String get healthNotEnabled => 'HealthOS not enabled';

  @override
  String healthPlanLoadFailed(String message) {
    return 'Plan load failed: $message';
  }

  @override
  String get healthGarminTitle => 'Garmin Connect';

  @override
  String get healthGarminDisconnected => 'Disconnected';

  @override
  String get healthGarminConnected => 'Connected';

  @override
  String get healthGarminSyncingBadge => 'Syncing';

  @override
  String get healthGarminErrorBadge => 'Error';

  @override
  String get healthGarminRestoringBadge => 'Restoring';

  @override
  String get healthGarminVerifyBadge => 'Verify';

  @override
  String get healthGarminMfaRequired => 'MFA Required';

  @override
  String get healthGarminConnectSheetTitle => 'Connect Garmin';

  @override
  String get healthGarminMfaCodeLabel => 'MFA code';

  @override
  String get healthGarminEmailLabel => 'Email';

  @override
  String get healthGarminEmailHint => 'you@example.com';

  @override
  String get healthGarminPasswordLabel => 'Password';

  @override
  String get healthGarminRememberPassword => 'Securely save password';

  @override
  String get healthGarminRememberPasswordHint =>
      'Encrypted in this device’s Keychain or Keystore. Never synced.';

  @override
  String get healthGarminAutoRenewEnabled => 'Session auto-renewal is on';

  @override
  String get healthGarminRegionLabel => 'Region';

  @override
  String get healthGarminRegionChina => 'China';

  @override
  String get healthGarminRegionGlobal => 'Global';

  @override
  String get healthGarminConnect => 'Connect';

  @override
  String get healthGarminDisconnect => 'Disconnect';

  @override
  String get healthGarminSync => 'Sync';

  @override
  String get healthGarminRetry => 'Retry';

  @override
  String get healthGarminEnterCode => 'Enter Code';

  @override
  String get healthGarminRestoringSession => 'Restoring session…';

  @override
  String get healthGarminSyncingData => 'Syncing data…';

  @override
  String get healthGarminSyncError => 'Sync Error';

  @override
  String get healthGarminDisconnectTitle => 'Disconnect Garmin?';

  @override
  String get healthGarminDisconnectBody =>
      'Synced data will remain in the app.';

  @override
  String get healthGarminCancel => 'Cancel';

  @override
  String healthGarminLastSync(String time, String count) {
    return 'Last sync $time · $count metrics';
  }

  @override
  String healthGarminSyncProgress(String current, String total, String count) {
    return 'Day $current/$total · $count metrics';
  }

  @override
  String get healthGarminCancelSync => 'Cancel Sync';

  @override
  String get healthGarminErrorAuthExpired =>
      'Garmin session expired. Please reconnect your account.';

  @override
  String get healthGarminErrorCredentialsInvalid =>
      'Your saved Garmin password no longer works. Enter it again to reconnect.';

  @override
  String get healthGarminErrorRateLimited =>
      'Garmin is limiting requests temporarily. Try again later.';

  @override
  String get healthGarminErrorEndpointUnavailable =>
      'Some Garmin data endpoints are unavailable for this account or region.';

  @override
  String get healthGarminErrorPersistFailed =>
      'Garmin data was fetched but could not be saved locally. Try syncing again.';

  @override
  String get healthGarminErrorUnsupportedSnapshot =>
      'Garmin returned data in a shape HealthOS does not support yet.';

  @override
  String get healthGarminErrorGeneric => 'Garmin sync failed. Try again.';

  @override
  String get settingsDomainsExecutionEnabledSubtitle =>
      'Today, commitments, progress, and personal todos.';

  @override
  String get settingsDomainsExecutionDisabledSubtitle =>
      'Turn decisions and plans into trackable actions.';

  @override
  String get settingsDomainsExecutionTodaySubtitle =>
      'Review today\'s actions, blockers, and progress.';

  @override
  String get executionTabToday => 'Today';

  @override
  String get executionTabCommitments => 'Plans';

  @override
  String get executionTabReview => 'Review';

  @override
  String get executionCommandToday => 'ExecutionOS Today';

  @override
  String get executionCommandCommitments => 'ExecutionOS Plans';

  @override
  String get executionCommandReview => 'ExecutionOS Review';

  @override
  String get executionTodayTitle => 'Today';

  @override
  String get executionTodayBriefSubtitle => 'Today\'s execution overview';

  @override
  String get executionCommitmentsTitle => 'Plans';

  @override
  String get executionPlansSelectItem => 'Select a plan to review it here';

  @override
  String get executionReviewTitle => 'Review';

  @override
  String get executionReviewNeedsAttentionTitle => 'Needs attention';

  @override
  String get executionReviewWeekResultsTitle => 'This week';

  @override
  String executionReviewRecentActivity(int count) {
    return 'Recent activity · $count';
  }

  @override
  String get executionReviewDetailsTitle => 'Review details';

  @override
  String get executionReviewDetailsSubtitle =>
      'Data freshness and technical run details';

  @override
  String get executionCreateActionTitle => 'New Action';

  @override
  String get executionCreatePlanTitle => 'Add';

  @override
  String get executionCreateProjectTitle => 'New Plan';

  @override
  String get executionCreateCommitmentTitle => 'New Commitment';

  @override
  String get executionCreateProgressTitle => 'New Progress';

  @override
  String get executionEditProgressTitle => 'Edit Progress';

  @override
  String get executionEditActionTitle => 'Edit Action';

  @override
  String get executionEditProjectTitle => 'Edit Plan';

  @override
  String get executionEditCommitmentTitle => 'Edit Commitment';

  @override
  String get executionActionField => 'Action';

  @override
  String get executionProjectField => 'Plan';

  @override
  String get executionCommitmentField => 'Commitment';

  @override
  String get executionRelationField => 'Belongs to';

  @override
  String get executionNoRelation => 'Inbox · no plan';

  @override
  String get executionStatusField => 'Status';

  @override
  String get executionPriorityField => 'Priority';

  @override
  String get executionHorizonField => 'Horizon';

  @override
  String get executionTargetDateField => 'Target date';

  @override
  String get executionScheduledForField => 'Scheduled';

  @override
  String get executionDueAtField => 'Due';

  @override
  String get executionDescriptionField => 'Description';

  @override
  String get executionTitleRequired => 'Add a title';

  @override
  String get executionActionTitleHint => 'What is the next concrete action?';

  @override
  String get executionActionNoteHint => 'Optional note';

  @override
  String get executionProjectTitleHint => 'What outcome needs multiple steps?';

  @override
  String get executionProjectDescriptionHint =>
      'Optional outcome, scope, or finish line';

  @override
  String get executionCommitmentTitleHint => 'What are you committing to?';

  @override
  String get executionCommitmentDescriptionHint =>
      'Optional scope, why it matters, or target outcome';

  @override
  String get executionOverviewFocus => 'Today';

  @override
  String get executionOverviewBlocked => 'Blocked';

  @override
  String get executionOverviewHigh => 'High';

  @override
  String get executionOverviewDue => 'Due';

  @override
  String get executionOverviewProjects => 'Plans';

  @override
  String get executionOverviewCommitments => 'Commitments';

  @override
  String get executionOverviewProgress7d => '7d progress';

  @override
  String get executionTodayEmptyTitle => 'No actions for today';

  @override
  String get executionTodayEmptyBody =>
      'Capture the next concrete step when something needs follow-through.';

  @override
  String get executionTodayFilteredEmptyTitle => 'No matching actions';

  @override
  String get executionTodayFilteredEmptyBody =>
      'Switch filters or capture a new action when something needs follow-through.';

  @override
  String executionDeleteConfirmTitle(Object item) {
    return 'Delete $item?';
  }

  @override
  String get executionDeleteConfirmBody =>
      'This removes it from ExecutionOS and syncs the deletion.';

  @override
  String get executionCommitmentsEmptyTitle => 'No active work';

  @override
  String get executionCommitmentsEmptyBody =>
      'Capture one next action, or group multi-step work into a plan.';

  @override
  String get executionCommitmentsClosedEmptyTitle => 'No closed items';

  @override
  String get executionCommitmentsClosedEmptyBody =>
      'Completed and archived plans will appear here.';

  @override
  String get executionReviewEmptyTitle => 'No progress yet';

  @override
  String get executionReviewEmptyBody =>
      'Completion and blocker notes will appear here for review.';

  @override
  String get executionClosedActionsSection => 'Recent closed actions';

  @override
  String get executionProjectsSection => 'Plans';

  @override
  String get executionCommitmentsSection => 'Ongoing';

  @override
  String get executionInboxSection => 'Inbox';

  @override
  String get executionActionsSection => 'Actions';

  @override
  String get executionRelatedActionsSection => 'Related actions';

  @override
  String get executionTimelineSection => 'Timeline';

  @override
  String get executionDetailMissingTitle => 'Item not found';

  @override
  String get executionDetailMissingBody =>
      'It may have been deleted or is no longer available on this device.';

  @override
  String get executionProjectStatusActive => 'Active';

  @override
  String get executionProjectStatusPaused => 'Paused';

  @override
  String get executionProjectStatusCompleted => 'Completed';

  @override
  String get executionProjectStatusArchived => 'Archived';

  @override
  String get executionStatusTodo => 'Todo';

  @override
  String get executionStatusDoing => 'Doing';

  @override
  String get executionStatusBlocked => 'Blocked';

  @override
  String get executionStatusDone => 'Done';

  @override
  String get executionStatusDropped => 'Dropped';

  @override
  String get executionPriorityLow => 'Low';

  @override
  String get executionPriorityNormal => 'Normal';

  @override
  String get executionPriorityHigh => 'High';

  @override
  String executionDueBadge(String date) {
    return 'Due $date';
  }

  @override
  String executionScheduledBadge(String date) {
    return 'Scheduled $date';
  }

  @override
  String executionOverdueBadge(String date) {
    return 'Overdue $date';
  }

  @override
  String executionTargetBadge(String date) {
    return 'Target $date';
  }

  @override
  String get executionNoAction => 'No action';

  @override
  String get executionUnknownAction => 'Unknown action';

  @override
  String get executionNoActionsAvailable => 'No open actions available';

  @override
  String get executionNoProject => 'No project';

  @override
  String get executionUnknownProject => 'Unknown project';

  @override
  String get executionNoProjectsAvailable => 'No active projects available';

  @override
  String get executionNoCommitment => 'No commitment';

  @override
  String get executionUnknownCommitment => 'Unknown commitment';

  @override
  String get executionNoCommitmentsAvailable =>
      'No active commitments available';

  @override
  String get executionPickerSearchHint => 'Search by title or note';

  @override
  String get executionPickerSearchEmpty => 'No matching items';

  @override
  String get executionActionStart => 'Start';

  @override
  String get executionActionBlock => 'Block';

  @override
  String get executionActionResume => 'Resume';

  @override
  String get executionActionDone => 'Done';

  @override
  String get executionActionDrop => 'Drop';

  @override
  String get executionActionStatusUpdateFailed =>
      'Couldn\'t update action status.';

  @override
  String get executionLifecyclePause => 'Pause';

  @override
  String get executionLifecycleResume => 'Resume';

  @override
  String get executionLifecycleComplete => 'Complete';

  @override
  String get executionLifecycleArchive => 'Archive';

  @override
  String get executionLifecycleActiveView => 'Active';

  @override
  String get executionLifecycleClosedView => 'Closed';

  @override
  String get executionClosedWorkEntry => 'Closed work';

  @override
  String get executionActiveWorkEntry => 'Back to active work';

  @override
  String get executionProjectStatusUpdateFailed =>
      'Couldn\'t update project status.';

  @override
  String get executionCommitmentStatusUpdateFailed =>
      'Couldn\'t update commitment status.';

  @override
  String get executionProgressDoneDefault => 'Marked done.';

  @override
  String get executionProgressDroppedDefault => 'Marked dropped.';

  @override
  String get executionProgressStartedDefault => 'Started work.';

  @override
  String get executionProgressResumedDefault => 'Resumed work.';

  @override
  String get executionProjectPausedDefault => 'Project paused.';

  @override
  String get executionProjectResumedDefault => 'Project resumed.';

  @override
  String get executionProjectCompletedDefault => 'Project completed.';

  @override
  String get executionProjectArchivedDefault => 'Project archived.';

  @override
  String get executionCommitmentPausedDefault => 'Commitment paused.';

  @override
  String get executionCommitmentResumedDefault => 'Commitment resumed.';

  @override
  String get executionCommitmentCompletedDefault => 'Commitment completed.';

  @override
  String get executionCommitmentArchivedDefault => 'Commitment archived.';

  @override
  String get executionLifecycleCompleteConfirmTitle =>
      'Complete with open actions?';

  @override
  String executionLifecycleCompleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open actions will remain active and move to Inbox.',
      one: '1 open action will remain active and move to Inbox.',
    );
    return '$_temp0';
  }

  @override
  String get executionLifecycleArchiveConfirmTitle =>
      'Archive with open actions?';

  @override
  String executionLifecycleArchiveConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open actions will remain active and move to Inbox.',
      one: '1 open action will remain active and move to Inbox.',
    );
    return '$_temp0';
  }

  @override
  String executionLifecycleStatusUpdated(Object status) {
    return 'Status updated to $status';
  }

  @override
  String executionDeleteWithOpenActionsBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open actions will move to Inbox.',
      one: '1 open action will move to Inbox.',
    );
    return 'This deletes the item. $_temp0';
  }

  @override
  String get executionProgressKindField => 'Progress type';

  @override
  String get executionProgressNoteField => 'Progress note';

  @override
  String get executionProgressNoteHint =>
      'Record a change or note. Use the action controls to change status.';

  @override
  String get executionProgressNoteRequired => 'Add a progress note';

  @override
  String get executionProgressKindBlocker => 'Blocker';

  @override
  String get executionProgressKindCompletion => 'Completion';

  @override
  String get executionProgressKindDropped => 'Dropped';

  @override
  String get executionProgressKindScope => 'Scope Change';

  @override
  String get executionProgressKindCheckin => 'Check-in';

  @override
  String get executionOpenActionsSection => 'Open actions';

  @override
  String get executionStandaloneActionsSection => 'Standalone actions';

  @override
  String get executionUnplacedActionsSection => 'Open actions to place';

  @override
  String get executionProjectCommitmentsSection => 'Project commitments';

  @override
  String get executionReviewWindow7d => '7 days';

  @override
  String get executionReviewWindow30d => '30 days';

  @override
  String get executionReviewWindowAll => 'All';

  @override
  String get executionReviewCompletedMetric => 'Completed';

  @override
  String get executionReviewBlockedMetric => 'Blockers';

  @override
  String get executionReviewProgressMetric => 'Progress';

  @override
  String get executionReviewGenerateTitle => 'Execution review';

  @override
  String get executionReviewGenerateBody =>
      'Generate a local review of focus, blockers, due work, and recent progress.';

  @override
  String get executionReviewGenerateAction => 'Generate review';

  @override
  String get executionProposalActionLabel => 'Action';

  @override
  String get executionProposalActionStatusLabel => 'Action Status';

  @override
  String get executionProposalProjectLabel => 'Project';

  @override
  String get executionProposalCommitmentLabel => 'Commitment';

  @override
  String get executionProposalProgressLabel => 'Progress';

  @override
  String get executionProposalRowAction => 'Action';

  @override
  String get executionProposalRowPriority => 'Priority';

  @override
  String get executionProposalRowProject => 'Project';

  @override
  String get executionProposalRowCommitment => 'Commitment';

  @override
  String get executionProposalRowProgress => 'Progress';

  @override
  String get executionProposalRowDue => 'Due';

  @override
  String get executionProposalRowSource => 'Source';

  @override
  String get agentOutputLanguageEnglish => 'English';

  @override
  String get agentOutputLanguageChinese => 'Chinese';

  @override
  String get financeAgentWeeklyWealthSkipNoSnapshot =>
      'no finance snapshot to review';

  @override
  String get financeAgentWeeklyWealthTitle => 'Weekly Wealth Review';

  @override
  String financeAgentWeeklyWealthSummary(Object details) {
    return 'Weekly wealth review: $details.';
  }

  @override
  String financeAgentWeeklyWealthPartNetWorth(Object value) {
    return 'Net worth $value';
  }

  @override
  String financeAgentWeeklyWealthPartAssets(Object value) {
    return 'assets $value';
  }

  @override
  String financeAgentWeeklyWealthPartLiabilities(Object value) {
    return 'liabilities $value';
  }

  @override
  String financeAgentWeeklyWealthPartLargestAllocation(
    Object amount,
    Object category,
    Object ratio,
  ) {
    return 'largest allocation $category $amount ($ratio)';
  }

  @override
  String financeAgentWeeklyWealthPartStalePrices(Object count) {
    return '$count stale prices';
  }

  @override
  String financeAgentWeeklyWealthPartFxGaps(Object count) {
    return '$count FX gaps';
  }

  @override
  String get financeAgentAssetCategoryStock => 'stocks';

  @override
  String get financeAgentAssetCategoryEtf => 'ETFs';

  @override
  String get financeAgentAssetCategoryBondsAndFunds => 'bonds and funds';

  @override
  String get financeAgentAssetCategoryCash => 'cash';

  @override
  String get financeAgentAssetCategoryCrypto => 'crypto';

  @override
  String get financeAgentAssetCategoryRealEstate => 'real estate';

  @override
  String get financeAgentAssetCategoryVehicle => 'vehicles';

  @override
  String get financeAgentAssetCategoryLiability => 'liabilities';

  @override
  String get financeAgentWeeklyWealthInsightNetWorthTitle => 'Net worth';

  @override
  String financeAgentWeeklyWealthInsightNetWorthBody(
    Object assets,
    Object liabilities,
    Object netWorth,
  ) {
    return '$netWorth net worth from $assets assets and $liabilities liabilities.';
  }

  @override
  String get financeAgentWeeklyWealthInsightLargestAllocationTitle =>
      'Largest allocation';

  @override
  String financeAgentWeeklyWealthInsightLargestAllocationBody(
    Object amount,
    Object category,
    Object ratio,
  ) {
    return '$category is $amount, about $ratio of assets.';
  }

  @override
  String get financeAgentWeeklyWealthInsightPriceFreshnessTitle =>
      'Price freshness';

  @override
  String financeAgentWeeklyWealthInsightPriceFreshnessBody(Object count) {
    return '$count holdings have stale prices.';
  }

  @override
  String get financeAgentWeeklyWealthInsightFxCoverageTitle => 'FX coverage';

  @override
  String financeAgentWeeklyWealthInsightFxCoverageBody(Object count) {
    return '$count holdings were excluded because FX conversion is missing.';
  }

  @override
  String get financeAgentWeeklyWealthAction => 'Review wealth';

  @override
  String get financeAgentCashflowSkipNoAnomaly =>
      'no cashflow anomaly detected';

  @override
  String get financeAgentCashflowTitle => 'Cashflow Anomaly Review';

  @override
  String get financeAgentCashflowDirectionHigher => 'higher';

  @override
  String get financeAgentCashflowDirectionLower => 'lower';

  @override
  String financeAgentCashflowSummary(Object delta) {
    return 'Cashflow anomaly review: projected monthly spending is $delta vs. the previous 3-month average.';
  }

  @override
  String get financeAgentCashflowInsightProjectionTitle =>
      'Monthly spending projection';

  @override
  String financeAgentCashflowInsightProjectionBody(
    Object delta,
    Object direction,
  ) {
    return 'Current-month spending is projected $direction than the previous 3-month average by $delta.';
  }

  @override
  String get financeAgentCashflowInsightDetectorTitle => 'Detector source';

  @override
  String get financeAgentCashflowInsightDetectorBody =>
      'This result comes from the on-device anomaly detector used by get_anomaly_flags.';

  @override
  String get financeAgentCashflowEvidenceLabel => 'Monthly expense anomaly';

  @override
  String get financeAgentCashflowAction => 'Review anomaly';

  @override
  String get financeAgentFireSkipNoPlan => 'no FIRE plan configured';

  @override
  String get financeAgentFireSkipNoDrift => 'no FIRE plan drift detected';

  @override
  String get financeAgentFireTitle => 'FIRE Plan Drift Monitor';

  @override
  String get financeAgentFireInsightPlanSnapshotTitle => 'Plan snapshot';

  @override
  String financeAgentFireInsightPlanSnapshotBody(
    Object cashBucketMonths,
    Object safeRate,
    Object targetCashBucketMonths,
    Object withdrawalRate,
  ) {
    return 'Withdrawal rate $withdrawalRate vs. safe rate $safeRate, cash bucket $cashBucketMonths / $targetCashBucketMonths months.';
  }

  @override
  String financeAgentFireEvidenceReviewLabel(Object periodKey) {
    return 'FIRE review $periodKey';
  }

  @override
  String get financeAgentFireEvidenceReviewBody =>
      'A deterministic snapshot of current plan metrics, assets, and risk thresholds.';

  @override
  String get financeAgentFireAction => 'Review FIRE plan';

  @override
  String get financeAgentFireActionBody =>
      'Open FIRE to review and adjust plan assumptions.';

  @override
  String financeAgentFireSummaryWithdrawal(
    Object safeRate,
    Object withdrawalRate,
  ) {
    return 'Current withdrawal rate is $withdrawalRate; the safe rate is $safeRate';
  }

  @override
  String financeAgentFireSummaryStress(int failedCount) {
    return '$failedCount stress scenarios did not pass';
  }

  @override
  String get financeAgentFireSummarySeparator => '. ';

  @override
  String get financeAgentFireMetricWithdrawalRate => 'Withdrawal rate';

  @override
  String get financeAgentFireMetricSafeRate => 'Safe rate';

  @override
  String get financeAgentFireMetricCashBucket => 'Cash runway';

  @override
  String get financeAgentFireMetricTarget => 'Plan target';

  @override
  String financeAgentFireMetricTargetMonths(int months) {
    return 'Target $months months';
  }

  @override
  String get financeAgentFireMetricExcess => 'Above safe rate';

  @override
  String get financeAgentFireMetricAffectedItems => 'Affected items';

  @override
  String get financeAgentFireMetricNetWorthAfter => 'Net worth after test';

  @override
  String get financeAgentFireMetricWithdrawalAfter =>
      'Withdrawal rate after test';

  @override
  String get financeAgentFireMetricCashAfter => 'Cash runway after test';

  @override
  String financeAgentFireMonthsValue(Object value) {
    return '$value months';
  }

  @override
  String financeAgentFirePercentagePoints(Object value) {
    return '$value pp';
  }

  @override
  String financeAgentFireStressGroupTitle(int count) {
    return '$count stress scenarios did not pass';
  }

  @override
  String financeAgentFireStressGroupBody(Object scenarios) {
    return 'Risk is concentrated in: $scenarios.';
  }

  @override
  String get financeAgentFireScenarioSeparator => ', ';

  @override
  String get financeAgentFireScenarioMarketDrawdown => 'Market drawdown';

  @override
  String get financeAgentFireScenarioExpenseSurge => 'Higher living costs';

  @override
  String get financeAgentFireScenarioOneOffShock => 'One-off expense';

  @override
  String get financeAgentFireScenarioFxShock => 'FX shock';

  @override
  String get financeAgentFireScenarioCashDepletion => 'Cash depletion';

  @override
  String get financeAgentFireScenarioUnknown => 'Other stress scenario';

  @override
  String get financeAgentFireStressVerdictSafe => 'Passed';

  @override
  String get financeAgentFireStressVerdictCautious => 'Attention';

  @override
  String get financeAgentFireStressVerdictDanger => 'Danger';

  @override
  String financeAgentFireStressResultContext(
    Object cashBucketMonths,
    Object withdrawalRate,
  ) {
    return 'Withdrawal rate $withdrawalRate · cash runway $cashBucketMonths months';
  }

  @override
  String get financeAgentFireTrendTitle => 'Since last review';

  @override
  String financeAgentFireTrendBody(Object changes) {
    return '$changes.';
  }

  @override
  String get financeAgentFireTrendWithdrawal => 'Withdrawal rate';

  @override
  String get financeAgentFireTrendNetWorth => 'Net worth';

  @override
  String get financeAgentFireTrendSafety => 'Safety level';

  @override
  String get financeAgentFireMethodTitle =>
      'Deterministic on-device calculation';

  @override
  String get financeAgentFireMethodBody =>
      'Calculated from the FIRE plan, assets, annual spending, and stress tests; AI does not determine the metrics.';

  @override
  String get financeAgentFireMethodPeriodLabel => 'Review period';

  @override
  String get financeAgentFireMethodModeLabel => 'Calculation';

  @override
  String get financeAgentFireMethodModeValue =>
      'On device · no cloud inference';

  @override
  String get financeAgentFireFindingCashBucketBelowTargetTitle =>
      'Cash bucket below target';

  @override
  String get financeAgentFireFindingWithdrawalRateAboveSwrTitle =>
      'Withdrawal rate above safe rate';

  @override
  String get financeAgentFireFindingWithdrawalRateInfiniteTitle =>
      'Withdrawal rate unavailable';

  @override
  String get financeAgentFireFindingEtaUnreachableTitle =>
      'FIRE ETA unreachable';

  @override
  String get financeAgentFireFindingCurrencyGapTitle => 'FX coverage gap';

  @override
  String get financeAgentFireFindingUnmappedHoldingsTitle =>
      'Unmapped FIRE holdings';

  @override
  String get financeAgentFireFindingStressDangerTitle => 'Stress test danger';

  @override
  String get financeAgentFireFindingStressCautiousTitle =>
      'Stress test caution';

  @override
  String get financeAgentFireFindingNetWorthBrokenTitle =>
      'Net worth below zero';

  @override
  String financeAgentFireFindingCashBucketBelowTargetBody(Object months) {
    return 'Cash runway is below the configured target of $months months.';
  }

  @override
  String financeAgentFireFindingWithdrawalRateAboveSwrBody(Object rate) {
    return 'Withdrawal rate is above the safe withdrawal rate by $rate.';
  }

  @override
  String get financeAgentFireFindingWithdrawalRateInfiniteBody =>
      'Annual spend exists, but investable assets are zero.';

  @override
  String get financeAgentFireFindingEtaUnreachableBody =>
      'Projection did not reach the FIRE target in the modeled horizon.';

  @override
  String financeAgentFireFindingCurrencyGapBody(Object count) {
    return '$count holdings are excluded because FX conversion is missing.';
  }

  @override
  String financeAgentFireFindingUnmappedHoldingsBody(Object count) {
    return '$count holdings are not mapped to FIRE buckets.';
  }

  @override
  String financeAgentFireFindingStressDangerBody(Object scenario) {
    return 'Stress scenario $scenario breaks the plan.';
  }

  @override
  String financeAgentFireFindingStressCautiousBody(Object scenario) {
    return 'Stress scenario $scenario needs attention.';
  }

  @override
  String get financeAgentFireFindingNetWorthBrokenBody =>
      'Net worth is below zero, so the FIRE plan needs review.';

  @override
  String financeAgentFireFindingDefaultBody(Object code) {
    return 'Review finding $code.';
  }

  @override
  String get financeAgentOptionsSkipNoScan =>
      'no options income scan available';

  @override
  String get financeAgentOptionsSkipNoFinding =>
      'no options income risk finding';

  @override
  String get financeAgentOptionsTitle => 'Options Income Risk Review';

  @override
  String financeAgentOptionsSummary(
    Object elevatedCount,
    Object issueTitle,
    Object opportunityCount,
    Object scanId,
  ) {
    return 'Options income risk review: $issueTitle across $opportunityCount opportunities in $scanId; $elevatedCount elevated-risk contracts.';
  }

  @override
  String get financeAgentOptionsIssueStaleScanTitle => 'Scan data is stale';

  @override
  String financeAgentOptionsIssueStaleScanBody(Object ageHours) {
    return 'Latest options-income scan is $ageHours hours old; quotes and greeks may no longer reflect the market.';
  }

  @override
  String get financeAgentOptionsIssueElevatedRiskTitle =>
      'Elevated-risk contracts present';

  @override
  String financeAgentOptionsIssueElevatedRiskBody(Object count) {
    return '$count cached opportunities are classified as elevated risk before trade review.';
  }

  @override
  String get financeAgentOptionsIssueQuoteQualityTitle =>
      'Quote quality needs review';

  @override
  String financeAgentOptionsIssueQuoteQualityBody(
    Object thinBookCount,
    Object wideSpreadCount,
  ) {
    return '$wideSpreadCount opportunities have bid/ask spread above 8%, and $thinBookCount have thin volume or open interest.';
  }

  @override
  String get financeAgentOptionsIssueNarrowCushionTitle =>
      'Margin of safety is narrow';

  @override
  String financeAgentOptionsIssueNarrowCushionBody(Object count) {
    return '$count opportunities have less than 5% margin of safety to breakeven.';
  }

  @override
  String get financeAgentOptionsIssueMissingGreeksTitle =>
      'Risk inputs are incomplete';

  @override
  String financeAgentOptionsIssueMissingGreeksBody(Object count) {
    return '$count opportunities are missing delta or implied volatility from the quote source.';
  }

  @override
  String get financeAgentOptionsIssueConcentrationTitle =>
      'Underlying concentration is high';

  @override
  String financeAgentOptionsIssueConcentrationBody(
    Object count,
    Object opportunityCount,
    Object underlying,
  ) {
    return '$count of $opportunityCount opportunities are tied to $underlying.';
  }

  @override
  String get financeAgentOptionsIssueModerateClusterTitle =>
      'Moderate-risk cluster';

  @override
  String financeAgentOptionsIssueModerateClusterBody(
    Object moderateCount,
    Object opportunityCount,
  ) {
    return '$moderateCount of $opportunityCount opportunities are moderate risk; review sizing before using the scan.';
  }

  @override
  String get financeAgentOptionsInsightScanSnapshotTitle => 'Scan snapshot';

  @override
  String financeAgentOptionsInsightScanSnapshotBody(
    Object opportunityCount,
    Object riskMix,
  ) {
    return '$opportunityCount cached opportunities, risk mix $riskMix.';
  }

  @override
  String financeAgentOptionsRiskMix(
    Object elevated,
    Object low,
    Object moderate,
  ) {
    return '$low low / $moderate moderate / $elevated elevated';
  }

  @override
  String financeAgentOptionsEvidenceScanLabel(Object scanId) {
    return 'Options income scan $scanId';
  }

  @override
  String get financeAgentOptionsAction => 'Review options scan';

  @override
  String healthAgentRecoverySkipInsufficient(Object count) {
    return 'insufficient HRV data ($count points)';
  }

  @override
  String get healthAgentRecoverySkipNoDecline =>
      'no sustained HRV decline detected';

  @override
  String get healthAgentRecoveryTitle => 'Recovery Alert';

  @override
  String healthAgentRecoverySummary(
    Object baselineMs,
    Object days,
    Object declinePct,
    Object recentMs,
  ) {
    return 'HRV has been below your baseline for $days days ($recentMs ms vs $baselineMs ms average, $declinePct% decline). Consider lighter activity today.';
  }

  @override
  String get healthAgentRecoveryInsightDeclineTitle => 'HRV decline';

  @override
  String healthAgentRecoveryInsightDeclineBody(Object days, Object declinePct) {
    return '$days days below baseline; $declinePct% lower than usual.';
  }

  @override
  String get healthAgentRecoveryInsightAdjustmentTitle =>
      'Suggested adjustment';

  @override
  String get healthAgentRecoveryInsightAdjustmentBody =>
      'Consider lighter activity today and watch recovery tomorrow.';

  @override
  String get healthAgentRecoveryEvidenceLabel => 'HRV trend';

  @override
  String get healthAgentRecoveryAction => 'Review recovery alert';

  @override
  String get healthAgentWeeklySkipNoData => 'no health data this week';

  @override
  String get healthAgentWeeklySkipNoActionable =>
      'no actionable signals this week';

  @override
  String get healthAgentWeeklyTitle => 'Weekly Summary';

  @override
  String healthAgentWeeklyPartRecovery(Object score, Object verdict) {
    return 'Recovery $score/100 ($verdict)';
  }

  @override
  String healthAgentWeeklyPartAvgSleep(Object hours) {
    return 'avg sleep ${hours}h';
  }

  @override
  String healthAgentWeeklyPartSteps(Object steps) {
    return '$steps steps';
  }

  @override
  String healthAgentWeeklyPartWorkouts(Object count, Object minutes) {
    return '$count workouts ($minutes min)';
  }

  @override
  String healthAgentWeeklySummary(Object details) {
    return 'This week: $details.';
  }

  @override
  String get healthAgentWeeklyInsightRecoveryTitle => 'Recovery';

  @override
  String healthAgentWeeklyInsightRecoveryBody(
    Object score,
    Object verdictSuffix,
  ) {
    return '$score/100$verdictSuffix';
  }

  @override
  String get healthAgentWeeklyInsightSleepTitle => 'Sleep';

  @override
  String healthAgentWeeklyInsightSleepBody(Object hours) {
    return 'Average ${hours}h per night.';
  }

  @override
  String get healthAgentWeeklyInsightActivityTitle => 'Activity';

  @override
  String healthAgentWeeklyInsightActivityBody(Object steps) {
    return '$steps steps this week.';
  }

  @override
  String get healthAgentWeeklyInsightWorkoutsTitle => 'Workouts';

  @override
  String healthAgentWeeklyInsightWorkoutsBody(Object count, Object minutes) {
    return '$count workouts, $minutes minutes total.';
  }

  @override
  String get healthAgentWeeklyEvidenceLabel => 'Weekly health rollup';

  @override
  String get healthAgentWeeklyAction => 'Review weekly summary';

  @override
  String get executionAgentReviewSkipNoSignals =>
      'no execution signals to review';

  @override
  String get executionAgentReviewTitle => 'Execution review';

  @override
  String executionAgentReviewSummary(Object details, Object sample) {
    return 'Execution review: $details.$sample';
  }

  @override
  String executionAgentReviewSummaryPartToday(Object count) {
    return '$count today actions';
  }

  @override
  String executionAgentReviewSummaryPartOpen(Object count) {
    return '$count open actions';
  }

  @override
  String executionAgentReviewSummaryPartProjects(Object count) {
    return '$count active projects';
  }

  @override
  String executionAgentReviewSummaryPartCommitments(Object count) {
    return '$count active commitments';
  }

  @override
  String executionAgentReviewSummaryPartProgress(Object count) {
    return '$count progress entries this week';
  }

  @override
  String executionAgentReviewSummaryPartBlocked(Object count) {
    return '$count blocked';
  }

  @override
  String executionAgentReviewSummaryPartDue(Object count) {
    return '$count due';
  }

  @override
  String executionAgentReviewSummaryFirst(Object title) {
    return ' First: $title.';
  }

  @override
  String get executionAgentReviewInsightTodayTitle => 'Today focus';

  @override
  String executionAgentReviewInsightTodayBody(
    Object openCount,
    Object todayCount,
  ) {
    return '$todayCount today-worthy actions out of $openCount open actions.';
  }

  @override
  String get executionAgentReviewInsightBlockedTitle => 'Blocked work';

  @override
  String executionAgentReviewInsightBlockedBody(Object count) {
    return '$count actions are blocked.';
  }

  @override
  String get executionAgentReviewInsightDueTitle => 'Due work';

  @override
  String executionAgentReviewInsightDueBody(Object count) {
    return '$count actions are due.';
  }

  @override
  String get executionAgentReviewInsightProgressTitle => 'Weekly progress';

  @override
  String executionAgentReviewInsightProgressBody(
    Object commitmentCount,
    Object progressCount,
    Object projectCount,
  ) {
    return '$progressCount progress entries across $projectCount active projects and $commitmentCount active commitments.';
  }

  @override
  String get executionAgentReviewInsightStalledTitle => 'Stalled work';

  @override
  String executionAgentReviewInsightStalledBody(Object count) {
    return '$count in-progress actions have not changed for at least 7 days.';
  }

  @override
  String get executionAgentReviewInsightNoNextActionTitle =>
      'Missing next actions';

  @override
  String executionAgentReviewInsightNoNextActionBody(
    Object commitmentCount,
    Object projectCount,
  ) {
    return '$projectCount active projects and $commitmentCount active commitments have no open next action.';
  }

  @override
  String get executionAgentReviewInsightOverdueTargetsTitle =>
      'Overdue targets';

  @override
  String executionAgentReviewInsightOverdueTargetsBody(
    Object commitmentCount,
    Object projectCount,
  ) {
    return '$projectCount projects and $commitmentCount commitments are past their target date.';
  }

  @override
  String get executionAgentReviewInsightRepeatedBlockerTitle =>
      'Repeated blockers';

  @override
  String executionAgentReviewInsightRepeatedBlockerBody(Object count) {
    return '$count actions recorded blockers more than once this week.';
  }

  @override
  String get executionAgentReviewInsightOverloadTitle => 'Today is overloaded';

  @override
  String executionAgentReviewInsightOverloadBody(Object count, Object limit) {
    return '$count actions compete for today. Narrow the focus to about $limit.';
  }

  @override
  String get executionAgentReviewInsightThroughputTitle => 'Weekly throughput';

  @override
  String executionAgentReviewInsightThroughputBody(
    Object completedCount,
    Object droppedCount,
  ) {
    return '$completedCount actions completed and $droppedCount dropped this week.';
  }

  @override
  String get executionAgentReviewInsightOutcomeTitle =>
      'Source signals after completion';

  @override
  String executionAgentReviewInsightOutcomeBody(
    Object activeCount,
    Object clearedCount,
  ) {
    return '$clearedCount source signals are no longer detected and $activeCount are still detected after their actions closed.';
  }

  @override
  String get executionAgentReviewPlanAction => 'Create a recovery plan';

  @override
  String get executionAgentReviewPlanActionBody =>
      'Review stalled and unowned work, then propose concrete next actions or status updates for confirmation.';

  @override
  String get executionAgentReviewAction => 'Review execution';

  @override
  String get knowledgeAgentReviewArtifactTitle => 'Weekly Knowledge Review';

  @override
  String get knowledgeAgentReviewInsightDecisionsTitle => 'Decisions due';

  @override
  String knowledgeAgentReviewInsightDecisionsBody(Object count, Object plural) {
    return '$count decision review$plural need attention.';
  }

  @override
  String get knowledgeAgentReviewInsightAssumptionsTitle => 'Stale assumptions';

  @override
  String knowledgeAgentReviewInsightAssumptionsBody(
    Object count,
    Object days,
    Object plural,
  ) {
    return '$count assumption$plural crossed the $days day verification window.';
  }

  @override
  String get knowledgeAgentReviewAction => 'Review knowledge items';

  @override
  String get knowledgeAgentAssumptionArtifactTitle => 'Assumption Review';

  @override
  String get knowledgeAgentAssumptionInsightTitle => 'Stale assumptions';

  @override
  String knowledgeAgentAssumptionInsightBody(
    Object count,
    Object days,
    Object plural,
  ) {
    return '$count assumption$plural crossed the $days day verification window.';
  }

  @override
  String get knowledgeAgentAssumptionAction => 'Review assumptions';

  @override
  String get knowledgeAgentContradictionArtifactTitle => 'Contradiction Check';

  @override
  String get knowledgeAgentContradictionInsightInvalidatedTitle =>
      'Invalidated assumptions';

  @override
  String knowledgeAgentContradictionInsightInvalidatedBody(
    Object count,
    Object plural,
  ) {
    return '$count decision$plural cite assumptions that are no longer open.';
  }

  @override
  String get knowledgeAgentContradictionInsightPrincipleTitle =>
      'Principle drift';

  @override
  String knowledgeAgentContradictionInsightPrincipleBody(
    Object count,
    Object plural,
  ) {
    return '$count recent item$plural may conflict with active principles.';
  }

  @override
  String get knowledgeAgentContradictionAction => 'Review contradictions';

  @override
  String get knowledgeAgentInboxSkipNoNotes => 'no untriaged notes';

  @override
  String knowledgeAgentInboxSummaryNoSuggestions(Object noteCount) {
    return 'Reviewed $noteCount notes and found no suggestions worth proposing.';
  }

  @override
  String knowledgeAgentInboxSummarySuggestions(
    Object noteCount,
    Object proposalCount,
  ) {
    return 'Generated $proposalCount suggestions for $noteCount notes.';
  }

  @override
  String get knowledgeAgentInboxArtifactTitle => 'Inbox Triage';

  @override
  String get knowledgeAgentInboxInsightSuggestionsTitle => 'New suggestions';

  @override
  String knowledgeAgentInboxInsightSuggestionsBody(
    Object noteCount,
    Object notePlural,
    Object proposalCount,
    Object proposalPlural,
  ) {
    return '$proposalCount suggestion$proposalPlural across $noteCount note$notePlural.';
  }

  @override
  String knowledgeAgentInboxSuggestionKindBody(Object count, Object label) {
    return '$count $label.';
  }

  @override
  String get knowledgeAgentInboxUntitledNote => 'Untitled note';

  @override
  String get knowledgeAgentInboxProposalClassification => 'Classification';

  @override
  String get knowledgeAgentInboxProposalTags => 'Tags';

  @override
  String get knowledgeAgentInboxProposalDecisionLinks => 'Decision links';

  @override
  String get knowledgeAgentInboxProposalSuggestionSingular => 'suggestion';

  @override
  String get knowledgeAgentInboxProposalSuggestionPlural => 'suggestions';

  @override
  String get knowledgeAgentInboxAction => 'Review inbox suggestions';

  @override
  String get ingestKindExpense => 'Expense';

  @override
  String get ingestKindIncome => 'Income';

  @override
  String get ingestKindTransfer => 'Transfer';

  @override
  String get ingestKindTrade => 'Security trade';

  @override
  String get ingestRecordTransfer => 'Open transfer form';

  @override
  String get ingestRecordTrade => 'Open trade form';

  @override
  String get ingestTransferRecorded => 'Transfer recorded and draft completed.';

  @override
  String get ingestTradeRecorded => 'Trade recorded and draft completed.';

  @override
  String get databaseUnlockLoading => 'Unlocking your local data…';

  @override
  String get databaseRecoveryTitle => 'Local data is locked';

  @override
  String get databaseRecoveryMissingKeyMessage =>
      'This device no longer has the key for the encrypted local database. Your data has not been overwritten. If you have an encrypted backup, reset this unreadable local copy and restore the backup from Settings.';

  @override
  String get databaseRecoveryInvalidKeyMessage =>
      'The stored database key is damaged. Your encrypted local data has not been modified. You can retry or reset this unreadable copy before restoring an encrypted backup.';

  @override
  String get databaseRecoveryUnlockFailedMessage =>
      'The device key could not unlock this local database. No data was changed. You can retry or reset the unreadable copy before restoring an encrypted backup.';

  @override
  String get databaseRecoveryMigrationTitle => 'Local data upgrade paused';

  @override
  String get databaseRecoveryMigrationMessage =>
      'NaviWealth could not safely finish encrypting the existing database. The original copy is preserved. Retry after checking free storage; do not reset unless you have a verified backup.';

  @override
  String get databaseRecoveryUnavailableTitle => 'Local data is unavailable';

  @override
  String get databaseRecoveryUnavailableMessage =>
      'The secure database could not be opened. Retry first. If the problem continues, keep the app data intact and review the diagnostic log before taking destructive action.';

  @override
  String get databaseRecoveryRetry => 'Retry unlock';

  @override
  String get databaseRecoveryResetAction => 'Reset unreadable local data';

  @override
  String get databaseRecoveryResetting => 'Resetting local data…';

  @override
  String get databaseRecoveryResetConfirmTitle =>
      'Reset unreadable local data?';

  @override
  String get databaseRecoveryResetConfirmBody =>
      'This permanently removes the encrypted database on this device. It cannot recover a missing device key. Continue only if this local copy is unrecoverable or you have an encrypted backup to restore afterward.';

  @override
  String get databaseRecoveryResetConfirmAction => 'Reset local data';

  @override
  String get databaseRecoveryResetFailed =>
      'Local data could not be reset. Nothing else was changed.';

  @override
  String get financialInboxTitle => 'Financial inbox';

  @override
  String get financialInboxPriorityImportant => 'Important';

  @override
  String get financialInboxPriorityAttention => 'Review';

  @override
  String financialInboxLastCheckedCompact(String date) {
    return 'Checked $date';
  }

  @override
  String get monthlyCloseTitle => 'Monthly close';

  @override
  String get monthlyCloseStart => 'Start monthly close';

  @override
  String get monthlyCloseStartBody =>
      'Review this month\'s evidence, reconcile balances, and close with a clear audit trail.';

  @override
  String monthlyClosePeriod(String period) {
    return 'Close $period';
  }

  @override
  String get monthlyCloseIntro =>
      'Complete each evidence check before closing the month.';

  @override
  String get monthlyCloseImport => 'Review imported transactions';

  @override
  String get monthlyCloseInbox => 'Clear the Financial Inbox';

  @override
  String get monthlyCloseAccounts => 'Reconcile account balances';

  @override
  String get monthlyCloseRunway => 'Review the next 90 days';

  @override
  String get monthlyCloseActions => 'Review follow-up actions';

  @override
  String get monthlyCloseMarkDone => 'Done';

  @override
  String get monthlyCloseUndo => 'Undo';

  @override
  String get monthlyCloseComplete => 'Close month';

  @override
  String get monthlyCloseCompleted => 'Month closed';

  @override
  String get monthlyCloseReconciliationTitle => 'Account reconciliation';

  @override
  String get monthlyCloseLedgerBalance =>
      'Ledger balance at the end of this period';

  @override
  String monthlyCloseDifference(String amount, String unit) {
    return 'Difference: $amount $unit';
  }

  @override
  String get monthlyCloseEnterStatementBalance => 'Enter statement balance';

  @override
  String monthlyCloseStatementBalanceTitle(String account) {
    return 'Statement balance for $account';
  }

  @override
  String get monthlyCloseAcceptDifference => 'Accept difference';

  @override
  String get monthlyCloseDifferenceReasonTitle =>
      'Why is this difference accepted?';

  @override
  String get monthlyCloseDifferenceReasonHint => 'Record the unresolved reason';

  @override
  String get monthlyCloseWithException => 'Close with exception';

  @override
  String get monthlyCloseExceptionTitle => 'Explain the close exception';

  @override
  String get monthlyCloseExceptionHint =>
      'Record why the remaining evidence is accepted';

  @override
  String get monthlyCloseStateBlocked => 'Blocked';

  @override
  String get monthlyCloseStateReady => 'Ready';

  @override
  String get monthlyCloseStateVerified => 'Verified';

  @override
  String get monthlyCloseStateOverridden => 'Accepted';

  @override
  String get monthlyCloseVerifiedBody =>
      'Every evidence check was verified when this month was closed.';

  @override
  String monthlyCloseOverriddenBody(String reason) {
    return 'Closed with exception: $reason';
  }

  @override
  String financialInboxCount(int count) {
    return '$count items need attention';
  }

  @override
  String get financialInboxEmptyTitle => 'You\'re all caught up';

  @override
  String get financialInboxEmptyBody =>
      'New imports and confirmed money risks will appear here.';

  @override
  String get financialInboxResolve => 'Resolve';

  @override
  String get financialInboxSnooze => 'Snooze';

  @override
  String get financialInboxChooseSnooze => 'Snooze until';

  @override
  String get financialInboxSnoozeTomorrow => 'Tomorrow';

  @override
  String get financialInboxSnoozeWeek => 'In 7 days';

  @override
  String get financialInboxSnoozeMonth => 'In 30 days';

  @override
  String get financialInboxResolveGroup => 'Resolve group';

  @override
  String financialInboxResolveGroupBody(int count) {
    return 'Resolve all $count items in this priority group?';
  }

  @override
  String financialInboxResolvedCount(int count) {
    return 'Resolved $count items';
  }

  @override
  String financialInboxImportTitle(int count) {
    return 'Review $count imported items';
  }

  @override
  String get financialInboxImportBody =>
      'Confirm the records before they enter your ledger.';

  @override
  String get financialInboxRunwayTitle => 'Review your money runway';

  @override
  String get financialInboxRunwayBody =>
      'A projected balance is below your safety reserve.';

  @override
  String financialInboxFxTitle(int count) {
    return 'Add $count missing exchange rates';
  }

  @override
  String get financialInboxFxBody =>
      'Missing rates reduce forecast confidence.';

  @override
  String financialInboxBalanceTitle(int count) {
    return 'Resolve $count balance differences';
  }

  @override
  String get financialInboxBalanceBody =>
      'Statement and ledger balances do not match.';

  @override
  String get financialInboxAnomalyTitle => 'Review unusual spending';

  @override
  String get financialInboxAnomalyBody =>
      'Projected spending differs materially from recent months.';

  @override
  String financialInboxSubscriptionTitle(int count) {
    return 'Review $count subscription changes';
  }

  @override
  String get financialInboxSubscriptionBody =>
      'A recurring payment changed beyond the local threshold.';

  @override
  String financialInboxValuationTitle(int count) {
    return 'Refresh $count stale valuations';
  }

  @override
  String get financialInboxValuationBody =>
      'Stale prices reduce the reliability of your current position.';

  @override
  String get financialInboxDecisionTitle => 'Review a financial decision';

  @override
  String get financialInboxDecisionBody =>
      'The scheduled outcome review is now due.';

  @override
  String financialInboxConcentrationTitle(int count) {
    return 'Review $count concentration risks';
  }

  @override
  String get financialInboxConcentrationBody =>
      'A holding or sector exceeds your configured concentration thresholds.';

  @override
  String financialInboxRebalanceTitle(int count) {
    return 'Rebalance $count allocation drifts';
  }

  @override
  String get financialInboxRebalanceBody =>
      'Asset-level target weights have drifted past your rebalance warning threshold.';

  @override
  String financialInboxDividendTitle(int count) {
    return 'Review $count dividend declines';
  }

  @override
  String get financialInboxDividendBody =>
      'Trailing dividends for a holding fell materially versus the prior year.';

  @override
  String get financialInboxEvidenceDimension => 'Dimension';

  @override
  String get financialInboxEvidenceLabel => 'Label';

  @override
  String get financialInboxEvidenceWeight => 'Weight';

  @override
  String get financialInboxEvidenceThreshold => 'Threshold';

  @override
  String get financialInboxEvidenceSeverity => 'Severity';

  @override
  String get financialInboxEvidenceBreachCount => 'Breaches';

  @override
  String get financialInboxEvidenceMaxDeviation => 'Max deviation';

  @override
  String get financialInboxEvidenceDropRatio => 'Drop ratio';

  @override
  String get financialInboxEvidenceTtmGross => 'TTM gross';

  @override
  String get financialInboxEvidencePriorTtmGross => 'Prior TTM gross';

  @override
  String get financialInboxEvidenceAssetId => 'Asset';

  @override
  String get settingsProductMetricsTitle => 'Local product metrics';

  @override
  String get settingsProductMetricsSubtitle =>
      'Opt in to device-only funnel counters. No financial values or identifiers are recorded or uploaded.';

  @override
  String get settingsProductMetricsCopy => 'Copy product evidence';

  @override
  String get settingsProductMetricsCopySubtitle =>
      'Export privacy-safe daily and total aggregates from this device.';

  @override
  String get settingsProductMetricsCopied => 'Product evidence copied';

  @override
  String get lifeEventScenariosTitle => 'Life-event scenarios';

  @override
  String get lifeEventScenariosIntro =>
      'Compare deterministic outcomes before making a choice. Assumptions, your selection, and the later review stay together.';

  @override
  String get lifeEventOptimistic => 'Optimistic';

  @override
  String get lifeEventBaseline => 'Baseline';

  @override
  String get lifeEventConservative => 'Conservative';

  @override
  String get lifeEventScenariosEmptyTitle =>
      'Add your financial baseline first';

  @override
  String get lifeEventScenariosEmptyBody =>
      'Add accounts and spending history so scenarios can use your real liquid balance and monthly outflow.';

  @override
  String get lifeEventLargePurchase => 'Large purchase';

  @override
  String get lifeEventCareerBreak => 'Career break';

  @override
  String get lifeEventHomePurchase => 'Home purchase';

  @override
  String get lifeEventLargePurchaseAssumption =>
      'Preset: one-time cost equal to 20% of current liquid funds.';

  @override
  String lifeEventCareerBreakAssumption(int months) {
    return 'Preset: no income for $months months.';
  }

  @override
  String get lifeEventHomePurchaseAssumption =>
      'Preset: 30% of liquid funds upfront and 10% higher monthly outflow for one year.';

  @override
  String get lifeEventAfter90Days => 'Liquid funds after 90 days';

  @override
  String get lifeEventAfter12Months => 'Liquid funds after 12 months';

  @override
  String get lifeEventMonthlySurplus => 'Monthly surplus during event';

  @override
  String get lifeEventEditAssumptions => 'Edit assumptions';

  @override
  String get lifeEventUpfrontCost => 'Upfront cost';

  @override
  String get lifeEventIncomeDelta => 'Monthly income change';

  @override
  String get lifeEventOutflowDelta => 'Monthly outflow change';

  @override
  String get lifeEventDurationMonths => 'Duration in months';

  @override
  String get lifeEventFireImpact => 'Estimated FIRE impact';

  @override
  String lifeEventFireDelay(int months) {
    return 'About $months months later';
  }

  @override
  String get lifeEventFireNoDelay => 'No material delay';

  @override
  String get lifeEventAskAi => 'Explore with assistant';

  @override
  String get lifeEventChooseScenario => 'Save decision';

  @override
  String get lifeEventOpenAction => 'Open follow-up';

  @override
  String get lifeEventAdjustPlan => 'Adjust budget';

  @override
  String get lifeEventDecisionSaved => 'Decision and assumptions saved';

  @override
  String lifeEventReviewActionTitle(String decision) {
    return 'Review decision: $decision';
  }

  @override
  String get lifeEventReviewActionBody =>
      'Compare the deterministic forecast with observed financial data. Do not infer causality.';

  @override
  String get lifeEventDecisionHistory => 'Decisions to review';

  @override
  String get lifeEventPendingReview => 'Pending review';

  @override
  String get lifeEventReviewed => 'Reviewed';

  @override
  String lifeEventReviewOn(String date) {
    return 'Review on $date';
  }

  @override
  String get lifeEventChooseReviewDate => 'Choose review timing';

  @override
  String get lifeEventReviewIn30Days => 'In 30 days';

  @override
  String get lifeEventReviewIn90Days => 'In 90 days';

  @override
  String get lifeEventReviewIn180Days => 'In 180 days';

  @override
  String get lifeEventCaptureActual => 'Capture current outcome';

  @override
  String lifeEventObservedDifference(String amount) {
    return 'Observed 90-day balance difference: $amount. This is a comparison, not a causal claim.';
  }

  @override
  String get moneyRunwayCreateAction => 'Turn risk into an action';

  @override
  String get moneyRunwayActionConfirmTitle => 'Create an Execution action?';

  @override
  String get moneyRunwayActionConfirmBody =>
      'The current runway evidence will be attached. Nothing is created until you confirm.';

  @override
  String get moneyRunwayActionTitle => 'Improve short-term money runway';

  @override
  String get moneyRunwayActionCreated => 'Execution action created';

  @override
  String get moneyRunwayTitle => 'Money runway';

  @override
  String get moneyRunwayNinetyDayBalance => 'Expected balance in 90 days';

  @override
  String get moneyRunwayEmptyTitle => 'Build your first runway';

  @override
  String get moneyRunwayEmptyBody =>
      'Import a statement or add an account to see the next 90 days.';

  @override
  String get moneyRunwayHorizonsTitle => 'Forward balance';

  @override
  String moneyRunwayMinimumBalance(String amount) {
    return 'Lowest expected balance: $amount';
  }

  @override
  String moneyRunwayMinimumBalanceDate(String date) {
    return 'Lowest point: $date';
  }

  @override
  String moneyRunwayRiskDate(String date) {
    return 'Cash shortfall expected $date';
  }

  @override
  String moneyRunwayReserveBreachDate(String date) {
    return 'Below reserve target $date';
  }

  @override
  String moneyRunwayDays(Object days) {
    return '$days days';
  }

  @override
  String get moneyRunwayStatusHealthy => 'On track';

  @override
  String get moneyRunwayStatusHealthyBody =>
      'Expected cash stays above your reserve target.';

  @override
  String get moneyRunwayStatusWatch => 'Watch';

  @override
  String get moneyRunwayStatusWatchBody =>
      'Expected cash remains positive but falls below your reserve target.';

  @override
  String get moneyRunwayStatusShortfall => 'Shortfall';

  @override
  String get moneyRunwayStatusShortfallBody =>
      'Expected cash falls below zero within this window.';

  @override
  String moneyRunwayConfidence(Object confidence) {
    return 'Confidence: $confidence';
  }

  @override
  String get moneyRunwayConfidenceLow => 'low';

  @override
  String get moneyRunwayConfidenceMedium => 'medium';

  @override
  String get moneyRunwayConfidenceHigh => 'high';

  @override
  String get moneyRunwayAssumptionsTitle => 'Assumptions';

  @override
  String get moneyRunwayStartingCash => 'Liquid balance';

  @override
  String get moneyRunwayReserveTarget => 'Reserve target';

  @override
  String get moneyRunwayVariableEstimate =>
      'Estimated variable spending / month';

  @override
  String get moneyRunwaySourceObservedHistory => 'Observed 90-day history';

  @override
  String get moneyRunwaySourceFirePlan => 'FIRE plan';

  @override
  String get moneyRunwaySourceDefaultPolicy => 'Default 3-month reserve';

  @override
  String get moneyRunwayCoverage => 'Emergency coverage';

  @override
  String get moneyRunwayCompleteness => 'Data completeness';

  @override
  String get moneyRunwayHistoricalError => 'Recent forecast error';

  @override
  String get moneyRunwayScenariosTitle => 'Stress test';

  @override
  String get moneyRunwayScenarioPurchase => 'Spend one month of expenses now';

  @override
  String get moneyRunwayScenarioDelayedIncome =>
      'Delay expected income by 14 days';

  @override
  String get moneyRunwayScenarioReducedIncome =>
      'Reduce expected income by 30%';

  @override
  String get moneyRunwayCustomScenarioAction => 'Custom stress test';

  @override
  String get moneyRunwayCustomScenarioTitle => 'Custom runway scenario';

  @override
  String moneyRunwayCustomPurchase(String currency) {
    return 'One-time expense ($currency)';
  }

  @override
  String get moneyRunwayCustomDelayDays => 'Income delay (days)';

  @override
  String get moneyRunwayCustomReductionPercent => 'Income reduction (%)';

  @override
  String get moneyRunwayCustomDurationDays => 'Reduction duration (days)';

  @override
  String get moneyRunwayCustomInvalid =>
      'Enter non-negative values, a reduction from 0 to 100%, and at least one stress factor.';

  @override
  String get moneyRunwayCustomRun => 'Run scenario';

  @override
  String get moneyRunwayCustomResult => 'Custom minimum balance';

  @override
  String get moneyRunwayCustomReset => 'Clear custom scenario';

  @override
  String moneyRunwayCoverageMonths(Object months) {
    return '$months months';
  }

  @override
  String get moneyRunwayScheduledTitle => 'Known upcoming flows';

  @override
  String get moneyRunwayScheduledEmpty =>
      'No recurring income or bills are configured.';

  @override
  String moneyRunwayScheduledCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count upcoming items included',
      one: '1 upcoming item included',
    );
    return '$_temp0';
  }

  @override
  String get moneyRunwayTimelineTitle => 'Upcoming cash timeline';

  @override
  String moneyRunwayTimelineMore(int count) {
    return 'Show all $count';
  }

  @override
  String get moneyRunwayTimelineLess => 'Collapse timeline';

  @override
  String moneyRunwayTimelineBalanceAfter(String amount) {
    return 'Expected balance that day: $amount';
  }

  @override
  String get moneyRunwayTimelineEmpty =>
      'No scheduled flows in the next 90 days. Add recurring income or bills to make this forecast more useful.';

  @override
  String get moneyRunwayManageScheduled => 'Manage scheduled flows';

  @override
  String get moneyRunwayDeclaredDividend => 'Declared after-tax dividend';

  @override
  String get moneyRunwayEstimatedDividend => 'Estimated after-tax dividend';

  @override
  String get moneyRunwayEstimatedFlow => 'estimate';

  @override
  String moneyRunwayMissingFx(Object currencies) {
    return 'Excluded because FX rates are missing: $currencies';
  }

  @override
  String get financeActivationTitle => 'Your first useful result';

  @override
  String get financeActivationDismiss => 'Hide setup guide';

  @override
  String financeActivationProgress(int completed, int total) {
    return '$completed/$total';
  }

  @override
  String get financeActivationDataTitle => 'Start with real activity';

  @override
  String get financeActivationDataBody =>
      'Add an entry manually or import a statement so the result is grounded in your own data.';

  @override
  String get financeActivationDataAction => 'Add financial data';

  @override
  String get financeActivationReviewTitle => 'Review only the exceptions';

  @override
  String financeActivationReviewBody(int count) {
    return '$count items still need confirmation or recovery.';
  }

  @override
  String get financeActivationReviewAction => 'Continue review';

  @override
  String get financeActivationRunwayTitle => 'Check the next 90 days';

  @override
  String get financeActivationRunwayBody =>
      'Your entries are ready. Verify the resulting cash runway and its missing data.';

  @override
  String get financeActivationRunwayAction => 'Review runway';

  @override
  String get financialInboxEvidenceTitle => 'Evidence';

  @override
  String get financialInboxFirstDetected => 'First detected';

  @override
  String get financialInboxLastChecked => 'Last checked';

  @override
  String get financialInboxLinkedAction => 'Linked action';

  @override
  String get financialInboxFixSource => 'Fix the source';

  @override
  String get financialInboxCreateAction => 'Create action';

  @override
  String get financialInboxViewAction => 'View action';

  @override
  String get financialInboxActionUnavailable =>
      'Enable ExecutionOS to create an action.';

  @override
  String get financialInboxEvidencePeriod => 'Period';

  @override
  String get financialInboxEvidenceMismatchCount => 'Balance differences';

  @override
  String get financialInboxEvidenceChangeRatio => 'Change ratio';

  @override
  String get financialInboxEvidenceExpenseCount => 'Expenses this month';

  @override
  String get financialInboxExpenseDetailsTitle => 'Expense details';

  @override
  String get financialInboxExpenseUntitled => 'Expense';

  @override
  String get financialInboxEvidenceChangeCount => 'Changes';

  @override
  String get financialInboxEvidenceStaleCount => 'Stale values';

  @override
  String get financialInboxEvidenceReviewDate => 'Review date';

  @override
  String get financialInboxEvidenceCurrencies => 'Currencies';

  @override
  String get financialInboxEvidenceCompleteness => 'Data completeness';

  @override
  String get financialInboxActionTodo => 'To do';

  @override
  String get financialInboxActionDoing => 'In progress';

  @override
  String get financialInboxActionBlocked => 'Blocked';

  @override
  String get financialInboxActionDone => 'Completed';

  @override
  String get financialInboxActionDropped => 'Dropped';

  @override
  String get financialInboxActionUnknown => 'Unavailable';

  @override
  String get financialInboxRevalidation => 'Source revalidation';

  @override
  String get financialInboxRevalidationCleared =>
      'Cleared in a later complete check';

  @override
  String get financialInboxRevalidationStillDetected =>
      'Still detected after completion';

  @override
  String get financialInboxRevalidationInconclusive =>
      'Could not complete the source check';

  @override
  String get financialInboxRevalidationActionDropped =>
      'Action dropped; signal remains open';

  @override
  String get financialInboxRevalidatedAt => 'Revalidated at';

  @override
  String get monthlyCloseCoverageTitle => 'Account coverage';

  @override
  String monthlyCloseCoverageValue(int accepted, int total) {
    return '$accepted/$total';
  }

  @override
  String monthlyCloseSincePrevious(int newCount, int clearedCount) {
    return 'Since the previous close: $newCount new signals, $clearedCount cleared.';
  }

  @override
  String monthlyClosePreviousDuration(int minutes) {
    return 'Previous close took $minutes minutes.';
  }

  @override
  String monthlyCloseCarriedForward(int signals, int reconciliations) {
    return 'Still open from last close: $signals signals, $reconciliations reconciliation exceptions.';
  }

  @override
  String get monthlyCloseHistoryTitle => 'Close history';

  @override
  String monthlyCloseHistoryCount(int count) {
    return '$count previous closes';
  }

  @override
  String monthlyCloseHistoryExceptions(int count) {
    return '$count exceptions';
  }

  @override
  String monthlyCloseHistoryDuration(int minutes) {
    return '$minutes min';
  }

  @override
  String get expenseCategoriesManageTitle => 'Expense categories';

  @override
  String get expenseCategoriesAdd => 'Add category';

  @override
  String get expenseCategoriesEdit => 'Edit category';

  @override
  String get expenseCategoriesEmpty => 'No expense categories';

  @override
  String get expenseCategoriesArchived => 'Archived';

  @override
  String get expenseCategoriesBuiltIn => 'Built-in';

  @override
  String get expenseCategoriesCustom => 'Custom';

  @override
  String get expenseCategoriesMoveUp => 'Move up';

  @override
  String get expenseCategoriesMoveDown => 'Move down';

  @override
  String get expenseCategoriesArchive => 'Archive category';

  @override
  String get expenseCategoriesRestore => 'Restore category';

  @override
  String get expenseCategoriesNameLabel => 'Name';

  @override
  String get expenseCategoriesNameRequired => 'Enter a category name';

  @override
  String get expenseCategoriesParentLabel => 'Parent category';

  @override
  String get expenseCategoriesParentHelper =>
      'Optional. Leave empty for a top-level category.';

  @override
  String get expenseCategoriesMakeTopLevel => 'Move to top level';

  @override
  String get expenseCategoriesIconLabel => 'Icon token';

  @override
  String get expenseCategoriesColorLabel => 'Accent color';

  @override
  String get expenseCategoriesColorHelper =>
      'Choose a color used in lists and reports.';

  @override
  String get leapsOverlayTitle => 'LEAPS upside overlay';

  @override
  String get leapsOverlaySubtitle =>
      'Long calls tracked separately from the Wheel';

  @override
  String get leapsOverlayAdd => 'Add LEAPS call';

  @override
  String get leapsOverlayEdit => 'Edit LEAPS call';

  @override
  String get leapsOverlayEmpty => 'No long calls recorded';

  @override
  String leapsOverlayOpenCount(int count) {
    return '$count open LEAPS';
  }

  @override
  String get leapsOverlayCost => 'Open premium at risk';

  @override
  String get leapsOverlayCoverage => 'Wheel income coverage';

  @override
  String get leapsOverlayDeltaShares => 'Delta-equivalent shares';

  @override
  String get leapsOverlayCombinedRealized => 'Combined realized P&L';

  @override
  String get leapsOverlayUnknown => 'Not recorded';

  @override
  String leapsOverlayCoverageValue(String percent) {
    return '$percent% covered';
  }

  @override
  String get leapsOverlayOptionSymbol => 'Call contract';

  @override
  String get leapsOverlayOpenedAt => 'Opened';

  @override
  String get leapsOverlayExpiration => 'Expiration';

  @override
  String get leapsOverlayStrike => 'Strike';

  @override
  String get leapsOverlayEntryDebit => 'Entry debit per contract';

  @override
  String get leapsOverlayExitCredit => 'Exit credit per contract';

  @override
  String get leapsOverlayCurrentMark => 'Current mark per contract';

  @override
  String get leapsOverlayCurrentDelta => 'Current delta (0–1)';

  @override
  String get leapsOverlayMarkedAt => 'Mark date';

  @override
  String get leapsOverlayStatus => 'Position status';

  @override
  String get leapsOverlayStatusOpen => 'Open';

  @override
  String get leapsOverlayStatusClosed => 'Closed';

  @override
  String get leapsOverlayStatusExercised => 'Exercised';

  @override
  String get leapsOverlayStatusExpired => 'Expired';

  @override
  String get leapsOverlayDeleteTitle => 'Delete LEAPS position?';

  @override
  String get leapsOverlayDeleteBody =>
      'This removes the position from the synced strategy record.';

  @override
  String get leapsOverlayDurationHint =>
      'LEAPS are long-dated at listing. Record the actual expiration even when less than one year remains.';

  @override
  String get leapsOverlayDeltaHint =>
      'Optional manual snapshot. Leave empty when unknown; NaviWealth will not invent a value.';

  @override
  String get leapsOverlayDateInvalid =>
      'Expiration must be after the open date.';

  @override
  String get leapsOverlayDeltaInvalid => 'Enter a delta from 0 to 1.';

  @override
  String get aiChatProposalKindLeapsCall => 'LEAPS call position';

  @override
  String get incomeStrategyTitle => 'Income strategy';

  @override
  String get incomeStrategyTabOverview => 'Overview';

  @override
  String get incomeStrategyTabUnderlyings => 'Underlyings';

  @override
  String get incomeStrategyTabActivity => 'Activity';

  @override
  String get incomeStrategyEmptyTitle => 'No income strategy yet';

  @override
  String get incomeStrategyEmptyBody =>
      'Compose dividends, Wheel and LEAPS sleeves around an underlying. Existing positions remain visible even when they are outside the plan.';

  @override
  String get incomeStrategyRealizedResult => 'Realized result';

  @override
  String get incomeStrategyProjectedCash => 'Projected cash';

  @override
  String get incomeStrategyCapitalAtRisk => 'Capital at risk';

  @override
  String get incomeStrategyRiskCount => 'Risks to review';

  @override
  String get incomeStrategyRisksTitle => 'Coordination risks';

  @override
  String get incomeStrategyUnderlyingsTitle => 'Strategy tracks';

  @override
  String incomeStrategyRiskSummary(int count) {
    return '$count risks';
  }

  @override
  String get incomeStrategyPlanAligned => 'Aligned';

  @override
  String get incomeStrategyEnabled => 'On';

  @override
  String get incomeStrategyDisabled => 'Off';

  @override
  String get incomeStrategyNoPosition => 'No current position';

  @override
  String get incomeStrategyActivityEmpty => 'No strategy activity yet';

  @override
  String get incomeStrategyOpenDividendCenter => 'Dividend center';

  @override
  String get incomeStrategyOpenOptionsPlanner => 'Options workspace';

  @override
  String get incomeStrategySleeveDividends => 'Dividends';

  @override
  String get incomeStrategySleeveWheel => 'Wheel';

  @override
  String get incomeStrategySleeveLeaps => 'LEAPS call';

  @override
  String get incomeStrategyStatusHolding => 'Holding';

  @override
  String get incomeStrategyStatusPlanned => 'Planned';

  @override
  String get incomeStrategyStatusOpen => 'Open';

  @override
  String get incomeStrategyStatusResolved => 'Resolved';

  @override
  String get incomeStrategyMetricPartial => 'Partial valuation';

  @override
  String get incomeStrategyCashFlowDividend => 'Gross dividend';

  @override
  String get incomeStrategyCashFlowWithholding => 'Dividend withholding';

  @override
  String get incomeStrategyCashFlowWheel => 'Wheel realized result';

  @override
  String get incomeStrategyCashFlowLeapsPurchase => 'LEAPS purchase';

  @override
  String get incomeStrategyCashFlowLeapsSale => 'LEAPS sale';

  @override
  String get incomeStrategyCashFlowLeapsExercise => 'LEAPS exercise cash';

  @override
  String get incomeStrategyRiskUnplanned =>
      'A live sleeve is outside the current strategy plan. Review it instead of hiding the exposure.';

  @override
  String get incomeStrategyRiskCapitalBudget =>
      'Combined sleeve capital exceeds the plan budget.';

  @override
  String get incomeStrategyRiskAssignment =>
      'Open put assignment value exceeds the configured limit.';

  @override
  String get incomeStrategyRiskConcentration =>
      'The underlying exceeds the configured portfolio weight.';

  @override
  String get incomeStrategyRiskDividend =>
      'An open covered call may remove shares while the plan is configured to preserve dividend income.';

  @override
  String get incomeStrategyRiskStacked =>
      'The Wheel short put and LEAPS call stack downside-sensitive capital on the same underlying.';

  @override
  String get incomeStrategyRiskLeapsBudget =>
      'Open LEAPS cost exceeds the configured budget.';

  @override
  String get incomeStrategyRiskLeapsCoverage =>
      'Realized income does not yet cover the open LEAPS cost.';

  @override
  String get incomeStrategyRiskMissingMark =>
      'A LEAPS position has no current mark, so market value is incomplete.';

  @override
  String get incomeStrategyRiskMissingDelta =>
      'A LEAPS position has no delta, so equivalent-share exposure is incomplete.';

  @override
  String get incomeStrategyRiskMissingFx =>
      'An FX rate is missing, so one or more monetary totals are incomplete.';

  @override
  String get incomeStrategyRiskStaleValuation =>
      'A position mark is stale and should be refreshed.';

  @override
  String get incomeStrategyRiskIncomeTarget =>
      'Year-to-date realized income is materially behind the configured annual target.';

  @override
  String get incomeStrategyRiskExpiration =>
      'An option is near expiration and needs review.';

  @override
  String get incomeStrategyPlanAdd => 'Add strategy plan';

  @override
  String get incomeStrategyPlanEdit => 'Edit strategy plan';

  @override
  String get incomeStrategyPlanSubtitle =>
      'Choose any combination of sleeves and set shared risk limits.';

  @override
  String get incomeStrategyPlanAsset => 'Underlying';

  @override
  String get incomeStrategyPlanSleeves => 'Enabled sleeves';

  @override
  String get incomeStrategyPlanGroup => 'Strategy group';

  @override
  String get incomeStrategyPlanGroupHint =>
      'Coordinate wheel and LEAPS legs across underlyings — e.g. a TQQQ wheel funding a QQQ LEAPS call.';

  @override
  String get incomeStrategyPlanGroupNone => 'None (standalone)';

  @override
  String get incomeStrategyPlanGroupNew => 'New group…';

  @override
  String get incomeStrategyPlanGroupNameLabel => 'Group name';

  @override
  String get incomeStrategyPlanGroupNameRequired =>
      'Enter a name for the new group.';

  @override
  String get incomeStrategyPlanPreserveDividend => 'Preserve dividend income';

  @override
  String get incomeStrategyPlanAllowCalledAway =>
      'Allow shares to be called away';

  @override
  String get incomeStrategyPlanLimits => 'Shared limits';

  @override
  String get incomeStrategyPlanLimitsHint =>
      'Optional portfolio and sleeve guardrails';

  @override
  String get incomeStrategyPlanCapitalBudget => 'Total capital budget';

  @override
  String get incomeStrategyPlanAnnualTarget => 'Annual income target';

  @override
  String get incomeStrategyPlanMaxWeight => 'Maximum portfolio weight (%)';

  @override
  String get incomeStrategyPlanMaxLeapsCost => 'Maximum open LEAPS cost';

  @override
  String get incomeStrategyPlanMaxAssignment => 'Maximum put assignment value';

  @override
  String get incomeStrategyPlanAssetRequired => 'Choose an underlying.';

  @override
  String get incomeStrategyPlanSleeveRequired => 'Enable at least one sleeve.';

  @override
  String get incomeStrategyPlanNumberInvalid =>
      'Enter non-negative limits and a portfolio weight from 0 to 100.';

  @override
  String get incomeStrategyPlanDeleteTitle => 'Delete strategy plan?';

  @override
  String get incomeStrategyPlanDeleteBody =>
      'Live holdings and trades remain visible, but the shared sleeve settings and limits will be removed.';

  @override
  String get rebalanceStagePortfolioTitle =>
      '1 · Move capital between portfolios';

  @override
  String get rebalanceStageStrategyTitle =>
      '2 · Allocate capital between sleeves';

  @override
  String get rebalanceStageAssetTitle =>
      '3 · Rebalance assets inside the sleeve';

  @override
  String rebalanceDecisionPolicyBlocked(String name) {
    return '$name is outside its allowed deviation, but its transfer rule blocks the required movement.';
  }

  @override
  String rebalanceDecisionNoCounterparty(String name) {
    return '$name is outside its allowed deviation, but there is no eligible source or destination.';
  }

  @override
  String get rebalanceCapitalBlockedTitle => 'Needs attention';

  @override
  String get rebalanceConfigurePlanAction => 'Edit allocation plan';

  @override
  String get portfolioCapitalAssignmentTitle => 'Asset assignment';

  @override
  String get portfolioCapitalAssignmentSubtitle =>
      'Assign positions and cash to exactly one portfolio and strategy.';

  @override
  String get portfolioCapitalAssignmentLotsAction => 'Assign positions';

  @override
  String get portfolioCapitalAssignmentLotsHint =>
      'Place whole or partial tax lots under a strategy.';

  @override
  String get portfolioCapitalAssignmentCashAction => 'Assign cash';

  @override
  String get portfolioCapitalAssignmentCashHint =>
      'Reserve account cash for a strategy.';

  @override
  String get portfolioStrategyLibraryTitle => 'Strategy library';

  @override
  String get portfolioStrategyLibrarySubtitle =>
      'Built-in and custom strategy types used when adding a strategy.';

  @override
  String get portfolioStrategyBuiltInBadge => 'Built-in';

  @override
  String get portfolioStrategyCustomBadge => 'Custom';

  @override
  String get portfolioStrategyEditAction => 'Edit';

  @override
  String get portfolioStrategyArchiveAction => 'Archive';

  @override
  String get portfolioStrategyArchiveTitle => 'Archive this strategy type?';

  @override
  String get portfolioStrategyArchiveBody =>
      'Existing strategies keep their current configuration. This type will no longer appear when adding a strategy.';

  @override
  String get portfolioStrategyArchiveFailed =>
      'Couldn\'t archive this strategy type.';

  @override
  String get rebalanceCapitalFirstHint =>
      'Complete the capital movements above by updating asset assignment. Asset trades unlock after the portfolio and strategy balances are within tolerance.';

  @override
  String get rebalanceCapitalBlockedHint =>
      'This allocation cannot be completed automatically. Adjust its transfer policy or target, or add eligible capital; the next stage will be recalculated after it is resolved.';

  @override
  String get rebalanceTransferTaskTitle => 'Current transfer task';

  @override
  String rebalanceTransferTaskSummary(String from, String to, String amount) {
    return '$from → $to · $amount';
  }

  @override
  String get rebalanceTransferTaskHint =>
      'Move cash first, then adjust position ownership if needed. Return to rebalancing when done to recalculate the next stage from the latest assignments.';

  @override
  String get rebalanceTransferTaskRecalculateAction => 'Done, recalculate';

  @override
  String get rebalanceCapitalFirstAction => 'Resolve capital movements first';

  @override
  String get rebalanceResolveTransferAction => 'Resolve transfer';

  @override
  String get healthActivationTitle => 'Connect your health data';

  @override
  String get healthActivationBody =>
      'Choose the source you already use. HealthOS stays useful with manual entries, and every connection is read-only.';

  @override
  String get healthActivationAction => 'Connect system health';

  @override
  String get healthActivationGarminAction => 'Connect Garmin';

  @override
  String get healthActivationManualAction => 'Record manually';

  @override
  String healthRefreshFresh(String time) {
    return 'Health data updated $time';
  }

  @override
  String healthRefreshStale(String time) {
    return 'Health data may be out of date · updated $time';
  }

  @override
  String healthRefreshPartialFailure(int count) {
    return '$count data source failed to refresh';
  }

  @override
  String get healthRefreshPullHint =>
      'Pull down to sync every connected source';

  @override
  String healthRecoveryConfidence(String confidence, int coverage) {
    return '$confidence confidence · $coverage% coverage';
  }

  @override
  String get healthRecoveryConfidenceHigh => 'High';

  @override
  String get healthRecoveryConfidenceMedium => 'Medium';

  @override
  String get healthRecoveryConfidenceLow => 'Low';

  @override
  String get healthRecoveryConfidenceInsufficient => 'Insufficient';

  @override
  String healthRecoveryFreshness(String time) {
    return 'Latest input $time';
  }

  @override
  String get healthRecoveryWhyTitle => 'Why this score';

  @override
  String get healthRecoveryWhyLess => 'Hide score details';

  @override
  String healthRecoveryEvidence(String metric, String recent, String delta) {
    return '$metric: $recent now · $delta vs baseline';
  }

  @override
  String healthRecoveryEvidenceNoBaseline(String metric, String recent) {
    return '$metric: $recent · building your baseline';
  }

  @override
  String healthRecoveryEvidenceBaseline(
    String baseline,
    int recentSamples,
    int baselineSamples,
  ) {
    return 'Baseline $baseline · $recentSamples recent / $baselineSamples baseline samples';
  }

  @override
  String healthRecoveryEvidenceNoBaselineSamples(int recentSamples) {
    return '$recentSamples recent samples · baseline forming';
  }

  @override
  String healthRecoveryDeltaUp(String value) {
    return '$value% above';
  }

  @override
  String healthRecoveryDeltaDown(String value) {
    return '$value% below';
  }

  @override
  String get healthRecoveryMetricHrv => 'HRV';

  @override
  String get healthRecoveryMetricRhr => 'Resting heart rate';

  @override
  String get healthRecoveryMetricSleep => 'Sleep';

  @override
  String get healthRecoveryMetricVo2 => 'VO₂ max';

  @override
  String get healthRecoveryMetricBodyBattery => 'Body Battery';

  @override
  String get healthRecoveryMetricStress => 'Stress';

  @override
  String get healthSettingsSourcesTitle => 'Connected data sources';

  @override
  String get healthSettingsSourcesHelp =>
      'Manage connections, secure Garmin sessions, and source freshness in one place.';

  @override
  String get executionDailyFocusTitle => 'Daily Top 3';

  @override
  String get executionDailyFocusEmpty =>
      'Choose up to three actions that deserve your attention today.';

  @override
  String get executionTodayNextActions => 'Next actions';

  @override
  String executionDailyFocusSuggestion(String titles) {
    return 'Suggested from your latest review: $titles';
  }

  @override
  String get executionDailyFocusUseSuggestion => 'Use these';

  @override
  String executionActionStatusUpdated(String status) {
    return 'Action moved to $status';
  }

  @override
  String get executionQuickWhenField => 'When';

  @override
  String get executionQuickWhenInbox => 'Inbox';

  @override
  String get executionQuickWhenToday => 'Today';

  @override
  String get executionQuickWhenTomorrow => 'Tomorrow';

  @override
  String get executionShowDetails => 'More details';

  @override
  String get executionHideDetails => 'Fewer details';

  @override
  String get executionScheduleAfterDue =>
      'The scheduled date must be on or before the deadline.';

  @override
  String get executionBlockReasonTitle => 'What is blocking this action?';

  @override
  String get executionBlockReasonHint =>
      'Name the dependency, decision, or missing information';

  @override
  String get executionDailyFocusToggle => 'Top 3';

  @override
  String executionDailyFocusCount(int count) {
    return '$count/3';
  }

  @override
  String get executionDailyFocusReplaceTitle => 'Replace a Top 3 action';

  @override
  String executionDailyFocusReplaceBody(String title) {
    return 'Your Top 3 is full. Choose which action to replace with “$title”.';
  }

  @override
  String get executionDailyFocusReplaceAction => 'Replace this action';

  @override
  String get executionDailyFocusMoveUp => 'Move up';

  @override
  String get executionDailyFocusMoveDown => 'Move down';

  @override
  String get executionDailyFocusRemove => 'Remove from Top 3';

  @override
  String get executionDueAgentTitle => 'Actions due soon';

  @override
  String get executionDueAgentDescription =>
      'Checks daily for open actions due by tomorrow and can send a local reminder.';

  @override
  String get executionDueAgentNothingDue =>
      'No actions are due in the next day.';

  @override
  String executionDueAgentSummary(int count, String title) {
    return '$count actions are due by tomorrow. First: $title';
  }

  @override
  String executionReviewCreateNextActions(int count) {
    return 'Create $count next actions';
  }

  @override
  String get executionReviewCreateNextActionsBody =>
      'Create one high-priority action for every project or commitment that still has no open next action?';

  @override
  String executionReviewCreatedNextActions(int count) {
    return 'Created $count next actions';
  }

  @override
  String executionReviewDraftNextActions(int count) {
    return 'Review $count missing next actions';
  }

  @override
  String get executionReviewAgentNotRun =>
      'The weekly Execution Review has not run yet.';

  @override
  String get executionReviewAgentRunning => 'Execution Review is running now.';

  @override
  String get executionReviewAgentFailed =>
      'The latest Execution Review failed. Your activity summary is still available.';

  @override
  String executionReviewAgentLastRun(String date) {
    return 'Last Execution Review: $date';
  }

  @override
  String get executionReviewRunNow => 'Run review';

  @override
  String executionReviewNextActionFor(String title) {
    return 'Define the next step for $title';
  }

  @override
  String get agentSettingsTriggerEvent => 'Data change';

  @override
  String get executionSearchTitle => 'Search ExecutionOS';

  @override
  String get executionSearchFilterTitle => 'Result type';

  @override
  String get executionSearchFilterAll => 'All';

  @override
  String get executionSearchHint => 'Search actions and plans';

  @override
  String get executionSearchEmptyTitle => 'Search all execution work';

  @override
  String get executionSearchEmptyBody =>
      'Results include open and closed actions and plans.';

  @override
  String get executionSearchStartAction => 'Start searching';

  @override
  String get executionSearchNoResults => 'No matching work';

  @override
  String get executionSearchTryAgain => 'Try a title, note, or description.';

  @override
  String get executionSearchClearAction => 'Clear search';

  @override
  String get executionSearchKindAction => 'Action';

  @override
  String get executionSearchKindProject => 'Plan';

  @override
  String get executionSearchKindProgress => 'Progress';

  @override
  String get knowledgeSettingsReviewCadence => 'Review cadence';

  @override
  String get knowledgeSettingsStaleThreshold => 'Stale assumption threshold';

  @override
  String knowledgeSettingsEveryDays(int days) {
    return 'Every $days days';
  }

  @override
  String knowledgeSettingsAfterDays(int days) {
    return 'After $days days without verification';
  }

  @override
  String knowledgeCaptureNeedsStructure(String kind) {
    return '$kind needs its structured fields before it can be created. Add decision options, assumption confidence, or experiment method and metrics.';
  }

  @override
  String get knowledgeMarkdownInsertImage => 'Insert image';

  @override
  String get knowledgeImageSourceCamera => 'Take photo';

  @override
  String get knowledgeImageSourceGallery => 'Photo library';

  @override
  String get knowledgeImageSourceFile => 'Choose file';

  @override
  String get knowledgeImageImportFailed => 'Couldn\'t import the image';

  @override
  String get knowledgeImageLocalOnlyToast =>
      'Image inserted. It is currently stored on this device only.';

  @override
  String get developerIssuesTitle => 'Report a product issue';

  @override
  String get developerIssuesSubtitle =>
      'Save a local dogfood report with bounded diagnostics. Nothing is sent until you export it.';

  @override
  String get developerIssuesDescriptionLabel => 'What should be improved?';

  @override
  String get developerIssuesDescriptionHint =>
      'Example: The FIRE card\'s information hierarchy makes the recommended action hard to find.';

  @override
  String get developerIssuesDescriptionHelp =>
      'Describe the observed problem and the result you expected. Do not include secrets.';

  @override
  String get developerIssuesDescriptionRequired =>
      'Describe the product issue before saving.';

  @override
  String get developerIssuesCaptureAction => 'Save local report';

  @override
  String get developerIssuesCapturingAction => 'Saving…';

  @override
  String get developerIssuesSavedToast => 'Report saved on this device';

  @override
  String get developerIssuesSaveFailedToast =>
      'Couldn\'t save the report. Review the description and try again.';

  @override
  String get developerIssuesContextSection => 'Captured context';

  @override
  String get developerIssuesRouteLabel => 'Source route';

  @override
  String get developerIssuesDomainLabel => 'Domain';

  @override
  String get developerIssuesShellDomain => 'LifeOS shell';

  @override
  String get developerIssuesHistorySection => 'Local reports';

  @override
  String get developerIssuesEmpty => 'No reports saved on this device.';

  @override
  String get developerIssuesExportAction => 'Export';

  @override
  String get developerIssuesExportedLabel => 'Exported';

  @override
  String get developerIssuesLocalLabel => 'Local only';

  @override
  String get developerIssuesTraceAttached => 'Trace attached';

  @override
  String developerIssuesToolErrorsAttached(int count) {
    return '$count tool error codes';
  }

  @override
  String get developerIssuesExportFailedToast =>
      'Couldn\'t open the export sheet. Try again.';

  @override
  String get developerIssuesAdvancedTitle => 'Product issue reports';

  @override
  String get developerIssuesAdvancedSubtitle =>
      'Capture route, build, latest trace, and bounded tool error codes locally';
}
