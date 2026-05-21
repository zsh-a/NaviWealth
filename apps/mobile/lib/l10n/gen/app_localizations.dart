import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Application name shown in title bar and launchers
  ///
  /// In en, this message translates to:
  /// **'NaviWealth'**
  String get appTitle;

  /// Bottom nav: dashboard / overview tab
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navHome;

  /// Expense list label
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// Bottom nav: settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Bottom nav: activity tab (single timeline)
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// Bottom nav / More hub: accounts tab
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// Bottom nav action that opens the command palette on touch shells
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Cash-flow overview page title
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get cashFlowTitle;

  /// Command palette action that opens the cash-flow overview
  ///
  /// In en, this message translates to:
  /// **'Open cash flow'**
  String get cashFlowCommandOpen;

  /// Command palette entry that opens Activity filtered to income entries
  ///
  /// In en, this message translates to:
  /// **'View income'**
  String get cashFlowCommandViewIncome;

  /// Cash-flow period selector: monthly
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get cashFlowPeriodMonth;

  /// Cash-flow period selector: quarterly
  ///
  /// In en, this message translates to:
  /// **'Quarter'**
  String get cashFlowPeriodQuarter;

  /// Cash-flow period selector: yearly
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get cashFlowPeriodYear;

  /// Cash-flow KPI: incoming cash
  ///
  /// In en, this message translates to:
  /// **'Inflow'**
  String get cashFlowKpiInflow;

  /// Cash-flow KPI: outgoing cash
  ///
  /// In en, this message translates to:
  /// **'Outflow'**
  String get cashFlowKpiOutflow;

  /// Cash-flow KPI: net cash flow
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get cashFlowKpiNet;

  /// Cash-flow bar chart title
  ///
  /// In en, this message translates to:
  /// **'Income vs expense'**
  String get cashFlowIncomeExpenseTitle;

  /// Cash-flow trend chart title
  ///
  /// In en, this message translates to:
  /// **'Net cash-flow trend'**
  String get cashFlowNetTrendTitle;

  /// Cash-flow category pie chart title
  ///
  /// In en, this message translates to:
  /// **'Category mix'**
  String get cashFlowCategoryTitle;

  /// Cash-flow page link into the Dividend Center
  ///
  /// In en, this message translates to:
  /// **'View dividend center'**
  String get cashFlowViewDividendCenter;

  /// Cash-flow page empty-state title
  ///
  /// In en, this message translates to:
  /// **'No cash flow yet'**
  String get cashFlowEmptyTitle;

  /// Cash-flow page empty-state body
  ///
  /// In en, this message translates to:
  /// **'Income and expenses appear here once you record transactions.'**
  String get cashFlowEmptyBody;

  /// Cash-flow page error state
  ///
  /// In en, this message translates to:
  /// **'Cash flow failed to load: {error}'**
  String cashFlowLoadError(String error);

  /// Recurring transactions list page title
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get recurringListTitle;

  /// Command palette entry to open recurring transactions
  ///
  /// In en, this message translates to:
  /// **'Recurring transactions'**
  String get recurringCommandOpen;

  /// Chinese command-palette keyword for recurring; present in every locale
  ///
  /// In en, this message translates to:
  /// **'周期'**
  String get commandKeywordRecurringCn;

  /// Recurring list error state
  ///
  /// In en, this message translates to:
  /// **'Recurring rules failed to load: {error}'**
  String recurringLoadError(String error);

  /// Recurring list empty-state title
  ///
  /// In en, this message translates to:
  /// **'No recurring rules'**
  String get recurringEmptyTitle;

  /// Recurring list empty-state body
  ///
  /// In en, this message translates to:
  /// **'Set up rules for salary, subscriptions or other repeating cash flow.'**
  String get recurringEmptyBody;

  /// Recurring list empty-state CTA
  ///
  /// In en, this message translates to:
  /// **'Add recurring rule'**
  String get recurringEmptyCta;

  /// Recurring row next-due label
  ///
  /// In en, this message translates to:
  /// **'Next: {date}'**
  String recurringNextDue(String date);

  /// Shown when a recurring template cannot be decoded
  ///
  /// In en, this message translates to:
  /// **'Template unreadable'**
  String get recurringTemplateCorrupt;

  /// Recurring row action sheet title
  ///
  /// In en, this message translates to:
  /// **'Recurring rule'**
  String get recurringRowActionsTitle;

  /// Recurring row action: edit
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get recurringActionEdit;

  /// Subtitle for edit action
  ///
  /// In en, this message translates to:
  /// **'Change amount or schedule'**
  String get recurringActionEditHint;

  /// Recurring row action: disable
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get recurringActionDisable;

  /// Subtitle for disable action
  ///
  /// In en, this message translates to:
  /// **'Stop generating new entries'**
  String get recurringActionDisableHint;

  /// Subtitle for delete action
  ///
  /// In en, this message translates to:
  /// **'Remove this rule permanently'**
  String get recurringActionDeleteHint;

  /// Disable confirm title
  ///
  /// In en, this message translates to:
  /// **'Disable rule?'**
  String get recurringDisableTitle;

  /// Disable confirm body
  ///
  /// In en, this message translates to:
  /// **'It will stop creating new entries. You can recreate it later.'**
  String get recurringDisableBody;

  /// Delete confirm title
  ///
  /// In en, this message translates to:
  /// **'Delete rule?'**
  String get recurringDeleteTitle;

  /// Delete confirm body
  ///
  /// In en, this message translates to:
  /// **'This recurring rule will be removed. This cannot be undone.'**
  String get recurringDeleteBody;

  /// Toast after disabling a rule
  ///
  /// In en, this message translates to:
  /// **'Rule disabled'**
  String get recurringDisabled;

  /// Toast after deleting a rule
  ///
  /// In en, this message translates to:
  /// **'Rule deleted'**
  String get recurringDeleted;

  /// Toast when a recurring action fails
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get recurringActionFailed;

  /// Recurrence summary: daily
  ///
  /// In en, this message translates to:
  /// **'Every {n} day(s)'**
  String recurringEveryDay(int n);

  /// Recurrence summary: weekly
  ///
  /// In en, this message translates to:
  /// **'Every {n} week(s)'**
  String recurringEveryWeek(int n);

  /// Recurrence summary: monthly
  ///
  /// In en, this message translates to:
  /// **'Every {n} month(s)'**
  String recurringEveryMonth(int n);

  /// Recurrence summary: yearly
  ///
  /// In en, this message translates to:
  /// **'Every {n} year(s)'**
  String recurringEveryYear(int n);

  /// Recurrence summary: day of month
  ///
  /// In en, this message translates to:
  /// **'on day {day}'**
  String recurringByMonthDay(int day);

  /// Recurrence summary: end date
  ///
  /// In en, this message translates to:
  /// **'until {date}'**
  String recurringUntil(String date);

  /// Recurring form title (create)
  ///
  /// In en, this message translates to:
  /// **'New recurring rule'**
  String get recurringFormNewTitle;

  /// Recurring form title (edit)
  ///
  /// In en, this message translates to:
  /// **'Edit recurring rule'**
  String get recurringFormEditTitle;

  /// Recurring form subtitle
  ///
  /// In en, this message translates to:
  /// **'Generates a journal entry on each occurrence'**
  String get recurringFormSubtitle;

  /// Recurring form submit label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get recurringFormSave;

  /// Recurring form: income/expense selector label
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get recurringFieldKind;

  /// Recurring kind: income
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get recurringKindIncome;

  /// Recurring kind: expense
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get recurringKindExpense;

  /// Recurring form amount field
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get recurringFieldAmount;

  /// Recurring form cash account picker
  ///
  /// In en, this message translates to:
  /// **'Cash account'**
  String get recurringFieldCashAccount;

  /// Recurring form counter account picker
  ///
  /// In en, this message translates to:
  /// **'Category account'**
  String get recurringFieldCategoryAccount;

  /// Recurring form narration field
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get recurringFieldNote;

  /// Recurring form first-occurrence date
  ///
  /// In en, this message translates to:
  /// **'Starts on'**
  String get recurringFieldStart;

  /// Recurring form frequency selector
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get recurringFieldFrequency;

  /// Frequency option: daily
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get recurringFreqDaily;

  /// Frequency option: weekly
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get recurringFreqWeekly;

  /// Frequency option: monthly
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get recurringFreqMonthly;

  /// Frequency option: yearly
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get recurringFreqYearly;

  /// Recurring form interval field
  ///
  /// In en, this message translates to:
  /// **'Every N periods'**
  String get recurringFieldInterval;

  /// Recurring form day-of-month field
  ///
  /// In en, this message translates to:
  /// **'Day of month'**
  String get recurringFieldByMonthDay;

  /// Day-of-month helper
  ///
  /// In en, this message translates to:
  /// **'Optional, 1–31'**
  String get recurringFieldByMonthDayHelper;

  /// Recurring form end-date field
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get recurringFieldUntil;

  /// End-date helper
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get recurringFieldUntilHelper;

  /// Recurring validation: required field
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get recurringValidationRequired;

  /// Recurring validation: positive amount
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than 0'**
  String get recurringValidationPositive;

  /// Recurring validation: interval
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number'**
  String get recurringValidationInterval;

  /// Recurring validation: day of month
  ///
  /// In en, this message translates to:
  /// **'Day must be 1–31'**
  String get recurringValidationByMonthDay;

  /// Recurring validation: accounts required
  ///
  /// In en, this message translates to:
  /// **'Pick both accounts'**
  String get recurringValidationAccounts;

  /// Recurring validation: distinct accounts
  ///
  /// In en, this message translates to:
  /// **'Cash and category accounts must differ'**
  String get recurringValidationSameAccount;

  /// Recurring validation: currency required
  ///
  /// In en, this message translates to:
  /// **'Pick a currency'**
  String get recurringValidationCurrency;

  /// Default narration when note is blank
  ///
  /// In en, this message translates to:
  /// **'Recurring transaction'**
  String get recurringDefaultNarration;

  /// Toast when saving a recurring rule fails
  ///
  /// In en, this message translates to:
  /// **'Could not save the rule'**
  String get recurringSaveFailed;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get cashFlowKindSalary;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Dividend'**
  String get cashFlowKindDividend;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get cashFlowKindInterest;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Capital gains'**
  String get cashFlowKindCapitalGains;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get cashFlowKindOtherIncome;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get cashFlowKindExpense;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get cashFlowKindTransfer;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get cashFlowKindOpening;

  /// Cash-flow category label
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cashFlowKindOther;

  /// Dividend center page and command palette title
  ///
  /// In en, this message translates to:
  /// **'Dividend Center'**
  String get dividendCenterTitle;

  /// Dividend center KPI label: current year-to-date gross dividends
  ///
  /// In en, this message translates to:
  /// **'Year to date'**
  String get dividendCenterMetricYtd;

  /// Dividend center KPI label: trailing twelve month gross dividends
  ///
  /// In en, this message translates to:
  /// **'Trailing 12 months'**
  String get dividendCenterMetricTtm;

  /// Dividend center KPI label: year-over-year comparison for the same period
  ///
  /// In en, this message translates to:
  /// **'YoY same period'**
  String get dividendCenterMetricYoy;

  /// Dividend center KPI label: withholding tax total
  ///
  /// In en, this message translates to:
  /// **'Withholding tax'**
  String get dividendCenterMetricWithholding;

  /// Dividend center section title for ranked holdings
  ///
  /// In en, this message translates to:
  /// **'Holding ranking'**
  String get dividendCenterHoldingRanking;

  /// Dividend center section title for dividend history
  ///
  /// In en, this message translates to:
  /// **'History timeline'**
  String get dividendCenterHistoryTimeline;

  /// Dividend center forecast placeholder title
  ///
  /// In en, this message translates to:
  /// **'Next 12 months'**
  String get dividendCenterForecastTitle;

  /// Dividend center forecast placeholder body
  ///
  /// In en, this message translates to:
  /// **'Forecasting is not enabled yet.'**
  String get dividendCenterForecastUnavailable;

  /// Dividend center forecast source label
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String dividendCenterForecastSource(String source);

  /// Dividend center empty-state title
  ///
  /// In en, this message translates to:
  /// **'No dividend records yet'**
  String get dividendCenterEmptyTitle;

  /// Dividend center empty-state body
  ///
  /// In en, this message translates to:
  /// **'Record a cash dividend or corporate action to start the timeline.'**
  String get dividendCenterEmptyBody;

  /// Dividend center empty-state CTA
  ///
  /// In en, this message translates to:
  /// **'Record dividend'**
  String get dividendCenterRecordAction;

  /// Dividend center error state
  ///
  /// In en, this message translates to:
  /// **'Dividend center failed to load: {error}'**
  String dividendCenterLoadError(String error);

  /// Title of the dividend timeline row action sheet
  ///
  /// In en, this message translates to:
  /// **'Dividend entry'**
  String get dividendEventActionsTitle;

  /// Dividend row action: open the journal entry detail
  ///
  /// In en, this message translates to:
  /// **'View in activity'**
  String get dividendEventViewInActivity;

  /// Subtitle for view-in-activity action
  ///
  /// In en, this message translates to:
  /// **'Open the underlying journal entry'**
  String get dividendEventViewInActivityHint;

  /// Dividend row action: re-record via corporate action form
  ///
  /// In en, this message translates to:
  /// **'Edit (re-record)'**
  String get dividendEventEdit;

  /// Subtitle for the edit/re-record action
  ///
  /// In en, this message translates to:
  /// **'Record a corrected corporate action'**
  String get dividendEventEditHint;

  /// Subtitle for the delete action
  ///
  /// In en, this message translates to:
  /// **'Remove this dividend entry'**
  String get dividendEventDeleteHint;

  /// Confirm dialog title for deleting a dividend entry
  ///
  /// In en, this message translates to:
  /// **'Delete dividend?'**
  String get dividendEventDeleteTitle;

  /// Confirm dialog body for deleting a dividend entry
  ///
  /// In en, this message translates to:
  /// **'Delete the dividend for {asset}? This cannot be undone.'**
  String dividendEventDeleteBody(String asset);

  /// Toast after a dividend entry is deleted
  ///
  /// In en, this message translates to:
  /// **'Dividend deleted'**
  String get dividendEventDeleted;

  /// Toast when dividend deletion fails
  ///
  /// In en, this message translates to:
  /// **'Could not delete the dividend'**
  String get dividendEventDeleteFailed;

  /// Toast when the journal entry cannot be loaded
  ///
  /// In en, this message translates to:
  /// **'Could not open this entry'**
  String get dividendEventOpenFailed;

  /// Dividend forecast strategy label: declared corporate actions
  ///
  /// In en, this message translates to:
  /// **'Declared'**
  String get dividendForecastStrategyDeclared;

  /// Dividend forecast strategy label: annualized dividend per share extrapolation
  ///
  /// In en, this message translates to:
  /// **'DPS'**
  String get dividendForecastStrategyDps;

  /// Dividend forecast strategy label: trailing twelve months
  ///
  /// In en, this message translates to:
  /// **'TTM'**
  String get dividendForecastStrategyTtm;

  /// Dividend forecast strategy label: multiple strategies combined
  ///
  /// In en, this message translates to:
  /// **'Composite'**
  String get dividendForecastStrategyComposite;

  /// Fallback dividend forecast strategy label
  ///
  /// In en, this message translates to:
  /// **'Forecast'**
  String get dividendForecastStrategyUnknown;

  /// Short fallback label when a metric is not available
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get commonNotAvailable;

  /// Chinese command-palette search keyword for cash flow; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'现金流'**
  String get commandKeywordCashFlowCn;

  /// Chinese command-palette search keyword for income; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'收入'**
  String get commandKeywordIncomeCn;

  /// Chinese command-palette search keyword for dividends; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'股息'**
  String get commandKeywordDividendCn;

  /// Chinese command-palette search keyword for salary; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'工资'**
  String get commandKeywordSalaryCn;

  /// Chinese command-palette search keyword for the dividend center; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'股息中心'**
  String get commandKeywordDividendCenterCn;

  /// Chinese command-palette search keyword for a user's dividends; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'我的股息'**
  String get commandKeywordMyDividendsCn;

  /// Chinese command-palette search keyword for passive income; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'被动收入'**
  String get commandKeywordPassiveIncomeCn;

  /// Chinese command-palette search keyword for dividend distributions; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'分红'**
  String get commandKeywordBonusDividendCn;

  /// Chinese command-palette search keyword for withholding tax; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'代扣税'**
  String get commandKeywordWithholdingTaxCn;

  /// Chinese command-palette search keyword for corporate actions; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'公司行动'**
  String get commandKeywordCorporateActionCn;

  /// Chinese command-palette search keyword for stock splits; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'拆股'**
  String get commandKeywordSplitCn;

  /// Chinese command-palette search keyword for rights issues; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'配股'**
  String get commandKeywordRightsIssueCn;

  /// Chinese command-palette search keyword for rebalance; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'再平衡'**
  String get commandKeywordRebalanceCn;

  /// Chinese command-palette search keyword for target allocation; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'目标配置'**
  String get commandKeywordTargetAllocationCn;

  /// Accounts hub section header for cash + deposit + bonds & funds
  ///
  /// In en, this message translates to:
  /// **'Cash & Deposits'**
  String get accountsHubSectionCashDeposits;

  /// Accounts hub section header for stocks / ETFs / crypto
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get accountsHubSectionInvestments;

  /// Accounts hub section header for real estate / vehicles
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get accountsHubSectionPhysical;

  /// Accounts hub section header for debts / mortgages / loans
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get accountsHubSectionLiabilities;

  /// Accounts hub link row that opens the bank-accounts list
  ///
  /// In en, this message translates to:
  /// **'Manage bank accounts'**
  String get accountsHubManageBankAccounts;

  /// Investment portfolio hub page title
  ///
  /// In en, this message translates to:
  /// **'Portfolio'**
  String get portfolioHubTitle;

  /// Accounts hub link subtitle for the investment portfolio hub
  ///
  /// In en, this message translates to:
  /// **'Holdings, returns, and allocation views'**
  String get portfolioHubAccountsEntrySubtitle;

  /// Portfolio hub KPI label: current portfolio market value
  ///
  /// In en, this message translates to:
  /// **'Market value'**
  String get portfolioHubMarketValueLabel;

  /// Portfolio hub KPI label: year-to-date money-weighted return
  ///
  /// In en, this message translates to:
  /// **'YTD XIRR'**
  String get portfolioHubYtdXirrLabel;

  /// Portfolio hub KPI label: absolute unrealized return
  ///
  /// In en, this message translates to:
  /// **'Absolute return'**
  String get portfolioHubAbsoluteReturnLabel;

  /// Portfolio hub grouping view: account
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get portfolioHubViewAccount;

  /// Portfolio hub grouping view: currency
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get portfolioHubViewCurrency;

  /// Portfolio hub grouping view: asset class
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get portfolioHubViewAssetClass;

  /// Portfolio hub grouped holdings section title
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get portfolioHubHoldingsTitle;

  /// Portfolio hub individual holdings section title
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get portfolioHubPositionsTitle;

  /// Portfolio hub group row holding count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 holding} other{{count} holdings}}'**
  String portfolioHubHoldingCount(int count);

  /// Portfolio hub account group fallback title
  ///
  /// In en, this message translates to:
  /// **'Unknown account'**
  String get portfolioHubUnknownAccount;

  /// Portfolio hub account group default subtitle
  ///
  /// In en, this message translates to:
  /// **'Brokerage account'**
  String get portfolioHubAccountGroupSubtitle;

  /// Portfolio hub currency group subtitle
  ///
  /// In en, this message translates to:
  /// **'Settlement currency'**
  String get portfolioHubCurrencyGroupSubtitle;

  /// Portfolio hub asset class group subtitle
  ///
  /// In en, this message translates to:
  /// **'Asset class'**
  String get portfolioHubAssetClassGroupSubtitle;

  /// Portfolio hub empty state
  ///
  /// In en, this message translates to:
  /// **'No investment holdings yet.'**
  String get portfolioHubEmpty;

  /// Portfolio hub load error state
  ///
  /// In en, this message translates to:
  /// **'Portfolio failed to load: {error}'**
  String portfolioHubLoadError(String error);

  /// Portfolio hub asset type label: stock
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get portfolioHubAssetTypeStock;

  /// Portfolio hub asset type label: ETF
  ///
  /// In en, this message translates to:
  /// **'ETF'**
  String get portfolioHubAssetTypeEtf;

  /// Portfolio hub asset type label: mutual fund
  ///
  /// In en, this message translates to:
  /// **'Mutual fund'**
  String get portfolioHubAssetTypeMutualFund;

  /// Portfolio hub asset type label: bond
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get portfolioHubAssetTypeBond;

  /// Portfolio hub asset type label: crypto
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get portfolioHubAssetTypeCrypto;

  /// Portfolio hub asset type label: cash
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get portfolioHubAssetTypeCash;

  /// Portfolio hub asset type label: commodity
  ///
  /// In en, this message translates to:
  /// **'Commodity'**
  String get portfolioHubAssetTypeCommodity;

  /// Portfolio hub asset type label: custom asset
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get portfolioHubAssetTypeCustom;

  /// Portfolio hub asset type label: term deposit
  ///
  /// In en, this message translates to:
  /// **'Term deposit'**
  String get portfolioHubAssetTypeBankDepositTerm;

  /// Portfolio hub asset type label: demand deposit
  ///
  /// In en, this message translates to:
  /// **'Demand deposit'**
  String get portfolioHubAssetTypeBankDepositDemand;

  /// Portfolio hub asset type label: wealth product
  ///
  /// In en, this message translates to:
  /// **'Wealth product'**
  String get portfolioHubAssetTypeWealthProduct;

  /// No description provided for @portfolioHubEnginesTitle.
  ///
  /// In en, this message translates to:
  /// **'Engine views'**
  String get portfolioHubEnginesTitle;

  /// No description provided for @portfolioHubRealizedPnlTitle.
  ///
  /// In en, this message translates to:
  /// **'Realized P/L'**
  String get portfolioHubRealizedPnlTitle;

  /// No description provided for @portfolioHubRealizedPnlCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lot} other{{count} lots}}'**
  String portfolioHubRealizedPnlCount(int count);

  /// No description provided for @portfolioHubRealizedPnlEmpty.
  ///
  /// In en, this message translates to:
  /// **'No closed lots yet.'**
  String get portfolioHubRealizedPnlEmpty;

  /// No description provided for @portfolioHubHoldingPeriod.
  ///
  /// In en, this message translates to:
  /// **'Held {period}'**
  String portfolioHubHoldingPeriod(String period);

  /// No description provided for @portfolioHubHoldingYears.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 year} other{{count} years}}'**
  String portfolioHubHoldingYears(int count);

  /// No description provided for @portfolioHubHoldingMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String portfolioHubHoldingMonths(int count);

  /// No description provided for @portfolioHubHoldingDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String portfolioHubHoldingDays(int count);

  /// No description provided for @portfolioHubDividendForecastTitle.
  ///
  /// In en, this message translates to:
  /// **'Dividend forecast'**
  String get portfolioHubDividendForecastTitle;

  /// No description provided for @portfolioHubDividendForecastEmpty.
  ///
  /// In en, this message translates to:
  /// **'No projected dividends yet.'**
  String get portfolioHubDividendForecastEmpty;

  /// No description provided for @portfolioHubDividendForecastEvent.
  ///
  /// In en, this message translates to:
  /// **'Projected payout'**
  String get portfolioHubDividendForecastEvent;

  /// No description provided for @portfolioHubForecastConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High confidence'**
  String get portfolioHubForecastConfidenceHigh;

  /// No description provided for @portfolioHubForecastConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium confidence'**
  String get portfolioHubForecastConfidenceMedium;

  /// No description provided for @portfolioHubForecastConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low confidence'**
  String get portfolioHubForecastConfidenceLow;

  /// No description provided for @portfolioHubEventTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Event timeline'**
  String get portfolioHubEventTimelineTitle;

  /// No description provided for @portfolioHubEventTimelineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event} other{{count} events}}'**
  String portfolioHubEventTimelineCount(int count);

  /// No description provided for @portfolioHubEventTimelineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No dividend or corporate-action events yet.'**
  String get portfolioHubEventTimelineEmpty;

  /// No description provided for @dcaSimulatorTitle.
  ///
  /// In en, this message translates to:
  /// **'DCA simulator'**
  String get dcaSimulatorTitle;

  /// No description provided for @dcaSimulatorAccountsEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Backtest recurring buys with cached monthly prices'**
  String get dcaSimulatorAccountsEntrySubtitle;

  /// No description provided for @dcaSimulatorSymbolField.
  ///
  /// In en, this message translates to:
  /// **'Symbol or basket'**
  String get dcaSimulatorSymbolField;

  /// No description provided for @dcaSimulatorSymbolHint.
  ///
  /// In en, this message translates to:
  /// **'VOO or VOO, QQQ'**
  String get dcaSimulatorSymbolHint;

  /// No description provided for @dcaSimulatorAmountField.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get dcaSimulatorAmountField;

  /// No description provided for @dcaSimulatorCurrencyField.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get dcaSimulatorCurrencyField;

  /// No description provided for @dcaSimulatorMarketField.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get dcaSimulatorMarketField;

  /// No description provided for @dcaSimulatorMarketUs.
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get dcaSimulatorMarketUs;

  /// No description provided for @dcaSimulatorMarketHk.
  ///
  /// In en, this message translates to:
  /// **'Hong Kong'**
  String get dcaSimulatorMarketHk;

  /// No description provided for @dcaSimulatorMarketCn.
  ///
  /// In en, this message translates to:
  /// **'China A'**
  String get dcaSimulatorMarketCn;

  /// No description provided for @dcaSimulatorMarketCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get dcaSimulatorMarketCrypto;

  /// No description provided for @dcaSimulatorFrequencyField.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get dcaSimulatorFrequencyField;

  /// No description provided for @dcaSimulatorFrequencyMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get dcaSimulatorFrequencyMonthly;

  /// No description provided for @dcaSimulatorFrequencyQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get dcaSimulatorFrequencyQuarterly;

  /// No description provided for @dcaSimulatorWindowField.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get dcaSimulatorWindowField;

  /// No description provided for @dcaSimulatorWindow1y.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get dcaSimulatorWindow1y;

  /// No description provided for @dcaSimulatorWindow3y.
  ///
  /// In en, this message translates to:
  /// **'3 years'**
  String get dcaSimulatorWindow3y;

  /// No description provided for @dcaSimulatorWindow5y.
  ///
  /// In en, this message translates to:
  /// **'5 years'**
  String get dcaSimulatorWindow5y;

  /// No description provided for @dcaSimulatorRunAction.
  ///
  /// In en, this message translates to:
  /// **'Run simulation'**
  String get dcaSimulatorRunAction;

  /// No description provided for @dcaSimulatorDraftAction.
  ///
  /// In en, this message translates to:
  /// **'Draft next buys'**
  String get dcaSimulatorDraftAction;

  /// No description provided for @dcaSimulatorFreshnessLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get dcaSimulatorFreshnessLive;

  /// No description provided for @dcaSimulatorFreshnessCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get dcaSimulatorFreshnessCache;

  /// No description provided for @dcaSimulatorFreshnessStale.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get dcaSimulatorFreshnessStale;

  /// No description provided for @dcaSimulatorResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Backtest result'**
  String get dcaSimulatorResultTitle;

  /// No description provided for @dcaSimulatorTotalInvested.
  ///
  /// In en, this message translates to:
  /// **'Invested'**
  String get dcaSimulatorTotalInvested;

  /// No description provided for @dcaSimulatorEndingValue.
  ///
  /// In en, this message translates to:
  /// **'Ending value'**
  String get dcaSimulatorEndingValue;

  /// No description provided for @dcaSimulatorCumulativeReturn.
  ///
  /// In en, this message translates to:
  /// **'Total return'**
  String get dcaSimulatorCumulativeReturn;

  /// No description provided for @dcaSimulatorAverageCost.
  ///
  /// In en, this message translates to:
  /// **'Avg cost'**
  String get dcaSimulatorAverageCost;

  /// No description provided for @dcaSimulatorMaxDrawdown.
  ///
  /// In en, this message translates to:
  /// **'Max drawdown'**
  String get dcaSimulatorMaxDrawdown;

  /// No description provided for @dcaSimulatorChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio value'**
  String get dcaSimulatorChartTitle;

  /// No description provided for @dcaSimulatorChartSeries.
  ///
  /// In en, this message translates to:
  /// **'DCA value'**
  String get dcaSimulatorChartSeries;

  /// No description provided for @dcaSimulatorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No monthly market data matched this window.'**
  String get dcaSimulatorEmpty;

  /// No description provided for @dcaSimulatorInvalidSymbols.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one symbol.'**
  String get dcaSimulatorInvalidSymbols;

  /// No description provided for @dcaSimulatorInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive amount.'**
  String get dcaSimulatorInvalidAmount;

  /// No description provided for @dcaSimulatorInvalidCurrency.
  ///
  /// In en, this message translates to:
  /// **'Use a currency code.'**
  String get dcaSimulatorInvalidCurrency;

  /// No description provided for @dcaSimulatorLoadError.
  ///
  /// In en, this message translates to:
  /// **'DCA simulation failed: {error}'**
  String dcaSimulatorLoadError(String error);

  /// No description provided for @dcaSimulatorDraftNote.
  ///
  /// In en, this message translates to:
  /// **'DCA plan: buy {symbol} for {amount} {currency}'**
  String dcaSimulatorDraftNote(String symbol, String amount, String currency);

  /// No description provided for @dcaSimulatorPositionAverageCost.
  ///
  /// In en, this message translates to:
  /// **'{currency} {averageCost} avg cost'**
  String dcaSimulatorPositionAverageCost(String currency, String averageCost);

  /// No description provided for @assetDetailFxPnlTitle.
  ///
  /// In en, this message translates to:
  /// **'Price vs FX contribution'**
  String get assetDetailFxPnlTitle;

  /// No description provided for @assetDetailFxPnlMarketLeg.
  ///
  /// In en, this message translates to:
  /// **'Price movement'**
  String get assetDetailFxPnlMarketLeg;

  /// No description provided for @assetDetailFxPnlCurrencyLeg.
  ///
  /// In en, this message translates to:
  /// **'FX movement'**
  String get assetDetailFxPnlCurrencyLeg;

  /// No description provided for @assetDetailFxPnlTotal.
  ///
  /// In en, this message translates to:
  /// **'Total base P/L'**
  String get assetDetailFxPnlTotal;

  /// No description provided for @assetDetailFxPnlLoadError.
  ///
  /// In en, this message translates to:
  /// **'FX P/L failed to load: {error}'**
  String assetDetailFxPnlLoadError(String error);

  /// Section header above the home AI Insight Feed
  ///
  /// In en, this message translates to:
  /// **'Insights for you'**
  String get dashboardAiInsightsTitle;

  /// Section header above the home recent-activity timeline preview
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get dashboardActivityPreviewTitle;

  /// Link at the bottom of the home recent-activity preview
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get dashboardActivityPreviewViewAll;

  /// Section header above the home compact allocation summary
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get dashboardAllocationSummaryTitle;

  /// Link from the home allocation summary into the Accounts hub
  ///
  /// In en, this message translates to:
  /// **'View breakdown'**
  String get dashboardAllocationViewBreakdown;

  /// Home page greeting hero — 5:00 to 12:00
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGreetingMorning;

  /// Home page greeting hero — 12:00 to 18:00
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGreetingAfternoon;

  /// Home page greeting hero — 18:00 to 24:00
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGreetingEvening;

  /// Home page greeting hero — 0:00 to 5:00
  ///
  /// In en, this message translates to:
  /// **'Good night'**
  String get homeGreetingNight;

  /// Status line fragment under the home greeting describing month-to-date net worth direction
  ///
  /// In en, this message translates to:
  /// **'Net worth {pct} this month'**
  String homeGreetingNetWorthFragment(String pct);

  /// Status line fragment under the home greeting describing pending AI insights
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 insight available} other{{count} insights available}}'**
  String homeGreetingInsightsFragment(int count);

  /// Activity timeline filter chip: clear all kind filters
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get activityFilterChipAll;

  /// Activity timeline filter chip: income
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get activityFilterChipIncome;

  /// Activity timeline filter chip: expense
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get activityFilterChipExpense;

  /// Activity timeline filter chip: transfer
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get activityFilterChipTransfer;

  /// Activity timeline filter chip: trade
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get activityFilterChipTrade;

  /// Title of the activity entry detail page
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get activityEntryDetailTitle;

  /// Section header for the AI-generated explanation block in the activity entry detail page
  ///
  /// In en, this message translates to:
  /// **'AI insight'**
  String get activityEntryDetailAiExplanation;

  /// Empty state when no AI explanation is available
  ///
  /// In en, this message translates to:
  /// **'No insight available for this entry.'**
  String get activityEntryDetailNoExplanation;

  /// Heuristic AI insight shown for subscription-like transaction descriptions
  ///
  /// In en, this message translates to:
  /// **'Recurring subscription. Review whether it still fits your plan before the next renewal.'**
  String get activityEntryDetailInsightSubscription;

  /// Heuristic AI insight shown for rent or mortgage-like transaction descriptions
  ///
  /// In en, this message translates to:
  /// **'Recurring housing payment. Keep it in the essential-spending baseline.'**
  String get activityEntryDetailInsightHousing;

  /// Heuristic AI insight shown for salary or payroll-like transaction descriptions
  ///
  /// In en, this message translates to:
  /// **'Primary income inflow. Keep it stable in cash-flow projections.'**
  String get activityEntryDetailInsightIncome;

  /// AI context summary section eyebrow
  ///
  /// In en, this message translates to:
  /// **'Monthly summary'**
  String get aiContextSummaryThisMonth;

  /// AI summary line — month-to-date net worth direction. {pct} carries the sign and percent (e.g. "+2.3%").
  ///
  /// In en, this message translates to:
  /// **'Net worth {pct} this month'**
  String aiContextSummaryNetWorthLine(String pct);

  /// AI summary line — number of unusual expense events the assistant noticed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unusual expense flagged} other{{count} unusual expenses flagged}}'**
  String aiContextSummaryUnusualLine(int count);

  /// AI summary line — upcoming deposit maturities. {days} is the closest maturity horizon in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 deposit matures in {days}d} other{{count} deposits mature in {days}d}}'**
  String aiContextSummaryUpcomingLine(int count, int days);

  /// Section header for the AI action cards rail
  ///
  /// In en, this message translates to:
  /// **'Suggested actions'**
  String get aiActionCardsTitle;

  /// Affordance label on each action card to deep-link into the detail flow
  ///
  /// In en, this message translates to:
  /// **'Open →'**
  String get aiActionCardsOpen;

  /// Collapsible section title under the AI chat that links to FIRE / Rebalance / Analytics
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get aiInsightsPanelTitle;

  /// Insights panel link label for the Rebalance detail page
  ///
  /// In en, this message translates to:
  /// **'Rebalance'**
  String get aiInsightsRebalanceTitle;

  /// Title shown on the AI chat session more-actions sheet
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get aiChatSessionActionsTitle;

  /// Net-worth breakdown stat: assets total
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get dashboardNetWorthAssetsLabel;

  /// Net-worth breakdown stat: liabilities total
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get dashboardNetWorthLiabilitiesLabel;

  /// Home net-worth card status while market prices or FX rates are refreshing
  ///
  /// In en, this message translates to:
  /// **'Updating valuations…'**
  String get dashboardValuationUpdating;

  /// Home net-worth card status while cloud ledger sync is in flight
  ///
  /// In en, this message translates to:
  /// **'Syncing latest records…'**
  String get dashboardLedgerSyncing;

  /// Home net-worth card status shortly after valuation refresh finishes
  ///
  /// In en, this message translates to:
  /// **'Valuations updated just now'**
  String get dashboardValuationUpdated;

  /// Portfolio segmented control: assets sub-tab
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get portfolioAssetsTab;

  /// Portfolio segmented control: liabilities sub-tab
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get portfolioLiabilitiesTab;

  /// Title of the Activity-page '+' action sheet — only flow entries (expense/trade/transfer/convert)
  ///
  /// In en, this message translates to:
  /// **'Record activity'**
  String get activityActionsTitle;

  /// Affordance under Expense in the Activity actions sheet
  ///
  /// In en, this message translates to:
  /// **'Cash out for goods or services'**
  String get activityActionExpenseHint;

  /// Affordance under Trade in the Activity actions sheet
  ///
  /// In en, this message translates to:
  /// **'Buy or sell a security'**
  String get activityActionTradeHint;

  /// Affordance under Transfer in the Activity actions sheet
  ///
  /// In en, this message translates to:
  /// **'Move funds between two accounts'**
  String get activityActionTransferHint;

  /// Affordance under Convert in the Activity actions sheet
  ///
  /// In en, this message translates to:
  /// **'Exchange currency inside one account'**
  String get activityActionConvertHint;

  /// Title of the Accounts-page '+' action sheet — only structural creation (account/asset/liability)
  ///
  /// In en, this message translates to:
  /// **'Add wealth container'**
  String get accountsActionsTitle;

  /// Affordance under New account in the Accounts actions sheet
  ///
  /// In en, this message translates to:
  /// **'Bank, brokerage or crypto account'**
  String get accountsActionAccountHint;

  /// Affordance under New liability in the Accounts actions sheet
  ///
  /// In en, this message translates to:
  /// **'Mortgage, loan or credit balance'**
  String get accountsActionLiabilityHint;

  /// No description provided for @superFabTrade.
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get superFabTrade;

  /// No description provided for @superFabExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get superFabExpense;

  /// No description provided for @superFabAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get superFabAsset;

  /// No description provided for @superFabTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get superFabTransfer;

  /// Affordance under Transfer in the global action panel
  ///
  /// In en, this message translates to:
  /// **'Move funds between accounts'**
  String get superFabTransferSubtitle;

  /// Global action panel entry — exchange currency inside one container
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get superFabConvert;

  /// Affordance under Convert in the global action panel
  ///
  /// In en, this message translates to:
  /// **'Exchange currency inside one account'**
  String get superFabConvertSubtitle;

  /// No description provided for @superFabLiability.
  ///
  /// In en, this message translates to:
  /// **'Liability'**
  String get superFabLiability;

  /// Hint shown at the top of the Transfer form when the user enters via the Convert action
  ///
  /// In en, this message translates to:
  /// **'Converting inside a single account — pick the same account twice and choose two different currencies.'**
  String get transferConvertModeBanner;

  /// No description provided for @homeAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get homeAppBarTitle;

  /// Tooltip for the home AppBar action that opens the AI chat surface.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get homeAiAssistantTooltip;

  /// No description provided for @homeNetWorthTitle.
  ///
  /// In en, this message translates to:
  /// **'Net Worth'**
  String get homeNetWorthTitle;

  /// No description provided for @homeNetWorthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Base currency {currency} · shown once data is connected'**
  String homeNetWorthSubtitle(String currency);

  /// Home cashflow card title: trailing twelve month passive income
  ///
  /// In en, this message translates to:
  /// **'Passive income'**
  String get homePassiveIncomeTitle;

  /// Home passive income card subtitle when data exists
  ///
  /// In en, this message translates to:
  /// **'TTM dividends, interest, and other passive income'**
  String get homePassiveIncomeSubtitle;

  /// Home passive income card subtitle when the next-month forecast is available
  ///
  /// In en, this message translates to:
  /// **'TTM passive income · next month est. {amount}'**
  String homePassiveIncomeSubtitleWithNextMonth(String amount);

  /// Home passive income card empty-state guidance
  ///
  /// In en, this message translates to:
  /// **'Record dividends or interest to start TTM tracking'**
  String get homePassiveIncomeEmpty;

  /// Home passive income card badge when no prior TTM window exists
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get homePassiveIncomeDeltaNew;

  /// Home monthly cashflow card title
  ///
  /// In en, this message translates to:
  /// **'This month cashflow'**
  String get homeMonthlyCashFlowTitle;

  /// Home monthly cashflow card inflow and outflow line
  ///
  /// In en, this message translates to:
  /// **'In {inflow} · Out {outflow}'**
  String homeMonthlyCashFlowSubtitle(String inflow, String outflow);

  /// Home monthly cashflow card empty-state guidance
  ///
  /// In en, this message translates to:
  /// **'Add income or spending entries to see this month'**
  String get homeMonthlyCashFlowEmpty;

  /// Home monthly cashflow card trailing baseline label
  ///
  /// In en, this message translates to:
  /// **'vs 3-month average {average}'**
  String homeMonthlyCashFlowBaseline(String average);

  /// Home monthly cashflow card baseline empty text
  ///
  /// In en, this message translates to:
  /// **'3-month average appears after entries post'**
  String get homeMonthlyCashFlowBaselineEmpty;

  /// Home cashflow cards empty amount text
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get homeCashFlowEmptyValue;

  /// Home cashflow card error message
  ///
  /// In en, this message translates to:
  /// **'Cashflow summary is unavailable'**
  String get homeCashFlowCardError;

  /// No description provided for @assetsAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assetsAppBarTitle;

  /// Master-detail empty state for portfolio at desktop width
  ///
  /// In en, this message translates to:
  /// **'Select an asset on the left to see its details.'**
  String get assetsDetailEmpty;

  /// No description provided for @assetsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No assets yet. Tap the button in the bottom right to add cash, deposits, wealth products, real estate, or vehicles.'**
  String get assetsEmptyHint;

  /// No description provided for @assetsAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add asset'**
  String get assetsAddAction;

  /// No description provided for @assetsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String assetsLoadError(String error);

  /// No description provided for @assetsAddCashTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash / multi-currency balance'**
  String get assetsAddCashTitle;

  /// No description provided for @assetsAddCashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track available balance in checking or cash accounts'**
  String get assetsAddCashSubtitle;

  /// No description provided for @assetsAddDepositTitle.
  ///
  /// In en, this message translates to:
  /// **'Deposit (term / demand)'**
  String get assetsAddDepositTitle;

  /// No description provided for @assetsAddDepositSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record interest rate, value date, and maturity'**
  String get assetsAddDepositSubtitle;

  /// No description provided for @assetsAddWealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Wealth product'**
  String get assetsAddWealthTitle;

  /// No description provided for @assetsAddWealthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maintain expected return and current valuation manually'**
  String get assetsAddWealthSubtitle;

  /// No description provided for @assetsAddRealEstateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Address, purchase price, current valuation; can link a mortgage'**
  String get assetsAddRealEstateSubtitle;

  /// No description provided for @assetsAddVehicleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase price, annual residual rate, automatic depreciation'**
  String get assetsAddVehicleSubtitle;

  /// No description provided for @assetsChipInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Rate {rate}%'**
  String assetsChipInterestRate(String rate);

  /// No description provided for @assetsChipExpectedReturn.
  ///
  /// In en, this message translates to:
  /// **'Expected {rate}%'**
  String assetsChipExpectedReturn(String rate);

  /// No description provided for @assetsChipMaturityDate.
  ///
  /// In en, this message translates to:
  /// **'Matures {date}'**
  String assetsChipMaturityDate(String date);

  /// No description provided for @assetTypeCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get assetTypeCash;

  /// No description provided for @assetTypeBankDepositTerm.
  ///
  /// In en, this message translates to:
  /// **'Term deposit'**
  String get assetTypeBankDepositTerm;

  /// No description provided for @assetTypeBankDepositDemand.
  ///
  /// In en, this message translates to:
  /// **'Demand deposit'**
  String get assetTypeBankDepositDemand;

  /// No description provided for @assetTypeWealthProduct.
  ///
  /// In en, this message translates to:
  /// **'Wealth product'**
  String get assetTypeWealthProduct;

  /// No description provided for @assetTypeStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get assetTypeStock;

  /// No description provided for @assetTypeEtf.
  ///
  /// In en, this message translates to:
  /// **'ETF'**
  String get assetTypeEtf;

  /// No description provided for @assetTypeMutualFund.
  ///
  /// In en, this message translates to:
  /// **'Mutual fund'**
  String get assetTypeMutualFund;

  /// No description provided for @assetTypeBond.
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get assetTypeBond;

  /// No description provided for @assetTypeCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get assetTypeCrypto;

  /// Compact quantity badge in the securities list — e.g. 'Qty 100'.
  ///
  /// In en, this message translates to:
  /// **'Qty {quantity}'**
  String securitiesHoldingQuantity(String quantity);

  /// Subtitle when the user has zero shares of a known securities asset.
  ///
  /// In en, this message translates to:
  /// **'Not held'**
  String get securitiesHoldingFlat;

  /// No description provided for @corpActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Corporate Action'**
  String get corpActionTitle;

  /// No description provided for @corpActionSelectAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get corpActionSelectAsset;

  /// No description provided for @corpActionSelectAssetHint.
  ///
  /// In en, this message translates to:
  /// **'Choose which holding the action applies to.'**
  String get corpActionSelectAssetHint;

  /// No description provided for @corpActionEventTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Event type'**
  String get corpActionEventTypeTitle;

  /// No description provided for @corpActionTypeCashDividend.
  ///
  /// In en, this message translates to:
  /// **'Cash dividend'**
  String get corpActionTypeCashDividend;

  /// No description provided for @corpActionTypeStockDividend.
  ///
  /// In en, this message translates to:
  /// **'Stock dividend'**
  String get corpActionTypeStockDividend;

  /// No description provided for @corpActionTypeSplit.
  ///
  /// In en, this message translates to:
  /// **'Split / reverse split'**
  String get corpActionTypeSplit;

  /// No description provided for @corpActionTypeRightsIssue.
  ///
  /// In en, this message translates to:
  /// **'Rights issue'**
  String get corpActionTypeRightsIssue;

  /// No description provided for @corpActionTypeDrip.
  ///
  /// In en, this message translates to:
  /// **'DRIP (reinvest)'**
  String get corpActionTypeDrip;

  /// No description provided for @corpActionEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get corpActionEffectiveDate;

  /// No description provided for @corpActionAmountPerShare.
  ///
  /// In en, this message translates to:
  /// **'Amount per share'**
  String get corpActionAmountPerShare;

  /// No description provided for @corpActionWithholdingTax.
  ///
  /// In en, this message translates to:
  /// **'Withholding tax (total)'**
  String get corpActionWithholdingTax;

  /// No description provided for @corpActionBonusRatio.
  ///
  /// In en, this message translates to:
  /// **'Bonus ratio (extra shares per held share)'**
  String get corpActionBonusRatio;

  /// No description provided for @corpActionSplitRatio.
  ///
  /// In en, this message translates to:
  /// **'Split ratio'**
  String get corpActionSplitRatio;

  /// No description provided for @corpActionSplitRatioHelp.
  ///
  /// In en, this message translates to:
  /// **'2 = 2-for-1 forward split · 0.1 = 1-for-10 reverse split'**
  String get corpActionSplitRatioHelp;

  /// No description provided for @corpActionSubscribedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Subscribed quantity'**
  String get corpActionSubscribedQuantity;

  /// No description provided for @corpActionPricePerUnit.
  ///
  /// In en, this message translates to:
  /// **'Price per share'**
  String get corpActionPricePerUnit;

  /// No description provided for @corpActionFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get corpActionFee;

  /// No description provided for @corpActionPreviewAction.
  ///
  /// In en, this message translates to:
  /// **'Preview impact'**
  String get corpActionPreviewAction;

  /// No description provided for @corpActionSubmitAction.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get corpActionSubmitAction;

  /// No description provided for @corpActionPreviewHeading.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get corpActionPreviewHeading;

  /// No description provided for @corpActionNoEligibleHolding.
  ///
  /// In en, this message translates to:
  /// **'No eligible holding for this asset and account on the effective date.'**
  String get corpActionNoEligibleHolding;

  /// No description provided for @corpActionPreviewSharesOnRecord.
  ///
  /// In en, this message translates to:
  /// **'Shares on record'**
  String get corpActionPreviewSharesOnRecord;

  /// No description provided for @corpActionPreviewGross.
  ///
  /// In en, this message translates to:
  /// **'Gross'**
  String get corpActionPreviewGross;

  /// No description provided for @corpActionPreviewTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get corpActionPreviewTax;

  /// No description provided for @corpActionPreviewNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get corpActionPreviewNet;

  /// No description provided for @corpActionPreviewCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get corpActionPreviewCashFlow;

  /// No description provided for @corpActionPreviewLotChange.
  ///
  /// In en, this message translates to:
  /// **'Lot {id}: {beforeQty} → {afterQty} @ {beforeCost} → {afterCost}'**
  String corpActionPreviewLotChange(
    String id,
    String beforeQty,
    String afterQty,
    String beforeCost,
    String afterCost,
  );

  /// No description provided for @corpActionPreviewNewLot.
  ///
  /// In en, this message translates to:
  /// **'New lot: {qty} @ {cost}'**
  String corpActionPreviewNewLot(String qty, String cost);

  /// No description provided for @corpActionSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Recorded.'**
  String get corpActionSubmitted;

  /// No description provided for @corpActionInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive number'**
  String get corpActionInvalidNumber;

  /// No description provided for @corpActionInvalidNumberNonNegative.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative number'**
  String get corpActionInvalidNumberNonNegative;

  /// Tile on the Assets page that opens the liabilities subscreen
  ///
  /// In en, this message translates to:
  /// **'Liabilities & repayment plans'**
  String get assetsLiabilitiesLink;

  /// No description provided for @liabilitiesAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get liabilitiesAppBarTitle;

  /// No description provided for @liabilitiesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No liabilities yet. Add a mortgage, car loan, credit card or consumer loan to track repayment.'**
  String get liabilitiesEmptyHint;

  /// No description provided for @liabilitiesAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add liability'**
  String get liabilitiesAddAction;

  /// No description provided for @liabilityTypeMortgage.
  ///
  /// In en, this message translates to:
  /// **'Mortgage'**
  String get liabilityTypeMortgage;

  /// No description provided for @liabilityTypeCarLoan.
  ///
  /// In en, this message translates to:
  /// **'Car loan'**
  String get liabilityTypeCarLoan;

  /// No description provided for @liabilityTypeCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit card'**
  String get liabilityTypeCreditCard;

  /// No description provided for @liabilityTypeConsumerLoan.
  ///
  /// In en, this message translates to:
  /// **'Consumer loan'**
  String get liabilityTypeConsumerLoan;

  /// No description provided for @liabilityTypeStudentLoan.
  ///
  /// In en, this message translates to:
  /// **'Student loan'**
  String get liabilityTypeStudentLoan;

  /// No description provided for @liabilityTypeMarginLoan.
  ///
  /// In en, this message translates to:
  /// **'Margin loan'**
  String get liabilityTypeMarginLoan;

  /// No description provided for @liabilityTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get liabilityTypeOther;

  /// No description provided for @liabilityRateTypeFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed rate'**
  String get liabilityRateTypeFixed;

  /// No description provided for @liabilityRateTypeLpr.
  ///
  /// In en, this message translates to:
  /// **'LPR floating'**
  String get liabilityRateTypeLpr;

  /// No description provided for @liabilityMethodEqualInstallment.
  ///
  /// In en, this message translates to:
  /// **'Equal installment'**
  String get liabilityMethodEqualInstallment;

  /// No description provided for @liabilityMethodEqualPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Equal principal'**
  String get liabilityMethodEqualPrincipal;

  /// No description provided for @liabilityFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get liabilityFieldName;

  /// No description provided for @liabilityFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get liabilityFieldType;

  /// No description provided for @liabilityFieldPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get liabilityFieldPrincipal;

  /// No description provided for @liabilityFieldInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Annual rate (%)'**
  String get liabilityFieldInterestRate;

  /// No description provided for @liabilityFieldRateType.
  ///
  /// In en, this message translates to:
  /// **'Rate type'**
  String get liabilityFieldRateType;

  /// No description provided for @liabilityFieldTerm.
  ///
  /// In en, this message translates to:
  /// **'Term (months)'**
  String get liabilityFieldTerm;

  /// No description provided for @liabilityFieldStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get liabilityFieldStartDate;

  /// No description provided for @liabilityFieldMethod.
  ///
  /// In en, this message translates to:
  /// **'Repayment method'**
  String get liabilityFieldMethod;

  /// No description provided for @liabilityFieldCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get liabilityFieldCurrency;

  /// No description provided for @liabilityFieldStatementDay.
  ///
  /// In en, this message translates to:
  /// **'Statement day'**
  String get liabilityFieldStatementDay;

  /// No description provided for @liabilityFieldPaymentDueDay.
  ///
  /// In en, this message translates to:
  /// **'Payment due day'**
  String get liabilityFieldPaymentDueDay;

  /// No description provided for @liabilitySaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get liabilitySaveAction;

  /// No description provided for @liabilityValidationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get liabilityValidationRequired;

  /// No description provided for @liabilityValidationPositive.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than zero'**
  String get liabilityValidationPositive;

  /// No description provided for @liabilityValidationDayOfMonth.
  ///
  /// In en, this message translates to:
  /// **'Must be 1–31'**
  String get liabilityValidationDayOfMonth;

  /// No description provided for @liabilitySummaryRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining principal'**
  String get liabilitySummaryRemaining;

  /// No description provided for @liabilitySummaryInterestPaid.
  ///
  /// In en, this message translates to:
  /// **'Interest paid so far'**
  String get liabilitySummaryInterestPaid;

  /// No description provided for @liabilitySummaryInterestTotal.
  ///
  /// In en, this message translates to:
  /// **'Total interest cost'**
  String get liabilitySummaryInterestTotal;

  /// No description provided for @liabilitySummaryInterestRatio.
  ///
  /// In en, this message translates to:
  /// **'Interest as share of total payments'**
  String get liabilitySummaryInterestRatio;

  /// No description provided for @liabilitySummaryProgress.
  ///
  /// In en, this message translates to:
  /// **'Paid {paid} of {total} periods'**
  String liabilitySummaryProgress(int paid, int total);

  /// No description provided for @liabilityScheduleHeading.
  ///
  /// In en, this message translates to:
  /// **'Amortization schedule'**
  String get liabilityScheduleHeading;

  /// No description provided for @liabilityScheduleColPeriod.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get liabilityScheduleColPeriod;

  /// No description provided for @liabilityScheduleColDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get liabilityScheduleColDue;

  /// No description provided for @liabilityScheduleColPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get liabilityScheduleColPrincipal;

  /// No description provided for @liabilityScheduleColInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get liabilityScheduleColInterest;

  /// No description provided for @liabilityScheduleColRemaining.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get liabilityScheduleColRemaining;

  /// No description provided for @liabilityScheduleColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get liabilityScheduleColStatus;

  /// No description provided for @liabilityScheduleStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get liabilityScheduleStatusPaid;

  /// No description provided for @liabilityScheduleStatusDue.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get liabilityScheduleStatusDue;

  /// No description provided for @liabilityScheduleMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get liabilityScheduleMarkPaid;

  /// No description provided for @liabilityScheduleMarkPaidConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark period {period} paid?'**
  String liabilityScheduleMarkPaidConfirmTitle(int period);

  /// No description provided for @liabilityScheduleMarkPaidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This records a {amount} liability-payment transaction dated today and cannot be undone from this screen.'**
  String liabilityScheduleMarkPaidConfirmBody(String amount);

  /// No description provided for @liabilityScheduleMarkPaidNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Assign a payer account before marking periods paid.'**
  String get liabilityScheduleMarkPaidNoAccount;

  /// No description provided for @liabilityNotFound.
  ///
  /// In en, this message translates to:
  /// **'Liability not found'**
  String get liabilityNotFound;

  /// No description provided for @liabilityRevolvingNoSchedule.
  ///
  /// In en, this message translates to:
  /// **'Credit-card / revolving lines have no fixed amortization schedule.'**
  String get liabilityRevolvingNoSchedule;

  /// No description provided for @physicalAssetsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Real estate & vehicles'**
  String get physicalAssetsSectionTitle;

  /// No description provided for @physicalAssetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No real estate or vehicles yet. Tap + to add one.'**
  String get physicalAssetsEmpty;

  /// No description provided for @physicalAssetTypeRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real estate'**
  String get physicalAssetTypeRealEstate;

  /// No description provided for @physicalAssetTypeVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get physicalAssetTypeVehicle;

  /// No description provided for @physicalAssetAddRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Add real estate'**
  String get physicalAssetAddRealEstate;

  /// No description provided for @physicalAssetAddVehicle.
  ///
  /// In en, this message translates to:
  /// **'Add vehicle'**
  String get physicalAssetAddVehicle;

  /// No description provided for @physicalAssetFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get physicalAssetFieldName;

  /// No description provided for @physicalAssetFieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get physicalAssetFieldAddress;

  /// No description provided for @physicalAssetFieldPurchaseDate.
  ///
  /// In en, this message translates to:
  /// **'Purchase date'**
  String get physicalAssetFieldPurchaseDate;

  /// No description provided for @physicalAssetFieldPurchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Purchase price'**
  String get physicalAssetFieldPurchasePrice;

  /// No description provided for @physicalAssetFieldCurrentValuation.
  ///
  /// In en, this message translates to:
  /// **'Current valuation'**
  String get physicalAssetFieldCurrentValuation;

  /// No description provided for @physicalAssetFieldCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get physicalAssetFieldCurrency;

  /// No description provided for @physicalAssetFieldAnnualResidualRate.
  ///
  /// In en, this message translates to:
  /// **'Annual residual rate'**
  String get physicalAssetFieldAnnualResidualRate;

  /// No description provided for @physicalAssetFieldAutoDepreciation.
  ///
  /// In en, this message translates to:
  /// **'Auto-depreciate between updates'**
  String get physicalAssetFieldAutoDepreciation;

  /// No description provided for @physicalAssetFieldLinkedLiability.
  ///
  /// In en, this message translates to:
  /// **'Linked mortgage / loan id'**
  String get physicalAssetFieldLinkedLiability;

  /// No description provided for @physicalAssetFieldNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get physicalAssetFieldNote;

  /// No description provided for @physicalAssetCreateSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get physicalAssetCreateSubmit;

  /// No description provided for @physicalAssetUpdateValuationAction.
  ///
  /// In en, this message translates to:
  /// **'Update valuation'**
  String get physicalAssetUpdateValuationAction;

  /// No description provided for @physicalAssetUpdateValuationTitle.
  ///
  /// In en, this message translates to:
  /// **'Update valuation'**
  String get physicalAssetUpdateValuationTitle;

  /// No description provided for @physicalAssetUpdateValuationDate.
  ///
  /// In en, this message translates to:
  /// **'As-of date'**
  String get physicalAssetUpdateValuationDate;

  /// No description provided for @physicalAssetUpdateValuationAmount.
  ///
  /// In en, this message translates to:
  /// **'New valuation'**
  String get physicalAssetUpdateValuationAmount;

  /// No description provided for @physicalAssetUpdateValuationSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save valuation'**
  String get physicalAssetUpdateValuationSubmit;

  /// No description provided for @physicalAssetDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get physicalAssetDeleteAction;

  /// No description provided for @physicalAssetDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this asset?'**
  String get physicalAssetDeleteConfirmTitle;

  /// No description provided for @physicalAssetDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Valuation history will be tombstoned but recoverable on devices that have already synced.'**
  String get physicalAssetDeleteConfirmBody;

  /// No description provided for @physicalAssetDetailValuationTitle.
  ///
  /// In en, this message translates to:
  /// **'Current valuation'**
  String get physicalAssetDetailValuationTitle;

  /// No description provided for @physicalAssetDetailHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Valuation history'**
  String get physicalAssetDetailHistoryTitle;

  /// No description provided for @physicalAssetDetailDepreciationProjection.
  ///
  /// In en, this message translates to:
  /// **'Depreciation projection'**
  String get physicalAssetDetailDepreciationProjection;

  /// No description provided for @physicalAssetDetailPurchaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get physicalAssetDetailPurchaseLabel;

  /// No description provided for @physicalAssetDetailManualUpdateLabel.
  ///
  /// In en, this message translates to:
  /// **'Manual update'**
  String get physicalAssetDetailManualUpdateLabel;

  /// No description provided for @physicalAssetDetailAutoEstimateLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-estimate'**
  String get physicalAssetDetailAutoEstimateLabel;

  /// No description provided for @physicalAssetDetailEstimatedToday.
  ///
  /// In en, this message translates to:
  /// **'Estimated value today: {value}'**
  String physicalAssetDetailEstimatedToday(String value);

  /// No description provided for @physicalAssetValidationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get physicalAssetValidationRequired;

  /// No description provided for @physicalAssetValidationPositive.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than 0'**
  String get physicalAssetValidationPositive;

  /// No description provided for @physicalAssetValidationResidualRange.
  ///
  /// In en, this message translates to:
  /// **'Must be between 0 and 1'**
  String get physicalAssetValidationResidualRange;

  /// No description provided for @physicalAssetNotFound.
  ///
  /// In en, this message translates to:
  /// **'Asset not found'**
  String get physicalAssetNotFound;

  /// No description provided for @settingsAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsAppBarTitle;

  /// No description provided for @settingsAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountTitle;

  /// No description provided for @settingsAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in & multi-device sync'**
  String get settingsAccountSubtitle;

  /// No description provided for @settingsBaseCurrencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Base currency'**
  String get settingsBaseCurrencyTitle;

  /// No description provided for @settingsBaseCurrencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'{currency} (default)'**
  String settingsBaseCurrencySubtitle(String currency);

  /// No description provided for @settingsBaseCurrencyHint.
  ///
  /// In en, this message translates to:
  /// **'Totals on the dashboard, allocation chart, and trend chart are shown in this currency.'**
  String get settingsBaseCurrencyHint;

  /// No description provided for @settingsBaseCurrencySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick base currency'**
  String get settingsBaseCurrencySheetTitle;

  /// No description provided for @settingsFxRatesTitle.
  ///
  /// In en, this message translates to:
  /// **'FX rates'**
  String get settingsFxRatesTitle;

  /// No description provided for @settingsFxRatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates are auto-synced from Yahoo Finance. Manual entry available as fallback.'**
  String get settingsFxRatesSubtitle;

  /// No description provided for @fxRatesAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'FX rates'**
  String get fxRatesAppBarTitle;

  /// No description provided for @fxRatesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No FX rates recorded yet. Rates are auto-synced on app launch — add accounts in different currencies to get started.'**
  String get fxRatesEmpty;

  /// No description provided for @fxRatesRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Syncing rates…'**
  String get fxRatesRefreshing;

  /// No description provided for @fxRatesSyncedFrom.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get fxRatesSyncedFrom;

  /// No description provided for @fxRatesAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add rate'**
  String get fxRatesAddAction;

  /// No description provided for @fxRatesEntrySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add an FX rate'**
  String get fxRatesEntrySheetTitle;

  /// No description provided for @fxRatesFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fxRatesFromLabel;

  /// No description provided for @fxRatesToLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get fxRatesToLabel;

  /// No description provided for @fxRatesRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get fxRatesRateLabel;

  /// No description provided for @fxRatesAsOfLabel.
  ///
  /// In en, this message translates to:
  /// **'As of'**
  String get fxRatesAsOfLabel;

  /// No description provided for @fxRatesSamePairError.
  ///
  /// In en, this message translates to:
  /// **'Source and target currencies must differ.'**
  String get fxRatesSamePairError;

  /// No description provided for @fxRatesInvalidRateError.
  ///
  /// In en, this message translates to:
  /// **'Rate must be a positive number.'**
  String get fxRatesInvalidRateError;

  /// No description provided for @dashboardCurrencyMismatchBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 holding excluded — missing FX rate to {currency}} other{{count} holdings excluded — missing FX rates to {currency}}}'**
  String dashboardCurrencyMismatchBanner(int count, String currency);

  /// No description provided for @dashboardCurrencyMismatchAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get dashboardCurrencyMismatchAction;

  /// No description provided for @dashboardCurrencyMismatchSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Holdings excluded from totals'**
  String get dashboardCurrencyMismatchSheetTitle;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About NaviWealth'**
  String get settingsAboutTitle;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String settingsAboutSubtitle(String version);

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeModeTitle;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @settingsMarketColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Up / down colors'**
  String get settingsMarketColorTitle;

  /// No description provided for @marketColorRedUpGreenDown.
  ///
  /// In en, this message translates to:
  /// **'Red up / green down (CN)'**
  String get marketColorRedUpGreenDown;

  /// No description provided for @marketColorGreenUpRedDown.
  ///
  /// In en, this message translates to:
  /// **'Green up / red down (Intl)'**
  String get marketColorGreenUpRedDown;

  /// No description provided for @marketColorColorblind.
  ///
  /// In en, this message translates to:
  /// **'Color-blind safe (blue / orange)'**
  String get marketColorColorblind;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get langSystem;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get langChinese;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get commonSaving;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// No description provided for @commonLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String commonLoadError(String error);

  /// Generic load failure message that hides raw exception details from the UI.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this view. Please try again.'**
  String get commonLoadFailed;

  /// Generic failure snackbar shown when an optimistic form submit fails after the form has already popped.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your changes. Tap retry.'**
  String get commonSaveFailed;

  /// Shown when a route's deferred bundle fails to download (offline, bad CDN cache, etc.).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this section'**
  String get deferredLoadFailedTitle;

  /// No description provided for @deferredLoadRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get deferredLoadRetry;

  /// Title shown when go_router can't match a URL to any registered route (404).
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get routeNotFoundTitle;

  /// Body of the 404 page; includes the URL the user tried to visit.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find {path}. It may have been moved or never existed.'**
  String routeNotFoundMessage(String path);

  /// Title shown when go_router's errorBuilder fires for a runtime error (not a 404).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get routeErrorTitle;

  /// Action that navigates back to the home tab from an error / not-found page.
  ///
  /// In en, this message translates to:
  /// **'Back to overview'**
  String get routeGoHome;

  /// Title of the shortcut help dialog (Cmd/Ctrl+/)
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutsHelpTitle;

  /// No description provided for @shortcutCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Open command palette'**
  String get shortcutCommandPalette;

  /// No description provided for @shortcutShowHelp.
  ///
  /// In en, this message translates to:
  /// **'Show keyboard shortcut help'**
  String get shortcutShowHelp;

  /// No description provided for @shortcutDismissOverlay.
  ///
  /// In en, this message translates to:
  /// **'Close current dialog'**
  String get shortcutDismissOverlay;

  /// Help-dialog label for the Cmd/Ctrl+B sidebar toggle
  ///
  /// In en, this message translates to:
  /// **'Collapse / expand sidebar'**
  String get shortcutToggleSidebar;

  /// No description provided for @shortcutSwitchTab.
  ///
  /// In en, this message translates to:
  /// **'Switch to tab {position} ({label})'**
  String shortcutSwitchTab(int position, String label);

  /// Help-dialog label for the Cmd/Ctrl+/ AI chat shortcut
  ///
  /// In en, this message translates to:
  /// **'Open AI chat'**
  String get shortcutOpenAiChat;

  /// Help-dialog label for vim-style g+key navigation
  ///
  /// In en, this message translates to:
  /// **'Vim-style go to {target}'**
  String shortcutVimGoto(String target);

  /// Help-dialog label for / key to focus search in master-detail lists
  ///
  /// In en, this message translates to:
  /// **'Focus list search'**
  String get shortcutListSearch;

  /// Help-dialog label for j key to select next list item in master-detail
  ///
  /// In en, this message translates to:
  /// **'Select next item'**
  String get shortcutListNext;

  /// Help-dialog label for k key to select previous list item in master-detail
  ///
  /// In en, this message translates to:
  /// **'Select previous item'**
  String get shortcutListPrevious;

  /// Placeholder for the command palette search box
  ///
  /// In en, this message translates to:
  /// **'Search commands…'**
  String get commandPaletteSearchHint;

  /// Placeholder text on the mobile shell's command-bar pill (§5.10.2 / S2.5)
  ///
  /// In en, this message translates to:
  /// **'Search, jump, ask…'**
  String get commandPaletteMobileEntryHint;

  /// Shown in the command palette when the query matches no commands
  ///
  /// In en, this message translates to:
  /// **'No commands match your search'**
  String get commandPaletteEmpty;

  /// Dynamic command palette entry that opens AI chat with the user's query prefilled
  ///
  /// In en, this message translates to:
  /// **'Ask AI: {query}'**
  String commandPaletteAskAi(String query);

  /// Tiny badge on the command palette result pane showing the answer was computed on-device
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get askAiResultLocalBadge;

  /// Shown when the natural-language parser can't resolve a query locally
  ///
  /// In en, this message translates to:
  /// **'Can\'t answer this here. Continue in AI history for a full chat.'**
  String get askAiResultNoLocalMatch;

  /// Link below the no-local-match notice that opens /settings/ai-history with the query prefilled
  ///
  /// In en, this message translates to:
  /// **'Continue in AI history →'**
  String get askAiResultContinueInChat;

  /// §5.10.6 guardrail copy shown when the user types a write-shaped natural language query
  ///
  /// In en, this message translates to:
  /// **'The command palette doesn\'t execute transfers, orders, or account deletion. Use the corresponding page.'**
  String get askAiResultIrreversibleBlocked;

  /// Shown when the local executor throws while running a parsed query plan
  ///
  /// In en, this message translates to:
  /// **'Could not run this query: {error}'**
  String askAiResultError(String error);

  /// Shown when a parsed query returns zero rows
  ///
  /// In en, this message translates to:
  /// **'No matching records.'**
  String get askAiResultEmpty;

  /// Footer hint when only the first N rows are previewed
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String askAiResultMoreRows(int count);

  /// Summary line: number of rows in the result
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String askAiResultRowCount(int count);

  /// Title for the spending-by-category result card
  ///
  /// In en, this message translates to:
  /// **'Spending by category'**
  String get askAiResultTitleSpending;

  /// Title for the transactions-filter result card
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get askAiResultTitleTransactions;

  /// Title for the net-worth-trend result card
  ///
  /// In en, this message translates to:
  /// **'Net worth trend'**
  String get askAiResultTitleNetWorth;

  /// Title for the subscription-list result card
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get askAiResultTitleSubscriptions;

  /// Title for the refund-matching result card
  ///
  /// In en, this message translates to:
  /// **'Refund matches'**
  String get askAiResultTitleRefunds;

  /// Generic title for query result cards we haven't specialized
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get askAiResultTitleGeneric;

  /// Command palette: navigate to the home/overview tab
  ///
  /// In en, this message translates to:
  /// **'Go to Overview'**
  String get commandPaletteGoOverview;

  /// Command palette: navigate to the settings tab
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get commandPaletteGoSettings;

  /// Command palette: open the trade entry form
  ///
  /// In en, this message translates to:
  /// **'New trade'**
  String get commandPaletteNewTrade;

  /// Command palette: open the new expense form
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get commandPaletteNewExpense;

  /// Command palette: open the AI chat page
  ///
  /// In en, this message translates to:
  /// **'Open AI assistant'**
  String get commandPaletteOpenAi;

  /// Command palette: cycle between light and dark theme
  ///
  /// In en, this message translates to:
  /// **'Toggle theme (light / dark)'**
  String get commandPaletteToggleTheme;

  /// Command palette: cycle market direction colors
  ///
  /// In en, this message translates to:
  /// **'Toggle market color mode'**
  String get commandPaletteToggleColorMode;

  /// Command palette: cycle between supported languages
  ///
  /// In en, this message translates to:
  /// **'Toggle language'**
  String get commandPaletteToggleLanguage;

  /// Command palette: open the shortcut help dialog
  ///
  /// In en, this message translates to:
  /// **'Show keyboard shortcuts'**
  String get commandPaletteShortcutHelp;

  /// Banner shown when the PWA service worker has a new version waiting to activate
  ///
  /// In en, this message translates to:
  /// **'A new version of NaviWealth is ready.'**
  String get pwaUpdateAvailable;

  /// Action to apply the pending PWA update and reload
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get pwaUpdateApply;

  /// Action to dismiss the PWA update banner without refreshing
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get pwaUpdateDismiss;

  /// Subtitle on the login screen, sits below the app name.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authLoginTitle;

  /// Primary action button on the login form.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authLoginSubmit;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordShowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authPasswordShowTooltip;

  /// No description provided for @authPasswordHideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authPasswordHideTooltip;

  /// No description provided for @authEmailErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get authEmailErrorEmpty;

  /// No description provided for @authEmailErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid email.'**
  String get authEmailErrorInvalid;

  /// No description provided for @authPasswordErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get authPasswordErrorEmpty;

  /// No description provided for @authPasswordErrorTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get authPasswordErrorTooShort;

  /// No description provided for @authLoginErrorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get authLoginErrorInvalidCredentials;

  /// No description provided for @authLoginErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get authLoginErrorNetwork;

  /// No description provided for @authLoginErrorServer.
  ///
  /// In en, this message translates to:
  /// **'The server is having trouble. Please try again in a minute.'**
  String get authLoginErrorServer;

  /// No description provided for @authLoginErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again.'**
  String get authLoginErrorGeneric;

  /// Inline banner shown on the login screen after the auth controller dropped an expired session.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get authLoginNoticeSessionExpired;

  /// Settings row that opens the device list.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevicesTitle;

  /// No description provided for @settingsDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View signed-in devices and revoke access'**
  String get settingsDevicesSubtitle;

  /// AppBar title on the devices list page.
  ///
  /// In en, this message translates to:
  /// **'Signed-in devices'**
  String get authDevicesTitle;

  /// Fallback name for devices that signed in without a device_name.
  ///
  /// In en, this message translates to:
  /// **'Unnamed device'**
  String get authDeviceUnnamed;

  /// Chip on the row representing the currently signed-in device.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get authDeviceCurrent;

  /// Subtitle of a device row showing when it last touched the API.
  ///
  /// In en, this message translates to:
  /// **'Last seen {timestamp}'**
  String authDeviceLastSeen(String timestamp);

  /// No description provided for @authDeviceRevokeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign this device out'**
  String get authDeviceRevokeTooltip;

  /// No description provided for @authDeviceRevokeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign this device out?'**
  String get authDeviceRevokeDialogTitle;

  /// No description provided for @authDeviceRevokeDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Sign {device} out? It will need to log in again to sync.'**
  String authDeviceRevokeDialogBody(String device);

  /// No description provided for @authDeviceRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authDeviceRevokeConfirm;

  /// No description provided for @authDeviceRevokeError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t revoke that device. Please try again.'**
  String get authDeviceRevokeError;

  /// No description provided for @authDevicesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your devices.'**
  String get authDevicesLoadError;

  /// No description provided for @authLogoutCurrentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authLogoutCurrentTooltip;

  /// No description provided for @authLogoutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get authLogoutDialogTitle;

  /// No description provided for @authLogoutDialogBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to sign in again on this device.'**
  String get authLogoutDialogBody;

  /// No description provided for @authLogoutDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authLogoutDialogConfirm;

  /// No description provided for @dashboardAllocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Asset allocation'**
  String get dashboardAllocationTitle;

  /// No description provided for @dashboardTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth trend'**
  String get dashboardTrendTitle;

  /// No description provided for @dashboardCategoryStock.
  ///
  /// In en, this message translates to:
  /// **'Stocks'**
  String get dashboardCategoryStock;

  /// No description provided for @dashboardCategoryEtf.
  ///
  /// In en, this message translates to:
  /// **'ETFs'**
  String get dashboardCategoryEtf;

  /// No description provided for @dashboardCategoryBondsAndFunds.
  ///
  /// In en, this message translates to:
  /// **'Bonds & funds'**
  String get dashboardCategoryBondsAndFunds;

  /// No description provided for @dashboardCategoryCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get dashboardCategoryCash;

  /// No description provided for @dashboardCategoryCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get dashboardCategoryCrypto;

  /// No description provided for @dashboardCategoryRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real estate'**
  String get dashboardCategoryRealEstate;

  /// No description provided for @dashboardCategoryVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicles'**
  String get dashboardCategoryVehicle;

  /// No description provided for @dashboardCategoryLiability.
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get dashboardCategoryLiability;

  /// No description provided for @dashboardRange1M.
  ///
  /// In en, this message translates to:
  /// **'1M'**
  String get dashboardRange1M;

  /// No description provided for @dashboardRange3M.
  ///
  /// In en, this message translates to:
  /// **'3M'**
  String get dashboardRange3M;

  /// No description provided for @dashboardRange6M.
  ///
  /// In en, this message translates to:
  /// **'6M'**
  String get dashboardRange6M;

  /// No description provided for @dashboardRange1Y.
  ///
  /// In en, this message translates to:
  /// **'1Y'**
  String get dashboardRange1Y;

  /// No description provided for @dashboardRange3Y.
  ///
  /// In en, this message translates to:
  /// **'3Y'**
  String get dashboardRange3Y;

  /// No description provided for @dashboardRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dashboardRangeAll;

  /// No description provided for @dashboardRangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get dashboardRangeCustom;

  /// No description provided for @dashboardDrillDownItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String dashboardDrillDownItemCount(int count);

  /// No description provided for @dashboardNetWorthBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Assets {assets} − Liabilities {liabilities} ({currency})'**
  String dashboardNetWorthBreakdown(
    String assets,
    String liabilities,
    String currency,
  );

  /// No description provided for @dashboardSnapshotError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your dashboard: {error}'**
  String dashboardSnapshotError(String error);

  /// No description provided for @dashboardTrendError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the trend chart: {error}'**
  String dashboardTrendError(String error);

  /// No description provided for @dashboardTrendFlatHint.
  ///
  /// In en, this message translates to:
  /// **'Trend line is flat — no historical valuation snapshots yet for the assets in this window.'**
  String get dashboardTrendFlatHint;

  /// Label for the today's net-worth change cell on the dashboard header.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dashboardHeaderDeltaTodayLabel;

  /// Label for the month-to-date net-worth change cell on the dashboard header.
  ///
  /// In en, this message translates to:
  /// **'MTD'**
  String get dashboardHeaderDeltaMonthLabel;

  /// Label for the year-to-date return cell on the dashboard header.
  ///
  /// In en, this message translates to:
  /// **'YTD'**
  String get dashboardHeaderDeltaYtdLabel;

  /// AppBar title for the analytics tab.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsAppBarTitle;

  /// No description provided for @analyticsEquityTitle.
  ///
  /// In en, this message translates to:
  /// **'Equity Allocation'**
  String get analyticsEquityTitle;

  /// No description provided for @analyticsEquitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slice your stock & ETF holdings by sector, region, or market cap.'**
  String get analyticsEquitySubtitle;

  /// No description provided for @analyticsDimensionSector.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get analyticsDimensionSector;

  /// No description provided for @analyticsDimensionRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get analyticsDimensionRegion;

  /// No description provided for @analyticsDimensionMarketCap.
  ///
  /// In en, this message translates to:
  /// **'Market Cap'**
  String get analyticsDimensionMarketCap;

  /// No description provided for @analyticsTotalValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Total {currency}'**
  String analyticsTotalValueLabel(String currency);

  /// No description provided for @analyticsBucketUnclassified.
  ///
  /// In en, this message translates to:
  /// **'Unclassified'**
  String get analyticsBucketUnclassified;

  /// No description provided for @analyticsBucketRegionCnA.
  ///
  /// In en, this message translates to:
  /// **'A-shares'**
  String get analyticsBucketRegionCnA;

  /// No description provided for @analyticsBucketRegionHk.
  ///
  /// In en, this message translates to:
  /// **'Hong Kong'**
  String get analyticsBucketRegionHk;

  /// No description provided for @analyticsBucketRegionUs.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get analyticsBucketRegionUs;

  /// No description provided for @analyticsBucketRegionCrypto.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get analyticsBucketRegionCrypto;

  /// No description provided for @analyticsBucketRegionFx.
  ///
  /// In en, this message translates to:
  /// **'FX'**
  String get analyticsBucketRegionFx;

  /// No description provided for @analyticsBucketRegionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get analyticsBucketRegionUnknown;

  /// No description provided for @analyticsBucketMarketCapLarge.
  ///
  /// In en, this message translates to:
  /// **'Large cap'**
  String get analyticsBucketMarketCapLarge;

  /// No description provided for @analyticsBucketMarketCapMid.
  ///
  /// In en, this message translates to:
  /// **'Mid cap'**
  String get analyticsBucketMarketCapMid;

  /// No description provided for @analyticsBucketMarketCapSmall.
  ///
  /// In en, this message translates to:
  /// **'Small cap'**
  String get analyticsBucketMarketCapSmall;

  /// No description provided for @analyticsHoldingsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {{count} holding} other {{count} holdings}}'**
  String analyticsHoldingsCount(int count);

  /// No description provided for @analyticsUnclassifiedHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 holding is missing classification metadata.} other {{count} holdings are missing classification metadata.}}'**
  String analyticsUnclassifiedHint(int count);

  /// No description provided for @analyticsUnclassifiedAction.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get analyticsUnclassifiedAction;

  /// No description provided for @analyticsUnclassifiedRowCta.
  ///
  /// In en, this message translates to:
  /// **'Tap a holding to fill in its metadata.'**
  String get analyticsUnclassifiedRowCta;

  /// No description provided for @analyticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No equity holdings yet'**
  String get analyticsEmptyTitle;

  /// No description provided for @analyticsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Once you record stock or ETF trades, the breakdown will show up here.'**
  String get analyticsEmptyHint;

  /// No description provided for @analyticsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the allocation view.'**
  String get analyticsLoadError;

  /// No description provided for @analyticsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get analyticsRetry;

  /// No description provided for @analyticsBucketSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Holdings in {label}'**
  String analyticsBucketSheetTitle(String label);

  /// No description provided for @analyticsHoldingTooltip.
  ///
  /// In en, this message translates to:
  /// **'{symbol} · {value} · {weight}'**
  String analyticsHoldingTooltip(String symbol, String value, String weight);

  /// No description provided for @fireAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE'**
  String get fireAppBarTitle;

  /// No description provided for @fireLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load FIRE dashboard. {detail}'**
  String fireLoadError(String detail);

  /// No description provided for @fireRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get fireRetry;

  /// No description provided for @fireEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your FIRE goal'**
  String get fireEmptyTitle;

  /// No description provided for @fireEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your target net worth, monthly expenses and savings to see how far you are from financial independence.'**
  String get fireEmptyHint;

  /// No description provided for @fireEmptySetGoalCta.
  ///
  /// In en, this message translates to:
  /// **'Set goal'**
  String get fireEmptySetGoalCta;

  /// No description provided for @fireEditGoal.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get fireEditGoal;

  /// No description provided for @fireGoalSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE goal'**
  String get fireGoalSheetTitle;

  /// No description provided for @fireGoalSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Inputs are stored on this device only and are inflation-adjusted with the rate below.'**
  String get fireGoalSheetSubtitle;

  /// No description provided for @fireGoalSheetCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get fireGoalSheetCancel;

  /// No description provided for @fireGoalSheetSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get fireGoalSheetSave;

  /// No description provided for @fireGoalFieldTarget.
  ///
  /// In en, this message translates to:
  /// **'Target net worth'**
  String get fireGoalFieldTarget;

  /// No description provided for @fireGoalFieldTargetHelper.
  ///
  /// In en, this message translates to:
  /// **'Net worth required to retire, in today\'s purchasing power.'**
  String get fireGoalFieldTargetHelper;

  /// No description provided for @fireGoalFieldMonthlyExpenses.
  ///
  /// In en, this message translates to:
  /// **'Monthly expenses at FIRE'**
  String get fireGoalFieldMonthlyExpenses;

  /// No description provided for @fireGoalFieldMonthlyExpensesHelper.
  ///
  /// In en, this message translates to:
  /// **'Used by the 4% rule to check if your target supports your lifestyle.'**
  String get fireGoalFieldMonthlyExpensesHelper;

  /// No description provided for @fireGoalFieldMonthlySurplus.
  ///
  /// In en, this message translates to:
  /// **'Monthly surplus (savings)'**
  String get fireGoalFieldMonthlySurplus;

  /// No description provided for @fireGoalFieldMonthlySurplusHelper.
  ///
  /// In en, this message translates to:
  /// **'How much you save each month — drives the projection\'s contribution.'**
  String get fireGoalFieldMonthlySurplusHelper;

  /// No description provided for @fireGoalFieldInflation.
  ///
  /// In en, this message translates to:
  /// **'Inflation: {rate}%'**
  String fireGoalFieldInflation(String rate);

  /// No description provided for @fireGoalValidationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fireGoalValidationRequired;

  /// No description provided for @fireGoalValidationInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get fireGoalValidationInvalidNumber;

  /// No description provided for @fireGoalValidationNonNegative.
  ///
  /// In en, this message translates to:
  /// **'Must be zero or positive'**
  String get fireGoalValidationNonNegative;

  /// No description provided for @fireGoalValidationPositive.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than zero'**
  String get fireGoalValidationPositive;

  /// No description provided for @fireProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress to FIRE'**
  String get fireProgressTitle;

  /// No description provided for @fireProgressGaugeCaption.
  ///
  /// In en, this message translates to:
  /// **'of FIRE target'**
  String get fireProgressGaugeCaption;

  /// No description provided for @fireProgressCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current net worth'**
  String get fireProgressCurrent;

  /// No description provided for @fireProgressTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get fireProgressTarget;

  /// No description provided for @fireProgressGap.
  ///
  /// In en, this message translates to:
  /// **'Gap to FIRE'**
  String get fireProgressGap;

  /// No description provided for @fireCountdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to FIRE · {scenario}'**
  String fireCountdownTitle(String scenario);

  /// No description provided for @fireCountdownReachedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached FIRE'**
  String get fireCountdownReachedTitle;

  /// No description provided for @fireCountdownReachedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth already meets the target — focus on sustaining the safe-withdrawal rate.'**
  String get fireCountdownReachedSubtitle;

  /// No description provided for @fireCountdownUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable within 100 years at the current surplus and return rate. Increase savings or your return assumption.'**
  String get fireCountdownUnreachable;

  /// No description provided for @fireCountdownUnreachableShort.
  ///
  /// In en, this message translates to:
  /// **'100y+'**
  String get fireCountdownUnreachableShort;

  /// No description provided for @fireCountdownYearsOnly.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{1 year} other{{years} years}}'**
  String fireCountdownYearsOnly(int years);

  /// No description provided for @fireCountdownMonthsOnly.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, =1{1 month} other{{months} months}}'**
  String fireCountdownMonthsOnly(int months);

  /// No description provided for @fireCountdownYearsMonths.
  ///
  /// In en, this message translates to:
  /// **'{years}y {months}m'**
  String fireCountdownYearsMonths(int years, int months);

  /// No description provided for @fireCountdownDaysAprox.
  ///
  /// In en, this message translates to:
  /// **'≈ {days} days'**
  String fireCountdownDaysAprox(int days);

  /// No description provided for @fireProjectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Projection'**
  String get fireProjectionTitle;

  /// No description provided for @fireProjectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth path under each return scenario; dashed line is the inflation-adjusted target.'**
  String get fireProjectionSubtitle;

  /// No description provided for @fireProjectionTargetLineLegend.
  ///
  /// In en, this message translates to:
  /// **'Target (inflation-adjusted)'**
  String get fireProjectionTargetLineLegend;

  /// No description provided for @fireScenariosTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Scenarios'**
  String get fireScenariosTableTitle;

  /// No description provided for @fireScenarioConservative.
  ///
  /// In en, this message translates to:
  /// **'Conservative'**
  String get fireScenarioConservative;

  /// No description provided for @fireScenarioNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get fireScenarioNeutral;

  /// No description provided for @fireScenarioAggressive.
  ///
  /// In en, this message translates to:
  /// **'Aggressive'**
  String get fireScenarioAggressive;

  /// No description provided for @fireScenarioLive.
  ///
  /// In en, this message translates to:
  /// **'Live (XIRR)'**
  String get fireScenarioLive;

  /// No description provided for @fireScenarioRateLabel.
  ///
  /// In en, this message translates to:
  /// **'{rate}% annualized'**
  String fireScenarioRateLabel(String rate);

  /// No description provided for @fireScenarioReachedNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get fireScenarioReachedNow;

  /// No description provided for @fireSafeWithdrawalTitle.
  ///
  /// In en, this message translates to:
  /// **'4% rule'**
  String get fireSafeWithdrawalTitle;

  /// No description provided for @fireSafeWithdrawalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trinity-study safe withdrawal: 4% of the target each year, in today\'s purchasing power.'**
  String get fireSafeWithdrawalSubtitle;

  /// No description provided for @fireSafeWithdrawalMonthly.
  ///
  /// In en, this message translates to:
  /// **'Safe monthly withdrawal'**
  String get fireSafeWithdrawalMonthly;

  /// No description provided for @fireSafeWithdrawalAnnual.
  ///
  /// In en, this message translates to:
  /// **'Safe annual withdrawal'**
  String get fireSafeWithdrawalAnnual;

  /// No description provided for @fireSafeWithdrawalNoExpenses.
  ///
  /// In en, this message translates to:
  /// **'Set monthly expenses to compare with this withdrawal.'**
  String get fireSafeWithdrawalNoExpenses;

  /// No description provided for @fireSafeWithdrawalCovers.
  ///
  /// In en, this message translates to:
  /// **'Covers planned expenses with {amount} to spare each month.'**
  String fireSafeWithdrawalCovers(String amount);

  /// No description provided for @fireSafeWithdrawalShortfall.
  ///
  /// In en, this message translates to:
  /// **'Falls short of planned expenses by {amount} per month.'**
  String fireSafeWithdrawalShortfall(String amount);

  /// No description provided for @fireSensitivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get fireSensitivityTitle;

  /// No description provided for @fireSensitivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How time-to-FIRE shifts when monthly surplus changes by ±20%.'**
  String get fireSensitivitySubtitle;

  /// No description provided for @fireSensitivityHigherSurplus.
  ///
  /// In en, this message translates to:
  /// **'+20% surplus'**
  String get fireSensitivityHigherSurplus;

  /// No description provided for @fireSensitivityBaseline.
  ///
  /// In en, this message translates to:
  /// **'Current surplus'**
  String get fireSensitivityBaseline;

  /// No description provided for @fireSensitivityLowerSurplus.
  ///
  /// In en, this message translates to:
  /// **'-20% surplus'**
  String get fireSensitivityLowerSurplus;

  /// No description provided for @fireOsHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Freedom status'**
  String get fireOsHeroTitle;

  /// No description provided for @fireOsHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whether today\'s portfolio still supports the lifestyle you planned for.'**
  String get fireOsHeroSubtitle;

  /// No description provided for @fireOsHeroNetWorthLabel.
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get fireOsHeroNetWorthLabel;

  /// No description provided for @fireOsHeroInvestableLabel.
  ///
  /// In en, this message translates to:
  /// **'Investable'**
  String get fireOsHeroInvestableLabel;

  /// No description provided for @fireOsHeroLiquidLabel.
  ///
  /// In en, this message translates to:
  /// **'Liquid'**
  String get fireOsHeroLiquidLabel;

  /// No description provided for @fireOsHeroWithdrawalRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate'**
  String get fireOsHeroWithdrawalRateLabel;

  /// No description provided for @fireOsHeroWithdrawalRateValue.
  ///
  /// In en, this message translates to:
  /// **'{rate}% / SWR {swr}%'**
  String fireOsHeroWithdrawalRateValue(String rate, String swr);

  /// No description provided for @fireOsHeroWithdrawalRateInfinite.
  ///
  /// In en, this message translates to:
  /// **'Spend without investable assets'**
  String get fireOsHeroWithdrawalRateInfinite;

  /// No description provided for @fireOsHeroCashBucketLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket'**
  String get fireOsHeroCashBucketLabel;

  /// No description provided for @fireOsHeroCashBucketValue.
  ///
  /// In en, this message translates to:
  /// **'{months} mo / target {target} mo'**
  String fireOsHeroCashBucketValue(String months, int target);

  /// No description provided for @fireOsHeroCashBucketInfinite.
  ///
  /// In en, this message translates to:
  /// **'No recorded monthly expense'**
  String get fireOsHeroCashBucketInfinite;

  /// No description provided for @fireOsHeroEtaLabel.
  ///
  /// In en, this message translates to:
  /// **'FIRE ETA'**
  String get fireOsHeroEtaLabel;

  /// No description provided for @fireOsHeroEtaReached.
  ///
  /// In en, this message translates to:
  /// **'Already reached'**
  String get fireOsHeroEtaReached;

  /// No description provided for @fireOsHeroEtaUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Not within 100 years'**
  String get fireOsHeroEtaUnreachable;

  /// No description provided for @fireOsHeroAnnualSpendLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual spend'**
  String get fireOsHeroAnnualSpendLabel;

  /// No description provided for @fireOsAnnualSpendSourceTrailing.
  ///
  /// In en, this message translates to:
  /// **'Trailing 12 months'**
  String get fireOsAnnualSpendSourceTrailing;

  /// No description provided for @fireOsAnnualSpendSourcePlan.
  ///
  /// In en, this message translates to:
  /// **'Plan input'**
  String get fireOsAnnualSpendSourcePlan;

  /// No description provided for @fireOsSafetySafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get fireOsSafetySafe;

  /// No description provided for @fireOsSafetyCautious.
  ///
  /// In en, this message translates to:
  /// **'Cautious'**
  String get fireOsSafetyCautious;

  /// No description provided for @fireOsSafetyDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get fireOsSafetyDanger;

  /// No description provided for @fireOsSafetyUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Plan not set'**
  String get fireOsSafetyUnconfigured;

  /// No description provided for @fireOsSuggestedActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested next steps'**
  String get fireOsSuggestedActionsTitle;

  /// No description provided for @fireOsSuggestedActionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No actions right now — the plan is steady.'**
  String get fireOsSuggestedActionsEmpty;

  /// No description provided for @fireOsActionConfigurePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your FIRE plan'**
  String get fireOsActionConfigurePlanTitle;

  /// No description provided for @fireOsActionConfigurePlanDetail.
  ///
  /// In en, this message translates to:
  /// **'Tell NaviWealth your target, expenses, and savings so it can judge safety.'**
  String get fireOsActionConfigurePlanDetail;

  /// No description provided for @fireOsActionHoldSteadyTitle.
  ///
  /// In en, this message translates to:
  /// **'On track — keep it steady'**
  String get fireOsActionHoldSteadyTitle;

  /// No description provided for @fireOsActionHoldSteadyDetail.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate is below SWR and the cash bucket is healthy.'**
  String get fireOsActionHoldSteadyDetail;

  /// No description provided for @fireOsActionTopUpCashBucketTitle.
  ///
  /// In en, this message translates to:
  /// **'Top up the cash bucket'**
  String get fireOsActionTopUpCashBucketTitle;

  /// No description provided for @fireOsActionTopUpCashBucketDetail.
  ///
  /// In en, this message translates to:
  /// **'Add {amount} to reach {months} months of runway.'**
  String fireOsActionTopUpCashBucketDetail(String amount, int months);

  /// No description provided for @fireOsActionReduceSpendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce spending'**
  String get fireOsActionReduceSpendingTitle;

  /// No description provided for @fireOsActionReduceSpendingDetailPct.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate is {pct} percentage points above your SWR.'**
  String fireOsActionReduceSpendingDetailPct(String pct);

  /// No description provided for @fireOsActionReduceSpendingDetailGeneric.
  ///
  /// In en, this message translates to:
  /// **'Spending has outrun the investable base — review the monthly burn.'**
  String get fireOsActionReduceSpendingDetailGeneric;

  /// No description provided for @fireOsActionDelayDiscretionaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delay discretionary spend'**
  String get fireOsActionDelayDiscretionaryTitle;

  /// No description provided for @fireOsActionDelayDiscretionaryDetail.
  ///
  /// In en, this message translates to:
  /// **'Push travel, upgrades, or big purchases out until the withdrawal rate cools down.'**
  String get fireOsActionDelayDiscretionaryDetail;

  /// No description provided for @fireOsActionRebalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebalance toward target'**
  String get fireOsActionRebalanceTitle;

  /// No description provided for @fireOsActionRebalanceDetail.
  ///
  /// In en, this message translates to:
  /// **'Allocation has drifted — bring sleeves back in line.'**
  String get fireOsActionRebalanceDetail;

  /// No description provided for @fireOsActionBuildRiskReserveTitle.
  ///
  /// In en, this message translates to:
  /// **'Build a risk reserve'**
  String get fireOsActionBuildRiskReserveTitle;

  /// No description provided for @fireOsActionBuildRiskReserveDetail.
  ///
  /// In en, this message translates to:
  /// **'Net worth is negative or thin — set aside emergency / medical reserves.'**
  String get fireOsActionBuildRiskReserveDetail;

  /// No description provided for @fireOsActionRunReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the latest review'**
  String get fireOsActionRunReviewTitle;

  /// No description provided for @fireOsActionRunReviewDetail.
  ///
  /// In en, this message translates to:
  /// **'Check the monthly or quarterly review for context.'**
  String get fireOsActionRunReviewDetail;

  /// No description provided for @fireOsActionFixCurrencyGapTitle.
  ///
  /// In en, this message translates to:
  /// **'Fix missing FX rates'**
  String get fireOsActionFixCurrencyGapTitle;

  /// No description provided for @fireOsActionFixCurrencyGapDetail.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings are missing a rate into your base currency.'**
  String fireOsActionFixCurrencyGapDetail(int count);

  /// No description provided for @fireOsPlanFormAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get fireOsPlanFormAdvancedTitle;

  /// No description provided for @fireOsPlanFormSwrLabel.
  ///
  /// In en, this message translates to:
  /// **'Safe withdrawal rate'**
  String get fireOsPlanFormSwrLabel;

  /// No description provided for @fireOsPlanFormSwrValue.
  ///
  /// In en, this message translates to:
  /// **'{rate}%'**
  String fireOsPlanFormSwrValue(String rate);

  /// No description provided for @fireOsPlanFormSwrHelper.
  ///
  /// In en, this message translates to:
  /// **'Trinity-study default is 4%. Lean FIRE typically aims lower; Fat FIRE leaves more buffer.'**
  String get fireOsPlanFormSwrHelper;

  /// No description provided for @fireOsPlanFormCashBucketLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket target (months)'**
  String get fireOsPlanFormCashBucketLabel;

  /// No description provided for @fireOsPlanFormCashBucketHelper.
  ///
  /// In en, this message translates to:
  /// **'How many months of expenses to keep in liquid cash.'**
  String get fireOsPlanFormCashBucketHelper;

  /// No description provided for @fireOsPlanFormLifestyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle mode'**
  String get fireOsPlanFormLifestyleLabel;

  /// No description provided for @fireOsPlanFormLifestyleLean.
  ///
  /// In en, this message translates to:
  /// **'Lean'**
  String get fireOsPlanFormLifestyleLean;

  /// No description provided for @fireOsPlanFormLifestyleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fireOsPlanFormLifestyleStandard;

  /// No description provided for @fireOsPlanFormLifestyleFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get fireOsPlanFormLifestyleFat;

  /// No description provided for @fireOsPlanFormLifestyleCoast.
  ///
  /// In en, this message translates to:
  /// **'Coast'**
  String get fireOsPlanFormLifestyleCoast;

  /// No description provided for @fireOsPlanFormLifestyleBarista.
  ///
  /// In en, this message translates to:
  /// **'Barista'**
  String get fireOsPlanFormLifestyleBarista;

  /// No description provided for @fireOsBucketsTitle.
  ///
  /// In en, this message translates to:
  /// **'Buckets'**
  String get fireOsBucketsTitle;

  /// No description provided for @fireOsBucketsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Each holding is interpreted as one of cash, defensive, growth, risk reserve, or dream.'**
  String get fireOsBucketsSubtitle;

  /// No description provided for @fireOsBucketRoleCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get fireOsBucketRoleCash;

  /// No description provided for @fireOsBucketRoleDefensive.
  ///
  /// In en, this message translates to:
  /// **'Defensive'**
  String get fireOsBucketRoleDefensive;

  /// No description provided for @fireOsBucketRoleGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get fireOsBucketRoleGrowth;

  /// No description provided for @fireOsBucketRoleRiskReserve.
  ///
  /// In en, this message translates to:
  /// **'Risk reserve'**
  String get fireOsBucketRoleRiskReserve;

  /// No description provided for @fireOsBucketRoleDream.
  ///
  /// In en, this message translates to:
  /// **'Dream'**
  String get fireOsBucketRoleDream;

  /// No description provided for @fireOsBucketStatusOnTrack.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get fireOsBucketStatusOnTrack;

  /// No description provided for @fireOsBucketStatusUnder.
  ///
  /// In en, this message translates to:
  /// **'Below target'**
  String get fireOsBucketStatusUnder;

  /// No description provided for @fireOsBucketStatusOver.
  ///
  /// In en, this message translates to:
  /// **'Over target'**
  String get fireOsBucketStatusOver;

  /// No description provided for @fireOsBucketStatusEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get fireOsBucketStatusEmpty;

  /// No description provided for @fireOsBucketNoTarget.
  ///
  /// In en, this message translates to:
  /// **'No formal target'**
  String get fireOsBucketNoTarget;

  /// No description provided for @fireOsBucketCoverage.
  ///
  /// In en, this message translates to:
  /// **'{current} / {target}'**
  String fireOsBucketCoverage(String current, String target);

  /// No description provided for @fireOsBucketAssets.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 holding} other{{count} holdings}}'**
  String fireOsBucketAssets(int count);

  /// No description provided for @fireOsBucketsManageCta.
  ///
  /// In en, this message translates to:
  /// **'Manage bucket rules'**
  String get fireOsBucketsManageCta;

  /// No description provided for @fireOsBucketsMappingTitle.
  ///
  /// In en, this message translates to:
  /// **'Bucket rules'**
  String get fireOsBucketsMappingTitle;

  /// No description provided for @fireOsBucketsMappingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the bucket each holding belongs to. Defaults are applied to anything you leave unset.'**
  String get fireOsBucketsMappingSubtitle;

  /// No description provided for @fireOsBucketsMappingSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get fireOsBucketsMappingSave;

  /// No description provided for @fireOsBucketsMappingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get fireOsBucketsMappingCancel;

  /// No description provided for @fireOsBucketsMappingDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get fireOsBucketsMappingDefault;

  /// No description provided for @fireOsBucketsMappingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No holdings to map yet. Add accounts or assets first.'**
  String get fireOsBucketsMappingEmpty;

  /// No description provided for @fireOsUnmappedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unmapped holdings'**
  String get fireOsUnmappedTitle;

  /// No description provided for @fireOsUnmappedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'These assets aren\'t part of any bucket. Map them if they should fund the plan.'**
  String get fireOsUnmappedSubtitle;

  /// No description provided for @fireOsInsightBucketDeviation.
  ///
  /// In en, this message translates to:
  /// **'Bucket below target'**
  String get fireOsInsightBucketDeviation;

  /// No description provided for @fireOsInsightBucketDeviationValue.
  ///
  /// In en, this message translates to:
  /// **'{role}: {current} / {target}'**
  String fireOsInsightBucketDeviationValue(
    String role,
    String current,
    String target,
  );

  /// No description provided for @fireOsInsightUnmappedHoldings.
  ///
  /// In en, this message translates to:
  /// **'Unmapped holdings'**
  String get fireOsInsightUnmappedHoldings;

  /// No description provided for @fireOsInsightUnmappedHoldingsValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 holding} other{{count} holdings}} not assigned to any bucket'**
  String fireOsInsightUnmappedHoldingsValue(int count);

  /// No description provided for @fireOsSimulationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Simulations'**
  String get fireOsSimulationsTitle;

  /// No description provided for @fireOsSimulationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Press a preset to see how a change to the plan moves WR / cash bucket coverage / safety level. Nothing is saved.'**
  String get fireOsSimulationsSubtitle;

  /// No description provided for @fireOsSimulationsBaselineLabel.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get fireOsSimulationsBaselineLabel;

  /// No description provided for @fireOsSimulationsPresetExpenseUp20.
  ///
  /// In en, this message translates to:
  /// **'Spending +20%'**
  String get fireOsSimulationsPresetExpenseUp20;

  /// No description provided for @fireOsSimulationsPresetExpenseDown10.
  ///
  /// In en, this message translates to:
  /// **'Spending −10%'**
  String get fireOsSimulationsPresetExpenseDown10;

  /// No description provided for @fireOsSimulationsPresetSurplusUp30.
  ///
  /// In en, this message translates to:
  /// **'Surplus +30%'**
  String get fireOsSimulationsPresetSurplusUp30;

  /// No description provided for @fireOsSimulationsPresetHalfRetireIncome.
  ///
  /// In en, this message translates to:
  /// **'Half-retire +¥5k/mo'**
  String get fireOsSimulationsPresetHalfRetireIncome;

  /// No description provided for @fireOsSimulationsPresetInflationUp1pp.
  ///
  /// In en, this message translates to:
  /// **'Inflation +1 pp'**
  String get fireOsSimulationsPresetInflationUp1pp;

  /// No description provided for @fireOsSimulationsPresetSwrTight.
  ///
  /// In en, this message translates to:
  /// **'SWR 3.5%'**
  String get fireOsSimulationsPresetSwrTight;

  /// No description provided for @fireOsSimulationsPresetCashBucketUp24.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket 24 mo'**
  String get fireOsSimulationsPresetCashBucketUp24;

  /// No description provided for @fireOsSimulationsDeltaWrPp.
  ///
  /// In en, this message translates to:
  /// **'WR {sign}{pp} pp'**
  String fireOsSimulationsDeltaWrPp(String sign, String pp);

  /// No description provided for @fireOsSimulationsDeltaWrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'WR —'**
  String get fireOsSimulationsDeltaWrUnavailable;

  /// No description provided for @fireOsSimulationsDeltaCash.
  ///
  /// In en, this message translates to:
  /// **'Cash {sign}{months} mo'**
  String fireOsSimulationsDeltaCash(String sign, String months);

  /// No description provided for @fireOsSimulationsDeltaCashUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cash —'**
  String get fireOsSimulationsDeltaCashUnavailable;

  /// No description provided for @fireOsStressTitle.
  ///
  /// In en, this message translates to:
  /// **'Stress tests'**
  String get fireOsStressTitle;

  /// No description provided for @fireOsStressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How the plan holds up under bear markets, expense surges, one-off shocks, FX swings, and cash depletion.'**
  String get fireOsStressSubtitle;

  /// No description provided for @fireOsStressEmpty.
  ///
  /// In en, this message translates to:
  /// **'Configure a FIRE plan to run stress tests.'**
  String get fireOsStressEmpty;

  /// No description provided for @fireOsStressScenarioMarketDrawdown.
  ///
  /// In en, this message translates to:
  /// **'Market drawdown −{pct}%'**
  String fireOsStressScenarioMarketDrawdown(String pct);

  /// No description provided for @fireOsStressScenarioExpenseSurge.
  ///
  /// In en, this message translates to:
  /// **'Expenses +{pct}%'**
  String fireOsStressScenarioExpenseSurge(String pct);

  /// No description provided for @fireOsStressScenarioOneOffShock.
  ///
  /// In en, this message translates to:
  /// **'One-off shock {amount}'**
  String fireOsStressScenarioOneOffShock(String amount);

  /// No description provided for @fireOsStressScenarioFxShock.
  ///
  /// In en, this message translates to:
  /// **'FX shock ±{pct}%'**
  String fireOsStressScenarioFxShock(String pct);

  /// No description provided for @fireOsStressScenarioCashDepletion.
  ///
  /// In en, this message translates to:
  /// **'Cash drawdown over {months} months'**
  String fireOsStressScenarioCashDepletion(int months);

  /// No description provided for @fireOsStressVerdictSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get fireOsStressVerdictSafe;

  /// No description provided for @fireOsStressVerdictCautious.
  ///
  /// In en, this message translates to:
  /// **'Cautious'**
  String get fireOsStressVerdictCautious;

  /// No description provided for @fireOsStressVerdictDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get fireOsStressVerdictDanger;

  /// No description provided for @fireOsStressMetricWr.
  ///
  /// In en, this message translates to:
  /// **'WR {rate}%'**
  String fireOsStressMetricWr(String rate);

  /// No description provided for @fireOsStressMetricWrInfinite.
  ///
  /// In en, this message translates to:
  /// **'WR ∞'**
  String get fireOsStressMetricWrInfinite;

  /// No description provided for @fireOsStressMetricCash.
  ///
  /// In en, this message translates to:
  /// **'Cash {months} mo'**
  String fireOsStressMetricCash(String months);

  /// No description provided for @fireOsStressMetricNetWorth.
  ///
  /// In en, this message translates to:
  /// **'NW {amount}'**
  String fireOsStressMetricNetWorth(String amount);

  /// No description provided for @fireOsReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Periodic review'**
  String get fireOsReviewTitle;

  /// No description provided for @fireOsReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deterministic monthly / quarterly / annual snapshots; the AI explains them, never invents them.'**
  String get fireOsReviewSubtitle;

  /// No description provided for @fireOsReviewKindMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get fireOsReviewKindMonthly;

  /// No description provided for @fireOsReviewKindQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get fireOsReviewKindQuarterly;

  /// No description provided for @fireOsReviewKindAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get fireOsReviewKindAnnual;

  /// No description provided for @fireOsReviewGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated {date}'**
  String fireOsReviewGeneratedAt(String date);

  /// No description provided for @fireOsReviewDiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Compared to {key}'**
  String fireOsReviewDiffTitle(String key);

  /// No description provided for @fireOsReviewDiffNoBaseline.
  ///
  /// In en, this message translates to:
  /// **'No prior snapshot to diff against — save one to see month-over-month deltas.'**
  String get fireOsReviewDiffNoBaseline;

  /// No description provided for @fireOsReviewDiffWr.
  ///
  /// In en, this message translates to:
  /// **'WR {sign}{pp} pp'**
  String fireOsReviewDiffWr(String sign, String pp);

  /// No description provided for @fireOsReviewDiffWrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'WR delta unavailable (infinite either side)'**
  String get fireOsReviewDiffWrUnavailable;

  /// No description provided for @fireOsReviewDiffNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Net worth {sign}{amount}'**
  String fireOsReviewDiffNetWorth(String sign, String amount);

  /// No description provided for @fireOsReviewDiffNetWorthCurrencyChanged.
  ///
  /// In en, this message translates to:
  /// **'Net worth currency changed — delta skipped.'**
  String get fireOsReviewDiffNetWorthCurrencyChanged;

  /// No description provided for @fireOsReviewDiffSafetyChanged.
  ///
  /// In en, this message translates to:
  /// **'Safety {from} → {to}'**
  String fireOsReviewDiffSafetyChanged(String from, String to);

  /// No description provided for @fireOsReviewDiffSafetyHeld.
  ///
  /// In en, this message translates to:
  /// **'Safety held at {level}'**
  String fireOsReviewDiffSafetyHeld(String level);

  /// No description provided for @fireOsReviewSaveSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Save snapshot'**
  String get fireOsReviewSaveSnapshot;

  /// No description provided for @fireOsReviewSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved · {key}'**
  String fireOsReviewSaved(String key);

  /// No description provided for @fireOsReviewFindingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get fireOsReviewFindingsTitle;

  /// No description provided for @fireOsReviewFindingNetWorthHealthy.
  ///
  /// In en, this message translates to:
  /// **'Net worth is positive.'**
  String get fireOsReviewFindingNetWorthHealthy;

  /// No description provided for @fireOsReviewFindingNetWorthBroken.
  ///
  /// In en, this message translates to:
  /// **'Net worth is at or below zero.'**
  String get fireOsReviewFindingNetWorthBroken;

  /// No description provided for @fireOsReviewFindingWithdrawalRateBelowSwr.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate is below SWR by {pct} pp.'**
  String fireOsReviewFindingWithdrawalRateBelowSwr(String pct);

  /// No description provided for @fireOsReviewFindingWithdrawalRateAboveSwr.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate is above SWR by {pct} pp.'**
  String fireOsReviewFindingWithdrawalRateAboveSwr(String pct);

  /// No description provided for @fireOsReviewFindingWithdrawalRateInfinite.
  ///
  /// In en, this message translates to:
  /// **'Spend exists with no investable assets.'**
  String get fireOsReviewFindingWithdrawalRateInfinite;

  /// No description provided for @fireOsReviewFindingWithinTargetCashBucket.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket covers {months} months — at target.'**
  String fireOsReviewFindingWithinTargetCashBucket(int months);

  /// No description provided for @fireOsReviewFindingBelowTargetCashBucket.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket below the {months}-month target.'**
  String fireOsReviewFindingBelowTargetCashBucket(int months);

  /// No description provided for @fireOsReviewFindingFireEtaReached.
  ///
  /// In en, this message translates to:
  /// **'FIRE target already reached.'**
  String get fireOsReviewFindingFireEtaReached;

  /// No description provided for @fireOsReviewFindingFireEtaUnreachable.
  ///
  /// In en, this message translates to:
  /// **'FIRE target not reached within 100 years.'**
  String get fireOsReviewFindingFireEtaUnreachable;

  /// No description provided for @fireOsReviewFindingFireEtaProgressing.
  ///
  /// In en, this message translates to:
  /// **'FIRE ETA at {months} months.'**
  String fireOsReviewFindingFireEtaProgressing(int months);

  /// No description provided for @fireOsReviewFindingCurrencyGap.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings without an FX rate to base currency.'**
  String fireOsReviewFindingCurrencyGap(int count);

  /// No description provided for @fireOsReviewFindingUnmappedHoldings.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings not assigned to a bucket.'**
  String fireOsReviewFindingUnmappedHoldings(int count);

  /// No description provided for @fireOsReviewFindingStressDanger.
  ///
  /// In en, this message translates to:
  /// **'Stress test \"{scenario}\" lands at danger.'**
  String fireOsReviewFindingStressDanger(String scenario);

  /// No description provided for @fireOsReviewFindingStressCautious.
  ///
  /// In en, this message translates to:
  /// **'Stress test \"{scenario}\" lands at cautious.'**
  String fireOsReviewFindingStressCautious(String scenario);

  /// No description provided for @fireOsReviewFindingStressSafe.
  ///
  /// In en, this message translates to:
  /// **'All stress tests are safe under current assumptions.'**
  String get fireOsReviewFindingStressSafe;

  /// No description provided for @fireOsInsightHighWithdrawalRate.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate above SWR'**
  String get fireOsInsightHighWithdrawalRate;

  /// No description provided for @fireOsInsightHighWithdrawalRateValue.
  ///
  /// In en, this message translates to:
  /// **'{rate}% / SWR {swr}%'**
  String fireOsInsightHighWithdrawalRateValue(String rate, String swr);

  /// No description provided for @fireOsInsightLowCashBucket.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket below target'**
  String get fireOsInsightLowCashBucket;

  /// No description provided for @fireOsInsightLowCashBucketValue.
  ///
  /// In en, this message translates to:
  /// **'{months} of {target} months'**
  String fireOsInsightLowCashBucketValue(String months, int target);

  /// No description provided for @benchmarkComparisonTitle.
  ///
  /// In en, this message translates to:
  /// **'Benchmark comparison'**
  String get benchmarkComparisonTitle;

  /// No description provided for @benchmarkComparisonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pin major indices against your net worth and read off the excess return.'**
  String get benchmarkComparisonSubtitle;

  /// No description provided for @benchmarkComparisonError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the benchmark comparison: {error}'**
  String benchmarkComparisonError(String error);

  /// No description provided for @benchmarkSeriesPortfolio.
  ///
  /// In en, this message translates to:
  /// **'Portfolio'**
  String get benchmarkSeriesPortfolio;

  /// No description provided for @benchmarkPortfolioAnnualizedLabel.
  ///
  /// In en, this message translates to:
  /// **'Portfolio annualized'**
  String get benchmarkPortfolioAnnualizedLabel;

  /// No description provided for @benchmarkAnnualizedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Annualized {value}'**
  String benchmarkAnnualizedSubtitle(String value);

  /// No description provided for @benchmarkIndexHs300.
  ///
  /// In en, this message translates to:
  /// **'CSI 300'**
  String get benchmarkIndexHs300;

  /// No description provided for @benchmarkIndexSp500.
  ///
  /// In en, this message translates to:
  /// **'S&P 500'**
  String get benchmarkIndexSp500;

  /// No description provided for @benchmarkIndexNasdaq.
  ///
  /// In en, this message translates to:
  /// **'NASDAQ'**
  String get benchmarkIndexNasdaq;

  /// No description provided for @benchmarkIndexHsi.
  ///
  /// In en, this message translates to:
  /// **'Hang Seng'**
  String get benchmarkIndexHsi;

  /// AppBar title for the rebalance page.
  ///
  /// In en, this message translates to:
  /// **'Rebalance'**
  String get rebalanceTitle;

  /// No description provided for @rebalanceSchemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Target scheme'**
  String get rebalanceSchemeTitle;

  /// No description provided for @rebalanceSchemeConservative.
  ///
  /// In en, this message translates to:
  /// **'Conservative'**
  String get rebalanceSchemeConservative;

  /// No description provided for @rebalanceSchemeBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get rebalanceSchemeBalanced;

  /// No description provided for @rebalanceSchemeAggressive.
  ///
  /// In en, this message translates to:
  /// **'Aggressive'**
  String get rebalanceSchemeAggressive;

  /// No description provided for @rebalanceSchemeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get rebalanceSchemeCustom;

  /// No description provided for @rebalanceDriftTitle.
  ///
  /// In en, this message translates to:
  /// **'Allocation drift'**
  String get rebalanceDriftTitle;

  /// No description provided for @rebalanceOverallDrift.
  ///
  /// In en, this message translates to:
  /// **'Overall drift: {value}'**
  String rebalanceOverallDrift(String value);

  /// No description provided for @rebalanceBalanced.
  ///
  /// In en, this message translates to:
  /// **'On target'**
  String get rebalanceBalanced;

  /// No description provided for @rebalanceTradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested trades'**
  String get rebalanceTradeTitle;

  /// No description provided for @rebalanceBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get rebalanceBuy;

  /// No description provided for @rebalanceSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get rebalanceSell;

  /// No description provided for @rebalanceEstimatedFees.
  ///
  /// In en, this message translates to:
  /// **'Estimated fees'**
  String get rebalanceEstimatedFees;

  /// No description provided for @rebalanceEstimatedTaxes.
  ///
  /// In en, this message translates to:
  /// **'Estimated taxes'**
  String get rebalanceEstimatedTaxes;

  /// No description provided for @rebalanceDriftAfter.
  ///
  /// In en, this message translates to:
  /// **'Drift after rebalance'**
  String get rebalanceDriftAfter;

  /// No description provided for @rebalanceExecuteAction.
  ///
  /// In en, this message translates to:
  /// **'Rebalance now'**
  String get rebalanceExecuteAction;

  /// No description provided for @rebalanceExecutionSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm rebalance'**
  String get rebalanceExecutionSheetTitle;

  /// No description provided for @rebalanceExecutionSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review 1 draft trade before continuing.} other{Review {count} draft trades before continuing.}}'**
  String rebalanceExecutionSheetSubtitle(int count);

  /// No description provided for @rebalanceExecutionCreateDrafts.
  ///
  /// In en, this message translates to:
  /// **'Create drafts'**
  String get rebalanceExecutionCreateDrafts;

  /// No description provided for @rebalanceExecutionTradeValue.
  ///
  /// In en, this message translates to:
  /// **'Suggested value'**
  String get rebalanceExecutionTradeValue;

  /// No description provided for @rebalanceExecutionDraftNote.
  ///
  /// In en, this message translates to:
  /// **'Rebalance suggestion: {direction} {category} for {amount} {currency}'**
  String rebalanceExecutionDraftNote(
    Object direction,
    Object category,
    Object amount,
    Object currency,
  );

  /// No description provided for @rebalanceEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get rebalanceEmptyTitle;

  /// No description provided for @rebalanceEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add assets to see your allocation drift and rebalance suggestions.'**
  String get rebalanceEmptyHint;

  /// No description provided for @rebalanceSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rebalance settings'**
  String get rebalanceSettingsTooltip;

  /// No description provided for @rebalanceSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get rebalanceSettingsTitle;

  /// No description provided for @rebalanceWarningThreshold.
  ///
  /// In en, this message translates to:
  /// **'Warning threshold'**
  String get rebalanceWarningThreshold;

  /// No description provided for @rebalanceCriticalThreshold.
  ///
  /// In en, this message translates to:
  /// **'Critical threshold'**
  String get rebalanceCriticalThreshold;

  /// No description provided for @rebalanceNavLink.
  ///
  /// In en, this message translates to:
  /// **'Rebalance'**
  String get rebalanceNavLink;

  /// Command palette entry that opens the rebalance page.
  ///
  /// In en, this message translates to:
  /// **'Go to Rebalance'**
  String get rebalanceCommandOpen;

  /// Command palette entry that opens the custom target allocation editor.
  ///
  /// In en, this message translates to:
  /// **'Adjust target allocation'**
  String get rebalanceCommandAdjustTarget;

  /// No description provided for @targetAllocationEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom target'**
  String get targetAllocationEditorTitle;

  /// No description provided for @targetAllocationEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tune category weights; the total must equal 100%.'**
  String get targetAllocationEditorSubtitle;

  /// No description provided for @targetAllocationEditorEditAction.
  ///
  /// In en, this message translates to:
  /// **'Custom target'**
  String get targetAllocationEditorEditAction;

  /// No description provided for @targetAllocationEditorTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total allocation'**
  String get targetAllocationEditorTotalLabel;

  /// No description provided for @targetAllocationEditorTotalHint.
  ///
  /// In en, this message translates to:
  /// **'Total must be 100%. Current total: {value}%.'**
  String targetAllocationEditorTotalHint(String value);

  /// No description provided for @targetAllocationEditorPercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get targetAllocationEditorPercentLabel;

  /// No description provided for @targetAllocationEditorRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get targetAllocationEditorRequiredError;

  /// No description provided for @targetAllocationEditorRangeError.
  ///
  /// In en, this message translates to:
  /// **'Use 0-100'**
  String get targetAllocationEditorRangeError;

  /// No description provided for @targetAllocationEditorPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Target mix'**
  String get targetAllocationEditorPreviewTitle;

  /// Header for the risk concentration alert panel on the analytics page.
  ///
  /// In en, this message translates to:
  /// **'Concentration Alerts'**
  String get riskAlertTitle;

  /// Alert title for a single asset exceeding its concentration threshold.
  ///
  /// In en, this message translates to:
  /// **'{name} overweight'**
  String riskAlertAssetTitle(String name);

  /// Alert title for a sector exceeding its concentration threshold.
  ///
  /// In en, this message translates to:
  /// **'{sector} overweight'**
  String riskAlertSectorTitle(String sector);

  /// Alert title for a region exceeding its concentration threshold.
  ///
  /// In en, this message translates to:
  /// **'{region} overweight'**
  String riskAlertRegionTitle(String region);

  /// Alert title for a currency exceeding its concentration threshold.
  ///
  /// In en, this message translates to:
  /// **'{currency} exposure'**
  String riskAlertCurrencyTitle(String currency);

  /// Subtitle showing which dimension threshold was breached.
  ///
  /// In en, this message translates to:
  /// **'{dimension} threshold: {threshold}'**
  String riskAlertThresholdBreached(String dimension, String threshold);

  /// No description provided for @riskDimensionAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get riskDimensionAsset;

  /// No description provided for @riskDimensionSector.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get riskDimensionSector;

  /// No description provided for @riskDimensionRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get riskDimensionRegion;

  /// No description provided for @riskDimensionCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get riskDimensionCurrency;

  /// No description provided for @settingsRiskSection.
  ///
  /// In en, this message translates to:
  /// **'Risk Preferences'**
  String get settingsRiskSection;

  /// No description provided for @settingsRiskAssetLabel.
  ///
  /// In en, this message translates to:
  /// **'Single asset limit'**
  String get settingsRiskAssetLabel;

  /// No description provided for @settingsRiskAssetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alert when one asset exceeds this share of total portfolio.'**
  String get settingsRiskAssetSubtitle;

  /// No description provided for @settingsRiskSectorLabel.
  ///
  /// In en, this message translates to:
  /// **'Sector limit'**
  String get settingsRiskSectorLabel;

  /// No description provided for @settingsRiskSectorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alert when one sector exceeds this share.'**
  String get settingsRiskSectorSubtitle;

  /// No description provided for @settingsRiskRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region limit'**
  String get settingsRiskRegionLabel;

  /// No description provided for @settingsRiskRegionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alert when one market / region exceeds this share.'**
  String get settingsRiskRegionSubtitle;

  /// No description provided for @settingsRiskCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency limit'**
  String get settingsRiskCurrencyLabel;

  /// No description provided for @settingsRiskCurrencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alert when one currency exposure exceeds this share.'**
  String get settingsRiskCurrencySubtitle;

  /// No description provided for @settingsRiskResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsRiskResetDefaults;

  /// No description provided for @tradeEntryAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Record trade'**
  String get tradeEntryAppBarTitle;

  /// No description provided for @tradeEntrySuccess.
  ///
  /// In en, this message translates to:
  /// **'Trade recorded'**
  String get tradeEntrySuccess;

  /// No description provided for @tradeEntryFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record trade: {error}'**
  String tradeEntryFailure(String error);

  /// No description provided for @tradeEntryQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get tradeEntryQuantityLabel;

  /// No description provided for @tradeEntryPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get tradeEntryPriceLabel;

  /// No description provided for @tradeEntryPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to fetch from market data'**
  String get tradeEntryPriceHelper;

  /// No description provided for @tradeEntryDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Trade date'**
  String get tradeEntryDateLabel;

  /// No description provided for @tradeEntryFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get tradeEntryFeeLabel;

  /// No description provided for @tradeEntryTaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tradeEntryTaxLabel;

  /// No description provided for @tradeEntryCashAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash account'**
  String get tradeEntryCashAccountLabel;

  /// No description provided for @tradeEntryCatalogLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load catalog: {error}'**
  String tradeEntryCatalogLoadError(String error);

  /// No description provided for @tradeEntryDecimalScaleHintGeneric.
  ///
  /// In en, this message translates to:
  /// **'Up to 8 decimals for stocks/ETFs, 18 for crypto'**
  String get tradeEntryDecimalScaleHintGeneric;

  /// No description provided for @tradeEntryDecimalScaleHint.
  ///
  /// In en, this message translates to:
  /// **'Up to {scale} decimal places'**
  String tradeEntryDecimalScaleHint(int scale);

  /// No description provided for @tradeTypeBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get tradeTypeBuy;

  /// No description provided for @tradeTypeSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get tradeTypeSell;

  /// No description provided for @tradeTypeTransferIn.
  ///
  /// In en, this message translates to:
  /// **'Transfer in'**
  String get tradeTypeTransferIn;

  /// No description provided for @tradeTypeTransferOut.
  ///
  /// In en, this message translates to:
  /// **'Transfer out'**
  String get tradeTypeTransferOut;

  /// No description provided for @tradeTypeValuationAdjust.
  ///
  /// In en, this message translates to:
  /// **'Valuation adjust'**
  String get tradeTypeValuationAdjust;

  /// No description provided for @tradeTypeDividend.
  ///
  /// In en, this message translates to:
  /// **'Dividend'**
  String get tradeTypeDividend;

  /// No description provided for @tradeTypeReinvest.
  ///
  /// In en, this message translates to:
  /// **'Reinvest'**
  String get tradeTypeReinvest;

  /// No description provided for @tradeTypeInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get tradeTypeInterest;

  /// No description provided for @tradeTypeDeposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get tradeTypeDeposit;

  /// No description provided for @tradeTypeWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get tradeTypeWithdraw;

  /// No description provided for @tradeTypeFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get tradeTypeFee;

  /// No description provided for @tradeTypeTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tradeTypeTax;

  /// No description provided for @tradeTypeSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get tradeTypeSplit;

  /// No description provided for @tradeTypeLiabilityPayment.
  ///
  /// In en, this message translates to:
  /// **'Loan payment'**
  String get tradeTypeLiabilityPayment;

  /// No description provided for @tradeTypeExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get tradeTypeExpense;

  /// Tooltip for the expenses list AppBar action that opens the monthly report.
  ///
  /// In en, this message translates to:
  /// **'Monthly report'**
  String get expensesReportTooltip;

  /// No description provided for @expenseFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get expenseFormCreateTitle;

  /// No description provided for @expenseFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get expenseFormEditTitle;

  /// No description provided for @expenseFormDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get expenseFormDeleteTooltip;

  /// No description provided for @expenseFormAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expenseFormAmountLabel;

  /// No description provided for @expenseFormAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than 0'**
  String get expenseFormAmountInvalid;

  /// No description provided for @expenseFormCategoryAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick a category, account, and currency'**
  String get expenseFormCategoryAccountRequired;

  /// No description provided for @expenseFormCategoriesLoading.
  ///
  /// In en, this message translates to:
  /// **'Setting up default categories, please wait…'**
  String get expenseFormCategoriesLoading;

  /// No description provided for @expenseFormCategoriesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load categories: {error}'**
  String expenseFormCategoriesLoadError(String error);

  /// No description provided for @expenseFormAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get expenseFormAccountLabel;

  /// No description provided for @expenseFormAccountsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load accounts: {error}'**
  String expenseFormAccountsLoadError(String error);

  /// No description provided for @expenseFormDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expenseFormDateLabel;

  /// No description provided for @expenseFormDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense'**
  String get expenseFormDeleteDialogTitle;

  /// No description provided for @expenseFormDeleteDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this expense? This change syncs to your other devices.'**
  String get expenseFormDeleteDialogBody;

  /// No description provided for @expenseFormNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account first'**
  String get expenseFormNoAccountsTitle;

  /// No description provided for @expenseFormNoAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Expenses need a funding account. Create one under Accounts, then come back here.'**
  String get expenseFormNoAccountsBody;

  /// No description provided for @expenseFormNoAccountsCta.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get expenseFormNoAccountsCta;

  /// No description provided for @expenseHistorySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Change history'**
  String get expenseHistorySectionTitle;

  /// No description provided for @expenseHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No changes recorded yet.'**
  String get expenseHistoryEmpty;

  /// No description provided for @expenseHistoryLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load history: {error}'**
  String expenseHistoryLoadError(String error);

  /// No description provided for @expenseHistoryEventCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get expenseHistoryEventCreated;

  /// No description provided for @expenseHistoryEventChanged.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get expenseHistoryEventChanged;

  /// No description provided for @expenseHistoryEventDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get expenseHistoryEventDeleted;

  /// No description provided for @expenseHistoryEventRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get expenseHistoryEventRestored;

  /// No description provided for @expenseHistoryCreatedBody.
  ///
  /// In en, this message translates to:
  /// **'Expense recorded.'**
  String get expenseHistoryCreatedBody;

  /// No description provided for @expenseHistoryDeletedBody.
  ///
  /// In en, this message translates to:
  /// **'Expense deleted.'**
  String get expenseHistoryDeletedBody;

  /// No description provided for @expenseHistoryRestoredBody.
  ///
  /// In en, this message translates to:
  /// **'Expense restored.'**
  String get expenseHistoryRestoredBody;

  /// No description provided for @expenseHistoryFieldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expenseHistoryFieldAmount;

  /// No description provided for @expenseHistoryFieldCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get expenseHistoryFieldCurrency;

  /// No description provided for @expenseHistoryFieldAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get expenseHistoryFieldAccount;

  /// No description provided for @expenseHistoryFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseHistoryFieldCategory;

  /// No description provided for @expenseHistoryFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expenseHistoryFieldDate;

  /// No description provided for @expenseHistoryFieldNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get expenseHistoryFieldNote;

  /// No description provided for @expenseHistoryFieldTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get expenseHistoryFieldTags;

  /// No description provided for @expenseHistoryEmptyValue.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get expenseHistoryEmptyValue;

  /// No description provided for @expenseHistoryUnknownReference.
  ///
  /// In en, this message translates to:
  /// **'(unknown)'**
  String get expenseHistoryUnknownReference;

  /// No description provided for @expenseHistoryReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String expenseHistoryReasonLabel(String reason);

  /// No description provided for @aiChatAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get aiChatAppBarTitle;

  /// No description provided for @aiChatHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Conversation history'**
  String get aiChatHistoryTooltip;

  /// No description provided for @aiChatNewSessionTooltip.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get aiChatNewSessionTooltip;

  /// No description provided for @aiChatLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to use the AI assistant.'**
  String get aiChatLoginRequired;

  /// No description provided for @aiChatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your financial assistant'**
  String get aiChatEmptyTitle;

  /// No description provided for @aiChatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Answers grounded in your holdings and ledger entries. Numbers come from your locally-synced ledger; the model never invents key figures.'**
  String get aiChatEmptyBody;

  /// No description provided for @aiChatEmptySuggestion1.
  ///
  /// In en, this message translates to:
  /// **'How much have I made in the last three months?'**
  String get aiChatEmptySuggestion1;

  /// No description provided for @aiChatEmptySuggestion2.
  ///
  /// In en, this message translates to:
  /// **'Which holdings carry the highest risk?'**
  String get aiChatEmptySuggestion2;

  /// No description provided for @aiChatEmptySuggestion3.
  ///
  /// In en, this message translates to:
  /// **'What does my industry breakdown look like?'**
  String get aiChatEmptySuggestion3;

  /// No description provided for @aiChatEmptySuggestion4.
  ///
  /// In en, this message translates to:
  /// **'What\'s my XIRR since inception?'**
  String get aiChatEmptySuggestion4;

  /// No description provided for @aiChatEmptySuggestionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Try these'**
  String get aiChatEmptySuggestionsHeader;

  /// No description provided for @aiChatBootstrappingLabel.
  ///
  /// In en, this message translates to:
  /// **'Preparing conversation…'**
  String get aiChatBootstrappingLabel;

  /// No description provided for @aiChatSessionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get aiChatSessionsHeader;

  /// No description provided for @aiChatSessionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to start your first conversation.'**
  String get aiChatSessionsEmpty;

  /// No description provided for @aiChatSessionMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get aiChatSessionMoreTooltip;

  /// No description provided for @aiChatSessionRenameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get aiChatSessionRenameAction;

  /// No description provided for @aiChatSessionRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get aiChatSessionRenameTitle;

  /// No description provided for @aiChatSessionTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get aiChatSessionTitleLabel;

  /// No description provided for @aiChatSessionDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get aiChatSessionDeleteTitle;

  /// No description provided for @aiChatSessionDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'All messages in \"{title}\" will be deleted.'**
  String aiChatSessionDeleteBody(String title);

  /// No description provided for @aiChatRelativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get aiChatRelativeJustNow;

  /// No description provided for @aiChatRelativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String aiChatRelativeMinutesAgo(int minutes);

  /// No description provided for @aiChatRelativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String aiChatRelativeHoursAgo(int hours);

  /// No description provided for @aiChatRelativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String aiChatRelativeDaysAgo(int days);

  /// No description provided for @aiChatComposerHintIdle.
  ///
  /// In en, this message translates to:
  /// **'Ask NaviWealth, e.g. \"How much did I earn last month?\"'**
  String get aiChatComposerHintIdle;

  /// No description provided for @aiChatComposerHintStreaming.
  ///
  /// In en, this message translates to:
  /// **'Generating answer…'**
  String get aiChatComposerHintStreaming;

  /// No description provided for @aiChatComposerHintFlushing.
  ///
  /// In en, this message translates to:
  /// **'Syncing local data…'**
  String get aiChatComposerHintFlushing;

  /// No description provided for @aiChatComposerSendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send (⌘/Ctrl + Enter)'**
  String get aiChatComposerSendTooltip;

  /// No description provided for @aiChatComposerStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get aiChatComposerStopTooltip;

  /// No description provided for @aiChatThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get aiChatThinking;

  /// Streaming indicator while the assistant is waiting for a tool call
  ///
  /// In en, this message translates to:
  /// **'Running {tool}'**
  String aiChatRunningTool(String tool);

  /// No description provided for @aiChatStaleSyncNotice.
  ///
  /// In en, this message translates to:
  /// **'Local data hasn\'t finished syncing; answers may lag behind your most recent edits.'**
  String get aiChatStaleSyncNotice;

  /// Footer shown when the model hit max_tokens and the visible reply is incomplete
  ///
  /// In en, this message translates to:
  /// **'Reply was cut off — output length limit reached'**
  String get aiChatTruncatedMaxTokens;

  /// Footer shown when the backend hit MAX_TOOL_ROUNDS while the model still wanted to call tools
  ///
  /// In en, this message translates to:
  /// **'Stopped — tool-call budget exhausted'**
  String get aiChatTruncatedToolBudget;

  /// Footer shown when the model returned a refusal stop reason
  ///
  /// In en, this message translates to:
  /// **'The model declined to answer'**
  String get aiChatTruncatedRefusal;

  /// Footer shown when the SSE stream ended before a done event arrived
  ///
  /// In en, this message translates to:
  /// **'Connection dropped before the reply finished'**
  String get aiChatTruncatedNetwork;

  /// Footer shown for any unrecognised or unknown stop reason
  ///
  /// In en, this message translates to:
  /// **'Reply ended unexpectedly'**
  String get aiChatTruncatedUnknown;

  /// Inline button next to the truncation footer that asks the model to continue
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get aiChatTruncatedContinue;

  /// Hidden user message sent to the model when the user taps the Continue affordance
  ///
  /// In en, this message translates to:
  /// **'Please continue.'**
  String get aiChatTruncatedContinuePrompt;

  /// No description provided for @aiChatProposalKindTrade.
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get aiChatProposalKindTrade;

  /// No description provided for @aiChatProposalKindExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get aiChatProposalKindExpense;

  /// No description provided for @aiChatProposalKindLiabilityPayment.
  ///
  /// In en, this message translates to:
  /// **'Repayment'**
  String get aiChatProposalKindLiabilityPayment;

  /// No description provided for @aiChatProposalKindAccountCreate.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get aiChatProposalKindAccountCreate;

  /// No description provided for @aiChatProposalKindAssetValuation.
  ///
  /// In en, this message translates to:
  /// **'Valuation update'**
  String get aiChatProposalKindAssetValuation;

  /// No description provided for @aiChatProposalKindFirePlanUpdate.
  ///
  /// In en, this message translates to:
  /// **'FIRE plan update'**
  String get aiChatProposalKindFirePlanUpdate;

  /// No description provided for @aiChatProposalKindFireBucketRule.
  ///
  /// In en, this message translates to:
  /// **'FIRE bucket rule'**
  String get aiChatProposalKindFireBucketRule;

  /// No description provided for @aiChatProposalKindUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get aiChatProposalKindUnknown;

  /// No description provided for @aiChatProposalPendingHeader.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation · {kind}'**
  String aiChatProposalPendingHeader(String kind);

  /// No description provided for @aiChatProposalNeedsClarificationHeader.
  ///
  /// In en, this message translates to:
  /// **'Needs clarification · {kind}'**
  String aiChatProposalNeedsClarificationHeader(String kind);

  /// No description provided for @aiChatProposalCandidatesHeading.
  ///
  /// In en, this message translates to:
  /// **'Options:'**
  String get aiChatProposalCandidatesHeading;

  /// No description provided for @aiChatProposalSummaryEdited.
  ///
  /// In en, this message translates to:
  /// **'{summary} (edited)'**
  String aiChatProposalSummaryEdited(String summary);

  /// No description provided for @aiChatProposalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get aiChatProposalConfirm;

  /// No description provided for @aiChatProposalApplying.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get aiChatProposalApplying;

  /// No description provided for @aiChatProposalEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get aiChatProposalEdit;

  /// No description provided for @aiChatProposalEditKindTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {kind}'**
  String aiChatProposalEditKindTitle(String kind);

  /// No description provided for @aiChatProposalSaveEdits.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get aiChatProposalSaveEdits;

  /// No description provided for @aiChatProposalFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String aiChatProposalFailure(String error);

  /// No description provided for @aiChatProposalUndoFailure.
  ///
  /// In en, this message translates to:
  /// **'Undo failed: {error}'**
  String aiChatProposalUndoFailure(String error);

  /// No description provided for @aiChatProposalAppliedFallback.
  ///
  /// In en, this message translates to:
  /// **'Recorded {summary}'**
  String aiChatProposalAppliedFallback(String summary);

  /// No description provided for @aiChatProposalUndoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Undid {summary}'**
  String aiChatProposalUndoneLabel(String summary);

  /// No description provided for @aiChatProposalCancelledLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: {summary}'**
  String aiChatProposalCancelledLabel(String summary);

  /// No description provided for @aiChatProposalUndoCountdown.
  ///
  /// In en, this message translates to:
  /// **'Undo ({seconds}s)'**
  String aiChatProposalUndoCountdown(int seconds);

  /// No description provided for @aiChatProposalBatchPending.
  ///
  /// In en, this message translates to:
  /// **'{count} items awaiting confirmation in this turn'**
  String aiChatProposalBatchPending(int count);

  /// No description provided for @aiChatProposalBatchConfirmAll.
  ///
  /// In en, this message translates to:
  /// **'Confirm all'**
  String get aiChatProposalBatchConfirmAll;

  /// No description provided for @aiChatFieldQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get aiChatFieldQuantity;

  /// No description provided for @aiChatFieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (leave blank to backfill from market)'**
  String get aiChatFieldPrice;

  /// No description provided for @aiChatFieldFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get aiChatFieldFee;

  /// No description provided for @aiChatFieldTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get aiChatFieldTax;

  /// No description provided for @aiChatFieldNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get aiChatFieldNote;

  /// No description provided for @aiChatFieldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get aiChatFieldAmount;

  /// No description provided for @aiChatFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date (RFC3339)'**
  String get aiChatFieldDate;

  /// No description provided for @aiChatFieldDateHint.
  ///
  /// In en, this message translates to:
  /// **'2026-04-30T12:00:00Z'**
  String get aiChatFieldDateHint;

  /// No description provided for @aiChatFieldAccountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get aiChatFieldAccountName;

  /// No description provided for @aiChatFieldInstitution.
  ///
  /// In en, this message translates to:
  /// **'Institution (optional)'**
  String get aiChatFieldInstitution;

  /// No description provided for @aiChatFieldNewValuation.
  ///
  /// In en, this message translates to:
  /// **'New valuation'**
  String get aiChatFieldNewValuation;

  /// No description provided for @aiChatRowOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get aiChatRowOperation;

  /// No description provided for @aiChatRowAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get aiChatRowAsset;

  /// No description provided for @aiChatRowAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get aiChatRowAccount;

  /// No description provided for @aiChatRowQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get aiChatRowQuantity;

  /// No description provided for @aiChatRowPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get aiChatRowPrice;

  /// No description provided for @aiChatRowFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get aiChatRowFee;

  /// No description provided for @aiChatRowDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get aiChatRowDate;

  /// No description provided for @aiChatRowNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get aiChatRowNote;

  /// No description provided for @aiChatRowAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get aiChatRowAmount;

  /// No description provided for @aiChatRowCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get aiChatRowCategory;

  /// No description provided for @aiChatRowLiability.
  ///
  /// In en, this message translates to:
  /// **'Liability'**
  String get aiChatRowLiability;

  /// No description provided for @aiChatRowRepayAccount.
  ///
  /// In en, this message translates to:
  /// **'Repayment account'**
  String get aiChatRowRepayAccount;

  /// No description provided for @aiChatRowName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get aiChatRowName;

  /// No description provided for @aiChatRowType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get aiChatRowType;

  /// No description provided for @aiChatRowCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get aiChatRowCurrency;

  /// No description provided for @aiChatRowInstitution.
  ///
  /// In en, this message translates to:
  /// **'Institution'**
  String get aiChatRowInstitution;

  /// No description provided for @aiChatRowNewValue.
  ///
  /// In en, this message translates to:
  /// **'New valuation'**
  String get aiChatRowNewValue;

  /// No description provided for @aiChatToolGetHoldings.
  ///
  /// In en, this message translates to:
  /// **'Query holdings'**
  String get aiChatToolGetHoldings;

  /// No description provided for @aiChatToolComputeXirr.
  ///
  /// In en, this message translates to:
  /// **'Compute XIRR'**
  String get aiChatToolComputeXirr;

  /// No description provided for @aiChatToolComputeNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Compute net worth'**
  String get aiChatToolComputeNetWorth;

  /// No description provided for @aiChatToolGetIndustryBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Industry breakdown'**
  String get aiChatToolGetIndustryBreakdown;

  /// No description provided for @aiChatToolGetGeoBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Region breakdown'**
  String get aiChatToolGetGeoBreakdown;

  /// No description provided for @aiChatToolGetMarketCapBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Market-cap breakdown'**
  String get aiChatToolGetMarketCapBreakdown;

  /// No description provided for @aiChatToolGetRiskAlerts.
  ///
  /// In en, this message translates to:
  /// **'Risk alerts'**
  String get aiChatToolGetRiskAlerts;

  /// No description provided for @aiChatToolFallback.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get aiChatToolFallback;

  /// No description provided for @aiChatToolInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get aiChatToolInputLabel;

  /// No description provided for @aiChatToolOutputLabel.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get aiChatToolOutputLabel;

  /// No description provided for @aiChatToolJumpAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset {id}'**
  String aiChatToolJumpAsset(String id);

  /// No description provided for @aiChatToolJumpAccount.
  ///
  /// In en, this message translates to:
  /// **'Account {id}'**
  String aiChatToolJumpAccount(String id);

  /// No description provided for @aiChatToolJumpLiability.
  ///
  /// In en, this message translates to:
  /// **'Liability {id}'**
  String aiChatToolJumpLiability(String id);

  /// No description provided for @aiChatToolShowRawJson.
  ///
  /// In en, this message translates to:
  /// **'View raw JSON'**
  String get aiChatToolShowRawJson;

  /// No description provided for @aiChatToolShowCompactView.
  ///
  /// In en, this message translates to:
  /// **'Back to compact view'**
  String get aiChatToolShowCompactView;

  /// No description provided for @aiFloatingPillLabel.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get aiFloatingPillLabel;

  /// No description provided for @aiChatSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get aiChatSheetTitle;

  /// No description provided for @aiChatSheetEmpty.
  ///
  /// In en, this message translates to:
  /// **'Ask anything about your finances.'**
  String get aiChatSheetEmpty;

  /// No description provided for @aiChatSheetExpandTooltip.
  ///
  /// In en, this message translates to:
  /// **'Expand to full screen'**
  String get aiChatSheetExpandTooltip;

  /// No description provided for @chartEmptyDefault.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get chartEmptyDefault;

  /// Default label for the shared AmountField when no caller-provided label is supplied.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get formAmountFieldLabelDefault;

  /// AmountField validator: empty input.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get formAmountFieldRequired;

  /// AmountField validator: not a parseable Decimal.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount format'**
  String get formAmountFieldInvalid;

  /// AmountField validator: negative value where the caller forbids them.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot be negative'**
  String get formAmountFieldNegativeNotAllowed;

  /// Default label for the shared NoteField.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get formNoteFieldLabelDefault;

  /// Tooltip on the icon that clears a tap-to-pick DateField.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get formDateFieldClearTooltip;

  /// DateField validator when the field is required and empty.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get formDateFieldRequired;

  /// Default label for the shared AccountPicker.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get formAccountPickerLabelDefault;

  /// AccountPicker validator when no account is selected.
  ///
  /// In en, this message translates to:
  /// **'Pick an account'**
  String get formAccountPickerRequired;

  /// Default label for the shared CurrencyPicker.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get formCurrencyPickerLabelDefault;

  /// CurrencyPicker validator when no currency is selected.
  ///
  /// In en, this message translates to:
  /// **'Pick a currency'**
  String get formCurrencyPickerRequired;

  /// Picker entry for a currency, e.g. "USD · US Dollar".
  ///
  /// In en, this message translates to:
  /// **'{code} · {name}'**
  String currencyOptionLabel(String code, String name);

  /// No description provided for @currencyNameCNY.
  ///
  /// In en, this message translates to:
  /// **'Chinese Yuan'**
  String get currencyNameCNY;

  /// No description provided for @currencyNameUSD.
  ///
  /// In en, this message translates to:
  /// **'US Dollar'**
  String get currencyNameUSD;

  /// No description provided for @currencyNameHKD.
  ///
  /// In en, this message translates to:
  /// **'Hong Kong Dollar'**
  String get currencyNameHKD;

  /// No description provided for @currencyNameEUR.
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyNameEUR;

  /// No description provided for @currencyNameJPY.
  ///
  /// In en, this message translates to:
  /// **'Japanese Yen'**
  String get currencyNameJPY;

  /// No description provided for @currencyNameGBP.
  ///
  /// In en, this message translates to:
  /// **'British Pound'**
  String get currencyNameGBP;

  /// No description provided for @currencyNameSGD.
  ///
  /// In en, this message translates to:
  /// **'Singapore Dollar'**
  String get currencyNameSGD;

  /// No description provided for @currencyNameAUD.
  ///
  /// In en, this message translates to:
  /// **'Australian Dollar'**
  String get currencyNameAUD;

  /// No description provided for @currencyNameCAD.
  ///
  /// In en, this message translates to:
  /// **'Canadian Dollar'**
  String get currencyNameCAD;

  /// No description provided for @currencyNameTWD.
  ///
  /// In en, this message translates to:
  /// **'New Taiwan Dollar'**
  String get currencyNameTWD;

  /// Default label above the expense-form category grid picker.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseCategoryPickerLabelDefault;

  /// Validator message when no expense category is selected.
  ///
  /// In en, this message translates to:
  /// **'Pick a category'**
  String get expenseCategoryPickerRequired;

  /// Legend label for the projected-valuation curve on a physical asset's trend chart.
  ///
  /// In en, this message translates to:
  /// **'Projected valuation'**
  String get physicalAssetValuationProjected;

  /// Legend label for the historical-valuation curve on a physical asset's trend chart.
  ///
  /// In en, this message translates to:
  /// **'Historical valuation'**
  String get physicalAssetValuationHistorical;

  /// Accessibility label for the physical asset valuation-trend chart.
  ///
  /// In en, this message translates to:
  /// **'Valuation trend'**
  String get physicalAssetValuationTrendSemanticLabel;

  /// Master-detail empty state for /activity/accounts at desktop width
  ///
  /// In en, this message translates to:
  /// **'Select an account on the left to edit its details.'**
  String get accountsDetailEmpty;

  /// No description provided for @accountsCreateAction.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get accountsCreateAction;

  /// No description provided for @accountsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String accountsLoadError(String error);

  /// No description provided for @accountsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Tap the bottom-right button to add one, then come back to record assets.'**
  String get accountsEmptyHint;

  /// Wealth container category — physical cash, e-wallets (Alipay, Wechat Pay, etc.)
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get accountCategoryCash;

  /// Wealth container category — bank checking / savings deposit account
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accountCategoryBank;

  /// Wealth container category — securities brokerage (stocks, ETFs, options)
  ///
  /// In en, this message translates to:
  /// **'Brokerage'**
  String get accountCategoryBroker;

  /// Wealth container category — on-chain wallet or exchange holding crypto assets
  ///
  /// In en, this message translates to:
  /// **'Crypto wallet'**
  String get accountCategoryCrypto;

  /// Wealth container category — revolving credit (credit cards, lines of credit)
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get accountCategoryCredit;

  /// Wealth container category — installment debt (mortgage, car loan, student loan)
  ///
  /// In en, this message translates to:
  /// **'Loan'**
  String get accountCategoryLoan;

  /// Wealth container category — fallback for tangible / illiquid assets (real estate, vehicle, art)
  ///
  /// In en, this message translates to:
  /// **'Other asset'**
  String get accountCategoryAsset;

  /// Wealth container category — fallback for obligations not credit / loan
  ///
  /// In en, this message translates to:
  /// **'Other liability'**
  String get accountCategoryLiability;

  /// One-line affordance shown under the Cash card in the account category picker
  ///
  /// In en, this message translates to:
  /// **'Wallets, e-wallets, physical bills'**
  String get accountCategoryCashHint;

  /// Affordance for the Bank card
  ///
  /// In en, this message translates to:
  /// **'Checking, savings, deposits'**
  String get accountCategoryBankHint;

  /// Affordance for the Brokerage card
  ///
  /// In en, this message translates to:
  /// **'Stocks, ETFs, mutual funds'**
  String get accountCategoryBrokerHint;

  /// Affordance for the Crypto card
  ///
  /// In en, this message translates to:
  /// **'On-chain wallets, exchanges'**
  String get accountCategoryCryptoHint;

  /// Affordance for the Credit card
  ///
  /// In en, this message translates to:
  /// **'Credit cards, revolving credit'**
  String get accountCategoryCreditHint;

  /// Affordance for the Loan card
  ///
  /// In en, this message translates to:
  /// **'Mortgage, car loan, student loan'**
  String get accountCategoryLoanHint;

  /// Affordance for the Other asset card
  ///
  /// In en, this message translates to:
  /// **'Real estate, vehicles, collectibles'**
  String get accountCategoryAssetHint;

  /// Affordance for the Other liability card
  ///
  /// In en, this message translates to:
  /// **'Anything you owe that isn\'t credit or loan'**
  String get accountCategoryLiabilityHint;

  /// Accounting side — asset (debit-balance). Auto-derived; only shown in debug / ledger surfaces.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get accountSideAsset;

  /// Accounting side — liability (credit-balance).
  ///
  /// In en, this message translates to:
  /// **'Liability'**
  String get accountSideLiability;

  /// Accounting side — income (system account).
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get accountSideIncome;

  /// Accounting side — expense (system account).
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get accountSideExpense;

  /// Accounting side — equity (system account, opening balance counter-postings).
  ///
  /// In en, this message translates to:
  /// **'Equity'**
  String get accountSideEquity;

  /// No description provided for @accountFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get accountFormCreateTitle;

  /// No description provided for @accountFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountFormEditTitle;

  /// No description provided for @accountFormDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get accountFormDeleteTooltip;

  /// No description provided for @accountFormDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountFormDeleteTitle;

  /// No description provided for @accountFormDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? This sync to other devices.'**
  String accountFormDeleteContent(String name);

  /// No description provided for @accountFormCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountFormCancelAction;

  /// No description provided for @accountFormDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get accountFormDeleteAction;

  /// No description provided for @accountFormTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accountFormTypeLabel;

  /// No description provided for @accountFormCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Accounting category'**
  String get accountFormCategoryLabel;

  /// No description provided for @accountFormCategoryHelper.
  ///
  /// In en, this message translates to:
  /// **'Where this account sits in the accounting identity. Defaults from the account type — change it if the suggestion doesn\'t match.'**
  String get accountFormCategoryHelper;

  /// No description provided for @accountFormNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountFormNameLabel;

  /// No description provided for @accountFormNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the account name'**
  String get accountFormNameRequired;

  /// No description provided for @accountFormInstitutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Institution'**
  String get accountFormInstitutionLabel;

  /// No description provided for @accountFormInstitutionHelper.
  ///
  /// In en, this message translates to:
  /// **'Bank / brokerage / platform (optional)'**
  String get accountFormInstitutionHelper;

  /// No description provided for @accountFormAccountNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Account number / last digits (optional)'**
  String get accountFormAccountNumberLabel;

  /// No description provided for @accountFormArchivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get accountFormArchivedTitle;

  /// No description provided for @accountFormArchivedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Archived accounts are hidden from the main list.'**
  String get accountFormArchivedSubtitle;

  /// No description provided for @accountFormSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get accountFormSaving;

  /// No description provided for @accountFormSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get accountFormSave;

  /// No description provided for @cashFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Record cash balance'**
  String get cashFormCreateTitle;

  /// No description provided for @cashFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit cash balance'**
  String get cashFormEditTitle;

  /// No description provided for @cashFormDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get cashFormDeleteTooltip;

  /// No description provided for @cashFormLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String cashFormLoadError(String error);

  /// No description provided for @cashFormNeedAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Please create a bank / cash account first.'**
  String get cashFormNeedAccountHint;

  /// No description provided for @cashFormCreateAccountAction.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get cashFormCreateAccountAction;

  /// No description provided for @cashFormBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get cashFormBalanceLabel;

  /// No description provided for @cashFormNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname (optional)'**
  String get cashFormNicknameLabel;

  /// No description provided for @cashFormNicknameHelper.
  ///
  /// In en, this message translates to:
  /// **'e.g. CMB HKD demand, Yu’e Bao'**
  String get cashFormNicknameHelper;

  /// No description provided for @cashFormSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get cashFormSaving;

  /// No description provided for @cashFormSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cashFormSave;

  /// No description provided for @cashFormDuplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash already exists'**
  String get cashFormDuplicateTitle;

  /// No description provided for @cashFormDuplicateMessage.
  ///
  /// In en, this message translates to:
  /// **'This account already has a cash balance recorded. Would you like to edit the existing one instead?'**
  String get cashFormDuplicateMessage;

  /// No description provided for @cashFormDuplicateCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cashFormDuplicateCancel;

  /// No description provided for @cashFormDuplicateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit existing'**
  String get cashFormDuplicateEdit;

  /// No description provided for @manualAssetDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete asset'**
  String get manualAssetDeleteTitle;

  /// No description provided for @manualAssetDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete this asset record?'**
  String get manualAssetDeleteContent;

  /// No description provided for @manualAssetDeleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get manualAssetDeleteCancel;

  /// No description provided for @manualAssetDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get manualAssetDeleteConfirm;

  /// Activity page segmented control: activity feed tab
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityFeedTab;

  /// Activity feed empty state message
  ///
  /// In en, this message translates to:
  /// **'No activity yet — record a transfer, expense, or trade and it will appear here.'**
  String get activityFeedEmpty;

  /// Trade entry: warning dialog title when buy would overdraw cash
  ///
  /// In en, this message translates to:
  /// **'Cash balance will go negative'**
  String get tradeEntryCashOverdrawTitle;

  /// Trade entry: warning dialog body when buy would overdraw cash. {amount} is the resulting balance.
  ///
  /// In en, this message translates to:
  /// **'After this purchase, your cash account balance will be {amount}. Do you want to proceed?'**
  String tradeEntryCashOverdrawMessage(Object amount);

  /// Trade entry: warning dialog confirm button
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get tradeEntryCashOverdrawProceed;

  /// Activity feed date section: today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get activityFeedToday;

  /// Activity feed date section: yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get activityFeedYesterday;

  /// Activity feed date section: this week
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get activityFeedThisWeek;

  /// Activity feed date section: earlier
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get activityFeedEarlier;

  /// Accounts page app bar: transfer action tooltip
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get accountsTransferAction;

  /// Accounts page app bar: journal action tooltip
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get accountsJournalAction;

  /// Expense list page app bar: report action tooltip
  ///
  /// In en, this message translates to:
  /// **'Expense Report'**
  String get expenseReportTitle;

  /// Plan page: FIRE card title
  ///
  /// In en, this message translates to:
  /// **'FIRE'**
  String get planFireTitle;

  /// Plan page: FIRE card subtitle
  ///
  /// In en, this message translates to:
  /// **'Financial independence calculator'**
  String get planFireSubtitle;

  /// Plan page: analytics card title
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get planAnalyticsTitle;

  /// Plan page: analytics card subtitle
  ///
  /// In en, this message translates to:
  /// **'Portfolio allocation analysis'**
  String get planAnalyticsSubtitle;

  /// Plan page: rebalance card title
  ///
  /// In en, this message translates to:
  /// **'Rebalance'**
  String get planRebalanceTitle;

  /// Plan page: rebalance card subtitle
  ///
  /// In en, this message translates to:
  /// **'Portfolio drift & rebalancing'**
  String get planRebalanceSubtitle;

  /// Plan page summary chip shown when a card summary cannot load.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get planSummaryLoadError;

  /// Plan page FIRE summary chip when no FIRE goal is configured.
  ///
  /// In en, this message translates to:
  /// **'Set a target'**
  String get planSummaryConfigureGoal;

  /// Plan page FIRE progress summary chip.
  ///
  /// In en, this message translates to:
  /// **'Progress {value}'**
  String planSummaryProgress(String value);

  /// Plan page FIRE estimated time-to-target summary chip.
  ///
  /// In en, this message translates to:
  /// **'ETA {value}'**
  String planSummaryEta(String value);

  /// Plan page analytics summary chip when there are no risk alerts.
  ///
  /// In en, this message translates to:
  /// **'No concentration alerts'**
  String get planSummaryNoRiskAlerts;

  /// Plan page analytics summary chip for concentration alert count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 alert} other {{count} alerts}}'**
  String planSummaryRiskAlerts(int count);

  /// Plan page analytics summary chip for critical concentration alert count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 critical} other {{count} critical}}'**
  String planSummaryCriticalAlerts(int count);

  /// Plan page rebalance summary chip when there is no portfolio snapshot.
  ///
  /// In en, this message translates to:
  /// **'No portfolio data'**
  String get planSummaryNoPortfolio;

  /// Plan page rebalance summary chip when allocation is within thresholds.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get planSummaryBalanced;

  /// Plan page rebalance summary chip for overall drift.
  ///
  /// In en, this message translates to:
  /// **'Drift {value}'**
  String planSummaryDrift(String value);

  /// Plan page rebalance summary chip for suggested trade count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 trade} other {{count} trades}}'**
  String planSummaryTrades(int count);

  /// Settings section header for account-level preferences
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// Settings section header for backup/restore
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsDataSection;

  /// Settings tile that opens the backup page
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsDataTitle;

  /// Settings tile subtitle for backup
  ///
  /// In en, this message translates to:
  /// **'Export or import encrypted data backups'**
  String get settingsDataSubtitle;

  /// Settings tile that opens the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'AI privacy'**
  String get settingsAiPrivacyTitle;

  /// Settings tile subtitle for the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'Pick what the AI can send to the cloud'**
  String get settingsAiPrivacySubtitle;

  /// Title of the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'AI privacy'**
  String get aiPrivacyTitle;

  /// Intro copy on the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'Choose how much detail the AI can see when it leaves the device. You can change this at any time.'**
  String get aiPrivacyIntro;

  /// Radio label: amounts can go to the cloud
  ///
  /// In en, this message translates to:
  /// **'Amounts allowed'**
  String get aiPrivacyModeAmountsAllowedLabel;

  /// Radio description: amounts can go to the cloud
  ///
  /// In en, this message translates to:
  /// **'Send exact amounts and account context. Best answer quality.'**
  String get aiPrivacyModeAmountsAllowedDescription;

  /// Radio label: amounts go up as ballpark buckets
  ///
  /// In en, this message translates to:
  /// **'Amounts bucketed'**
  String get aiPrivacyModeAmountsBucketedLabel;

  /// Radio description for bucketed amounts
  ///
  /// In en, this message translates to:
  /// **'Round amounts to the nearest order of magnitude before sending. Cloud sees patterns but not exact numbers.'**
  String get aiPrivacyModeAmountsBucketedDescription;

  /// Radio label: amounts never leave the device
  ///
  /// In en, this message translates to:
  /// **'Amounts stay local'**
  String get aiPrivacyModeAmountsLocalLabel;

  /// Radio description for local-only amounts
  ///
  /// In en, this message translates to:
  /// **'Only intent and category names leave the device. Cloud answers narrow to qualitative tips.'**
  String get aiPrivacyModeAmountsLocalDescription;

  /// Toggle label for masking account names
  ///
  /// In en, this message translates to:
  /// **'Mask account / institution names'**
  String get aiPrivacyMaskAccountsLabel;

  /// Toggle description for masking account names
  ///
  /// In en, this message translates to:
  /// **'Replace bank and broker names with anonymous IDs before they\'re sent.'**
  String get aiPrivacyMaskAccountsDescription;

  /// Title of the first-launch privacy onboarding sheet
  ///
  /// In en, this message translates to:
  /// **'Pick your AI privacy posture'**
  String get aiPrivacyOnboardingTitle;

  /// Body copy of the first-launch privacy onboarding sheet
  ///
  /// In en, this message translates to:
  /// **'NaviWealth\'s AI is local-first. When it needs to use the cloud, this setting decides what it can send. You can change it later in Settings.'**
  String get aiPrivacyOnboardingBody;

  /// Confirm button on the privacy onboarding sheet
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get aiPrivacyOnboardingConfirm;

  /// Section header above the list of undo-able AI changes on the transparency page
  ///
  /// In en, this message translates to:
  /// **'Pending AI changes'**
  String get aiTransparencyUndoSectionTitle;

  /// Empty state for the pending-undo section
  ///
  /// In en, this message translates to:
  /// **'No pending AI changes.'**
  String get aiTransparencyUndoEmpty;

  /// Per-row undo button on the transparency page
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get aiTransparencyUndoAction;

  /// Settings section header for developer tools
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get settingsDeveloperSection;

  /// Settings tile that opens the log viewer
  ///
  /// In en, this message translates to:
  /// **'App Logs'**
  String get settingsLogsTitle;

  /// Settings tile subtitle for log viewer
  ///
  /// In en, this message translates to:
  /// **'View real-time diagnostic logs'**
  String get settingsLogsSubtitle;

  /// Backup page: export tile title
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get backupExportTitle;

  /// Backup page: export tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Create an encrypted backup of all your data'**
  String get backupExportSubtitle;

  /// Backup page: import tile title
  ///
  /// In en, this message translates to:
  /// **'Import Backup'**
  String get backupImportTitle;

  /// Backup page: import tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Restore data from a backup file'**
  String get backupImportSubtitle;

  /// Backup dialog: passphrase field label
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get backupPassphraseLabel;

  /// Backup dialog: passphrase field hint
  ///
  /// In en, this message translates to:
  /// **'Enter a passphrase to encrypt the backup'**
  String get backupPassphraseHint;

  /// Backup dialog: empty passphrase error
  ///
  /// In en, this message translates to:
  /// **'Passphrase is required'**
  String get backupPassphraseRequired;

  /// Backup dialog: restore confirmation title
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get backupConfirmRestoreTitle;

  /// Backup dialog: restore confirmation message
  ///
  /// In en, this message translates to:
  /// **'This will replace ALL local data with the contents of the backup. This cannot be undone. Continue?'**
  String get backupConfirmRestoreMessage;

  /// Backup dialog: restore button
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupConfirmRestoreAction;

  /// Backup dialog: export button
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get backupExportAction;

  /// Backup dialog: cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get backupCancelAction;

  /// Backup progress: exporting
  ///
  /// In en, this message translates to:
  /// **'Encrypting backup…'**
  String get backupExportProgress;

  /// Backup progress: importing
  ///
  /// In en, this message translates to:
  /// **'Restoring backup…'**
  String get backupImportProgress;

  /// Backup toast: export success
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully'**
  String get backupExportSuccess;

  /// Backup toast: import success with row count
  ///
  /// In en, this message translates to:
  /// **'Backup restored successfully. {count} rows imported.'**
  String backupImportSuccess(int count);

  /// Backup error: wrong passphrase
  ///
  /// In en, this message translates to:
  /// **'Wrong passphrase or corrupt backup file'**
  String get backupWrongPassphrase;

  /// Backup error: schema too new
  ///
  /// In en, this message translates to:
  /// **'This backup was created with a newer version of NaviWealth. Please update the app first.'**
  String get backupSchemaTooNew;

  /// Backup error: invalid file format
  ///
  /// In en, this message translates to:
  /// **'Invalid backup file'**
  String get backupInvalidFile;

  /// Backup error: file picker failure
  ///
  /// In en, this message translates to:
  /// **'Could not read the selected file'**
  String get backupFilePickerError;

  /// Backup dialog: restore passphrase hint
  ///
  /// In en, this message translates to:
  /// **'Enter the backup passphrase'**
  String get backupRestorePassphraseHint;

  /// Log viewer page: clear logs tooltip
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logViewerClearTooltip;

  /// Activity feed: error loading journal entries
  ///
  /// In en, this message translates to:
  /// **'Failed to load feed: {error}'**
  String activityFeedLoadError(String error);

  /// Expense form: toast when existing expense fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load expense. Create a new entry instead.'**
  String get expenseFormLoadError;

  /// Accounts page AppBar: journal history tooltip
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get accountsJournalTooltip;

  /// Accounts page AppBar: new transfer tooltip
  ///
  /// In en, this message translates to:
  /// **'New transfer'**
  String get accountsTransferTooltip;

  /// Account form: parent account tree picker label
  ///
  /// In en, this message translates to:
  /// **'Parent account (optional)'**
  String get accountFormParentLabel;

  /// Account form: parent account helper text
  ///
  /// In en, this message translates to:
  /// **'Group this account under another in the tree.'**
  String get accountFormParentHelper;

  /// Account form: tooltip to clear parent selection
  ///
  /// In en, this message translates to:
  /// **'Make top-level'**
  String get accountFormMakeTopLevelTooltip;

  /// Account form: icon picker section heading
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get accountFormIconHeading;

  /// Account form: tooltip for the no-icon chip
  ///
  /// In en, this message translates to:
  /// **'No icon'**
  String get accountFormNoIconTooltip;

  /// Account form: color picker section heading
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get accountFormColorHeading;

  /// Account form: tooltip for the no-color swatch
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get accountFormNoColorTooltip;

  /// Transfer form page: AppBar title
  ///
  /// In en, this message translates to:
  /// **'New transfer'**
  String get transferTitle;

  /// Transfer form: error loading accounts
  ///
  /// In en, this message translates to:
  /// **'Failed to load accounts: {error}'**
  String transferLoadError(String error);

  /// Transfer form: source account picker label
  ///
  /// In en, this message translates to:
  /// **'From account'**
  String get transferFromLabel;

  /// Transfer form: destination account picker label
  ///
  /// In en, this message translates to:
  /// **'To account'**
  String get transferToLabel;

  /// Transfer form: empty field validator
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get transferValidationRequired;

  /// Transfer form: source and dest are the same
  ///
  /// In en, this message translates to:
  /// **'Pick a different account'**
  String get transferValidationDifferentAccount;

  /// Transfer form: amount field label (single currency)
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get transferAmountLabel;

  /// Transfer form: amount field label with currency
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String transferAmountWithCurrencyLabel(String currency);

  /// Transfer form: destination amount label for cross-currency
  ///
  /// In en, this message translates to:
  /// **'To amount ({currency})'**
  String transferToAmountLabel(String currency);

  /// Transfer form: helper when no FX rate exists
  ///
  /// In en, this message translates to:
  /// **'No FX rate on file — enter the converted amount.'**
  String get transferFxRateHelper;

  /// Transfer form: helper for editing auto-filled rate
  ///
  /// In en, this message translates to:
  /// **'Edit to override the auto-filled rate.'**
  String get transferFxRateEditHelper;

  /// Transfer form: date field label
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get transferDateLabel;

  /// Transfer form: preview section title
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transferPreviewTitle;

  /// Transfer form: submit button text
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transferSubmitAction;

  /// Transfer form: FX rate display
  ///
  /// In en, this message translates to:
  /// **'Rate: 1 {from} = {rate} {to}'**
  String transferRateLabel(String from, String rate, String to);

  /// Transfer form: server rejection error
  ///
  /// In en, this message translates to:
  /// **'Transfer rejected: {message}'**
  String transferRejectedError(String message);

  /// Transfer form: generic transfer failure
  ///
  /// In en, this message translates to:
  /// **'Transfer failed: {error}'**
  String transferFailedError(String error);

  /// Transfer form: retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get transferRetryLabel;

  /// Journal list page: AppBar title
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalTitle;

  /// Journal list page: error loading entries
  ///
  /// In en, this message translates to:
  /// **'Failed to load journal: {error}'**
  String journalLoadError(String error);

  /// Journal list page: empty state message
  ///
  /// In en, this message translates to:
  /// **'No journal entries yet — record a transfer, expense, or trade and it will land here.'**
  String get journalEmptyHint;

  /// Entry kind badge: trade label
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get entryKindTrade;

  /// Entry kind badge: transfer label
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get entryKindTransfer;

  /// Entry kind badge: income label
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get entryKindIncome;

  /// Entry kind badge: expense label
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get entryKindExpense;

  /// Entry kind badge: payment label
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get entryKindPayment;

  /// Entry kind badge: adjustment label
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get entryKindAdjustment;

  /// Entry kind badge: opening label
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get entryKindOpening;

  /// Entry kind badge: other label
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get entryKindOther;

  /// Entry kind badge: generic entry label
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get entryKindEntry;

  /// Entry kind badge: accessibility semantic label
  ///
  /// In en, this message translates to:
  /// **'Journal entry · {kind}'**
  String entryKindSemanticLabel(String kind);

  /// AI chat: error message when request is cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get chatCancelled;

  /// AI chat: default session title
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get chatNewSession;

  /// AI chat: system notice about context truncation
  ///
  /// In en, this message translates to:
  /// **'{count} earlier messages were folded to stay within the context limit.'**
  String chatContextTruncated(int count);

  /// Expense report page: AppBar title
  ///
  /// In en, this message translates to:
  /// **'Expense Report'**
  String get expenseReportAppBarTitle;

  /// Expense report page: load error
  ///
  /// In en, this message translates to:
  /// **'Failed to load report: {error}'**
  String expenseReportLoadError(String error);

  /// Expense report: range chip — this month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get expenseReportRangeThisMonth;

  /// Expense report: range chip — last 3 months
  ///
  /// In en, this message translates to:
  /// **'Last 3 months'**
  String get expenseReportRangeLast3Months;

  /// Expense report: range chip — last 6 months
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get expenseReportRangeLast6Months;

  /// Expense report: range chip — last 12 months
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get expenseReportRangeLast12Months;

  /// Expense report: range chip — custom
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get expenseReportRangeCustom;

  /// Expense report: summary card heading
  ///
  /// In en, this message translates to:
  /// **'Total expenses'**
  String get expenseReportTotalExpenses;

  /// Expense report: monthly average metric label
  ///
  /// In en, this message translates to:
  /// **'Monthly avg'**
  String get expenseReportMonthlyAverage;

  /// Expense report: entry count metric label
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get expenseReportEntryCount;

  /// Expense report: category count metric label
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get expenseReportCategoryCount;

  /// Expense report: warning about skipped FX entries
  ///
  /// In en, this message translates to:
  /// **'{count} expenses excluded — missing FX rate.'**
  String expenseReportSkippedFx(int count);

  /// Expense report: info line about base currency
  ///
  /// In en, this message translates to:
  /// **'Base currency {currency} · monthly avg over {months} months'**
  String expenseReportBaseCurrency(String currency, int months);

  /// Expense report: category pie chart section title
  ///
  /// In en, this message translates to:
  /// **'Category share'**
  String get expenseReportCategoryShare;

  /// Expense report: fallback category name
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get expenseReportUncategorized;

  /// Expense report: empty state
  ///
  /// In en, this message translates to:
  /// **'No expenses in this period.'**
  String get expenseReportNoExpenses;

  /// Expense report: chart bar month label
  ///
  /// In en, this message translates to:
  /// **'{month}月'**
  String expenseReportMonthLabel(int month);

  /// Expense report: monthly trend chart section title
  ///
  /// In en, this message translates to:
  /// **'Monthly trend'**
  String get expenseReportMonthlyTrend;

  /// Expense report: chart series name
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenseReportSeriesExpenses;

  /// Expense report: chart accessibility label
  ///
  /// In en, this message translates to:
  /// **'Monthly expense trend'**
  String get expenseReportMonthlyTrendSemantic;

  /// Expense report: category detail section title
  ///
  /// In en, this message translates to:
  /// **'Category detail'**
  String get expenseReportCategoryDetail;

  /// Expense report: entry count per category
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String expenseReportItemCount(int count);

  /// Expense list: search field hint
  ///
  /// In en, this message translates to:
  /// **'Search by note'**
  String get expenseListSearchHint;

  /// Expense list: filter chip — all categories
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get expenseListAllCategories;

  /// Expense list: grouping chip — month
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get expenseListGroupMonth;

  /// Expense list: grouping chip — week
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get expenseListGroupWeek;

  /// Expense list: group total label
  ///
  /// In en, this message translates to:
  /// **'Total {amount}'**
  String expenseListTotal(String amount);

  /// Expense list: fallback category name
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get expenseListUncategorized;

  /// Expense list: empty state when filtered
  ///
  /// In en, this message translates to:
  /// **'No matching expenses.'**
  String get expenseListEmptyFiltered;

  /// Expense list: empty state default
  ///
  /// In en, this message translates to:
  /// **'No expenses yet. Tap the + button to start tracking.'**
  String get expenseListEmptyDefault;

  /// Expense list: month group header
  ///
  /// In en, this message translates to:
  /// **'{year} 年 {month} 月'**
  String expenseListMonthGroup(int year, int month);

  /// Expense list: week group header
  ///
  /// In en, this message translates to:
  /// **'{year} 年第 {week} 周'**
  String expenseListWeekGroup(int year, int week);

  /// Asset detail page: generic load error
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String assetDetailLoadError(String error);

  /// Asset detail page: asset not found state
  ///
  /// In en, this message translates to:
  /// **'Asset not found or deleted'**
  String get assetDetailNotFound;

  /// Asset detail page: unsupported type state
  ///
  /// In en, this message translates to:
  /// **'This asset type does not support manual editing'**
  String get assetDetailUnsupportedType;

  /// Asset detail: toast — no metadata match
  ///
  /// In en, this message translates to:
  /// **'No matching metadata found'**
  String get assetDetailNoMetadataMatch;

  /// Asset detail: toast — metadata filled
  ///
  /// In en, this message translates to:
  /// **'Metadata synced'**
  String get assetDetailMetadataSynced;

  /// Asset detail: toast — metadata already current
  ///
  /// In en, this message translates to:
  /// **'Metadata is up to date'**
  String get assetDetailMetadataUpToDate;

  /// Asset detail: toast — no network
  ///
  /// In en, this message translates to:
  /// **'Network unavailable — cannot sync metadata'**
  String get assetDetailNetworkUnavailable;

  /// Asset detail: sync metadata button tooltip
  ///
  /// In en, this message translates to:
  /// **'Sync metadata'**
  String get assetDetailSyncMetadataTooltip;

  /// Asset detail: new trade button label
  ///
  /// In en, this message translates to:
  /// **'New trade'**
  String get assetDetailNewTradeLabel;

  /// Asset detail: fallback for unknown market
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get assetDetailUnknown;

  /// Asset detail: holdings section load error
  ///
  /// In en, this message translates to:
  /// **'Holdings load failed: {error}'**
  String assetDetailHoldingsLoadError(String error);

  /// Asset detail: holdings card heading
  ///
  /// In en, this message translates to:
  /// **'Holdings'**
  String get assetDetailHoldingsTitle;

  /// Asset detail: current quantity metric
  ///
  /// In en, this message translates to:
  /// **'Current qty'**
  String get assetDetailCurrentQuantity;

  /// Asset detail: average cost metric
  ///
  /// In en, this message translates to:
  /// **'Avg cost'**
  String get assetDetailAverageCost;

  /// Asset detail: current market value metric
  ///
  /// In en, this message translates to:
  /// **'Market value'**
  String get assetDetailCurrentMarketValue;

  /// Asset detail: info when price is unavailable
  ///
  /// In en, this message translates to:
  /// **'Price unavailable — market value shows as zero'**
  String get assetDetailPriceUnavailable;

  /// Asset detail: P&L section load error
  ///
  /// In en, this message translates to:
  /// **'P&L load failed: {error}'**
  String assetDetailPnLLoadError(String error);

  /// Asset detail: P&L card heading
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss'**
  String get assetDetailPnLTitle;

  /// Asset detail: unrealized P&L label
  ///
  /// In en, this message translates to:
  /// **'Unrealized P&L'**
  String get assetDetailUnrealizedPnL;

  /// Asset detail: base currency info
  ///
  /// In en, this message translates to:
  /// **'Base currency: {currency}'**
  String assetDetailBaseCurrency(String currency);

  /// Asset detail: today's change metric
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get assetDetailTodayChange;

  /// Asset detail: stale quote status
  ///
  /// In en, this message translates to:
  /// **'Quote stale'**
  String get assetDetailQuoteStale;

  /// Asset detail: quote unavailable status
  ///
  /// In en, this message translates to:
  /// **'Quote unavailable'**
  String get assetDetailQuoteUnavailable;

  /// Asset detail: 30-day trend chart heading
  ///
  /// In en, this message translates to:
  /// **'30-day trend'**
  String get assetDetailTrend30d;

  /// Asset detail: info when no market is linked
  ///
  /// In en, this message translates to:
  /// **'This asset is not linked to a market — no trend to display'**
  String get assetDetailNoMarketLinked;

  /// Asset detail: trend chart load error
  ///
  /// In en, this message translates to:
  /// **'Could not load quote: {error}'**
  String assetDetailTrendLoadError(String error);

  /// Asset detail: chart series — close price
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get assetDetailSeriesClosePrice;

  /// Asset detail: chart series — cost basis line
  ///
  /// In en, this message translates to:
  /// **'Cost basis'**
  String get assetDetailSeriesCostBasis;

  /// Asset detail: chart accessibility label
  ///
  /// In en, this message translates to:
  /// **'30-day close price trend'**
  String get assetDetailTrendSemanticLabel;

  /// Asset detail: stale quote badge text
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get assetDetailStaleBadge;

  /// Expense report: pie chart accessibility label
  ///
  /// In en, this message translates to:
  /// **'Category share'**
  String get assetDetailCategoryShareSemantic;

  /// Deposit form: validation — maturity date required
  ///
  /// In en, this message translates to:
  /// **'Term deposits require a maturity date'**
  String get depositMaturityRequired;

  /// Deposit form: delete dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete deposit'**
  String get depositDeleteTitle;

  /// Deposit form: delete dialog body
  ///
  /// In en, this message translates to:
  /// **'Delete this deposit record?'**
  String get depositDeleteBody;

  /// Deposit form: AppBar title (create)
  ///
  /// In en, this message translates to:
  /// **'Record deposit'**
  String get depositCreateTitle;

  /// Deposit form: AppBar title (edit)
  ///
  /// In en, this message translates to:
  /// **'Edit deposit'**
  String get depositEditTitle;

  /// Deposit form: delete button tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get depositDeleteTooltip;

  /// Deposit form: term deposit chip
  ///
  /// In en, this message translates to:
  /// **'Term'**
  String get depositTypeTerm;

  /// Deposit form: demand deposit chip
  ///
  /// In en, this message translates to:
  /// **'Demand'**
  String get depositTypeDemand;

  /// Deposit form: name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get depositNameLabel;

  /// Deposit form: name field helper
  ///
  /// In en, this message translates to:
  /// **'e.g. CMB 1-year term, ICBC demand savings'**
  String get depositNameHelper;

  /// Deposit form: name validator
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get depositNameRequired;

  /// Deposit form: principal field label
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get depositPrincipalLabel;

  /// Deposit form: interest rate field label
  ///
  /// In en, this message translates to:
  /// **'Annual rate (%)'**
  String get depositRateLabel;

  /// Deposit form: rate field helper
  ///
  /// In en, this message translates to:
  /// **'e.g. 3.25 means 3.25%'**
  String get depositRateHelper;

  /// Deposit form: rate validator — empty
  ///
  /// In en, this message translates to:
  /// **'Enter the interest rate'**
  String get depositRateRequired;

  /// Deposit form: rate validator — bad format
  ///
  /// In en, this message translates to:
  /// **'Invalid rate format'**
  String get depositRateInvalid;

  /// Deposit form: rate validator — negative
  ///
  /// In en, this message translates to:
  /// **'Rate cannot be negative'**
  String get depositRateNegative;

  /// Deposit form: value date field label
  ///
  /// In en, this message translates to:
  /// **'Value date'**
  String get depositValueDateLabel;

  /// Deposit form: maturity date field label
  ///
  /// In en, this message translates to:
  /// **'Maturity date'**
  String get depositMaturityDateLabel;

  /// Deposit form: current valuation field label
  ///
  /// In en, this message translates to:
  /// **'Current valuation (optional)'**
  String get depositCurrentValuationLabel;

  /// Deposit form: valuation field helper
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use principal as current valuation'**
  String get depositCurrentValuationHelper;

  /// Deposit form: auto-renew switch title
  ///
  /// In en, this message translates to:
  /// **'Auto-renew'**
  String get depositAutoRenewTitle;

  /// Deposit form: auto-renew switch subtitle
  ///
  /// In en, this message translates to:
  /// **'On maturity you\'ll be prompted to re-register; no new deposit is created automatically'**
  String get depositAutoRenewSubtitle;

  /// Deposit form: empty state when no bank account exists
  ///
  /// In en, this message translates to:
  /// **'Please create a bank account first.'**
  String get depositNoAccountHint;

  /// Deposit form: create account button
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get depositCreateAccountAction;

  /// Wealth product form: delete dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete wealth product'**
  String get wealthProductDeleteTitle;

  /// Wealth product form: delete dialog body
  ///
  /// In en, this message translates to:
  /// **'Delete this wealth product record?'**
  String get wealthProductDeleteBody;

  /// Wealth product form: AppBar title (create)
  ///
  /// In en, this message translates to:
  /// **'Record wealth product'**
  String get wealthProductCreateTitle;

  /// Wealth product form: AppBar title (edit)
  ///
  /// In en, this message translates to:
  /// **'Edit wealth product'**
  String get wealthProductEditTitle;

  /// Wealth product form: delete button tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get wealthProductDeleteTooltip;

  /// Wealth product form: empty state hint
  ///
  /// In en, this message translates to:
  /// **'Please create a bank / brokerage account first.'**
  String get wealthProductNoAccountHint;

  /// Wealth product form: create account button
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get wealthProductCreateAccountAction;

  /// Wealth product form: name field label
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get wealthProductNameLabel;

  /// Wealth product form: name validator
  ///
  /// In en, this message translates to:
  /// **'Enter the product name'**
  String get wealthProductNameRequired;

  /// Wealth product form: issuer field label
  ///
  /// In en, this message translates to:
  /// **'Issuer (optional)'**
  String get wealthProductIssuerLabel;

  /// Wealth product form: code field label
  ///
  /// In en, this message translates to:
  /// **'Product code (optional)'**
  String get wealthProductCodeLabel;

  /// Wealth product form: amount field label
  ///
  /// In en, this message translates to:
  /// **'Subscription amount'**
  String get wealthProductAmountLabel;

  /// Wealth product form: expected return field label
  ///
  /// In en, this message translates to:
  /// **'Expected annual return (%)'**
  String get wealthProductExpectedReturnLabel;

  /// Wealth product form: return field helper
  ///
  /// In en, this message translates to:
  /// **'e.g. 4.5 means 4.5%'**
  String get wealthProductExpectedReturnHelper;

  /// Wealth product form: return validator — empty
  ///
  /// In en, this message translates to:
  /// **'Enter expected return'**
  String get wealthProductExpectedReturnRequired;

  /// Wealth product form: return validator — bad format
  ///
  /// In en, this message translates to:
  /// **'Invalid format'**
  String get wealthProductInvalidFormat;

  /// Wealth product form: value date field label
  ///
  /// In en, this message translates to:
  /// **'Value date'**
  String get wealthProductValueDateLabel;

  /// Wealth product form: maturity date field label
  ///
  /// In en, this message translates to:
  /// **'Maturity date (optional)'**
  String get wealthProductMaturityDateLabel;

  /// Wealth product form: valuation field label
  ///
  /// In en, this message translates to:
  /// **'Current valuation (manual)'**
  String get wealthProductValuationLabel;

  /// Wealth product form: valuation field helper
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use subscription amount as current valuation'**
  String get wealthProductValuationHelper;

  /// Manual security: CN A-shares market label
  ///
  /// In en, this message translates to:
  /// **'A-shares'**
  String get manualSecurityMarketCnA;

  /// Manual security: Hong Kong market label
  ///
  /// In en, this message translates to:
  /// **'HK stocks'**
  String get manualSecurityMarketHk;

  /// Manual security: US market label
  ///
  /// In en, this message translates to:
  /// **'US stocks'**
  String get manualSecurityMarketUs;

  /// Manual security: crypto market label
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get manualSecurityMarketCrypto;

  /// Manual security: stock type label
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get manualSecurityTypeStock;

  /// Manual security: ETF type label
  ///
  /// In en, this message translates to:
  /// **'ETF'**
  String get manualSecurityTypeEtf;

  /// Manual security: mutual fund type label
  ///
  /// In en, this message translates to:
  /// **'Mutual fund'**
  String get manualSecurityTypeMutualFund;

  /// Manual security: bond type label
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get manualSecurityTypeBond;

  /// Manual security: crypto type label
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get manualSecurityTypeCrypto;

  /// Manual security: toast — empty input
  ///
  /// In en, this message translates to:
  /// **'Enter a code or name first'**
  String get manualSecurityEnterCodeOrName;

  /// Manual security: toast — no network
  ///
  /// In en, this message translates to:
  /// **'Network unavailable — use manual entry'**
  String get manualSecurityNetworkUnavailable;

  /// Manual security: toast — no results
  ///
  /// In en, this message translates to:
  /// **'No matches found — use manual entry'**
  String get manualSecurityNoMatch;

  /// Manual security: toast — import success
  ///
  /// In en, this message translates to:
  /// **'Metadata imported from network'**
  String get manualSecurityImported;

  /// Manual security: match dialog title
  ///
  /// In en, this message translates to:
  /// **'Select a match'**
  String get manualSecuritySelectMatchTitle;

  /// Manual security: bottom sheet title
  ///
  /// In en, this message translates to:
  /// **'Add security manually'**
  String get manualSecuritySheetTitle;

  /// Manual security: sheet description
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Tap \'Import from network\' to optionally fill fields from Yahoo / CoinGecko metadata.'**
  String get manualSecuritySheetDescription;

  /// Manual security: code field label
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get manualSecurityCodeLabel;

  /// Manual security: code validator — empty
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get manualSecurityCodeRequired;

  /// Manual security: code validator — colon
  ///
  /// In en, this message translates to:
  /// **'Code cannot contain \':\''**
  String get manualSecurityCodeNoColon;

  /// Manual security: import button label
  ///
  /// In en, this message translates to:
  /// **'Import from network'**
  String get manualSecurityImportAction;

  /// Manual security: import button loading label
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get manualSecurityImporting;

  /// Manual security: name field label
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get manualSecurityNameLabel;

  /// Manual security: market dropdown label
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get manualSecurityMarketLabel;

  /// Manual security: type dropdown label
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get manualSecurityTypeLabel;

  /// Manual security: ISIN field label
  ///
  /// In en, this message translates to:
  /// **'ISIN (optional)'**
  String get manualSecurityIsinLabel;

  /// Manual security: add button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get manualSecurityAddAction;

  /// Local securities picker: default search label
  ///
  /// In en, this message translates to:
  /// **'Asset search'**
  String get localSecuritiesSearchLabel;

  /// Local securities picker: search hint
  ///
  /// In en, this message translates to:
  /// **'Enter code, name, or pinyin'**
  String get localSecuritiesSearchHint;

  /// Local securities picker: validator
  ///
  /// In en, this message translates to:
  /// **'Select an asset'**
  String get localSecuritiesValidationRequired;

  /// Local securities picker: my assets section header
  ///
  /// In en, this message translates to:
  /// **'My assets'**
  String get localSecuritiesMyAssets;

  /// Local securities picker: catalog section header
  ///
  /// In en, this message translates to:
  /// **'Local catalog'**
  String get localSecuritiesCatalog;

  /// Local securities picker: manual add option
  ///
  /// In en, this message translates to:
  /// **'Not found? Add manually'**
  String get localSecuritiesManualAdd;

  /// Local securities picker: use search query as code
  ///
  /// In en, this message translates to:
  /// **'Use \"{query}\" as code'**
  String localSecuritiesUseQueryAsCode(String query);

  /// Dashboard insight label: FIRE plan
  ///
  /// In en, this message translates to:
  /// **'FIRE'**
  String get dashboardInsightFireLabel;

  /// Dashboard FIRE insight value when at least one year remains
  ///
  /// In en, this message translates to:
  /// **'{years}y {months}m to go'**
  String dashboardInsightFireToGoYears(int years, int months);

  /// Dashboard FIRE insight value when less than one year remains
  ///
  /// In en, this message translates to:
  /// **'{months}m to go'**
  String dashboardInsightFireToGoMonths(int months);

  /// Dashboard FIRE insight value when goal is reached
  ///
  /// In en, this message translates to:
  /// **'Goal reached'**
  String get dashboardInsightFireReached;

  /// Dashboard insight label: rebalance drift
  ///
  /// In en, this message translates to:
  /// **'Portfolio drift'**
  String get dashboardInsightDriftLabel;

  /// Dashboard drift direction: overweight
  ///
  /// In en, this message translates to:
  /// **'over'**
  String get dashboardInsightDriftOver;

  /// Dashboard drift direction: underweight
  ///
  /// In en, this message translates to:
  /// **'under'**
  String get dashboardInsightDriftUnder;

  /// Dashboard drift insight value
  ///
  /// In en, this message translates to:
  /// **'{category} {direction} {points}pp'**
  String dashboardInsightDriftValue(
    String category,
    String direction,
    int points,
  );

  /// Dashboard insight label: upcoming deposit maturities
  ///
  /// In en, this message translates to:
  /// **'Maturities'**
  String get dashboardInsightMaturityLabel;

  /// Dashboard deposit maturity insight value
  ///
  /// In en, this message translates to:
  /// **'{count} deposits due in {days}d'**
  String dashboardInsightMaturityValue(int count, int days);

  /// Dashboard insight label: expense anomaly
  ///
  /// In en, this message translates to:
  /// **'Expense trend'**
  String get dashboardInsightAnomalyLabel;

  /// Dashboard expense anomaly insight value
  ///
  /// In en, this message translates to:
  /// **'Projected {percent}'**
  String dashboardInsightAnomalyValue(String percent);

  /// Dashboard insight label: same merchant + amount within ±2 days
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate charge'**
  String get dashboardInsightDuplicateChargeLabel;

  /// Dashboard duplicate-charge insight value
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 pair} other{{count} pairs}} totaling {amount}'**
  String dashboardInsightDuplicateChargeValue(int count, String amount);

  /// Dashboard insight label: prior-month net-worth summary, fired in the first week of a new month
  ///
  /// In en, this message translates to:
  /// **'Last month recap'**
  String get dashboardInsightMonthlySummaryLabel;

  /// Monthly summary insight value when net worth grew
  ///
  /// In en, this message translates to:
  /// **'Net worth grew {amount}'**
  String dashboardInsightMonthlySummaryUp(String amount);

  /// Monthly summary insight value when net worth declined
  ///
  /// In en, this message translates to:
  /// **'Net worth shrank {amount}'**
  String dashboardInsightMonthlySummaryDown(String amount);

  /// Monthly summary insight value when net worth was unchanged
  ///
  /// In en, this message translates to:
  /// **'Net worth was flat'**
  String get dashboardInsightMonthlySummaryFlat;

  /// Insight card action: expand inline detail
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get dashboardInsightActionExpand;

  /// Insight card action: open the command palette with the insight as context
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get dashboardInsightActionAsk;

  /// Insight card action: hide this insight kind on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dashboardInsightActionDismiss;

  /// Portfolio view switcher: assets list
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get portfolioViewAssets;

  /// Portfolio view switcher: by account
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get portfolioViewAccount;

  /// Portfolio view switcher: by currency
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get portfolioViewCurrency;

  /// Portfolio view switcher: by asset class
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get portfolioViewClass;

  /// Portfolio aggregate row item count
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String portfolioAggregateItems(int count);

  /// Portfolio by-currency row native currency total
  ///
  /// In en, this message translates to:
  /// **'Native {amount}'**
  String portfolioCurrencyNative(String amount);

  /// Portfolio by-account fallback group
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get portfolioUnassignedAccount;

  /// Activity feed add action label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get activityAddAction;

  /// Activity feed filter action title
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get activityFeedFilterTitle;

  /// Activity feed filter clear action
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get activityFeedFilterClear;

  /// Activity feed filter kind section
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get activityFeedFilterKind;

  /// Activity feed filter account section
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get activityFeedFilterAccount;

  /// Empty state under the account multi-select when the user has no accounts
  ///
  /// In en, this message translates to:
  /// **'No accounts yet — add one from the Accounts tab.'**
  String get activityFeedFilterAccountEmpty;

  /// Activity feed filter date range section header
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get activityFeedFilterDateRange;

  /// Date range pill — current week (Mon → today)
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get activityFeedFilterRangeThisWeek;

  /// Date range pill — current calendar month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get activityFeedFilterRangeThisMonth;

  /// Date range pill — previous calendar month
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get activityFeedFilterRangeLastMonth;

  /// Date range pill — current calendar year
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get activityFeedFilterRangeThisYear;

  /// Date range pill that opens the platform date range picker
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get activityFeedFilterRangeCustom;

  /// Activity feed filter date shortcut
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get activityFeedFilterThisMonth;

  /// Activity feed empty state when filters are active
  ///
  /// In en, this message translates to:
  /// **'No activity matches these filters.'**
  String get activityFeedFilteredEmpty;

  /// Activity feed pagination button
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get activityFeedLoadMore;

  /// Activity feed pagination complete text
  ///
  /// In en, this message translates to:
  /// **'All activity loaded'**
  String get activityFeedAllLoaded;

  /// Web-only backup and restore security warning banner
  ///
  /// In en, this message translates to:
  /// **'Web local storage is not SQLCipher-encrypted. Backup files are encrypted with your password; avoid long-term storage of sensitive accounts in the web app.'**
  String get backupWebSecurityWarning;

  /// Shared form: saving button label
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get formSaving;

  /// Shared form: save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get formSave;

  /// Settings tile that opens the sync status page
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSyncTitle;

  /// Subtitle for the sync settings tile
  ///
  /// In en, this message translates to:
  /// **'View sync state and last activity'**
  String get settingsSyncSubtitle;

  /// App bar title on the sync status page
  ///
  /// In en, this message translates to:
  /// **'Sync Status'**
  String get syncStatusTitle;

  /// Tooltip on the manual sync icon button
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncStatusRefreshNow;

  /// Shown when the status stream itself errors
  ///
  /// In en, this message translates to:
  /// **'Could not read sync status: {error}'**
  String syncStatusBusError(String error);

  /// Hero card title before the first sync cycle has run
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncStatusHeadlineIdle;

  /// Hero card title while a sync cycle is in flight
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncStatusHeadlineSyncing;

  /// Hero card title when the last sync succeeded
  ///
  /// In en, this message translates to:
  /// **'All synced'**
  String get syncStatusHeadlineOnline;

  /// Hero card title when the last sync failed with a network error
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncStatusHeadlineOffline;

  /// Hero card title when the last sync failed with a non-recoverable error
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncStatusHeadlineFailed;

  /// Hero card subtitle when last_success_at is unknown
  ///
  /// In en, this message translates to:
  /// **'No successful sync yet on this device'**
  String get syncStatusSubtitleNeverSynced;

  /// Hero card subtitle showing how long ago the last successful sync ran
  ///
  /// In en, this message translates to:
  /// **'Last synced {when}'**
  String syncStatusSubtitleLastSynced(String when);

  /// Relative time chip — under a minute ago
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get syncStatusJustNow;

  /// Relative time chip — minutes
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 minute ago} other{{n} minutes ago}}'**
  String syncStatusMinutesAgo(int n);

  /// Relative time chip — hours
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 hour ago} other{{n} hours ago}}'**
  String syncStatusHoursAgo(int n);

  /// Relative time chip — days
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 day ago} other{{n} days ago}}'**
  String syncStatusDaysAgo(int n);

  /// Section header for the outbox depth card
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get syncStatusPendingHeader;

  /// Outbox card title while depth is loading
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get syncStatusPendingLoading;

  /// Outbox card title when nothing is queued
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get syncStatusPendingNone;

  /// Outbox card title when local ops are queued
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 change waiting} other{{n} changes waiting}}'**
  String syncStatusPendingCount(int n);

  /// Outbox card caption when there are pending ops
  ///
  /// In en, this message translates to:
  /// **'Local edits queued for the next push'**
  String get syncStatusPendingCaption;

  /// Outbox card caption when nothing is queued
  ///
  /// In en, this message translates to:
  /// **'All local edits have been pushed to the server'**
  String get syncStatusPendingCaptionEmpty;

  /// Outbox card trailing action button label
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncStatusActionSyncNow;

  /// Section header for the last-error card
  ///
  /// In en, this message translates to:
  /// **'Last error'**
  String get syncStatusErrorHeader;

  /// Section header for the diagnostics card
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get syncStatusDetailsHeader;

  /// Diagnostics row label for the raw state name
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get syncStatusDetailState;

  /// Diagnostics row label for the last status-event timestamp
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get syncStatusDetailUpdatedAt;

  /// Diagnostics row label for this device id
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get syncStatusDetailDevice;

  /// Diagnostics row label for the persisted last_pulled_hlc
  ///
  /// In en, this message translates to:
  /// **'Pull cursor'**
  String get syncStatusDetailCursor;

  /// Diagnostics cursor placeholder before any pull has run
  ///
  /// In en, this message translates to:
  /// **'not set'**
  String get syncStatusDetailCursorUnset;

  /// Diagnostics row label for the API base URL (debug only)
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get syncStatusDetailEndpoint;

  /// Section header for the per-table row counters (debug builds only)
  ///
  /// In en, this message translates to:
  /// **'Local row counts (debug)'**
  String get syncStatusLocalCountsHeader;

  /// Diagnostic counter: non-system accounts
  ///
  /// In en, this message translates to:
  /// **'Accounts (user)'**
  String get syncStatusLocalAccountsUser;

  /// Diagnostic counter: bootstrap system accounts
  ///
  /// In en, this message translates to:
  /// **'Accounts (system)'**
  String get syncStatusLocalAccountsSystem;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Journal entries'**
  String get syncStatusLocalJournalEntries;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Postings'**
  String get syncStatusLocalPostings;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get syncStatusLocalAssets;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Prices'**
  String get syncStatusLocalPrices;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get syncStatusLocalLiabilities;

  /// Diagnostic counter
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get syncStatusLocalTags;

  /// Hero card subtitle while a cycle is in flight
  ///
  /// In en, this message translates to:
  /// **'Syncing changes…'**
  String get syncStatusHeroSyncing;

  /// Stat tile label — outbox depth
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get syncStatusStatPending;

  /// Stat tile label — total local rows across syncable tables
  ///
  /// In en, this message translates to:
  /// **'Local rows'**
  String get syncStatusStatLocal;

  /// Stat tile label — when the engine last succeeded
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get syncStatusStatLastSync;

  /// Stat tile placeholder before first successful sync
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get syncStatusStatNever;

  /// Compact relative-time chip when the event is under a minute old
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get syncStatusStatJustNow;

  /// No description provided for @aiReplyChipCompareLastPeriod.
  ///
  /// In en, this message translates to:
  /// **'Compare to previous period'**
  String get aiReplyChipCompareLastPeriod;

  /// No description provided for @aiReplyChipFindKeyDrivers.
  ///
  /// In en, this message translates to:
  /// **'Find the key drivers'**
  String get aiReplyChipFindKeyDrivers;

  /// No description provided for @aiReplyChipHowControlSpending.
  ///
  /// In en, this message translates to:
  /// **'How do I rein in spending?'**
  String get aiReplyChipHowControlSpending;

  /// No description provided for @aiReplyChipViewHoldings.
  ///
  /// In en, this message translates to:
  /// **'View holdings detail'**
  String get aiReplyChipViewHoldings;

  /// No description provided for @aiReplyChipComputeXirr.
  ///
  /// In en, this message translates to:
  /// **'Compute XIRR'**
  String get aiReplyChipComputeXirr;

  /// No description provided for @aiReplyChipCompareLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Compare to last month'**
  String get aiReplyChipCompareLastMonth;

  /// No description provided for @aiReplyChipMarketDrop20.
  ///
  /// In en, this message translates to:
  /// **'What if the market drops 20%?'**
  String get aiReplyChipMarketDrop20;

  /// No description provided for @aiReplyChipMonthlySaveDelta.
  ///
  /// In en, this message translates to:
  /// **'How much more to save each month?'**
  String get aiReplyChipMonthlySaveDelta;

  /// No description provided for @aiReplyChipRebalanceAdvice.
  ///
  /// In en, this message translates to:
  /// **'Rebalancing advice'**
  String get aiReplyChipRebalanceAdvice;

  /// No description provided for @aiReplyChipCompareAnotherPeriod.
  ///
  /// In en, this message translates to:
  /// **'Compare another period'**
  String get aiReplyChipCompareAnotherPeriod;

  /// No description provided for @aiReplyChipBiggestCategoryChange.
  ///
  /// In en, this message translates to:
  /// **'Which categories changed most?'**
  String get aiReplyChipBiggestCategoryChange;

  /// No description provided for @aiReplyChipTrendSummary.
  ///
  /// In en, this message translates to:
  /// **'Give a trend summary'**
  String get aiReplyChipTrendSummary;

  /// No description provided for @aiReplyChipHandleInsight.
  ///
  /// In en, this message translates to:
  /// **'How should I handle this?'**
  String get aiReplyChipHandleInsight;

  /// No description provided for @aiReplyChipSimilarHistory.
  ///
  /// In en, this message translates to:
  /// **'Show similar past cases'**
  String get aiReplyChipSimilarHistory;

  /// No description provided for @aiReplyChipActionPlan.
  ///
  /// In en, this message translates to:
  /// **'Give me a concrete action plan'**
  String get aiReplyChipActionPlan;

  /// No description provided for @aiReplyChipRiskConcentration.
  ///
  /// In en, this message translates to:
  /// **'Risk concentration check'**
  String get aiReplyChipRiskConcentration;

  /// No description provided for @aiReplyChipUnusedSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Which subscriptions go unused?'**
  String get aiReplyChipUnusedSubscriptions;

  /// No description provided for @aiReplyChipCancelPriciestSub.
  ///
  /// In en, this message translates to:
  /// **'Cancel the priciest subscription?'**
  String get aiReplyChipCancelPriciestSub;

  /// No description provided for @aiReplyChipUnmatchedRefunds.
  ///
  /// In en, this message translates to:
  /// **'Unmatched refunds'**
  String get aiReplyChipUnmatchedRefunds;

  /// No description provided for @aiReplyChipCompareBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Compare with benchmark'**
  String get aiReplyChipCompareBenchmark;

  /// No description provided for @aiReplyChipForecast12mo.
  ///
  /// In en, this message translates to:
  /// **'12-month forecast'**
  String get aiReplyChipForecast12mo;

  /// No description provided for @aiReplyChipExpandDetails.
  ///
  /// In en, this message translates to:
  /// **'Expand details'**
  String get aiReplyChipExpandDetails;

  /// No description provided for @aiReplyChipActionPlanGeneric.
  ///
  /// In en, this message translates to:
  /// **'Give an action plan'**
  String get aiReplyChipActionPlanGeneric;

  /// No description provided for @aiReplyChipVsLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Compare with last month'**
  String get aiReplyChipVsLastMonth;

  /// No description provided for @aiCapsuleExpandFallback.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get aiCapsuleExpandFallback;

  /// Dashboard insight label: Layer 4 ingest queue has parsed drafts awaiting confirmation
  ///
  /// In en, this message translates to:
  /// **'Records to confirm'**
  String get dashboardInsightIngestQueueLabel;

  /// Dashboard ingest-queue insight value
  ///
  /// In en, this message translates to:
  /// **'{count} parsed · {fresh} ready to add'**
  String dashboardInsightIngestQueueValue(int count, int fresh);

  /// Dashboard insight label shown when this month cashflow is negative
  ///
  /// In en, this message translates to:
  /// **'Cashflow gap'**
  String get dashboardInsightCashFlowDeficitLabel;

  /// Dashboard insight detail for current-month negative cashflow
  ///
  /// In en, this message translates to:
  /// **'This month is short {amount}'**
  String dashboardInsightCashFlowDeficitValue(String amount);

  /// Layer 4 ingest review page title
  ///
  /// In en, this message translates to:
  /// **'Review entries'**
  String get ingestReviewTitle;

  /// Ingest review: accounts stream error
  ///
  /// In en, this message translates to:
  /// **'Failed to load accounts: {error}'**
  String ingestAccountsLoadError(String error);

  /// Ingest review: drafts stream error
  ///
  /// In en, this message translates to:
  /// **'Failed to load the queue: {error}'**
  String ingestQueueLoadError(String error);

  /// Ingest review: paying-account selector label
  ///
  /// In en, this message translates to:
  /// **'Paid from'**
  String get ingestExpenseAccountLabel;

  /// Ingest review: batch-confirm button (new drafts only)
  ///
  /// In en, this message translates to:
  /// **'Confirm all · new only ({count})'**
  String ingestConfirmAllFresh(int count);

  /// Ingest review: no account chosen warning
  ///
  /// In en, this message translates to:
  /// **'Pick a paying account first'**
  String get ingestSelectAccountFirst;

  /// Ingest review: confirm service unavailable
  ///
  /// In en, this message translates to:
  /// **'Service not ready yet'**
  String get ingestServiceNotReady;

  /// Ingest review: single confirm success toast
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get ingestRecorded;

  /// Ingest review: batch confirm success toast
  ///
  /// In en, this message translates to:
  /// **'Recorded {count}'**
  String ingestRecordedN(int count);

  /// Ingest paste dialog title
  ///
  /// In en, this message translates to:
  /// **'Paste statement text'**
  String get ingestPasteTitle;

  /// Ingest paste dialog text-field hint
  ///
  /// In en, this message translates to:
  /// **'Paste CSV / statement text\ne.g. 2026-05-10,Starbucks,-38.00,CNY'**
  String get ingestPasteHint;

  /// Ingest paste dialog confirm button
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get ingestParseAction;

  /// Ingest review: parse produced zero rows
  ///
  /// In en, this message translates to:
  /// **'No recognizable transactions'**
  String get ingestNoTransactions;

  /// Ingest review: parse result summary toast
  ///
  /// In en, this message translates to:
  /// **'Parsed {total} · {fresh} new · {dup} possible dup'**
  String ingestParseSummary(int total, int fresh, int dup);

  /// Ingest review: draft with no category hint
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get ingestUncategorized;

  /// Ingest review: dismiss one draft
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get ingestSkip;

  /// Ingest review: confirm one draft
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get ingestConfirm;

  /// Ingest dedup verdict: no match
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get ingestVerdictNew;

  /// Ingest dedup verdict: probable duplicate
  ///
  /// In en, this message translates to:
  /// **'Likely dup'**
  String get ingestVerdictLikely;

  /// Ingest dedup verdict: exact duplicate
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get ingestVerdictDuplicate;

  /// Ingest review empty-state title
  ///
  /// In en, this message translates to:
  /// **'Nothing to confirm'**
  String get ingestEmptyTitle;

  /// Ingest review empty-state body
  ///
  /// In en, this message translates to:
  /// **'Paste statement / CSV text — it is parsed into drafts,\nreconciled, and confirmed here.'**
  String get ingestEmptyBody;

  /// Ingest review: open paste dialog
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get ingestPasteAction;

  /// Ingest review: pick a receipt / statement / CSV file
  ///
  /// In en, this message translates to:
  /// **'Import file'**
  String get ingestImportFileAction;

  /// Ingest review: snap a receipt with the camera
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get ingestCameraAction;

  /// Settings tile and page title for AI trace transparency
  ///
  /// In en, this message translates to:
  /// **'AI transparency'**
  String get settingsAiTransparencyTitle;

  /// Settings tile subtitle for AI trace transparency
  ///
  /// In en, this message translates to:
  /// **'View detailed traces from recent AI calls'**
  String get settingsAiTransparencySubtitle;

  /// Settings tile and page title for on-device LLM credentials
  ///
  /// In en, this message translates to:
  /// **'On-device AI · Bring your own key'**
  String get settingsAiLlmTitle;

  /// Settings tile subtitle for on-device LLM credentials
  ///
  /// In en, this message translates to:
  /// **'Manage multiple provider keys and switch local direct connections'**
  String get settingsAiLlmSubtitle;

  /// Toast shown when saving an LLM profile without a usable key
  ///
  /// In en, this message translates to:
  /// **'Enter an API key first'**
  String get aiLlmMissingApiKey;

  /// Toast after saving an LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Saved to secure device storage'**
  String get aiLlmSaved;

  /// Toast after activating an LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Switched'**
  String get aiLlmSwitched;

  /// Toast after deleting an LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Removed from this device'**
  String get aiLlmRemoved;

  /// Empty state on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'No providers yet. Add an API key to run AI through a local direct connection.'**
  String get aiLlmEmpty;

  /// Button and editor title for adding an LLM provider
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get aiLlmAddProvider;

  /// Editor title for updating an LLM provider
  ///
  /// In en, this message translates to:
  /// **'Edit provider'**
  String get aiLlmEditProvider;

  /// Tag on the active LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get aiLlmActiveTag;

  /// Hint on an inactive LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Tap to switch'**
  String get aiLlmTapToSwitch;

  /// LLM profile name field label
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get aiLlmNameLabel;

  /// LLM profile name field hint
  ///
  /// In en, this message translates to:
  /// **'Anthropic official / company gateway …'**
  String get aiLlmNameHint;

  /// LLM profile provider picker label
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiLlmProviderLabel;

  /// API key field hint when editing a profile that already has a stored key
  ///
  /// In en, this message translates to:
  /// **'Configured · leave blank to keep unchanged'**
  String get aiLlmStoredKeyHint;

  /// LLM profile base URL field label
  ///
  /// In en, this message translates to:
  /// **'Custom Base URL (optional)'**
  String get aiLlmBaseUrlLabel;

  /// LLM profile model field label
  ///
  /// In en, this message translates to:
  /// **'Model (optional; blank uses default)'**
  String get aiLlmModelLabel;

  /// Button label for probing an LLM provider
  ///
  /// In en, this message translates to:
  /// **'Test connectivity'**
  String get aiLlmTestConnectivity;

  /// Button label while probing an LLM provider
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get aiLlmTesting;

  /// Button label while saving an LLM provider
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get aiLlmSaving;

  /// Intro copy on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'Use your own LLM API key so AI runs through a local direct connection to the provider. You can save multiple providers and switch anytime. Keys stay in this device\'s secure storage (Keychain/Keystore); they are not uploaded, synced, or backed up. Your provider account owns cost and rate limits.'**
  String get aiLlmIntro;

  /// Unsupported-platform card title on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'This platform does not support on-device direct connections'**
  String get aiLlmUnsupportedTitle;

  /// Unsupported-platform card body on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'Bring-your-own-key on-device AI works on native platforms (iOS / Android / macOS / Windows / Linux) with system secure storage. Web continues to use cloud AI.'**
  String get aiLlmUnsupportedBody;

  /// Status line when an LLM provider is active
  ///
  /// In en, this message translates to:
  /// **'Active: {name} · local direct connection'**
  String aiLlmStatusActive(String name);

  /// Status line when profiles exist but no active usable profile is selected
  ///
  /// In en, this message translates to:
  /// **'Providers saved, but none selected'**
  String get aiLlmStatusSavedNoActive;

  /// Status line when secure storage read fails
  ///
  /// In en, this message translates to:
  /// **'Could not read secure storage'**
  String get aiLlmStatusReadFailed;

  /// Status line when there is no usable LLM provider
  ///
  /// In en, this message translates to:
  /// **'Not configured · no on-device AI available'**
  String get aiLlmStatusNotConfigured;

  /// Provider picker label for Anthropic protocol
  ///
  /// In en, this message translates to:
  /// **'{provider} (Anthropic Messages protocol)'**
  String aiLlmAnthropicProtocol(String provider);

  /// Provider picker label for OpenAI protocol
  ///
  /// In en, this message translates to:
  /// **'{provider} (Chat Completions protocol)'**
  String aiLlmOpenAiProtocol(String provider);

  /// AI transparency list empty state after applying the error filter
  ///
  /// In en, this message translates to:
  /// **'No records match the current filter'**
  String get aiTransparencyFilteredEmpty;

  /// AI transparency page load error
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String aiTransparencyLoadError(String error);

  /// AI trace verbose capture setting title
  ///
  /// In en, this message translates to:
  /// **'Detailed capture'**
  String get aiTransparencyVerboseTitle;

  /// AI trace verbose capture setting subtitle
  ///
  /// In en, this message translates to:
  /// **'Record each step\'s input and output (local only; cleaned after 30 days)'**
  String get aiTransparencyVerboseSubtitle;

  /// Toggle state label: on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get aiTransparencyToggleOn;

  /// Toggle state label: off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiTransparencyToggleOff;

  /// AI transparency aggregate title
  ///
  /// In en, this message translates to:
  /// **'Last {count} calls'**
  String aiTransparencyRecentCalls(int count);

  /// AI trace error-count pill
  ///
  /// In en, this message translates to:
  /// **'Errors {count}'**
  String aiTransparencyErrors(int count);

  /// AI transparency page empty state
  ///
  /// In en, this message translates to:
  /// **'No AI call records yet.\nAfter the next conversation, the full trace will appear here.'**
  String get aiTransparencyEmpty;

  /// AI trace tool-count pill
  ///
  /// In en, this message translates to:
  /// **'Tools {count}'**
  String aiTransparencyToolsCount(int count);

  /// AI trace stale read-model count pill
  ///
  /// In en, this message translates to:
  /// **'Stale x{count}'**
  String aiTransparencyStaleCount(int count);

  /// Fallback title for an AI trace without an intent label
  ///
  /// In en, this message translates to:
  /// **'(unnamed turn)'**
  String get aiTransparencyUnnamedTurn;

  /// AI transparency detail page title
  ///
  /// In en, this message translates to:
  /// **'Call chain'**
  String get aiTransparencyDetailTitle;

  /// AI trace detail not-found state
  ///
  /// In en, this message translates to:
  /// **'This call record was not found'**
  String get aiTransparencyTraceNotFound;

  /// AI trace detail message for old trace records without spans
  ///
  /// In en, this message translates to:
  /// **'This record has no execution chain (it predates the span model and will be cleaned automatically within 30 days).'**
  String get aiTransparencyNoSpans;

  /// AI trace detail header summary
  ///
  /// In en, this message translates to:
  /// **'{count} events · started {time}'**
  String aiTransparencyEventSummary(int count, String time);

  /// AI trace round-count pill
  ///
  /// In en, this message translates to:
  /// **'{count} rounds'**
  String aiTraceRoundsCount(int count);

  /// AI span detail notice when verbose payload capture is disabled
  ///
  /// In en, this message translates to:
  /// **'input/output was not captured (compact mode). Turn on Detailed capture on the AI transparency page; new calls will record each step\'s parameters and return values for debugging.'**
  String get aiTraceNoPayloadCaptured;

  /// Chat error shown when no usable on-device AI runtime is available
  ///
  /// In en, this message translates to:
  /// **'AI requires your own API key in Settings before it can run. The model connection is made directly from this device, and requests/data do not pass through our servers. On-device AI is not supported on web yet.'**
  String get aiChatDeviceUnavailable;

  /// AI context timeframe passed from the expense form
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get expenseFormAiTimeframeRecent90Days;

  /// Title of the confirm dialog shown when leaving a form with unsaved input
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get unsavedChangesTitle;

  /// Body of the unsaved-changes confirm dialog
  ///
  /// In en, this message translates to:
  /// **'Your edits will be lost if you leave now.'**
  String get unsavedChangesBody;

  /// Destructive confirm action — leave and lose the edits
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get unsavedChangesDiscard;

  /// Cancel action of the unsaved-changes dialog — stay on the form
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get unsavedChangesKeepEditing;

  /// Transient hint shown on the first back press at the Home tab root
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// Investment watchlist page title
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get watchlistTitle;

  /// Accounts hub entry subtitle for watchlist
  ///
  /// In en, this message translates to:
  /// **'Track symbols and local price alerts'**
  String get watchlistAccountsEntrySubtitle;

  /// Add a symbol to the watchlist
  ///
  /// In en, this message translates to:
  /// **'Add symbol'**
  String get watchlistAddAction;

  /// Watchlist add sheet title
  ///
  /// In en, this message translates to:
  /// **'Add to watchlist'**
  String get watchlistAddTitle;

  /// Watchlist alert edit sheet title
  ///
  /// In en, this message translates to:
  /// **'Alerts for {symbol}'**
  String watchlistEditAlertTitle(String symbol);

  /// Watchlist empty state title
  ///
  /// In en, this message translates to:
  /// **'No watchlist symbols'**
  String get watchlistEmptyTitle;

  /// Watchlist empty state body
  ///
  /// In en, this message translates to:
  /// **'Add a ticker to poll prices cache-first and trigger threshold alerts while the page is open.'**
  String get watchlistEmptyBody;

  /// Watchlist symbol input label
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get watchlistSymbolField;

  /// Watchlist market picker label
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get watchlistMarketField;

  /// Watchlist upper price alert input
  ///
  /// In en, this message translates to:
  /// **'Alert above'**
  String get watchlistAlertAboveField;

  /// Watchlist lower price alert input
  ///
  /// In en, this message translates to:
  /// **'Alert below'**
  String get watchlistAlertBelowField;

  /// Save watchlist alert rules
  ///
  /// In en, this message translates to:
  /// **'Save alerts'**
  String get watchlistSaveAlertsAction;

  /// Edit watchlist alert rules action
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get watchlistEditAlertsAction;

  /// Remove watchlist item action
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get watchlistRemoveAction;

  /// Watchlist price unavailable placeholder
  ///
  /// In en, this message translates to:
  /// **'No price'**
  String get watchlistPriceUnavailable;

  /// Market data freshness live label
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get watchlistFreshnessLive;

  /// Market data freshness cached label
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get watchlistFreshnessCache;

  /// Market data freshness stale label
  ///
  /// In en, this message translates to:
  /// **'Stale cache'**
  String get watchlistFreshnessStale;

  /// Watchlist upper alert chip
  ///
  /// In en, this message translates to:
  /// **'Above {price}'**
  String watchlistAlertAboveChip(String price);

  /// Watchlist lower alert chip
  ///
  /// In en, this message translates to:
  /// **'Below {price}'**
  String watchlistAlertBelowChip(String price);

  /// Watchlist upper alert notification
  ///
  /// In en, this message translates to:
  /// **'{symbol} is at {price}, above your alert'**
  String watchlistAlertTriggeredAbove(String symbol, String price);

  /// Watchlist lower alert notification
  ///
  /// In en, this message translates to:
  /// **'{symbol} is at {price}, below your alert'**
  String watchlistAlertTriggeredBelow(String symbol, String price);

  /// Watchlist symbol required validation
  ///
  /// In en, this message translates to:
  /// **'Enter a symbol'**
  String get watchlistSymbolRequired;

  /// Watchlist alert price validation
  ///
  /// In en, this message translates to:
  /// **'Enter a positive price'**
  String get watchlistInvalidNumber;

  /// CN A market label
  ///
  /// In en, this message translates to:
  /// **'A-share'**
  String get watchlistMarketCnA;

  /// Hong Kong stock market label
  ///
  /// In en, this message translates to:
  /// **'Hong Kong'**
  String get watchlistMarketHkStock;

  /// US stock market label
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get watchlistMarketUsStock;

  /// Crypto market label
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get watchlistMarketCrypto;

  /// FX market label
  ///
  /// In en, this message translates to:
  /// **'FX'**
  String get watchlistMarketFx;

  /// Unknown market label
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get watchlistMarketUnknown;

  /// Desktop master/detail affordance that clears the selected detail
  ///
  /// In en, this message translates to:
  /// **'Back to list'**
  String get masterDetailBackToList;

  /// Income Planner page title; also used by the accounts hub entry and command palette label
  ///
  /// In en, this message translates to:
  /// **'Income Planner'**
  String get incomePlannerTitle;

  /// Accounts hub entry subtitle for Income Planner
  ///
  /// In en, this message translates to:
  /// **'Screen sell-put and covered-call income opportunities'**
  String get incomePlannerAccountsEntrySubtitle;

  /// Chinese command-palette search keyword for options; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'期权'**
  String get commandKeywordOptionsCn;

  /// Chinese command-palette search keyword for sell put; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'卖看跌'**
  String get commandKeywordSellPutCn;

  /// Chinese command-palette search keyword for covered call; intentionally present in every locale
  ///
  /// In en, this message translates to:
  /// **'备兑'**
  String get commandKeywordCoveredCallCn;

  /// Empty-state body shown when Income Planner is opened on the web build
  ///
  /// In en, this message translates to:
  /// **'Income Planner is only available on mobile.'**
  String get incomePlannerUnsupportedOnWeb;

  /// Title of the OCC risk disclosure sheet (first-run gate)
  ///
  /// In en, this message translates to:
  /// **'Options risk disclosure'**
  String get incomePlannerOccTitle;

  /// Subtitle of the OCC risk disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Read before using'**
  String get incomePlannerOccSubtitle;

  /// Long-form OCC ODD acknowledgement body
  ///
  /// In en, this message translates to:
  /// **'Selling cash-secured puts and covered calls have defined and undefined risks. Sell-puts can require you to buy 100 shares at strike if assigned; covered calls cap upside above strike. Income Planner only screens opportunities that match your stated risk preferences — it does not predict prices and does not place orders. By continuing you acknowledge you have read OCC Characteristics and Risks of Standardized Options.'**
  String get incomePlannerOccBody;

  /// OCC disclosure accept action
  ///
  /// In en, this message translates to:
  /// **'I have read and accept'**
  String get incomePlannerOccAccept;

  /// OCC disclosure dismiss action
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get incomePlannerOccCancel;

  /// Link to the OCC Options Disclosure Document
  ///
  /// In en, this message translates to:
  /// **'Open OCC ODD'**
  String get incomePlannerOccLearnMore;

  /// Title of the configuration start state
  ///
  /// In en, this message translates to:
  /// **'Set up your stance'**
  String get incomePlannerStartTitle;

  /// Body of the configuration start state
  ///
  /// In en, this message translates to:
  /// **'Tell Income Planner which strategies and risk level you want, then approve the underlyings you would be happy to own or sell.'**
  String get incomePlannerStartBody;

  /// Start-state CTA opening the OCC disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Configure preferences'**
  String get incomePlannerStartCta;

  /// Empty state title for approved-underlyings list
  ///
  /// In en, this message translates to:
  /// **'No approved underlyings yet'**
  String get incomePlannerNoApprovedTitle;

  /// Empty state body for approved-underlyings list
  ///
  /// In en, this message translates to:
  /// **'Add the stocks or ETFs you would be willing to long-term hold (for sell puts) or sell at a higher price (for covered calls). Income Planner only scans symbols on this list.'**
  String get incomePlannerNoApprovedBody;

  /// CTA to add an underlying to the approved list
  ///
  /// In en, this message translates to:
  /// **'Add underlying'**
  String get incomePlannerAddApprovedCta;

  /// Title of the strategy-profile sheet
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get incomePlannerProfileTitle;

  /// Field label for the strategy mode preset
  ///
  /// In en, this message translates to:
  /// **'Risk mode'**
  String get incomePlannerProfileMode;

  /// Conservative preset label
  ///
  /// In en, this message translates to:
  /// **'Conservative'**
  String get incomePlannerProfileModeConservative;

  /// Balanced preset label
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get incomePlannerProfileModeBalanced;

  /// Aggressive preset label
  ///
  /// In en, this message translates to:
  /// **'Aggressive'**
  String get incomePlannerProfileModeAggressive;

  /// Custom preset label
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get incomePlannerProfileModeCustom;

  /// Toggle label for the earnings-window guard
  ///
  /// In en, this message translates to:
  /// **'Skip candidates within 7 days of earnings'**
  String get incomePlannerProfileAvoidEarnings;

  /// Toggle label for the macro-event guard
  ///
  /// In en, this message translates to:
  /// **'Skip candidates within 7 days of CPI / FOMC'**
  String get incomePlannerProfileAvoidMacroEvents;

  /// Toggle label gating scans to the approved list
  ///
  /// In en, this message translates to:
  /// **'Only scan symbols on the approved list (recommended)'**
  String get incomePlannerProfileOnlyApproved;

  /// Section heading for allowed strategies toggle group
  ///
  /// In en, this message translates to:
  /// **'Strategies'**
  String get incomePlannerProfileAllowedStrategies;

  /// Toggle label for cash-secured puts
  ///
  /// In en, this message translates to:
  /// **'Cash-secured puts'**
  String get incomePlannerProfileAllowPut;

  /// Toggle label for covered calls
  ///
  /// In en, this message translates to:
  /// **'Covered calls'**
  String get incomePlannerProfileAllowCall;

  /// Profile sheet primary action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get incomePlannerProfileSave;

  /// Profile sheet cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get incomePlannerProfileCancel;

  /// Title of the add-underlying sheet
  ///
  /// In en, this message translates to:
  /// **'Add approved underlying'**
  String get incomePlannerAddUnderlyingTitle;

  /// Title of the edit-underlying sheet
  ///
  /// In en, this message translates to:
  /// **'Edit underlying'**
  String get incomePlannerEditUnderlyingTitle;

  /// Symbol field label
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get incomePlannerSymbolLabel;

  /// Example symbol placeholder
  ///
  /// In en, this message translates to:
  /// **'AAPL'**
  String get incomePlannerSymbolHint;

  /// Market field label
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get incomePlannerMarketLabel;

  /// Approved-underlying per-symbol allowPut toggle label
  ///
  /// In en, this message translates to:
  /// **'Allow cash-secured puts'**
  String get incomePlannerAllowPutLabel;

  /// Approved-underlying per-symbol allowCall toggle label
  ///
  /// In en, this message translates to:
  /// **'Allow covered calls'**
  String get incomePlannerAllowCallLabel;

  /// Generic save action label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get incomePlannerSaveAction;

  /// Generic delete action label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get incomePlannerDeleteAction;

  /// Generic cancel action label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get incomePlannerCancelAction;

  /// Section header for approved-underlyings list
  ///
  /// In en, this message translates to:
  /// **'Approved underlyings'**
  String get incomePlannerApprovedSectionTitle;

  /// Section header for the opportunities list
  ///
  /// In en, this message translates to:
  /// **'Opportunities'**
  String get incomePlannerOpportunitiesSectionTitle;

  /// Empty state for the opportunities section before the first scan
  ///
  /// In en, this message translates to:
  /// **'No cached opportunities yet. Tap \"Refresh opportunities\" to scan your approved underlyings.'**
  String get incomePlannerOpportunitiesEmpty;

  /// CTA that triggers a new scan
  ///
  /// In en, this message translates to:
  /// **'Refresh opportunities'**
  String get incomePlannerRefreshAction;

  /// Refresh button label while a scan is in flight
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get incomePlannerRefreshRunning;

  /// Error card title when a scan fails
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get incomePlannerRefreshFailedTitle;

  /// Body shown when the scan universe is empty
  ///
  /// In en, this message translates to:
  /// **'No symbols are eligible. Add at least one approved underlying with put/call enabled, or check that you own ≥100 shares for covered calls.'**
  String get incomePlannerRefreshUniverseEmpty;

  /// Last-scan timestamp prefix
  ///
  /// In en, this message translates to:
  /// **'Last scan'**
  String get incomePlannerLastScanLabel;

  /// Hint shown when the scan cache is older than 24 hours
  ///
  /// In en, this message translates to:
  /// **'Cached results are older than 24h — refresh for fresher data.'**
  String get incomePlannerLastScanStale;

  /// Body shown when a scan completed but every candidate was rejected
  ///
  /// In en, this message translates to:
  /// **'No candidates passed your hard filters this scan. Loosen your preferences (e.g. lower yield floor, wider DTE) and try again.'**
  String get incomePlannerOpportunitiesAllRejected;

  /// Title shown after a completed scan finds no qualifying option opportunities
  ///
  /// In en, this message translates to:
  /// **'No matching opportunities this scan'**
  String get incomePlannerNoMatchesTitle;

  /// Toast shown after a completed scan returns zero qualifying opportunities
  ///
  /// In en, this message translates to:
  /// **'Scan finished: no opportunities matched your current filters.'**
  String get incomePlannerScanNoMatchesToast;

  /// Short scan outcome summary shown in the zero-result state
  ///
  /// In en, this message translates to:
  /// **'Scanned {symbols} symbols · rejected {rejected} contracts · {errors} fetch errors'**
  String incomePlannerScanSummary(int symbols, int rejected, int errors);

  /// Short label for the cash-secured put strategy
  ///
  /// In en, this message translates to:
  /// **'Sell put'**
  String get incomePlannerChipCashSecuredPut;

  /// Short label for the covered-call strategy
  ///
  /// In en, this message translates to:
  /// **'Covered call'**
  String get incomePlannerChipCoveredCall;

  /// Risk badge: low
  ///
  /// In en, this message translates to:
  /// **'Low risk'**
  String get incomePlannerRiskLow;

  /// Risk badge: moderate
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get incomePlannerRiskModerate;

  /// Risk badge: elevated
  ///
  /// In en, this message translates to:
  /// **'Elevated'**
  String get incomePlannerRiskElevated;

  /// Card metric: annualized yield
  ///
  /// In en, this message translates to:
  /// **'Annualized'**
  String get incomePlannerMetricAnnualized;

  /// Card metric: cash required to collateralise the trade
  ///
  /// In en, this message translates to:
  /// **'Cash required'**
  String get incomePlannerMetricCash;

  /// Card metric: breakeven price
  ///
  /// In en, this message translates to:
  /// **'Breakeven'**
  String get incomePlannerMetricBreakeven;

  /// Card metric: days-to-expiration shorthand
  ///
  /// In en, this message translates to:
  /// **'DTE'**
  String get incomePlannerMetricDte;

  /// Card metric: strike price
  ///
  /// In en, this message translates to:
  /// **'Strike'**
  String get incomePlannerMetricStrike;

  /// Card metric: margin of safety / cushion
  ///
  /// In en, this message translates to:
  /// **'Cushion'**
  String get incomePlannerMetricMargin;

  /// Card CTA opening the opportunity detail sheet
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get incomePlannerCardDetailsCta;

  /// Detail sheet section: strengths
  ///
  /// In en, this message translates to:
  /// **'Why this looks good'**
  String get incomePlannerDetailWhyGood;

  /// Detail sheet section: weaknesses
  ///
  /// In en, this message translates to:
  /// **'Why this is risky'**
  String get incomePlannerDetailWhyRisky;

  /// Detail sheet section: worst-case scenario
  ///
  /// In en, this message translates to:
  /// **'Worst case'**
  String get incomePlannerDetailWorstCase;

  /// Detail sheet section: best-fit description
  ///
  /// In en, this message translates to:
  /// **'Best for'**
  String get incomePlannerDetailBestFor;

  /// Detail sheet section: when to pass
  ///
  /// In en, this message translates to:
  /// **'Avoid if'**
  String get incomePlannerDetailAvoidIf;

  /// Detail sheet section: per-dimension score bars
  ///
  /// In en, this message translates to:
  /// **'Score breakdown'**
  String get incomePlannerDetailScoreBreakdown;

  /// Detail sheet primary action: open trade-journal sheet
  ///
  /// In en, this message translates to:
  /// **'Log this trade'**
  String get incomePlannerDetailLogTrade;

  /// Section header for the trade journal
  ///
  /// In en, this message translates to:
  /// **'Trade journal'**
  String get incomePlannerJournalSectionTitle;

  /// Empty state for the trade journal
  ///
  /// In en, this message translates to:
  /// **'Closed and open positions you log will appear here.'**
  String get incomePlannerJournalEmpty;

  /// CTA to open a fresh journal sheet
  ///
  /// In en, this message translates to:
  /// **'Log trade'**
  String get incomePlannerJournalAddCta;

  /// Title of the journal sheet when editing an existing row
  ///
  /// In en, this message translates to:
  /// **'Edit trade journal entry'**
  String get incomePlannerJournalEditTitle;

  /// Journal sheet field label for entry premium
  ///
  /// In en, this message translates to:
  /// **'Credit received'**
  String get incomePlannerJournalCreditLabel;

  /// Journal sheet field label for close-out debit
  ///
  /// In en, this message translates to:
  /// **'Debit paid to close'**
  String get incomePlannerJournalDebitLabel;

  /// Journal sheet field label for the OCC option symbol
  ///
  /// In en, this message translates to:
  /// **'Option symbol'**
  String get incomePlannerJournalOptionSymbolLabel;

  /// Example option symbol placeholder
  ///
  /// In en, this message translates to:
  /// **'AAPL250620P00190000'**
  String get incomePlannerJournalOptionSymbolHint;

  /// Numeric amount placeholder
  ///
  /// In en, this message translates to:
  /// **'0.00'**
  String get incomePlannerJournalAmountHint;

  /// Journal sheet free-text notes label
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get incomePlannerJournalNotesLabel;

  /// Journal status label: open position
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get incomePlannerJournalStatusOpen;

  /// Journal status label: closed position
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get incomePlannerJournalStatusClosed;

  /// Journal status label: assigned
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get incomePlannerJournalStatusAssigned;

  /// Journal status label: expired worthless
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get incomePlannerJournalStatusExpired;

  /// Validation: missing symbol
  ///
  /// In en, this message translates to:
  /// **'Symbol is required'**
  String get incomePlannerSymbolRequired;

  /// Validation: symbol already approved
  ///
  /// In en, this message translates to:
  /// **'This symbol is already on the list'**
  String get incomePlannerDuplicateSymbol;

  /// Error message when persisting the strategy profile fails
  ///
  /// In en, this message translates to:
  /// **'Could not save preferences'**
  String get incomePlannerProfileSaveError;

  /// Error message when persisting an approved-underlying fails
  ///
  /// In en, this message translates to:
  /// **'Could not save underlying'**
  String get incomePlannerUnderlyingSaveError;

  /// Generic preferences entry label
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get incomePlannerPreferencesAction;

  /// Generic edit action label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get incomePlannerEditAction;

  /// Time-ago suffix in minutes
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String incomePlannerLastScanMinutes(int n);

  /// Time-ago suffix in hours
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String incomePlannerLastScanHours(int n);

  /// Time-ago suffix in days
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String incomePlannerLastScanDays(int n);

  /// Last-scan summary when the cache is fresh
  ///
  /// In en, this message translates to:
  /// **'{label}: {ago} · {count, plural, =1{1 candidate} other{{count} candidates}}'**
  String incomePlannerLastScanFresh(String label, String ago, int count);

  /// Last-scan summary when the cache is stale
  ///
  /// In en, this message translates to:
  /// **'{label}: {ago} · {stale}'**
  String incomePlannerLastScanStaleSummary(
    String label,
    String ago,
    String stale,
  );
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
