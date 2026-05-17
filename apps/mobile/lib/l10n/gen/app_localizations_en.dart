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
  String get navHome => 'Overview';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navSettings => 'Settings';

  @override
  String get navActivity => 'Activity';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSearch => 'Search';

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
  String get commandPaletteOpenAi => 'Open AI assistant';

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
  String get authLoginSubmit => 'Sign in';

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
  String get rebalanceEmptyTitle => 'No data yet';

  @override
  String get rebalanceEmptyHint =>
      'Add assets to see your allocation drift and rebalance suggestions.';

  @override
  String get rebalanceSettingsTooltip => 'Rebalance settings';

  @override
  String get rebalanceSettingsTitle => 'Settings';

  @override
  String get rebalanceWarningThreshold => 'Warning threshold';

  @override
  String get rebalanceCriticalThreshold => 'Critical threshold';

  @override
  String get rebalanceNavLink => 'Rebalance';

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
  String get settingsRiskSection => 'Risk Preferences';

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
  String get tradeEntryDateLabel => 'Trade date';

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
  String get expenseFormDateLabel => 'Date';

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
  String get aiChatEmptyTitle => 'Your financial assistant';

  @override
  String get aiChatEmptyBody =>
      'Answers grounded in your holdings and ledger entries. Numbers come from your locally-synced ledger; the model never invents key figures.';

  @override
  String get aiChatEmptySuggestion1 =>
      'How much have I made in the last three months?';

  @override
  String get aiChatEmptySuggestion2 => 'Which holdings carry the highest risk?';

  @override
  String get aiChatEmptySuggestion3 =>
      'What does my industry breakdown look like?';

  @override
  String get aiChatEmptySuggestion4 => 'What\'s my XIRR since inception?';

  @override
  String get aiChatEmptySuggestionsHeader => 'Try these';

  @override
  String get aiChatBootstrappingLabel => 'Preparing conversation…';

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
      'Ask NaviWealth, e.g. \"How much did I earn last month?\"';

  @override
  String get aiChatComposerHintStreaming => 'Generating answer…';

  @override
  String get aiChatComposerHintFlushing => 'Syncing local data…';

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
  String get aiChatStaleSyncNotice =>
      'Local data hasn\'t finished syncing; answers may lag behind your most recent edits.';

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
  String get aiChatToolShowRawJson => 'View raw JSON';

  @override
  String get aiChatToolShowCompactView => 'Back to compact view';

  @override
  String get aiFloatingPillLabel => 'Ask AI';

  @override
  String get aiChatSheetTitle => 'AI assistant';

  @override
  String get aiChatSheetEmpty => 'Ask anything about your finances.';

  @override
  String get aiChatSheetExpandTooltip => 'Expand to full screen';

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
  String get cashFormDuplicateTitle => 'Cash already exists';

  @override
  String get cashFormDuplicateMessage =>
      'This account already has a cash balance recorded. Would you like to edit the existing one instead?';

  @override
  String get cashFormDuplicateCancel => 'Cancel';

  @override
  String get cashFormDuplicateEdit => 'Edit existing';

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
  String get settingsDataSection => 'Data';

  @override
  String get settingsDataTitle => 'Backup & Restore';

  @override
  String get settingsDataSubtitle => 'Export or import encrypted data backups';

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
  String get transferDateLabel => 'Date';

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
      'Paste CSV / statement text\ne.g. 2026-05-10,Starbucks,-38.00,CNY';

  @override
  String get ingestParseAction => 'Parse';

  @override
  String get ingestNoTransactions => 'No recognizable transactions';

  @override
  String ingestParseSummary(int total, int fresh, int dup) {
    return 'Parsed $total · $fresh new · $dup possible dup';
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
      'Paste statement / CSV text — it is parsed into drafts,\nreconciled, and confirmed here.';

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
  String aiTransparencyStaleCount(int count) {
    return 'Stale x$count';
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
  String get masterDetailBackToList => 'Back to list';
}
