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

  /// No description provided for @commonSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String commonSelectedCount(int count);

  /// No description provided for @rebalanceExecutionResumeInterruptedAction.
  ///
  /// In en, this message translates to:
  /// **'Resume interrupted work'**
  String get rebalanceExecutionResumeInterruptedAction;

  /// Application name shown in title bar and launchers
  ///
  /// In en, this message translates to:
  /// **'NaviWealth'**
  String get appTitle;

  /// Bottom nav: today / driver's-seat tab. Renamed from 'Overview' under the IA contract — Today is read-only operating dashboard.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navHome;

  /// Alias for navHome under the new IA. Prefer this in new code.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// Expense list label
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// Global settings — accessed via Today top-right ⚙, not a tab (IA contract §1).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Bottom nav: records tab (single timeline of events)
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get navActivity;

  /// Account management page label; the Wealth tab remains the owned-object overview.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// Bottom nav: wealth tab (owned objects + current state)
  ///
  /// In en, this message translates to:
  /// **'Wealth'**
  String get navWealth;

  /// Bottom nav: plan tab (decisions + future state — FIRE, rebalance, and strategy tools)
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get navPlan;

  /// Bottom nav action that opens the command palette on touch shells
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Tooltip on the Today header gear that opens /settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettingsTooltip;

  /// Title for the LifeOS domain switcher sheet
  ///
  /// In en, this message translates to:
  /// **'Switch domain'**
  String get shellSwitchDomainTitle;

  /// Desktop sidebar tooltip when the sidebar is collapsed
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar  (⌘B)'**
  String get shellExpandSidebarShortcut;

  /// Desktop sidebar tooltip when the sidebar is expanded
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar  (⌘B)'**
  String get shellCollapseSidebarShortcut;

  /// Plan hub page title (IA contract §1: decisions + future state)
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planHubTitle;

  /// Plan hub: rebalance section card title
  ///
  /// In en, this message translates to:
  /// **'Rebalance'**
  String get planRebalanceSectionTitle;

  /// Plan hub: options-income section subtitle
  ///
  /// In en, this message translates to:
  /// **'Dividends, Wheel & LEAPS'**
  String get planIncomeSectionSubtitle;

  /// Plan hub: monthly category budget section title
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get planBudgetSectionTitle;

  /// No description provided for @planAttentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get planAttentionTitle;

  /// No description provided for @planAttentionShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String planAttentionShowAll(int count);

  /// No description provided for @planAttentionCollapse.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get planAttentionCollapse;

  /// No description provided for @planAttentionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String planAttentionCount(int count);

  /// Plan hub section for the monthly budget and near-term cash runway
  ///
  /// In en, this message translates to:
  /// **'Cash safety'**
  String get planCashSafetyTitle;

  /// Plan hub section for financial independence and life-event scenarios
  ///
  /// In en, this message translates to:
  /// **'Goals & scenarios'**
  String get planLongTermGoalsTitle;

  /// Plan hub section for recurring investing and rebalancing
  ///
  /// In en, this message translates to:
  /// **'Investing'**
  String get planInvestmentPlanTitle;

  /// Plan hub section for dividend and options-income workflows
  ///
  /// In en, this message translates to:
  /// **'Income strategies'**
  String get planIncomeStrategiesTitle;

  /// No description provided for @planExploreActiveOptions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 options position active} other{{count} options positions active}}'**
  String planExploreActiveOptions(int count);

  /// No description provided for @planDcaPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring investment plan'**
  String get planDcaPlanTitle;

  /// No description provided for @planFireGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial independence'**
  String get planFireGoalTitle;

  /// No description provided for @planFireGoalNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set a long-term target when it becomes useful'**
  String get planFireGoalNotConfigured;

  /// No description provided for @planStatusNeedsSetup.
  ///
  /// In en, this message translates to:
  /// **'Needs setup'**
  String get planStatusNeedsSetup;

  /// No description provided for @planStatusLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading status…'**
  String get planStatusLoading;

  /// No description provided for @planStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Status unavailable'**
  String get planStatusUnavailable;

  /// No description provided for @planStatusPartiallyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some plan statuses are temporarily unavailable.'**
  String get planStatusPartiallyUnavailable;

  /// No description provided for @planStatusView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get planStatusView;

  /// No description provided for @planStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get planStatusInProgress;

  /// No description provided for @planStatusOnTrack.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get planStatusOnTrack;

  /// No description provided for @planStatusNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get planStatusNeedsAttention;

  /// No description provided for @planStatusActionRequired.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get planStatusActionRequired;

  /// No description provided for @planStatusNoPendingReviews.
  ///
  /// In en, this message translates to:
  /// **'No reviews due'**
  String get planStatusNoPendingReviews;

  /// No description provided for @planStatusPendingReviews.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 review due} other{{count} reviews due}}'**
  String planStatusPendingReviews(int count);

  /// No description provided for @planStatusRebalanceBalanced.
  ///
  /// In en, this message translates to:
  /// **'On target'**
  String get planStatusRebalanceBalanced;

  /// No description provided for @planStatusRebalanceAttention.
  ///
  /// In en, this message translates to:
  /// **'{percent}% drift'**
  String planStatusRebalanceAttention(String percent);

  /// No description provided for @planStatusRebalanceActive.
  ///
  /// In en, this message translates to:
  /// **'Execution in progress'**
  String get planStatusRebalanceActive;

  /// No description provided for @planStatusBudgetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 category cap} other{{count} category caps}}'**
  String planStatusBudgetCount(int count);

  /// No description provided for @planStatusBudgetComfortable.
  ///
  /// In en, this message translates to:
  /// **'Spending is within plan'**
  String get planStatusBudgetComfortable;

  /// No description provided for @planStatusBudgetUsed.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used this month'**
  String planStatusBudgetUsed(String percent);

  /// No description provided for @planStatusBudgetStrained.
  ///
  /// In en, this message translates to:
  /// **'Approaching the monthly limit'**
  String get planStatusBudgetStrained;

  /// No description provided for @planStatusBudgetOver.
  ///
  /// In en, this message translates to:
  /// **'Monthly budget exceeded'**
  String get planStatusBudgetOver;

  /// No description provided for @planStatusFireProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% toward target'**
  String planStatusFireProgress(String percent);

  /// No description provided for @planStatusDcaDue.
  ///
  /// In en, this message translates to:
  /// **'Contribution due'**
  String get planStatusDcaDue;

  /// No description provided for @planStatusDcaNext.
  ///
  /// In en, this message translates to:
  /// **'Next {date}'**
  String planStatusDcaNext(String date);

  /// No description provided for @planStatusDcaPaused.
  ///
  /// In en, this message translates to:
  /// **'All plans paused'**
  String get planStatusDcaPaused;

  /// Title shown on the /plan/budget page header
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get planBudgetTitle;

  /// Empty state title on the budget page
  ///
  /// In en, this message translates to:
  /// **'No budgets yet'**
  String get planBudgetEmptyTitle;

  /// Empty state body on the budget page explaining the feature
  ///
  /// In en, this message translates to:
  /// **'Set a monthly cap for any category to track spending against it here.'**
  String get planBudgetEmptyBody;

  /// No description provided for @planBudgetEmptyCta.
  ///
  /// In en, this message translates to:
  /// **'Set first budget'**
  String get planBudgetEmptyCta;

  /// No description provided for @planBudgetAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add budget'**
  String get planBudgetAddAction;

  /// No description provided for @planBudgetCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New budget'**
  String get planBudgetCreateTitle;

  /// No description provided for @planBudgetCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Expense category'**
  String get planBudgetCategoryLabel;

  /// No description provided for @planBudgetCategoryHelper.
  ///
  /// In en, this message translates to:
  /// **'Choose the category whose monthly spending this cap should track.'**
  String get planBudgetCategoryHelper;

  /// No description provided for @planBudgetCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an expense category.'**
  String get planBudgetCategoryRequired;

  /// No description provided for @planBudgetNoAvailableCategories.
  ///
  /// In en, this message translates to:
  /// **'Every expense category already has a budget for this month.'**
  String get planBudgetNoAvailableCategories;

  /// No description provided for @planBudgetPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get planBudgetPreviousMonth;

  /// No description provided for @planBudgetCopyPreviousAction.
  ///
  /// In en, this message translates to:
  /// **'Copy previous month'**
  String get planBudgetCopyPreviousAction;

  /// No description provided for @planBudgetCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} budgets from the previous month'**
  String planBudgetCopied(int count);

  /// No description provided for @planBudgetCurrencyMismatch.
  ///
  /// In en, this message translates to:
  /// **'{count} budgets use another currency and are excluded from this summary.'**
  String planBudgetCurrencyMismatch(int count);

  /// No description provided for @planBudgetNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get planBudgetNextMonth;

  /// No description provided for @planBudgetPeriodCurrency.
  ///
  /// In en, this message translates to:
  /// **'{month} · {currency}'**
  String planBudgetPeriodCurrency(String month, String currency);

  /// Header above the list of budgets for the active month
  ///
  /// In en, this message translates to:
  /// **'{month} budgets'**
  String planBudgetMonthHeader(String month);

  /// Label preceding the sum of all budgets for the active month
  ///
  /// In en, this message translates to:
  /// **'Total monthly budget'**
  String get planBudgetTotalLabel;

  /// No description provided for @planBudgetSpentOf.
  ///
  /// In en, this message translates to:
  /// **'Spent {spent} of {budgeted} {currency}'**
  String planBudgetSpentOf(String spent, String budgeted, String currency);

  /// No description provided for @planBudgetRemaining.
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency} left'**
  String planBudgetRemaining(String amount, String currency);

  /// No description provided for @planBudgetOverBy.
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency} over'**
  String planBudgetOverBy(String amount, String currency);

  /// No description provided for @planBudgetEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit budget'**
  String get planBudgetEditTitle;

  /// No description provided for @planBudgetDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete budget'**
  String get planBudgetDeleteAction;

  /// No description provided for @planBudgetDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this budget?'**
  String get planBudgetDeleteTitle;

  /// No description provided for @planBudgetDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the category cap for the selected month. Recorded expenses are not affected.'**
  String get planBudgetDeleteBody;

  /// No description provided for @planBudgetAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String planBudgetAmountLabel(String currency);

  /// No description provided for @planBudgetNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get planBudgetNoteLabel;

  /// No description provided for @planBudgetInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative amount.'**
  String get planBudgetInvalidAmount;

  /// No description provided for @planBudgetSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save budget: {error}'**
  String planBudgetSaveFailed(String error);

  /// Title shown on /plan/income/wheel page header
  ///
  /// In en, this message translates to:
  /// **'Wheel cycles'**
  String get planWheelTitle;

  /// Empty state title on the Wheel page
  ///
  /// In en, this message translates to:
  /// **'No active cycles'**
  String get planWheelEmptyTitle;

  /// Empty state body explaining when cycles appear
  ///
  /// In en, this message translates to:
  /// **'Record a sell-put or covered-call trade and the cycle will surface here.'**
  String get planWheelEmptyBody;

  /// No description provided for @planWheelHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Cycle history'**
  String get planWheelHistoryTitle;

  /// No description provided for @planWheelStageBetween.
  ///
  /// In en, this message translates to:
  /// **'Between cycles'**
  String get planWheelStageBetween;

  /// No description provided for @planWheelStageCashWaiting.
  ///
  /// In en, this message translates to:
  /// **'Cash waiting'**
  String get planWheelStageCashWaiting;

  /// No description provided for @planWheelStageShortPut.
  ///
  /// In en, this message translates to:
  /// **'Short put (open)'**
  String get planWheelStageShortPut;

  /// No description provided for @planWheelStagePutExpired.
  ///
  /// In en, this message translates to:
  /// **'Put expired'**
  String get planWheelStagePutExpired;

  /// No description provided for @planWheelStagePutAssigned.
  ///
  /// In en, this message translates to:
  /// **'Put assigned'**
  String get planWheelStagePutAssigned;

  /// No description provided for @planWheelStageSharesHeld.
  ///
  /// In en, this message translates to:
  /// **'Shares held'**
  String get planWheelStageSharesHeld;

  /// No description provided for @planWheelStageShortCall.
  ///
  /// In en, this message translates to:
  /// **'Short call (open)'**
  String get planWheelStageShortCall;

  /// No description provided for @planWheelStageCallExpired.
  ///
  /// In en, this message translates to:
  /// **'Call expired'**
  String get planWheelStageCallExpired;

  /// No description provided for @planWheelStageCallCalled.
  ///
  /// In en, this message translates to:
  /// **'Called away'**
  String get planWheelStageCallCalled;

  /// Holding detail tab title for upcoming corporate actions
  ///
  /// In en, this message translates to:
  /// **'Upcoming events'**
  String get investmentEventTimelineTitle;

  /// Empty state body when no corporate actions are scheduled
  ///
  /// In en, this message translates to:
  /// **'No upcoming dividends or splits in the next 90 days.'**
  String get investmentEventTimelineEmpty;

  /// Error state title when corporate-action events fail to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load upcoming events.'**
  String get investmentEventTimelineError;

  /// Label on a cash-dividend event row
  ///
  /// In en, this message translates to:
  /// **'Dividend'**
  String get investmentEventDividend;

  /// Label on a split event row, with the ratio (e.g. "4-for-1")
  ///
  /// In en, this message translates to:
  /// **'Split {ratio}'**
  String investmentEventSplit(String ratio);

  /// Label on a rights-offering event row
  ///
  /// In en, this message translates to:
  /// **'Rights offering'**
  String get investmentEventRights;

  /// Label on a DRIP reinvestment event row
  ///
  /// In en, this message translates to:
  /// **'DRIP'**
  String get investmentEventDrip;

  /// Plan hero shown when FIRE engine has no data yet
  ///
  /// In en, this message translates to:
  /// **'Set up your FIRE plan to see progress here.'**
  String get planHeroEmpty;

  /// No description provided for @planHeroConfigure.
  ///
  /// In en, this message translates to:
  /// **'Set up plan'**
  String get planHeroConfigure;

  /// Plan hero — years remaining to financial independence
  ///
  /// In en, this message translates to:
  /// **'{years} years to FIRE'**
  String planHeroYearsToFire(String years);

  /// Plan hero — label for FIRE progress percent
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get planHeroProgressLabel;

  /// Plan hero — secondary CTA hint when drift is detected
  ///
  /// In en, this message translates to:
  /// **'Next: review rebalance'**
  String get planHeroNextRebalance;

  /// Plan hero primary CTA: deep-link to /plan/fire
  ///
  /// In en, this message translates to:
  /// **'See plan'**
  String get planHeroSeePlan;

  /// Wealth hub page title (IA contract §1: owned objects + current state)
  ///
  /// In en, this message translates to:
  /// **'Wealth'**
  String get wealthHubTitle;

  /// Wealth hub subtitle
  ///
  /// In en, this message translates to:
  /// **'What you own, what you owe.'**
  String get wealthHubSubtitle;

  /// No description provided for @wealthEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with an account'**
  String get wealthEmptyTitle;

  /// No description provided for @wealthEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add where you keep money, then record holdings and liabilities as needed.'**
  String get wealthEmptyBody;

  /// No description provided for @wealthEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get wealthEmptyAction;

  /// Heading above account, holdings, and liability navigation on the Wealth hub
  ///
  /// In en, this message translates to:
  /// **'Wealth items'**
  String get wealthObjectsTitle;

  /// Wealth hub: accounts section title
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get wealthAccountsSectionTitle;

  /// Wealth hub: accounts section subtitle
  ///
  /// In en, this message translates to:
  /// **'Cash, banks, brokers, crypto'**
  String get wealthAccountsSectionSubtitle;

  /// Wealth hub: holdings section title (links into portfolio hub)
  ///
  /// In en, this message translates to:
  /// **'Holdings'**
  String get wealthHoldingsSectionTitle;

  /// Wealth hub: holdings section subtitle
  ///
  /// In en, this message translates to:
  /// **'Positions across all accounts'**
  String get wealthHoldingsSectionSubtitle;

  /// Wealth hub: dividend center destination subtitle
  ///
  /// In en, this message translates to:
  /// **'Forecasts, received income, and withholding tax'**
  String get wealthDividendSectionSubtitle;

  /// Wealth hub: watchlist section title
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get wealthWatchlistSectionTitle;

  /// Wealth hub: watchlist section subtitle
  ///
  /// In en, this message translates to:
  /// **'Symbols you\'re tracking'**
  String get wealthWatchlistSectionSubtitle;

  /// Wealth hub: liabilities section title
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get wealthLiabilitiesSectionTitle;

  /// Wealth hub: liabilities section subtitle
  ///
  /// In en, this message translates to:
  /// **'Loans, mortgages, credit'**
  String get wealthLiabilitiesSectionSubtitle;

  /// Wealth hub: historical net worth, assets, and liabilities trend section title
  ///
  /// In en, this message translates to:
  /// **'Wealth trend'**
  String get wealthTrendTitle;

  /// Wealth trend chart hint when the selected metric is unchanged across the selected period
  ///
  /// In en, this message translates to:
  /// **'No change in the selected period.'**
  String get wealthTrendFlatHint;

  /// Disclosure below a dashed wealth trend that contains estimated valuations.
  ///
  /// In en, this message translates to:
  /// **'Estimated from cost basis because a market price is unavailable. Period change is unavailable.'**
  String get wealthTrendEstimatedDisclosure;

  /// Disclosure when the reliable wealth trend starts after the selected range.
  ///
  /// In en, this message translates to:
  /// **'Earlier incomplete or estimated valuations are excluded from the trend and period change.'**
  String get wealthTrendExcludedDisclosure;

  /// Disclosure when missing valuation inputs prevent a reliable current wealth trend.
  ///
  /// In en, this message translates to:
  /// **'A complete current valuation is unavailable, so no partial total is plotted.'**
  String get wealthTrendIncompleteDisclosure;

  /// Wealth tab: title for the multi-perspective allocation section
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get wealthPerspectiveSectionTitle;

  /// Wealth perspective segmented control: group by asset category
  ///
  /// In en, this message translates to:
  /// **'By category'**
  String get wealthPerspectiveByCategory;

  /// Wealth perspective segmented control: group by native currency
  ///
  /// In en, this message translates to:
  /// **'By currency'**
  String get wealthPerspectiveByCurrency;

  /// Bucket-level subtitle: number of underlying holdings
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 holding} other{{count} holdings}}'**
  String wealthPerspectiveItemCount(int count);

  /// Empty-state body for the perspective section when no allocations exist
  ///
  /// In en, this message translates to:
  /// **'No holdings yet. Add assets from the Wealth quick actions to see the breakdown.'**
  String get wealthPerspectiveEmpty;

  /// Cash-flow overview page title
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get cashFlowTitle;

  /// No description provided for @cashFlowShowOriginalCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Show original currencies'**
  String get cashFlowShowOriginalCurrencies;

  /// No description provided for @cashFlowShowBaseCurrency.
  ///
  /// In en, this message translates to:
  /// **'Show base currency'**
  String get cashFlowShowBaseCurrency;

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
  /// **'Monthly'**
  String get cashFlowPeriodMonth;

  /// Cash-flow period selector: quarterly
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get cashFlowPeriodQuarter;

  /// Cash-flow period selector: yearly
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get cashFlowPeriodYear;

  /// No description provided for @cashFlowPreviousPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get cashFlowPreviousPeriod;

  /// No description provided for @cashFlowNextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get cashFlowNextPeriod;

  /// Cash-flow selected calendar quarter
  ///
  /// In en, this message translates to:
  /// **'{year} Q{quarter}'**
  String cashFlowAnchorQuarter(int year, int quarter);

  /// Cash-flow completeness warning for missing FX rates
  ///
  /// In en, this message translates to:
  /// **'{count} cash-flow entries were excluded because {currencies} rates are missing.'**
  String cashFlowFxIncomplete(int count, String currencies);

  /// Cash-flow KPI: incoming cash
  ///
  /// In en, this message translates to:
  /// **'Inflow'**
  String get cashFlowKpiInflow;

  /// Cash-flow KPI: outgoing cash
  ///
  /// In en, this message translates to:
  /// **'Cash spending'**
  String get cashFlowKpiOutflow;

  /// Cash-flow KPI: net cash flow
  ///
  /// In en, this message translates to:
  /// **'Operating net'**
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

  /// No description provided for @cashFlowCategoryIncome.
  ///
  /// In en, this message translates to:
  /// **'Income sources'**
  String get cashFlowCategoryIncome;

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

  /// No description provided for @recurringFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get recurringFilterActive;

  /// No description provided for @recurringFilterPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringFilterPaused;

  /// No description provided for @recurringPausedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No paused rules'**
  String get recurringPausedEmptyTitle;

  /// No description provided for @recurringPausedEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Paused and completed rules remain available here.'**
  String get recurringPausedEmptyBody;

  /// No description provided for @recurringPausedBadge.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringPausedBadge;

  /// No description provided for @recurringCompletedBadge.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get recurringCompletedBadge;

  /// Recurring list empty-state CTA
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
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

  /// No description provided for @recurringActionEnable.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get recurringActionEnable;

  /// No description provided for @recurringActionEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Start generating entries again'**
  String get recurringActionEnableHint;

  /// Subtitle for delete action
  ///
  /// In en, this message translates to:
  /// **'Remove this rule permanently'**
  String get recurringActionDeleteHint;

  /// Delete confirm title
  ///
  /// In en, this message translates to:
  /// **'Delete rule?'**
  String get recurringDeleteTitle;

  /// Delete confirm body
  ///
  /// In en, this message translates to:
  /// **'This recurring rule will be removed. You can undo it from the confirmation message.'**
  String get recurringDeleteBody;

  /// Toast after disabling a rule
  ///
  /// In en, this message translates to:
  /// **'Rule disabled'**
  String get recurringDisabled;

  /// No description provided for @recurringEnabled.
  ///
  /// In en, this message translates to:
  /// **'Rule resumed'**
  String get recurringEnabled;

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

  /// Recurring form disclosure title for optional schedule and note fields
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get recurringFormDetailsTitle;

  /// Recurring form disclosure summary when optional fields use defaults
  ///
  /// In en, this message translates to:
  /// **'Interval, end date & note'**
  String get recurringFormDetailsSummary;

  /// Recurring form disclosure summary when optional fields have values
  ///
  /// In en, this message translates to:
  /// **'Custom options configured'**
  String get recurringFormDetailsConfigured;

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

  /// Recurring validation: end date precedes first occurrence
  ///
  /// In en, this message translates to:
  /// **'The end date must include at least one scheduled occurrence'**
  String get recurringValidationUntilBeforeStart;

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

  /// Dividend center KPI label: trailing twelve month net dividends after withholding
  ///
  /// In en, this message translates to:
  /// **'TTM after tax'**
  String get dividendCenterMetricTtmNet;

  /// No description provided for @dividendCenterMetricTtmNetCaption.
  ///
  /// In en, this message translates to:
  /// **'Kept {ratio} after withholding'**
  String dividendCenterMetricTtmNetCaption(String ratio);

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

  /// No description provided for @dividendCenterPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Dividend income watch'**
  String get dividendCenterPolicyTitle;

  /// No description provided for @dividendCenterPolicyBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 holding\'s recorded dividend cash fell vs the prior year} other{{count} holdings\' recorded dividend cash fell vs the prior year}}'**
  String dividendCenterPolicyBody(int count);

  /// No description provided for @dividendCenterPolicySeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get dividendCenterPolicySeverityWarning;

  /// No description provided for @dividendCenterPolicySeverityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get dividendCenterPolicySeverityCritical;

  /// No description provided for @dividendCenterPolicyDropLine.
  ///
  /// In en, this message translates to:
  /// **'Down {percent}%'**
  String dividendCenterPolicyDropLine(String percent);

  /// No description provided for @dividendResilienceTitle.
  ///
  /// In en, this message translates to:
  /// **'Historical dividend resilience'**
  String get dividendResilienceTitle;

  /// No description provided for @dividendResilienceConfidence.
  ///
  /// In en, this message translates to:
  /// **'{confidence} confidence'**
  String dividendResilienceConfidence(String confidence);

  /// No description provided for @dividendResilienceConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get dividendResilienceConfidenceHigh;

  /// No description provided for @dividendResilienceConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get dividendResilienceConfidenceMedium;

  /// No description provided for @dividendResilienceConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get dividendResilienceConfidenceLow;

  /// No description provided for @dividendResilienceNoCoverage.
  ///
  /// In en, this message translates to:
  /// **'No recorded history available.'**
  String get dividendResilienceNoCoverage;

  /// No description provided for @dividendResilienceCoverage.
  ///
  /// In en, this message translates to:
  /// **'{start}–{end} · {months} observed months · {recordedMonths} payout months recorded'**
  String dividendResilienceCoverage(
    String start,
    String end,
    int months,
    int recordedMonths,
  );

  /// No description provided for @dividendResilienceCadenceCoverage.
  ///
  /// In en, this message translates to:
  /// **'Cadence check: {expected} expected payments · {missing} possibly missing · {irregular} irregular assets'**
  String dividendResilienceCadenceCoverage(
    int expected,
    int missing,
    int irregular,
  );

  /// No description provided for @dividendResilienceNetSeries.
  ///
  /// In en, this message translates to:
  /// **'After tax'**
  String get dividendResilienceNetSeries;

  /// No description provided for @dividendResilienceChartLabel.
  ///
  /// In en, this message translates to:
  /// **'Rolling twelve-month gross and after-tax dividend income'**
  String get dividendResilienceChartLabel;

  /// No description provided for @dividendResilienceIncomeCagr.
  ///
  /// In en, this message translates to:
  /// **'After-tax income CAGR'**
  String get dividendResilienceIncomeCagr;

  /// No description provided for @dividendResilienceMaxDrawdown.
  ///
  /// In en, this message translates to:
  /// **'Max income decline'**
  String get dividendResilienceMaxDrawdown;

  /// No description provided for @dividendResilienceLargestSource.
  ///
  /// In en, this message translates to:
  /// **'Largest income source'**
  String get dividendResilienceLargestSource;

  /// No description provided for @dividendResilienceRetention.
  ///
  /// In en, this message translates to:
  /// **'After-tax retention'**
  String get dividendResilienceRetention;

  /// No description provided for @dividendResilienceNotRecovered.
  ///
  /// In en, this message translates to:
  /// **'Not yet recovered'**
  String get dividendResilienceNotRecovered;

  /// No description provided for @dividendResilienceRecoveredIn.
  ///
  /// In en, this message translates to:
  /// **'Recovered in {months} months'**
  String dividendResilienceRecoveredIn(int months);

  /// No description provided for @dividendResilienceAttributionTitle.
  ///
  /// In en, this message translates to:
  /// **'What changed vs the prior 12 months'**
  String get dividendResilienceAttributionTitle;

  /// No description provided for @dividendResilienceAttributionHint.
  ///
  /// In en, this message translates to:
  /// **'Recorded cash is separated only where the ledger has enough per-share and FX evidence.'**
  String get dividendResilienceAttributionHint;

  /// No description provided for @dividendResilienceAttributionSplit.
  ///
  /// In en, this message translates to:
  /// **'Holding {holding} · per share {unit} · FX {fx}'**
  String dividendResilienceAttributionSplit(
    String holding,
    String unit,
    String fx,
  );

  /// No description provided for @dividendResilienceAttributionCombined.
  ///
  /// In en, this message translates to:
  /// **'Holding/per-share {local} · FX {fx}'**
  String dividendResilienceAttributionCombined(String local, String fx);

  /// No description provided for @dividendResilienceDriverHolding.
  ///
  /// In en, this message translates to:
  /// **'Main driver: holding quantity'**
  String get dividendResilienceDriverHolding;

  /// No description provided for @dividendResilienceDriverUnitDividend.
  ///
  /// In en, this message translates to:
  /// **'Main driver: dividend per share'**
  String get dividendResilienceDriverUnitDividend;

  /// No description provided for @dividendResilienceDriverFx.
  ///
  /// In en, this message translates to:
  /// **'Main driver: exchange rate'**
  String get dividendResilienceDriverFx;

  /// No description provided for @dividendResilienceDriverCombined.
  ///
  /// In en, this message translates to:
  /// **'Holding and per-share effects are combined'**
  String get dividendResilienceDriverCombined;

  /// No description provided for @dividendResilienceMethodology.
  ///
  /// In en, this message translates to:
  /// **'Based on your recorded ledger, not a backtest. {matchedPercent}% of attributed entries have per-share evidence; {excludedCount} entries were excluded for missing FX.'**
  String dividendResilienceMethodology(int matchedPercent, int excludedCount);

  /// No description provided for @financialInboxEvidencePrimaryDriver.
  ///
  /// In en, this message translates to:
  /// **'Primary change driver'**
  String get financialInboxEvidencePrimaryDriver;

  /// No description provided for @financialInboxEvidenceUnitDividend.
  ///
  /// In en, this message translates to:
  /// **'Per-share evidence available'**
  String get financialInboxEvidenceUnitDividend;

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

  /// Gross dividend amount label
  ///
  /// In en, this message translates to:
  /// **'Gross'**
  String get dividendCenterGross;

  /// Dividend withholding tax label
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get dividendCenterWithholding;

  /// Expand the complete dividend history
  ///
  /// In en, this message translates to:
  /// **'Show all {count} months'**
  String dividendCenterHistoryShowAll(int count);

  /// Collapse dividend history
  ///
  /// In en, this message translates to:
  /// **'Show recent months'**
  String get dividendCenterHistoryShowLess;

  /// Dividend ranking portfolio share label
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get dividendCenterRankingShare;

  /// Dividend ranking yield on cost label
  ///
  /// In en, this message translates to:
  /// **'Yield on cost'**
  String get dividendCenterRankingYieldOnCost;

  /// Dividend ranking net (after withholding) yield on cost label
  ///
  /// In en, this message translates to:
  /// **'Net yield on cost'**
  String get dividendCenterRankingNetYieldOnCost;

  /// Dividend ranking withholding label
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get dividendCenterRankingWithholding;

  /// Dividend center forecast placeholder title
  ///
  /// In en, this message translates to:
  /// **'Next 12 months'**
  String get dividendCenterForecastTitle;

  /// Dividend center forecast placeholder body
  ///
  /// In en, this message translates to:
  /// **'Not enough history or declared payments to forecast yet.'**
  String get dividendCenterForecastUnavailable;

  /// No description provided for @dividendCenterForecastHistoricalError.
  ///
  /// In en, this message translates to:
  /// **'90-day historical error {error} across {count} reviews'**
  String dividendCenterForecastHistoricalError(String error, int count);

  /// Dividend forecast warning for declared payments excluded due to missing FX
  ///
  /// In en, this message translates to:
  /// **'Missing {currencies} rates'**
  String dividendCenterForecastFxIncomplete(String currencies);

  /// Dividend center completeness warning for missing FX rates
  ///
  /// In en, this message translates to:
  /// **'{count} dividend entries were excluded because {currencies} rates are missing.'**
  String dividendCenterFxIncomplete(int count, String currencies);

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
  /// **'Delete the dividend for {asset}? You can undo it from the confirmation message.'**
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

  /// No description provided for @portfolioAllHoldings.
  ///
  /// In en, this message translates to:
  /// **'All holdings'**
  String get portfolioAllHoldings;

  /// No description provided for @portfolioUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get portfolioUnassigned;

  /// No description provided for @portfolioManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio settings'**
  String get portfolioManageTitle;

  /// No description provided for @portfolioCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New portfolio'**
  String get portfolioCreateTitle;

  /// No description provided for @portfolioEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit portfolio'**
  String get portfolioEditTitle;

  /// No description provided for @portfolioNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Portfolio name'**
  String get portfolioNameLabel;

  /// No description provided for @portfolioNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a portfolio name.'**
  String get portfolioNameRequired;

  /// No description provided for @portfolioStrategyLabel.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get portfolioStrategyLabel;

  /// No description provided for @portfolioCreateApproachTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an approach'**
  String get portfolioCreateApproachTitle;

  /// No description provided for @portfolioCreateApproachHint.
  ///
  /// In en, this message translates to:
  /// **'Start with a clear default. You can refine allocation later.'**
  String get portfolioCreateApproachHint;

  /// No description provided for @portfolioCreateRecommendedHint.
  ///
  /// In en, this message translates to:
  /// **'Recommended for a diversified long-term core'**
  String get portfolioCreateRecommendedHint;

  /// No description provided for @portfolioCreateCustomizableHint.
  ///
  /// In en, this message translates to:
  /// **'A focused starting point you can customize later'**
  String get portfolioCreateCustomizableHint;

  /// No description provided for @portfolioStrategyIndexCore.
  ///
  /// In en, this message translates to:
  /// **'Index core'**
  String get portfolioStrategyIndexCore;

  /// No description provided for @portfolioStrategyDividendIncome.
  ///
  /// In en, this message translates to:
  /// **'Dividend income'**
  String get portfolioStrategyDividendIncome;

  /// No description provided for @portfolioStrategyOptionsIncome.
  ///
  /// In en, this message translates to:
  /// **'Options income'**
  String get portfolioStrategyOptionsIncome;

  /// No description provided for @portfolioStrategyIncome.
  ///
  /// In en, this message translates to:
  /// **'Dividend income'**
  String get portfolioStrategyIncome;

  /// No description provided for @portfolioStrategyGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get portfolioStrategyGrowth;

  /// No description provided for @portfolioStrategyPreservation.
  ///
  /// In en, this message translates to:
  /// **'Capital preservation'**
  String get portfolioStrategyPreservation;

  /// No description provided for @portfolioStrategyGoalLinked.
  ///
  /// In en, this message translates to:
  /// **'Goal linked'**
  String get portfolioStrategyGoalLinked;

  /// No description provided for @portfolioStrategyCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get portfolioStrategyCustom;

  /// No description provided for @portfolioStrategyCustomCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create strategy type'**
  String get portfolioStrategyCustomCreateAction;

  /// No description provided for @portfolioStrategyCustomNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Strategy type name'**
  String get portfolioStrategyCustomNameLabel;

  /// No description provided for @portfolioStrategyCapitalRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Capital role'**
  String get portfolioStrategyCapitalRoleLabel;

  /// No description provided for @portfolioStrategyCapitalOwner.
  ///
  /// In en, this message translates to:
  /// **'Owns a capital allocation'**
  String get portfolioStrategyCapitalOwner;

  /// No description provided for @portfolioStrategyCapitalOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay without a capital weight'**
  String get portfolioStrategyCapitalOverlay;

  /// No description provided for @portfolioStrategyDefaultAssetLabel.
  ///
  /// In en, this message translates to:
  /// **'Default asset category'**
  String get portfolioStrategyDefaultAssetLabel;

  /// No description provided for @portfolioAnnualIncomeTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual income target (optional)'**
  String get portfolioAnnualIncomeTargetLabel;

  /// No description provided for @portfolioNoPortfolios.
  ///
  /// In en, this message translates to:
  /// **'Create a portfolio to classify holdings by purpose.'**
  String get portfolioNoPortfolios;

  /// No description provided for @portfolioAssignLotsTitle.
  ///
  /// In en, this message translates to:
  /// **'Include positions'**
  String get portfolioAssignLotsTitle;

  /// No description provided for @portfolioAssignLotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose purchase lots to include in a portfolio sleeve.'**
  String get portfolioAssignLotsSubtitle;

  /// No description provided for @portfolioAssignCashTitle.
  ///
  /// In en, this message translates to:
  /// **'Include cash'**
  String get portfolioAssignCashTitle;

  /// No description provided for @portfolioAssignCashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reserve cash from an asset account for one sleeve.'**
  String get portfolioAssignCashSubtitle;

  /// No description provided for @portfolioAssignCashAction.
  ///
  /// In en, this message translates to:
  /// **'Include cash'**
  String get portfolioAssignCashAction;

  /// No description provided for @portfolioCashAssignmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Included cash'**
  String get portfolioCashAssignmentsTitle;

  /// No description provided for @portfolioCashAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Asset account'**
  String get portfolioCashAccountLabel;

  /// No description provided for @portfolioCashAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Assigned amount'**
  String get portfolioCashAmountLabel;

  /// No description provided for @portfolioCashAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get portfolioCashAmountInvalid;

  /// No description provided for @portfolioCashNoAccounts.
  ///
  /// In en, this message translates to:
  /// **'Create an asset account before assigning cash.'**
  String get portfolioCashNoAccounts;

  /// No description provided for @portfolioCashAssignmentSummary.
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency} · {group}'**
  String portfolioCashAssignmentSummary(
    String amount,
    String currency,
    String group,
  );

  /// No description provided for @portfolioAssignmentSaved.
  ///
  /// In en, this message translates to:
  /// **'Included assets saved.'**
  String get portfolioAssignmentSaved;

  /// No description provided for @portfolioStudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio studio'**
  String get portfolioStudioTitle;

  /// No description provided for @portfolioStudioNotFound.
  ///
  /// In en, this message translates to:
  /// **'This portfolio no longer exists.'**
  String get portfolioStudioNotFound;

  /// No description provided for @portfolioStudioPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Investment plan'**
  String get portfolioStudioPlanTitle;

  /// No description provided for @portfolioStudioPlanHint.
  ///
  /// In en, this message translates to:
  /// **'Review targets and drift here, then open a portfolio to adjust sleeves, assets, and rules.'**
  String get portfolioStudioPlanHint;

  /// No description provided for @portfolioStudioPlanEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Create your first portfolio to define how capital should be used and rebalanced.'**
  String get portfolioStudioPlanEmptyHint;

  /// No description provided for @portfolioStudioPlanTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Plan target'**
  String get portfolioStudioPlanTargetLabel;

  /// No description provided for @portfolioStudioTargetSummary.
  ///
  /// In en, this message translates to:
  /// **'{target}% plan target · {count} sleeves'**
  String portfolioStudioTargetSummary(String target, int count);

  /// No description provided for @portfolioStudioConfiguredStatus.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get portfolioStudioConfiguredStatus;

  /// No description provided for @portfolioStudioSleevesMetric.
  ///
  /// In en, this message translates to:
  /// **'Sleeves'**
  String get portfolioStudioSleevesMetric;

  /// No description provided for @portfolioStudioAssetsMetric.
  ///
  /// In en, this message translates to:
  /// **'Included assets'**
  String get portfolioStudioAssetsMetric;

  /// No description provided for @portfolioStudioRulesMetric.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get portfolioStudioRulesMetric;

  /// No description provided for @portfolioStudioRebalanceAction.
  ///
  /// In en, this message translates to:
  /// **'Check rebalance'**
  String get portfolioStudioRebalanceAction;

  /// No description provided for @portfolioStudioOverviewTab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get portfolioStudioOverviewTab;

  /// No description provided for @portfolioStudioStructureTab.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get portfolioStudioStructureTab;

  /// No description provided for @portfolioStudioAssetsTab.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get portfolioStudioAssetsTab;

  /// No description provided for @portfolioStudioRulesTab.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get portfolioStudioRulesTab;

  /// No description provided for @portfolioStudioConfigurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio setup'**
  String get portfolioStudioConfigurationTitle;

  /// No description provided for @portfolioStudioConfigurationHint.
  ///
  /// In en, this message translates to:
  /// **'Open only the area you want to adjust.'**
  String get portfolioStudioConfigurationHint;

  /// No description provided for @portfolioStudioSleeveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} strategies'**
  String portfolioStudioSleeveCount(int count);

  /// No description provided for @portfolioStudioIncludedAssetCount.
  ///
  /// In en, this message translates to:
  /// **'{count} included assets'**
  String portfolioStudioIncludedAssetCount(int count);

  /// No description provided for @portfolioStudioRuleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} optional rules'**
  String portfolioStudioRuleCount(int count);

  /// No description provided for @portfolioStudioAllocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Capital path'**
  String get portfolioStudioAllocationTitle;

  /// No description provided for @portfolioStudioAllocationHint.
  ///
  /// In en, this message translates to:
  /// **'Plan → portfolio → sleeve → asset target, configured in one path.'**
  String get portfolioStudioAllocationHint;

  /// No description provided for @portfolioStudioNextActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get portfolioStudioNextActionTitle;

  /// No description provided for @portfolioStudioNextActionHint.
  ///
  /// In en, this message translates to:
  /// **'Adjust sleeve weights together and always keep the total at 100%.'**
  String get portfolioStudioNextActionHint;

  /// No description provided for @portfolioStudioStructureTitle.
  ///
  /// In en, this message translates to:
  /// **'Strategy sleeves'**
  String get portfolioStudioStructureTitle;

  /// No description provided for @portfolioStudioStructureHint.
  ///
  /// In en, this message translates to:
  /// **'Each sleeve owns a capital target and its internal asset allocation.'**
  String get portfolioStudioStructureHint;

  /// No description provided for @portfolioStudioSleeveSummary.
  ///
  /// In en, this message translates to:
  /// **'{target}% target · {count} asset targets · {policy}'**
  String portfolioStudioSleeveSummary(String target, int count, String policy);

  /// No description provided for @portfolioStudioIncludedAssetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Included assets'**
  String get portfolioStudioIncludedAssetsTitle;

  /// No description provided for @portfolioStudioIncludedAssetsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose positions and cash for this portfolio and the sleeve that owns them.'**
  String get portfolioStudioIncludedAssetsHint;

  /// No description provided for @portfolioStudioAssetTargetsHint.
  ///
  /// In en, this message translates to:
  /// **'The asset classes and specific securities planned inside each sleeve.'**
  String get portfolioStudioAssetTargetsHint;

  /// No description provided for @portfolioStudioNoIncludedAssets.
  ///
  /// In en, this message translates to:
  /// **'No positions or cash are included yet.'**
  String get portfolioStudioNoIncludedAssets;

  /// No description provided for @portfolioStudioIncludedPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Position lot'**
  String get portfolioStudioIncludedPositionLabel;

  /// No description provided for @portfolioStudioIncludePositionAction.
  ///
  /// In en, this message translates to:
  /// **'Include positions'**
  String get portfolioStudioIncludePositionAction;

  /// No description provided for @portfolioStudioIncludeCashAction.
  ///
  /// In en, this message translates to:
  /// **'Include cash'**
  String get portfolioStudioIncludeCashAction;

  /// No description provided for @portfolioStudioAddAssetsAction.
  ///
  /// In en, this message translates to:
  /// **'Add assets'**
  String get portfolioStudioAddAssetsAction;

  /// No description provided for @portfolioStudioAddAssetsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a position or cash balance to include.'**
  String get portfolioStudioAddAssetsHint;

  /// No description provided for @portfolioStudioRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules and enhancements'**
  String get portfolioStudioRulesTitle;

  /// No description provided for @portfolioStudioRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Rules attach to a sleeve without owning a separate capital weight.'**
  String get portfolioStudioRulesHint;

  /// No description provided for @portfolioStudioNoRules.
  ///
  /// In en, this message translates to:
  /// **'No extra rules. Sleeves still run with their own targets.'**
  String get portfolioStudioNoRules;

  /// No description provided for @portfolioStudioAssetTargetCount.
  ///
  /// In en, this message translates to:
  /// **'{count} asset targets'**
  String portfolioStudioAssetTargetCount(int count);

  /// No description provided for @portfolioTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio trend'**
  String get portfolioTrendTitle;

  /// No description provided for @portfolioTrendHint.
  ///
  /// In en, this message translates to:
  /// **'Track value separately from capital flows, then switch to cash-flow-adjusted performance.'**
  String get portfolioTrendHint;

  /// No description provided for @portfolioTrendMarketValue.
  ///
  /// In en, this message translates to:
  /// **'Market value'**
  String get portfolioTrendMarketValue;

  /// No description provided for @portfolioTrendPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get portfolioTrendPerformance;

  /// No description provided for @portfolioTrendCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current value'**
  String get portfolioTrendCurrentValue;

  /// No description provided for @portfolioTrendPeriodPerformance.
  ///
  /// In en, this message translates to:
  /// **'Period return'**
  String get portfolioTrendPeriodPerformance;

  /// No description provided for @portfolioTrendNetFlow.
  ///
  /// In en, this message translates to:
  /// **'Net capital flow'**
  String get portfolioTrendNetFlow;

  /// No description provided for @portfolioTrendAwaitingData.
  ///
  /// In en, this message translates to:
  /// **'A trend appears after assets or cash are included.'**
  String get portfolioTrendAwaitingData;

  /// No description provided for @portfolioTrendEstimatedDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Some points use estimated prices or incomplete FX history.'**
  String get portfolioTrendEstimatedDisclosure;

  /// No description provided for @portfolioTrendChartSemantics.
  ///
  /// In en, this message translates to:
  /// **'Portfolio value and performance trend'**
  String get portfolioTrendChartSemantics;

  /// No description provided for @portfolioTrendMonthSemantics.
  ///
  /// In en, this message translates to:
  /// **'Portfolio performance over the last month'**
  String get portfolioTrendMonthSemantics;

  /// No description provided for @portfolioTrendRangeYtd.
  ///
  /// In en, this message translates to:
  /// **'YTD'**
  String get portfolioTrendRangeYtd;

  /// No description provided for @rebalancePortfoliosTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio allocation'**
  String get rebalancePortfoliosTitle;

  /// No description provided for @rebalanceCapitalTreeHint.
  ///
  /// In en, this message translates to:
  /// **'Portfolio transfers → strategy allocation → assets inside each strategy'**
  String get rebalanceCapitalTreeHint;

  /// No description provided for @rebalancePortfolioWeightPair.
  ///
  /// In en, this message translates to:
  /// **'Actual {actual} · target {target}'**
  String rebalancePortfolioWeightPair(String actual, String target);

  /// No description provided for @rebalancePortfolioTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Inter-portfolio transfers'**
  String get rebalancePortfolioTransfersTitle;

  /// No description provided for @rebalanceGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebalance groups'**
  String get rebalanceGroupsTitle;

  /// No description provided for @rebalanceGroupWeight.
  ///
  /// In en, this message translates to:
  /// **'Target {percent}'**
  String rebalanceGroupWeight(String percent);

  /// No description provided for @rebalanceGroupTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Capital transfers'**
  String get rebalanceGroupTransfersTitle;

  /// No description provided for @rebalanceGroupTransfer.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to}: {amount}'**
  String rebalanceGroupTransfer(String from, String to, String amount);

  /// No description provided for @portfolioGroupsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Strategy sleeves'**
  String get portfolioGroupsSectionTitle;

  /// No description provided for @portfolioAllocationSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Portfolio capital allocation'**
  String get portfolioAllocationSectionTitle;

  /// No description provided for @portfolioAllocationWeightSummary.
  ///
  /// In en, this message translates to:
  /// **'Universe target {weight}%'**
  String portfolioAllocationWeightSummary(String weight);

  /// No description provided for @portfolioAllocationEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit portfolio allocation'**
  String get portfolioAllocationEditTitle;

  /// No description provided for @portfolioAllocationPlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set every portfolio together. The total must equal 100%.'**
  String get portfolioAllocationPlanSubtitle;

  /// No description provided for @portfolioAllocationTargetWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Universe target (%)'**
  String get portfolioAllocationTargetWeightLabel;

  /// No description provided for @portfolioAllocationSingleTargetHint.
  ///
  /// In en, this message translates to:
  /// **'A universe with one portfolio must remain at 100%. Add another portfolio before changing its target.'**
  String get portfolioAllocationSingleTargetHint;

  /// No description provided for @portfolioGroupAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add sleeve'**
  String get portfolioGroupAddAction;

  /// No description provided for @portfolioStrategyAllocationEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit sleeve allocation'**
  String get portfolioStrategyAllocationEditTitle;

  /// No description provided for @portfolioStrategyAllocationPlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set every sleeve together. The total must equal 100%.'**
  String get portfolioStrategyAllocationPlanSubtitle;

  /// No description provided for @portfolioOverlayAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get portfolioOverlayAddAction;

  /// No description provided for @portfolioOverlayNoTemplates.
  ///
  /// In en, this message translates to:
  /// **'Create a rule type before attaching one to a sleeve.'**
  String get portfolioOverlayNoTemplates;

  /// No description provided for @portfolioOverlayHostGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Apply to sleeve'**
  String get portfolioOverlayHostGroupLabel;

  /// No description provided for @portfolioOverlaySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules and enhancements'**
  String get portfolioOverlaySectionTitle;

  /// No description provided for @portfolioOverlayDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get portfolioOverlayDeleteAction;

  /// No description provided for @portfolioOverlayDeleteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This rule will be removed from its sleeve. Included assets and the accounting ledger will not change.'**
  String get portfolioOverlayDeleteConfirmation;

  /// No description provided for @portfolioGroupEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit sleeve'**
  String get portfolioGroupEditTitle;

  /// No description provided for @portfolioGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Sleeve name'**
  String get portfolioGroupNameLabel;

  /// No description provided for @portfolioStrategyDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete sleeve'**
  String get portfolioStrategyDeleteAction;

  /// No description provided for @portfolioStrategyDeleteLastBlocked.
  ///
  /// In en, this message translates to:
  /// **'A portfolio must keep at least one capital strategy. Delete the portfolio instead if it is no longer needed.'**
  String get portfolioStrategyDeleteLastBlocked;

  /// No description provided for @portfolioStrategyDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the strategy. Try again.'**
  String get portfolioStrategyDeleteFailed;

  /// No description provided for @portfolioStrategyDeleteTransferDescription.
  ///
  /// In en, this message translates to:
  /// **'The {weight}% target and {assignmentCount} asset or cash assignments will move to the selected strategy. {overlayCount} attached overlays will be deleted.'**
  String portfolioStrategyDeleteTransferDescription(
    String weight,
    int assignmentCount,
    int overlayCount,
  );

  /// No description provided for @portfolioGroupTargetWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Portfolio target (%)'**
  String get portfolioGroupTargetWeightLabel;

  /// No description provided for @portfolioGroupSingleTargetHint.
  ///
  /// In en, this message translates to:
  /// **'A portfolio with one strategy must remain at 100%. Add another strategy before changing its target.'**
  String get portfolioGroupSingleTargetHint;

  /// No description provided for @portfolioGroupDriftBandLabel.
  ///
  /// In en, this message translates to:
  /// **'Allowed deviation (%)'**
  String get portfolioGroupDriftBandLabel;

  /// No description provided for @portfolioGroupTransferPolicyLabel.
  ///
  /// In en, this message translates to:
  /// **'Capital transfer rule'**
  String get portfolioGroupTransferPolicyLabel;

  /// No description provided for @portfolioGroupTransferBidirectional.
  ///
  /// In en, this message translates to:
  /// **'Free transfer'**
  String get portfolioGroupTransferBidirectional;

  /// No description provided for @portfolioGroupTransferInflowsOnly.
  ///
  /// In en, this message translates to:
  /// **'Receive funds only'**
  String get portfolioGroupTransferInflowsOnly;

  /// No description provided for @portfolioGroupTransferIsolated.
  ///
  /// In en, this message translates to:
  /// **'Manage independently'**
  String get portfolioGroupTransferIsolated;

  /// No description provided for @capitalAllocationTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total allocation'**
  String get capitalAllocationTotalLabel;

  /// No description provided for @capitalAllocationEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get capitalAllocationEditAction;

  /// No description provided for @capitalAllocationTotalHint.
  ///
  /// In en, this message translates to:
  /// **'Allocation is {total}%. Adjust all items until the total is 100%.'**
  String capitalAllocationTotalHint(String total);

  /// No description provided for @capitalAllocationAdvancedAction.
  ///
  /// In en, this message translates to:
  /// **'Funding rules and tolerance'**
  String get capitalAllocationAdvancedAction;

  /// No description provided for @capitalAllocationBalanceEvenlyAction.
  ///
  /// In en, this message translates to:
  /// **'Distribute evenly'**
  String get capitalAllocationBalanceEvenlyAction;

  /// No description provided for @capitalAllocationFillRemainderAction.
  ///
  /// In en, this message translates to:
  /// **'Fill remainder'**
  String get capitalAllocationFillRemainderAction;

  /// No description provided for @capitalAllocationToleranceLabel.
  ///
  /// In en, this message translates to:
  /// **'Allowed deviation (%)'**
  String get capitalAllocationToleranceLabel;

  /// No description provided for @capitalAllocationRuleLabel.
  ///
  /// In en, this message translates to:
  /// **'Funding rule'**
  String get capitalAllocationRuleLabel;

  /// No description provided for @capitalAllocationRuleBidirectional.
  ///
  /// In en, this message translates to:
  /// **'Flexible transfers'**
  String get capitalAllocationRuleBidirectional;

  /// No description provided for @capitalAllocationRuleBidirectionalDescription.
  ///
  /// In en, this message translates to:
  /// **'Capital may move into or out of this item.'**
  String get capitalAllocationRuleBidirectionalDescription;

  /// No description provided for @capitalAllocationRuleInflowsOnly.
  ///
  /// In en, this message translates to:
  /// **'Receive funds only'**
  String get capitalAllocationRuleInflowsOnly;

  /// No description provided for @capitalAllocationRuleInflowsOnlyDescription.
  ///
  /// In en, this message translates to:
  /// **'Capital may move in but existing capital will not be moved out.'**
  String get capitalAllocationRuleInflowsOnlyDescription;

  /// No description provided for @capitalAllocationRuleIsolated.
  ///
  /// In en, this message translates to:
  /// **'Manage independently'**
  String get capitalAllocationRuleIsolated;

  /// No description provided for @capitalAllocationRuleIsolatedDescription.
  ///
  /// In en, this message translates to:
  /// **'No automatic capital transfers in either direction.'**
  String get capitalAllocationRuleIsolatedDescription;

  /// No description provided for @capitalAllocationSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the allocation plan. Try again.'**
  String get capitalAllocationSaveFailed;

  /// No description provided for @portfolioGroupWeightSummary.
  ///
  /// In en, this message translates to:
  /// **'{weight}% target · {policy}'**
  String portfolioGroupWeightSummary(String weight, String policy);

  /// No description provided for @portfolioGroupNoTemplates.
  ///
  /// In en, this message translates to:
  /// **'No capital strategy types are available.'**
  String get portfolioGroupNoTemplates;

  /// No description provided for @portfolioSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the portfolio. Try again.'**
  String get portfolioSaveFailed;

  /// No description provided for @portfolioDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the portfolio. Try again.'**
  String get portfolioDeleteFailed;

  /// No description provided for @portfolioDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete portfolio'**
  String get portfolioDeleteAction;

  /// No description provided for @portfolioDeleteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Asset and cash assignments will be cleared, and strategy configuration will also be deleted. The accounting ledger will not change.'**
  String get portfolioDeleteConfirmation;

  /// No description provided for @portfolioDeleteTransferDescription.
  ///
  /// In en, this message translates to:
  /// **'The {weight}% target and {assignmentCount} asset or cash assignments will move to the selected strategy. The original portfolio and its strategy configuration will be deleted.'**
  String portfolioDeleteTransferDescription(String weight, int assignmentCount);

  /// No description provided for @portfolioRemovalTransferHint.
  ///
  /// In en, this message translates to:
  /// **'Targets and assignments move in one transaction. The accounting ledger does not change.'**
  String get portfolioRemovalTransferHint;

  /// No description provided for @portfolioRemovalTransferTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer to'**
  String get portfolioRemovalTransferTargetLabel;

  /// No description provided for @portfolioRemovalTransferAction.
  ///
  /// In en, this message translates to:
  /// **'Transfer and delete'**
  String get portfolioRemovalTransferAction;

  /// No description provided for @portfolioStrategyCountSummary.
  ///
  /// In en, this message translates to:
  /// **'{strategy} · {count} capital strategies'**
  String portfolioStrategyCountSummary(String strategy, int count);

  /// No description provided for @portfolioLotsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lot} other{{count} lots}}'**
  String portfolioLotsCount(int count);

  /// No description provided for @portfolioScopedReturnUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Portfolio return starts after assignment history is recorded.'**
  String get portfolioScopedReturnUnavailable;

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

  /// Portfolio hub KPI label: current total cost basis
  ///
  /// In en, this message translates to:
  /// **'Cost basis'**
  String get portfolioHubCostBasisLabel;

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

  /// No description provided for @portfolioHubShowAllPositions.
  ///
  /// In en, this message translates to:
  /// **'Show all positions'**
  String get portfolioHubShowAllPositions;

  /// No description provided for @portfolioHubShowFewerPositions.
  ///
  /// In en, this message translates to:
  /// **'Show fewer positions'**
  String get portfolioHubShowFewerPositions;

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
  /// **'Insights'**
  String get portfolioHubEnginesTitle;

  /// No description provided for @portfolioHubSectionPositions.
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get portfolioHubSectionPositions;

  /// No description provided for @portfolioHubSectionAllocation.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get portfolioHubSectionAllocation;

  /// No description provided for @portfolioHubSectionInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get portfolioHubSectionInsights;

  /// No description provided for @portfolioHubConcentrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Concentration risk'**
  String get portfolioHubConcentrationTitle;

  /// No description provided for @portfolioHubConcentrationSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 position exceeds your thresholds} other{{count} positions exceed your thresholds}}'**
  String portfolioHubConcentrationSummary(int count);

  /// No description provided for @portfolioHubConcentrationDimensionAsset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get portfolioHubConcentrationDimensionAsset;

  /// No description provided for @portfolioHubConcentrationDimensionSector.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get portfolioHubConcentrationDimensionSector;

  /// No description provided for @portfolioHubConcentrationDimensionRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get portfolioHubConcentrationDimensionRegion;

  /// No description provided for @portfolioHubConcentrationDimensionCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get portfolioHubConcentrationDimensionCurrency;

  /// No description provided for @portfolioHubConcentrationSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get portfolioHubConcentrationSeverityWarning;

  /// No description provided for @portfolioHubConcentrationSeverityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get portfolioHubConcentrationSeverityCritical;

  /// No description provided for @portfolioHubConcentrationWeightLine.
  ///
  /// In en, this message translates to:
  /// **'{weight}% · cap {threshold}%'**
  String portfolioHubConcentrationWeightLine(String weight, String threshold);

  /// No description provided for @portfolioHubConcentrationRebalanceCta.
  ///
  /// In en, this message translates to:
  /// **'Review rebalance plan'**
  String get portfolioHubConcentrationRebalanceCta;

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
  /// **'VOO or VOO:60, QQQ:40'**
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
  /// **'Save recurring plan'**
  String get dcaSimulatorDraftAction;

  /// No description provided for @dcaPlanSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring plans'**
  String get dcaPlanSectionTitle;

  /// No description provided for @dcaPlanEmpty.
  ///
  /// In en, this message translates to:
  /// **'Run a simulation, then save it as a recurring plan.'**
  String get dcaPlanEmpty;

  /// No description provided for @dcaPlanSaved.
  ///
  /// In en, this message translates to:
  /// **'Recurring investment plan saved'**
  String get dcaPlanSaved;

  /// No description provided for @dcaPlanActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get dcaPlanActive;

  /// No description provided for @dcaPlanPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get dcaPlanPaused;

  /// No description provided for @dcaPlanNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next {date} · {amount} {currency}'**
  String dcaPlanNextDue(String date, String amount, String currency);

  /// No description provided for @dcaPlanExecuteNow.
  ///
  /// In en, this message translates to:
  /// **'Record contribution'**
  String get dcaPlanExecuteNow;

  /// No description provided for @dcaPlanPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get dcaPlanPause;

  /// No description provided for @dcaPlanResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get dcaPlanResume;

  /// No description provided for @dcaPlanDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recurring plan?'**
  String get dcaPlanDeleteTitle;

  /// No description provided for @dcaPlanDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the schedule and its future reminders. Recorded trades are kept.'**
  String get dcaPlanDeleteBody;

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

  /// Subtitle under the FinanceOS Today greeting
  ///
  /// In en, this message translates to:
  /// **'Today\'s financial overview'**
  String get homeTodayBriefSubtitle;

  /// Subtitle under the Life hub greeting
  ///
  /// In en, this message translates to:
  /// **'See what needs your attention today'**
  String get lifeBriefSubtitle;

  /// Hero card eyebrow on the Life hub
  ///
  /// In en, this message translates to:
  /// **'LifeOS'**
  String get lifeStageTitle;

  /// Life hero metric label when high-priority signals exist
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get lifeHeroMetricAttention;

  /// Life hero metric label when only normal signals exist
  ///
  /// In en, this message translates to:
  /// **'New updates'**
  String get lifeHeroMetricSignals;

  /// Life hero metric label when calm
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get lifeHeroMetricClear;

  /// Life hero when no signals
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention today'**
  String get lifeHeroHeadlineCalm;

  /// Life hero when normal updates exist
  ///
  /// In en, this message translates to:
  /// **'New updates across your domains'**
  String get lifeHeroHeadlineSignals;

  /// Life hero when high-priority updates exist
  ///
  /// In en, this message translates to:
  /// **'Some items need priority attention'**
  String get lifeHeroHeadlineAttention;

  /// Life hero supporting line
  ///
  /// In en, this message translates to:
  /// **'Important changes across {count} active domains'**
  String lifeHeroBody(int count);

  /// Collapsed sticky residual when high-priority signals exist
  ///
  /// In en, this message translates to:
  /// **'{count} to do'**
  String lifeStickyAttention(int count);

  /// Collapsed sticky residual for normal signals
  ///
  /// In en, this message translates to:
  /// **'{count} new updates'**
  String lifeStickySignals(int count);

  /// Collapsed sticky residual when calm
  ///
  /// In en, this message translates to:
  /// **'Nothing to do'**
  String get lifeStickyCalm;

  /// No description provided for @lifeReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get lifeReviewTitle;

  /// No description provided for @lifeReviewHeadline.
  ///
  /// In en, this message translates to:
  /// **'Close the loop'**
  String get lifeReviewHeadline;

  /// No description provided for @lifeReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Revisit decisions, assumptions, and follow-through in one place.'**
  String get lifeReviewSubtitle;

  /// No description provided for @lifeReviewPickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what you want to review.'**
  String get lifeReviewPickerSubtitle;

  /// Cross-domain signal list title
  ///
  /// In en, this message translates to:
  /// **'Latest updates'**
  String get lifeTimelineTitle;

  /// High-priority signal group title on Life hub
  ///
  /// In en, this message translates to:
  /// **'Priority attention'**
  String get lifeTimelinePriorityTitle;

  /// Empty attention list title
  ///
  /// In en, this message translates to:
  /// **'Quiet day'**
  String get lifeTimelineEmptyTitle;

  /// Empty state for the life signal list
  ///
  /// In en, this message translates to:
  /// **'You can still open a domain to view its details.'**
  String get lifeTimelineEmpty;

  /// Expand collapsed attention list
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String lifeTimelineShowMore(int count);

  /// Collapse expanded attention list
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get lifeTimelineShowLess;

  /// Domain chip on life timeline
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get lifeDomainFinance;

  /// Domain chip on life timeline
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get lifeDomainHealth;

  /// Domain chip on life timeline
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get lifeDomainKnowledge;

  /// Domain chip on life timeline
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get lifeDomainExecution;

  /// Desktop dock / spatial nav label for Life hub
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get lifeNavLabel;

  /// Life signal: finance day summary title
  ///
  /// In en, this message translates to:
  /// **'{count} finance entries today'**
  String lifeSignalFinanceDayTitle(String count);

  /// Life signal: finance day summary subtitle
  ///
  /// In en, this message translates to:
  /// **'{expense} expenses · {income} income'**
  String lifeSignalFinanceDaySubtitle(String expense, String income);

  /// Life signal title when current-month spending is nearing the budget limit
  ///
  /// In en, this message translates to:
  /// **'Monthly budget needs attention'**
  String get lifeSignalFinanceBudgetStrainedTitle;

  /// Life signal title when current-month spending exceeds the budget
  ///
  /// In en, this message translates to:
  /// **'Monthly budget exceeded'**
  String get lifeSignalFinanceBudgetOverTitle;

  /// Life signal subtitle for current-month budget pressure
  ///
  /// In en, this message translates to:
  /// **'{periodMonth} budget usage'**
  String lifeSignalFinanceBudgetSubtitle(String periodMonth);

  /// Life signal: strained recovery title
  ///
  /// In en, this message translates to:
  /// **'Recovery needs attention'**
  String get lifeSignalRecoveryTitle;

  /// Life signal: recovery subtitle
  ///
  /// In en, this message translates to:
  /// **'Your recovery status has a change worth reviewing'**
  String get lifeSignalRecoverySubtitle;

  /// Life signal: blocked execution title
  ///
  /// In en, this message translates to:
  /// **'{count} blocked actions'**
  String lifeSignalExecBlockedTitle(String count);

  /// Life signal: blocked execution subtitle
  ///
  /// In en, this message translates to:
  /// **'Some actions have not made progress'**
  String get lifeSignalExecBlockedSubtitle;

  /// Life signal: due execution title
  ///
  /// In en, this message translates to:
  /// **'{count} due actions'**
  String lifeSignalExecDueTitle(String count);

  /// Life signal: due execution subtitle
  ///
  /// In en, this message translates to:
  /// **'These actions are planned for today'**
  String get lifeSignalExecDueSubtitle;

  /// Life signal: knowledge inbox title
  ///
  /// In en, this message translates to:
  /// **'{count} notes in inbox'**
  String lifeSignalKnowledgeTitle(String count);

  /// Life signal: knowledge subtitle
  ///
  /// In en, this message translates to:
  /// **'Notes are waiting to be organized or reviewed'**
  String get lifeSignalKnowledgeSubtitle;

  /// Life signal: agent result fallback title
  ///
  /// In en, this message translates to:
  /// **'New financial insight'**
  String get lifeSignalAgentTitle;

  /// Life signal: agent result subtitle
  ///
  /// In en, this message translates to:
  /// **'Your financial brief has a new analysis'**
  String get lifeSignalAgentSubtitle;

  /// Fallback title for the route-backed Agent result detail
  ///
  /// In en, this message translates to:
  /// **'Insight details'**
  String get agentArtifactDetailTitle;

  /// Title when a route-backed Agent result cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Insight unavailable'**
  String get agentArtifactMissingTitle;

  /// Explanation when a route-backed Agent result cannot be opened
  ///
  /// In en, this message translates to:
  /// **'This result may have expired, been dismissed, or belong to a domain that is not active.'**
  String get agentArtifactMissingBody;

  /// Title of the Life signal evidence sheet
  ///
  /// In en, this message translates to:
  /// **'Update details'**
  String get lifeSignalDetailTitle;

  /// Evidence section in the Life signal sheet
  ///
  /// In en, this message translates to:
  /// **'Why this appeared'**
  String get lifeSignalEvidenceTitle;

  /// Recovery evidence shown before creating an action
  ///
  /// In en, this message translates to:
  /// **'Recovery score: {score}'**
  String lifeSignalRecoveryScoreEvidence(String score);

  /// Create an ExecutionOS action from a Life signal
  ///
  /// In en, this message translates to:
  /// **'Create action'**
  String get lifeSignalCreateAction;

  /// Accessible label for a Life update's independent create-action control
  ///
  /// In en, this message translates to:
  /// **'Create action for {update}'**
  String lifeSignalCreateActionFor(String update);

  /// Open domain settings before converting a signal to an action
  ///
  /// In en, this message translates to:
  /// **'Enable ExecutionOS'**
  String get lifeSignalEnableExecution;

  /// Open the domain surface that produced a Life signal
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get lifeSignalOpenSource;

  /// Confirmation title for a Life-to-Execution proposal
  ///
  /// In en, this message translates to:
  /// **'Create this action?'**
  String get lifeSignalActionConfirmTitle;

  /// Confirmation summary for a Life-to-Execution proposal
  ///
  /// In en, this message translates to:
  /// **'{title}\n\nSource: {source}'**
  String lifeSignalActionConfirmBody(String title, String source);

  /// Success message after applying a Life-to-Execution proposal
  ///
  /// In en, this message translates to:
  /// **'Action created with its source information attached.'**
  String get lifeSignalActionCreated;

  /// Failure message for a Life-to-Execution proposal
  ///
  /// In en, this message translates to:
  /// **'Could not create action: {error}'**
  String lifeSignalActionFailed(String error);

  /// Outcome badge when a completed cross-domain action's source signal is no longer active
  ///
  /// In en, this message translates to:
  /// **'{source}: signal no longer detected'**
  String executionOutcomeSignalCleared(String source);

  /// Outcome badge when a completed cross-domain action's source signal remains active
  ///
  /// In en, this message translates to:
  /// **'{source}: signal still detected'**
  String executionOutcomeSignalStillActive(String source);

  /// Open Execution Today after creating a Life action
  ///
  /// In en, this message translates to:
  /// **'Open Execution'**
  String get lifeSignalOpenExecution;

  /// Suggested action title for a Finance day signal
  ///
  /// In en, this message translates to:
  /// **'View today\'s finance activity'**
  String get lifeSignalActionReviewFinance;

  /// Suggested action title for a Finance budget pressure signal
  ///
  /// In en, this message translates to:
  /// **'View this month\'s budget'**
  String get lifeSignalActionReviewBudget;

  /// Suggested action title for a strained recovery signal
  ///
  /// In en, this message translates to:
  /// **'Protect recovery today'**
  String get lifeSignalActionProtectRecovery;

  /// Suggested action title for a Knowledge inbox signal
  ///
  /// In en, this message translates to:
  /// **'Review the Knowledge inbox'**
  String get lifeSignalActionReviewKnowledge;

  /// Suggested action title for a Finance agent signal
  ///
  /// In en, this message translates to:
  /// **'View the latest financial insight'**
  String get lifeSignalActionReviewAgent;

  /// Action note preserving the source signal evidence
  ///
  /// In en, this message translates to:
  /// **'From {source}: {detail}'**
  String lifeSignalActionNote(String source, String detail);

  /// Home FinanceOS agent result panel loading title
  ///
  /// In en, this message translates to:
  /// **'Loading financial insights'**
  String get financeAgentResultsLoading;

  /// Home FinanceOS agent result panel loading body
  ///
  /// In en, this message translates to:
  /// **'Recent financial reviews are loading.'**
  String get financeAgentResultsLoadingBody;

  /// Home FinanceOS agent result panel empty title
  ///
  /// In en, this message translates to:
  /// **'No financial insights yet'**
  String get financeAgentResultsEmptyTitle;

  /// Home FinanceOS agent result panel empty body
  ///
  /// In en, this message translates to:
  /// **'New planning review results will appear here.'**
  String get financeAgentResultsEmptyBody;

  /// Home FinanceOS agent result panel error title
  ///
  /// In en, this message translates to:
  /// **'Financial insights could not load'**
  String get financeAgentResultsErrorTitle;

  /// Home FinanceOS agent result panel error body
  ///
  /// In en, this message translates to:
  /// **'{error}'**
  String financeAgentResultsErrorBody(String error);

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
  /// **'Entry insight'**
  String get activityEntryDetailAiExplanation;

  /// Empty state when no AI explanation is available
  ///
  /// In en, this message translates to:
  /// **'No insight available for this entry.'**
  String get activityEntryDetailNoExplanation;

  /// Transaction detail posting line count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String activityEntryDetailLegCount(int count);

  /// Transaction detail section title for the full posting breakdown
  ///
  /// In en, this message translates to:
  /// **'Ledger breakdown'**
  String get activityEntryDetailLedgerTitle;

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

  /// Affordance under Income in the Activity actions sheet
  ///
  /// In en, this message translates to:
  /// **'Record salary, dividend or other income'**
  String get activityActionIncomeHint;

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
  /// **'Add wealth item'**
  String get accountsActionsTitle;

  /// Subtitle for the Wealth quick-add panel
  ///
  /// In en, this message translates to:
  /// **'Choose what you want to add to your net worth.'**
  String get wealthActionPanelSubtitle;

  /// Summary under the progressive Asset choice in the Wealth quick-add panel
  ///
  /// In en, this message translates to:
  /// **'Cash, deposits, investments, or physical assets'**
  String get wealthActionPanelAssetHint;

  /// Subtitle for the second-level asset type picker
  ///
  /// In en, this message translates to:
  /// **'Choose the type that best fits this asset.'**
  String get wealthActionPanelAssetSubtitle;

  /// Wealth quick-add section heading for account containers
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get wealthActionPanelAccountsGroup;

  /// Wealth quick-add section heading for cash/deposit/wealth products
  ///
  /// In en, this message translates to:
  /// **'Deposits & products'**
  String get wealthActionPanelFinancialGroup;

  /// Wealth quick-add section heading for real estate and vehicles
  ///
  /// In en, this message translates to:
  /// **'Physical assets'**
  String get wealthActionPanelPhysicalGroup;

  /// Wealth quick-add section heading for liabilities
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get wealthActionPanelLiabilitiesGroup;

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

  /// No description provided for @superFabIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get superFabIncome;

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
  /// **'Choose two accounts with different currencies, then confirm the amount sent and received.'**
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

  /// Home quick action label that opens the new account flow.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get homeQuickAddAccount;

  /// Home quick action label that opens the new expense or journal entry flow.
  ///
  /// In en, this message translates to:
  /// **'Record entry'**
  String get homeQuickRecordEntry;

  /// Home quick action label that opens the activity ingest flow.
  ///
  /// In en, this message translates to:
  /// **'Import statements'**
  String get homeQuickImport;

  /// Tooltip for the Finance home privacy button when tapping will hide exact monetary amounts.
  ///
  /// In en, this message translates to:
  /// **'Hide amounts'**
  String get financePrivacyHideAmountsTooltip;

  /// Tooltip for the Finance home privacy button when tapping will reveal exact monetary amounts.
  ///
  /// In en, this message translates to:
  /// **'Show amounts'**
  String get financePrivacyShowAmountsTooltip;

  /// No description provided for @homeNetWorthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add an account or import data to see net worth in {currency}'**
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

  /// Account used to fund liability repayments
  ///
  /// In en, this message translates to:
  /// **'Payer account'**
  String get liabilityFieldPayerAccount;

  /// Helper below the liability payer account picker
  ///
  /// In en, this message translates to:
  /// **'Scheduled repayments will be recorded against this account.'**
  String get liabilityPayerAccountHint;

  /// Liability form notice when no custody account can fund repayments
  ///
  /// In en, this message translates to:
  /// **'No eligible payment account is available. Create a cash or bank account first.'**
  String get liabilityPayerAccountEmpty;

  /// Liability save guard when no payer account is selected
  ///
  /// In en, this message translates to:
  /// **'Choose a payer account before saving.'**
  String get liabilityPayerAccountRequired;

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

  /// Optional note field for a liability
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get liabilityFieldNote;

  /// No description provided for @liabilityDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule details'**
  String get liabilityDetailsTitle;

  /// Collapsed liability schedule summary for loans
  ///
  /// In en, this message translates to:
  /// **'Rate type, start date & repayment'**
  String get liabilityDetailsLoanSummary;

  /// Collapsed liability schedule summary for credit cards
  ///
  /// In en, this message translates to:
  /// **'Billing dates & note'**
  String get liabilityDetailsCardSummary;

  /// Button/title for editing liability metadata
  ///
  /// In en, this message translates to:
  /// **'Edit liability'**
  String get liabilityEditAction;

  /// Info banner explaining liability edit mode limitations
  ///
  /// In en, this message translates to:
  /// **'Name, payer account and note can be edited here. Principal, rate and term stay locked because they drive the repayment schedule.'**
  String get liabilityEditMetadataOnlyHint;

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

  /// Validation shown when liability and payer account currencies differ
  ///
  /// In en, this message translates to:
  /// **'Use the payer account currency: {currency}'**
  String liabilityValidationAccountCurrency(String currency);

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

  /// Title of the liability payment date sheet
  ///
  /// In en, this message translates to:
  /// **'Record period {period} payment'**
  String liabilityPaymentSheetTitle(int period);

  /// Read-only payment amount summary in the liability payment sheet
  ///
  /// In en, this message translates to:
  /// **'Payment amount · {amount}'**
  String liabilityPaymentSheetAmount(String amount);

  /// Date field label in the liability payment sheet
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get liabilityPaymentSheetDate;

  /// Helper below the liability payment date field
  ///
  /// In en, this message translates to:
  /// **'Choose the date the money left the payer account.'**
  String get liabilityPaymentSheetDateHint;

  /// Submit action in the liability payment sheet
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get liabilityPaymentSheetSubmit;

  /// No description provided for @liabilityScheduleMarkPaidNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Assign a payer account before marking periods paid.'**
  String get liabilityScheduleMarkPaidNoAccount;

  /// Confirmation title before reopening a paid liability period
  ///
  /// In en, this message translates to:
  /// **'Undo payment for period {period}?'**
  String liabilityScheduleUndoConfirmTitle(int period);

  /// Confirmation body before undoing a liability payment
  ///
  /// In en, this message translates to:
  /// **'This removes the linked ledger transaction and returns the period to pending.'**
  String get liabilityScheduleUndoConfirmBody;

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

  /// No description provided for @physicalAssetDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Asset details'**
  String get physicalAssetDetailsTitle;

  /// No description provided for @physicalAssetVehicleDetailsSummary.
  ///
  /// In en, this message translates to:
  /// **'Valuation & depreciation'**
  String get physicalAssetVehicleDetailsSummary;

  /// No description provided for @physicalAssetRealEstateDetailsSummary.
  ///
  /// In en, this message translates to:
  /// **'Address, valuation & linked loan'**
  String get physicalAssetRealEstateDetailsSummary;

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
  /// **'Valuation history will be marked as deleted. Devices that synced previously may still retain a recoverable copy.'**
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

  /// No description provided for @fxRatesSyncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Rates updated'**
  String get fxRatesSyncCompleted;

  /// No description provided for @fxRatesSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sync rates: {error}'**
  String fxRatesSyncFailed(String error);

  /// No description provided for @fxRatesSyncPartial.
  ///
  /// In en, this message translates to:
  /// **'Updated {synced} of {total} currency pairs. {error}'**
  String fxRatesSyncPartial(int synced, int total, String error);

  /// No description provided for @fxRatesOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency monitor'**
  String get fxRatesOverviewTitle;

  /// No description provided for @fxRatesOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A quiet view of the rates used across your wealth history.'**
  String get fxRatesOverviewSubtitle;

  /// No description provided for @fxRatesStatusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get fxRatesStatusSyncing;

  /// No description provided for @fxRatesStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get fxRatesStatusFailed;

  /// No description provided for @fxRatesStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get fxRatesStatusReady;

  /// No description provided for @fxRatesStatusLocal.
  ///
  /// In en, this message translates to:
  /// **'Local history'**
  String get fxRatesStatusLocal;

  /// No description provided for @fxRatesTrackedPairsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tracked pairs'**
  String get fxRatesTrackedPairsLabel;

  /// No description provided for @fxRatesBaseCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Base currency'**
  String get fxRatesBaseCurrencyLabel;

  /// No description provided for @fxRatesLastUpdatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get fxRatesLastUpdatedLabel;

  /// No description provided for @fxRatesLatestObservation.
  ///
  /// In en, this message translates to:
  /// **'Latest observation'**
  String get fxRatesLatestObservation;

  /// No description provided for @fxRatesHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get fxRatesHistoryTitle;

  /// No description provided for @fxRatesRange7D.
  ///
  /// In en, this message translates to:
  /// **'7D'**
  String get fxRatesRange7D;

  /// No description provided for @fxRatesRange30D.
  ///
  /// In en, this message translates to:
  /// **'30D'**
  String get fxRatesRange30D;

  /// No description provided for @fxRatesRange90D.
  ///
  /// In en, this message translates to:
  /// **'90D'**
  String get fxRatesRange90D;

  /// No description provided for @fxRatesRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get fxRatesRangeAll;

  /// No description provided for @fxRatesHistoryEntries.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get fxRatesHistoryEntries;

  /// No description provided for @fxRatesViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get fxRatesViewDetails;

  /// No description provided for @fxRatesNotEnoughHistory.
  ///
  /// In en, this message translates to:
  /// **'More observations will reveal a trend.'**
  String get fxRatesNotEnoughHistory;

  /// No description provided for @fxRatesRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Showing the selected window. Switch to All for the full history.'**
  String get fxRatesRangeHint;

  /// No description provided for @fxRatesAsOfValue.
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String fxRatesAsOfValue(String date);

  /// No description provided for @fxRatesPairsTracked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pairs} one{1 pair} other{{count} pairs}}'**
  String fxRatesPairsTracked(int count);

  /// No description provided for @fxRatesEntriesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 entry} other{{count} entries}}'**
  String fxRatesEntriesCount(int count);

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

  /// No description provided for @fxRatesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this FX rate?'**
  String get fxRatesDeleteConfirmTitle;

  /// No description provided for @fxRatesDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the recorded rate for this currency pair and date.'**
  String get fxRatesDeleteConfirmBody;

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

  /// No description provided for @dashboardValuationTrustMissingFx.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 holding excluded — missing FX to {currency}} other{{count} holdings excluded — missing FX to {currency}}}'**
  String dashboardValuationTrustMissingFx(int count, String currency);

  /// No description provided for @dashboardValuationTrustWarning.
  ///
  /// In en, this message translates to:
  /// **'{staleCount, plural, =0{{quality} valuation · as of {asOf}} one{1 stale holding · {quality} · as of {asOf}} other{{staleCount} stale holdings · {quality} · as of {asOf}}}'**
  String dashboardValuationTrustWarning(
    int staleCount,
    String quality,
    String asOf,
  );

  /// No description provided for @dashboardValuationTrustReady.
  ///
  /// In en, this message translates to:
  /// **'{quality} valuation · as of {asOf}'**
  String dashboardValuationTrustReady(String quality, String asOf);

  /// No description provided for @dashboardValuationTrustAction.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get dashboardValuationTrustAction;

  /// No description provided for @dashboardValuationTrustSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Valuation confidence'**
  String get dashboardValuationTrustSheetTitle;

  /// No description provided for @dashboardValuationTrustQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality: {quality}'**
  String dashboardValuationTrustQuality(String quality);

  /// No description provided for @dashboardValuationTrustAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {asOf}'**
  String dashboardValuationTrustAsOf(String asOf);

  /// No description provided for @dashboardValuationTrustStale.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 holding has a stale price} other{{count} holdings have stale prices}}'**
  String dashboardValuationTrustStale(int count);

  /// No description provided for @dashboardValuationQualityRealTime.
  ///
  /// In en, this message translates to:
  /// **'Real-time'**
  String get dashboardValuationQualityRealTime;

  /// No description provided for @dashboardValuationQualityDelayed.
  ///
  /// In en, this message translates to:
  /// **'Delayed'**
  String get dashboardValuationQualityDelayed;

  /// No description provided for @dashboardValuationQualityDailyClose.
  ///
  /// In en, this message translates to:
  /// **'Daily close'**
  String get dashboardValuationQualityDailyClose;

  /// No description provided for @dashboardValuationQualityManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get dashboardValuationQualityManual;

  /// No description provided for @dashboardValuationQualityEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get dashboardValuationQualityEstimated;

  /// No description provided for @dashboardValuationQualityStale.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get dashboardValuationQualityStale;

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

  /// No description provided for @settingsAccentSeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsAccentSeedTitle;

  /// No description provided for @accentSeedCyan.
  ///
  /// In en, this message translates to:
  /// **'Turquoise'**
  String get accentSeedCyan;

  /// No description provided for @accentSeedViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get accentSeedViolet;

  /// No description provided for @accentSeedIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get accentSeedIndigo;

  /// No description provided for @settingsSurfaceStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Surface style'**
  String get settingsSurfaceStyleTitle;

  /// No description provided for @surfaceStyleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get surfaceStyleStandard;

  /// No description provided for @surfaceStyleOled.
  ///
  /// In en, this message translates to:
  /// **'OLED black'**
  String get surfaceStyleOled;

  /// No description provided for @surfaceStyleHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get surfaceStyleHighContrast;

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

  /// Generic refresh/reload action label
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

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

  /// No description provided for @commonSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get commonSaved;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get commonDeleted;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Centered list reveal control: show N more items
  ///
  /// In en, this message translates to:
  /// **'More · {count}'**
  String commonRevealMore(int count);

  /// Centered list reveal control: collapse expanded items
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get commonRevealLess;

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

  /// No description provided for @commonRequiredField.
  ///
  /// In en, this message translates to:
  /// **'Enter a value.'**
  String get commonRequiredField;

  /// No description provided for @commonInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number.'**
  String get commonInvalidNumber;

  /// No description provided for @commonSafeErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t complete that. Please try again.'**
  String get commonSafeErrorMessage;

  /// No description provided for @shellMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get shellMoreActions;

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

  /// Generic failure toast shown when a commit-first form submission fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your changes. Try again.'**
  String get commonSaveFailed;

  /// No description provided for @commonDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete this item. Try again.'**
  String get commonDeleteFailed;

  /// Generic undo affordance label.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonUndoSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Change undone'**
  String get commonUndoSucceeded;

  /// No description provided for @commonUndoFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t undo the change. Try again.'**
  String get commonUndoFailed;

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

  /// Secondary action on the error / not-found page that pops the previous route when one exists.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get routeGoBack;

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
  /// **'Assistant: {query}'**
  String commandPaletteAskAi(String query);

  /// Tiny badge on the command palette result pane showing the answer was computed on-device
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get askAiResultLocalBadge;

  /// Shown when the natural-language parser can't resolve a query locally
  ///
  /// In en, this message translates to:
  /// **'Can\'t answer this here. Continue in the AI assistant for a full conversation.'**
  String get askAiResultNoLocalMatch;

  /// Link below the no-local-match notice that opens /settings/ai-history with the query prefilled
  ///
  /// In en, this message translates to:
  /// **'Continue in AI assistant'**
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

  /// Command palette: open a new AI chat (via askAi helper, routes through aiContextProvider)
  ///
  /// In en, this message translates to:
  /// **'Open assistant'**
  String get commandPaletteOpenAi;

  /// Compact visible label for the assistant action in mobile navigation
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get navAskAi;

  /// Command palette: open the read-only AI session history under Settings
  ///
  /// In en, this message translates to:
  /// **'AI history'**
  String get commandPaletteAiHistory;

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

  /// Banner shown when an Android GitHub APK update is available
  ///
  /// In en, this message translates to:
  /// **'NaviWealth {version} is available.'**
  String nativeUpdateAvailable(String version);

  /// Action to manually check for a new Android APK release
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get nativeUpdateCheck;

  /// Button label while manually checking for an Android APK release
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get nativeUpdateChecking;

  /// Toast shown when no newer Android APK release is available
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date.'**
  String get nativeUpdateUpToDate;

  /// Toast shown when the manual Android update check fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates. Please try again later.'**
  String get nativeUpdateCheckFailed;

  /// Toast shown when the Android update manifest is not configured
  ///
  /// In en, this message translates to:
  /// **'Updates are unavailable for this build.'**
  String get nativeUpdateUnavailable;

  /// Title of the Android OS notification for a new release
  ///
  /// In en, this message translates to:
  /// **'NaviWealth update available'**
  String get nativeUpdateNotificationTitle;

  /// Body of the Android OS notification for a new release
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready to install.'**
  String nativeUpdateNotificationBody(String version);

  /// Action to download and install the Android APK update
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get nativeUpdateApply;

  /// Action to dismiss the native app update banner for this version
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get nativeUpdateDismiss;

  /// Progress label shown while the Android APK is downloaded
  ///
  /// In en, this message translates to:
  /// **'Downloading update ({percent}%)'**
  String nativeUpdateDownloading(int percent);

  /// Toast shown when Android blocks installs from this app
  ///
  /// In en, this message translates to:
  /// **'Allow NaviWealth to install updates in Android settings, then tap Update again.'**
  String get nativeUpdateInstallPermission;

  /// Toast shown when the APK SHA-256 does not match the GitHub manifest
  ///
  /// In en, this message translates to:
  /// **'The downloaded update failed integrity verification.'**
  String get nativeUpdateVerificationFailed;

  /// Toast shown when package, signature, or version checks reject the APK
  ///
  /// In en, this message translates to:
  /// **'The downloaded update is not a valid NaviWealth package.'**
  String get nativeUpdatePackageMismatch;

  /// Toast shown when the system package installer cannot be started
  ///
  /// In en, this message translates to:
  /// **'Android could not start the update installer.'**
  String get nativeUpdateInstallFailed;

  /// Toast shown when a GitHub update download fails
  ///
  /// In en, this message translates to:
  /// **'Could not download the update. Please try again later.'**
  String get nativeUpdateDownloadFailed;

  /// Toast shown after the Android package installer is launched
  ///
  /// In en, this message translates to:
  /// **'Update downloaded. Confirm installation in Android.'**
  String get nativeUpdateInstallStarted;

  /// Subtitle on the login screen, sits below the app name.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authLoginTitle;

  /// Subtitle on the registration screen, sits below the app name.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterTitle;

  /// Primary action button on the login form.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authLoginSubmit;

  /// Primary action button on the registration form.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterSubmit;

  /// Secondary action on the login form that switches to registration mode.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get authRegisterSwitch;

  /// Secondary action on the registration form that switches back to login mode.
  ///
  /// In en, this message translates to:
  /// **'Sign in instead'**
  String get authLoginSwitch;

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

  /// No description provided for @authRegisterErrorAccountExists.
  ///
  /// In en, this message translates to:
  /// **'An account already exists. Sign in instead.'**
  String get authRegisterErrorAccountExists;

  /// Inline banner shown on the login screen after the auth controller dropped an expired session.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get authLoginNoticeSessionExpired;

  /// Subtitle on the login page when a local-only user is registering for cloud sync.
  ///
  /// In en, this message translates to:
  /// **'Create a new cloud account and sync your existing data'**
  String get authUpgradeRegisterHint;

  /// Subtitle on the login page when a local-only user is signing in to an existing cloud account.
  ///
  /// In en, this message translates to:
  /// **'Sign in to an existing account (local data is kept separately)'**
  String get authUpgradeConnectHint;

  /// Submit button when a local-only user registers to upgrade to cloud.
  ///
  /// In en, this message translates to:
  /// **'Create & Sync'**
  String get authUpgradeRegisterSubmit;

  /// Submit button when a local-only user signs in to connect to cloud.
  ///
  /// In en, this message translates to:
  /// **'Sign In & Sync'**
  String get authUpgradeConnectSubmit;

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

  /// Settings row title for disabling cloud sync while keeping this device local.
  ///
  /// In en, this message translates to:
  /// **'Switch to Local Mode'**
  String get settingsSwitchToLocalTitle;

  /// Settings row subtitle for switching a cloud account to local-only mode.
  ///
  /// In en, this message translates to:
  /// **'Disable cloud sync while keeping data on this device'**
  String get settingsSwitchToLocalSubtitle;

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

  /// Label for the current net-worth metric above the dashboard trend chart.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get dashboardTrendMetricCurrent;

  /// Label for the selected-range net-worth change metric above the dashboard trend chart.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get dashboardTrendMetricChange;

  /// Label for the selected date range metric above the dashboard trend chart.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get dashboardTrendMetricRange;

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

  /// Analytics overview metric label for net worth.
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get analyticsOverviewNetWorth;

  /// Analytics overview metric label for month-to-date change.
  ///
  /// In en, this message translates to:
  /// **'Month change'**
  String get analyticsOverviewMonthlyChange;

  /// Analytics overview metric label for current-period cash flow.
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get analyticsOverviewCashFlow;

  /// Analytics overview metric label for FIRE projected ETA.
  ///
  /// In en, this message translates to:
  /// **'FIRE ETA'**
  String get analyticsOverviewFireEta;

  /// Analytics overview FIRE ETA value in months.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, =1 {1 month} other {{months} months}}'**
  String analyticsOverviewFireEtaMonths(int months);

  /// Analytics overview value when FIRE plan is not configured.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get analyticsOverviewFireNotConfigured;

  /// Analytics overview unavailable metric placeholder.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get analyticsOverviewUnavailable;

  /// Analytics card title for recent monthly cash-flow trend.
  ///
  /// In en, this message translates to:
  /// **'Cash-flow trend'**
  String get analyticsCashFlowTrendTitle;

  /// Analytics cash-flow trend card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Net operating cash flow across the last six months.'**
  String get analyticsCashFlowTrendSubtitle;

  /// Bar chart series label for net cash flow.
  ///
  /// In en, this message translates to:
  /// **'Net cash flow'**
  String get analyticsCashFlowTrendNetSeries;

  /// Metric label for six-month average net cash flow.
  ///
  /// In en, this message translates to:
  /// **'6M avg net'**
  String get analyticsCashFlowTrendAverageNet;

  /// Metric label for current month cash inflow.
  ///
  /// In en, this message translates to:
  /// **'This month inflow'**
  String get analyticsCashFlowTrendInflow;

  /// Metric label for current month cash outflow.
  ///
  /// In en, this message translates to:
  /// **'This month outflow'**
  String get analyticsCashFlowTrendOutflow;

  /// Accessibility label for the analytics cash-flow trend chart.
  ///
  /// In en, this message translates to:
  /// **'Recent monthly net cash-flow bar chart'**
  String get analyticsCashFlowTrendSemantic;

  /// Analytics cash-flow card error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load cash-flow trend.'**
  String get analyticsCashFlowTrendLoadError;

  /// Analytics card title for FIRE progress.
  ///
  /// In en, this message translates to:
  /// **'FIRE progress'**
  String get analyticsFireProgressTitle;

  /// Analytics FIRE progress card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Investable assets against your target and current runway.'**
  String get analyticsFireProgressSubtitle;

  /// FIRE progress percent caption.
  ///
  /// In en, this message translates to:
  /// **'{value} of target'**
  String analyticsFireProgressPercent(String value);

  /// Metric label for FIRE investable assets.
  ///
  /// In en, this message translates to:
  /// **'Investable'**
  String get analyticsFireProgressInvestable;

  /// Metric label for FIRE target net worth.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get analyticsFireProgressTarget;

  /// Metric label for FIRE withdrawal rate.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal'**
  String get analyticsFireProgressWithdrawalRate;

  /// Metric label for FIRE cash bucket months.
  ///
  /// In en, this message translates to:
  /// **'Cash runway'**
  String get analyticsFireProgressCashRunway;

  /// Metric label for FIRE ETA.
  ///
  /// In en, this message translates to:
  /// **'ETA'**
  String get analyticsFireProgressEta;

  /// Generic month count for FIRE progress metrics.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, =1 {1 month} other {{months} months}}'**
  String analyticsFireProgressMonths(int months);

  /// FIRE cash runway value when expenses are zero.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get analyticsFireProgressUnlimited;

  /// FIRE progress card empty-state title.
  ///
  /// In en, this message translates to:
  /// **'FIRE plan not configured'**
  String get analyticsFireProgressNotConfiguredTitle;

  /// FIRE progress card empty-state body.
  ///
  /// In en, this message translates to:
  /// **'Set a FIRE target to track progress and runway here.'**
  String get analyticsFireProgressNotConfiguredBody;

  /// Analytics FIRE progress card error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load FIRE progress.'**
  String get analyticsFireProgressLoadError;

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

  /// Expandable FIRE depth section title
  ///
  /// In en, this message translates to:
  /// **'Resilience checks'**
  String get fireDepthTitle;

  /// Expandable FIRE depth section subtitle
  ///
  /// In en, this message translates to:
  /// **'Automatic checks for the risks that matter'**
  String get fireDepthSubtitle;

  /// FIRE hero progress caption under the slim bar
  ///
  /// In en, this message translates to:
  /// **'{progress} · {current} of {target}'**
  String fireHeroProgressLine(String progress, String current, String target);

  /// Label above the single suggested FIRE action
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get fireHeroNextStepLabel;

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

  /// No description provided for @fireBudgetNoDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget signal not available'**
  String get fireBudgetNoDataTitle;

  /// No description provided for @fireBudgetNoDataDetail.
  ///
  /// In en, this message translates to:
  /// **'Set a monthly budget to connect current spending pressure to this FIRE plan.'**
  String get fireBudgetNoDataDetail;

  /// No description provided for @fireBudgetComfortableTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget supports the plan'**
  String get fireBudgetComfortableTitle;

  /// No description provided for @fireBudgetComfortableDetail.
  ///
  /// In en, this message translates to:
  /// **'This month’s spending is within the comfortable range.'**
  String get fireBudgetComfortableDetail;

  /// No description provided for @fireBudgetStrainedTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget pressure is rising'**
  String get fireBudgetStrainedTitle;

  /// No description provided for @fireBudgetStrainedDetail.
  ///
  /// In en, this message translates to:
  /// **'Spending is near the monthly limit; protect the planned surplus.'**
  String get fireBudgetStrainedDetail;

  /// No description provided for @fireBudgetOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly budget exceeded'**
  String get fireBudgetOverTitle;

  /// No description provided for @fireBudgetOverDetail.
  ///
  /// In en, this message translates to:
  /// **'Current spending pressure may reduce the surplus assumed by this FIRE plan.'**
  String get fireBudgetOverDetail;

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
  /// **'Review monthly, quarterly, and annual snapshots. Metrics are calculated by rules; AI only explains the results.'**
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

  /// No description provided for @rebalanceExecutionWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get rebalanceExecutionWorkspaceTitle;

  /// No description provided for @rebalanceExecutionResumeAction.
  ///
  /// In en, this message translates to:
  /// **'Resume execution'**
  String get rebalanceExecutionResumeAction;

  /// No description provided for @rebalanceExecutionReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace active execution?'**
  String get rebalanceExecutionReplaceTitle;

  /// No description provided for @rebalanceExecutionReplaceBody.
  ///
  /// In en, this message translates to:
  /// **'Your active execution was created from a different plan. Trades already recorded remain in the ledger. Undo from the old queue is permanently disabled when this plan starts.'**
  String get rebalanceExecutionReplaceBody;

  /// No description provided for @rebalanceExecutionReplaceAction.
  ///
  /// In en, this message translates to:
  /// **'Replace and continue'**
  String get rebalanceExecutionReplaceAction;

  /// No description provided for @rebalanceExecutionProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} resolved'**
  String rebalanceExecutionProgress(int done, int total);

  /// No description provided for @rebalanceExecutionApplyAction.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get rebalanceExecutionApplyAction;

  /// No description provided for @rebalanceExecutionUndoAction.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get rebalanceExecutionUndoAction;

  /// No description provided for @rebalanceExecutionStopAction.
  ///
  /// In en, this message translates to:
  /// **'Stop after current'**
  String get rebalanceExecutionStopAction;

  /// No description provided for @rebalanceExecutionStoppedToast.
  ///
  /// In en, this message translates to:
  /// **'Stopped after the current trade.'**
  String get rebalanceExecutionStoppedToast;

  /// No description provided for @rebalanceExecutionCompletedToast.
  ///
  /// In en, this message translates to:
  /// **'The batch completed successfully.'**
  String get rebalanceExecutionCompletedToast;

  /// No description provided for @rebalanceExecutionPartialToast.
  ///
  /// In en, this message translates to:
  /// **'{completed} completed; {failed} need attention.'**
  String rebalanceExecutionPartialToast(int completed, int failed);

  /// No description provided for @rebalanceExecutionFailedToast.
  ///
  /// In en, this message translates to:
  /// **'The batch stopped; {failed} need attention.'**
  String rebalanceExecutionFailedToast(int failed);

  /// No description provided for @rebalanceExecutionRecoveryToast.
  ///
  /// In en, this message translates to:
  /// **'The batch stopped because an item needs recovery.'**
  String get rebalanceExecutionRecoveryToast;

  /// No description provided for @rebalanceExecutionArchiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive execution'**
  String get rebalanceExecutionArchiveAction;

  /// No description provided for @rebalanceExecutionArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive this execution?'**
  String get rebalanceExecutionArchiveTitle;

  /// No description provided for @rebalanceExecutionArchiveBody.
  ///
  /// In en, this message translates to:
  /// **'Archiving closes this queue. Trades already recorded remain in the ledger, and Undo from this queue is permanently disabled. Reviewed details and progress remain visible, but skipped and pending trades can no longer be changed.'**
  String get rebalanceExecutionArchiveBody;

  /// No description provided for @rebalanceExecutionArchiveAppliedBody.
  ///
  /// In en, this message translates to:
  /// **'Applied trades will not be undone. Undo them before archiving if you need to reverse their ledger entries.'**
  String get rebalanceExecutionArchiveAppliedBody;

  /// No description provided for @rebalanceExecutionBusyLeaveBlocked.
  ///
  /// In en, this message translates to:
  /// **'Finish or stop the current operation before leaving.'**
  String get rebalanceExecutionBusyLeaveBlocked;

  /// No description provided for @rebalanceExecutionReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get rebalanceExecutionReviewAction;

  /// No description provided for @rebalanceExecutionAddPriceAction.
  ///
  /// In en, this message translates to:
  /// **'Add price'**
  String get rebalanceExecutionAddPriceAction;

  /// No description provided for @rebalanceExecutionRetryApplyAction.
  ///
  /// In en, this message translates to:
  /// **'Retry execution'**
  String get rebalanceExecutionRetryApplyAction;

  /// No description provided for @rebalanceExecutionRetryUndoAction.
  ///
  /// In en, this message translates to:
  /// **'Retry undo'**
  String get rebalanceExecutionRetryUndoAction;

  /// No description provided for @rebalanceExecutionSkipAction.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get rebalanceExecutionSkipAction;

  /// No description provided for @rebalanceExecutionReopenAction.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get rebalanceExecutionReopenAction;

  /// No description provided for @rebalanceExecutionNotFound.
  ///
  /// In en, this message translates to:
  /// **'This execution is unavailable or belongs to another user.'**
  String get rebalanceExecutionNotFound;

  /// No description provided for @rebalanceExecutionEmptyQueue.
  ///
  /// In en, this message translates to:
  /// **'This plan has no trades to execute.'**
  String get rebalanceExecutionEmptyQueue;

  /// No description provided for @rebalanceExecutionEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Review trade'**
  String get rebalanceExecutionEditorTitle;

  /// No description provided for @rebalanceExecutionSaveReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Save review'**
  String get rebalanceExecutionSaveReviewAction;

  /// No description provided for @rebalanceExecutionAssetLabel.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get rebalanceExecutionAssetLabel;

  /// No description provided for @rebalanceExecutionCashAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash account (optional)'**
  String get rebalanceExecutionCashAccountLabel;

  /// No description provided for @rebalanceExecutionManualPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'Automatic pricing is unavailable. Enter a price to continue without a quote.'**
  String get rebalanceExecutionManualPriceHelper;

  /// No description provided for @rebalanceExecutionIssuePriceRequired.
  ///
  /// In en, this message translates to:
  /// **'No usable price is available. Add a price to continue.'**
  String get rebalanceExecutionIssuePriceRequired;

  /// No description provided for @rebalanceExecutionIssueInvalidReview.
  ///
  /// In en, this message translates to:
  /// **'Some trade details are invalid. Review them before continuing.'**
  String get rebalanceExecutionIssueInvalidReview;

  /// No description provided for @rebalanceExecutionIssueStaleReview.
  ///
  /// In en, this message translates to:
  /// **'This review is out of date. Review the latest details before continuing.'**
  String get rebalanceExecutionIssueStaleReview;

  /// No description provided for @rebalanceExecutionIssueHoldingsChanged.
  ///
  /// In en, this message translates to:
  /// **'Available holdings changed. Review the quantity before continuing.'**
  String get rebalanceExecutionIssueHoldingsChanged;

  /// No description provided for @rebalanceExecutionIssueOwnerChanged.
  ///
  /// In en, this message translates to:
  /// **'The active profile changed, so this trade cannot be executed safely.'**
  String get rebalanceExecutionIssueOwnerChanged;

  /// No description provided for @rebalanceExecutionIssueApplyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price lookup or execution is temporarily unavailable. Retry the execution, or add a price if one is missing.'**
  String get rebalanceExecutionIssueApplyUnavailable;

  /// No description provided for @rebalanceExecutionIssueUndoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Undo is temporarily unavailable. Retry the undo operation.'**
  String get rebalanceExecutionIssueUndoUnavailable;

  /// No description provided for @rebalanceExecutionIssueUnsafe.
  ///
  /// In en, this message translates to:
  /// **'This trade cannot be continued safely. Skip it or archive the execution.'**
  String get rebalanceExecutionIssueUnsafe;

  /// No description provided for @rebalanceExecutionIssueRecoveryCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Recovery data is incomplete. Verify the ledger before archiving this execution.'**
  String get rebalanceExecutionIssueRecoveryCorrupt;

  /// No description provided for @rebalanceExecutionIssueLegacyApplyFailure.
  ///
  /// In en, this message translates to:
  /// **'A previous execution attempt failed. Retry the execution.'**
  String get rebalanceExecutionIssueLegacyApplyFailure;

  /// No description provided for @rebalanceExecutionIssueLegacyUndoFailure.
  ///
  /// In en, this message translates to:
  /// **'A previous undo attempt failed. Retry the undo operation.'**
  String get rebalanceExecutionIssueLegacyUndoFailure;

  /// No description provided for @rebalanceExecutionStateNeedsDetails.
  ///
  /// In en, this message translates to:
  /// **'Needs details'**
  String get rebalanceExecutionStateNeedsDetails;

  /// No description provided for @rebalanceExecutionStateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get rebalanceExecutionStateReady;

  /// No description provided for @rebalanceExecutionStateApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get rebalanceExecutionStateApplying;

  /// No description provided for @rebalanceExecutionStateApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get rebalanceExecutionStateApplied;

  /// No description provided for @rebalanceExecutionStateApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Apply failed'**
  String get rebalanceExecutionStateApplyFailed;

  /// No description provided for @rebalanceExecutionStateUndoing.
  ///
  /// In en, this message translates to:
  /// **'Undoing'**
  String get rebalanceExecutionStateUndoing;

  /// No description provided for @rebalanceExecutionStateUndone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get rebalanceExecutionStateUndone;

  /// No description provided for @rebalanceExecutionStateUndoFailed.
  ///
  /// In en, this message translates to:
  /// **'Undo failed'**
  String get rebalanceExecutionStateUndoFailed;

  /// No description provided for @rebalanceExecutionStateSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get rebalanceExecutionStateSkipped;

  /// No description provided for @rebalanceExecutionStateRecoveryBlocked.
  ///
  /// In en, this message translates to:
  /// **'Needs recovery'**
  String get rebalanceExecutionStateRecoveryBlocked;

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

  /// Title of the sheet that exposes the rebalance feature's drift-trigger thresholds — distinct from the concentration-alert thresholds in Settings.
  ///
  /// In en, this message translates to:
  /// **'Drift thresholds'**
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
  /// **'Tune category and asset weights; the total must equal 100%.'**
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

  /// No description provided for @targetAllocationEditorCategoryTargets.
  ///
  /// In en, this message translates to:
  /// **'Category targets'**
  String get targetAllocationEditorCategoryTargets;

  /// No description provided for @targetAllocationEditorAddCategory.
  ///
  /// In en, this message translates to:
  /// **'Add asset class'**
  String get targetAllocationEditorAddCategory;

  /// No description provided for @targetAllocationEditorNoCategoriesAvailable.
  ///
  /// In en, this message translates to:
  /// **'All asset classes are added'**
  String get targetAllocationEditorNoCategoriesAvailable;

  /// No description provided for @targetAllocationEditorAssetTargets.
  ///
  /// In en, this message translates to:
  /// **'Asset targets'**
  String get targetAllocationEditorAssetTargets;

  /// No description provided for @targetAllocationEditorAddAssetTarget.
  ///
  /// In en, this message translates to:
  /// **'Add asset target'**
  String get targetAllocationEditorAddAssetTarget;

  /// No description provided for @targetAllocationEditorNoAssetTargets.
  ///
  /// In en, this message translates to:
  /// **'No single-asset targets yet.'**
  String get targetAllocationEditorNoAssetTargets;

  /// No description provided for @targetAllocationEditorNoAssetsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No available assets'**
  String get targetAllocationEditorNoAssetsAvailable;

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

  /// Header for the section that groups every investment-related preference (risk appetite, target allocation, alert thresholds).
  ///
  /// In en, this message translates to:
  /// **'Investment Preferences'**
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

  /// Label for the risk-appetite chip row in Settings — the single dial that drives the rebalance preset and AI tone.
  ///
  /// In en, this message translates to:
  /// **'Risk appetite'**
  String get settingsRiskAppetiteLabel;

  /// No description provided for @settingsRiskAppetiteConservative.
  ///
  /// In en, this message translates to:
  /// **'Conservative'**
  String get settingsRiskAppetiteConservative;

  /// No description provided for @settingsRiskAppetiteModerate.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get settingsRiskAppetiteModerate;

  /// No description provided for @settingsRiskAppetiteAggressive.
  ///
  /// In en, this message translates to:
  /// **'Aggressive'**
  String get settingsRiskAppetiteAggressive;

  /// No description provided for @settingsRiskAppetiteCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsRiskAppetiteCustom;

  /// Subtitle shown under the appetite chip row when the user is on the Custom track (they've hand-edited target weights).
  ///
  /// In en, this message translates to:
  /// **'Custom target weights'**
  String get settingsRiskAppetiteCustomBadge;

  /// Title for the confirmation dialog shown before applying a risk-appetite preset.
  ///
  /// In en, this message translates to:
  /// **'Apply risk posture?'**
  String get settingsRiskAppetiteConfirmTitle;

  /// Body for the confirmation dialog shown before applying a risk-appetite preset.
  ///
  /// In en, this message translates to:
  /// **'Switch to {appetite}? This also retunes target allocation and concentration alerts while they are on automatic presets.'**
  String settingsRiskAppetiteConfirmBody(String appetite);

  /// Confirm action for applying a risk-appetite preset.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get settingsRiskAppetiteConfirmAction;

  /// Inline link row in Settings — opens the per-category target weight editor.
  ///
  /// In en, this message translates to:
  /// **'Target allocation'**
  String get settingsTargetAllocationLabel;

  /// Subtitle for the target-allocation link row when the user is on a preset — e.g. "Balanced preset".
  ///
  /// In en, this message translates to:
  /// **'{preset} preset'**
  String settingsTargetAllocationSubtitlePreset(String preset);

  /// No description provided for @settingsTargetAllocationSubtitleCustom.
  ///
  /// In en, this message translates to:
  /// **'Hand-tuned weights'**
  String get settingsTargetAllocationSubtitleCustom;

  /// Inline link row in Settings — opens the advanced concentration-alert thresholds page.
  ///
  /// In en, this message translates to:
  /// **'Concentration alert thresholds'**
  String get settingsRiskThresholdsLabel;

  /// No description provided for @settingsRiskThresholdsSubtitleAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto-tuned by your risk appetite'**
  String get settingsRiskThresholdsSubtitleAuto;

  /// No description provided for @settingsRiskThresholdsSubtitleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom thresholds set'**
  String get settingsRiskThresholdsSubtitleCustom;

  /// No description provided for @settingsRiskThresholdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Concentration alert thresholds'**
  String get settingsRiskThresholdsTitle;

  /// No description provided for @settingsRiskThresholdsHint.
  ///
  /// In en, this message translates to:
  /// **'These thresholds decide when the Risk Alerts panel flags a position as concentrated. They\'re auto-tuned based on your risk appetite — tweak only if you want to override the defaults.'**
  String get settingsRiskThresholdsHint;

  /// Inline link row in Settings — opens the FIRE stress-test parameter editor.
  ///
  /// In en, this message translates to:
  /// **'FIRE stress-test parameters'**
  String get settingsStressTestLabel;

  /// No description provided for @settingsStressTestSubtitleAuto.
  ///
  /// In en, this message translates to:
  /// **'Using defaults'**
  String get settingsStressTestSubtitleAuto;

  /// No description provided for @settingsStressTestSubtitleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom assumptions set'**
  String get settingsStressTestSubtitleCustom;

  /// No description provided for @settingsStressTestTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE stress-test parameters'**
  String get settingsStressTestTitle;

  /// No description provided for @settingsStressTestHint.
  ///
  /// In en, this message translates to:
  /// **'Stress tests on the FIRE page run a few \"what if\" scenarios against your plan. These knobs decide how harsh each scenario assumes the world gets — only worth tweaking if you want a more conservative (higher) or relaxed (lower) test.'**
  String get settingsStressTestHint;

  /// No description provided for @settingsStressTestMarketDrawdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Market drawdown'**
  String get settingsStressTestMarketDrawdownLabel;

  /// No description provided for @settingsStressTestMarketDrawdownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bear-market drop applied to growth assets'**
  String get settingsStressTestMarketDrawdownSubtitle;

  /// No description provided for @settingsStressTestExpenseShockLabel.
  ///
  /// In en, this message translates to:
  /// **'Expense shock'**
  String get settingsStressTestExpenseShockLabel;

  /// No description provided for @settingsStressTestExpenseShockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sustained living-cost increase'**
  String get settingsStressTestExpenseShockSubtitle;

  /// No description provided for @settingsStressTestFxShockLabel.
  ///
  /// In en, this message translates to:
  /// **'FX shock'**
  String get settingsStressTestFxShockLabel;

  /// No description provided for @settingsStressTestFxShockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Currency swing magnitude'**
  String get settingsStressTestFxShockSubtitle;

  /// No description provided for @settingsStressTestLumpSumLabel.
  ///
  /// In en, this message translates to:
  /// **'One-off lump-sum outlay'**
  String get settingsStressTestLumpSumLabel;

  /// No description provided for @settingsStressTestLumpSumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Medical / family-support shock, in your base currency'**
  String get settingsStressTestLumpSumSubtitle;

  /// No description provided for @settingsStressTestLumpSumHint.
  ///
  /// In en, this message translates to:
  /// **'0 = test disabled'**
  String get settingsStressTestLumpSumHint;

  /// No description provided for @settingsStressTestResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsStressTestResetDefaults;

  /// Inline link row in Settings — opens the monthly-expense window / override editor that powers the FIRE projection.
  ///
  /// In en, this message translates to:
  /// **'Monthly expense model'**
  String get settingsMonthlyExpenseLabel;

  /// No description provided for @settingsMonthlyExpenseSubtitleAuto.
  ///
  /// In en, this message translates to:
  /// **'{months}-month rolling average'**
  String settingsMonthlyExpenseSubtitleAuto(int months);

  /// No description provided for @settingsMonthlyExpenseSubtitleOverride.
  ///
  /// In en, this message translates to:
  /// **'Manual override set'**
  String get settingsMonthlyExpenseSubtitleOverride;

  /// No description provided for @settingsMonthlyExpenseHint.
  ///
  /// In en, this message translates to:
  /// **'Your FIRE projection needs a monthly-expense figure. By default we average your past spending over a rolling window; flip on the manual override if you\'d rather hand-pick a number.'**
  String get settingsMonthlyExpenseHint;

  /// No description provided for @settingsMonthlyExpenseWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Rolling window'**
  String get settingsMonthlyExpenseWindowLabel;

  /// No description provided for @settingsMonthlyExpenseWindowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Months of history averaged into the auto-derived expense.'**
  String get settingsMonthlyExpenseWindowSubtitle;

  /// No description provided for @settingsMonthlyExpenseWindowValue.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, =1{1 month} other{{months} months}}'**
  String settingsMonthlyExpenseWindowValue(int months);

  /// No description provided for @settingsMonthlyExpenseOverrideLabel.
  ///
  /// In en, this message translates to:
  /// **'Manual override'**
  String get settingsMonthlyExpenseOverrideLabel;

  /// No description provided for @settingsMonthlyExpenseOverrideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bypass the auto-derivation. Leave blank to use the rolling average.'**
  String get settingsMonthlyExpenseOverrideSubtitle;

  /// No description provided for @settingsMonthlyExpenseOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for auto'**
  String get settingsMonthlyExpenseOverrideHint;

  /// No description provided for @settingsMonthlyExpenseResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsMonthlyExpenseResetDefaults;

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
  /// **'Trade date & time'**
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

  /// No description provided for @tradeEntryAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Trade details'**
  String get tradeEntryAdvancedTitle;

  /// No description provided for @tradeEntryAdvancedSummary.
  ///
  /// In en, this message translates to:
  /// **'Now · no fees or notes'**
  String get tradeEntryAdvancedSummary;

  /// No description provided for @tradeEntryAdvancedConfigured.
  ///
  /// In en, this message translates to:
  /// **'Custom date, costs or notes'**
  String get tradeEntryAdvancedConfigured;

  /// No description provided for @tradeEntryCashAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash account'**
  String get tradeEntryCashAccountLabel;

  /// Trade entry: brokerage or exchange account that owns the position
  ///
  /// In en, this message translates to:
  /// **'Holding account'**
  String get tradeEntryHoldingAccountLabel;

  /// Trade entry: collapsed settlement section title
  ///
  /// In en, this message translates to:
  /// **'Settlement'**
  String get tradeEntrySettlementTitle;

  /// No description provided for @tradeEntrySettlementBrokerCash.
  ///
  /// In en, this message translates to:
  /// **'{currency} cash in holding account'**
  String tradeEntrySettlementBrokerCash(String currency);

  /// No description provided for @tradeEntrySettlementExternal.
  ///
  /// In en, this message translates to:
  /// **'{account} · {currency}'**
  String tradeEntrySettlementExternal(String account, String currency);

  /// Trade entry: optional external bank or cash account used for settlement
  ///
  /// In en, this message translates to:
  /// **'External settlement account'**
  String get tradeEntrySettlementAccountLabel;

  /// Trade entry: explains the implicit brokerage-cash settlement option
  ///
  /// In en, this message translates to:
  /// **'Leave the account empty to settle against cash held inside the brokerage or exchange account.'**
  String get tradeEntrySettlementHelper;

  /// No description provided for @tradeEntryCrossCurrencyHint.
  ///
  /// In en, this message translates to:
  /// **'This instrument quotes in {assetCurrency}; price, costs, and cash will be recorded in {tradeCurrency}.'**
  String tradeEntryCrossCurrencyHint(
    String assetCurrency,
    String tradeCurrency,
  );

  /// No description provided for @tradeEntryCashAccountCurrencyChanged.
  ///
  /// In en, this message translates to:
  /// **'The previous cash account does not support this currency. Pick another cash account.'**
  String get tradeEntryCashAccountCurrencyChanged;

  /// No description provided for @tradeEntryBrokerAccountRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Brokerage account required'**
  String get tradeEntryBrokerAccountRequiredTitle;

  /// No description provided for @tradeEntryBrokerAccountRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a brokerage or crypto account before recording a securities trade.'**
  String get tradeEntryBrokerAccountRequiredMessage;

  /// No description provided for @tradeEntryCashAccountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a live cash account that matches the transaction currency.'**
  String get tradeEntryCashAccountInvalid;

  /// No description provided for @tradeEntryLotCurrencyMismatch.
  ///
  /// In en, this message translates to:
  /// **'The selected currency does not match this holding\'s lots. Change the visible Currency field. If the holding contains lots in multiple currencies, repair or split the holding first.'**
  String get tradeEntryLotCurrencyMismatch;

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

  /// No description provided for @tradeTypeAdjustShort.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get tradeTypeAdjustShort;

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

  /// No description provided for @expenseFormAccountMissingNotice.
  ///
  /// In en, this message translates to:
  /// **'The previous payment account is unavailable. Pick an account to continue.'**
  String get expenseFormAccountMissingNotice;

  /// No description provided for @expenseFormCurrencyConflictNotice.
  ///
  /// In en, this message translates to:
  /// **'This expense is recorded in {expenseCurrency}, but the account now uses {accountCurrency}. Choose the intended currency before saving.'**
  String expenseFormCurrencyConflictNotice(
    String accountCurrency,
    String expenseCurrency,
  );

  /// No description provided for @expenseFormAccountsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load accounts: {error}'**
  String expenseFormAccountsLoadError(String error);

  /// No description provided for @expenseFormDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get expenseFormDateLabel;

  /// Expense form: disclosure for optional date and note fields
  ///
  /// In en, this message translates to:
  /// **'Date & note'**
  String get expenseFormAdvancedTitle;

  /// No description provided for @expenseFormDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense'**
  String get expenseFormDeleteDialogTitle;

  /// No description provided for @expenseFormDeleteDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this expense? You can undo it from the confirmation message, and the change syncs to your other devices.'**
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

  /// No description provided for @incomeFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Record income'**
  String get incomeFormCreateTitle;

  /// No description provided for @incomeFormAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get incomeFormAmountLabel;

  /// No description provided for @incomeFormAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than 0'**
  String get incomeFormAmountInvalid;

  /// No description provided for @incomeFormKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Income type'**
  String get incomeFormKindLabel;

  /// No description provided for @incomeFormAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Deposit account'**
  String get incomeFormAccountLabel;

  /// No description provided for @incomeFormAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a deposit account and currency'**
  String get incomeFormAccountRequired;

  /// No description provided for @incomeFormAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Date & note'**
  String get incomeFormAdvancedTitle;

  /// No description provided for @incomeFormDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get incomeFormDateLabel;

  /// No description provided for @incomeFormDefaultNarration.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeFormDefaultNarration;

  /// No description provided for @incomeFormNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account first'**
  String get incomeFormNoAccountsTitle;

  /// No description provided for @incomeFormNoAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Income needs a deposit account. Create one under Accounts, then come back here.'**
  String get incomeFormNoAccountsBody;

  /// No description provided for @incomeFormNoAccountsCta.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get incomeFormNoAccountsCta;

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

  /// No description provided for @aiToolHoldingsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No holdings data yet'**
  String get aiToolHoldingsEmpty;

  /// No description provided for @aiToolAssetColumn.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get aiToolAssetColumn;

  /// No description provided for @aiToolQuantityColumn.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get aiToolQuantityColumn;

  /// No description provided for @aiToolCostColumn.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get aiToolCostColumn;

  /// No description provided for @aiToolHiddenItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more item hidden} other{{count} more items hidden}}'**
  String aiToolHiddenItems(int count);

  /// No description provided for @aiToolPaymentAccountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payment accounts available'**
  String get aiToolPaymentAccountsEmpty;

  /// No description provided for @aiToolPaymentAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Available payment accounts'**
  String get aiToolPaymentAccountsTitle;

  /// No description provided for @aiToolHiddenAccounts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more account hidden} other{{count} more accounts hidden}}'**
  String aiToolHiddenAccounts(int count);

  /// No description provided for @aiToolXirrAssetScope.
  ///
  /// In en, this message translates to:
  /// **'Asset {assetId}'**
  String aiToolXirrAssetScope(String assetId);

  /// No description provided for @aiToolXirrPortfolioScope.
  ///
  /// In en, this message translates to:
  /// **'Portfolio'**
  String get aiToolXirrPortfolioScope;

  /// No description provided for @aiToolAllHistory.
  ///
  /// In en, this message translates to:
  /// **'All history'**
  String get aiToolAllHistory;

  /// No description provided for @aiToolXirrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot calculate: cash flows are one-sided or insufficient'**
  String get aiToolXirrUnavailable;

  /// No description provided for @aiToolCashFlowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cash flow} other{{count} cash flows}}'**
  String aiToolCashFlowCount(int count);

  /// No description provided for @aiToolNetWorthEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cumulative net cash-flow data in this range'**
  String get aiToolNetWorthEmpty;

  /// No description provided for @aiToolCurrentNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Cumulative net cash flow'**
  String get aiToolCurrentNetWorth;

  /// No description provided for @aiToolNetWorthSeriesName.
  ///
  /// In en, this message translates to:
  /// **'Cumulative net cash flow'**
  String get aiToolNetWorthSeriesName;

  /// Caption under the AI net-cash-flow card clarifying methodology vs true net worth.
  ///
  /// In en, this message translates to:
  /// **'Monthly cumulative net cash flow · not mark-to-market net worth'**
  String get aiToolNetWorthMethodNote;

  /// Delta chip context for net cash-flow change over the series window.
  ///
  /// In en, this message translates to:
  /// **'vs range start'**
  String get aiToolNetWorthVsStart;

  /// No description provided for @aiToolSamplePointCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sample point} other{{count} sample points}}'**
  String aiToolSamplePointCount(int count);

  /// No description provided for @aiToolBreakdownCostEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cost basis to break down'**
  String get aiToolBreakdownCostEmpty;

  /// No description provided for @aiToolOtherCategoriesSummary.
  ///
  /// In en, this message translates to:
  /// **'Other {count} categories total {share}'**
  String aiToolOtherCategoriesSummary(int count, String share);

  /// No description provided for @aiToolRiskAlertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No risk alerts triggered'**
  String get aiToolRiskAlertsEmpty;

  /// No description provided for @aiToolRiskAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Risk alert'**
  String get aiToolRiskAlertTitle;

  /// No description provided for @aiToolHoldingsDataMalformed.
  ///
  /// In en, this message translates to:
  /// **'Holdings data format is invalid'**
  String get aiToolHoldingsDataMalformed;

  /// No description provided for @aiToolTotalCostSummary.
  ///
  /// In en, this message translates to:
  /// **'Total cost {cost} · {count, plural, =1{1 holding class} other{{count} holding classes}}'**
  String aiToolTotalCostSummary(String cost, int count);

  /// No description provided for @aiToolRecurringPatternsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stable recurring spending detected yet'**
  String get aiToolRecurringPatternsEmpty;

  /// No description provided for @aiToolMoreItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+ 1 more item} other{+ {count} more items}}'**
  String aiToolMoreItems(int count);

  /// No description provided for @aiToolCadenceMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get aiToolCadenceMonthly;

  /// No description provided for @aiToolCadenceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get aiToolCadenceWeekly;

  /// No description provided for @aiToolOccurrences.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time} other{{count} times}}'**
  String aiToolOccurrences(int count);

  /// No description provided for @aiToolOccurrencesRecent.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time} other{{count} times}} · last {date}'**
  String aiToolOccurrencesRecent(int count, String date);

  /// No description provided for @aiToolSubscriptionChangesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No subscription price changes detected this period'**
  String get aiToolSubscriptionChangesEmpty;

  /// No description provided for @aiToolSinceDate.
  ///
  /// In en, this message translates to:
  /// **' · since {date}'**
  String aiToolSinceDate(String date);

  /// No description provided for @aiToolRefundLinksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No refund matches detected yet'**
  String get aiToolRefundLinksEmpty;

  /// No description provided for @aiChatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your LifeOS assistant'**
  String get aiChatEmptyTitle;

  /// No description provided for @aiChatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Ask about finance, knowledge, health, and plans together. Answers prioritize on-device data and enabled features; when information is missing, the assistant asks before assuming.'**
  String get aiChatEmptyBody;

  /// No description provided for @aiChatEmptySuggestion1.
  ///
  /// In en, this message translates to:
  /// **'What needs my attention right now?'**
  String get aiChatEmptySuggestion1;

  /// No description provided for @aiChatEmptySuggestion2.
  ///
  /// In en, this message translates to:
  /// **'Summarize recent finance, knowledge, and health signals.'**
  String get aiChatEmptySuggestion2;

  /// No description provided for @aiChatEmptySuggestion3.
  ///
  /// In en, this message translates to:
  /// **'What risks show up in my plans and reviews?'**
  String get aiChatEmptySuggestion3;

  /// No description provided for @aiChatEmptySuggestion4.
  ///
  /// In en, this message translates to:
  /// **'What is the highest-value next step right now?'**
  String get aiChatEmptySuggestion4;

  /// No description provided for @aiChatEmptySuggestionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Try these'**
  String get aiChatEmptySuggestionsHeader;

  /// Empty-state suggestion shown when AiContextSummary has a monthlyChangePct signal.
  ///
  /// In en, this message translates to:
  /// **'Explain this month\'s net worth change'**
  String get aiChatEmptyDynamicNetWorth;

  /// Empty-state suggestion shown when AiContextSummary has flagged expense anomalies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Look at the flagged expense} other{Look at the {count} flagged expenses}}'**
  String aiChatEmptyDynamicAnomaly(int count);

  /// Empty-state suggestion shown when AiContextSummary has upcoming deposit maturities.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 deposit matures in {days}d — what should I do?} other{{count} deposits mature in {days}d — what should I do?}}'**
  String aiChatEmptyDynamicMaturity(int count, int days);

  /// No description provided for @aiChatBootstrappingLabel.
  ///
  /// In en, this message translates to:
  /// **'Preparing conversation…'**
  String get aiChatBootstrappingLabel;

  /// No description provided for @aiIntentDefaultTimeframe.
  ///
  /// In en, this message translates to:
  /// **'the last 30 days'**
  String get aiIntentDefaultTimeframe;

  /// No description provided for @aiIntentCurrentObject.
  ///
  /// In en, this message translates to:
  /// **'the current object'**
  String get aiIntentCurrentObject;

  /// No description provided for @aiIntentFallbackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please analyze {objectLabel}.'**
  String aiIntentFallbackPrompt(Object objectLabel);

  /// No description provided for @aiIntentExplainChangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Why it changed'**
  String get aiIntentExplainChangeLabel;

  /// No description provided for @aiIntentExplainChangePrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain why {objectLabel} changed during {timeframe}, and call out the relevant trends.'**
  String aiIntentExplainChangePrompt(Object objectLabel, Object timeframe);

  /// No description provided for @aiIntentSummarizeAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account overview'**
  String get aiIntentSummarizeAccountLabel;

  /// No description provided for @aiIntentSummarizeAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Summarize account {objectLabel} during {timeframe} in concise bullets.'**
  String aiIntentSummarizeAccountPrompt(Object objectLabel, Object timeframe);

  /// No description provided for @aiIntentStressTestPlanLabel.
  ///
  /// In en, this message translates to:
  /// **'Improve resilience'**
  String get aiIntentStressTestPlanLabel;

  /// No description provided for @aiIntentStressTestPlanPrompt.
  ///
  /// In en, this message translates to:
  /// **'Evaluate how resilient {objectLabel} is under adverse conditions, then give 2–3 concrete improvements.'**
  String aiIntentStressTestPlanPrompt(Object objectLabel);

  /// No description provided for @aiIntentComparePeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get aiIntentComparePeriodLabel;

  /// No description provided for @aiIntentComparePeriodPrompt.
  ///
  /// In en, this message translates to:
  /// **'Compare {objectLabel} across two periods and explain the drivers.'**
  String aiIntentComparePeriodPrompt(Object objectLabel);

  /// No description provided for @aiIntentExplainInsightLabel.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get aiIntentExplainInsightLabel;

  /// No description provided for @aiIntentExplainInsightPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain this insight ({objectLabel}) in detail, including trigger, severity, and possible actions.'**
  String aiIntentExplainInsightPrompt(Object objectLabel);

  /// No description provided for @aiIntentExplainChartLabel.
  ///
  /// In en, this message translates to:
  /// **'Ask about chart'**
  String get aiIntentExplainChartLabel;

  /// No description provided for @aiIntentExplainChartPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain the key changes in this chart ({objectLabel}) during {timeframe}, including likely drivers.'**
  String aiIntentExplainChartPrompt(Object objectLabel, Object timeframe);

  /// No description provided for @aiIntentTransactionsExplainSelectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Interpret'**
  String get aiIntentTransactionsExplainSelectionLabel;

  /// No description provided for @aiIntentTransactionsExplainSelectionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Interpret these selected transactions ({objectLabel}); identify common patterns, anomalies, and possible categorization.'**
  String aiIntentTransactionsExplainSelectionPrompt(Object objectLabel);

  /// No description provided for @aiIntentExplainFireStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Explain FIRE state'**
  String get aiIntentExplainFireStateLabel;

  /// No description provided for @aiIntentExplainFireStatePrompt.
  ///
  /// In en, this message translates to:
  /// **'Use get_fire_state to explain the current safety level, withdrawal rate, cash-bucket coverage, and FIRE ETA for {objectLabel}; call out the one or two suggested_actions that matter most.'**
  String aiIntentExplainFireStatePrompt(Object objectLabel);

  /// No description provided for @aiIntentReviewCashBucketLabel.
  ///
  /// In en, this message translates to:
  /// **'Check cash runway'**
  String get aiIntentReviewCashBucketLabel;

  /// No description provided for @aiIntentReviewCashBucketPrompt.
  ///
  /// In en, this message translates to:
  /// **'Use get_fire_state to check cash-runway months vs target for {objectLabel}. If short, give the refill amount and prepare a propose_fire_plan_update suggestion.'**
  String aiIntentReviewCashBucketPrompt(Object objectLabel);

  /// No description provided for @aiIntentSimulateFireChangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Simulate'**
  String get aiIntentSimulateFireChangeLabel;

  /// No description provided for @aiIntentSimulateFireChangePrompt.
  ///
  /// In en, this message translates to:
  /// **'Use simulate_fire_plan to model how changes to {objectLabel} affect FIRE status, including expenses, balance, SWR, and cash-bucket months. Make clear this is a simulation and does not write to the plan.'**
  String aiIntentSimulateFireChangePrompt(Object objectLabel);

  /// No description provided for @aiIntentExplainStressTestLabel.
  ///
  /// In en, this message translates to:
  /// **'Explain stress test'**
  String get aiIntentExplainStressTestLabel;

  /// No description provided for @aiIntentExplainStressTestPrompt.
  ///
  /// In en, this message translates to:
  /// **'Use get_fire_stress_tests to explain how market drawdown, higher expenses, one-off shocks, FX shocks, and cash-bucket depletion affect {objectLabel}. Emphasize that this is a resilience check, not a forecast.'**
  String aiIntentExplainStressTestPrompt(Object objectLabel);

  /// No description provided for @aiIntentSuggestFireActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Next steps'**
  String get aiIntentSuggestFireActionsLabel;

  /// No description provided for @aiIntentSuggestFireActionsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Use get_fire_state suggested_actions to give the three highest-value next steps. If a plan change is involved, use propose_fire_plan_update so I can confirm.'**
  String get aiIntentSuggestFireActionsPrompt;

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
  /// **'Ask NaviWealth about finance, knowledge, health, or plans'**
  String get aiChatComposerHintIdle;

  /// No description provided for @aiChatComposerHintStreaming.
  ///
  /// In en, this message translates to:
  /// **'Generating answer…'**
  String get aiChatComposerHintStreaming;

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

  /// No description provided for @speechInputStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start voice input'**
  String get speechInputStartTooltip;

  /// No description provided for @speechInputStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop and keep transcript'**
  String get speechInputStopTooltip;

  /// No description provided for @speechInputContinuousStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start continuous conversation'**
  String get speechInputContinuousStartTooltip;

  /// No description provided for @speechInputContinuousStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop continuous conversation'**
  String get speechInputContinuousStopTooltip;

  /// No description provided for @speechInputStartingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Preparing on-device speech recognition…'**
  String get speechInputStartingTooltip;

  /// No description provided for @speechInputPreparingStatus.
  ///
  /// In en, this message translates to:
  /// **'Preparing microphone…'**
  String get speechInputPreparingStatus;

  /// No description provided for @speechInputPermissionStatus.
  ///
  /// In en, this message translates to:
  /// **'Waiting for microphone permission…'**
  String get speechInputPermissionStatus;

  /// No description provided for @speechInputReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'Recognition is ready; starting microphone…'**
  String get speechInputReadyStatus;

  /// No description provided for @speechInputListeningStatus.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get speechInputListeningStatus;

  /// No description provided for @speechInputContinuousStatus.
  ///
  /// In en, this message translates to:
  /// **'Listening continuously…'**
  String get speechInputContinuousStatus;

  /// No description provided for @speechInputEndpointingStatus.
  ///
  /// In en, this message translates to:
  /// **'Finishing recognition…'**
  String get speechInputEndpointingStatus;

  /// No description provided for @speechInputThinkingStatus.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get speechInputThinkingStatus;

  /// No description provided for @speechInputSpeakingStatus.
  ///
  /// In en, this message translates to:
  /// **'Speaking · Tap the mic to interrupt'**
  String get speechInputSpeakingStatus;

  /// No description provided for @speechInputDuplexSpeakingStatus.
  ///
  /// In en, this message translates to:
  /// **'Speaking · You can interrupt by talking'**
  String get speechInputDuplexSpeakingStatus;

  /// No description provided for @speechInputDuplexPausedStatus.
  ///
  /// In en, this message translates to:
  /// **'Speaking paused · Keep talking to interrupt'**
  String get speechInputDuplexPausedStatus;

  /// No description provided for @speechInputSwitchToTextTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch to text input'**
  String get speechInputSwitchToTextTooltip;

  /// No description provided for @speechInputCancelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel voice input'**
  String get speechInputCancelTooltip;

  /// No description provided for @speechOutputStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop speaking'**
  String get speechOutputStopTooltip;

  /// No description provided for @speechInputModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Download the real-time Chinese speech model first'**
  String get speechInputModelMissing;

  /// No description provided for @speechInputUnsupported.
  ///
  /// In en, this message translates to:
  /// **'On-device voice input is unavailable on this platform'**
  String get speechInputUnsupported;

  /// No description provided for @speechInputPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for voice input'**
  String get speechInputPermissionDenied;

  /// No description provided for @speechInputRecorderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The microphone or recording device is unavailable'**
  String get speechInputRecorderUnavailable;

  /// No description provided for @speechInputRuntimeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The on-device speech recognition service is unavailable'**
  String get speechInputRuntimeUnavailable;

  /// No description provided for @speechInputSessionBusy.
  ///
  /// In en, this message translates to:
  /// **'The previous voice session is still closing'**
  String get speechInputSessionBusy;

  /// No description provided for @speechInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition could not start. Try again later'**
  String get speechInputFailed;

  /// No description provided for @speechInputRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get speechInputRetry;

  /// No description provided for @speechOutputEngineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech is unavailable on this device'**
  String get speechOutputEngineUnavailable;

  /// No description provided for @speechOutputSynthesisFailed.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech could not play this answer'**
  String get speechOutputSynthesisFailed;

  /// No description provided for @speechOutputSessionBusy.
  ///
  /// In en, this message translates to:
  /// **'Another answer is already being spoken'**
  String get speechOutputSessionBusy;

  /// No description provided for @aiChatThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get aiChatThinking;

  /// Collapsed summary under an assistant turn that called read tools.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tool used} other{{count} tools used}}'**
  String aiChatToolsUsed(int count);

  /// Affordance to expand the collapsed tool-steps group.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get aiChatToolsExpand;

  /// Affordance to collapse expanded tool-steps.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get aiChatToolsCollapse;

  /// Streaming indicator while the assistant is waiting for a tool call. {tool} is already a localized friendly name from friendlyToolName().
  ///
  /// In en, this message translates to:
  /// **'Running {tool}'**
  String aiChatRunningTool(String tool);

  /// Short label on the floating jump-to-latest control in the chat timeline.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get aiChatJumpToLatest;

  /// Jump-to-latest chip when messages arrived while the user was scrolled up.
  ///
  /// In en, this message translates to:
  /// **'Latest · {count}'**
  String aiChatJumpToLatestWithCount(int count);

  /// Date separator label for messages sent today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get aiChatDateToday;

  /// Date separator label for messages sent yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get aiChatDateYesterday;

  /// Title of the long-press action sheet for a chat message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get aiChatMessageActionsTitle;

  /// Collapsed summary of an answered ask_user decision.
  ///
  /// In en, this message translates to:
  /// **'Selected: {label}'**
  String aiChatDecisionSelected(String label);

  /// Placeholder for free-form ask_user custom option input.
  ///
  /// In en, this message translates to:
  /// **'Type your own option…'**
  String get aiChatDecisionCustomHint;

  /// Jump link from the AI net cash-flow card to the wealth hub.
  ///
  /// In en, this message translates to:
  /// **'Open wealth'**
  String get aiToolOpenWealth;

  /// Tooltip on the floating button that re-anchors the conversation to the most recent message after the user has scrolled up.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get aiChatJumpToLatestTooltip;

  /// Inline action under a completed assistant message — copies its text to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get aiChatMessageCopy;

  /// Confirmation snackbar shown after the user copies an assistant reply.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get aiChatMessageCopied;

  /// Title of the confirmation dialog shown before opening a link rendered from AI markdown output.
  ///
  /// In en, this message translates to:
  /// **'Open link?'**
  String get aiChatLinkConfirmTitle;

  /// Body text of the confirmation dialog shown before opening a link from AI output.
  ///
  /// In en, this message translates to:
  /// **'Confirm the destination — AI replies are untrusted and may contain unexpected URLs.'**
  String get aiChatLinkConfirmBody;

  /// Confirm button on the AI-link open dialog.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get aiChatLinkOpen;

  /// Snackbar shown if launchUrl returns false (no installed handler / blocked by OS).
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get aiChatLinkOpenFailed;

  /// Inline action under the last assistant message — discards the turn and re-runs the prompt.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get aiChatMessageRegenerate;

  /// Screen-reader prefix announcing a user chat bubble. Followed by the message content.
  ///
  /// In en, this message translates to:
  /// **'You said:'**
  String get aiChatSemanticsUserMessage;

  /// Screen-reader announcement for an assistant chat bubble. The bubble contents (text + tool calls) follow.
  ///
  /// In en, this message translates to:
  /// **'Assistant reply'**
  String get aiChatSemanticsAssistantMessage;

  /// Screen-reader announcement when the assistant bubble is in an errored state.
  ///
  /// In en, this message translates to:
  /// **'Assistant reply failed'**
  String get aiChatSemanticsAssistantError;

  /// Screen-reader prefix announcing an inline system message (truncation notice, stale-sync warning).
  ///
  /// In en, this message translates to:
  /// **'System notice:'**
  String get aiChatSemanticsSystemNotice;

  /// Tooltip on the small info icon at the end of an inline tool attribution row, opening the debug sheet with raw JSON.
  ///
  /// In en, this message translates to:
  /// **'View raw tool input/output'**
  String get aiChatToolDebugTooltip;

  /// Tooltip / a11y hint on the transparency badge — taps navigate to the per-trace detail page.
  ///
  /// In en, this message translates to:
  /// **'View full transparency trace'**
  String get aiChatTransparencyOpenDetail;

  /// Tooltip on the active LlmProfile chip above the composer. Taps open the AI LLM credentials settings page so the user can swap profiles.
  ///
  /// In en, this message translates to:
  /// **'Switch model profile'**
  String get aiChatProfileChipTooltip;

  /// Inline action under the trailing user message — opens a sheet to edit and re-send the prompt.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get aiChatEditUserMessage;

  /// Title of the edit-and-resend sheet for user messages.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get aiChatEditUserMessageTitle;

  /// Warning shown in the edit sheet about branch-replace semantics.
  ///
  /// In en, this message translates to:
  /// **'Saving discards the existing reply and any later turns, then re-runs your edited prompt.'**
  String get aiChatEditUserMessageWarning;

  /// Submit button label in the edit-and-resend sheet.
  ///
  /// In en, this message translates to:
  /// **'Save and resend'**
  String get aiChatEditUserMessageSubmit;

  /// Toast/hint after tapping edit on a user message — content is loaded into the composer.
  ///
  /// In en, this message translates to:
  /// **'Edit in composer, then send to replace this turn'**
  String get aiChatEditUserMessageHint;

  /// Banner above the composer while an edit-and-resend draft is active.
  ///
  /// In en, this message translates to:
  /// **'Editing message — send to replace this turn'**
  String get aiChatEditBannerTitle;

  /// Cancel button on the edit-and-resend composer banner.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get aiChatEditCancel;

  /// Message count meta under a session list row.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}}'**
  String aiChatSessionMessageCount(int count);

  /// Hint under an ask_user decision card when free-form replies are allowed.
  ///
  /// In en, this message translates to:
  /// **'Or type your own option below.'**
  String get aiChatDecisionAllowCustom;

  /// Natural-language reply written back when the user picks a decision option.
  ///
  /// In en, this message translates to:
  /// **'I choose \"{label}\". Continue under this option.'**
  String aiChatDecisionReply(String label);

  /// Footer toggle in the proposal edit sheet that expands the curated fields list to every payload key.
  ///
  /// In en, this message translates to:
  /// **'More fields'**
  String get aiChatProposalEditMoreFields;

  /// Footer toggle that collapses the proposal edit sheet back to the curated high-frequency fields.
  ///
  /// In en, this message translates to:
  /// **'Standard fields'**
  String get aiChatProposalEditStandardFields;

  /// Placeholder text in the search box at the top of the sessions panel.
  ///
  /// In en, this message translates to:
  /// **'Search conversations…'**
  String get aiChatSessionsSearchHint;

  /// Empty state shown in the sessions panel when no session titles match the current search query.
  ///
  /// In en, this message translates to:
  /// **'No conversations match \"{query}\"'**
  String aiChatSessionsSearchEmpty(String query);

  /// Clears the sessions panel search query when no results match.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get aiChatSessionsSearchClear;

  /// Section header for user-pinned chat sessions.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get aiChatSessionsGroupPinned;

  /// Section header for archived chat sessions.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get aiChatSessionsGroupArchived;

  /// Toggle to reveal archived sessions in the history panel.
  ///
  /// In en, this message translates to:
  /// **'Show archive ({count})'**
  String aiChatSessionsShowArchived(int count);

  /// Toggle to hide archived sessions again.
  ///
  /// In en, this message translates to:
  /// **'Hide archive'**
  String get aiChatSessionsHideArchived;

  /// Permanently delete all archived sessions.
  ///
  /// In en, this message translates to:
  /// **'Clear archive'**
  String get aiChatSessionsClearArchive;

  /// Confirm sheet title for deleting all archived sessions.
  ///
  /// In en, this message translates to:
  /// **'Clear archive?'**
  String get aiChatSessionsClearArchiveTitle;

  /// Confirm sheet body for clearing the archive.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes every archived conversation. This cannot be undone.'**
  String get aiChatSessionsClearArchiveBody;

  /// Toast after clearing the archive.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count, plural, =1{1 archived conversation} other{{count} archived conversations}}'**
  String aiChatSessionsClearArchiveDone(int count);

  /// Empty state when all sessions are archived.
  ///
  /// In en, this message translates to:
  /// **'No active conversations'**
  String get aiChatSessionsEmptyActive;

  /// Pin a chat session to the top of the history list.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get aiChatSessionPinAction;

  /// Remove the pin from a chat session.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get aiChatSessionUnpinAction;

  /// Archive a chat session.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get aiChatSessionArchiveAction;

  /// Restore an archived chat session.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get aiChatSessionUnarchiveAction;

  /// Section header in the sessions panel for conversations with their last message today (local time).
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get aiChatSessionsGroupToday;

  /// Section header — conversations whose last message landed yesterday (local time).
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get aiChatSessionsGroupYesterday;

  /// Section header — conversations within the past 7 days but not today/yesterday.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get aiChatSessionsGroupThisWeek;

  /// Section header — conversations within the past 30 days but not in the more recent buckets.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get aiChatSessionsGroupThisMonth;

  /// Section header — conversations older than 30 days.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get aiChatSessionsGroupOlder;

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

  /// No description provided for @aiChatProposalKindIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get aiChatProposalKindIncome;

  /// No description provided for @aiChatProposalKindTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get aiChatProposalKindTransfer;

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

  /// No description provided for @aiChatProposalKindOptionsProfileUpdate.
  ///
  /// In en, this message translates to:
  /// **'Income Planner preferences'**
  String get aiChatProposalKindOptionsProfileUpdate;

  /// No description provided for @aiChatProposalKindOptionsJournalEntry.
  ///
  /// In en, this message translates to:
  /// **'Options journal entry'**
  String get aiChatProposalKindOptionsJournalEntry;

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

  /// No description provided for @aiChatProposalBatchProgress.
  ///
  /// In en, this message translates to:
  /// **'Applying {completed} of {total}'**
  String aiChatProposalBatchProgress(int completed, int total);

  /// No description provided for @aiChatProposalBatchRecover.
  ///
  /// In en, this message translates to:
  /// **'Undo applied items'**
  String get aiChatProposalBatchRecover;

  /// No description provided for @aiChatProposalBatchRecoveryNeeded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 applied item still needs to be undone before retrying} other{{count} applied items still need to be undone before retrying}}'**
  String aiChatProposalBatchRecoveryNeeded(int count);

  /// No description provided for @aiChatProposalBatchRolledBack.
  ///
  /// In en, this message translates to:
  /// **'Applied items were undone. The batch is safe to retry.'**
  String get aiChatProposalBatchRolledBack;

  /// Snackbar shown after the user taps 'Confirm all' and every item applied cleanly.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Applied 1 item} other{Applied {count} items}}'**
  String aiChatProposalBatchResultAllOk(int count);

  /// Snackbar shown after batch confirm when some items applied and some errored. Both counts are positive.
  ///
  /// In en, this message translates to:
  /// **'Applied {applied} · {failed} failed'**
  String aiChatProposalBatchResultMixed(int applied, int failed);

  /// Snackbar shown after batch confirm when every eligible item errored.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Failed to apply} other{All {count} items failed}}'**
  String aiChatProposalBatchResultAllFailed(int count);

  /// Warning above the typed-confirm field for high-risk proposals (broker_order, bulk_delete). {token} is the literal string the user must type.
  ///
  /// In en, this message translates to:
  /// **'High-risk action. Type \"{token}\" to enable Confirm.'**
  String aiChatProposalConfirmTokenWarning(String token);

  /// Helper text shown below the typed-confirm field while the user's input does not yet match the token.
  ///
  /// In en, this message translates to:
  /// **'Confirm is disabled until you type \"{token}\".'**
  String aiChatProposalConfirmTokenPending(String token);

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

  /// No description provided for @aiChatFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get aiChatFieldNotes;

  /// No description provided for @aiChatFieldOptionPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get aiChatFieldOptionPremium;

  /// No description provided for @aiChatRecommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get aiChatRecommendedBadge;

  /// No description provided for @aiChatFieldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get aiChatFieldAmount;

  /// No description provided for @aiChatFieldDestinationAmount.
  ///
  /// In en, this message translates to:
  /// **'Destination amount'**
  String get aiChatFieldDestinationAmount;

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

  /// No description provided for @aiChatRowFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From account'**
  String get aiChatRowFromAccount;

  /// No description provided for @aiChatRowToAccount.
  ///
  /// In en, this message translates to:
  /// **'To account'**
  String get aiChatRowToAccount;

  /// No description provided for @aiChatRowDestinationAmount.
  ///
  /// In en, this message translates to:
  /// **'Destination amount'**
  String get aiChatRowDestinationAmount;

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

  /// No description provided for @aiChatRowUnderlying.
  ///
  /// In en, this message translates to:
  /// **'Underlying'**
  String get aiChatRowUnderlying;

  /// No description provided for @aiChatRowOptionContract.
  ///
  /// In en, this message translates to:
  /// **'Option contract'**
  String get aiChatRowOptionContract;

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

  /// Evidence chip label deep-linking to a ledger journal entry
  ///
  /// In en, this message translates to:
  /// **'Entry {id}'**
  String aiChatToolJumpJournalEntry(String id);

  /// Evidence chip label deep-linking to an options trade journal entry
  ///
  /// In en, this message translates to:
  /// **'Trade {id}'**
  String aiChatToolJumpTradeJournal(String id);

  /// Section header above the evidence chip strip in a tool invocation card
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get aiChatToolEvidenceLabel;

  /// No description provided for @aiChatToolShowRawJson.
  ///
  /// In en, this message translates to:
  /// **'View raw data'**
  String get aiChatToolShowRawJson;

  /// No description provided for @aiChatToolShowCompactView.
  ///
  /// In en, this message translates to:
  /// **'Back to compact view'**
  String get aiChatToolShowCompactView;

  /// No description provided for @aiFloatingPillLabel.
  ///
  /// In en, this message translates to:
  /// **'Open assistant'**
  String get aiFloatingPillLabel;

  /// No description provided for @aiChatSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get aiChatSheetTitle;

  /// No description provided for @aiChatSheetEmpty.
  ///
  /// In en, this message translates to:
  /// **'Ask anything about your Life OS.'**
  String get aiChatSheetEmpty;

  /// No description provided for @aiChatSheetExpandTooltip.
  ///
  /// In en, this message translates to:
  /// **'Expand to full screen'**
  String get aiChatSheetExpandTooltip;

  /// No description provided for @aiChatSheetNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get aiChatSheetNewTooltip;

  /// No description provided for @chartEmptyDefault.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get chartEmptyDefault;

  /// No description provided for @chartTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get chartTotalLabel;

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

  /// AmountField validator: zero where the caller requires a positive value.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero'**
  String get formAmountFieldZeroNotAllowed;

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

  /// Generic time field label used next to DateField when editing date-time values.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get formDateFieldTimeLabel;

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

  /// Default label for the expense-form category picker.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseCategoryPickerLabelDefault;

  /// Validator message when no expense category is selected.
  ///
  /// In en, this message translates to:
  /// **'Pick a category'**
  String get expenseCategoryPickerRequired;

  /// No description provided for @systemAccountIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get systemAccountIncome;

  /// No description provided for @systemAccountIncomeSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get systemAccountIncomeSalary;

  /// No description provided for @systemAccountIncomeDividend.
  ///
  /// In en, this message translates to:
  /// **'Dividend'**
  String get systemAccountIncomeDividend;

  /// No description provided for @systemAccountIncomeInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get systemAccountIncomeInterest;

  /// No description provided for @systemAccountIncomeCapitalGains.
  ///
  /// In en, this message translates to:
  /// **'Capital Gains'**
  String get systemAccountIncomeCapitalGains;

  /// No description provided for @systemAccountIncomeOther.
  ///
  /// In en, this message translates to:
  /// **'Other Income'**
  String get systemAccountIncomeOther;

  /// No description provided for @systemAccountExpense.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get systemAccountExpense;

  /// No description provided for @systemAccountExpenseDining.
  ///
  /// In en, this message translates to:
  /// **'Dining'**
  String get systemAccountExpenseDining;

  /// No description provided for @systemAccountExpenseGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get systemAccountExpenseGroceries;

  /// No description provided for @systemAccountExpenseCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get systemAccountExpenseCoffee;

  /// No description provided for @systemAccountExpenseTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get systemAccountExpenseTransport;

  /// No description provided for @systemAccountExpenseRideHailing.
  ///
  /// In en, this message translates to:
  /// **'Ride Hailing'**
  String get systemAccountExpenseRideHailing;

  /// No description provided for @systemAccountExpenseHousing.
  ///
  /// In en, this message translates to:
  /// **'Housing'**
  String get systemAccountExpenseHousing;

  /// No description provided for @systemAccountExpenseUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get systemAccountExpenseUtilities;

  /// No description provided for @systemAccountExpenseHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get systemAccountExpenseHousehold;

  /// No description provided for @systemAccountExpenseShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get systemAccountExpenseShopping;

  /// No description provided for @systemAccountExpenseSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get systemAccountExpenseSubscriptions;

  /// No description provided for @systemAccountExpenseEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get systemAccountExpenseEntertainment;

  /// No description provided for @systemAccountExpenseMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get systemAccountExpenseMedical;

  /// No description provided for @systemAccountExpenseFitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get systemAccountExpenseFitness;

  /// No description provided for @systemAccountExpenseEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get systemAccountExpenseEducation;

  /// No description provided for @systemAccountExpenseTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get systemAccountExpenseTravel;

  /// No description provided for @systemAccountExpenseCommunication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get systemAccountExpenseCommunication;

  /// No description provided for @systemAccountExpenseGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get systemAccountExpenseGift;

  /// No description provided for @systemAccountExpenseFamilySupport.
  ///
  /// In en, this message translates to:
  /// **'Family Support'**
  String get systemAccountExpenseFamilySupport;

  /// No description provided for @systemAccountExpensePets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get systemAccountExpensePets;

  /// No description provided for @systemAccountExpenseTrading.
  ///
  /// In en, this message translates to:
  /// **'Trading'**
  String get systemAccountExpenseTrading;

  /// No description provided for @systemAccountExpenseTradingFee.
  ///
  /// In en, this message translates to:
  /// **'Trading Fee'**
  String get systemAccountExpenseTradingFee;

  /// No description provided for @systemAccountExpenseTradingTax.
  ///
  /// In en, this message translates to:
  /// **'Trading Tax'**
  String get systemAccountExpenseTradingTax;

  /// No description provided for @systemAccountExpenseTradingInterest.
  ///
  /// In en, this message translates to:
  /// **'Trading Interest'**
  String get systemAccountExpenseTradingInterest;

  /// No description provided for @systemAccountExpenseTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get systemAccountExpenseTax;

  /// No description provided for @systemAccountExpenseTaxWithholding.
  ///
  /// In en, this message translates to:
  /// **'Withholding Tax'**
  String get systemAccountExpenseTaxWithholding;

  /// No description provided for @systemAccountExpenseOther.
  ///
  /// In en, this message translates to:
  /// **'Other Expense'**
  String get systemAccountExpenseOther;

  /// No description provided for @systemAccountEquity.
  ///
  /// In en, this message translates to:
  /// **'Equity'**
  String get systemAccountEquity;

  /// No description provided for @systemAccountEquityOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get systemAccountEquityOpeningBalance;

  /// No description provided for @systemAccountEquitySplits.
  ///
  /// In en, this message translates to:
  /// **'Stock Splits'**
  String get systemAccountEquitySplits;

  /// No description provided for @systemAccountEquityAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get systemAccountEquityAdjustments;

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
  /// **'Select an account on the left to see its balance and activity.'**
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
  /// **'Add your first account to start tracking assets.'**
  String get accountsEmptyHint;

  /// No description provided for @accountsOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Account overview'**
  String get accountsOverviewTitle;

  /// No description provided for @accountsOverviewAccountsLabel.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsOverviewAccountsLabel;

  /// No description provided for @accountsOverviewInstitutionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Institutions'**
  String get accountsOverviewInstitutionsLabel;

  /// No description provided for @accountsOverviewCurrenciesLabel.
  ///
  /// In en, this message translates to:
  /// **'Currencies'**
  String get accountsOverviewCurrenciesLabel;

  /// No description provided for @accountsCategoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}}'**
  String accountsCategoryCount(int count);

  /// No description provided for @accountDetailEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountDetailEditAction;

  /// No description provided for @accountDetailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Account not found'**
  String get accountDetailNotFound;

  /// No description provided for @accountDetailBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Available balance'**
  String get accountDetailBalanceTitle;

  /// No description provided for @accountDetailTransferAction.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get accountDetailTransferAction;

  /// Action shown on a cash account detail reached from a cash asset
  ///
  /// In en, this message translates to:
  /// **'Adjust balance'**
  String get accountDetailAdjustBalanceAction;

  /// No description provided for @accountDetailAddBalanceAction.
  ///
  /// In en, this message translates to:
  /// **'Add cash balance'**
  String get accountDetailAddBalanceAction;

  /// No description provided for @accountDetailRecentActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get accountDetailRecentActivityTitle;

  /// No description provided for @accountDetailNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded for this account yet.'**
  String get accountDetailNoActivity;

  /// No description provided for @accountDetailTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accountDetailTypeLabel;

  /// No description provided for @accountDetailCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary currency'**
  String get accountDetailCurrencyLabel;

  /// No description provided for @accountDetailInstitutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Institution'**
  String get accountDetailInstitutionLabel;

  /// No description provided for @accountDetailNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Account number'**
  String get accountDetailNumberLabel;

  /// No description provided for @accountDetailNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get accountDetailNotesLabel;

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

  /// No description provided for @accountFormAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'More account details'**
  String get accountFormAdvancedTitle;

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

  /// Read-only account helper shown when editing a cash balance
  ///
  /// In en, this message translates to:
  /// **'This cash balance is linked to the account above. To move it, delete this balance and record it under another account.'**
  String get cashFormAccountLockedHint;

  /// Cash form status while checking the selected account for an existing cash asset
  ///
  /// In en, this message translates to:
  /// **'Checking this account for an existing cash balance…'**
  String get cashFormCheckingExisting;

  /// Cash form notice title when the selected account already has a cash asset
  ///
  /// In en, this message translates to:
  /// **'Existing cash balance found'**
  String get cashFormExistingFoundTitle;

  /// Cash form notice explaining duplicate prevention
  ///
  /// In en, this message translates to:
  /// **'Saving will update this account’s existing balance instead of creating a duplicate.'**
  String get cashFormExistingFoundBody;

  /// Fallback shown when editing a cash balance whose linked account is not available in the active account list
  ///
  /// In en, this message translates to:
  /// **'Linked account unavailable'**
  String get cashFormMissingAccount;

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

  /// No description provided for @activitySelectEntry.
  ///
  /// In en, this message translates to:
  /// **'Select an entry to inspect it without leaving the timeline'**
  String get activitySelectEntry;

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

  /// Activity feed page summary: expense total label
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get activityFeedSummaryExpense;

  /// Activity feed page summary: income total label
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get activityFeedSummaryIncome;

  /// Activity feed page summary: loaded entry count
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get activityFeedSummaryCount;

  /// Activity feed page summary: income minus expense
  ///
  /// In en, this message translates to:
  /// **'Net cash flow'**
  String get activityFeedSummaryNet;

  /// Activity feed page summary: number of currently loaded entries when more pages exist
  ///
  /// In en, this message translates to:
  /// **'{count} shown'**
  String activityFeedSummaryShown(int count);

  /// Activity feed page summary: complete entry count
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String activityFeedSummaryCountValue(int count);

  /// Activity day section trailing expense total
  ///
  /// In en, this message translates to:
  /// **'Out {amount}'**
  String activityFeedDayExpense(String amount);

  /// Activity day section trailing income total
  ///
  /// In en, this message translates to:
  /// **'In {amount}'**
  String activityFeedDayIncome(String amount);

  /// Toggle activity search field
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get activityFeedSearchAction;

  /// Activity search field hint
  ///
  /// In en, this message translates to:
  /// **'Search merchant, note, or account'**
  String get activityFeedSearchHint;

  /// Active search filter chip
  ///
  /// In en, this message translates to:
  /// **'“{query}”'**
  String activityFeedSearchTag(String query);

  /// Confirm dialog title when deleting a journal entry
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get activityEntryDeleteTitle;

  /// Confirm dialog body when deleting a journal entry
  ///
  /// In en, this message translates to:
  /// **'This removes the journal entry and its postings from your ledger. You can undo it from the confirmation message.'**
  String get activityEntryDeleteBody;

  /// Toast shown after deleting a journal entry
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get activityEntryDeleted;

  /// Toast shown when deleting a journal entry fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete this entry. Try again.'**
  String get activityEntryDeleteFailed;

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

  /// No description provided for @settingsAiSection.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get settingsAiSection;

  /// No description provided for @settingsAiHubTitle.
  ///
  /// In en, this message translates to:
  /// **'AI & device intelligence'**
  String get settingsAiHubTitle;

  /// No description provided for @settingsAiHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Providers, local models, agents, privacy, and activity'**
  String get settingsAiHubSubtitle;

  /// No description provided for @settingsAiHubRuntimeSection.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get settingsAiHubRuntimeSection;

  /// No description provided for @settingsAiHubTrustSection.
  ///
  /// In en, this message translates to:
  /// **'Privacy & transparency'**
  String get settingsAiHubTrustSection;

  /// Settings row that opens saved AI conversation history.
  ///
  /// In en, this message translates to:
  /// **'AI history'**
  String get settingsAiHistoryTitle;

  /// Settings row subtitle for saved AI conversation history.
  ///
  /// In en, this message translates to:
  /// **'Review saved AI conversations'**
  String get settingsAiHistorySubtitle;

  /// No description provided for @personalMemoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal memory'**
  String get personalMemoryTitle;

  /// No description provided for @personalMemorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage goals, preferences, constraints, and rules used by AI'**
  String get personalMemorySubtitle;

  /// No description provided for @personalMemorySection.
  ///
  /// In en, this message translates to:
  /// **'Confirmed profile'**
  String get personalMemorySection;

  /// No description provided for @personalMemoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No confirmed profile facts yet.'**
  String get personalMemoryEmpty;

  /// No description provided for @personalMemoryAdd.
  ///
  /// In en, this message translates to:
  /// **'Add profile fact'**
  String get personalMemoryAdd;

  /// No description provided for @personalMemoryCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Add profile fact'**
  String get personalMemoryCreateTitle;

  /// No description provided for @personalMemoryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile fact'**
  String get personalMemoryEditTitle;

  /// No description provided for @personalMemoryKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get personalMemoryKind;

  /// No description provided for @personalMemoryKindGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get personalMemoryKindGoal;

  /// No description provided for @personalMemoryKindPreference.
  ///
  /// In en, this message translates to:
  /// **'Preference'**
  String get personalMemoryKindPreference;

  /// No description provided for @personalMemoryKindConstraint.
  ///
  /// In en, this message translates to:
  /// **'Constraint'**
  String get personalMemoryKindConstraint;

  /// No description provided for @personalMemoryKindRule.
  ///
  /// In en, this message translates to:
  /// **'Rule'**
  String get personalMemoryKindRule;

  /// No description provided for @personalMemoryKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get personalMemoryKey;

  /// No description provided for @personalMemoryKeyHint.
  ///
  /// In en, this message translates to:
  /// **'For example: cash_buffer_months'**
  String get personalMemoryKeyHint;

  /// No description provided for @personalMemoryValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get personalMemoryValue;

  /// No description provided for @personalMemoryValueHint.
  ///
  /// In en, this message translates to:
  /// **'Text or JSON value'**
  String get personalMemoryValueHint;

  /// No description provided for @personalMemorySummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get personalMemorySummary;

  /// No description provided for @personalMemorySummaryHint.
  ///
  /// In en, this message translates to:
  /// **'A clear fact the agent may use as evidence'**
  String get personalMemorySummaryHint;

  /// No description provided for @personalMemoryDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain (optional)'**
  String get personalMemoryDomain;

  /// No description provided for @personalMemoryDomainHint.
  ///
  /// In en, this message translates to:
  /// **'finance, health, knowledge, or execution'**
  String get personalMemoryDomainHint;

  /// No description provided for @personalMemoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Key and summary are required'**
  String get personalMemoryRequired;

  /// No description provided for @personalMemoryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this profile fact?'**
  String get personalMemoryDeleteTitle;

  /// No description provided for @personalMemoryDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It will stop appearing in future AI context. This cannot be undone from this screen.'**
  String get personalMemoryDeleteBody;

  /// No description provided for @personalMemoryInactiveDomain.
  ///
  /// In en, this message translates to:
  /// **'Kept locally; excluded from AI while this domain is off'**
  String get personalMemoryInactiveDomain;

  /// No description provided for @personalMemoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load personal memory: {error}'**
  String personalMemoryLoadFailed(String error);

  /// No description provided for @settingsAdvancedHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced diagnostics'**
  String get settingsAdvancedHubTitle;

  /// No description provided for @settingsAdvancedHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Logs and performance tools'**
  String get settingsAdvancedHubSubtitle;

  /// Settings section header for app version and low-frequency diagnostics.
  ///
  /// In en, this message translates to:
  /// **'About & diagnostics'**
  String get settingsAboutDiagnosticsSection;

  /// Settings section header for sync, backup/restore, and storage maintenance.
  ///
  /// In en, this message translates to:
  /// **'Data & sync'**
  String get settingsDataSection;

  /// Settings section header for notification, device privacy, and optional telemetry controls.
  ///
  /// In en, this message translates to:
  /// **'Notifications & privacy'**
  String get settingsNotificationsPrivacySection;

  /// Settings tile and page title for LifeOS data management
  ///
  /// In en, this message translates to:
  /// **'Data & storage'**
  String get settingsDataManagementTitle;

  /// Settings data-management tile and page subtitle
  ///
  /// In en, this message translates to:
  /// **'Inspect, export, clean, and reset each OS from one place'**
  String get settingsDataManagementSubtitle;

  /// No description provided for @dataManagementBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup & restore'**
  String get dataManagementBackupTitle;

  /// No description provided for @dataManagementBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a backup before destructive maintenance'**
  String get dataManagementBackupSubtitle;

  /// No description provided for @dataManagementSafetyNotice.
  ///
  /// In en, this message translates to:
  /// **'Cache cleanup removes only rebuildable local data. OS reset actions require confirmation and are kept separate from cache maintenance.'**
  String get dataManagementSafetyNotice;

  /// No description provided for @dataManagementAutomaticTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic maintenance'**
  String get dataManagementAutomaticTitle;

  /// No description provided for @dataManagementAutomaticSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily cleanup of expired AI, agent, ingest, and event history'**
  String get dataManagementAutomaticSubtitle;

  /// No description provided for @dataManagementRunMaintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Run maintenance now'**
  String get dataManagementRunMaintenanceTitle;

  /// No description provided for @dataManagementRunMaintenanceNever.
  ///
  /// In en, this message translates to:
  /// **'No maintenance run recorded'**
  String get dataManagementRunMaintenanceNever;

  /// No description provided for @dataManagementRunMaintenanceLast.
  ///
  /// In en, this message translates to:
  /// **'Last run removed {count} rows'**
  String dataManagementRunMaintenanceLast(int count);

  /// No description provided for @dataManagementMaintenanceRunning.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get dataManagementMaintenanceRunning;

  /// No description provided for @dataManagementMaintenanceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Maintenance complete · {count} rows removed'**
  String dataManagementMaintenanceSuccess(int count);

  /// No description provided for @dataManagementDomainEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get dataManagementDomainEnabled;

  /// No description provided for @dataManagementDomainDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get dataManagementDomainDisabled;

  /// No description provided for @dataManagementSourceRows.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get dataManagementSourceRows;

  /// No description provided for @dataManagementDeletedRows.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get dataManagementDeletedRows;

  /// No description provided for @dataManagementCacheRows.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get dataManagementCacheRows;

  /// No description provided for @dataManagementTableSummary.
  ///
  /// In en, this message translates to:
  /// **'{sourceTables} source tables · {cacheTables} cache tables'**
  String dataManagementTableSummary(int sourceTables, int cacheTables);

  /// No description provided for @dataManagementCacheHelp.
  ///
  /// In en, this message translates to:
  /// **'Local derived data; features rebuild it when needed.'**
  String get dataManagementCacheHelp;

  /// No description provided for @dataManagementClearCacheAction.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get dataManagementClearCacheAction;

  /// No description provided for @dataManagementClearing.
  ///
  /// In en, this message translates to:
  /// **'Clearing…'**
  String get dataManagementClearing;

  /// No description provided for @dataManagementClearCacheConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear {domain} cache?'**
  String dataManagementClearCacheConfirmTitle(String domain);

  /// No description provided for @dataManagementClearCacheConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes {count} local cache rows. Synced source data is not affected.'**
  String dataManagementClearCacheConfirmBody(int count);

  /// No description provided for @dataManagementClearCacheSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} cache rows'**
  String dataManagementClearCacheSuccess(int count);

  /// No description provided for @dataManagementExportDomainAction.
  ///
  /// In en, this message translates to:
  /// **'Export OS'**
  String get dataManagementExportDomainAction;

  /// No description provided for @dataManagementResetDeviceAction.
  ///
  /// In en, this message translates to:
  /// **'Reset this device'**
  String get dataManagementResetDeviceAction;

  /// No description provided for @dataManagementResetEverywhereAction.
  ///
  /// In en, this message translates to:
  /// **'Delete everywhere'**
  String get dataManagementResetEverywhereAction;

  /// No description provided for @dataManagementResetting.
  ///
  /// In en, this message translates to:
  /// **'Resetting…'**
  String get dataManagementResetting;

  /// No description provided for @dataManagementResetDeviceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset {domain} on this device?'**
  String dataManagementResetDeviceConfirmTitle(String domain);

  /// No description provided for @dataManagementResetDeviceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Data and history for this domain will be removed from this device. If cloud sync is enabled, cloud data may download again on the next sync.'**
  String get dataManagementResetDeviceConfirmBody;

  /// No description provided for @dataManagementResetEverywhereConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {domain}?'**
  String dataManagementResetEverywhereConfirmTitle(String domain);

  /// No description provided for @dataManagementResetEverywhereConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes this domain\'s data from the cloud and every connected device. Offline devices cannot restore it when they reconnect. This action cannot be undone.'**
  String get dataManagementResetEverywhereConfirmBody;

  /// No description provided for @dataManagementResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Reset complete · {count} local rows removed'**
  String dataManagementResetSuccess(int count);

  /// No description provided for @dataManagementSharedTitle.
  ///
  /// In en, this message translates to:
  /// **'AI & cross-domain data'**
  String get dataManagementSharedTitle;

  /// No description provided for @dataManagementSharedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Device-local conversations, traces, memories, event projections, and agent results'**
  String get dataManagementSharedSubtitle;

  /// No description provided for @dataManagementChatRows.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get dataManagementChatRows;

  /// No description provided for @dataManagementAiRows.
  ///
  /// In en, this message translates to:
  /// **'AI audit'**
  String get dataManagementAiRows;

  /// No description provided for @dataManagementMemoryRows.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get dataManagementMemoryRows;

  /// No description provided for @dataManagementAgentRows.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get dataManagementAgentRows;

  /// No description provided for @dataManagementStorageUsage.
  ///
  /// In en, this message translates to:
  /// **'Database {used} · {reclaimable} reclaimable'**
  String dataManagementStorageUsage(String used, String reclaimable);

  /// No description provided for @dataManagementClearSharedAction.
  ///
  /// In en, this message translates to:
  /// **'Clear local history'**
  String get dataManagementClearSharedAction;

  /// No description provided for @dataManagementClearSharedConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear AI and cross-domain history?'**
  String get dataManagementClearSharedConfirmTitle;

  /// No description provided for @dataManagementClearSharedConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes {count} local chat, audit, memory, event, and agent-history rows. OS source data and preferences remain.'**
  String dataManagementClearSharedConfirmBody(int count);

  /// No description provided for @dataManagementClearSharedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} local history rows'**
  String dataManagementClearSharedSuccess(int count);

  /// No description provided for @dataManagementCompactAction.
  ///
  /// In en, this message translates to:
  /// **'Compact database'**
  String get dataManagementCompactAction;

  /// No description provided for @dataManagementCompacting.
  ///
  /// In en, this message translates to:
  /// **'Compacting…'**
  String get dataManagementCompacting;

  /// No description provided for @dataManagementCompactSuccess.
  ///
  /// In en, this message translates to:
  /// **'Database compacted'**
  String get dataManagementCompactSuccess;

  /// No description provided for @dataManagementResetAllTitle.
  ///
  /// In en, this message translates to:
  /// **'All OS data'**
  String get dataManagementResetAllTitle;

  /// No description provided for @dataManagementResetAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use only when you want to start over across FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS. Account, device, settings, and FX configuration remain.'**
  String get dataManagementResetAllSubtitle;

  /// No description provided for @dataManagementResetAllDeviceAction.
  ///
  /// In en, this message translates to:
  /// **'Reset all on this device'**
  String get dataManagementResetAllDeviceAction;

  /// No description provided for @dataManagementResetAllEverywhereAction.
  ///
  /// In en, this message translates to:
  /// **'Delete all OS data everywhere'**
  String get dataManagementResetAllEverywhereAction;

  /// No description provided for @dataManagementResetAllDeviceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset every OS on this device?'**
  String get dataManagementResetAllDeviceConfirmTitle;

  /// No description provided for @dataManagementResetAllDeviceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All local OS source data, caches, AI history, memories, and agent results will be removed. Cloud data can download again during sync.'**
  String get dataManagementResetAllDeviceConfirmBody;

  /// No description provided for @dataManagementResetAllEverywhereConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete every OS?'**
  String get dataManagementResetAllEverywhereConfirmTitle;

  /// No description provided for @dataManagementResetAllEverywhereConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All OS data will be permanently deleted from the server and every device. Account, device, settings, and FX configuration remain. This cannot be undone.'**
  String get dataManagementResetAllEverywhereConfirmBody;

  /// No description provided for @backupDomainPageTitle.
  ///
  /// In en, this message translates to:
  /// **'{domain} backup'**
  String backupDomainPageTitle(String domain);

  /// Settings section header for LifeOS domain opt-in management
  ///
  /// In en, this message translates to:
  /// **'Domains'**
  String get settingsDomainsSection;

  /// No description provided for @settingsDomainsDeepLinkBlockedNotice.
  ///
  /// In en, this message translates to:
  /// **'That link belongs to a domain that is not enabled yet. Turn the domain on below to open it.'**
  String get settingsDomainsDeepLinkBlockedNotice;

  /// Settings tile and page title for LifeOS domain management
  ///
  /// In en, this message translates to:
  /// **'Domain management'**
  String get settingsDomainsTitle;

  /// Settings tile subtitle for LifeOS domain management
  ///
  /// In en, this message translates to:
  /// **'Manage FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS'**
  String get settingsDomainsSubtitle;

  /// Subtitle for the always-on FinanceOS card in domain settings
  ///
  /// In en, this message translates to:
  /// **'Always-on finance domain: currency, FX rates, risk posture, allocation, and FIRE planning assumptions'**
  String get settingsDomainsFinanceSubtitle;

  /// Badge for the always-on FinanceOS domain
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get settingsDomainsFinanceAlwaysOnBadge;

  /// Toast shown after disabling an optional LifeOS domain from domain settings.
  ///
  /// In en, this message translates to:
  /// **'{domain} disabled. You can re-enable it here at any time.'**
  String settingsDomainsDisabledToast(String domain);

  /// No description provided for @settingsDomainsEnableSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'{domain} is ready'**
  String settingsDomainsEnableSuccessTitle(String domain);

  /// No description provided for @settingsDomainsEnableSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Open {domain} now and create the first useful item. You can also come back later.'**
  String settingsDomainsEnableSuccessBody(String domain);

  /// No description provided for @settingsDomainsOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get settingsDomainsOpenNow;

  /// No description provided for @settingsDomainsOpenLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get settingsDomainsOpenLater;

  /// No description provided for @settingsDomainsDisableConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off {domain}?'**
  String settingsDomainsDisableConfirmTitle(String domain);

  /// No description provided for @settingsDomainsDisableConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your {domain} data stays on this device and in sync, but its navigation, tools, background agents, and notifications will stop until you turn it on again.'**
  String settingsDomainsDisableConfirmBody(String domain);

  /// No description provided for @settingsDomainsDisableConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get settingsDomainsDisableConfirmAction;

  /// Open operational settings for an enabled LifeOS domain.
  ///
  /// In en, this message translates to:
  /// **'Configure {domain}'**
  String settingsDomainsConfigure(String domain);

  /// Settings page title for LifeOS agent management.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agentSettingsTitle;

  /// Hint text shown at the top of the Agents settings page.
  ///
  /// In en, this message translates to:
  /// **'Control scheduled LifeOS agents for active domains on this device.'**
  String get agentSettingsSubtitle;

  /// Empty state title when no active domain has registered agents.
  ///
  /// In en, this message translates to:
  /// **'No active agents'**
  String get agentSettingsNoActiveTitle;

  /// Empty state message when no active domain has registered agents.
  ///
  /// In en, this message translates to:
  /// **'Enable a LifeOS domain to see its agents here.'**
  String get agentSettingsNoActiveMessage;

  /// Button label from the Agents settings empty state to open LifeOS domain management.
  ///
  /// In en, this message translates to:
  /// **'Manage domains'**
  String get agentSettingsManageDomains;

  /// Badge for non-toggleable managed agents.
  ///
  /// In en, this message translates to:
  /// **'Managed'**
  String get agentSettingsManagedBadge;

  /// Button label to run an agent immediately.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get agentSettingsRunNow;

  /// Button label to open the latest visible result from an agent run.
  ///
  /// In en, this message translates to:
  /// **'View result'**
  String get agentSettingsViewResult;

  /// Button label to open an agent run history sheet.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get agentSettingsViewHistory;

  /// Sheet title for one agent's run history.
  ///
  /// In en, this message translates to:
  /// **'{agentName} history'**
  String agentSettingsHistoryTitle(String agentName);

  /// Empty state title for an agent history sheet with no runs.
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get agentSettingsHistoryEmptyTitle;

  /// Empty state message for an agent history sheet with no runs.
  ///
  /// In en, this message translates to:
  /// **'Run this agent once to start its local history.'**
  String get agentSettingsHistoryEmptyMessage;

  /// Button/status label while an agent is running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentSettingsRunning;

  /// Badge for an enabled agent.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get agentSettingsEnabled;

  /// Badge for a disabled agent.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get agentSettingsDisabled;

  /// Compact overview metric showing enabled agents out of all active-domain agents.
  ///
  /// In en, this message translates to:
  /// **'Enabled {enabled}/{total}'**
  String agentSettingsOverviewEnabled(int enabled, int total);

  /// Compact overview metric showing enabled agents with ready results.
  ///
  /// In en, this message translates to:
  /// **'Ready {count}'**
  String agentSettingsOverviewReady(int count);

  /// Compact overview metric showing enabled agents whose latest run failed.
  ///
  /// In en, this message translates to:
  /// **'Failed {count}'**
  String agentSettingsOverviewFailed(int count);

  /// Compact overview metric showing enabled notification-capable agents with notifications on.
  ///
  /// In en, this message translates to:
  /// **'Notifications {count}'**
  String agentSettingsOverviewNotificationsOn(int count);

  /// Title for the privacy-safe rolling Agent quality summary.
  ///
  /// In en, this message translates to:
  /// **'30-day quality'**
  String get agentQualityTitle;

  /// Agent quality summary shown before any terminal runs exist.
  ///
  /// In en, this message translates to:
  /// **'No completed runs in this window'**
  String get agentQualityNoRuns;

  /// Completed Agent runs included in the quality window.
  ///
  /// In en, this message translates to:
  /// **'{count} completed runs'**
  String agentQualityCompletedRuns(int count);

  /// Share of completed Agent runs with a ready result.
  ///
  /// In en, this message translates to:
  /// **'Ready {percent}% · {count}/{total}'**
  String agentQualityReadyRate(int percent, int count, int total);

  /// Share of completed Agent runs with no meaningful finding.
  ///
  /// In en, this message translates to:
  /// **'No finding {percent}% · {count}/{total}'**
  String agentQualityNoFindingRate(int percent, int count, int total);

  /// Share of completed Agent runs that failed.
  ///
  /// In en, this message translates to:
  /// **'Failed {percent}% · {count}/{total}'**
  String agentQualityFailureRate(int percent, int count, int total);

  /// Share of Agent artifacts dismissed or snoozed by the user.
  ///
  /// In en, this message translates to:
  /// **'Hidden or delayed {percent}% · {count}/{total}'**
  String agentQualitySuppressedRate(int percent, int count, int total);

  /// Share of evidence-bearing Agent artifacts whose evidence references all have routes.
  ///
  /// In en, this message translates to:
  /// **'Evidence-linked {percent}% · {count}/{total}'**
  String agentQualityEvidenceRate(int percent, int count, int total);

  /// Agent quality summary shown before any evidence navigation attempts exist.
  ///
  /// In en, this message translates to:
  /// **'No evidence-open samples'**
  String get agentQualityEvidenceNavigationNoSamples;

  /// Share of Agent evidence navigation attempts accepted by the app router.
  ///
  /// In en, this message translates to:
  /// **'Evidence opened {percent}% · {successes}/{attempts}'**
  String agentQualityEvidenceNavigationRate(
    int percent,
    int successes,
    int attempts,
  );

  /// Privacy explanation below the rolling Agent quality summary.
  ///
  /// In en, this message translates to:
  /// **'Device-only aggregates · no result content, evidence ids, or routes retained'**
  String get agentQualityPrivacyNote;

  /// Subtitle when an agent has no run history.
  ///
  /// In en, this message translates to:
  /// **'Never run'**
  String get agentSettingsNeverRun;

  /// Badge showing when an agent last ran.
  ///
  /// In en, this message translates to:
  /// **'Last run {date}'**
  String agentSettingsLastRunAt(String date);

  /// Badge showing the next eligible automatic agent run.
  ///
  /// In en, this message translates to:
  /// **'Next {date}'**
  String agentSettingsNextRunAt(String date);

  /// Schedule status when an agent is due on the next foreground tick.
  ///
  /// In en, this message translates to:
  /// **'Next check when the app opens'**
  String get agentSettingsNextRunOnOpen;

  /// Label for the agent execution mode shown in agent details.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get agentSettingsExecutionTitle;

  /// Explanation that the current mobile scheduler catches up scheduled agents on foreground.
  ///
  /// In en, this message translates to:
  /// **'Checks when the app opens or returns to the foreground'**
  String get agentSettingsExecutionForeground;

  /// Explanation below the manual run action.
  ///
  /// In en, this message translates to:
  /// **'Runs once without changing the automatic schedule'**
  String get agentSettingsRunNowHint;

  /// Schedule hint for agents with a preferred local run time.
  ///
  /// In en, this message translates to:
  /// **'around {time}'**
  String agentSettingsAroundTime(String time);

  /// Schedule cadence for agents that run every N hours.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} hour(s)'**
  String agentSettingsEveryHours(int hours);

  /// Schedule cadence for agents that run every N minutes.
  ///
  /// In en, this message translates to:
  /// **'Every {minutes} min'**
  String agentSettingsEveryMinutes(int minutes);

  /// Schedule cadence for agents whose interval contains both hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'Every {hours}h {minutes}m'**
  String agentSettingsEveryHoursMinutes(int hours, int minutes);

  /// Agent schedule cadence label for once per day.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get agentSettingsCadenceDaily;

  /// Agent schedule cadence label for once per week.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get agentSettingsCadenceWeekly;

  /// Agent schedule cadence label for once per month.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get agentSettingsCadenceMonthly;

  /// Agent schedule cadence label for once per year.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get agentSettingsCadenceYearly;

  /// Toast fallback after an agent run finishes without a summary.
  ///
  /// In en, this message translates to:
  /// **'{agentName} finished'**
  String agentSettingsRunFinished(String agentName);

  /// Toast shown when a manual agent run is skipped because another run is already active.
  ///
  /// In en, this message translates to:
  /// **'{agentName} is already running'**
  String agentSettingsRunBusy(String agentName);

  /// Toast shown when a manual agent run fails before an agent result can be returned.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t run agent: {error}'**
  String agentSettingsRunFailed(String error);

  /// Toast shown when an agent settings toggle fails to save.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update agent settings: {error}'**
  String agentSettingsSaveFailed(String error);

  /// Diagnostic badge shown when a registered agent has no presentation metadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata missing'**
  String get agentSettingsMissingPresentationBadge;

  /// Fallback description when a registered agent has no presentation metadata.
  ///
  /// In en, this message translates to:
  /// **'This agent is registered without presentation metadata.'**
  String get agentSettingsMissingPresentationDescription;

  /// Agent settings row subtitle with lifecycle status and run detail.
  ///
  /// In en, this message translates to:
  /// **'{status} · {detail}'**
  String agentSettingsStatusWithDetail(String status, String detail);

  /// Agent run trigger label: manual run.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get agentSettingsTriggerManual;

  /// Agent run trigger label: scheduled run.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get agentSettingsTriggerSchedule;

  /// Agent run trigger label: background due flag.
  ///
  /// In en, this message translates to:
  /// **'Background due'**
  String get agentSettingsTriggerBackgroundDue;

  /// Agent run trigger label: foreground catch-up run.
  ///
  /// In en, this message translates to:
  /// **'Catch-up'**
  String get agentSettingsTriggerCatchUp;

  /// Settings sub-page section header for logs, performance, and developer tools.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic tools'**
  String get settingsAdvancedSection;

  /// Settings tile and page title for local AI model management
  ///
  /// In en, this message translates to:
  /// **'AI Models'**
  String get settingsAiModelsTitle;

  /// Settings tile subtitle for local AI model management
  ///
  /// In en, this message translates to:
  /// **'Download and manage local AI and speech models'**
  String get settingsAiModelsSubtitle;

  /// Title for the LLM settings card that checks the FRB-backed agent runtime path
  ///
  /// In en, this message translates to:
  /// **'AI service check'**
  String get aiLlmRuntimeCheckTitle;

  /// Description for the FRB-backed runtime check when an active LLM profile is available
  ///
  /// In en, this message translates to:
  /// **'Send a test request with the current model configuration to check whether the AI service is available.'**
  String get aiLlmRuntimeCheckReady;

  /// Runtime check unavailable message shown when no usable active LLM profile exists
  ///
  /// In en, this message translates to:
  /// **'Save and activate a model provider before checking the AI service.'**
  String get aiLlmRuntimeCheckNoProfile;

  /// Button label that starts an FRB-backed agent runtime check
  ///
  /// In en, this message translates to:
  /// **'Start check'**
  String get aiLlmRuntimeCheckAction;

  /// Button label while the FRB-backed agent runtime check is running
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get aiLlmRuntimeCheckRunning;

  /// Short prompt sent through the active LLM profile for the agent runtime check
  ///
  /// In en, this message translates to:
  /// **'Reply with one short sentence confirming NaviWealth can reach the current AI service.'**
  String get aiLlmRuntimeCheckPrompt;

  /// Toast shown after the FRB-backed agent runtime check completes.
  ///
  /// In en, this message translates to:
  /// **'AI service check completed: {status}'**
  String aiLlmRuntimeCheckSucceeded(String status);

  /// Status text and toast shown when the FRB-backed agent runtime check fails.
  ///
  /// In en, this message translates to:
  /// **'AI service check failed: {error}'**
  String aiLlmRuntimeCheckFailed(String error);

  /// Inline status shown after the FRB-backed native runtime step completes.
  ///
  /// In en, this message translates to:
  /// **'On-device check: {status}'**
  String aiLlmRuntimeCheckStatus(String status);

  /// Button label that opens an agent result detail sheet.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get agentResultReviewAction;

  /// Button label that retries a failed agent run.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get agentResultRetryAction;

  /// Button label that opens an AI follow-up for an agent result action.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get agentResultAskAction;

  /// Loading message shown while a domain surface loads agent artifacts and run status.
  ///
  /// In en, this message translates to:
  /// **'Checking the latest agent results for this view.'**
  String get agentResultLoadingBody;

  /// Agent artifact kind label for briefings.
  ///
  /// In en, this message translates to:
  /// **'Briefing'**
  String get agentResultKindBriefing;

  /// Agent artifact kind label for reviews.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get agentResultKindReview;

  /// Agent artifact kind label for alerts.
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get agentResultKindAlert;

  /// Agent artifact kind label for reminders.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get agentResultKindReminder;

  /// Agent artifact severity badge for items needing attention.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get agentResultSeverityAttention;

  /// Agent artifact severity badge for warning items.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get agentResultSeverityWarning;

  /// Agent run lifecycle status: running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentRunStatusRunning;

  /// Agent run lifecycle status: ran without a user-visible finding.
  ///
  /// In en, this message translates to:
  /// **'No finding'**
  String get agentRunStatusNoFinding;

  /// Agent run lifecycle status: ready with a result.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get agentRunStatusReady;

  /// Agent run lifecycle status: failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentRunStatusFailed;

  /// Agent detail section title for insights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get agentResultInsightsSection;

  /// Agent detail section title for evidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get agentResultEvidenceSection;

  /// Collapsed agent detail section for evidence and analysis method.
  ///
  /// In en, this message translates to:
  /// **'Evidence & method'**
  String get agentResultEvidenceMethodSection;

  /// No description provided for @agentResultEvidenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sources'**
  String agentResultEvidenceCount(int count);

  /// Fallback description for an evidence reference.
  ///
  /// In en, this message translates to:
  /// **'View the data source behind this evidence.'**
  String get agentResultEvidenceAvailableBody;

  /// No description provided for @agentResultEvidenceSupportCount.
  ///
  /// In en, this message translates to:
  /// **'Supported by {count} sources'**
  String agentResultEvidenceSupportCount(int count);

  /// Open the domain page related to an insight.
  ///
  /// In en, this message translates to:
  /// **'Open related page'**
  String get agentResultOpenRelatedPage;

  /// Title for the low-level agent trace entry.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get agentResultTechnicalDetailsTitle;

  /// Description for the low-level agent trace entry.
  ///
  /// In en, this message translates to:
  /// **'Review the analysis steps and tool activity for this result.'**
  String get agentResultTechnicalDetailsBody;

  /// Agent detail section title for the linked AI transparency trace.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get agentResultTraceSection;

  /// Agent detail trace entry title.
  ///
  /// In en, this message translates to:
  /// **'Runtime trace'**
  String get agentResultTraceTitle;

  /// Agent detail trace entry description.
  ///
  /// In en, this message translates to:
  /// **'Review the AI call chain and tool activity.'**
  String get agentResultTraceBody;

  /// Button label that opens the AI transparency trace for an agent result.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get agentResultTraceAction;

  /// Agent detail section title for actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get agentResultActionsSection;

  /// Agent detail action title for asking a follow-up question.
  ///
  /// In en, this message translates to:
  /// **'Ask Agent'**
  String get agentResultAskFollowUpTitle;

  /// Agent detail action description for asking a follow-up question.
  ///
  /// In en, this message translates to:
  /// **'Explain this result and its evidence.'**
  String get agentResultAskFollowUpBody;

  /// Agent detail action title for showing evidence behind the result.
  ///
  /// In en, this message translates to:
  /// **'Show evidence'**
  String get agentResultShowEvidenceTitle;

  /// Agent detail action description for showing evidence behind the result.
  ///
  /// In en, this message translates to:
  /// **'Map the evidence to the claims in this result.'**
  String get agentResultShowEvidenceBody;

  /// Agent detail action title for turning an agent result into a plan.
  ///
  /// In en, this message translates to:
  /// **'Create plan'**
  String get agentResultCreatePlanTitle;

  /// Agent detail action description for turning an agent result into a plan.
  ///
  /// In en, this message translates to:
  /// **'Turn this result into proposed next steps.'**
  String get agentResultCreatePlanBody;

  /// Agent detail action title for snoozing an agent result.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get agentResultSnoozeTitle;

  /// Agent detail action description for snoozing an agent result.
  ///
  /// In en, this message translates to:
  /// **'Hide this result until tomorrow.'**
  String get agentResultSnoozeBody;

  /// Button label that snoozes an agent result.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get agentResultSnoozeAction;

  /// Agent detail action title for dismissing an agent result.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get agentResultDismissTitle;

  /// Agent detail action description for dismissing an agent result.
  ///
  /// In en, this message translates to:
  /// **'Hide this result from active surfaces.'**
  String get agentResultDismissBody;

  /// Button label that dismisses an agent result.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get agentResultDismissAction;

  /// Toast shown when snoozing or dismissing an agent result fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update this result: {error}'**
  String agentResultVisibilityActionFailed(String error);

  /// No description provided for @agentResultLocalMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'How this result was produced'**
  String get agentResultLocalMethodTitle;

  /// No description provided for @agentResultLocalMethodDeterministicBody.
  ///
  /// In en, this message translates to:
  /// **'Calculated from local domain records using deterministic rules.'**
  String get agentResultLocalMethodDeterministicBody;

  /// No description provided for @agentResultLocalMethodAssistedBody.
  ///
  /// In en, this message translates to:
  /// **'Synthesized on device from local domain records; the supporting metrics remain source-derived.'**
  String get agentResultLocalMethodAssistedBody;

  /// No description provided for @agentResultLocalMethodSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Data source'**
  String get agentResultLocalMethodSourceLabel;

  /// No description provided for @agentResultLocalMethodRuntimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get agentResultLocalMethodRuntimeLabel;

  /// No description provided for @agentResultLocalMethodRuntimeValue.
  ///
  /// In en, this message translates to:
  /// **'On device'**
  String get agentResultLocalMethodRuntimeValue;

  /// No description provided for @agentResultMetricCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get agentResultMetricCurrent;

  /// No description provided for @agentResultMetricBaseline.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get agentResultMetricBaseline;

  /// Fallback action description when an agent result action has no metadata.
  ///
  /// In en, this message translates to:
  /// **'Open this action from the agent result.'**
  String get agentResultActionFallbackBody;

  /// Fallback action description that exposes the legacy action key only as secondary metadata.
  ///
  /// In en, this message translates to:
  /// **'Action key: {key}'**
  String agentResultActionFallbackWithKey(String key);

  /// Presentation label for the FinanceOS weekly wealth review agent.
  ///
  /// In en, this message translates to:
  /// **'Weekly Wealth Review'**
  String get agentPresentationWeeklyWealthReviewLabel;

  /// Presentation description for the FinanceOS weekly wealth review agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews net worth, allocation concentration, price freshness, and FX coverage.'**
  String get agentPresentationWeeklyWealthReviewDescription;

  /// Presentation label for the FinanceOS cashflow anomaly review agent.
  ///
  /// In en, this message translates to:
  /// **'Cashflow Anomaly Review'**
  String get agentPresentationCashflowAnomalyReviewLabel;

  /// Presentation description for the FinanceOS cashflow anomaly review agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews on-device monthly spending anomalies.'**
  String get agentPresentationCashflowAnomalyReviewDescription;

  /// Presentation label for the FinanceOS FIRE plan drift monitor agent.
  ///
  /// In en, this message translates to:
  /// **'FIRE Plan Drift Monitor'**
  String get agentPresentationFirePlanDriftMonitorLabel;

  /// Presentation description for the FinanceOS FIRE plan drift monitor agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews withdrawal rate, cash runway, plan ETA, and stress-test drift.'**
  String get agentPresentationFirePlanDriftMonitorDescription;

  /// Presentation label for the FinanceOS options income risk review agent.
  ///
  /// In en, this message translates to:
  /// **'Options Income Risk Review'**
  String get agentPresentationOptionsIncomeRiskReviewLabel;

  /// Presentation description for the FinanceOS options income risk review agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews scan freshness, quote quality, concentration, and contract risk.'**
  String get agentPresentationOptionsIncomeRiskReviewDescription;

  /// Presentation label for the HealthOS recovery alert agent.
  ///
  /// In en, this message translates to:
  /// **'Recovery Alert'**
  String get agentPresentationRecoveryAlertLabel;

  /// Presentation description for the HealthOS recovery alert agent.
  ///
  /// In en, this message translates to:
  /// **'Flags short sleep, low HRV, and recovery signals that need attention.'**
  String get agentPresentationRecoveryAlertDescription;

  /// Presentation label for the HealthOS weekly summary agent.
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get agentPresentationWeeklySummaryLabel;

  /// Presentation description for the HealthOS weekly summary agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews the week across sleep, activity, recovery, and trend evidence.'**
  String get agentPresentationWeeklySummaryDescription;

  /// Presentation label for the KnowledgeOS review agent.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Review'**
  String get agentPresentationKnowledgeReviewLabel;

  /// Presentation description for the KnowledgeOS review agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews due decisions and stale assumptions.'**
  String get agentPresentationKnowledgeReviewDescription;

  /// Presentation label for the KnowledgeOS assumption agent.
  ///
  /// In en, this message translates to:
  /// **'Assumption Review'**
  String get agentPresentationKnowledgeAssumptionLabel;

  /// Presentation description for the KnowledgeOS assumption agent.
  ///
  /// In en, this message translates to:
  /// **'Finds assumptions that need revalidation.'**
  String get agentPresentationKnowledgeAssumptionDescription;

  /// Presentation label for the KnowledgeOS contradiction agent.
  ///
  /// In en, this message translates to:
  /// **'Contradiction Review'**
  String get agentPresentationKnowledgeContradictionLabel;

  /// Presentation description for the KnowledgeOS contradiction agent.
  ///
  /// In en, this message translates to:
  /// **'Looks for conflicting notes, decisions, and assumptions.'**
  String get agentPresentationKnowledgeContradictionDescription;

  /// Presentation label for the KnowledgeOS inbox triage agent.
  ///
  /// In en, this message translates to:
  /// **'Inbox Triage'**
  String get agentPresentationKnowledgeInboxTriageLabel;

  /// Presentation description for the KnowledgeOS inbox triage agent.
  ///
  /// In en, this message translates to:
  /// **'Surfaces captured notes that need classification or follow-up.'**
  String get agentPresentationKnowledgeInboxTriageDescription;

  /// Presentation label for the ExecutionOS review agent.
  ///
  /// In en, this message translates to:
  /// **'Execution Review'**
  String get agentPresentationExecutionReviewLabel;

  /// Presentation description for the ExecutionOS review agent.
  ///
  /// In en, this message translates to:
  /// **'Reviews today actions, blocked work, commitments, and weekly progress.'**
  String get agentPresentationExecutionReviewDescription;

  /// Header for a ready proposal returned by the FRB-backed runtime check.
  ///
  /// In en, this message translates to:
  /// **'Ready proposal · {kind}'**
  String aiLlmRuntimeProposalTitle(String kind);

  /// Warning row for a ready proposal returned by the FRB-backed runtime check.
  ///
  /// In en, this message translates to:
  /// **'Warning: {warning}'**
  String aiLlmRuntimeProposalWarning(String warning);

  /// Button and confirm action label for applying a ready proposal returned by the FRB-backed runtime check
  ///
  /// In en, this message translates to:
  /// **'Apply proposal'**
  String get aiLlmRuntimeProposalApply;

  /// Button label while applying a ready proposal returned by the FRB-backed runtime check
  ///
  /// In en, this message translates to:
  /// **'Applying…'**
  String get aiLlmRuntimeProposalApplying;

  /// Confirm dialog title before applying a ready proposal returned by the FRB-backed runtime check
  ///
  /// In en, this message translates to:
  /// **'Apply this proposal?'**
  String get aiLlmRuntimeProposalConfirmTitle;

  /// Confirm dialog body before applying a ready proposal returned by the FRB-backed runtime check.
  ///
  /// In en, this message translates to:
  /// **'{summary}\n\nConfirm to save this change in the same way as the AI assistant.'**
  String aiLlmRuntimeProposalConfirmBody(String summary);

  /// Toast shown after a ready proposal returned by the FRB-backed runtime check is applied.
  ///
  /// In en, this message translates to:
  /// **'Proposal apply finished: {status}'**
  String aiLlmRuntimeProposalApplied(String status);

  /// Inline status shown after applying a ready proposal returned by the FRB-backed runtime check.
  ///
  /// In en, this message translates to:
  /// **'Proposal apply: {status}'**
  String aiLlmRuntimeProposalStatus(String status);

  /// Status text and toast shown when applying a ready proposal returned by the FRB-backed runtime check fails.
  ///
  /// In en, this message translates to:
  /// **'Proposal apply failed: {error}'**
  String aiLlmRuntimeProposalFailed(String error);

  /// Compact trailing pill on a settings link row indicating the value is auto-tuned by another preference (e.g. risk appetite). Renders uppercase.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsBadgeAuto;

  /// Compact trailing pill on a settings link row indicating the value has been hand-customised. Renders uppercase.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsBadgeCustom;

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

  /// Settings tile and page title for notification preferences
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsTitle;

  /// Settings tile subtitle for notification preferences
  ///
  /// In en, this message translates to:
  /// **'Permissions, agent reminders, and HealthOS briefing alerts'**
  String get settingsNotificationsSubtitle;

  /// Master app-level notification preference label
  ///
  /// In en, this message translates to:
  /// **'Allow app notifications'**
  String get settingsNotificationsMasterTitle;

  /// Master app-level notification preference subtitle
  ///
  /// In en, this message translates to:
  /// **'Controls local agent notifications and background reminder jobs.'**
  String get settingsNotificationsMasterSubtitle;

  /// Notification settings permission status while loading
  ///
  /// In en, this message translates to:
  /// **'Checking system notification permission…'**
  String get settingsNotificationsPermissionChecking;

  /// Notification settings permission status when OS permission is granted
  ///
  /// In en, this message translates to:
  /// **'System notifications are allowed.'**
  String get settingsNotificationsPermissionGranted;

  /// Notification settings permission status when OS permission is denied
  ///
  /// In en, this message translates to:
  /// **'System notifications are off for NaviWealth.'**
  String get settingsNotificationsPermissionDenied;

  /// Notification settings permission status when local notifications are unsupported
  ///
  /// In en, this message translates to:
  /// **'Notifications are not available on this platform.'**
  String get settingsNotificationsPermissionUnavailable;

  /// Notification settings permission load error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read notification permission: {error}'**
  String settingsNotificationsPermissionFailed(String error);

  /// Button label requesting OS notification permission
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get settingsNotificationsPermissionRequest;

  /// Button label while requesting OS notification permission
  ///
  /// In en, this message translates to:
  /// **'Enabling…'**
  String get settingsNotificationsPermissionRequesting;

  /// Settings switch row label for Face ID / fingerprint app unlock
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get settingsBiometricTitle;

  /// Settings switch row subtitle for biometric unlock when available
  ///
  /// In en, this message translates to:
  /// **'Require Face ID or fingerprint when NaviWealth opens.'**
  String get settingsBiometricSubtitle;

  /// Settings biometric row subtitle while checking device support or authenticating
  ///
  /// In en, this message translates to:
  /// **'Checking biometric availability…'**
  String get settingsBiometricChecking;

  /// Settings biometric row subtitle when the current platform/device is unsupported
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not available on this device.'**
  String get settingsBiometricUnavailable;

  /// Settings biometric row subtitle when the device supports biometrics but no biometric is enrolled
  ///
  /// In en, this message translates to:
  /// **'Set up Face ID or fingerprint on this device first.'**
  String get settingsBiometricNotEnrolled;

  /// Title on the biometric app lock screen
  ///
  /// In en, this message translates to:
  /// **'NaviWealth is locked'**
  String get biometricUnlockTitle;

  /// Subtitle on the biometric app lock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock with your device biometric to continue.'**
  String get biometricUnlockSubtitle;

  /// Button on the biometric app lock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get biometricUnlockButton;

  /// Button label while biometric authentication is in progress
  ///
  /// In en, this message translates to:
  /// **'Unlocking…'**
  String get biometricUnlockChecking;

  /// Toast shown when biometric authentication is cancelled or fails
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock failed.'**
  String get biometricUnlockFailed;

  /// System biometric prompt reason string
  ///
  /// In en, this message translates to:
  /// **'Unlock NaviWealth'**
  String get biometricUnlockReason;

  /// Settings switch row label for opt-in anonymous crash + error telemetry
  ///
  /// In en, this message translates to:
  /// **'Crash reporting'**
  String get settingsCrashReportingTitle;

  /// Settings switch row subtitle clarifying the opt-in default and what gets sent
  ///
  /// In en, this message translates to:
  /// **'Send anonymous error reports to help fix bugs. Off by default.'**
  String get settingsCrashReportingSubtitle;

  /// Settings tile that opens the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'AI privacy'**
  String get settingsAiPrivacyTitle;

  /// Settings tile subtitle for the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'Control what is sent to your model provider'**
  String get settingsAiPrivacySubtitle;

  /// Title of the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'AI privacy'**
  String get aiPrivacyTitle;

  /// Intro copy on the AI privacy page
  ///
  /// In en, this message translates to:
  /// **'Choose how much data can be sent when you use a cloud model. You can change this at any time.'**
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

  /// Toast shown after copying app logs to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Logs copied'**
  String get settingsLogsCopiedToast;

  /// Header action that copies all diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Copy all logs'**
  String get settingsLogsCopyAction;

  /// Header action that shares all diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Share all logs'**
  String get settingsLogsShareAction;

  /// Confirmation title before clearing diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Clear logs?'**
  String get settingsLogsClearTitle;

  /// Confirmation body before clearing diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'This removes the in-memory diagnostic log history from this device.'**
  String get settingsLogsClearBody;

  /// Destructive action label for clearing diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get settingsLogsClearAction;

  /// Settings developer diagnostics: performance page title
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsPerfTitle;

  /// Settings developer diagnostics: performance page subtitle
  ///
  /// In en, this message translates to:
  /// **'Inspect recent frame timing and jank'**
  String get settingsPerfSubtitle;

  /// Performance diagnostics label for sampled frames
  ///
  /// In en, this message translates to:
  /// **'Recent frames'**
  String get settingsPerfRecentFrames;

  /// Performance diagnostics label for janky frame count
  ///
  /// In en, this message translates to:
  /// **'Jank frames'**
  String get settingsPerfJankFrames;

  /// Performance diagnostics label for target frame budget
  ///
  /// In en, this message translates to:
  /// **'Frame budget'**
  String get settingsPerfFrameBudget;

  /// Performance diagnostics timing section title
  ///
  /// In en, this message translates to:
  /// **'Frame timing'**
  String get settingsPerfTimingTitle;

  /// No description provided for @settingsPerfTotalP50.
  ///
  /// In en, this message translates to:
  /// **'Total p50'**
  String get settingsPerfTotalP50;

  /// No description provided for @settingsPerfTotalP95.
  ///
  /// In en, this message translates to:
  /// **'Total p95'**
  String get settingsPerfTotalP95;

  /// No description provided for @settingsPerfBuildP95.
  ///
  /// In en, this message translates to:
  /// **'Build p95'**
  String get settingsPerfBuildP95;

  /// No description provided for @settingsPerfRasterP95.
  ///
  /// In en, this message translates to:
  /// **'Raster p95'**
  String get settingsPerfRasterP95;

  /// Accessibility label for copying the privacy-safe performance report
  ///
  /// In en, this message translates to:
  /// **'Copy performance evidence'**
  String get settingsPerfCopyEvidence;

  /// Toast after copying the privacy-safe performance report
  ///
  /// In en, this message translates to:
  /// **'Performance evidence copied'**
  String get settingsPerfEvidenceCopied;

  /// No description provided for @settingsDomainsHealthEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI tools and Memory indexing are enabled'**
  String get settingsDomainsHealthEnabledSubtitle;

  /// No description provided for @settingsDomainsHealthDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on AI tools and Memory indexing'**
  String get settingsDomainsHealthDisabledSubtitle;

  /// No description provided for @settingsDomainsHealthTodaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View recovery, metrics, and health trends'**
  String get settingsDomainsHealthTodaySubtitle;

  /// No description provided for @settingsDomainsKnowledgeEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox, Library, Review, AI tools, and Memory indexing are enabled'**
  String get settingsDomainsKnowledgeEnabledSubtitle;

  /// No description provided for @settingsDomainsKnowledgeDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personal decisions and cognitive memory'**
  String get settingsDomainsKnowledgeDisabledSubtitle;

  /// No description provided for @settingsDomainsKnowledgeInboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture notes, write decisions, and review the library'**
  String get settingsDomainsKnowledgeInboxSubtitle;

  /// No description provided for @settingsDomainsKnowledgeLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse decisions, assumptions, routines, concepts, and notes'**
  String get settingsDomainsKnowledgeLibrarySubtitle;

  /// No description provided for @settingsDomainsKnowledgeReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review due decisions, stale assumptions, and due routines'**
  String get settingsDomainsKnowledgeReviewSubtitle;

  /// No description provided for @settingsDomainsKnowledgeMemoryTitle.
  ///
  /// In en, this message translates to:
  /// **'KnowledgeOS Memory'**
  String get settingsDomainsKnowledgeMemoryTitle;

  /// No description provided for @settingsDomainsKnowledgeMemorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage the local model used for recall, dedupe, and semantic search'**
  String get settingsDomainsKnowledgeMemorySubtitle;

  /// No description provided for @settingsDomainsHealthPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied — try again in system Health settings'**
  String get settingsDomainsHealthPermissionDenied;

  /// No description provided for @settingsDomainsHealthSyncRunning.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get settingsDomainsHealthSyncRunning;

  /// No description provided for @settingsDomainsHealthSyncIdle.
  ///
  /// In en, this message translates to:
  /// **'Import the last 30 days from the system health platform'**
  String get settingsDomainsHealthSyncIdle;

  /// No description provided for @settingsDomainsHealthSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Last sync failed'**
  String get settingsDomainsHealthSyncFailed;

  /// No description provided for @settingsDomainsHealthSyncSummary.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {upserted} new / {unchanged} unchanged · fetched {total} items'**
  String settingsDomainsHealthSyncSummary(
    int upserted,
    int unchanged,
    int total,
  );

  /// No description provided for @settingsDomainsHealthSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync health data'**
  String get settingsDomainsHealthSyncTitle;

  /// No description provided for @settingsAiModelsCheckingRuntime.
  ///
  /// In en, this message translates to:
  /// **'Checking the embedder path for next launch…'**
  String get settingsAiModelsCheckingRuntime;

  /// No description provided for @settingsAiModelsRuntimeCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Embedder path check failed: {error}'**
  String settingsAiModelsRuntimeCheckFailed(String error);

  /// No description provided for @settingsAiModelsRuntimeReady.
  ///
  /// In en, this message translates to:
  /// **'Next launch will load Rust EmbeddingGemma'**
  String get settingsAiModelsRuntimeReady;

  /// No description provided for @settingsAiModelsRuntimeStub.
  ///
  /// In en, this message translates to:
  /// **'Next launch will still use the stub embedder'**
  String get settingsAiModelsRuntimeStub;

  /// No description provided for @settingsAiModelsModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsAiModelsModelLabel;

  /// No description provided for @settingsAiModelsModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing: EmbeddingGemma model dir'**
  String get settingsAiModelsModelMissing;

  /// No description provided for @settingsAiModelsOrtMissing.
  ///
  /// In en, this message translates to:
  /// **'ONNX Runtime library missing'**
  String get settingsAiModelsOrtMissing;

  /// No description provided for @settingsAiModelsNativeLibLabel.
  ///
  /// In en, this message translates to:
  /// **'native lib'**
  String get settingsAiModelsNativeLibLabel;

  /// No description provided for @settingsAiModelsNativeLibPlatform.
  ///
  /// In en, this message translates to:
  /// **'Loaded by the platform plugin'**
  String get settingsAiModelsNativeLibPlatform;

  /// No description provided for @settingsAiModelsInstalledSource.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get settingsAiModelsInstalledSource;

  /// No description provided for @settingsAiModelsMissingSource.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get settingsAiModelsMissingSource;

  /// No description provided for @settingsAiModelsHint.
  ///
  /// In en, this message translates to:
  /// **'Model files stay on this device and are never uploaded. EmbeddingGemma powers local memory retrieval; Zipformer powers real-time Mandarin voice input. ONNX Runtime is bundled with the app.'**
  String get settingsAiModelsHint;

  /// No description provided for @settingsAiModelsSpeechEngineTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition engine'**
  String get settingsAiModelsSpeechEngineTitle;

  /// No description provided for @settingsAiModelsSpeechEngineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System on-device recognition is the safe default. Zipformer keeps audio local and needs its model bundle.'**
  String get settingsAiModelsSpeechEngineSubtitle;

  /// No description provided for @settingsAiModelsSpeechEngineLocalOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'This platform currently uses local Zipformer recognition and needs its model bundle.'**
  String get settingsAiModelsSpeechEngineLocalOnlySubtitle;

  /// No description provided for @settingsAiModelsSpeechEngineSystem.
  ///
  /// In en, this message translates to:
  /// **'System on-device'**
  String get settingsAiModelsSpeechEngineSystem;

  /// No description provided for @settingsAiModelsSpeechEngineZipformer.
  ///
  /// In en, this message translates to:
  /// **'Local Zipformer'**
  String get settingsAiModelsSpeechEngineZipformer;

  /// No description provided for @settingsAiModelsSpeechEngineZipformerMissing.
  ///
  /// In en, this message translates to:
  /// **'Download the Zipformer bundle below before using local recognition.'**
  String get settingsAiModelsSpeechEngineZipformerMissing;

  /// No description provided for @settingsAiModelsFootnote.
  ///
  /// In en, this message translates to:
  /// **'The speech model is available on the next microphone tap. After downloading EmbeddingGemma, restart the app; existing memories are re-indexed in the next cycle and original records remain unchanged.'**
  String get settingsAiModelsFootnote;

  /// No description provided for @settingsAiModelsStateLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load state: {error}'**
  String settingsAiModelsStateLoadFailed(String error);

  /// No description provided for @settingsAiModelsStatusInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get settingsAiModelsStatusInstalled;

  /// No description provided for @settingsAiModelsStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get settingsAiModelsStatusDownloading;

  /// No description provided for @settingsAiModelsStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsAiModelsStatusFailed;

  /// No description provided for @settingsAiModelsStatusNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get settingsAiModelsStatusNotInstalled;

  /// No description provided for @settingsAiModelsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsAiModelsCancel;

  /// No description provided for @settingsAiModelsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsAiModelsDelete;

  /// No description provided for @settingsAiModelsRedownload.
  ///
  /// In en, this message translates to:
  /// **'Redownload'**
  String get settingsAiModelsRedownload;

  /// No description provided for @settingsAiModelsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get settingsAiModelsDownload;

  /// No description provided for @settingsAiModelsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete model?'**
  String get settingsAiModelsDeleteTitle;

  /// No description provided for @settingsAiModelsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'After deletion, the corresponding on-device capability becomes unavailable or falls back to its lightweight implementation. Re-enabling it requires another download.'**
  String get settingsAiModelsDeleteBody;

  /// No description provided for @settingsAiModelsActiveRuntimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Running embedder'**
  String get settingsAiModelsActiveRuntimeTitle;

  /// No description provided for @settingsAiModelsActiveRuntimeLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking the active embedder…'**
  String get settingsAiModelsActiveRuntimeLoading;

  /// No description provided for @settingsAiModelsActiveRuntimeFailed.
  ///
  /// In en, this message translates to:
  /// **'Active embedder check failed: {error}'**
  String settingsAiModelsActiveRuntimeFailed(String error);

  /// No description provided for @settingsAiModelsActiveRuntimeNative.
  ///
  /// In en, this message translates to:
  /// **'On-device'**
  String get settingsAiModelsActiveRuntimeNative;

  /// No description provided for @settingsAiModelsActiveRuntimeStub.
  ///
  /// In en, this message translates to:
  /// **'Simulation'**
  String get settingsAiModelsActiveRuntimeStub;

  /// No description provided for @settingsAiModelsActiveRuntimeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsAiModelsActiveRuntimeUnknown;

  /// No description provided for @settingsAiModelsFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Model fingerprint'**
  String get settingsAiModelsFingerprintLabel;

  /// No description provided for @settingsAiModelsDimensionLabel.
  ///
  /// In en, this message translates to:
  /// **'dimension'**
  String get settingsAiModelsDimensionLabel;

  /// No description provided for @settingsAiModelsMemoryRowsLabel.
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get settingsAiModelsMemoryRowsLabel;

  /// No description provided for @settingsAiModelsVectorRowsLabel.
  ///
  /// In en, this message translates to:
  /// **'Vectors'**
  String get settingsAiModelsVectorRowsLabel;

  /// No description provided for @settingsAiModelsCurrentVectorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get settingsAiModelsCurrentVectorsLabel;

  /// No description provided for @settingsAiModelsStaleVectorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get settingsAiModelsStaleVectorsLabel;

  /// No description provided for @settingsAiModelsEventsLabel.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get settingsAiModelsEventsLabel;

  /// No description provided for @settingsAiModelsSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Indexed sources'**
  String get settingsAiModelsSourcesTitle;

  /// No description provided for @settingsAiModelsNoSources.
  ///
  /// In en, this message translates to:
  /// **'No memory sources indexed yet.'**
  String get settingsAiModelsNoSources;

  /// No description provided for @settingsAiModelsStaleVectorsHint.
  ///
  /// In en, this message translates to:
  /// **'Some vectors were created by a different embedder fingerprint. They will be refreshed by the next indexer cycle.'**
  String get settingsAiModelsStaleVectorsHint;

  /// No description provided for @knowledgeAiSuggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI suggestions'**
  String get knowledgeAiSuggestionsTitle;

  /// No description provided for @knowledgeAiSuggestionsTitleWithCount.
  ///
  /// In en, this message translates to:
  /// **'AI suggestions ({count})'**
  String knowledgeAiSuggestionsTitleWithCount(int count);

  /// No description provided for @knowledgeAiSuggestionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} background organization suggestions, ready for your review.'**
  String knowledgeAiSuggestionsSubtitle(Object count);

  /// No description provided for @knowledgeAiSuggestionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No organization suggestions are waiting.'**
  String get knowledgeAiSuggestionsEmpty;

  /// No description provided for @knowledgeAiSuggestionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String knowledgeAiSuggestionCount(Object count);

  /// No description provided for @knowledgeAiSuggestionKindClassification.
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get knowledgeAiSuggestionKindClassification;

  /// No description provided for @knowledgeAiSuggestionKindTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get knowledgeAiSuggestionKindTags;

  /// No description provided for @knowledgeAiSuggestionKindLinkToDecision.
  ///
  /// In en, this message translates to:
  /// **'Decision link'**
  String get knowledgeAiSuggestionKindLinkToDecision;

  /// No description provided for @knowledgeAiSuggestionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get knowledgeAiSuggestionDetails;

  /// No description provided for @knowledgeAiSuggestionHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get knowledgeAiSuggestionHideDetails;

  /// No description provided for @knowledgeAiSuggestionAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept suggestion'**
  String get knowledgeAiSuggestionAccept;

  /// No description provided for @knowledgeAiSuggestionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss suggestion'**
  String get knowledgeAiSuggestionDismiss;

  /// No description provided for @knowledgeAiSuggestionPayloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested fields'**
  String get knowledgeAiSuggestionPayloadTitle;

  /// No description provided for @knowledgeAiSuggestionSnoozeOneDay.
  ///
  /// In en, this message translates to:
  /// **'Remind tomorrow'**
  String get knowledgeAiSuggestionSnoozeOneDay;

  /// No description provided for @knowledgeAiSuggestionSnoozedToast.
  ///
  /// In en, this message translates to:
  /// **'Suggestion will return tomorrow.'**
  String get knowledgeAiSuggestionSnoozedToast;

  /// No description provided for @knowledgeAiSuggestionAppliedToast.
  ///
  /// In en, this message translates to:
  /// **'Suggestion applied to the note.'**
  String get knowledgeAiSuggestionAppliedToast;

  /// No description provided for @knowledgeAiSuggestionViewAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get knowledgeAiSuggestionViewAction;

  /// No description provided for @knowledgeAiSuggestionDismissedToast.
  ///
  /// In en, this message translates to:
  /// **'Suggestion dismissed.'**
  String get knowledgeAiSuggestionDismissedToast;

  /// No description provided for @knowledgeAiSuggestionFeedbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Was this suggestion useful?'**
  String get knowledgeAiSuggestionFeedbackLabel;

  /// No description provided for @knowledgeAiSuggestionFeedbackGood.
  ///
  /// In en, this message translates to:
  /// **'Useful'**
  String get knowledgeAiSuggestionFeedbackGood;

  /// No description provided for @knowledgeAiSuggestionFeedbackBad.
  ///
  /// In en, this message translates to:
  /// **'Not useful'**
  String get knowledgeAiSuggestionFeedbackBad;

  /// No description provided for @knowledgeAiSuggestionFeedbackToast.
  ///
  /// In en, this message translates to:
  /// **'Feedback saved.'**
  String get knowledgeAiSuggestionFeedbackToast;

  /// No description provided for @knowledgeAiSuggestionMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get knowledgeAiSuggestionMoreActions;

  /// No description provided for @knowledgeAiSuggestionClassificationSummary.
  ///
  /// In en, this message translates to:
  /// **'Organize as {kind}'**
  String knowledgeAiSuggestionClassificationSummary(String kind);

  /// No description provided for @knowledgeAiSuggestionTagsSummary.
  ///
  /// In en, this message translates to:
  /// **'Add tags: {tags}'**
  String knowledgeAiSuggestionTagsSummary(String tags);

  /// No description provided for @knowledgeAiSuggestionDecisionLinksSummary.
  ///
  /// In en, this message translates to:
  /// **'Link to {count} related decisions'**
  String knowledgeAiSuggestionDecisionLinksSummary(int count);

  /// No description provided for @knowledgeAiSuggestionFieldTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get knowledgeAiSuggestionFieldTags;

  /// No description provided for @knowledgeAiSuggestionFieldDecisions.
  ///
  /// In en, this message translates to:
  /// **'Related decisions'**
  String get knowledgeAiSuggestionFieldDecisions;

  /// No description provided for @knowledgeAgentAssumptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Assumptions to verify this month'**
  String get knowledgeAgentAssumptionTitle;

  /// No description provided for @knowledgeAgentAssumptionNoStale.
  ///
  /// In en, this message translates to:
  /// **'No stale active assumptions.'**
  String get knowledgeAgentAssumptionNoStale;

  /// No description provided for @knowledgeAgentAssumptionSummaryOne.
  ///
  /// In en, this message translates to:
  /// **'1 active assumption has not been verified for more than {days} days: {first}'**
  String knowledgeAgentAssumptionSummaryOne(Object days, Object first);

  /// No description provided for @knowledgeAgentAssumptionSummaryMany.
  ///
  /// In en, this message translates to:
  /// **'{count} active assumptions have not been verified for more than {days} days. First: {first}'**
  String knowledgeAgentAssumptionSummaryMany(
    Object count,
    Object days,
    Object first,
  );

  /// No description provided for @knowledgeAgentReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly review'**
  String get knowledgeAgentReviewTitle;

  /// No description provided for @knowledgeAgentReviewNothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due for review this week.'**
  String get knowledgeAgentReviewNothingDue;

  /// No description provided for @knowledgeAgentReviewDecisionOne.
  ///
  /// In en, this message translates to:
  /// **'1 decision is due for review: {first}'**
  String knowledgeAgentReviewDecisionOne(Object first);

  /// No description provided for @knowledgeAgentReviewDecisionMany.
  ///
  /// In en, this message translates to:
  /// **'{count} decisions are due for review. First: {first}'**
  String knowledgeAgentReviewDecisionMany(Object count, Object first);

  /// No description provided for @knowledgeAgentReviewAssumptionOne.
  ///
  /// In en, this message translates to:
  /// **'1 assumption has not been verified for more than {days} days: {first}'**
  String knowledgeAgentReviewAssumptionOne(Object days, Object first);

  /// No description provided for @knowledgeAgentReviewAssumptionMany.
  ///
  /// In en, this message translates to:
  /// **'{count} assumptions have not been verified for more than {days} days. First: {first}'**
  String knowledgeAgentReviewAssumptionMany(
    Object count,
    Object days,
    Object first,
  );

  /// No description provided for @knowledgeAgentContradictionTitle.
  ///
  /// In en, this message translates to:
  /// **'Decision conflicts detected'**
  String get knowledgeAgentContradictionTitle;

  /// No description provided for @knowledgeAgentContradictionNone.
  ///
  /// In en, this message translates to:
  /// **'No contradictions detected in the last 90-day window.'**
  String get knowledgeAgentContradictionNone;

  /// No description provided for @knowledgeAgentContradictionInvalidatedAssumption.
  ///
  /// In en, this message translates to:
  /// **'This decision still references assumption {assumptionId}, but that assumption is no longer active (possibly falsified or retired).'**
  String knowledgeAgentContradictionInvalidatedAssumption(Object assumptionId);

  /// No description provided for @knowledgeAgentContradictionSummaryOne.
  ///
  /// In en, this message translates to:
  /// **'Detected 1 {kind} issue: {detail}'**
  String knowledgeAgentContradictionSummaryOne(Object detail, Object kind);

  /// No description provided for @knowledgeAgentContradictionSummaryMany.
  ///
  /// In en, this message translates to:
  /// **'Detected {count} conflicts. First: {kind} → {detail}'**
  String knowledgeAgentContradictionSummaryMany(
    Object count,
    Object detail,
    Object kind,
  );

  /// No description provided for @knowledgeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String knowledgeLoadFailed(String error);

  /// No description provided for @knowledgeNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note {noteId} was deleted'**
  String knowledgeNoteDeleted(String noteId);

  /// No description provided for @knowledgeUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get knowledgeUntitled;

  /// No description provided for @knowledgeMarkdownEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get knowledgeMarkdownEdit;

  /// No description provided for @knowledgeMarkdownPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get knowledgeMarkdownPreview;

  /// No description provided for @knowledgeMarkdownPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No preview yet. Switch back to edit mode to enter content.'**
  String get knowledgeMarkdownPreviewEmpty;

  /// No description provided for @knowledgeMarkdownBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get knowledgeMarkdownBold;

  /// No description provided for @knowledgeMarkdownLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get knowledgeMarkdownLink;

  /// No description provided for @knowledgeMarkdownBulletedList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get knowledgeMarkdownBulletedList;

  /// No description provided for @knowledgeMarkdownQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get knowledgeMarkdownQuote;

  /// No description provided for @knowledgeMarkdownInlineCode.
  ///
  /// In en, this message translates to:
  /// **'Inline code'**
  String get knowledgeMarkdownInlineCode;

  /// No description provided for @knowledgeMarkdownTableLabel.
  ///
  /// In en, this message translates to:
  /// **'Table, {rows} rows and {columns} columns'**
  String knowledgeMarkdownTableLabel(int rows, int columns);

  /// No description provided for @knowledgeMarkdownImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Image: {description}'**
  String knowledgeMarkdownImageLabel(String description);

  /// No description provided for @knowledgeDecisionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Decision does not exist or was deleted'**
  String get knowledgeDecisionNotFound;

  /// No description provided for @knowledgeDecisionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Decision details'**
  String get knowledgeDecisionDetailTitle;

  /// No description provided for @knowledgeDecisionActionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Turn this decision into one concrete next step.'**
  String get knowledgeDecisionActionPrompt;

  /// No description provided for @knowledgeActionLinked.
  ///
  /// In en, this message translates to:
  /// **'A follow-up action is already linked.'**
  String get knowledgeActionLinked;

  /// No description provided for @knowledgeActionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create action'**
  String get knowledgeActionCreate;

  /// No description provided for @knowledgeActionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open action'**
  String get knowledgeActionOpen;

  /// No description provided for @knowledgeActionCreated.
  ///
  /// In en, this message translates to:
  /// **'Follow-up action created'**
  String get knowledgeActionCreated;

  /// No description provided for @knowledgeActionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Enable ExecutionOS to create a follow-up action.'**
  String get knowledgeActionUnavailable;

  /// No description provided for @knowledgeActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the action: {error}'**
  String knowledgeActionFailed(String error);

  /// No description provided for @knowledgeNoteActionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Turn this note into one concrete follow-up.'**
  String get knowledgeNoteActionPrompt;

  /// No description provided for @knowledgeNoteActionDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow up: {note}'**
  String knowledgeNoteActionDraftTitle(String note);

  /// No description provided for @knowledgeExperimentActionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Turn this experiment into its next concrete step.'**
  String get knowledgeExperimentActionPrompt;

  /// No description provided for @knowledgeExperimentActionDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Run experiment: {experiment}'**
  String knowledgeExperimentActionDraftTitle(String experiment);

  /// No description provided for @knowledgeDecisionActionDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow up: {decision}'**
  String knowledgeDecisionActionDraftTitle(String decision);

  /// No description provided for @knowledgeDecisionActionDraftNote.
  ///
  /// In en, this message translates to:
  /// **'Decision: {choice}'**
  String knowledgeDecisionActionDraftNote(String choice);

  /// No description provided for @knowledgeDecisionDecidedAt.
  ///
  /// In en, this message translates to:
  /// **'Decided on {date}'**
  String knowledgeDecisionDecidedAt(Object date);

  /// No description provided for @knowledgeDecisionDecidedAtWithReview.
  ///
  /// In en, this message translates to:
  /// **'Decided on {decidedDate} · Review {reviewDate}'**
  String knowledgeDecisionDecidedAtWithReview(
    Object decidedDate,
    Object reviewDate,
  );

  /// No description provided for @knowledgeNoteDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get knowledgeNoteDetailTitle;

  /// No description provided for @knowledgeNoteEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get knowledgeNoteEditTitle;

  /// No description provided for @knowledgeNoteEditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update title, content, and metadata.'**
  String get knowledgeNoteEditSubtitle;

  /// No description provided for @knowledgeNoteSourceUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Source URL'**
  String get knowledgeNoteSourceUrlLabel;

  /// No description provided for @knowledgeNoteTagsHint.
  ///
  /// In en, this message translates to:
  /// **'\"investing\", \"fire\", \"banking\"'**
  String get knowledgeNoteTagsHint;

  /// No description provided for @knowledgeNoteProjectHint.
  ///
  /// In en, this message translates to:
  /// **'\"fire-plan\", \"health-2026\"'**
  String get knowledgeNoteProjectHint;

  /// No description provided for @knowledgeConceptDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Concept'**
  String get knowledgeConceptDetailTitle;

  /// No description provided for @knowledgeExperimentDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Experiment'**
  String get knowledgeExperimentDetailTitle;

  /// No description provided for @knowledgePrincipleDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Principle'**
  String get knowledgePrincipleDetailTitle;

  /// No description provided for @knowledgeAssumptionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Assumption'**
  String get knowledgeAssumptionDetailTitle;

  /// No description provided for @knowledgeRoutineDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get knowledgeRoutineDetailTitle;

  /// No description provided for @knowledgeObjectDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get knowledgeObjectDetailTitle;

  /// No description provided for @knowledgeDetailOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get knowledgeDetailOptionsTitle;

  /// No description provided for @knowledgeDetailMetadataTitle.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get knowledgeDetailMetadataTitle;

  /// No description provided for @knowledgeDetailRationaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Rationale'**
  String get knowledgeDetailRationaleTitle;

  /// No description provided for @knowledgeDetailPrinciplesTitle.
  ///
  /// In en, this message translates to:
  /// **'Referenced principles'**
  String get knowledgeDetailPrinciplesTitle;

  /// No description provided for @knowledgeDetailAssumptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Referenced assumptions'**
  String get knowledgeDetailAssumptionsTitle;

  /// No description provided for @knowledgeDetailActualOutcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Actual outcome'**
  String get knowledgeDetailActualOutcomeTitle;

  /// No description provided for @knowledgeDetailExpectedOutcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Expected outcome'**
  String get knowledgeDetailExpectedOutcomeTitle;

  /// No description provided for @knowledgeDetailMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get knowledgeDetailMetricsTitle;

  /// No description provided for @knowledgeDetailEvolutionTitle.
  ///
  /// In en, this message translates to:
  /// **'Cognitive trail'**
  String get knowledgeDetailEvolutionTitle;

  /// No description provided for @knowledgeDetailSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get knowledgeDetailSummaryTitle;

  /// No description provided for @knowledgeDetailRelatedConceptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Related concepts'**
  String get knowledgeDetailRelatedConceptsTitle;

  /// No description provided for @knowledgeDetailMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get knowledgeDetailMethodTitle;

  /// No description provided for @knowledgeDetailResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get knowledgeDetailResultTitle;

  /// No description provided for @knowledgeDetailConclusionTitle.
  ///
  /// In en, this message translates to:
  /// **'Conclusion'**
  String get knowledgeDetailConclusionTitle;

  /// No description provided for @knowledgeDetailEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get knowledgeDetailEvidenceTitle;

  /// No description provided for @knowledgeDetailBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get knowledgeDetailBodyTitle;

  /// No description provided for @knowledgeDetailSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get knowledgeDetailSourceTitle;

  /// No description provided for @knowledgeSourceOpenConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Open source link?'**
  String get knowledgeSourceOpenConfirmTitle;

  /// No description provided for @knowledgeSourceOpenConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll leave NaviWealth to open this external source. Confirm the destination.'**
  String get knowledgeSourceOpenConfirmBody;

  /// No description provided for @knowledgeSourceOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get knowledgeSourceOpenAction;

  /// No description provided for @knowledgeSourceOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the source link.'**
  String get knowledgeSourceOpenFailed;

  /// No description provided for @knowledgeSourceCopyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy source URL'**
  String get knowledgeSourceCopyAction;

  /// No description provided for @knowledgeDetailAliases.
  ///
  /// In en, this message translates to:
  /// **'Aliases: {aliases}'**
  String knowledgeDetailAliases(Object aliases);

  /// No description provided for @knowledgeDetailRelatedConceptCount.
  ///
  /// In en, this message translates to:
  /// **'{count} related'**
  String knowledgeDetailRelatedConceptCount(Object count);

  /// No description provided for @knowledgeDetailEvidenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} references'**
  String knowledgeDetailEvidenceCount(Object count);

  /// No description provided for @knowledgeDetailScope.
  ///
  /// In en, this message translates to:
  /// **'Scope: {scope}'**
  String knowledgeDetailScope(Object scope);

  /// No description provided for @knowledgeDetailConfidenceScope.
  ///
  /// In en, this message translates to:
  /// **'Confidence {confidence} · scope {scope}'**
  String knowledgeDetailConfidenceScope(Object confidence, Object scope);

  /// No description provided for @knowledgeDetailContextSnapshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Cross-domain state at the time'**
  String get knowledgeDetailContextSnapshotTitle;

  /// No description provided for @knowledgeDetailContextSnapshotCaptured.
  ///
  /// In en, this message translates to:
  /// **'Captured on {date} · {days}-day window'**
  String knowledgeDetailContextSnapshotCaptured(Object date, Object days);

  /// No description provided for @knowledgeDetailContextSnapshotEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cross-domain events in that window.'**
  String get knowledgeDetailContextSnapshotEmpty;

  /// No description provided for @knowledgeDetailContextSnapshotFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get knowledgeDetailContextSnapshotFinance;

  /// No description provided for @knowledgeDetailContextSnapshotHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get knowledgeDetailContextSnapshotHealth;

  /// No description provided for @knowledgeDetailCreatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get knowledgeDetailCreatedLabel;

  /// No description provided for @knowledgeDetailUpdatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get knowledgeDetailUpdatedLabel;

  /// No description provided for @knowledgeDetailUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String knowledgeDetailUpdatedAt(Object date);

  /// No description provided for @knowledgeDetailProjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get knowledgeDetailProjectLabel;

  /// No description provided for @knowledgeDetailTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get knowledgeDetailTagsLabel;

  /// No description provided for @knowledgeDetailAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get knowledgeDetailAliasesLabel;

  /// No description provided for @knowledgeDetailStartedLabel.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get knowledgeDetailStartedLabel;

  /// No description provided for @knowledgeDetailEndedLabel.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get knowledgeDetailEndedLabel;

  /// No description provided for @knowledgeDetailNextDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Next due'**
  String get knowledgeDetailNextDueLabel;

  /// No description provided for @knowledgeDetailLastDoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Last done'**
  String get knowledgeDetailLastDoneLabel;

  /// No description provided for @knowledgeDetailIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get knowledgeDetailIntervalLabel;

  /// No description provided for @knowledgeDetailTargetAssumptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Target assumption'**
  String get knowledgeDetailTargetAssumptionTitle;

  /// No description provided for @knowledgeDetailScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get knowledgeDetailScopeLabel;

  /// No description provided for @knowledgeDetailDeclaredLabel.
  ///
  /// In en, this message translates to:
  /// **'Declared'**
  String get knowledgeDetailDeclaredLabel;

  /// No description provided for @knowledgeDetailConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get knowledgeDetailConfidenceLabel;

  /// No description provided for @knowledgeDetailLastVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last verified'**
  String get knowledgeDetailLastVerifiedLabel;

  /// No description provided for @knowledgeDetailDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Related decisions'**
  String get knowledgeDetailDecisionsTitle;

  /// No description provided for @knowledgeDetailExperimentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Related experiments'**
  String get knowledgeDetailExperimentsTitle;

  /// No description provided for @knowledgeLibraryDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get knowledgeLibraryDeleteTooltip;

  /// No description provided for @knowledgeLibraryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete entry?'**
  String get knowledgeLibraryDeleteTitle;

  /// No description provided for @knowledgeLibraryDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be removed from Library and cleaned from AI memory after the next index sync.'**
  String knowledgeLibraryDeleteBody(Object title);

  /// No description provided for @knowledgeLibraryDeleteImpactBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" has {relationCount} relation(s), {referenceCount} inline reference(s), and {attachmentCount} attachment(s). Relations will be detached; referenced items and attachment files remain. You can undo this deletion.'**
  String knowledgeLibraryDeleteImpactBody(
    Object attachmentCount,
    Object referenceCount,
    Object relationCount,
    Object title,
  );

  /// No description provided for @knowledgeObjectNotFound.
  ///
  /// In en, this message translates to:
  /// **'Item does not exist or was deleted'**
  String get knowledgeObjectNotFound;

  /// No description provided for @knowledgeDeletedToast.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get knowledgeDeletedToast;

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

  /// Action that reverses the source and destination accounts on the transfer form
  ///
  /// In en, this message translates to:
  /// **'Swap accounts'**
  String get transferSwapAccountsAction;

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
  /// **'Date & time'**
  String get transferDateLabel;

  /// Transfer form: optional details disclosure title
  ///
  /// In en, this message translates to:
  /// **'Date & note'**
  String get transferDetailsTitle;

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

  /// Spending analysis page title
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get spendingTitle;

  /// Expense report: range chip — this month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get expenseReportRangeThisMonth;

  /// No description provided for @expenseReportRangeThisMonthCompact.
  ///
  /// In en, this message translates to:
  /// **'MTD'**
  String get expenseReportRangeThisMonthCompact;

  /// Expense report: range chip — last 3 months
  ///
  /// In en, this message translates to:
  /// **'Last 3 months'**
  String get expenseReportRangeLast3Months;

  /// No description provided for @expenseReportRange3mCompact.
  ///
  /// In en, this message translates to:
  /// **'3M'**
  String get expenseReportRange3mCompact;

  /// Expense report: range chip — last 6 months
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get expenseReportRangeLast6Months;

  /// No description provided for @expenseReportRange6mCompact.
  ///
  /// In en, this message translates to:
  /// **'6M'**
  String get expenseReportRange6mCompact;

  /// Expense report: range chip — last 12 months
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get expenseReportRangeLast12Months;

  /// No description provided for @expenseReportRange12mCompact.
  ///
  /// In en, this message translates to:
  /// **'12M'**
  String get expenseReportRange12mCompact;

  /// Expense report: range chip — custom
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get expenseReportRangeCustom;

  /// No description provided for @expenseReportRangeCustomCompact.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get expenseReportRangeCustomCompact;

  /// Expense report: summary card heading
  ///
  /// In en, this message translates to:
  /// **'Total expenses'**
  String get expenseReportTotalExpenses;

  /// Spending analysis: daily average metric label
  ///
  /// In en, this message translates to:
  /// **'Daily avg'**
  String get expenseReportDailyAverage;

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
  /// **'Base currency {currency} · {days} calendar days'**
  String expenseReportBaseCurrency(String currency, int days);

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

  /// Expense report: pie roll-up slice for remaining categories
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expenseReportOtherCategories;

  /// Expense report: subtitle for the Other roll-up row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 category} other{{count} categories}}'**
  String expenseReportOtherCategoryCount(int count);

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

  /// No description provided for @manualAssetDetailEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit asset'**
  String get manualAssetDetailEditAction;

  /// No description provided for @manualAssetDetailCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current value'**
  String get manualAssetDetailCurrentValue;

  /// No description provided for @manualAssetDetailAccount.
  ///
  /// In en, this message translates to:
  /// **'Held in'**
  String get manualAssetDetailAccount;

  /// No description provided for @manualAssetDetailPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get manualAssetDetailPrincipal;

  /// No description provided for @manualAssetDetailAnnualRate.
  ///
  /// In en, this message translates to:
  /// **'Annual rate'**
  String get manualAssetDetailAnnualRate;

  /// No description provided for @manualAssetDetailExpectedReturn.
  ///
  /// In en, this message translates to:
  /// **'Expected annual return'**
  String get manualAssetDetailExpectedReturn;

  /// No description provided for @manualAssetDetailStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get manualAssetDetailStartDate;

  /// No description provided for @manualAssetDetailMaturityDate.
  ///
  /// In en, this message translates to:
  /// **'Maturity date'**
  String get manualAssetDetailMaturityDate;

  /// No description provided for @manualAssetDetailIssuer.
  ///
  /// In en, this message translates to:
  /// **'Issuer'**
  String get manualAssetDetailIssuer;

  /// No description provided for @manualAssetDetailProductCode.
  ///
  /// In en, this message translates to:
  /// **'Product code'**
  String get manualAssetDetailProductCode;

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

  /// Asset detail hero: label above latest available close price
  ///
  /// In en, this message translates to:
  /// **'Latest close'**
  String get assetDetailLastClose;

  /// Asset detail: per-unit price used for current market-value calculation
  ///
  /// In en, this message translates to:
  /// **'Valuation price'**
  String get assetDetailValuationPrice;

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

  /// Deposit form: disclosure title for dates, valuation, and renewal settings
  ///
  /// In en, this message translates to:
  /// **'Dates & valuation'**
  String get depositDetailsTitle;

  /// Deposit form: term-deposit disclosure summary
  ///
  /// In en, this message translates to:
  /// **'Maturity, renewal & current value'**
  String get depositDetailsTermSummary;

  /// Deposit form: demand-deposit disclosure summary
  ///
  /// In en, this message translates to:
  /// **'Value date & current value'**
  String get depositDetailsDemandSummary;

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

  /// Wealth product form: optional details disclosure title
  ///
  /// In en, this message translates to:
  /// **'Product details'**
  String get wealthProductDetailsTitle;

  /// Wealth product form: optional details disclosure summary
  ///
  /// In en, this message translates to:
  /// **'Issuer, dates & current value'**
  String get wealthProductDetailsSummary;

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

  /// Symbol field: market selector label
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get localSecuritiesMarketLabel;

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
  /// **'Record entry'**
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

  /// Apply the activity filter draft
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get activityFeedFilterApply;

  /// Activity toolbar and filter option for no date restriction
  ///
  /// In en, this message translates to:
  /// **'All dates'**
  String get activityFeedFilterAllDates;

  /// Activity toolbar summary when no kind is selected
  ///
  /// In en, this message translates to:
  /// **'All kinds'**
  String get activityFeedFilterAllKinds;

  /// Activity toolbar summary for multiple selected kinds
  ///
  /// In en, this message translates to:
  /// **'{count} kinds'**
  String activityFeedFilterKindCount(int count);

  /// Activity toolbar summary for selected accounts
  ///
  /// In en, this message translates to:
  /// **'{count} accounts'**
  String activityFeedFilterAccountCount(int count);

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

  /// Section header for sync conflict diagnostics
  ///
  /// In en, this message translates to:
  /// **'Conflict diagnostics'**
  String get syncStatusConflictsHeader;

  /// Conflict diagnostics line for remote rows skipped by LWW because local state was newer or equal
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{No remote rows were blocked by local state} =1{1 remote row was older than local state} other{{n} remote rows were older than local state}}'**
  String syncStatusConflictsLocalWins(int n);

  /// Conflict diagnostics line for remote rows ignored due to unsupported namespaces, unknown prefixes, or unusable payloads
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 remote row was ignored because its namespace is not supported here} other{{n} remote rows were ignored because their namespace is not supported here}}'**
  String syncStatusConflictsIgnored(int n);

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

  /// Diagnostics row label for applied remote rows over total remote rows received in the last sync cycle
  ///
  /// In en, this message translates to:
  /// **'Remote rows'**
  String get syncStatusDetailRemoteRows;

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

  /// Sync rolling stability window currently meets its release thresholds.
  ///
  /// In en, this message translates to:
  /// **'Stability gate passed'**
  String get syncStabilityPassing;

  /// Sync rolling stability window has enough evidence but fails a threshold.
  ///
  /// In en, this message translates to:
  /// **'Sync stability needs attention'**
  String get syncStabilityFailing;

  /// Sync rolling stability window has not reached its sample and duration thresholds.
  ///
  /// In en, this message translates to:
  /// **'Collecting stability evidence'**
  String get syncStabilityCollecting;

  /// Summary of the local rolling Sync stability window.
  ///
  /// In en, this message translates to:
  /// **'{successful}/{total} successful · {days} days observed'**
  String syncStabilityWindow(int successful, int total, int days);

  /// Successful cycle rate in the Sync stability window.
  ///
  /// In en, this message translates to:
  /// **'Success {percent}%'**
  String syncStabilitySuccessRate(int percent);

  /// Fatal protocol error count in the Sync stability window.
  ///
  /// In en, this message translates to:
  /// **'Fatal {count}'**
  String syncStabilityFatal(int count);

  /// Domain generation reset failure count in the Sync stability window.
  ///
  /// In en, this message translates to:
  /// **'Reset failures {count}'**
  String syncStabilityResetFailures(int count);

  /// Failed Sync cycles followed by a successful cycle in the rolling window.
  ///
  /// In en, this message translates to:
  /// **'Recoveries {count}'**
  String syncStabilityRecoveries(int count);

  /// Explanation shown when the Sync stability gate passes.
  ///
  /// In en, this message translates to:
  /// **'All local release thresholds are currently met'**
  String get syncStabilityPassingDetail;

  /// Remaining terminal Sync cycles before the stability gate has enough evidence.
  ///
  /// In en, this message translates to:
  /// **'{count} more terminal cycles needed'**
  String syncStabilityNeedSamples(int count);

  /// Remaining observation days before the Sync stability gate has enough evidence.
  ///
  /// In en, this message translates to:
  /// **'{days} more observation days needed'**
  String syncStabilityNeedDuration(int days);

  /// Sync stability blocker when successful cycles are below the release threshold.
  ///
  /// In en, this message translates to:
  /// **'Needs at least {percent}% success'**
  String syncStabilityBelowSuccess(int percent);

  /// Sync stability blocker caused by fatal protocol errors.
  ///
  /// In en, this message translates to:
  /// **'Fatal protocol errors must return to zero'**
  String get syncStabilityFatalBlocker;

  /// Sync stability blocker caused by domain generation-reset failures.
  ///
  /// In en, this message translates to:
  /// **'Generation-reset failures must return to zero'**
  String get syncStabilityResetBlocker;

  /// Privacy note for the local Sync stability report.
  ///
  /// In en, this message translates to:
  /// **'Device-local aggregate · no row payloads or ids retained'**
  String get syncStabilityPrivacyNote;

  /// Copies the privacy-safe Sync stability report as JSON.
  ///
  /// In en, this message translates to:
  /// **'Copy evidence'**
  String get syncStabilityCopyEvidence;

  /// Toast after copying the Sync stability report.
  ///
  /// In en, this message translates to:
  /// **'Sync stability evidence copied.'**
  String get syncStabilityEvidenceCopied;

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

  /// Layer 4 ingest review page title
  ///
  /// In en, this message translates to:
  /// **'Review entries'**
  String get ingestReviewTitle;

  /// No description provided for @ingestCopyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy privacy-safe import diagnostics'**
  String get ingestCopyDiagnostics;

  /// No description provided for @ingestDiagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Import diagnostics copied'**
  String get ingestDiagnosticsCopied;

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

  /// Ingest review: source account for expenses or destination account for income
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get ingestExpenseAccountLabel;

  /// Ingest review: batch-confirm button (new drafts only)
  ///
  /// In en, this message translates to:
  /// **'Confirm all · new only ({count})'**
  String ingestConfirmAllFresh(int count);

  /// Ingest review: no account chosen warning
  ///
  /// In en, this message translates to:
  /// **'Pick a statement account first'**
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

  /// Import summary sheet: headline with recorded count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry recorded} other{{count} entries recorded}}'**
  String ingestSummaryTitle(num count);

  /// Import summary sheet: failed/needs-review line
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs review} other{{count} items need review}}'**
  String ingestSummaryFailures(num count);

  /// Import summary sheet: supporting body
  ///
  /// In en, this message translates to:
  /// **'Entries are in your activity feed and already reflected in balances.'**
  String get ingestSummaryBody;

  /// Import summary sheet: CTA to the activity feed
  ///
  /// In en, this message translates to:
  /// **'View activity'**
  String get ingestSummaryViewActivity;

  /// Agent results panel: loading title (all domains)
  ///
  /// In en, this message translates to:
  /// **'Assistant is checking in'**
  String get agentResultsLoadingTitle;

  /// Agent results panel: loading body
  ///
  /// In en, this message translates to:
  /// **'Fetching the latest agent results…'**
  String get agentResultsLoadingBody;

  /// Agent results panel: load error title
  ///
  /// In en, this message translates to:
  /// **'Agent results unavailable'**
  String get agentResultsErrorTitle;

  /// Agent results panel: empty title
  ///
  /// In en, this message translates to:
  /// **'No agent results yet'**
  String get agentResultsEmptyTitle;

  /// Agent results panel: empty body
  ///
  /// In en, this message translates to:
  /// **'Run the agent to get a fresh readout of this domain.'**
  String get agentResultsEmptyBody;

  /// Agent results panel: empty-state run CTA
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get agentResultsGenerateAction;

  /// Knowledge object status label
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get knowledgeStatusActive;

  /// Knowledge object status label
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get knowledgeStatusPaused;

  /// Knowledge object status label
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get knowledgeStatusRetired;

  /// Knowledge assumption status label
  ///
  /// In en, this message translates to:
  /// **'Weakened'**
  String get knowledgeStatusWeakened;

  /// Knowledge assumption status label
  ///
  /// In en, this message translates to:
  /// **'Falsified'**
  String get knowledgeStatusFalsified;

  /// Knowledge experiment status label
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get knowledgeStatusPlanned;

  /// Knowledge experiment status label
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get knowledgeStatusRunning;

  /// Knowledge experiment status label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get knowledgeStatusDone;

  /// Knowledge experiment status label
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get knowledgeStatusAbandoned;

  /// Knowledge routine status label
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get knowledgeStatusArchived;

  /// Ingest review: batch confirm success toast
  ///
  /// In en, this message translates to:
  /// **'Recorded {count}'**
  String ingestRecordedN(int count);

  /// Ingest review: partial batch confirm result
  ///
  /// In en, this message translates to:
  /// **'Recorded {success}; {failed} need attention'**
  String ingestRecordedPartial(int success, int failed);

  /// Ingest review: batch confirmation progress
  ///
  /// In en, this message translates to:
  /// **'Recording {completed} of {total} entries.'**
  String ingestRecordingProgress(int completed, int total);

  /// Ingest review: confirmation failure
  ///
  /// In en, this message translates to:
  /// **'Couldn’t record this entry. Try again.'**
  String get ingestRecordFailed;

  /// Ingest review: applied write needs lifecycle reconciliation
  ///
  /// In en, this message translates to:
  /// **'This entry may already be recorded. Resolve its review state before taking another action.'**
  String get ingestRecordNeedsReview;

  /// Ingest draft card: unsafe retry guard
  ///
  /// In en, this message translates to:
  /// **'This write may already exist in Activity. Resolve the review state instead of recording it again.'**
  String get ingestNeedsReviewHint;

  /// Ingest draft card: corrupt recovery fail-closed state
  ///
  /// In en, this message translates to:
  /// **'This entry may already exist in Activity, but its recovery details are unavailable. Recording it again is blocked.'**
  String get ingestRecoveryUnavailableHint;

  /// Ingest draft card: finalize an already-applied write
  ///
  /// In en, this message translates to:
  /// **'Resolve review state'**
  String get ingestResolveAction;

  /// Ingest review: reconciliation progress title
  ///
  /// In en, this message translates to:
  /// **'Resolving review state'**
  String get ingestResolvingTitle;

  /// Ingest review: reconciliation progress body
  ///
  /// In en, this message translates to:
  /// **'Finishing the review state without recording the entry again.'**
  String get ingestResolvingBody;

  /// Ingest review: reconciliation success
  ///
  /// In en, this message translates to:
  /// **'Review state resolved'**
  String get ingestResolveSucceeded;

  /// Ingest review: reconciliation failure
  ///
  /// In en, this message translates to:
  /// **'Couldn’t resolve the review state. Check Activity before trying again.'**
  String get ingestResolveFailed;

  /// Ingest review: dismiss success
  ///
  /// In en, this message translates to:
  /// **'Entry skipped'**
  String get ingestSkipped;

  /// Ingest review: dismiss failure
  ///
  /// In en, this message translates to:
  /// **'Couldn’t skip this entry. Try again.'**
  String get ingestSkipFailed;

  /// Ingest review: restore success
  ///
  /// In en, this message translates to:
  /// **'Entry restored'**
  String get ingestRestored;

  /// Ingest review: confirm undo success
  ///
  /// In en, this message translates to:
  /// **'Entry restored to review'**
  String get ingestUndoSucceeded;

  /// Ingest review: in-page title while undo is running
  ///
  /// In en, this message translates to:
  /// **'Restoring entries'**
  String get ingestUndoingTitle;

  /// Ingest review: undo failure or partial undo
  ///
  /// In en, this message translates to:
  /// **'Couldn’t undo every entry. Review the remaining records.'**
  String get ingestUndoFailed;

  /// Ingest review: batch undo progress
  ///
  /// In en, this message translates to:
  /// **'Restoring {completed} of {total} entries.'**
  String ingestUndoProgress(int completed, int total);

  /// Ingest paste dialog title
  ///
  /// In en, this message translates to:
  /// **'Paste statement text'**
  String get ingestPasteTitle;

  /// Ingest paste dialog text-field hint
  ///
  /// In en, this message translates to:
  /// **'Paste Alipay / WeChat Pay / bank CSV text\ne.g. 2026-05-10,Starbucks,-38.00,CNY'**
  String get ingestPasteHint;

  /// Ingest paste sheet: empty input validation
  ///
  /// In en, this message translates to:
  /// **'Paste statement text before parsing.'**
  String get ingestPasteRequired;

  /// Ingest review empty state: open the paste dialog
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get ingestEmptyPasteCta;

  /// Ingest paste dialog confirm button
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get ingestParseAction;

  /// Ingest review: parsing exception
  ///
  /// In en, this message translates to:
  /// **'Couldn’t parse this import. Try again.'**
  String get ingestParseFailed;

  /// Ingest review: camera/file capture exception
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read that source. Try again.'**
  String get ingestCaptureFailed;

  /// Ingest capture: unsupported file type
  ///
  /// In en, this message translates to:
  /// **'This file type isn’t supported.'**
  String get ingestCaptureUnsupported;

  /// Ingest capture: empty file or text
  ///
  /// In en, this message translates to:
  /// **'This source is empty.'**
  String get ingestCaptureEmpty;

  /// Ingest capture: file exceeds its memory budget
  ///
  /// In en, this message translates to:
  /// **'This file exceeds the {maxMiB} MiB import limit.'**
  String ingestCaptureTooLarge(int maxMiB);

  /// Ingest capture: direct or decoded text exceeds its budget
  ///
  /// In en, this message translates to:
  /// **'Text exceeds the {maxCharacters}-character import limit.'**
  String ingestCaptureTextTooLong(int maxCharacters);

  /// Ingest capture: source content is unavailable or changed while reading
  ///
  /// In en, this message translates to:
  /// **'This source couldn’t be read. Choose it again.'**
  String get ingestCaptureUnreadable;

  /// Ingest capture failure action: reopen file picker
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get ingestChooseAnotherFile;

  /// Ingest capture failure action: reopen camera
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get ingestRetakePhoto;

  /// Ingest drag and drop: aggregate rejected-file count
  ///
  /// In en, this message translates to:
  /// **'Couldn’t import {count} dropped files.'**
  String ingestDroppedSourcesRejected(int count);

  /// Shared ingest: recognized source was rejected by the parser
  ///
  /// In en, this message translates to:
  /// **'This shared source couldn’t be parsed.'**
  String get ingestSharedParseRejected;

  /// Shared ingest: unexpected processing failure
  ///
  /// In en, this message translates to:
  /// **'Something interrupted this shared import.'**
  String get ingestSharedParseFailed;

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

  /// Ingest review: parse summary when deterministic row diagnostics report skipped input rows
  ///
  /// In en, this message translates to:
  /// **'Parsed {total} · {fresh} new · {dup} possible dup · {skipped} skipped'**
  String ingestParseSummaryWithSkipped(
    int total,
    int fresh,
    int dup,
    int skipped,
  );

  /// Ingest review: in-page title while an import is being parsed
  ///
  /// In en, this message translates to:
  /// **'Parsing import'**
  String get ingestProcessingTitle;

  /// Ingest review: in-page status while an import source is being parsed
  ///
  /// In en, this message translates to:
  /// **'Reading {source}, extracting expenses, and checking duplicates against your ledger and pending imports.'**
  String ingestProcessingBody(String source);

  /// Ingest review: in-page title while drafts are being written to the ledger
  ///
  /// In en, this message translates to:
  /// **'Recording entries'**
  String get ingestRecordingTitle;

  /// Ingest review: in-page status while confirmed drafts are being recorded
  ///
  /// In en, this message translates to:
  /// **'Writing confirmed entries and refreshing the queue.'**
  String get ingestRecordingBody;

  /// Ingest source label for CSV input
  ///
  /// In en, this message translates to:
  /// **'CSV file'**
  String get ingestSourceCsv;

  /// Ingest source label for pasted statement text
  ///
  /// In en, this message translates to:
  /// **'Pasted text'**
  String get ingestSourcePaste;

  /// Ingest source label for image input
  ///
  /// In en, this message translates to:
  /// **'Receipt image'**
  String get ingestSourceImage;

  /// Ingest source label for PDF input
  ///
  /// In en, this message translates to:
  /// **'PDF statement'**
  String get ingestSourcePdf;

  /// Ingest source label for email input
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get ingestSourceEmail;

  /// Ingest review: parsed draft confidence chip
  ///
  /// In en, this message translates to:
  /// **'{percent}% confidence'**
  String ingestDraftConfidence(int percent);

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

  /// No description provided for @ingestEditDraft.
  ///
  /// In en, this message translates to:
  /// **'Correct fields'**
  String get ingestEditDraft;

  /// No description provided for @ingestEditDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get ingestEditDescription;

  /// No description provided for @ingestEditAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get ingestEditAmount;

  /// No description provided for @ingestEditCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get ingestEditCurrency;

  /// No description provided for @ingestEditDate.
  ///
  /// In en, this message translates to:
  /// **'Transaction date'**
  String get ingestEditDate;

  /// No description provided for @ingestEditCategory.
  ///
  /// In en, this message translates to:
  /// **'Category hint (optional)'**
  String get ingestEditCategory;

  /// No description provided for @ingestEditInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a description, positive amount, and currency.'**
  String get ingestEditInvalid;

  /// No description provided for @ingestEditConflict.
  ///
  /// In en, this message translates to:
  /// **'This draft changed while you were editing. Review the latest version and try again.'**
  String get ingestEditConflict;

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
  /// **'Import Alipay, WeChat Pay, or bank statement CSV/text regularly.\nOverlapping periods are flagged before confirmation.'**
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

  /// Ingest review: open the compact capture options menu
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get ingestCaptureMenuAction;

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
  /// **'AI services · Bring your own API key'**
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

  /// Confirmation title before deleting an LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'Delete provider?'**
  String get aiLlmDeleteTitle;

  /// Confirmation body before deleting an LLM provider profile
  ///
  /// In en, this message translates to:
  /// **'This removes {name} and its stored API key from this device.'**
  String aiLlmDeleteBody(String name);

  /// Empty state on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'No model providers configured. Add an API key to connect directly from this device.'**
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
  /// **'Use your own LLM API key to connect directly from this device to a model provider. You can save multiple providers and switch at any time. API keys stay in this device\'s secure storage (Keychain/Keystore) and are never uploaded, synced, or backed up. Costs and rate limits belong to your provider account.'**
  String get aiLlmIntro;

  /// Unsupported-platform card title on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'This platform does not support on-device direct connections'**
  String get aiLlmUnsupportedTitle;

  /// Unsupported-platform card body on the LLM credentials page
  ///
  /// In en, this message translates to:
  /// **'Bring-your-own-key AI services are available on iOS, Android, macOS, Windows, and Linux and require system secure storage. Web is not supported yet.'**
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

  /// No description provided for @watchlistSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select a symbol to inspect its quote and alert rules'**
  String get watchlistSelectItem;

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

  /// Title and accessible label for one watchlist row's action menu
  ///
  /// In en, this message translates to:
  /// **'Actions for {symbol}'**
  String watchlistRowActionsTitle(String symbol);

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

  /// Options workspace page title; also used by the command palette label
  ///
  /// In en, this message translates to:
  /// **'Options workspace'**
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
  /// **'Selling cash-secured puts and covered calls can result in losses. If assigned, a cash-secured put may require you to buy 100 shares at the strike price; a covered call limits potential gains above the strike price. Income Planner only screens opportunities that match your risk preferences. It does not predict prices or place orders. Read OCC Characteristics and Risks of Standardized Options before using this feature.'**
  String get incomePlannerOccBody;

  /// OCC disclosure accept action
  ///
  /// In en, this message translates to:
  /// **'I understand the risks · Continue'**
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

  /// Section heading for advanced options scan filter fields
  ///
  /// In en, this message translates to:
  /// **'Advanced filters'**
  String get incomePlannerProfileAdvancedFilters;

  /// Minimum days-to-expiration filter label
  ///
  /// In en, this message translates to:
  /// **'Min DTE'**
  String get incomePlannerProfileMinDte;

  /// Maximum days-to-expiration filter label
  ///
  /// In en, this message translates to:
  /// **'Max DTE'**
  String get incomePlannerProfileMaxDte;

  /// Minimum annualized yield filter label
  ///
  /// In en, this message translates to:
  /// **'Min annual yield'**
  String get incomePlannerProfileMinYield;

  /// Minimum open interest filter label
  ///
  /// In en, this message translates to:
  /// **'Min open interest'**
  String get incomePlannerProfileMinOpenInterest;

  /// Minimum contract volume filter label
  ///
  /// In en, this message translates to:
  /// **'Min volume'**
  String get incomePlannerProfileMinVolume;

  /// Maximum bid ask spread percentage filter label
  ///
  /// In en, this message translates to:
  /// **'Max spread'**
  String get incomePlannerProfileMaxSpread;

  /// Maximum per-trade cash usage percentage filter label
  ///
  /// In en, this message translates to:
  /// **'Max capital per trade'**
  String get incomePlannerProfileMaxCapitalPerTrade;

  /// Helper text for percentage fields in the strategy profile sheet
  ///
  /// In en, this message translates to:
  /// **'Enter a percent, e.g. 12 means 12%.'**
  String get incomePlannerProfilePercentHelper;

  /// Validation error for invalid profile numeric fields
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number.'**
  String get incomePlannerProfileValidationNumber;

  /// Validation error for out-of-range profile numeric fields
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max}.'**
  String incomePlannerProfileValidationRange(int min, int max);

  /// Validation error when max DTE is smaller than min DTE
  ///
  /// In en, this message translates to:
  /// **'Max DTE must be greater than or equal to min DTE.'**
  String get incomePlannerProfileValidationDteOrder;

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
  /// **'No candidates passed your guardrails. Review the reasons below; keeping your current limits and checking again later is a valid outcome.'**
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

  /// No description provided for @incomePlannerChipLeaps.
  ///
  /// In en, this message translates to:
  /// **'LEAPS call'**
  String get incomePlannerChipLeaps;

  /// No description provided for @incomePlannerLaneSellSection.
  ///
  /// In en, this message translates to:
  /// **'Income (puts & calls)'**
  String get incomePlannerLaneSellSection;

  /// No description provided for @incomePlannerLaneLeapsSection.
  ///
  /// In en, this message translates to:
  /// **'LEAPS calls'**
  String get incomePlannerLaneLeapsSection;

  /// No description provided for @incomePlannerAdjustLeapsBudget.
  ///
  /// In en, this message translates to:
  /// **'Adjust LEAPS budget'**
  String get incomePlannerAdjustLeapsBudget;

  /// No description provided for @incomePlannerScanLeapsCta.
  ///
  /// In en, this message translates to:
  /// **'Scan candidates'**
  String get incomePlannerScanLeapsCta;

  /// No description provided for @incomePlannerMetricLeapsCost.
  ///
  /// In en, this message translates to:
  /// **'Cost (max loss)'**
  String get incomePlannerMetricLeapsCost;

  /// No description provided for @incomePlannerMetricLeverage.
  ///
  /// In en, this message translates to:
  /// **'Leverage'**
  String get incomePlannerMetricLeverage;

  /// No description provided for @incomePlannerMetricAnnualCost.
  ///
  /// In en, this message translates to:
  /// **'Annualized time-value cost'**
  String get incomePlannerMetricAnnualCost;

  /// No description provided for @incomePlannerMetricFundingCoverage.
  ///
  /// In en, this message translates to:
  /// **'Income coverage'**
  String get incomePlannerMetricFundingCoverage;

  /// Risk badge: low
  ///
  /// In en, this message translates to:
  /// **'Lower relative risk'**
  String get incomePlannerRiskLow;

  /// Risk badge: moderate
  ///
  /// In en, this message translates to:
  /// **'Moderate relative risk'**
  String get incomePlannerRiskModerate;

  /// Risk badge: elevated
  ///
  /// In en, this message translates to:
  /// **'Elevated relative risk'**
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

  /// Card/detail metric: option mid price
  ///
  /// In en, this message translates to:
  /// **'Option price'**
  String get incomePlannerMetricOptionPrice;

  /// Detail metric: option bid and ask quote
  ///
  /// In en, this message translates to:
  /// **'Bid / Ask'**
  String get incomePlannerMetricBidAsk;

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

  /// No description provided for @incomePlannerDetailContractSection.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get incomePlannerDetailContractSection;

  /// No description provided for @incomePlannerDetailLiquiditySection.
  ///
  /// In en, this message translates to:
  /// **'Liquidity'**
  String get incomePlannerDetailLiquiditySection;

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

  /// No description provided for @incomePlannerJournalDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete trade journal entry?'**
  String get incomePlannerJournalDeleteTitle;

  /// No description provided for @incomePlannerJournalDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the entry from statistics, Wheel history, and its mirrored ledger postings.'**
  String get incomePlannerJournalDeleteBody;

  /// Journal sheet field label for entry premium
  ///
  /// In en, this message translates to:
  /// **'Credit received (per contract)'**
  String get incomePlannerJournalCreditLabel;

  /// Live preview under the per-contract credit field: credit × contract size × quantity
  ///
  /// In en, this message translates to:
  /// **'Total premium: {amount}'**
  String incomePlannerJournalTotalCredit(String amount);

  /// No description provided for @incomePlannerAssignmentNeedsAccount.
  ///
  /// In en, this message translates to:
  /// **'Link a brokerage account before recording an assignment — otherwise the share leg cannot be booked to the ledger.'**
  String get incomePlannerAssignmentNeedsAccount;

  /// Journal sheet field label for close-out debit
  ///
  /// In en, this message translates to:
  /// **'Debit paid to close (per contract)'**
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

  /// Journal sheet account picker label for the securities account
  ///
  /// In en, this message translates to:
  /// **'Brokerage account'**
  String get incomePlannerJournalBrokerageAccountLabel;

  /// Journal sheet account picker label for the cash account
  ///
  /// In en, this message translates to:
  /// **'Cash account'**
  String get incomePlannerJournalCashAccountLabel;

  /// Journal sheet field label for option strike price
  ///
  /// In en, this message translates to:
  /// **'Strike price'**
  String get incomePlannerJournalStrikeLabel;

  /// Journal sheet field label for option contract size, usually 100 shares
  ///
  /// In en, this message translates to:
  /// **'Contract size'**
  String get incomePlannerJournalContractSizeLabel;

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

  /// CTA to open options trade statistics
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get incomePlannerStatsAction;

  /// Title for the options trade statistics page
  ///
  /// In en, this message translates to:
  /// **'Options review'**
  String get incomePlannerStatsTitle;

  /// Empty title for options trade stats
  ///
  /// In en, this message translates to:
  /// **'No trades yet'**
  String get incomePlannerStatsEmptyTitle;

  /// Empty body for options trade stats
  ///
  /// In en, this message translates to:
  /// **'Log option trades from Income Planner to review premium, realized P&L, and assignment discipline.'**
  String get incomePlannerStatsEmptyBody;

  /// Overview card title on options trade stats page
  ///
  /// In en, this message translates to:
  /// **'Journal summary'**
  String get incomePlannerStatsOverviewTitle;

  /// Metric label: total option trades
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get incomePlannerStatsTotalTrades;

  /// Metric label: open option trades
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get incomePlannerStatsOpenTrades;

  /// Metric label: assigned option trades
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get incomePlannerStatsAssignedTrades;

  /// Metric label: expired option trades
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get incomePlannerStatsExpiredTrades;

  /// Metric label: total premium received
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get incomePlannerStatsPremium;

  /// Metric label: realized P&L with conservative tracking
  ///
  /// In en, this message translates to:
  /// **'Tracked P&L'**
  String get incomePlannerStatsRealizedPnl;

  /// Metric label: win rate
  ///
  /// In en, this message translates to:
  /// **'Win rate'**
  String get incomePlannerStatsWinRate;

  /// Metric label: average holding days
  ///
  /// In en, this message translates to:
  /// **'Avg days'**
  String get incomePlannerStatsAvgHoldingDays;

  /// Note explaining multi-currency stats are not merged
  ///
  /// In en, this message translates to:
  /// **'Amounts are shown separately because this journal contains {currencies}.'**
  String incomePlannerStatsMultiCurrencyNote(String currencies);

  /// No description provided for @incomePlannerStatsPremiumChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium by underlying'**
  String get incomePlannerStatsPremiumChartTitle;

  /// No description provided for @optionsExplainYieldStrength.
  ///
  /// In en, this message translates to:
  /// **'Annualized yield {yieldPct} (score {score})'**
  String optionsExplainYieldStrength(String yieldPct, String score);

  /// No description provided for @optionsExplainLiquidityStrength.
  ///
  /// In en, this message translates to:
  /// **'Good liquidity: bid/ask spread {spread}, open interest {openInterest} (score {score})'**
  String optionsExplainLiquidityStrength(
    String spread,
    int openInterest,
    String score,
  );

  /// No description provided for @optionsExplainSafetyStrength.
  ///
  /// In en, this message translates to:
  /// **'Margin of safety {margin} from breakeven (score {score})'**
  String optionsExplainSafetyStrength(String margin, String score);

  /// No description provided for @optionsExplainIvStrength.
  ///
  /// In en, this message translates to:
  /// **'Implied volatility {iv} is in a resilient range (score {score})'**
  String optionsExplainIvStrength(String iv, String score);

  /// No description provided for @optionsExplainIvUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get optionsExplainIvUnknown;

  /// No description provided for @optionsExplainFitStrength.
  ///
  /// In en, this message translates to:
  /// **'Fits current positions (score {score})'**
  String optionsExplainFitStrength(String score);

  /// No description provided for @optionsExplainEventStrength.
  ///
  /// In en, this message translates to:
  /// **'No earnings or macro event in the next 7 days (score {score})'**
  String optionsExplainEventStrength(String score);

  /// No description provided for @optionsExplainEventUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Event calendar unavailable; event risk is not scored'**
  String get optionsExplainEventUnavailable;

  /// No description provided for @optionsExplainGenericScore.
  ///
  /// In en, this message translates to:
  /// **'{dimension} score {score}'**
  String optionsExplainGenericScore(String dimension, String score);

  /// No description provided for @optionsExplainYieldWeak.
  ///
  /// In en, this message translates to:
  /// **'Lower annualized yield: {yieldPct} (score {score})'**
  String optionsExplainYieldWeak(String yieldPct, String score);

  /// No description provided for @optionsExplainLiquidityWeak.
  ///
  /// In en, this message translates to:
  /// **'Moderate liquidity: bid/ask spread {spread} (score {score})'**
  String optionsExplainLiquidityWeak(String spread, String score);

  /// No description provided for @optionsExplainSafetyWeak.
  ///
  /// In en, this message translates to:
  /// **'Limited margin of safety: {margin} (score {score})'**
  String optionsExplainSafetyWeak(String margin, String score);

  /// No description provided for @optionsExplainIvWeak.
  ///
  /// In en, this message translates to:
  /// **'Implied volatility is outside the normal range (score {score})'**
  String optionsExplainIvWeak(String score);

  /// No description provided for @optionsExplainFitWeak.
  ///
  /// In en, this message translates to:
  /// **'Only a moderate fit with current positions (score {score})'**
  String optionsExplainFitWeak(String score);

  /// No description provided for @optionsExplainEventWeak.
  ///
  /// In en, this message translates to:
  /// **'Execution needs caution inside the event window (score {score})'**
  String optionsExplainEventWeak(String score);

  /// No description provided for @optionsExplainEventCheck.
  ///
  /// In en, this message translates to:
  /// **'Check earnings and macro dates before placing the trade'**
  String get optionsExplainEventCheck;

  /// No description provided for @optionsExplainSummaryPut.
  ///
  /// In en, this message translates to:
  /// **'{symbol} {dte}DTE sell put @ {strike} — annualized {yieldPct}, margin of safety {margin}'**
  String optionsExplainSummaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  );

  /// No description provided for @optionsExplainSummaryCall.
  ///
  /// In en, this message translates to:
  /// **'{symbol} {dte}DTE covered call @ {strike} — annualized {yieldPct}, margin of safety {margin}'**
  String optionsExplainSummaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  );

  /// No description provided for @optionsExplainBestForPutConservative.
  ///
  /// In en, this message translates to:
  /// **'Best for conservative cash-flow preference: higher margin of safety and liquidity first.'**
  String get optionsExplainBestForPutConservative;

  /// No description provided for @optionsExplainBestForPutBalanced.
  ///
  /// In en, this message translates to:
  /// **'Best for balanced cash-flow preference: balances yield against downside risk.'**
  String get optionsExplainBestForPutBalanced;

  /// No description provided for @optionsExplainBestForPutAggressive.
  ///
  /// In en, this message translates to:
  /// **'Best when you accept higher assignment probability in exchange for annualized yield.'**
  String get optionsExplainBestForPutAggressive;

  /// No description provided for @optionsExplainBestForCallConservative.
  ///
  /// In en, this message translates to:
  /// **'Best for conservative enhancement: sell farther OTM calls with lower assignment probability.'**
  String get optionsExplainBestForCallConservative;

  /// No description provided for @optionsExplainBestForCallBalanced.
  ///
  /// In en, this message translates to:
  /// **'Best for balanced enhancement: add income without materially disrupting the position.'**
  String get optionsExplainBestForCallBalanced;

  /// No description provided for @optionsExplainBestForCallAggressive.
  ///
  /// In en, this message translates to:
  /// **'Best when you are willing to accept assignment to realize gains.'**
  String get optionsExplainBestForCallAggressive;

  /// No description provided for @optionsExplainAvoidPut.
  ///
  /// In en, this message translates to:
  /// **'Avoid if you are not willing to buy 100 shares at the strike when assigned.'**
  String get optionsExplainAvoidPut;

  /// No description provided for @optionsExplainAvoidCall.
  ///
  /// In en, this message translates to:
  /// **'Avoid if you are not willing to sell 100 shares at the strike.'**
  String get optionsExplainAvoidCall;

  /// No description provided for @optionsExplainWorstPut.
  ///
  /// In en, this message translates to:
  /// **'If {symbol} falls below {strike}, you would buy 100 shares at an effective cost of {breakeven}, using {cash} cash.'**
  String optionsExplainWorstPut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  );

  /// No description provided for @optionsExplainWorstCall.
  ///
  /// In en, this message translates to:
  /// **'If {symbol} rises to {strike}, you would sell 100 shares at {strike} and miss upside above that level; total proceeds are capped at {cap}.'**
  String optionsExplainWorstCall(String symbol, String strike, String cap);

  /// No description provided for @optionsExplainLeapsSummary.
  ///
  /// In en, this message translates to:
  /// **'{symbol} {dte}DTE LEAPS call @ {strike} — cost {cost}, delta {delta}'**
  String optionsExplainLeapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  );

  /// No description provided for @optionsExplainLeapsWorstCase.
  ///
  /// In en, this message translates to:
  /// **'If {symbol} closes below {strike} at expiration, the entire {cost} premium is lost. Maximum loss is the full cost paid.'**
  String optionsExplainLeapsWorstCase(
    String symbol,
    String strike,
    String cost,
  );

  /// No description provided for @optionsExplainLeapsBestFor.
  ///
  /// In en, this message translates to:
  /// **'Best as a funded stock substitute: long-dated deep-in-the-money exposure paid for by wheel or dividend income.'**
  String get optionsExplainLeapsBestFor;

  /// No description provided for @optionsExplainLeapsAvoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid if you cannot hold through a full drawdown — time value decays and the position can expire worthless.'**
  String get optionsExplainLeapsAvoid;

  /// No description provided for @optionsExplainLeapsCostBullet.
  ///
  /// In en, this message translates to:
  /// **'Annualized time-value cost {costPct} per unit of share exposure'**
  String optionsExplainLeapsCostBullet(String costPct);

  /// No description provided for @optionsExplainLeapsLeverageBullet.
  ///
  /// In en, this message translates to:
  /// **'Controls {leverage}x the share exposure per unit of capital (delta {delta})'**
  String optionsExplainLeapsLeverageBullet(String leverage, String delta);

  /// No description provided for @optionsExplainLeapsIntrinsicBullet.
  ///
  /// In en, this message translates to:
  /// **'{intrinsicPct} of the premium is intrinsic value'**
  String optionsExplainLeapsIntrinsicBullet(String intrinsicPct);

  /// No description provided for @optionsExplainLeapsSpreadBullet.
  ///
  /// In en, this message translates to:
  /// **'Wide bid/ask spread {spread} — LEAPS liquidity is thin, use limit orders'**
  String optionsExplainLeapsSpreadBullet(String spread);

  /// No description provided for @optionsExplainLeapsDeltaEstimated.
  ///
  /// In en, this message translates to:
  /// **'Delta is estimated from implied volatility — the data source provides no greeks'**
  String get optionsExplainLeapsDeltaEstimated;

  /// No description provided for @optionsExplainLeapsThetaBullet.
  ///
  /// In en, this message translates to:
  /// **'{extrinsic} of time value will decay to zero by expiration'**
  String optionsExplainLeapsThetaBullet(String extrinsic);

  /// No description provided for @optionsExplainLeapsFundingBullet.
  ///
  /// In en, this message translates to:
  /// **'Group income already covers {coverage} of this cost'**
  String optionsExplainLeapsFundingBullet(String coverage);

  /// No description provided for @optionsLedgerPremium.
  ///
  /// In en, this message translates to:
  /// **'Options premium {symbol}'**
  String optionsLedgerPremium(String symbol);

  /// No description provided for @optionsLedgerCloseDebit.
  ///
  /// In en, this message translates to:
  /// **'Options close debit {symbol}'**
  String optionsLedgerCloseDebit(String symbol);

  /// No description provided for @optionsLedgerPutAssigned.
  ///
  /// In en, this message translates to:
  /// **'Put assigned {symbol}'**
  String optionsLedgerPutAssigned(String symbol);

  /// No description provided for @optionsLedgerCallAssigned.
  ///
  /// In en, this message translates to:
  /// **'Covered call assigned {symbol}'**
  String optionsLedgerCallAssigned(String symbol);

  /// No description provided for @optionsLedgerLeapsOpen.
  ///
  /// In en, this message translates to:
  /// **'LEAPS open {symbol}'**
  String optionsLedgerLeapsOpen(String symbol);

  /// No description provided for @optionsLedgerLeapsClose.
  ///
  /// In en, this message translates to:
  /// **'LEAPS close {symbol}'**
  String optionsLedgerLeapsClose(String symbol);

  /// No description provided for @optionsLedgerLeapsExercise.
  ///
  /// In en, this message translates to:
  /// **'LEAPS exercise {symbol}'**
  String optionsLedgerLeapsExercise(String symbol);

  /// No description provided for @optionsLedgerLeapsExpired.
  ///
  /// In en, this message translates to:
  /// **'LEAPS expired {symbol}'**
  String optionsLedgerLeapsExpired(String symbol);

  /// Section title: strategy breakdown
  ///
  /// In en, this message translates to:
  /// **'By strategy'**
  String get incomePlannerStatsStrategySectionTitle;

  /// Section title: underlying symbol breakdown
  ///
  /// In en, this message translates to:
  /// **'By underlying'**
  String get incomePlannerStatsSymbolSectionTitle;

  /// Small stat line for strategy rows
  ///
  /// In en, this message translates to:
  /// **'{total} trades · {open} open'**
  String incomePlannerStatsTradeCount(int total, int open);

  /// Small stat line for underlying rows
  ///
  /// In en, this message translates to:
  /// **'{total} trades · {open} open · {assigned} assigned · {expired} expired'**
  String incomePlannerStatsSymbolDetail(
    int total,
    int open,
    int assigned,
    int expired,
  );

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

  /// Explicit checkbox acknowledgement in the OCC risk disclosure
  ///
  /// In en, this message translates to:
  /// **'I understand that assignment can require buying or selling 100 shares per contract, and that this planner does not place orders or guarantee returns.'**
  String get incomePlannerOccConfirmation;

  /// Validation when both per-underlying strategy toggles are disabled
  ///
  /// In en, this message translates to:
  /// **'Enable at least one strategy for this underlying.'**
  String get incomePlannerUnderlyingStrategyRequired;

  /// Confirmation title when deleting an approved underlying
  ///
  /// In en, this message translates to:
  /// **'Remove approved underlying?'**
  String get incomePlannerUnderlyingDeleteTitle;

  /// Confirmation body when deleting an approved underlying
  ///
  /// In en, this message translates to:
  /// **'{symbol} will no longer be included in option scans.'**
  String incomePlannerUnderlyingDeleteBody(String symbol);

  /// Supported-market helper in the approved-underlying form
  ///
  /// In en, this message translates to:
  /// **'Current scans support US-listed stocks and ETFs.'**
  String get incomePlannerSupportedMarketHelper;

  /// Approved underlying maximum buy price label
  ///
  /// In en, this message translates to:
  /// **'Highest acceptable assignment price'**
  String get incomePlannerMaxBuyPriceLabel;

  /// Approved underlying maximum buy price helper
  ///
  /// In en, this message translates to:
  /// **'Put strikes above this price are rejected. Leave blank for no additional price ceiling.'**
  String get incomePlannerMaxBuyPriceHelper;

  /// Approved underlying minimum sell price label
  ///
  /// In en, this message translates to:
  /// **'Lowest acceptable call-away price'**
  String get incomePlannerMinSellPriceLabel;

  /// Approved underlying minimum sell price helper
  ///
  /// In en, this message translates to:
  /// **'Call strikes below this price are rejected. Leave blank for no additional price floor.'**
  String get incomePlannerMinSellPriceHelper;

  /// Approved underlying notes label
  ///
  /// In en, this message translates to:
  /// **'Investment stance'**
  String get incomePlannerUnderlyingNotesLabel;

  /// Approved underlying notes helper
  ///
  /// In en, this message translates to:
  /// **'Record why you are willing to own or sell this underlying.'**
  String get incomePlannerUnderlyingNotesHelper;

  /// Generic positive-number validation
  ///
  /// In en, this message translates to:
  /// **'Enter a number greater than zero.'**
  String get incomePlannerPositiveNumberValidation;

  /// Profile validation when no strategy is enabled
  ///
  /// In en, this message translates to:
  /// **'Enable at least one options strategy.'**
  String get incomePlannerProfileStrategyRequired;

  /// Collapsed advanced-filter summary
  ///
  /// In en, this message translates to:
  /// **'{minDte}–{maxDte} DTE · max {capital}% per trade'**
  String incomePlannerProfileAdvancedSummary(
    int minDte,
    int maxDte,
    String capital,
  );

  /// Maximum underlying concentration field label
  ///
  /// In en, this message translates to:
  /// **'Max post-assignment underlying exposure'**
  String get incomePlannerProfileMaxUnderlyingExposure;

  /// Put absolute delta range label
  ///
  /// In en, this message translates to:
  /// **'Put absolute delta range'**
  String get incomePlannerProfilePutDeltaRange;

  /// No description provided for @incomePlannerProfileLeapsSection.
  ///
  /// In en, this message translates to:
  /// **'LEAPS scan'**
  String get incomePlannerProfileLeapsSection;

  /// No description provided for @incomePlannerProfileSellFilters.
  ///
  /// In en, this message translates to:
  /// **'Sell-side filters'**
  String get incomePlannerProfileSellFilters;

  /// No description provided for @incomePlannerProfileLeapsSummary.
  ///
  /// In en, this message translates to:
  /// **'{minDte}–{maxDte} DTE · delta {low}–{high}'**
  String incomePlannerProfileLeapsSummary(
    int minDte,
    int maxDte,
    String low,
    String high,
  );

  /// No description provided for @incomePlannerProfileLeapsMinDte.
  ///
  /// In en, this message translates to:
  /// **'LEAPS min DTE'**
  String get incomePlannerProfileLeapsMinDte;

  /// No description provided for @incomePlannerProfileLeapsMaxDte.
  ///
  /// In en, this message translates to:
  /// **'LEAPS max DTE'**
  String get incomePlannerProfileLeapsMaxDte;

  /// No description provided for @incomePlannerProfileLeapsDeltaRange.
  ///
  /// In en, this message translates to:
  /// **'LEAPS call delta range'**
  String get incomePlannerProfileLeapsDeltaRange;

  /// No description provided for @incomePlannerProfileLeapsMaxSpread.
  ///
  /// In en, this message translates to:
  /// **'LEAPS max spread (%)'**
  String get incomePlannerProfileLeapsMaxSpread;

  /// Call delta range label
  ///
  /// In en, this message translates to:
  /// **'Call delta range'**
  String get incomePlannerProfileCallDeltaRange;

  /// Delta range lower bound label
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get incomePlannerProfileDeltaLow;

  /// Delta range upper bound label
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get incomePlannerProfileDeltaHigh;

  /// Delta value validation
  ///
  /// In en, this message translates to:
  /// **'Use a decimal above 0 and at most 1.'**
  String get incomePlannerProfileDeltaValidation;

  /// Delta range order validation
  ///
  /// In en, this message translates to:
  /// **'High delta must be at least the low delta.'**
  String get incomePlannerProfileDeltaOrderValidation;

  /// Workspace opportunities tab
  ///
  /// In en, this message translates to:
  /// **'Opportunities'**
  String get incomePlannerWorkspaceOpportunities;

  /// Workspace journal tab
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get incomePlannerWorkspaceJournal;

  /// Workspace candidate-count metric
  ///
  /// In en, this message translates to:
  /// **'Candidates'**
  String get incomePlannerWorkspaceCandidates;

  /// Workspace open-position metric
  ///
  /// In en, this message translates to:
  /// **'Open positions'**
  String get incomePlannerWorkspaceOpenPositions;

  /// Workspace approved-underlying metric
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get incomePlannerWorkspaceApproved;

  /// Workspace scan freshness state
  ///
  /// In en, this message translates to:
  /// **'not scanned yet'**
  String get incomePlannerWorkspaceNeverScanned;

  /// Workspace stale scan state
  ///
  /// In en, this message translates to:
  /// **'scan is stale'**
  String get incomePlannerWorkspaceScanStale;

  /// Workspace fresh scan state
  ///
  /// In en, this message translates to:
  /// **'scan is fresh'**
  String get incomePlannerWorkspaceScanFresh;

  /// Workspace profile and freshness summary
  ///
  /// In en, this message translates to:
  /// **'{minDte}–{maxDte} DTE · max {capital} per trade · {scanState}'**
  String incomePlannerWorkspaceProfileSummary(
    int minDte,
    int maxDte,
    String capital,
    String scanState,
  );

  /// Workspace action to reveal approved underlyings
  ///
  /// In en, this message translates to:
  /// **'Manage underlyings'**
  String get incomePlannerManageApprovedAction;

  /// Collapsed approved-underlyings summary
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No approved symbols} =1{1 approved symbol} other{{count} approved symbols}}'**
  String incomePlannerApprovedSummary(int count);

  /// In-progress scan helper
  ///
  /// In en, this message translates to:
  /// **'Keeping cached results visible while fresh option chains are checked. This can take up to 45 seconds.'**
  String get incomePlannerScanProgressHint;

  /// Successful scan toast
  ///
  /// In en, this message translates to:
  /// **'Scan complete · {count} candidates'**
  String incomePlannerScanCompletedToast(int count);

  /// Opportunity filter: all strategies
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get incomePlannerOpportunityFilterAll;

  /// Opportunity result count and ordering summary
  ///
  /// In en, this message translates to:
  /// **'Showing {visible} of {total}, ordered by fit score'**
  String incomePlannerOpportunityCountSummary(int visible, int total);

  /// Empty state after filtering opportunities
  ///
  /// In en, this message translates to:
  /// **'No opportunities match this strategy filter.'**
  String get incomePlannerOpportunityFilterEmpty;

  /// Opportunity card expiration summary
  ///
  /// In en, this message translates to:
  /// **'Expires {date} · {dte} DTE'**
  String incomePlannerOpportunityExpirySummary(String date, int dte);

  /// Per-contract total premium metric
  ///
  /// In en, this message translates to:
  /// **'Total premium'**
  String get incomePlannerMetricPremiumTotal;

  /// Underlying spot price metric
  ///
  /// In en, this message translates to:
  /// **'Underlying'**
  String get incomePlannerMetricUnderlyingPrice;

  /// Option expiration date metric
  ///
  /// In en, this message translates to:
  /// **'Expiration'**
  String get incomePlannerMetricExpiration;

  /// Option delta metric
  ///
  /// In en, this message translates to:
  /// **'Delta'**
  String get incomePlannerMetricDelta;

  /// Option implied-volatility metric
  ///
  /// In en, this message translates to:
  /// **'Implied volatility'**
  String get incomePlannerMetricIv;

  /// Option open-interest metric
  ///
  /// In en, this message translates to:
  /// **'Open interest'**
  String get incomePlannerMetricOpenInterest;

  /// Option volume metric
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get incomePlannerMetricVolume;

  /// Option bid/ask spread metric
  ///
  /// In en, this message translates to:
  /// **'Bid/ask spread'**
  String get incomePlannerMetricSpread;

  /// Opportunity score dimension: yield
  ///
  /// In en, this message translates to:
  /// **'Yield'**
  String get incomePlannerScoreYield;

  /// Opportunity score dimension: liquidity
  ///
  /// In en, this message translates to:
  /// **'Liquidity'**
  String get incomePlannerScoreLiquidity;

  /// Opportunity score dimension: safety margin
  ///
  /// In en, this message translates to:
  /// **'Safety margin'**
  String get incomePlannerScoreSafetyMargin;

  /// Opportunity score dimension: implied volatility
  ///
  /// In en, this message translates to:
  /// **'Volatility fit'**
  String get incomePlannerScoreIv;

  /// Opportunity score dimension: portfolio fit
  ///
  /// In en, this message translates to:
  /// **'Portfolio fit'**
  String get incomePlannerScorePortfolioFit;

  /// Opportunity score dimension: event safety
  ///
  /// In en, this message translates to:
  /// **'Event safety'**
  String get incomePlannerScoreEventSafety;

  /// Zero-result rejection reason heading
  ///
  /// In en, this message translates to:
  /// **'Main rejection reasons'**
  String get incomePlannerRejectionReasonsTitle;

  /// Aggregated rejection reason line
  ///
  /// In en, this message translates to:
  /// **'{reason} · {count} contracts'**
  String incomePlannerRejectionReasonSummary(String reason, int count);

  /// No description provided for @incomePlannerRejectCapitalLimit.
  ///
  /// In en, this message translates to:
  /// **'Capital limit'**
  String get incomePlannerRejectCapitalLimit;

  /// No description provided for @incomePlannerRejectLiquidity.
  ///
  /// In en, this message translates to:
  /// **'Insufficient liquidity'**
  String get incomePlannerRejectLiquidity;

  /// No description provided for @incomePlannerRejectSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread too wide'**
  String get incomePlannerRejectSpread;

  /// No description provided for @incomePlannerRejectDte.
  ///
  /// In en, this message translates to:
  /// **'Outside DTE range'**
  String get incomePlannerRejectDte;

  /// No description provided for @incomePlannerRejectDelta.
  ///
  /// In en, this message translates to:
  /// **'Outside delta range'**
  String get incomePlannerRejectDelta;

  /// No description provided for @incomePlannerRejectDeltaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Greeks unavailable from the data source'**
  String get incomePlannerRejectDeltaUnavailable;

  /// No description provided for @incomePlannerRejectLeapsBudget.
  ///
  /// In en, this message translates to:
  /// **'Above the LEAPS budget'**
  String get incomePlannerRejectLeapsBudget;

  /// No description provided for @incomePlannerRejectQuote.
  ///
  /// In en, this message translates to:
  /// **'No usable quote'**
  String get incomePlannerRejectQuote;

  /// No description provided for @incomePlannerRejectPriceIntent.
  ///
  /// In en, this message translates to:
  /// **'Outside your acceptable price'**
  String get incomePlannerRejectPriceIntent;

  /// No description provided for @incomePlannerRejectEventRisk.
  ///
  /// In en, this message translates to:
  /// **'Event-risk guard'**
  String get incomePlannerRejectEventRisk;

  /// No description provided for @incomePlannerRejectOther.
  ///
  /// In en, this message translates to:
  /// **'Other hard filters'**
  String get incomePlannerRejectOther;

  /// No description provided for @incomePlannerApprovedPutNoLimit.
  ///
  /// In en, this message translates to:
  /// **'Put enabled'**
  String get incomePlannerApprovedPutNoLimit;

  /// No description provided for @incomePlannerApprovedPutLimit.
  ///
  /// In en, this message translates to:
  /// **'Put ≤ {price}'**
  String incomePlannerApprovedPutLimit(String price);

  /// No description provided for @incomePlannerApprovedCallNoLimit.
  ///
  /// In en, this message translates to:
  /// **'Call enabled'**
  String get incomePlannerApprovedCallNoLimit;

  /// No description provided for @incomePlannerApprovedCallLimit.
  ///
  /// In en, this message translates to:
  /// **'Call ≥ {price}'**
  String incomePlannerApprovedCallLimit(String price);

  /// No description provided for @incomePlannerJournalOpenedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Opened on'**
  String get incomePlannerJournalOpenedAtLabel;

  /// No description provided for @incomePlannerJournalExpirationLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiration'**
  String get incomePlannerJournalExpirationLabel;

  /// No description provided for @incomePlannerJournalClosedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolved on'**
  String get incomePlannerJournalClosedAtLabel;

  /// No description provided for @incomePlannerJournalContractQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of contracts'**
  String get incomePlannerJournalContractQuantityLabel;

  /// No description provided for @incomePlannerJournalFeesLabel.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get incomePlannerJournalFeesLabel;

  /// No description provided for @incomePlannerJournalFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get incomePlannerJournalFilterAll;

  /// No description provided for @incomePlannerJournalFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get incomePlannerJournalFilterOpen;

  /// No description provided for @incomePlannerJournalFilterResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get incomePlannerJournalFilterResolved;

  /// No description provided for @incomePlannerJournalFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No journal entries match this filter.'**
  String get incomePlannerJournalFilterEmpty;

  /// No description provided for @incomePlannerJournalExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'expires in {days}d'**
  String incomePlannerJournalExpiresIn(int days);

  /// No description provided for @incomePlannerJournalQuantitySummary.
  ///
  /// In en, this message translates to:
  /// **'{quantity} contract(s) · {size} shares each'**
  String incomePlannerJournalQuantitySummary(int quantity, int size);

  /// No description provided for @incomePlannerJournalPremiumLabel.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get incomePlannerJournalPremiumLabel;

  /// No description provided for @incomePlannerJournalNetPnlLabel.
  ///
  /// In en, this message translates to:
  /// **'Net P&L'**
  String get incomePlannerJournalNetPnlLabel;

  /// No description provided for @planWheelStageMixedOpen.
  ///
  /// In en, this message translates to:
  /// **'Mixed open positions'**
  String get planWheelStageMixedOpen;

  /// No description provided for @incomePlannerWheelOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No open positions} =1{1 open position} other{{count} open positions}}'**
  String incomePlannerWheelOpenCount(int count);

  /// No description provided for @incomePlannerWheelDueSummary.
  ///
  /// In en, this message translates to:
  /// **'{position} · {days} days remaining'**
  String incomePlannerWheelDueSummary(String position, int days);

  /// No description provided for @incomePlannerWheelExpiredSummary.
  ///
  /// In en, this message translates to:
  /// **'{position} · expired {days} days ago — record the outcome'**
  String incomePlannerWheelExpiredSummary(String position, int days);

  /// No description provided for @incomePlannerWheelRealizedIncome.
  ///
  /// In en, this message translates to:
  /// **'Realized net income'**
  String get incomePlannerWheelRealizedIncome;

  /// No description provided for @incomePlannerWheelOpenPositionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Open positions'**
  String get incomePlannerWheelOpenPositionsTitle;

  /// No description provided for @incomePlannerWheelExpirationMissing.
  ///
  /// In en, this message translates to:
  /// **'Expiration is missing · update this journal entry'**
  String get incomePlannerWheelExpirationMissing;

  /// No description provided for @incomePlannerWheelNextReviewOpen.
  ///
  /// In en, this message translates to:
  /// **'Review overlapping open positions and verify total exposure.'**
  String get incomePlannerWheelNextReviewOpen;

  /// No description provided for @incomePlannerWheelNextWaitPut.
  ///
  /// In en, this message translates to:
  /// **'Monitor the open put and record its outcome at expiration or close.'**
  String get incomePlannerWheelNextWaitPut;

  /// No description provided for @incomePlannerWheelNextRecordPut.
  ///
  /// In en, this message translates to:
  /// **'Record the put outcome before starting the next leg.'**
  String get incomePlannerWheelNextRecordPut;

  /// No description provided for @incomePlannerWheelNextScanCall.
  ///
  /// In en, this message translates to:
  /// **'Shares are held; scan for a covered call only if you are willing to sell.'**
  String get incomePlannerWheelNextScanCall;

  /// No description provided for @incomePlannerWheelNextWaitCall.
  ///
  /// In en, this message translates to:
  /// **'Monitor the covered call and record whether it expires, closes, or is assigned.'**
  String get incomePlannerWheelNextWaitCall;

  /// No description provided for @incomePlannerWheelNextRecordCall.
  ///
  /// In en, this message translates to:
  /// **'Record the call-away outcome and verify shares and cash.'**
  String get incomePlannerWheelNextRecordCall;

  /// No description provided for @incomePlannerWheelNextStartPut.
  ///
  /// In en, this message translates to:
  /// **'Cash is available; start a new put only for an approved underlying.'**
  String get incomePlannerWheelNextStartPut;

  /// Onboarding heading shown at first launch
  ///
  /// In en, this message translates to:
  /// **'Welcome to NaviWealth'**
  String get onboardingTitle;

  /// Onboarding sub-heading explaining the mode picker
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to use the app'**
  String get onboardingSubtitle;

  /// Onboarding card title: traditional account with sync
  ///
  /// In en, this message translates to:
  /// **'Cloud account'**
  String get onboardingCloudTitle;

  /// Onboarding cloud-account card body
  ///
  /// In en, this message translates to:
  /// **'Sync data across devices'**
  String get onboardingCloudDescription;

  /// Onboarding card title: no account, data stays on device
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get onboardingLocalOnlyTitle;

  /// Onboarding local-only card body
  ///
  /// In en, this message translates to:
  /// **'Data stays on this device, no sync'**
  String get onboardingLocalOnlyDescription;

  /// Account-section label shown to local-only users instead of an email
  ///
  /// In en, this message translates to:
  /// **'Local mode'**
  String get settingsAccountLocalOnlyBadge;

  /// Subtitle for the upgrade-to-cloud row.
  ///
  /// In en, this message translates to:
  /// **'Sync data across devices'**
  String get settingsUpgradeToCloudHint;

  /// Button for cloud users to downgrade to local-only mode.
  ///
  /// In en, this message translates to:
  /// **'Switch to Local Mode'**
  String get settingsSwitchToLocal;

  /// Confirmation dialog title for switching to local mode.
  ///
  /// In en, this message translates to:
  /// **'Switch to Local Mode?'**
  String get settingsSwitchToLocalConfirmTitle;

  /// Confirmation dialog body for switching to local mode.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync will be disabled. Your data will remain on this device but will no longer sync to other devices.'**
  String get settingsSwitchToLocalConfirmBody;

  /// Generic date field label
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get commonDate;

  /// Generic note field label
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get commonNote;

  /// Generic acknowledgement button label
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// HealthOS Today tab title
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get healthTodayTitle;

  /// Subtitle under the HealthOS Today greeting
  ///
  /// In en, this message translates to:
  /// **'Today\'s health overview'**
  String get healthTodayBriefSubtitle;

  /// No description provided for @healthTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get healthTrendTitle;

  /// No description provided for @healthPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get healthPlanTitle;

  /// No description provided for @healthTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get healthTabToday;

  /// No description provided for @healthTabTrend.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get healthTabTrend;

  /// No description provided for @healthTabPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get healthTabPlan;

  /// Collapsible Health Today sources section title
  ///
  /// In en, this message translates to:
  /// **'Data sources'**
  String get healthSourcesTitle;

  /// Collapsible Health Today sources section subtitle
  ///
  /// In en, this message translates to:
  /// **'HealthKit / Health Connect and Garmin'**
  String get healthSourcesSubtitle;

  /// Hint under empty metric values on Health Today
  ///
  /// In en, this message translates to:
  /// **'Open Sources below to sync or connect a device'**
  String get healthNoDataSyncHint;

  /// No description provided for @healthCommandToday.
  ///
  /// In en, this message translates to:
  /// **'Health · Today'**
  String get healthCommandToday;

  /// No description provided for @healthCommandTrend.
  ///
  /// In en, this message translates to:
  /// **'Health · Trends'**
  String get healthCommandTrend;

  /// No description provided for @healthCommandPlan.
  ///
  /// In en, this message translates to:
  /// **'Health · Plan'**
  String get healthCommandPlan;

  /// No description provided for @healthInputMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Input metrics'**
  String get healthInputMetricsTitle;

  /// No description provided for @healthConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get healthConfidenceLabel;

  /// No description provided for @healthConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get healthConfidenceLow;

  /// No description provided for @healthConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get healthConfidenceMedium;

  /// No description provided for @healthRecentHrvLabel.
  ///
  /// In en, this message translates to:
  /// **'HRV (recent average)'**
  String get healthRecentHrvLabel;

  /// No description provided for @healthRecentSleepLabel.
  ///
  /// In en, this message translates to:
  /// **'Sleep (recent average)'**
  String get healthRecentSleepLabel;

  /// No description provided for @healthRecentRhrLabel.
  ///
  /// In en, this message translates to:
  /// **'Resting heart rate (recent average)'**
  String get healthRecentRhrLabel;

  /// No description provided for @healthRecentVo2MaxLabel.
  ///
  /// In en, this message translates to:
  /// **'VO₂max (recent average)'**
  String get healthRecentVo2MaxLabel;

  /// No description provided for @healthSleepMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get healthSleepMetricLabel;

  /// No description provided for @healthHrvMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'HRV'**
  String get healthHrvMetricLabel;

  /// No description provided for @healthHeartRateMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Heart rate'**
  String get healthHeartRateMetricLabel;

  /// No description provided for @healthWorkoutMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get healthWorkoutMetricLabel;

  /// No description provided for @healthWorkoutDurationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String healthWorkoutDurationHoursMinutes(Object hours, Object minutes);

  /// No description provided for @healthWorkoutDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String healthWorkoutDurationMinutes(Object minutes);

  /// No description provided for @healthWeeklyWorkoutValue.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {count} workouts'**
  String healthWeeklyWorkoutValue(Object count, Object duration);

  /// No description provided for @healthStepsMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get healthStepsMetricLabel;

  /// No description provided for @healthEnergyMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get healthEnergyMetricLabel;

  /// No description provided for @healthLoadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get healthLoadingLabel;

  /// No description provided for @healthTrendGroupRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get healthTrendGroupRecovery;

  /// No description provided for @healthTrendGroupActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get healthTrendGroupActivity;

  /// No description provided for @healthTrendGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get healthTrendGroupBody;

  /// No description provided for @healthTrendLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String healthTrendLoadFailed(Object error);

  /// No description provided for @healthTrendNotEnoughData.
  ///
  /// In en, this message translates to:
  /// **'Not enough data yet.'**
  String get healthTrendNotEnoughData;

  /// No description provided for @healthTrendHrvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Heart-rate variability '**
  String get healthTrendHrvSubtitle;

  /// No description provided for @healthTrendSleepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nightly hours '**
  String get healthTrendSleepSubtitle;

  /// No description provided for @healthTrendHeartRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily average heart rate '**
  String get healthTrendHeartRateSubtitle;

  /// No description provided for @healthTrendRespiratoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Respiration'**
  String get healthTrendRespiratoryTitle;

  /// No description provided for @healthTrendRespiratorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily average respiratory rate '**
  String get healthTrendRespiratorySubtitle;

  /// No description provided for @healthTrendRhrTitle.
  ///
  /// In en, this message translates to:
  /// **'Resting HR'**
  String get healthTrendRhrTitle;

  /// No description provided for @healthTrendRhrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily resting heart rate '**
  String get healthTrendRhrSubtitle;

  /// No description provided for @healthTrendWorkoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily minutes '**
  String get healthTrendWorkoutSubtitle;

  /// No description provided for @healthTrendStepsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily steps '**
  String get healthTrendStepsSubtitle;

  /// No description provided for @healthTrendWalkingDistanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Walking distance'**
  String get healthTrendWalkingDistanceTitle;

  /// No description provided for @healthTrendWalkingDistanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily kilometers '**
  String get healthTrendWalkingDistanceSubtitle;

  /// No description provided for @healthTrendFlightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Flights climbed'**
  String get healthTrendFlightsTitle;

  /// No description provided for @healthTrendFlightsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily flights climbed '**
  String get healthTrendFlightsSubtitle;

  /// No description provided for @healthTrendWeightTitle.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get healthTrendWeightTitle;

  /// No description provided for @healthTrendWeightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Weight records '**
  String get healthTrendWeightSubtitle;

  /// No description provided for @healthTrendBodyFatTitle.
  ///
  /// In en, this message translates to:
  /// **'Body fat'**
  String get healthTrendBodyFatTitle;

  /// No description provided for @healthTrendBodyFatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Body fat percentage '**
  String get healthTrendBodyFatSubtitle;

  /// No description provided for @healthTrendVo2MaxTitle.
  ///
  /// In en, this message translates to:
  /// **'VO₂max'**
  String get healthTrendVo2MaxTitle;

  /// No description provided for @healthTrendVo2MaxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Max oxygen uptake '**
  String get healthTrendVo2MaxSubtitle;

  /// No description provided for @healthBodyBatteryMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Body Battery'**
  String get healthBodyBatteryMetricLabel;

  /// No description provided for @healthStressMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Stress'**
  String get healthStressMetricLabel;

  /// No description provided for @healthRhrMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'RHR'**
  String get healthRhrMetricLabel;

  /// No description provided for @healthTrainingLoadMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get healthTrainingLoadMetricLabel;

  /// No description provided for @healthSleepDeepLabel.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get healthSleepDeepLabel;

  /// No description provided for @healthSleepRemLabel.
  ///
  /// In en, this message translates to:
  /// **'REM'**
  String get healthSleepRemLabel;

  /// No description provided for @healthSleepLightLabel.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get healthSleepLightLabel;

  /// No description provided for @healthSleepAwakeLabel.
  ///
  /// In en, this message translates to:
  /// **'Awake'**
  String get healthSleepAwakeLabel;

  /// No description provided for @healthTrendBodyBatteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Battery'**
  String get healthTrendBodyBatteryTitle;

  /// No description provided for @healthTrendBodyBatterySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily max level'**
  String get healthTrendBodyBatterySubtitle;

  /// No description provided for @healthTrendStressTitle.
  ///
  /// In en, this message translates to:
  /// **'Stress'**
  String get healthTrendStressTitle;

  /// No description provided for @healthTrendStressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily average level '**
  String get healthTrendStressSubtitle;

  /// No description provided for @healthTrendTrainingLoadTitle.
  ///
  /// In en, this message translates to:
  /// **'Training load'**
  String get healthTrendTrainingLoadTitle;

  /// No description provided for @healthTrendTrainingLoadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly training load'**
  String get healthTrendTrainingLoadSubtitle;

  /// No description provided for @healthTrendTrainingEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Training effect'**
  String get healthTrendTrainingEffectTitle;

  /// No description provided for @healthTrendTrainingEffectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fitness improvement signal'**
  String get healthTrendTrainingEffectSubtitle;

  /// No description provided for @healthWeeklySummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly status'**
  String get healthWeeklySummaryTitle;

  /// No description provided for @healthWeeklySummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Key health signals from the last 7 days'**
  String get healthWeeklySummarySubtitle;

  /// No description provided for @healthWeeklySummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Sync a few days of data to summarize steps, sleep, training, and recovery here.'**
  String get healthWeeklySummaryEmpty;

  /// No description provided for @healthSpo2MetricLabel.
  ///
  /// In en, this message translates to:
  /// **'SpO₂'**
  String get healthSpo2MetricLabel;

  /// No description provided for @healthTrendSpo2Title.
  ///
  /// In en, this message translates to:
  /// **'Blood oxygen'**
  String get healthTrendSpo2Title;

  /// No description provided for @healthTrendSpo2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily average SpO₂'**
  String get healthTrendSpo2Subtitle;

  /// No description provided for @healthTrendTotalEnergyTitle.
  ///
  /// In en, this message translates to:
  /// **'Total energy'**
  String get healthTrendTotalEnergyTitle;

  /// No description provided for @healthTrendTotalEnergySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily total calories burned'**
  String get healthTrendTotalEnergySubtitle;

  /// No description provided for @healthKitTitle.
  ///
  /// In en, this message translates to:
  /// **'HealthKit / Health Connect'**
  String get healthKitTitle;

  /// No description provided for @healthSyncAction.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get healthSyncAction;

  /// No description provided for @healthSyncPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get healthSyncPermissionDenied;

  /// No description provided for @healthSyncingData.
  ///
  /// In en, this message translates to:
  /// **'Syncing health data…'**
  String get healthSyncingData;

  /// No description provided for @healthSyncReady.
  ///
  /// In en, this message translates to:
  /// **'Sync last 30 days of health data'**
  String get healthSyncReady;

  /// No description provided for @healthSyncResult.
  ///
  /// In en, this message translates to:
  /// **'Synced {upserted} new · {unchanged} unchanged'**
  String healthSyncResult(Object unchanged, Object upserted);

  /// No description provided for @healthSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get healthSyncFailed;

  /// No description provided for @healthSourceChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking connection…'**
  String get healthSourceChecking;

  /// No description provided for @healthSourceReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get healthSourceReady;

  /// No description provided for @healthSourcePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get healthSourcePermissionRequired;

  /// No description provided for @healthSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get healthSourceUnavailable;

  /// No description provided for @healthSourceSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get healthSourceSyncFailed;

  /// No description provided for @healthSourceLastSync.
  ///
  /// In en, this message translates to:
  /// **'Synced {time}'**
  String healthSourceLastSync(String time);

  /// No description provided for @healthSourceLastAttempt.
  ///
  /// In en, this message translates to:
  /// **'Tried {time}'**
  String healthSourceLastAttempt(String time);

  /// No description provided for @healthSourceLastSuccess.
  ///
  /// In en, this message translates to:
  /// **'Last success {time}'**
  String healthSourceLastSuccess(String time);

  /// No description provided for @healthSourceDataAt.
  ///
  /// In en, this message translates to:
  /// **'Data {time}'**
  String healthSourceDataAt(String time);

  /// No description provided for @healthSourceNoData.
  ///
  /// In en, this message translates to:
  /// **'No data imported yet'**
  String get healthSourceNoData;

  /// No description provided for @healthSyncButton.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get healthSyncButton;

  /// No description provided for @healthSyncingButton.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get healthSyncingButton;

  /// No description provided for @healthRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Recovery'**
  String get healthRecoveryTitle;

  /// No description provided for @healthRecoveryRested.
  ///
  /// In en, this message translates to:
  /// **'Rested'**
  String get healthRecoveryRested;

  /// No description provided for @healthRecoveryBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get healthRecoveryBalanced;

  /// No description provided for @healthRecoveryStrained.
  ///
  /// In en, this message translates to:
  /// **'Strained'**
  String get healthRecoveryStrained;

  /// No description provided for @healthRecoveryInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient data'**
  String get healthRecoveryInsufficient;

  /// No description provided for @healthRecoveryRestedTip.
  ///
  /// In en, this message translates to:
  /// **'Schedule high-intensity training or deep-focus work today.'**
  String get healthRecoveryRestedTip;

  /// No description provided for @healthRecoveryBalancedTip.
  ///
  /// In en, this message translates to:
  /// **'Maintain your usual pace — don\'t push to the limit.'**
  String get healthRecoveryBalancedTip;

  /// No description provided for @healthRecoveryStrainedTip.
  ///
  /// In en, this message translates to:
  /// **'Light activity, extra sleep. Avoid stacking pressure.'**
  String get healthRecoveryStrainedTip;

  /// No description provided for @healthRecoveryInsufficientTip.
  ///
  /// In en, this message translates to:
  /// **'Sync data and track for a few days for stable recovery advice.'**
  String get healthRecoveryInsufficientTip;

  /// No description provided for @agentResultUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String agentResultUpdated(String time);

  /// No description provided for @healthNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get healthNoData;

  /// No description provided for @healthShowAllMetrics.
  ///
  /// In en, this message translates to:
  /// **'Show all metrics'**
  String get healthShowAllMetrics;

  /// No description provided for @healthShowKeyMetrics.
  ///
  /// In en, this message translates to:
  /// **'Show key metrics'**
  String get healthShowKeyMetrics;

  /// Health Today: reveal compact secondary metrics
  ///
  /// In en, this message translates to:
  /// **'More · {count}'**
  String healthMoreMetrics(int count);

  /// Health Today: collapse secondary metrics
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get healthCollapseMetrics;

  /// Health recovery hero: expand plan action list
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get healthMorePlanActions;

  /// Health recovery hero: collapse plan action list
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get healthCollapsePlanActions;

  /// No description provided for @healthPlanTodayActions.
  ///
  /// In en, this message translates to:
  /// **'Today\'s actions'**
  String get healthPlanTodayActions;

  /// No description provided for @healthPlanHighIntensity.
  ///
  /// In en, this message translates to:
  /// **'Schedule high-intensity training or deep-focus work.'**
  String get healthPlanHighIntensity;

  /// No description provided for @healthPlanKeepSleep.
  ///
  /// In en, this message translates to:
  /// **'Keep normal sleep window; avoid overdrawing.'**
  String get healthPlanKeepSleep;

  /// No description provided for @healthPlanTrainAsPlanned.
  ///
  /// In en, this message translates to:
  /// **'Train as planned, keep 10-20% headroom.'**
  String get healthPlanTrainAsPlanned;

  /// No description provided for @healthPlanReduceCaffeine.
  ///
  /// In en, this message translates to:
  /// **'Cut afternoon caffeine; protect evening recovery.'**
  String get healthPlanReduceCaffeine;

  /// No description provided for @healthPlanLightActivity.
  ///
  /// In en, this message translates to:
  /// **'Switch to walking, stretching, or Zone 2.'**
  String get healthPlanLightActivity;

  /// No description provided for @healthPlanAvoidPressure.
  ///
  /// In en, this message translates to:
  /// **'Avoid back-to-back high-pressure meetings and evening training.'**
  String get healthPlanAvoidPressure;

  /// No description provided for @healthPlanSyncFirst.
  ///
  /// In en, this message translates to:
  /// **'Sync Health Connect data first.'**
  String get healthPlanSyncFirst;

  /// No description provided for @healthPlanTrackMore.
  ///
  /// In en, this message translates to:
  /// **'Track for a few more days before judging trends.'**
  String get healthPlanTrackMore;

  /// No description provided for @healthPlanEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Enable HealthOS in Settings → Domains to see recovery advice.'**
  String get healthPlanEnableHint;

  /// Title for the collapsible Health Plan disclaimer banner.
  ///
  /// In en, this message translates to:
  /// **'Health guidance only'**
  String get healthPlanDisclaimerTitle;

  /// No description provided for @healthPlanDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Not a medical diagnosis. HealthOS does not auto-adjust your schedule.'**
  String get healthPlanDisclaimer;

  /// Header action semantics for recording a body metric
  ///
  /// In en, this message translates to:
  /// **'Record body metric'**
  String get healthRecordBodyMetricAction;

  /// Body measurement entry sheet title
  ///
  /// In en, this message translates to:
  /// **'Record body metric'**
  String get healthBodyMeasurementTitle;

  /// Body measurement entry sheet subtitle
  ///
  /// In en, this message translates to:
  /// **'For low-frequency manual metrics like weight and body fat'**
  String get healthBodyMeasurementSubtitle;

  /// Weight metric label
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get healthMetricWeight;

  /// Body fat metric label
  ///
  /// In en, this message translates to:
  /// **'Body fat'**
  String get healthMetricBodyFat;

  /// Helper text for weight input
  ///
  /// In en, this message translates to:
  /// **'Unit: kg'**
  String get healthBodyMeasurementWeightHelper;

  /// Helper text for body fat input
  ///
  /// In en, this message translates to:
  /// **'Unit: %, for example 18.5'**
  String get healthBodyMeasurementBodyFatHelper;

  /// Validation error for body fat input
  ///
  /// In en, this message translates to:
  /// **'Body fat cannot exceed 100%'**
  String get healthBodyFatMaxError;

  /// Toast shown when saving a manual health metric fails
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String healthBodyMeasurementSaveFailed(String error);

  /// KnowledgeOS Inbox tab title
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get knowledgeInboxTitle;

  /// No description provided for @knowledgeInboxSuggestionsPending.
  ///
  /// In en, this message translates to:
  /// **'{count} AI suggestions are ready for review'**
  String knowledgeInboxSuggestionsPending(int count);

  /// No description provided for @knowledgeInboxSuggestionsLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking asynchronous AI suggestions…'**
  String get knowledgeInboxSuggestionsLoading;

  /// No description provided for @knowledgeInboxSuggestionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Organization status failed to load. Tap to retry.'**
  String get knowledgeInboxSuggestionsLoadFailed;

  /// No description provided for @knowledgeInboxAiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Notes save normally. Configure a device LLM to receive asynchronous classification and tag suggestions.'**
  String get knowledgeInboxAiUnavailable;

  /// No description provided for @knowledgeTabInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get knowledgeTabInbox;

  /// No description provided for @knowledgeTabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get knowledgeTabLibrary;

  /// No description provided for @knowledgeTabReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get knowledgeTabReview;

  /// No description provided for @knowledgeCommandInbox.
  ///
  /// In en, this message translates to:
  /// **'Knowledge · Inbox'**
  String get knowledgeCommandInbox;

  /// No description provided for @knowledgeCommandLibrary.
  ///
  /// In en, this message translates to:
  /// **'Knowledge · Library'**
  String get knowledgeCommandLibrary;

  /// No description provided for @knowledgeCommandReview.
  ///
  /// In en, this message translates to:
  /// **'Knowledge · Review'**
  String get knowledgeCommandReview;

  /// No description provided for @knowledgeProposalCaptureUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Capture upgrade'**
  String get knowledgeProposalCaptureUpgrade;

  /// No description provided for @knowledgeProposalMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge duplicates'**
  String get knowledgeProposalMerge;

  /// No description provided for @knowledgeProposalRoutine.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get knowledgeProposalRoutine;

  /// No description provided for @knowledgeProposalConceptLink.
  ///
  /// In en, this message translates to:
  /// **'Concept link'**
  String get knowledgeProposalConceptLink;

  /// No description provided for @knowledgeProposalRowType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get knowledgeProposalRowType;

  /// No description provided for @knowledgeProposalRowContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get knowledgeProposalRowContent;

  /// No description provided for @knowledgeProposalRowScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get knowledgeProposalRowScope;

  /// No description provided for @knowledgeProposalRowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get knowledgeProposalRowConfidence;

  /// No description provided for @knowledgeProposalRowLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get knowledgeProposalRowLink;

  /// No description provided for @knowledgeProposalRowRelation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get knowledgeProposalRowRelation;

  /// No description provided for @knowledgeProposalRowKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get knowledgeProposalRowKeep;

  /// No description provided for @knowledgeProposalRowSoftMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge (soft delete)'**
  String get knowledgeProposalRowSoftMerge;

  /// No description provided for @knowledgeProposalRowMergedTags.
  ///
  /// In en, this message translates to:
  /// **'Merged tags'**
  String get knowledgeProposalRowMergedTags;

  /// No description provided for @knowledgeProposalRowItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get knowledgeProposalRowItem;

  /// No description provided for @knowledgeProposalRowInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get knowledgeProposalRowInterval;

  /// No description provided for @knowledgeProposalIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Every {days} days'**
  String knowledgeProposalIntervalDays(int days);

  /// No description provided for @knowledgeInboxEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox is empty'**
  String get knowledgeInboxEmptyTitle;

  /// No description provided for @knowledgeInboxEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Capture the thought first. KnowledgeOS organizes it in the background, and you approve every upgrade.'**
  String get knowledgeInboxEmptyBody;

  /// No description provided for @knowledgeInboxLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox failed to load'**
  String get knowledgeInboxLoadFailedTitle;

  /// Button label for creating a knowledge capture
  ///
  /// In en, this message translates to:
  /// **'New capture'**
  String get knowledgeCaptureAction;

  /// Title for the knowledge type picker bottom sheet
  ///
  /// In en, this message translates to:
  /// **'New Entry'**
  String get knowledgeCreateEntry;

  /// No description provided for @knowledgeCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Capture a thought'**
  String get knowledgeCaptureTitle;

  /// No description provided for @knowledgeCaptureDraftRecovered.
  ///
  /// In en, this message translates to:
  /// **'Recovered your unfinished capture from this device.'**
  String get knowledgeCaptureDraftRecovered;

  /// No description provided for @knowledgeCaptureDraftDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get knowledgeCaptureDraftDiscard;

  /// No description provided for @knowledgeCaptureDraftCleared.
  ///
  /// In en, this message translates to:
  /// **'Draft cleared'**
  String get knowledgeCaptureDraftCleared;

  /// No description provided for @knowledgeCaptureTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get knowledgeCaptureTitleField;

  /// No description provided for @knowledgeCaptureBodyField.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get knowledgeCaptureBodyField;

  /// No description provided for @knowledgeCaptureTitleHint.
  ///
  /// In en, this message translates to:
  /// **'\"Bank card needs regular activity\"'**
  String get knowledgeCaptureTitleHint;

  /// No description provided for @knowledgeCaptureBodyHint.
  ///
  /// In en, this message translates to:
  /// **'\"Make one bank-card activity transaction every 6 months, otherwise it may become dormant\"'**
  String get knowledgeCaptureBodyHint;

  /// No description provided for @knowledgeCaptureSavedClassifyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved · AI is analyzing'**
  String get knowledgeCaptureSavedClassifyingTitle;

  /// No description provided for @knowledgeCaptureSavedPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved capture'**
  String get knowledgeCaptureSavedPreviewTitle;

  /// No description provided for @knowledgeCaptureSuggestionTitle.
  ///
  /// In en, this message translates to:
  /// **'AI suggestion'**
  String get knowledgeCaptureSuggestionTitle;

  /// No description provided for @knowledgeCaptureComposeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Write naturally. AI can shape the title and Markdown before anything is saved.'**
  String get knowledgeCaptureComposeSubtitle;

  /// No description provided for @knowledgeCaptureClassifyingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The note is saved. AI is checking whether it should become a routine, decision, or another type of knowledge.'**
  String get knowledgeCaptureClassifyingSubtitle;

  /// No description provided for @knowledgeCaptureSuggestionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review the extracted type and fields before applying.'**
  String get knowledgeCaptureSuggestionSubtitle;

  /// No description provided for @knowledgeCaptureTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get knowledgeCaptureTypeLabel;

  /// No description provided for @knowledgeCaptureKindAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get knowledgeCaptureKindAuto;

  /// No description provided for @knowledgeCaptureKindAutoDescription.
  ///
  /// In en, this message translates to:
  /// **'Let KnowledgeOS classify it after saving'**
  String get knowledgeCaptureKindAutoDescription;

  /// No description provided for @knowledgeCaptureKindNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get knowledgeCaptureKindNote;

  /// No description provided for @knowledgeCaptureKindRoutine.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get knowledgeCaptureKindRoutine;

  /// No description provided for @knowledgeCaptureKindDecision.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get knowledgeCaptureKindDecision;

  /// No description provided for @knowledgeCaptureKindAssumption.
  ///
  /// In en, this message translates to:
  /// **'Assumption'**
  String get knowledgeCaptureKindAssumption;

  /// No description provided for @knowledgeCaptureKindPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Principle'**
  String get knowledgeCaptureKindPrinciple;

  /// No description provided for @knowledgeCaptureKindConcept.
  ///
  /// In en, this message translates to:
  /// **'Concept'**
  String get knowledgeCaptureKindConcept;

  /// No description provided for @knowledgeCaptureKindExperiment.
  ///
  /// In en, this message translates to:
  /// **'Experiment'**
  String get knowledgeCaptureKindExperiment;

  /// No description provided for @knowledgeCaptureSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get knowledgeCaptureSave;

  /// No description provided for @knowledgeCaptureSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Saved to Inbox. Classification and links will be suggested in the background.'**
  String get knowledgeCaptureSavedToast;

  /// No description provided for @knowledgeCaptureOrganizeAction.
  ///
  /// In en, this message translates to:
  /// **'Organize & preview'**
  String get knowledgeCaptureOrganizeAction;

  /// No description provided for @knowledgeCaptureOrganizing.
  ///
  /// In en, this message translates to:
  /// **'Organizing...'**
  String get knowledgeCaptureOrganizing;

  /// No description provided for @knowledgeCaptureOrganizingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI is shaping the title, hierarchy, and Markdown while preserving your meaning.'**
  String get knowledgeCaptureOrganizingSubtitle;

  /// No description provided for @knowledgeCaptureOrganizingBody.
  ///
  /// In en, this message translates to:
  /// **'Creating a complete, readable draft. Your original remains unchanged until you approve it.'**
  String get knowledgeCaptureOrganizingBody;

  /// No description provided for @knowledgeCaptureOrganizedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review the rendered result, or switch to Edit for final adjustments before saving.'**
  String get knowledgeCaptureOrganizedSubtitle;

  /// No description provided for @knowledgeCaptureAiOrganizationHint.
  ///
  /// In en, this message translates to:
  /// **'AI will improve the title, structure, and reading flow without adding new facts.'**
  String get knowledgeCaptureAiOrganizationHint;

  /// No description provided for @knowledgeCaptureSaveWithoutAi.
  ///
  /// In en, this message translates to:
  /// **'Save original'**
  String get knowledgeCaptureSaveWithoutAi;

  /// No description provided for @knowledgeCaptureSaveOrganized.
  ///
  /// In en, this message translates to:
  /// **'Save organized note'**
  String get knowledgeCaptureSaveOrganized;

  /// No description provided for @knowledgeCaptureReviewDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Organized draft'**
  String get knowledgeCaptureReviewDraftTitle;

  /// No description provided for @knowledgeCaptureReviewDraftSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Preview first; every field remains editable.'**
  String get knowledgeCaptureReviewDraftSubtitle;

  /// No description provided for @knowledgeCaptureOriginalVersion.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get knowledgeCaptureOriginalVersion;

  /// No description provided for @knowledgeCaptureOrganizedVersion.
  ///
  /// In en, this message translates to:
  /// **'AI-organized draft'**
  String get knowledgeCaptureOrganizedVersion;

  /// No description provided for @knowledgeCaptureShowOriginal.
  ///
  /// In en, this message translates to:
  /// **'View original'**
  String get knowledgeCaptureShowOriginal;

  /// No description provided for @knowledgeCaptureShowOrganized.
  ///
  /// In en, this message translates to:
  /// **'View organized'**
  String get knowledgeCaptureShowOrganized;

  /// No description provided for @knowledgeCaptureUntitledOriginal.
  ///
  /// In en, this message translates to:
  /// **'Untitled original'**
  String get knowledgeCaptureUntitledOriginal;

  /// No description provided for @knowledgeCaptureOrganizeFailed.
  ///
  /// In en, this message translates to:
  /// **'AI could not produce a safe complete draft. Your original is unchanged.'**
  String get knowledgeCaptureOrganizeFailed;

  /// Submit button when the user manually chooses a capture kind
  ///
  /// In en, this message translates to:
  /// **'Save as {kind}'**
  String knowledgeCaptureSaveTyped(String kind);

  /// No description provided for @knowledgeCaptureSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get knowledgeCaptureSaving;

  /// No description provided for @knowledgeCaptureCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get knowledgeCaptureCancel;

  /// No description provided for @knowledgeCaptureClassifyingBody.
  ///
  /// In en, this message translates to:
  /// **'Reasoning can take 20-30 seconds. The Note is already saved, so you can skip waiting.'**
  String get knowledgeCaptureClassifyingBody;

  /// No description provided for @knowledgeCaptureSkipClassification.
  ///
  /// In en, this message translates to:
  /// **'Keep as Note'**
  String get knowledgeCaptureSkipClassification;

  /// No description provided for @knowledgeCaptureApplySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Apply suggestion'**
  String get knowledgeCaptureApplySuggestion;

  /// No description provided for @knowledgeCaptureApplyPolish.
  ///
  /// In en, this message translates to:
  /// **'Apply polish'**
  String get knowledgeCaptureApplyPolish;

  /// No description provided for @knowledgeCaptureApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying...'**
  String get knowledgeCaptureApplying;

  /// No description provided for @knowledgeCaptureKeepOriginal.
  ///
  /// In en, this message translates to:
  /// **'Keep original'**
  String get knowledgeCaptureKeepOriginal;

  /// No description provided for @knowledgeCaptureNotePolishOnly.
  ///
  /// In en, this message translates to:
  /// **'AI classified this as a note, so it will only polish the text. Reason: {reason}'**
  String knowledgeCaptureNotePolishOnly(Object reason);

  /// No description provided for @knowledgeCapturePolishedVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Review organized note'**
  String get knowledgeCapturePolishedVersionTitle;

  /// No description provided for @knowledgeCaptureTitleDiffLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get knowledgeCaptureTitleDiffLabel;

  /// No description provided for @knowledgeCaptureBodyDiffLabel.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get knowledgeCaptureBodyDiffLabel;

  /// No description provided for @knowledgeCaptureEmptyValue.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get knowledgeCaptureEmptyValue;

  /// No description provided for @knowledgeCaptureOriginalDiffValue.
  ///
  /// In en, this message translates to:
  /// **'Original: {value}'**
  String knowledgeCaptureOriginalDiffValue(Object value);

  /// No description provided for @knowledgeCaptureKindRoutineDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like a recurring item'**
  String get knowledgeCaptureKindRoutineDescription;

  /// No description provided for @knowledgeCaptureKindDecisionDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like it weighs options'**
  String get knowledgeCaptureKindDecisionDescription;

  /// No description provided for @knowledgeCaptureKindAssumptionDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like it states a belief'**
  String get knowledgeCaptureKindAssumptionDescription;

  /// No description provided for @knowledgeCaptureKindPrincipleDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like it states a principle'**
  String get knowledgeCaptureKindPrincipleDescription;

  /// No description provided for @knowledgeCaptureKindConceptDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like it defines a concept'**
  String get knowledgeCaptureKindConceptDescription;

  /// No description provided for @knowledgeCaptureKindExperimentDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like it describes an experiment'**
  String get knowledgeCaptureKindExperimentDescription;

  /// No description provided for @knowledgeCaptureKindNoteDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep as Note'**
  String get knowledgeCaptureKindNoteDescription;

  /// No description provided for @knowledgeCaptureRoutineUpgradeDetail.
  ///
  /// In en, this message translates to:
  /// **'Will create a Routine: \"{statement}\", every {intervalDays} days'**
  String knowledgeCaptureRoutineUpgradeDetail(
    Object intervalDays,
    Object statement,
  );

  /// No description provided for @knowledgeCaptureRoutineScopeDetail.
  ///
  /// In en, this message translates to:
  /// **'Scope = {scope}.'**
  String knowledgeCaptureRoutineScopeDetail(Object scope);

  /// No description provided for @knowledgeCaptureRoutineReminderDetail.
  ///
  /// In en, this message translates to:
  /// **'AI will remind you 7 days before it is due.'**
  String get knowledgeCaptureRoutineReminderDetail;

  /// No description provided for @knowledgeCaptureSuggestionReasonConfidence.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason} · confidence {confidence}'**
  String knowledgeCaptureSuggestionReasonConfidence(
    Object confidence,
    Object reason,
  );

  /// No description provided for @knowledgeCaptureSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Capture failed: {error}'**
  String knowledgeCaptureSaveFailed(Object error);

  /// No description provided for @knowledgeCaptureApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply suggestion: {error}'**
  String knowledgeCaptureApplyFailed(Object error);

  /// Placeholder in the KnowledgeOS AI prompt bar
  ///
  /// In en, this message translates to:
  /// **'Ask or search your knowledge...'**
  String get knowledgeAiPromptHint;

  /// No description provided for @knowledgeAiAskAction.
  ///
  /// In en, this message translates to:
  /// **'Ask KnowledgeOS'**
  String get knowledgeAiAskAction;

  /// Knowledge AI quick action: deduplicate notes
  ///
  /// In en, this message translates to:
  /// **'Deduplicate'**
  String get knowledgeAiDedupeAction;

  /// Prefill prompt for deduplicating knowledge items
  ///
  /// In en, this message translates to:
  /// **'Check whether my knowledge base has similar or duplicate notes or concepts, and suggest merges where useful.'**
  String get knowledgeAiDedupePrompt;

  /// Knowledge AI quick action: weekly review
  ///
  /// In en, this message translates to:
  /// **'Weekly review'**
  String get knowledgeAiWeeklyAction;

  /// Prefill prompt for weekly knowledge review
  ///
  /// In en, this message translates to:
  /// **'Give me this week\'s knowledge review: decisions due for review, stale assumptions, routines due this week, and orphan notes without tags or links.'**
  String get knowledgeAiWeeklyPrompt;

  /// Knowledge AI quick action: search
  ///
  /// In en, this message translates to:
  /// **'Search knowledge'**
  String get knowledgeAiSearchAction;

  /// Prefill prompt for searching knowledge
  ///
  /// In en, this message translates to:
  /// **'Search my knowledge base: '**
  String get knowledgeAiSearchPrompt;

  /// KnowledgeOS Library tab title
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get knowledgeLibraryTitle;

  /// No description provided for @knowledgeLibrarySelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select an item to keep browsing while you read'**
  String get knowledgeLibrarySelectItem;

  /// No description provided for @knowledgeLibraryEmptyAllTitle.
  ///
  /// In en, this message translates to:
  /// **'No knowledge yet'**
  String get knowledgeLibraryEmptyAllTitle;

  /// No description provided for @knowledgeLibraryEmptyAllBody.
  ///
  /// In en, this message translates to:
  /// **'Capture a quick note, or create a structured Decision or Assumption.'**
  String get knowledgeLibraryEmptyAllBody;

  /// No description provided for @knowledgeLibraryEmptyDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Decisions yet'**
  String get knowledgeLibraryEmptyDecisionsTitle;

  /// No description provided for @knowledgeLibraryEmptyDecisionsBody.
  ///
  /// In en, this message translates to:
  /// **'Use the create action to record the first decision worth reviewing.'**
  String get knowledgeLibraryEmptyDecisionsBody;

  /// No description provided for @knowledgeLibraryEmptyPrinciplesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Principles yet'**
  String get knowledgeLibraryEmptyPrinciplesTitle;

  /// No description provided for @knowledgeLibraryEmptyPrinciplesBody.
  ///
  /// In en, this message translates to:
  /// **'Use Principles for durable worldview rules that guide decisions.'**
  String get knowledgeLibraryEmptyPrinciplesBody;

  /// No description provided for @knowledgeLibraryEmptyAssumptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Assumptions yet'**
  String get knowledgeLibraryEmptyAssumptionsTitle;

  /// No description provided for @knowledgeLibraryEmptyAssumptionsBody.
  ///
  /// In en, this message translates to:
  /// **'Use Assumptions for falsifiable beliefs with confidence and review cadence.'**
  String get knowledgeLibraryEmptyAssumptionsBody;

  /// No description provided for @knowledgeLibraryEmptyNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Notes in the library yet'**
  String get knowledgeLibraryEmptyNotesTitle;

  /// No description provided for @knowledgeLibraryEmptyNotesBody.
  ///
  /// In en, this message translates to:
  /// **'Capture a note, then let KnowledgeOS suggest tags, links, or an upgrade.'**
  String get knowledgeLibraryEmptyNotesBody;

  /// No description provided for @knowledgeLibraryEmptyConceptsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Concept nodes yet'**
  String get knowledgeLibraryEmptyConceptsTitle;

  /// No description provided for @knowledgeLibraryEmptyConceptsBody.
  ///
  /// In en, this message translates to:
  /// **'Concepts power [[soft links]] and AI associations.'**
  String get knowledgeLibraryEmptyConceptsBody;

  /// No description provided for @knowledgeLibraryEmptyExperimentsTitle.
  ///
  /// In en, this message translates to:
  /// **'No active Experiments'**
  String get knowledgeLibraryEmptyExperimentsTitle;

  /// No description provided for @knowledgeLibraryEmptyExperimentsBody.
  ///
  /// In en, this message translates to:
  /// **'Experiments usually attach to an Assumption that needs validation.'**
  String get knowledgeLibraryEmptyExperimentsBody;

  /// No description provided for @knowledgeLibraryEmptyRoutinesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Routines yet'**
  String get knowledgeLibraryEmptyRoutinesTitle;

  /// No description provided for @knowledgeLibraryEmptyRoutinesBody.
  ///
  /// In en, this message translates to:
  /// **'Recurring reminders. After you create one, AI can surface it near the next due date.'**
  String get knowledgeLibraryEmptyRoutinesBody;

  /// No description provided for @knowledgeRoutineOverdueDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days overdue'**
  String knowledgeRoutineOverdueDays(Object days);

  /// No description provided for @knowledgeRoutineDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get knowledgeRoutineDueToday;

  /// No description provided for @knowledgeRoutineDueInDays.
  ///
  /// In en, this message translates to:
  /// **'Due in {days} days'**
  String knowledgeRoutineDueInDays(Object days);

  /// No description provided for @knowledgeRoutineLibraryMeta.
  ///
  /// In en, this message translates to:
  /// **'{dueLabel} · every {intervalDays} days · {scope}'**
  String knowledgeRoutineLibraryMeta(
    Object dueLabel,
    Object intervalDays,
    Object scope,
  );

  /// No description provided for @knowledgeLibrarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search this segment'**
  String get knowledgeLibrarySearchHint;

  /// No description provided for @knowledgeLibrarySearchSegmentHint.
  ///
  /// In en, this message translates to:
  /// **'Search {segment}'**
  String knowledgeLibrarySearchSegmentHint(Object segment);

  /// No description provided for @knowledgeLibraryTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge type'**
  String get knowledgeLibraryTypeTitle;

  /// No description provided for @knowledgeLibraryTypePickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what to browse in your library.'**
  String get knowledgeLibraryTypePickerSubtitle;

  /// No description provided for @knowledgeLibraryTypeScope.
  ///
  /// In en, this message translates to:
  /// **'{type} · {count} items'**
  String knowledgeLibraryTypeScope(String type, int count);

  /// No description provided for @knowledgeLibraryTypeGroupCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get knowledgeLibraryTypeGroupCore;

  /// No description provided for @knowledgeLibraryTypeGroupSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get knowledgeLibraryTypeGroupSources;

  /// No description provided for @knowledgeLibraryTypeGroupThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get knowledgeLibraryTypeGroupThinking;

  /// No description provided for @knowledgeLibraryTypeGroupAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get knowledgeLibraryTypeGroupAction;

  /// No description provided for @knowledgeLibraryTypeAllDescription.
  ///
  /// In en, this message translates to:
  /// **'Browse every knowledge object'**
  String get knowledgeLibraryTypeAllDescription;

  /// No description provided for @knowledgeLibraryTypeDecisionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Record choices, rationale, and outcomes'**
  String get knowledgeLibraryTypeDecisionsDescription;

  /// No description provided for @knowledgeLibraryTypePrinciplesDescription.
  ///
  /// In en, this message translates to:
  /// **'Durable rules that guide judgment'**
  String get knowledgeLibraryTypePrinciplesDescription;

  /// No description provided for @knowledgeLibraryTypeAssumptionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Beliefs that still need validation'**
  String get knowledgeLibraryTypeAssumptionsDescription;

  /// No description provided for @knowledgeLibraryTypeNotesDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep raw observations and sources'**
  String get knowledgeLibraryTypeNotesDescription;

  /// No description provided for @knowledgeLibraryTypeConceptsDescription.
  ///
  /// In en, this message translates to:
  /// **'Organize topics, aliases, and links'**
  String get knowledgeLibraryTypeConceptsDescription;

  /// No description provided for @knowledgeLibraryTypeExperimentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Validate assumptions through action'**
  String get knowledgeLibraryTypeExperimentsDescription;

  /// No description provided for @knowledgeLibraryTypeRoutinesDescription.
  ///
  /// In en, this message translates to:
  /// **'Repeat actions on a cadence'**
  String get knowledgeLibraryTypeRoutinesDescription;

  /// No description provided for @knowledgeLibraryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get knowledgeLibraryFilterAll;

  /// No description provided for @knowledgeLibraryFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get knowledgeLibraryFilterTitle;

  /// No description provided for @knowledgeLibrarySearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get knowledgeLibrarySearchClear;

  /// No description provided for @knowledgeLibraryItemActions.
  ///
  /// In en, this message translates to:
  /// **'Knowledge item actions'**
  String get knowledgeLibraryItemActions;

  /// No description provided for @knowledgeItemOrganize.
  ///
  /// In en, this message translates to:
  /// **'AI organize'**
  String get knowledgeItemOrganize;

  /// No description provided for @knowledgeItemLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get knowledgeItemLink;

  /// No description provided for @knowledgeRelationSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Link related knowledge'**
  String get knowledgeRelationSheetTitle;

  /// No description provided for @knowledgeRelationSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search knowledge'**
  String get knowledgeRelationSearchHint;

  /// No description provided for @knowledgeRelationNoTargets.
  ///
  /// In en, this message translates to:
  /// **'Everything available is already linked'**
  String get knowledgeRelationNoTargets;

  /// No description provided for @knowledgeRelationLinkedToast.
  ///
  /// In en, this message translates to:
  /// **'Linked to {title}'**
  String knowledgeRelationLinkedToast(Object title);

  /// No description provided for @knowledgeRelationLinkedTitle.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get knowledgeRelationLinkedTitle;

  /// No description provided for @knowledgeRelationAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Available knowledge'**
  String get knowledgeRelationAvailableTitle;

  /// No description provided for @knowledgeRelationRemoveLink.
  ///
  /// In en, this message translates to:
  /// **'{kind} · Remove link'**
  String knowledgeRelationRemoveLink(Object kind);

  /// No description provided for @knowledgeRelationUnlinkedToast.
  ///
  /// In en, this message translates to:
  /// **'Removed link to {title}'**
  String knowledgeRelationUnlinkedToast(Object title);

  /// No description provided for @knowledgeItemReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get knowledgeItemReview;

  /// No description provided for @knowledgeItemPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get knowledgeItemPause;

  /// No description provided for @knowledgeItemResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get knowledgeItemResume;

  /// No description provided for @knowledgeItemCopySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy summary'**
  String get knowledgeItemCopySummary;

  /// No description provided for @knowledgeItemStartExperiment.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get knowledgeItemStartExperiment;

  /// No description provided for @knowledgeItemRecordResult.
  ///
  /// In en, this message translates to:
  /// **'Record result'**
  String get knowledgeItemRecordResult;

  /// No description provided for @knowledgeItemCopyResult.
  ///
  /// In en, this message translates to:
  /// **'Copy result'**
  String get knowledgeItemCopyResult;

  /// No description provided for @knowledgeItemRestartExperiment.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get knowledgeItemRestartExperiment;

  /// No description provided for @knowledgeItemUpdatedToast.
  ///
  /// In en, this message translates to:
  /// **'Knowledge updated'**
  String get knowledgeItemUpdatedToast;

  /// No description provided for @knowledgeItemCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get knowledgeItemCopiedToast;

  /// No description provided for @knowledgeLibrarySearchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get knowledgeLibrarySearchRecent;

  /// No description provided for @knowledgeLibrarySearchSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get knowledgeLibrarySearchSuggestions;

  /// No description provided for @knowledgeLibrarySearchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching knowledge'**
  String get knowledgeLibrarySearchEmptyTitle;

  /// No description provided for @knowledgeLibrarySearchEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Try a different keyword or switch segments.'**
  String get knowledgeLibrarySearchEmptyBody;

  /// No description provided for @knowledgeLibrarySearchEmptyScopedBody.
  ///
  /// In en, this message translates to:
  /// **'No matches in {segment}. Search all knowledge or try another keyword.'**
  String knowledgeLibrarySearchEmptyScopedBody(String segment);

  /// No description provided for @knowledgeLibrarySearchAllAction.
  ///
  /// In en, this message translates to:
  /// **'Search all knowledge'**
  String get knowledgeLibrarySearchAllAction;

  /// No description provided for @knowledgeLibraryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String knowledgeLibraryLoadFailed(Object error);

  /// No description provided for @knowledgeLibraryDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String knowledgeLibraryDeleteFailed(Object error);

  /// No description provided for @knowledgeReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review · KnowledgeOS'**
  String get knowledgeReviewTitle;

  /// No description provided for @knowledgeReviewOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review status'**
  String get knowledgeReviewOverviewTitle;

  /// No description provided for @knowledgeReviewAllClearBadge.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get knowledgeReviewAllClearBadge;

  /// No description provided for @knowledgeReviewAllClearBody.
  ///
  /// In en, this message translates to:
  /// **'There are no due reviews or pending suggestions. Your deterministic review remains available even without AI.'**
  String get knowledgeReviewAllClearBody;

  /// No description provided for @knowledgeReviewBrowseLibrary.
  ///
  /// In en, this message translates to:
  /// **'Browse library'**
  String get knowledgeReviewBrowseLibrary;

  /// No description provided for @knowledgeReviewReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get knowledgeReviewReorder;

  /// No description provided for @knowledgeReviewAttentionSummary.
  ///
  /// In en, this message translates to:
  /// **'{routines} routines · {decisions} decisions · {assumptions} assumptions · {suggestions} AI suggestions · {findings} conflicts'**
  String knowledgeReviewAttentionSummary(
    int routines,
    int decisions,
    int assumptions,
    int suggestions,
    int findings,
  );

  /// No description provided for @knowledgeReviewAgentNotRun.
  ///
  /// In en, this message translates to:
  /// **'The Knowledge Review agent has not run yet.'**
  String get knowledgeReviewAgentNotRun;

  /// No description provided for @knowledgeReviewLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last agent review: {date}'**
  String knowledgeReviewLastRun(String date);

  /// No description provided for @knowledgeReviewAiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AI suggestions are unavailable until an active device LLM profile is configured. Due reviews still work.'**
  String get knowledgeReviewAiUnavailable;

  /// No description provided for @knowledgeReviewRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run Knowledge Review'**
  String get knowledgeReviewRunNow;

  /// No description provided for @knowledgeReviewRoutinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Routines due this week'**
  String get knowledgeReviewRoutinesTitle;

  /// No description provided for @knowledgeReviewRoutinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No routines are due in the next 7 days.'**
  String get knowledgeReviewRoutinesEmpty;

  /// No description provided for @knowledgeReviewDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Decisions due for review'**
  String get knowledgeReviewDecisionsTitle;

  /// No description provided for @knowledgeReviewDecisionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No decisions are due for review.'**
  String get knowledgeReviewDecisionsEmpty;

  /// No description provided for @knowledgeReviewDecisionOverdueDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String knowledgeReviewDecisionOverdueDays(Object days);

  /// No description provided for @knowledgeReviewDecisionReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get knowledgeReviewDecisionReviewed;

  /// No description provided for @knowledgeReviewMarkAllDecisionsReviewed.
  ///
  /// In en, this message translates to:
  /// **'Mark all reviewed'**
  String get knowledgeReviewMarkAllDecisionsReviewed;

  /// No description provided for @knowledgeReviewMarkSelectedDecisionsReviewed.
  ///
  /// In en, this message translates to:
  /// **'Mark selected reviewed'**
  String get knowledgeReviewMarkSelectedDecisionsReviewed;

  /// No description provided for @knowledgeReviewBatchActions.
  ///
  /// In en, this message translates to:
  /// **'Batch actions'**
  String get knowledgeReviewBatchActions;

  /// No description provided for @knowledgeReviewTotalCount.
  ///
  /// In en, this message translates to:
  /// **'{count} total'**
  String knowledgeReviewTotalCount(Object count);

  /// No description provided for @knowledgeReviewVisibleCount.
  ///
  /// In en, this message translates to:
  /// **'Showing first {visible} of {total}'**
  String knowledgeReviewVisibleCount(Object total, Object visible);

  /// No description provided for @knowledgeReviewDecisionNextReview.
  ///
  /// In en, this message translates to:
  /// **'Next review {date}'**
  String knowledgeReviewDecisionNextReview(Object date);

  /// No description provided for @knowledgeReviewDecisionsBulkReviewed.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled {count} decisions for review'**
  String knowledgeReviewDecisionsBulkReviewed(int count);

  /// No description provided for @knowledgeReviewDecisionReviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update review date: {error}'**
  String knowledgeReviewDecisionReviewFailed(Object error);

  /// No description provided for @knowledgeReviewAssumptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stale assumptions'**
  String get knowledgeReviewAssumptionsTitle;

  /// No description provided for @knowledgeReviewAssumptionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'All active assumptions were verified within {days} days.'**
  String knowledgeReviewAssumptionsEmpty(Object days);

  /// No description provided for @knowledgeReviewRoutineMeta.
  ///
  /// In en, this message translates to:
  /// **'{dueLabel} · every {intervalDays} days'**
  String knowledgeReviewRoutineMeta(Object dueLabel, Object intervalDays);

  /// No description provided for @knowledgeReviewAssumptionStaleSummary.
  ///
  /// In en, this message translates to:
  /// **'· {statement} ({days} days, conf {confidence})'**
  String knowledgeReviewAssumptionStaleSummary(
    Object confidence,
    Object days,
    Object statement,
  );

  /// No description provided for @knowledgeReviewLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String knowledgeReviewLoadFailed(Object error);

  /// No description provided for @knowledgeReviewRoutineDone.
  ///
  /// In en, this message translates to:
  /// **'Done. Next due {date}'**
  String knowledgeReviewRoutineDone(Object date);

  /// No description provided for @knowledgeReviewRoutineDoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not mark routine done: {error}'**
  String knowledgeReviewRoutineDoneFailed(Object error);

  /// No description provided for @knowledgeReviewMarkDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get knowledgeReviewMarkDone;

  /// No description provided for @knowledgeReviewMarkAllDone.
  ///
  /// In en, this message translates to:
  /// **'Mark all done'**
  String get knowledgeReviewMarkAllDone;

  /// No description provided for @knowledgeReviewMarkSelectedDone.
  ///
  /// In en, this message translates to:
  /// **'Mark selected done'**
  String get knowledgeReviewMarkSelectedDone;

  /// No description provided for @knowledgeReviewRoutinesBulkDone.
  ///
  /// In en, this message translates to:
  /// **'Marked {count} routines done'**
  String knowledgeReviewRoutinesBulkDone(int count);

  /// No description provided for @knowledgeReviewVerifyAssumption.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get knowledgeReviewVerifyAssumption;

  /// No description provided for @knowledgeReviewVerifyAllAssumptions.
  ///
  /// In en, this message translates to:
  /// **'Verify all'**
  String get knowledgeReviewVerifyAllAssumptions;

  /// No description provided for @knowledgeReviewVerifySelectedAssumptions.
  ///
  /// In en, this message translates to:
  /// **'Verify selected'**
  String get knowledgeReviewVerifySelectedAssumptions;

  /// No description provided for @knowledgeReviewAssumptionsBulkVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified {count} assumptions'**
  String knowledgeReviewAssumptionsBulkVerified(int count);

  /// No description provided for @knowledgeReviewAssumptionVerified.
  ///
  /// In en, this message translates to:
  /// **'Assumption verified.'**
  String get knowledgeReviewAssumptionVerified;

  /// No description provided for @knowledgeReviewAssumptionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm this assumption'**
  String get knowledgeReviewAssumptionConfirmTitle;

  /// No description provided for @knowledgeReviewAssumptionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Only verify this if it is still supported by current evidence: “{statement}”'**
  String knowledgeReviewAssumptionConfirmBody(String statement);

  /// No description provided for @knowledgeReviewAssumptionStillValid.
  ///
  /// In en, this message translates to:
  /// **'Still valid'**
  String get knowledgeReviewAssumptionStillValid;

  /// No description provided for @knowledgeReviewAssumptionVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not verify assumption: {error}'**
  String knowledgeReviewAssumptionVerifyFailed(Object error);

  /// No description provided for @knowledgeReviewSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get knowledgeReviewSelectAll;

  /// No description provided for @knowledgeReviewClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get knowledgeReviewClearSelection;

  /// No description provided for @knowledgeReviewSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String knowledgeReviewSelectedCount(int count);

  /// No description provided for @knowledgeSegmentAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get knowledgeSegmentAll;

  /// No description provided for @knowledgeSegmentDecisions.
  ///
  /// In en, this message translates to:
  /// **'Decisions'**
  String get knowledgeSegmentDecisions;

  /// No description provided for @knowledgeSegmentPrinciples.
  ///
  /// In en, this message translates to:
  /// **'Principles'**
  String get knowledgeSegmentPrinciples;

  /// No description provided for @knowledgeSegmentAssumptions.
  ///
  /// In en, this message translates to:
  /// **'Assumptions'**
  String get knowledgeSegmentAssumptions;

  /// No description provided for @knowledgeSegmentNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get knowledgeSegmentNotes;

  /// No description provided for @knowledgeSegmentConcepts.
  ///
  /// In en, this message translates to:
  /// **'Concepts'**
  String get knowledgeSegmentConcepts;

  /// No description provided for @knowledgeSegmentExperiments.
  ///
  /// In en, this message translates to:
  /// **'Experiments'**
  String get knowledgeSegmentExperiments;

  /// No description provided for @knowledgeSegmentRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get knowledgeSegmentRoutines;

  /// No description provided for @knowledgeNewDecision.
  ///
  /// In en, this message translates to:
  /// **'New Decision'**
  String get knowledgeNewDecision;

  /// No description provided for @knowledgeNewPrinciple.
  ///
  /// In en, this message translates to:
  /// **'New Principle'**
  String get knowledgeNewPrinciple;

  /// No description provided for @knowledgeNewAssumption.
  ///
  /// In en, this message translates to:
  /// **'New Assumption'**
  String get knowledgeNewAssumption;

  /// No description provided for @knowledgeNewNote.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get knowledgeNewNote;

  /// No description provided for @knowledgeNewConcept.
  ///
  /// In en, this message translates to:
  /// **'New Concept'**
  String get knowledgeNewConcept;

  /// No description provided for @knowledgeNewExperiment.
  ///
  /// In en, this message translates to:
  /// **'New Experiment'**
  String get knowledgeNewExperiment;

  /// No description provided for @knowledgeNewRoutine.
  ///
  /// In en, this message translates to:
  /// **'New Routine'**
  String get knowledgeNewRoutine;

  /// No description provided for @knowledgeNewMoreTypes.
  ///
  /// In en, this message translates to:
  /// **'More types'**
  String get knowledgeNewMoreTypes;

  /// No description provided for @knowledgeNewChooserTitle.
  ///
  /// In en, this message translates to:
  /// **'New...'**
  String get knowledgeNewChooserTitle;

  /// No description provided for @knowledgeNewChooserSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a structured knowledge object. Quick Notes are captured from Inbox.'**
  String get knowledgeNewChooserSubtitle;

  /// No description provided for @knowledgeNewDecisionHint.
  ///
  /// In en, this message translates to:
  /// **'Primary path: question, options, rationale'**
  String get knowledgeNewDecisionHint;

  /// No description provided for @knowledgeNewPrincipleHint.
  ///
  /// In en, this message translates to:
  /// **'A worldview primitive, for example \"edge-first\"'**
  String get knowledgeNewPrincipleHint;

  /// No description provided for @knowledgeNewAssumptionHint.
  ///
  /// In en, this message translates to:
  /// **'A falsifiable belief with confidence'**
  String get knowledgeNewAssumptionHint;

  /// No description provided for @knowledgeDecisionWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Decision'**
  String get knowledgeDecisionWriterTitle;

  /// No description provided for @knowledgeDecisionWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Decision as memory: question, options, rationale, review'**
  String get knowledgeDecisionWriterSubtitle;

  /// No description provided for @knowledgeDecisionEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Decision'**
  String get knowledgeDecisionEditTitle;

  /// No description provided for @knowledgeDecisionEditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update options, rationale, expected outcome, and review plan'**
  String get knowledgeDecisionEditSubtitle;

  /// No description provided for @knowledgeDecisionAddOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get knowledgeDecisionAddOption;

  /// No description provided for @knowledgeDecisionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get knowledgeDecisionClear;

  /// No description provided for @knowledgeDecisionExpectedOutcomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Expected outcome (optional)'**
  String get knowledgeDecisionExpectedOutcomeLabel;

  /// No description provided for @knowledgeDecisionRevisitConditionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Review when (optional)'**
  String get knowledgeDecisionRevisitConditionsLabel;

  /// No description provided for @knowledgeDecisionRevisitConditionsHint.
  ///
  /// In en, this message translates to:
  /// **'One condition per line, for example: cash runway falls below 12 months'**
  String get knowledgeDecisionRevisitConditionsHint;

  /// No description provided for @knowledgeDecisionRevisitConditionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Review conditions'**
  String get knowledgeDecisionRevisitConditionsTitle;

  /// No description provided for @knowledgeAssumptionWriterSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'Falsifiable belief with confidence for future review'**
  String get knowledgeAssumptionWriterSubtitle2;

  /// No description provided for @knowledgeConceptWriterSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'Anchor for soft links and AI cross references'**
  String get knowledgeConceptWriterSubtitle2;

  /// No description provided for @knowledgeExperimentWriterSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'Validate an assumption with an explicit method'**
  String get knowledgeExperimentWriterSubtitle2;

  /// No description provided for @knowledgeWriterAliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get knowledgeWriterAliasLabel;

  /// No description provided for @knowledgeRoutineMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get knowledgeRoutineMonthly;

  /// No description provided for @knowledgeRoutineQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get knowledgeRoutineQuarterly;

  /// No description provided for @knowledgeRoutineSemiannual.
  ///
  /// In en, this message translates to:
  /// **'Every 6 months'**
  String get knowledgeRoutineSemiannual;

  /// No description provided for @knowledgeRoutineYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get knowledgeRoutineYearly;

  /// No description provided for @knowledgeDecisionQuestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get knowledgeDecisionQuestionLabel;

  /// No description provided for @knowledgeDecisionQuestionHint.
  ///
  /// In en, this message translates to:
  /// **'\"Upgrade to QQQ + BOXX dynamic hedging?\"'**
  String get knowledgeDecisionQuestionHint;

  /// No description provided for @knowledgeDecisionOptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get knowledgeDecisionOptionsLabel;

  /// No description provided for @knowledgeDecisionOptionsRequirement.
  ///
  /// In en, this message translates to:
  /// **'Enter at least two different options.'**
  String get knowledgeDecisionOptionsRequirement;

  /// No description provided for @knowledgeDecisionSelectionRequirement.
  ///
  /// In en, this message translates to:
  /// **'Choose the option you decided to take.'**
  String get knowledgeDecisionSelectionRequirement;

  /// No description provided for @knowledgeDecisionOptionLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Option {index}'**
  String knowledgeDecisionOptionLabelHint(Object index);

  /// No description provided for @knowledgeDecisionOptionRationaleHint.
  ///
  /// In en, this message translates to:
  /// **'Why choose this option (optional)'**
  String get knowledgeDecisionOptionRationaleHint;

  /// No description provided for @knowledgeDecisionNoReferenceCandidates.
  ///
  /// In en, this message translates to:
  /// **'No Principle or Assumption has been declared yet. You can save the Decision now and attach references later.'**
  String get knowledgeDecisionNoReferenceCandidates;

  /// No description provided for @knowledgeDecisionRationaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Rationale (Markdown)'**
  String get knowledgeDecisionRationaleLabel;

  /// No description provided for @knowledgeDecisionRationaleHint.
  ///
  /// In en, this message translates to:
  /// **'Why this option: constraints and the judgment at the time'**
  String get knowledgeDecisionRationaleHint;

  /// No description provided for @knowledgeDecisionExpectedOutcomeHint.
  ///
  /// In en, this message translates to:
  /// **'How success will be judged: metrics or signals'**
  String get knowledgeDecisionExpectedOutcomeHint;

  /// No description provided for @knowledgeDecisionReviewDateTitle.
  ///
  /// In en, this message translates to:
  /// **'Review date'**
  String get knowledgeDecisionReviewDateTitle;

  /// No description provided for @knowledgeDecisionReviewDateOptional.
  ///
  /// In en, this message translates to:
  /// **'Review date (optional)'**
  String get knowledgeDecisionReviewDateOptional;

  /// No description provided for @knowledgeDecisionReviewDateScheduled.
  ///
  /// In en, this message translates to:
  /// **'Review on {date}'**
  String knowledgeDecisionReviewDateScheduled(Object date);

  /// No description provided for @knowledgeDecisionReviewDateChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get knowledgeDecisionReviewDateChoose;

  /// No description provided for @knowledgeDecisionReviewDateChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get knowledgeDecisionReviewDateChange;

  /// No description provided for @knowledgeDecisionReviewDateInDays.
  ///
  /// In en, this message translates to:
  /// **'+{days} days'**
  String knowledgeDecisionReviewDateInDays(Object days);

  /// No description provided for @knowledgeDecisionReviewDateInOneYear.
  ///
  /// In en, this message translates to:
  /// **'+1 year'**
  String get knowledgeDecisionReviewDateInOneYear;

  /// No description provided for @knowledgeDecisionReviewDateCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom date'**
  String get knowledgeDecisionReviewDateCustomLabel;

  /// No description provided for @knowledgeDecisionReviewDateCustomHint.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD'**
  String get knowledgeDecisionReviewDateCustomHint;

  /// No description provided for @knowledgeDecisionReviewDateCustomApply.
  ///
  /// In en, this message translates to:
  /// **'Use date'**
  String get knowledgeDecisionReviewDateCustomApply;

  /// No description provided for @knowledgeDecisionReviewDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date as YYYY-MM-DD.'**
  String get knowledgeDecisionReviewDateInvalid;

  /// No description provided for @knowledgeDecisionReviewDatePast.
  ///
  /// In en, this message translates to:
  /// **'Choose today or a future date.'**
  String get knowledgeDecisionReviewDatePast;

  /// No description provided for @knowledgeDecisionLifecycleTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Decision'**
  String get knowledgeDecisionLifecycleTitle;

  /// No description provided for @knowledgeDecisionLifecycleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Status, actual outcome, and cognitive trail'**
  String get knowledgeDecisionLifecycleSubtitle;

  /// No description provided for @knowledgeDecisionActualOutcomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Actual outcome (Markdown, optional)'**
  String get knowledgeDecisionActualOutcomeLabel;

  /// No description provided for @knowledgeDecisionStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get knowledgeDecisionStatusLabel;

  /// No description provided for @knowledgeDecisionStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get knowledgeDecisionStatusDraft;

  /// No description provided for @knowledgeDecisionStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get knowledgeDecisionStatusActive;

  /// No description provided for @knowledgeDecisionStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get knowledgeDecisionStatusPaused;

  /// No description provided for @knowledgeDecisionStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get knowledgeDecisionStatusExpired;

  /// No description provided for @knowledgeDecisionStatusVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get knowledgeDecisionStatusVerified;

  /// No description provided for @knowledgeDecisionStatusFalsified.
  ///
  /// In en, this message translates to:
  /// **'Falsified'**
  String get knowledgeDecisionStatusFalsified;

  /// No description provided for @knowledgeDecisionStatusSuperseded.
  ///
  /// In en, this message translates to:
  /// **'Superseded'**
  String get knowledgeDecisionStatusSuperseded;

  /// No description provided for @knowledgeDecisionActualOutcomeHint.
  ///
  /// In en, this message translates to:
  /// **'For review: what actually happened and how it differed from expectations'**
  String get knowledgeDecisionActualOutcomeHint;

  /// No description provided for @knowledgeDecisionSupersededByLabel.
  ///
  /// In en, this message translates to:
  /// **'Superseded by Decision'**
  String get knowledgeDecisionSupersededByLabel;

  /// No description provided for @knowledgeDecisionSupersededByEmpty.
  ///
  /// In en, this message translates to:
  /// **'No other Decision is available yet. Record the new decision first, then come back to mark the relationship.'**
  String get knowledgeDecisionSupersededByEmpty;

  /// No description provided for @knowledgePrincipleWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Principle'**
  String get knowledgePrincipleWriterTitle;

  /// No description provided for @knowledgePrincipleWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Long-lived worldview primitive, not falsifiable'**
  String get knowledgePrincipleWriterSubtitle;

  /// No description provided for @knowledgePrincipleStatementHint.
  ///
  /// In en, this message translates to:
  /// **'\"Default edge-first\" / \"Avoid high-maintenance systems\"'**
  String get knowledgePrincipleStatementHint;

  /// No description provided for @knowledgePrincipleRationaleHint.
  ///
  /// In en, this message translates to:
  /// **'Why this worldview should become a Principle'**
  String get knowledgePrincipleRationaleHint;

  /// No description provided for @knowledgeAssumptionWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Assumption'**
  String get knowledgeAssumptionWriterTitle;

  /// No description provided for @knowledgeAssumptionEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Assumption'**
  String get knowledgeAssumptionEditTitle;

  /// No description provided for @knowledgeAssumptionEditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update the statement, confidence, and scope'**
  String get knowledgeAssumptionEditSubtitle;

  /// No description provided for @knowledgeAssumptionWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Falsifiable belief with confidence'**
  String get knowledgeAssumptionWriterSubtitle;

  /// No description provided for @knowledgeAssumptionStatementHint.
  ///
  /// In en, this message translates to:
  /// **'\"Long-term index growth beats inflation\"'**
  String get knowledgeAssumptionStatementHint;

  /// No description provided for @knowledgeConceptWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Concept'**
  String get knowledgeConceptWriterTitle;

  /// No description provided for @knowledgeConceptWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Named node for search and soft links'**
  String get knowledgeConceptWriterSubtitle;

  /// No description provided for @knowledgeConceptNameHint.
  ///
  /// In en, this message translates to:
  /// **'Concept name, for example \"edge-first\"'**
  String get knowledgeConceptNameHint;

  /// No description provided for @knowledgeConceptAliasesHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated aliases'**
  String get knowledgeConceptAliasesHint;

  /// No description provided for @knowledgeConceptSummaryHint.
  ///
  /// In en, this message translates to:
  /// **'1-2 sentence definition for [[soft link]] tooltips'**
  String get knowledgeConceptSummaryHint;

  /// No description provided for @knowledgeExperimentWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Experiment'**
  String get knowledgeExperimentWriterTitle;

  /// No description provided for @knowledgeExperimentWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Test an assumption with method and metrics'**
  String get knowledgeExperimentWriterSubtitle;

  /// No description provided for @knowledgeExperimentHypothesisHint.
  ///
  /// In en, this message translates to:
  /// **'\"Covered call 60 DTE on QQQ outperforms 30 DTE\"'**
  String get knowledgeExperimentHypothesisHint;

  /// No description provided for @knowledgeExperimentMethodHint.
  ///
  /// In en, this message translates to:
  /// **'How to run it, for how long, and with what data'**
  String get knowledgeExperimentMethodHint;

  /// No description provided for @knowledgeExperimentMetricsHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated, for example \"yield, drawdown, sharpe\"'**
  String get knowledgeExperimentMetricsHint;

  /// No description provided for @knowledgeExperimentNoActiveAssumptions.
  ///
  /// In en, this message translates to:
  /// **'No active Assumptions are available. You can leave this empty.'**
  String get knowledgeExperimentNoActiveAssumptions;

  /// No description provided for @knowledgeExperimentTargetAssumptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Assumption (optional)'**
  String get knowledgeExperimentTargetAssumptionLabel;

  /// No description provided for @knowledgeRoutineWriterTitle.
  ///
  /// In en, this message translates to:
  /// **'New Routine'**
  String get knowledgeRoutineWriterTitle;

  /// No description provided for @knowledgeRoutineWriterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring reminder. AI can surface it near next due date.'**
  String get knowledgeRoutineWriterSubtitle;

  /// No description provided for @knowledgeRoutineStatementHint.
  ///
  /// In en, this message translates to:
  /// **'\"Activate bank card\" / \"Monthly reconciliation\"'**
  String get knowledgeRoutineStatementHint;

  /// No description provided for @knowledgeWriterStatementLabel.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get knowledgeWriterStatementLabel;

  /// No description provided for @knowledgeWriterRationaleMarkdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Rationale (Markdown)'**
  String get knowledgeWriterRationaleMarkdownLabel;

  /// No description provided for @knowledgeWriterScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get knowledgeWriterScopeLabel;

  /// No description provided for @knowledgeWriterScopeOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Scope tag (optional)'**
  String get knowledgeWriterScopeOptionalLabel;

  /// No description provided for @knowledgeWriterEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Evidence IDs'**
  String get knowledgeWriterEvidenceLabel;

  /// No description provided for @knowledgeWriterConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get knowledgeWriterConfidenceLabel;

  /// No description provided for @knowledgeConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get knowledgeConfidenceLow;

  /// No description provided for @knowledgeConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get knowledgeConfidenceMedium;

  /// No description provided for @knowledgeConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get knowledgeConfidenceHigh;

  /// No description provided for @knowledgeWriterScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Optional, such as investing, health, or work'**
  String get knowledgeWriterScopeHint;

  /// No description provided for @knowledgeWriterStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get knowledgeWriterStatusLabel;

  /// No description provided for @knowledgeWriterNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get knowledgeWriterNameLabel;

  /// No description provided for @knowledgeWriterAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get knowledgeWriterAliasesLabel;

  /// No description provided for @knowledgeWriterSummaryMarkdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary (Markdown)'**
  String get knowledgeWriterSummaryMarkdownLabel;

  /// No description provided for @knowledgeWriterHypothesisLabel.
  ///
  /// In en, this message translates to:
  /// **'Hypothesis'**
  String get knowledgeWriterHypothesisLabel;

  /// No description provided for @knowledgeWriterMethodMarkdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Method (Markdown)'**
  String get knowledgeWriterMethodMarkdownLabel;

  /// No description provided for @knowledgeWriterMetricsLabel.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get knowledgeWriterMetricsLabel;

  /// No description provided for @knowledgeWriterResultMarkdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Result (Markdown, optional)'**
  String get knowledgeWriterResultMarkdownLabel;

  /// No description provided for @knowledgeWriterConclusionMarkdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Conclusion (Markdown, optional)'**
  String get knowledgeWriterConclusionMarkdownLabel;

  /// No description provided for @knowledgeWriterCoreSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get knowledgeWriterCoreSectionTitle;

  /// No description provided for @knowledgeWriterEvidenceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence and rationale'**
  String get knowledgeWriterEvidenceSectionTitle;

  /// No description provided for @knowledgeWriterContextSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Additional context'**
  String get knowledgeWriterContextSectionTitle;

  /// No description provided for @knowledgeWriterReferencesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get knowledgeWriterReferencesSectionTitle;

  /// No description provided for @knowledgeWriterPlanningSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get knowledgeWriterPlanningSectionTitle;

  /// No description provided for @knowledgeWriterCadenceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Cadence'**
  String get knowledgeWriterCadenceSectionTitle;

  /// No description provided for @knowledgeRoutineStatementLabel.
  ///
  /// In en, this message translates to:
  /// **'What to do'**
  String get knowledgeRoutineStatementLabel;

  /// No description provided for @knowledgeRoutineFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get knowledgeRoutineFrequencyLabel;

  /// No description provided for @knowledgeNotesHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes are captured in Inbox'**
  String get knowledgeNotesHintTitle;

  /// No description provided for @knowledgeNotesHintBody.
  ///
  /// In en, this message translates to:
  /// **'The Notes segment is for browsing. Close this panel, switch to Inbox, and use the create action there.'**
  String get knowledgeNotesHintBody;

  /// No description provided for @knowledgeNoteTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get knowledgeNoteTagsLabel;

  /// Screen reader label when monetary amount is hidden by privacy mode
  ///
  /// In en, this message translates to:
  /// **'Amount hidden'**
  String get amountHidden;

  /// Trade narration verb: buy
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get tradeVerbBuy;

  /// Trade narration verb: sell
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get tradeVerbSell;

  /// No description provided for @healthNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'HealthOS not enabled'**
  String get healthNotEnabled;

  /// Error message when recovery plan fails to load
  ///
  /// In en, this message translates to:
  /// **'Plan load failed: {message}'**
  String healthPlanLoadFailed(String message);

  /// No description provided for @healthGarminTitle.
  ///
  /// In en, this message translates to:
  /// **'Garmin Connect'**
  String get healthGarminTitle;

  /// No description provided for @healthGarminDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get healthGarminDisconnected;

  /// No description provided for @healthGarminConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get healthGarminConnected;

  /// No description provided for @healthGarminSyncingBadge.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get healthGarminSyncingBadge;

  /// No description provided for @healthGarminErrorBadge.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get healthGarminErrorBadge;

  /// No description provided for @healthGarminRestoringBadge.
  ///
  /// In en, this message translates to:
  /// **'Restoring'**
  String get healthGarminRestoringBadge;

  /// No description provided for @healthGarminVerifyBadge.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get healthGarminVerifyBadge;

  /// No description provided for @healthGarminMfaRequired.
  ///
  /// In en, this message translates to:
  /// **'MFA Required'**
  String get healthGarminMfaRequired;

  /// No description provided for @healthGarminConnectSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Garmin'**
  String get healthGarminConnectSheetTitle;

  /// No description provided for @healthGarminMfaCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'MFA code'**
  String get healthGarminMfaCodeLabel;

  /// No description provided for @healthGarminEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get healthGarminEmailLabel;

  /// No description provided for @healthGarminEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get healthGarminEmailHint;

  /// No description provided for @healthGarminPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get healthGarminPasswordLabel;

  /// No description provided for @healthGarminRememberPassword.
  ///
  /// In en, this message translates to:
  /// **'Securely save password'**
  String get healthGarminRememberPassword;

  /// No description provided for @healthGarminRememberPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Encrypted in this device’s Keychain or Keystore. Never synced.'**
  String get healthGarminRememberPasswordHint;

  /// No description provided for @healthGarminAutoRenewEnabled.
  ///
  /// In en, this message translates to:
  /// **'Session auto-renewal is on'**
  String get healthGarminAutoRenewEnabled;

  /// No description provided for @healthGarminRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get healthGarminRegionLabel;

  /// No description provided for @healthGarminRegionChina.
  ///
  /// In en, this message translates to:
  /// **'China'**
  String get healthGarminRegionChina;

  /// No description provided for @healthGarminRegionGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get healthGarminRegionGlobal;

  /// No description provided for @healthGarminConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get healthGarminConnect;

  /// No description provided for @healthGarminDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get healthGarminDisconnect;

  /// No description provided for @healthGarminSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get healthGarminSync;

  /// No description provided for @healthGarminRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get healthGarminRetry;

  /// No description provided for @healthGarminEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get healthGarminEnterCode;

  /// No description provided for @healthGarminRestoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring session…'**
  String get healthGarminRestoringSession;

  /// No description provided for @healthGarminSyncingData.
  ///
  /// In en, this message translates to:
  /// **'Syncing data…'**
  String get healthGarminSyncingData;

  /// No description provided for @healthGarminSyncError.
  ///
  /// In en, this message translates to:
  /// **'Sync Error'**
  String get healthGarminSyncError;

  /// No description provided for @healthGarminDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Garmin?'**
  String get healthGarminDisconnectTitle;

  /// No description provided for @healthGarminDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'Synced data will remain in the app.'**
  String get healthGarminDisconnectBody;

  /// No description provided for @healthGarminCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get healthGarminCancel;

  /// Garmin connected status line
  ///
  /// In en, this message translates to:
  /// **'Last sync {time} · {count} metrics'**
  String healthGarminLastSync(String time, String count);

  /// Garmin sync progress indicator
  ///
  /// In en, this message translates to:
  /// **'Day {current}/{total} · {count} metrics'**
  String healthGarminSyncProgress(String current, String total, String count);

  /// No description provided for @healthGarminCancelSync.
  ///
  /// In en, this message translates to:
  /// **'Cancel Sync'**
  String get healthGarminCancelSync;

  /// No description provided for @healthGarminErrorAuthExpired.
  ///
  /// In en, this message translates to:
  /// **'Garmin session expired. Please reconnect your account.'**
  String get healthGarminErrorAuthExpired;

  /// No description provided for @healthGarminErrorCredentialsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Your saved Garmin password no longer works. Enter it again to reconnect.'**
  String get healthGarminErrorCredentialsInvalid;

  /// No description provided for @healthGarminErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Garmin is limiting requests temporarily. Try again later.'**
  String get healthGarminErrorRateLimited;

  /// No description provided for @healthGarminErrorEndpointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some Garmin data endpoints are unavailable for this account or region.'**
  String get healthGarminErrorEndpointUnavailable;

  /// No description provided for @healthGarminErrorPersistFailed.
  ///
  /// In en, this message translates to:
  /// **'Garmin data was fetched but could not be saved locally. Try syncing again.'**
  String get healthGarminErrorPersistFailed;

  /// No description provided for @healthGarminErrorUnsupportedSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Garmin returned data in a shape HealthOS does not support yet.'**
  String get healthGarminErrorUnsupportedSnapshot;

  /// No description provided for @healthGarminErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Garmin sync failed. Try again.'**
  String get healthGarminErrorGeneric;

  /// No description provided for @settingsDomainsExecutionEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Today, commitments, progress, and personal todos.'**
  String get settingsDomainsExecutionEnabledSubtitle;

  /// No description provided for @settingsDomainsExecutionDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn decisions and plans into trackable actions.'**
  String get settingsDomainsExecutionDisabledSubtitle;

  /// No description provided for @settingsDomainsExecutionTodaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review today\'s actions, blockers, and progress.'**
  String get settingsDomainsExecutionTodaySubtitle;

  /// No description provided for @executionTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get executionTabToday;

  /// No description provided for @executionTabCommitments.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get executionTabCommitments;

  /// No description provided for @executionTabReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get executionTabReview;

  /// No description provided for @executionCommandToday.
  ///
  /// In en, this message translates to:
  /// **'ExecutionOS Today'**
  String get executionCommandToday;

  /// No description provided for @executionCommandCommitments.
  ///
  /// In en, this message translates to:
  /// **'ExecutionOS Plans'**
  String get executionCommandCommitments;

  /// No description provided for @executionCommandReview.
  ///
  /// In en, this message translates to:
  /// **'ExecutionOS Review'**
  String get executionCommandReview;

  /// No description provided for @executionTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get executionTodayTitle;

  /// Subtitle under the ExecutionOS Today greeting
  ///
  /// In en, this message translates to:
  /// **'Today\'s execution overview'**
  String get executionTodayBriefSubtitle;

  /// No description provided for @executionCommitmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get executionCommitmentsTitle;

  /// No description provided for @executionPlansSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select a plan to review it here'**
  String get executionPlansSelectItem;

  /// No description provided for @executionReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get executionReviewTitle;

  /// No description provided for @executionReviewNeedsAttentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get executionReviewNeedsAttentionTitle;

  /// No description provided for @executionReviewWeekResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get executionReviewWeekResultsTitle;

  /// No description provided for @executionReviewRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity · {count}'**
  String executionReviewRecentActivity(int count);

  /// No description provided for @executionReviewDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Review details'**
  String get executionReviewDetailsTitle;

  /// No description provided for @executionReviewDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Data freshness and technical run details'**
  String get executionReviewDetailsSubtitle;

  /// No description provided for @executionCreateActionTitle.
  ///
  /// In en, this message translates to:
  /// **'New Action'**
  String get executionCreateActionTitle;

  /// No description provided for @executionCreatePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get executionCreatePlanTitle;

  /// No description provided for @executionCreateProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'New Plan'**
  String get executionCreateProjectTitle;

  /// No description provided for @executionCreateCommitmentTitle.
  ///
  /// In en, this message translates to:
  /// **'New Commitment'**
  String get executionCreateCommitmentTitle;

  /// No description provided for @executionCreateProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'New Progress'**
  String get executionCreateProgressTitle;

  /// No description provided for @executionEditProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Progress'**
  String get executionEditProgressTitle;

  /// No description provided for @executionEditActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Action'**
  String get executionEditActionTitle;

  /// No description provided for @executionEditProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Plan'**
  String get executionEditProjectTitle;

  /// No description provided for @executionEditCommitmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Commitment'**
  String get executionEditCommitmentTitle;

  /// No description provided for @executionActionField.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get executionActionField;

  /// No description provided for @executionProjectField.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get executionProjectField;

  /// No description provided for @executionCommitmentField.
  ///
  /// In en, this message translates to:
  /// **'Commitment'**
  String get executionCommitmentField;

  /// No description provided for @executionRelationField.
  ///
  /// In en, this message translates to:
  /// **'Belongs to'**
  String get executionRelationField;

  /// No description provided for @executionNoRelation.
  ///
  /// In en, this message translates to:
  /// **'Inbox · no plan'**
  String get executionNoRelation;

  /// No description provided for @executionStatusField.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get executionStatusField;

  /// No description provided for @executionPriorityField.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get executionPriorityField;

  /// No description provided for @executionHorizonField.
  ///
  /// In en, this message translates to:
  /// **'Horizon'**
  String get executionHorizonField;

  /// No description provided for @executionTargetDateField.
  ///
  /// In en, this message translates to:
  /// **'Target date'**
  String get executionTargetDateField;

  /// No description provided for @executionScheduledForField.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get executionScheduledForField;

  /// No description provided for @executionDueAtField.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get executionDueAtField;

  /// No description provided for @executionDescriptionField.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get executionDescriptionField;

  /// No description provided for @executionTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a title'**
  String get executionTitleRequired;

  /// No description provided for @executionActionTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What is the next concrete action?'**
  String get executionActionTitleHint;

  /// No description provided for @executionActionNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Optional note'**
  String get executionActionNoteHint;

  /// No description provided for @executionProjectTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What outcome needs multiple steps?'**
  String get executionProjectTitleHint;

  /// No description provided for @executionProjectDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional outcome, scope, or finish line'**
  String get executionProjectDescriptionHint;

  /// No description provided for @executionCommitmentTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What are you committing to?'**
  String get executionCommitmentTitleHint;

  /// No description provided for @executionCommitmentDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional scope, why it matters, or target outcome'**
  String get executionCommitmentDescriptionHint;

  /// No description provided for @executionOverviewFocus.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get executionOverviewFocus;

  /// No description provided for @executionOverviewBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get executionOverviewBlocked;

  /// No description provided for @executionOverviewHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get executionOverviewHigh;

  /// No description provided for @executionOverviewDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get executionOverviewDue;

  /// No description provided for @executionOverviewProjects.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get executionOverviewProjects;

  /// No description provided for @executionOverviewCommitments.
  ///
  /// In en, this message translates to:
  /// **'Commitments'**
  String get executionOverviewCommitments;

  /// No description provided for @executionOverviewProgress7d.
  ///
  /// In en, this message translates to:
  /// **'7d progress'**
  String get executionOverviewProgress7d;

  /// No description provided for @executionTodayEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No actions for today'**
  String get executionTodayEmptyTitle;

  /// No description provided for @executionTodayEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Capture the next concrete step when something needs follow-through.'**
  String get executionTodayEmptyBody;

  /// No description provided for @executionTodayFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching actions'**
  String get executionTodayFilteredEmptyTitle;

  /// No description provided for @executionTodayFilteredEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Switch filters or capture a new action when something needs follow-through.'**
  String get executionTodayFilteredEmptyBody;

  /// No description provided for @executionDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {item}?'**
  String executionDeleteConfirmTitle(Object item);

  /// No description provided for @executionDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes it from ExecutionOS and syncs the deletion.'**
  String get executionDeleteConfirmBody;

  /// No description provided for @executionCommitmentsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No active work'**
  String get executionCommitmentsEmptyTitle;

  /// No description provided for @executionCommitmentsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Capture one next action, or group multi-step work into a plan.'**
  String get executionCommitmentsEmptyBody;

  /// No description provided for @executionCommitmentsClosedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No closed items'**
  String get executionCommitmentsClosedEmptyTitle;

  /// No description provided for @executionCommitmentsClosedEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Completed and archived plans will appear here.'**
  String get executionCommitmentsClosedEmptyBody;

  /// No description provided for @executionReviewEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No progress yet'**
  String get executionReviewEmptyTitle;

  /// No description provided for @executionReviewEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Completion and blocker notes will appear here for review.'**
  String get executionReviewEmptyBody;

  /// No description provided for @executionClosedActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Recent closed actions'**
  String get executionClosedActionsSection;

  /// No description provided for @executionProjectsSection.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get executionProjectsSection;

  /// No description provided for @executionCommitmentsSection.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get executionCommitmentsSection;

  /// No description provided for @executionInboxSection.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get executionInboxSection;

  /// No description provided for @executionActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get executionActionsSection;

  /// No description provided for @executionRelatedActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Related actions'**
  String get executionRelatedActionsSection;

  /// No description provided for @executionTimelineSection.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get executionTimelineSection;

  /// No description provided for @executionDetailMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Item not found'**
  String get executionDetailMissingTitle;

  /// No description provided for @executionDetailMissingBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted or is no longer available on this device.'**
  String get executionDetailMissingBody;

  /// No description provided for @executionProjectStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get executionProjectStatusActive;

  /// No description provided for @executionProjectStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get executionProjectStatusPaused;

  /// No description provided for @executionProjectStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get executionProjectStatusCompleted;

  /// No description provided for @executionProjectStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get executionProjectStatusArchived;

  /// No description provided for @executionStatusTodo.
  ///
  /// In en, this message translates to:
  /// **'Todo'**
  String get executionStatusTodo;

  /// No description provided for @executionStatusDoing.
  ///
  /// In en, this message translates to:
  /// **'Doing'**
  String get executionStatusDoing;

  /// No description provided for @executionStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get executionStatusBlocked;

  /// No description provided for @executionStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get executionStatusDone;

  /// No description provided for @executionStatusDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get executionStatusDropped;

  /// No description provided for @executionPriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get executionPriorityLow;

  /// No description provided for @executionPriorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get executionPriorityNormal;

  /// No description provided for @executionPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get executionPriorityHigh;

  /// No description provided for @executionDueBadge.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String executionDueBadge(String date);

  /// No description provided for @executionScheduledBadge.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {date}'**
  String executionScheduledBadge(String date);

  /// No description provided for @executionOverdueBadge.
  ///
  /// In en, this message translates to:
  /// **'Overdue {date}'**
  String executionOverdueBadge(String date);

  /// No description provided for @executionTargetBadge.
  ///
  /// In en, this message translates to:
  /// **'Target {date}'**
  String executionTargetBadge(String date);

  /// No description provided for @executionNoAction.
  ///
  /// In en, this message translates to:
  /// **'No action'**
  String get executionNoAction;

  /// No description provided for @executionUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'Unknown action'**
  String get executionUnknownAction;

  /// No description provided for @executionNoActionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No open actions available'**
  String get executionNoActionsAvailable;

  /// No description provided for @executionNoProject.
  ///
  /// In en, this message translates to:
  /// **'No project'**
  String get executionNoProject;

  /// No description provided for @executionUnknownProject.
  ///
  /// In en, this message translates to:
  /// **'Unknown project'**
  String get executionUnknownProject;

  /// No description provided for @executionNoProjectsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No active projects available'**
  String get executionNoProjectsAvailable;

  /// No description provided for @executionNoCommitment.
  ///
  /// In en, this message translates to:
  /// **'No commitment'**
  String get executionNoCommitment;

  /// No description provided for @executionUnknownCommitment.
  ///
  /// In en, this message translates to:
  /// **'Unknown commitment'**
  String get executionUnknownCommitment;

  /// No description provided for @executionNoCommitmentsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No active commitments available'**
  String get executionNoCommitmentsAvailable;

  /// No description provided for @executionPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by title or note'**
  String get executionPickerSearchHint;

  /// No description provided for @executionPickerSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get executionPickerSearchEmpty;

  /// No description provided for @executionActionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get executionActionStart;

  /// No description provided for @executionActionBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get executionActionBlock;

  /// No description provided for @executionActionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get executionActionResume;

  /// No description provided for @executionActionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get executionActionDone;

  /// No description provided for @executionActionDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get executionActionDrop;

  /// No description provided for @executionActionStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update action status.'**
  String get executionActionStatusUpdateFailed;

  /// No description provided for @executionLifecyclePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get executionLifecyclePause;

  /// No description provided for @executionLifecycleResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get executionLifecycleResume;

  /// No description provided for @executionLifecycleComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get executionLifecycleComplete;

  /// No description provided for @executionLifecycleArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get executionLifecycleArchive;

  /// No description provided for @executionLifecycleActiveView.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get executionLifecycleActiveView;

  /// No description provided for @executionLifecycleClosedView.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get executionLifecycleClosedView;

  /// No description provided for @executionClosedWorkEntry.
  ///
  /// In en, this message translates to:
  /// **'Closed work'**
  String get executionClosedWorkEntry;

  /// No description provided for @executionActiveWorkEntry.
  ///
  /// In en, this message translates to:
  /// **'Back to active work'**
  String get executionActiveWorkEntry;

  /// No description provided for @executionProjectStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update project status.'**
  String get executionProjectStatusUpdateFailed;

  /// No description provided for @executionCommitmentStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update commitment status.'**
  String get executionCommitmentStatusUpdateFailed;

  /// No description provided for @executionProgressDoneDefault.
  ///
  /// In en, this message translates to:
  /// **'Marked done.'**
  String get executionProgressDoneDefault;

  /// No description provided for @executionProgressDroppedDefault.
  ///
  /// In en, this message translates to:
  /// **'Marked dropped.'**
  String get executionProgressDroppedDefault;

  /// No description provided for @executionProgressStartedDefault.
  ///
  /// In en, this message translates to:
  /// **'Started work.'**
  String get executionProgressStartedDefault;

  /// No description provided for @executionProgressResumedDefault.
  ///
  /// In en, this message translates to:
  /// **'Resumed work.'**
  String get executionProgressResumedDefault;

  /// No description provided for @executionProjectPausedDefault.
  ///
  /// In en, this message translates to:
  /// **'Project paused.'**
  String get executionProjectPausedDefault;

  /// No description provided for @executionProjectResumedDefault.
  ///
  /// In en, this message translates to:
  /// **'Project resumed.'**
  String get executionProjectResumedDefault;

  /// No description provided for @executionProjectCompletedDefault.
  ///
  /// In en, this message translates to:
  /// **'Project completed.'**
  String get executionProjectCompletedDefault;

  /// No description provided for @executionProjectArchivedDefault.
  ///
  /// In en, this message translates to:
  /// **'Project archived.'**
  String get executionProjectArchivedDefault;

  /// No description provided for @executionCommitmentPausedDefault.
  ///
  /// In en, this message translates to:
  /// **'Commitment paused.'**
  String get executionCommitmentPausedDefault;

  /// No description provided for @executionCommitmentResumedDefault.
  ///
  /// In en, this message translates to:
  /// **'Commitment resumed.'**
  String get executionCommitmentResumedDefault;

  /// No description provided for @executionCommitmentCompletedDefault.
  ///
  /// In en, this message translates to:
  /// **'Commitment completed.'**
  String get executionCommitmentCompletedDefault;

  /// No description provided for @executionCommitmentArchivedDefault.
  ///
  /// In en, this message translates to:
  /// **'Commitment archived.'**
  String get executionCommitmentArchivedDefault;

  /// No description provided for @executionLifecycleCompleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete with open actions?'**
  String get executionLifecycleCompleteConfirmTitle;

  /// No description provided for @executionLifecycleCompleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open action will remain active and move to Inbox.} other{{count} open actions will remain active and move to Inbox.}}'**
  String executionLifecycleCompleteConfirmBody(int count);

  /// No description provided for @executionLifecycleArchiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive with open actions?'**
  String get executionLifecycleArchiveConfirmTitle;

  /// No description provided for @executionLifecycleArchiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open action will remain active and move to Inbox.} other{{count} open actions will remain active and move to Inbox.}}'**
  String executionLifecycleArchiveConfirmBody(int count);

  /// No description provided for @executionLifecycleStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Status updated to {status}'**
  String executionLifecycleStatusUpdated(Object status);

  /// No description provided for @executionDeleteWithOpenActionsBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the item. {count, plural, =1{1 open action will move to Inbox.} other{{count} open actions will move to Inbox.}}'**
  String executionDeleteWithOpenActionsBody(int count);

  /// No description provided for @executionProgressKindField.
  ///
  /// In en, this message translates to:
  /// **'Progress type'**
  String get executionProgressKindField;

  /// No description provided for @executionProgressNoteField.
  ///
  /// In en, this message translates to:
  /// **'Progress note'**
  String get executionProgressNoteField;

  /// No description provided for @executionProgressNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Record a change or note. Use the action controls to change status.'**
  String get executionProgressNoteHint;

  /// No description provided for @executionProgressNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a progress note'**
  String get executionProgressNoteRequired;

  /// No description provided for @executionProgressKindBlocker.
  ///
  /// In en, this message translates to:
  /// **'Blocker'**
  String get executionProgressKindBlocker;

  /// No description provided for @executionProgressKindCompletion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get executionProgressKindCompletion;

  /// No description provided for @executionProgressKindDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get executionProgressKindDropped;

  /// No description provided for @executionProgressKindScope.
  ///
  /// In en, this message translates to:
  /// **'Scope Change'**
  String get executionProgressKindScope;

  /// No description provided for @executionProgressKindCheckin.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get executionProgressKindCheckin;

  /// No description provided for @executionOpenActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Open actions'**
  String get executionOpenActionsSection;

  /// No description provided for @executionStandaloneActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Standalone actions'**
  String get executionStandaloneActionsSection;

  /// No description provided for @executionUnplacedActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Open actions to place'**
  String get executionUnplacedActionsSection;

  /// No description provided for @executionProjectCommitmentsSection.
  ///
  /// In en, this message translates to:
  /// **'Project commitments'**
  String get executionProjectCommitmentsSection;

  /// No description provided for @executionReviewWindow7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get executionReviewWindow7d;

  /// No description provided for @executionReviewWindow30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get executionReviewWindow30d;

  /// No description provided for @executionReviewWindowAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get executionReviewWindowAll;

  /// No description provided for @executionReviewCompletedMetric.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get executionReviewCompletedMetric;

  /// No description provided for @executionReviewBlockedMetric.
  ///
  /// In en, this message translates to:
  /// **'Blockers'**
  String get executionReviewBlockedMetric;

  /// No description provided for @executionReviewProgressMetric.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get executionReviewProgressMetric;

  /// No description provided for @executionReviewGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution review'**
  String get executionReviewGenerateTitle;

  /// No description provided for @executionReviewGenerateBody.
  ///
  /// In en, this message translates to:
  /// **'Generate a local review of focus, blockers, due work, and recent progress.'**
  String get executionReviewGenerateBody;

  /// No description provided for @executionReviewGenerateAction.
  ///
  /// In en, this message translates to:
  /// **'Generate review'**
  String get executionReviewGenerateAction;

  /// No description provided for @executionProposalActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get executionProposalActionLabel;

  /// No description provided for @executionProposalActionStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Action Status'**
  String get executionProposalActionStatusLabel;

  /// No description provided for @executionProposalProjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get executionProposalProjectLabel;

  /// No description provided for @executionProposalCommitmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Commitment'**
  String get executionProposalCommitmentLabel;

  /// No description provided for @executionProposalProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get executionProposalProgressLabel;

  /// No description provided for @executionProposalRowAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get executionProposalRowAction;

  /// No description provided for @executionProposalRowPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get executionProposalRowPriority;

  /// No description provided for @executionProposalRowProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get executionProposalRowProject;

  /// No description provided for @executionProposalRowCommitment.
  ///
  /// In en, this message translates to:
  /// **'Commitment'**
  String get executionProposalRowCommitment;

  /// No description provided for @executionProposalRowProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get executionProposalRowProgress;

  /// No description provided for @executionProposalRowDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get executionProposalRowDue;

  /// No description provided for @executionProposalRowSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get executionProposalRowSource;

  /// No description provided for @agentOutputLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get agentOutputLanguageEnglish;

  /// No description provided for @agentOutputLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get agentOutputLanguageChinese;

  /// No description provided for @financeAgentWeeklyWealthSkipNoSnapshot.
  ///
  /// In en, this message translates to:
  /// **'no finance snapshot to review'**
  String get financeAgentWeeklyWealthSkipNoSnapshot;

  /// No description provided for @financeAgentWeeklyWealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Wealth Review'**
  String get financeAgentWeeklyWealthTitle;

  /// No description provided for @financeAgentWeeklyWealthSummary.
  ///
  /// In en, this message translates to:
  /// **'Weekly wealth review: {details}.'**
  String financeAgentWeeklyWealthSummary(Object details);

  /// No description provided for @financeAgentWeeklyWealthPartNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Net worth {value}'**
  String financeAgentWeeklyWealthPartNetWorth(Object value);

  /// No description provided for @financeAgentWeeklyWealthPartAssets.
  ///
  /// In en, this message translates to:
  /// **'assets {value}'**
  String financeAgentWeeklyWealthPartAssets(Object value);

  /// No description provided for @financeAgentWeeklyWealthPartLiabilities.
  ///
  /// In en, this message translates to:
  /// **'liabilities {value}'**
  String financeAgentWeeklyWealthPartLiabilities(Object value);

  /// No description provided for @financeAgentWeeklyWealthPartLargestAllocation.
  ///
  /// In en, this message translates to:
  /// **'largest allocation {category} {amount} ({ratio})'**
  String financeAgentWeeklyWealthPartLargestAllocation(
    Object amount,
    Object category,
    Object ratio,
  );

  /// No description provided for @financeAgentWeeklyWealthPartStalePrices.
  ///
  /// In en, this message translates to:
  /// **'{count} stale prices'**
  String financeAgentWeeklyWealthPartStalePrices(Object count);

  /// No description provided for @financeAgentWeeklyWealthPartFxGaps.
  ///
  /// In en, this message translates to:
  /// **'{count} FX gaps'**
  String financeAgentWeeklyWealthPartFxGaps(Object count);

  /// No description provided for @financeAgentAssetCategoryStock.
  ///
  /// In en, this message translates to:
  /// **'stocks'**
  String get financeAgentAssetCategoryStock;

  /// No description provided for @financeAgentAssetCategoryEtf.
  ///
  /// In en, this message translates to:
  /// **'ETFs'**
  String get financeAgentAssetCategoryEtf;

  /// No description provided for @financeAgentAssetCategoryBondsAndFunds.
  ///
  /// In en, this message translates to:
  /// **'bonds and funds'**
  String get financeAgentAssetCategoryBondsAndFunds;

  /// No description provided for @financeAgentAssetCategoryCash.
  ///
  /// In en, this message translates to:
  /// **'cash'**
  String get financeAgentAssetCategoryCash;

  /// No description provided for @financeAgentAssetCategoryCrypto.
  ///
  /// In en, this message translates to:
  /// **'crypto'**
  String get financeAgentAssetCategoryCrypto;

  /// No description provided for @financeAgentAssetCategoryRealEstate.
  ///
  /// In en, this message translates to:
  /// **'real estate'**
  String get financeAgentAssetCategoryRealEstate;

  /// No description provided for @financeAgentAssetCategoryVehicle.
  ///
  /// In en, this message translates to:
  /// **'vehicles'**
  String get financeAgentAssetCategoryVehicle;

  /// No description provided for @financeAgentAssetCategoryLiability.
  ///
  /// In en, this message translates to:
  /// **'liabilities'**
  String get financeAgentAssetCategoryLiability;

  /// No description provided for @financeAgentWeeklyWealthInsightNetWorthTitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get financeAgentWeeklyWealthInsightNetWorthTitle;

  /// No description provided for @financeAgentWeeklyWealthInsightNetWorthBody.
  ///
  /// In en, this message translates to:
  /// **'{netWorth} net worth from {assets} assets and {liabilities} liabilities.'**
  String financeAgentWeeklyWealthInsightNetWorthBody(
    Object assets,
    Object liabilities,
    Object netWorth,
  );

  /// No description provided for @financeAgentWeeklyWealthInsightLargestAllocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Largest allocation'**
  String get financeAgentWeeklyWealthInsightLargestAllocationTitle;

  /// No description provided for @financeAgentWeeklyWealthInsightLargestAllocationBody.
  ///
  /// In en, this message translates to:
  /// **'{category} is {amount}, about {ratio} of assets.'**
  String financeAgentWeeklyWealthInsightLargestAllocationBody(
    Object amount,
    Object category,
    Object ratio,
  );

  /// No description provided for @financeAgentWeeklyWealthInsightPriceFreshnessTitle.
  ///
  /// In en, this message translates to:
  /// **'Price freshness'**
  String get financeAgentWeeklyWealthInsightPriceFreshnessTitle;

  /// No description provided for @financeAgentWeeklyWealthInsightPriceFreshnessBody.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings have stale prices.'**
  String financeAgentWeeklyWealthInsightPriceFreshnessBody(Object count);

  /// No description provided for @financeAgentWeeklyWealthInsightFxCoverageTitle.
  ///
  /// In en, this message translates to:
  /// **'FX coverage'**
  String get financeAgentWeeklyWealthInsightFxCoverageTitle;

  /// No description provided for @financeAgentWeeklyWealthInsightFxCoverageBody.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings were excluded because FX conversion is missing.'**
  String financeAgentWeeklyWealthInsightFxCoverageBody(Object count);

  /// No description provided for @financeAgentWeeklyWealthAction.
  ///
  /// In en, this message translates to:
  /// **'Review wealth'**
  String get financeAgentWeeklyWealthAction;

  /// No description provided for @financeAgentCashflowSkipNoAnomaly.
  ///
  /// In en, this message translates to:
  /// **'no cashflow anomaly detected'**
  String get financeAgentCashflowSkipNoAnomaly;

  /// No description provided for @financeAgentCashflowTitle.
  ///
  /// In en, this message translates to:
  /// **'Cashflow Anomaly Review'**
  String get financeAgentCashflowTitle;

  /// No description provided for @financeAgentCashflowDirectionHigher.
  ///
  /// In en, this message translates to:
  /// **'higher'**
  String get financeAgentCashflowDirectionHigher;

  /// No description provided for @financeAgentCashflowDirectionLower.
  ///
  /// In en, this message translates to:
  /// **'lower'**
  String get financeAgentCashflowDirectionLower;

  /// No description provided for @financeAgentCashflowSummary.
  ///
  /// In en, this message translates to:
  /// **'Cashflow anomaly review: projected monthly spending is {delta} vs. the previous 3-month average.'**
  String financeAgentCashflowSummary(Object delta);

  /// No description provided for @financeAgentCashflowInsightProjectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly spending projection'**
  String get financeAgentCashflowInsightProjectionTitle;

  /// No description provided for @financeAgentCashflowInsightProjectionBody.
  ///
  /// In en, this message translates to:
  /// **'Current-month spending is projected {direction} than the previous 3-month average by {delta}.'**
  String financeAgentCashflowInsightProjectionBody(
    Object delta,
    Object direction,
  );

  /// No description provided for @financeAgentCashflowInsightDetectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Detector source'**
  String get financeAgentCashflowInsightDetectorTitle;

  /// No description provided for @financeAgentCashflowInsightDetectorBody.
  ///
  /// In en, this message translates to:
  /// **'This result comes from the on-device anomaly detector used by get_anomaly_flags.'**
  String get financeAgentCashflowInsightDetectorBody;

  /// No description provided for @financeAgentCashflowEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Monthly expense anomaly'**
  String get financeAgentCashflowEvidenceLabel;

  /// No description provided for @financeAgentCashflowAction.
  ///
  /// In en, this message translates to:
  /// **'Review anomaly'**
  String get financeAgentCashflowAction;

  /// No description provided for @financeAgentFireSkipNoPlan.
  ///
  /// In en, this message translates to:
  /// **'no FIRE plan configured'**
  String get financeAgentFireSkipNoPlan;

  /// No description provided for @financeAgentFireSkipNoDrift.
  ///
  /// In en, this message translates to:
  /// **'no FIRE plan drift detected'**
  String get financeAgentFireSkipNoDrift;

  /// No description provided for @financeAgentFireTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE Plan Drift Monitor'**
  String get financeAgentFireTitle;

  /// No description provided for @financeAgentFireInsightPlanSnapshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan snapshot'**
  String get financeAgentFireInsightPlanSnapshotTitle;

  /// No description provided for @financeAgentFireInsightPlanSnapshotBody.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate {withdrawalRate} vs. safe rate {safeRate}, cash bucket {cashBucketMonths} / {targetCashBucketMonths} months.'**
  String financeAgentFireInsightPlanSnapshotBody(
    Object cashBucketMonths,
    Object safeRate,
    Object targetCashBucketMonths,
    Object withdrawalRate,
  );

  /// No description provided for @financeAgentFireEvidenceReviewLabel.
  ///
  /// In en, this message translates to:
  /// **'FIRE review {periodKey}'**
  String financeAgentFireEvidenceReviewLabel(Object periodKey);

  /// No description provided for @financeAgentFireEvidenceReviewBody.
  ///
  /// In en, this message translates to:
  /// **'A deterministic snapshot of current plan metrics, assets, and risk thresholds.'**
  String get financeAgentFireEvidenceReviewBody;

  /// No description provided for @financeAgentFireAction.
  ///
  /// In en, this message translates to:
  /// **'Review FIRE plan'**
  String get financeAgentFireAction;

  /// No description provided for @financeAgentFireActionBody.
  ///
  /// In en, this message translates to:
  /// **'Open FIRE to review and adjust plan assumptions.'**
  String get financeAgentFireActionBody;

  /// No description provided for @financeAgentFireSummaryWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Current withdrawal rate is {withdrawalRate}; the safe rate is {safeRate}'**
  String financeAgentFireSummaryWithdrawal(
    Object safeRate,
    Object withdrawalRate,
  );

  /// No description provided for @financeAgentFireSummaryStress.
  ///
  /// In en, this message translates to:
  /// **'{failedCount} stress scenarios did not pass'**
  String financeAgentFireSummaryStress(int failedCount);

  /// No description provided for @financeAgentFireSummarySeparator.
  ///
  /// In en, this message translates to:
  /// **'. '**
  String get financeAgentFireSummarySeparator;

  /// No description provided for @financeAgentFireMetricWithdrawalRate.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate'**
  String get financeAgentFireMetricWithdrawalRate;

  /// No description provided for @financeAgentFireMetricSafeRate.
  ///
  /// In en, this message translates to:
  /// **'Safe rate'**
  String get financeAgentFireMetricSafeRate;

  /// No description provided for @financeAgentFireMetricCashBucket.
  ///
  /// In en, this message translates to:
  /// **'Cash runway'**
  String get financeAgentFireMetricCashBucket;

  /// No description provided for @financeAgentFireMetricTarget.
  ///
  /// In en, this message translates to:
  /// **'Plan target'**
  String get financeAgentFireMetricTarget;

  /// No description provided for @financeAgentFireMetricTargetMonths.
  ///
  /// In en, this message translates to:
  /// **'Target {months} months'**
  String financeAgentFireMetricTargetMonths(int months);

  /// No description provided for @financeAgentFireMetricExcess.
  ///
  /// In en, this message translates to:
  /// **'Above safe rate'**
  String get financeAgentFireMetricExcess;

  /// No description provided for @financeAgentFireMetricAffectedItems.
  ///
  /// In en, this message translates to:
  /// **'Affected items'**
  String get financeAgentFireMetricAffectedItems;

  /// No description provided for @financeAgentFireMetricNetWorthAfter.
  ///
  /// In en, this message translates to:
  /// **'Net worth after test'**
  String get financeAgentFireMetricNetWorthAfter;

  /// No description provided for @financeAgentFireMetricWithdrawalAfter.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate after test'**
  String get financeAgentFireMetricWithdrawalAfter;

  /// No description provided for @financeAgentFireMetricCashAfter.
  ///
  /// In en, this message translates to:
  /// **'Cash runway after test'**
  String get financeAgentFireMetricCashAfter;

  /// No description provided for @financeAgentFireMonthsValue.
  ///
  /// In en, this message translates to:
  /// **'{value} months'**
  String financeAgentFireMonthsValue(Object value);

  /// No description provided for @financeAgentFirePercentagePoints.
  ///
  /// In en, this message translates to:
  /// **'{value} pp'**
  String financeAgentFirePercentagePoints(Object value);

  /// No description provided for @financeAgentFireStressGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} stress scenarios did not pass'**
  String financeAgentFireStressGroupTitle(int count);

  /// No description provided for @financeAgentFireStressGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Risk is concentrated in: {scenarios}.'**
  String financeAgentFireStressGroupBody(Object scenarios);

  /// No description provided for @financeAgentFireScenarioSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get financeAgentFireScenarioSeparator;

  /// No description provided for @financeAgentFireScenarioMarketDrawdown.
  ///
  /// In en, this message translates to:
  /// **'Market drawdown'**
  String get financeAgentFireScenarioMarketDrawdown;

  /// No description provided for @financeAgentFireScenarioExpenseSurge.
  ///
  /// In en, this message translates to:
  /// **'Higher living costs'**
  String get financeAgentFireScenarioExpenseSurge;

  /// No description provided for @financeAgentFireScenarioOneOffShock.
  ///
  /// In en, this message translates to:
  /// **'One-off expense'**
  String get financeAgentFireScenarioOneOffShock;

  /// No description provided for @financeAgentFireScenarioFxShock.
  ///
  /// In en, this message translates to:
  /// **'FX shock'**
  String get financeAgentFireScenarioFxShock;

  /// No description provided for @financeAgentFireScenarioCashDepletion.
  ///
  /// In en, this message translates to:
  /// **'Cash depletion'**
  String get financeAgentFireScenarioCashDepletion;

  /// No description provided for @financeAgentFireScenarioUnknown.
  ///
  /// In en, this message translates to:
  /// **'Other stress scenario'**
  String get financeAgentFireScenarioUnknown;

  /// No description provided for @financeAgentFireStressVerdictSafe.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get financeAgentFireStressVerdictSafe;

  /// No description provided for @financeAgentFireStressVerdictCautious.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get financeAgentFireStressVerdictCautious;

  /// No description provided for @financeAgentFireStressVerdictDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get financeAgentFireStressVerdictDanger;

  /// No description provided for @financeAgentFireStressResultContext.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate {withdrawalRate} · cash runway {cashBucketMonths} months'**
  String financeAgentFireStressResultContext(
    Object cashBucketMonths,
    Object withdrawalRate,
  );

  /// No description provided for @financeAgentFireTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Since last review'**
  String get financeAgentFireTrendTitle;

  /// No description provided for @financeAgentFireTrendBody.
  ///
  /// In en, this message translates to:
  /// **'{changes}.'**
  String financeAgentFireTrendBody(Object changes);

  /// No description provided for @financeAgentFireTrendWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate'**
  String get financeAgentFireTrendWithdrawal;

  /// No description provided for @financeAgentFireTrendNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get financeAgentFireTrendNetWorth;

  /// No description provided for @financeAgentFireTrendSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety level'**
  String get financeAgentFireTrendSafety;

  /// No description provided for @financeAgentFireMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'Deterministic on-device calculation'**
  String get financeAgentFireMethodTitle;

  /// No description provided for @financeAgentFireMethodBody.
  ///
  /// In en, this message translates to:
  /// **'Calculated from the FIRE plan, assets, annual spending, and stress tests; AI does not determine the metrics.'**
  String get financeAgentFireMethodBody;

  /// No description provided for @financeAgentFireMethodPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Review period'**
  String get financeAgentFireMethodPeriodLabel;

  /// No description provided for @financeAgentFireMethodModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Calculation'**
  String get financeAgentFireMethodModeLabel;

  /// No description provided for @financeAgentFireMethodModeValue.
  ///
  /// In en, this message translates to:
  /// **'On device · no cloud inference'**
  String get financeAgentFireMethodModeValue;

  /// No description provided for @financeAgentFireFindingCashBucketBelowTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash bucket below target'**
  String get financeAgentFireFindingCashBucketBelowTargetTitle;

  /// No description provided for @financeAgentFireFindingWithdrawalRateAboveSwrTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate above safe rate'**
  String get financeAgentFireFindingWithdrawalRateAboveSwrTitle;

  /// No description provided for @financeAgentFireFindingWithdrawalRateInfiniteTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate unavailable'**
  String get financeAgentFireFindingWithdrawalRateInfiniteTitle;

  /// No description provided for @financeAgentFireFindingEtaUnreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE ETA unreachable'**
  String get financeAgentFireFindingEtaUnreachableTitle;

  /// No description provided for @financeAgentFireFindingCurrencyGapTitle.
  ///
  /// In en, this message translates to:
  /// **'FX coverage gap'**
  String get financeAgentFireFindingCurrencyGapTitle;

  /// No description provided for @financeAgentFireFindingUnmappedHoldingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Unmapped FIRE holdings'**
  String get financeAgentFireFindingUnmappedHoldingsTitle;

  /// No description provided for @financeAgentFireFindingStressDangerTitle.
  ///
  /// In en, this message translates to:
  /// **'Stress test danger'**
  String get financeAgentFireFindingStressDangerTitle;

  /// No description provided for @financeAgentFireFindingStressCautiousTitle.
  ///
  /// In en, this message translates to:
  /// **'Stress test caution'**
  String get financeAgentFireFindingStressCautiousTitle;

  /// No description provided for @financeAgentFireFindingNetWorthBrokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth below zero'**
  String get financeAgentFireFindingNetWorthBrokenTitle;

  /// No description provided for @financeAgentFireFindingCashBucketBelowTargetBody.
  ///
  /// In en, this message translates to:
  /// **'Cash runway is below the configured target of {months} months.'**
  String financeAgentFireFindingCashBucketBelowTargetBody(Object months);

  /// No description provided for @financeAgentFireFindingWithdrawalRateAboveSwrBody.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal rate is above the safe withdrawal rate by {rate}.'**
  String financeAgentFireFindingWithdrawalRateAboveSwrBody(Object rate);

  /// No description provided for @financeAgentFireFindingWithdrawalRateInfiniteBody.
  ///
  /// In en, this message translates to:
  /// **'Annual spend exists, but investable assets are zero.'**
  String get financeAgentFireFindingWithdrawalRateInfiniteBody;

  /// No description provided for @financeAgentFireFindingEtaUnreachableBody.
  ///
  /// In en, this message translates to:
  /// **'Projection did not reach the FIRE target in the modeled horizon.'**
  String get financeAgentFireFindingEtaUnreachableBody;

  /// No description provided for @financeAgentFireFindingCurrencyGapBody.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings are excluded because FX conversion is missing.'**
  String financeAgentFireFindingCurrencyGapBody(Object count);

  /// No description provided for @financeAgentFireFindingUnmappedHoldingsBody.
  ///
  /// In en, this message translates to:
  /// **'{count} holdings are not mapped to FIRE buckets.'**
  String financeAgentFireFindingUnmappedHoldingsBody(Object count);

  /// No description provided for @financeAgentFireFindingStressDangerBody.
  ///
  /// In en, this message translates to:
  /// **'Stress scenario {scenario} breaks the plan.'**
  String financeAgentFireFindingStressDangerBody(Object scenario);

  /// No description provided for @financeAgentFireFindingStressCautiousBody.
  ///
  /// In en, this message translates to:
  /// **'Stress scenario {scenario} needs attention.'**
  String financeAgentFireFindingStressCautiousBody(Object scenario);

  /// No description provided for @financeAgentFireFindingNetWorthBrokenBody.
  ///
  /// In en, this message translates to:
  /// **'Net worth is below zero, so the FIRE plan needs review.'**
  String get financeAgentFireFindingNetWorthBrokenBody;

  /// No description provided for @financeAgentFireFindingDefaultBody.
  ///
  /// In en, this message translates to:
  /// **'Review finding {code}.'**
  String financeAgentFireFindingDefaultBody(Object code);

  /// No description provided for @financeAgentOptionsSkipNoScan.
  ///
  /// In en, this message translates to:
  /// **'no options income scan available'**
  String get financeAgentOptionsSkipNoScan;

  /// No description provided for @financeAgentOptionsSkipNoFinding.
  ///
  /// In en, this message translates to:
  /// **'no options income risk finding'**
  String get financeAgentOptionsSkipNoFinding;

  /// No description provided for @financeAgentOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Options Income Risk Review'**
  String get financeAgentOptionsTitle;

  /// No description provided for @financeAgentOptionsSummary.
  ///
  /// In en, this message translates to:
  /// **'Options income risk review: {issueTitle} across {opportunityCount} opportunities in {scanId}; {elevatedCount} elevated-risk contracts.'**
  String financeAgentOptionsSummary(
    Object elevatedCount,
    Object issueTitle,
    Object opportunityCount,
    Object scanId,
  );

  /// No description provided for @financeAgentOptionsIssueStaleScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan data is stale'**
  String get financeAgentOptionsIssueStaleScanTitle;

  /// No description provided for @financeAgentOptionsIssueStaleScanBody.
  ///
  /// In en, this message translates to:
  /// **'Latest options-income scan is {ageHours} hours old; quotes and greeks may no longer reflect the market.'**
  String financeAgentOptionsIssueStaleScanBody(Object ageHours);

  /// No description provided for @financeAgentOptionsIssueElevatedRiskTitle.
  ///
  /// In en, this message translates to:
  /// **'Elevated-risk contracts present'**
  String get financeAgentOptionsIssueElevatedRiskTitle;

  /// No description provided for @financeAgentOptionsIssueElevatedRiskBody.
  ///
  /// In en, this message translates to:
  /// **'{count} cached opportunities are classified as elevated risk before trade review.'**
  String financeAgentOptionsIssueElevatedRiskBody(Object count);

  /// No description provided for @financeAgentOptionsIssueQuoteQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Quote quality needs review'**
  String get financeAgentOptionsIssueQuoteQualityTitle;

  /// No description provided for @financeAgentOptionsIssueQuoteQualityBody.
  ///
  /// In en, this message translates to:
  /// **'{wideSpreadCount} opportunities have bid/ask spread above 8%, and {thinBookCount} have thin volume or open interest.'**
  String financeAgentOptionsIssueQuoteQualityBody(
    Object thinBookCount,
    Object wideSpreadCount,
  );

  /// No description provided for @financeAgentOptionsIssueNarrowCushionTitle.
  ///
  /// In en, this message translates to:
  /// **'Margin of safety is narrow'**
  String get financeAgentOptionsIssueNarrowCushionTitle;

  /// No description provided for @financeAgentOptionsIssueNarrowCushionBody.
  ///
  /// In en, this message translates to:
  /// **'{count} opportunities have less than 5% margin of safety to breakeven.'**
  String financeAgentOptionsIssueNarrowCushionBody(Object count);

  /// No description provided for @financeAgentOptionsIssueMissingGreeksTitle.
  ///
  /// In en, this message translates to:
  /// **'Risk inputs are incomplete'**
  String get financeAgentOptionsIssueMissingGreeksTitle;

  /// No description provided for @financeAgentOptionsIssueMissingGreeksBody.
  ///
  /// In en, this message translates to:
  /// **'{count} opportunities are missing delta or implied volatility from the quote source.'**
  String financeAgentOptionsIssueMissingGreeksBody(Object count);

  /// No description provided for @financeAgentOptionsIssueConcentrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Underlying concentration is high'**
  String get financeAgentOptionsIssueConcentrationTitle;

  /// No description provided for @financeAgentOptionsIssueConcentrationBody.
  ///
  /// In en, this message translates to:
  /// **'{count} of {opportunityCount} opportunities are tied to {underlying}.'**
  String financeAgentOptionsIssueConcentrationBody(
    Object count,
    Object opportunityCount,
    Object underlying,
  );

  /// No description provided for @financeAgentOptionsIssueModerateClusterTitle.
  ///
  /// In en, this message translates to:
  /// **'Moderate-risk cluster'**
  String get financeAgentOptionsIssueModerateClusterTitle;

  /// No description provided for @financeAgentOptionsIssueModerateClusterBody.
  ///
  /// In en, this message translates to:
  /// **'{moderateCount} of {opportunityCount} opportunities are moderate risk; review sizing before using the scan.'**
  String financeAgentOptionsIssueModerateClusterBody(
    Object moderateCount,
    Object opportunityCount,
  );

  /// No description provided for @financeAgentOptionsInsightScanSnapshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan snapshot'**
  String get financeAgentOptionsInsightScanSnapshotTitle;

  /// No description provided for @financeAgentOptionsInsightScanSnapshotBody.
  ///
  /// In en, this message translates to:
  /// **'{opportunityCount} cached opportunities, risk mix {riskMix}.'**
  String financeAgentOptionsInsightScanSnapshotBody(
    Object opportunityCount,
    Object riskMix,
  );

  /// No description provided for @financeAgentOptionsRiskMix.
  ///
  /// In en, this message translates to:
  /// **'{low} low / {moderate} moderate / {elevated} elevated'**
  String financeAgentOptionsRiskMix(
    Object elevated,
    Object low,
    Object moderate,
  );

  /// No description provided for @financeAgentOptionsEvidenceScanLabel.
  ///
  /// In en, this message translates to:
  /// **'Options income scan {scanId}'**
  String financeAgentOptionsEvidenceScanLabel(Object scanId);

  /// No description provided for @financeAgentOptionsAction.
  ///
  /// In en, this message translates to:
  /// **'Review options scan'**
  String get financeAgentOptionsAction;

  /// No description provided for @healthAgentRecoverySkipInsufficient.
  ///
  /// In en, this message translates to:
  /// **'insufficient HRV data ({count} points)'**
  String healthAgentRecoverySkipInsufficient(Object count);

  /// No description provided for @healthAgentRecoverySkipNoDecline.
  ///
  /// In en, this message translates to:
  /// **'no sustained HRV decline detected'**
  String get healthAgentRecoverySkipNoDecline;

  /// No description provided for @healthAgentRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery Alert'**
  String get healthAgentRecoveryTitle;

  /// No description provided for @healthAgentRecoverySummary.
  ///
  /// In en, this message translates to:
  /// **'HRV has been below your baseline for {days} days ({recentMs} ms vs {baselineMs} ms average, {declinePct}% decline). Consider lighter activity today.'**
  String healthAgentRecoverySummary(
    Object baselineMs,
    Object days,
    Object declinePct,
    Object recentMs,
  );

  /// No description provided for @healthAgentRecoveryInsightDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'HRV decline'**
  String get healthAgentRecoveryInsightDeclineTitle;

  /// No description provided for @healthAgentRecoveryInsightDeclineBody.
  ///
  /// In en, this message translates to:
  /// **'{days} days below baseline; {declinePct}% lower than usual.'**
  String healthAgentRecoveryInsightDeclineBody(Object days, Object declinePct);

  /// No description provided for @healthAgentRecoveryInsightAdjustmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested adjustment'**
  String get healthAgentRecoveryInsightAdjustmentTitle;

  /// No description provided for @healthAgentRecoveryInsightAdjustmentBody.
  ///
  /// In en, this message translates to:
  /// **'Consider lighter activity today and watch recovery tomorrow.'**
  String get healthAgentRecoveryInsightAdjustmentBody;

  /// No description provided for @healthAgentRecoveryEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'HRV trend'**
  String get healthAgentRecoveryEvidenceLabel;

  /// No description provided for @healthAgentRecoveryAction.
  ///
  /// In en, this message translates to:
  /// **'Review recovery alert'**
  String get healthAgentRecoveryAction;

  /// No description provided for @healthAgentWeeklySkipNoData.
  ///
  /// In en, this message translates to:
  /// **'no health data this week'**
  String get healthAgentWeeklySkipNoData;

  /// No description provided for @healthAgentWeeklySkipNoActionable.
  ///
  /// In en, this message translates to:
  /// **'no actionable signals this week'**
  String get healthAgentWeeklySkipNoActionable;

  /// No description provided for @healthAgentWeeklyTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get healthAgentWeeklyTitle;

  /// No description provided for @healthAgentWeeklyPartRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery {score}/100 ({verdict})'**
  String healthAgentWeeklyPartRecovery(Object score, Object verdict);

  /// No description provided for @healthAgentWeeklyPartAvgSleep.
  ///
  /// In en, this message translates to:
  /// **'avg sleep {hours}h'**
  String healthAgentWeeklyPartAvgSleep(Object hours);

  /// No description provided for @healthAgentWeeklyPartSteps.
  ///
  /// In en, this message translates to:
  /// **'{steps} steps'**
  String healthAgentWeeklyPartSteps(Object steps);

  /// No description provided for @healthAgentWeeklyPartWorkouts.
  ///
  /// In en, this message translates to:
  /// **'{count} workouts ({minutes} min)'**
  String healthAgentWeeklyPartWorkouts(Object count, Object minutes);

  /// No description provided for @healthAgentWeeklySummary.
  ///
  /// In en, this message translates to:
  /// **'This week: {details}.'**
  String healthAgentWeeklySummary(Object details);

  /// No description provided for @healthAgentWeeklyInsightRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get healthAgentWeeklyInsightRecoveryTitle;

  /// No description provided for @healthAgentWeeklyInsightRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'{score}/100{verdictSuffix}'**
  String healthAgentWeeklyInsightRecoveryBody(
    Object score,
    Object verdictSuffix,
  );

  /// No description provided for @healthAgentWeeklyInsightSleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get healthAgentWeeklyInsightSleepTitle;

  /// No description provided for @healthAgentWeeklyInsightSleepBody.
  ///
  /// In en, this message translates to:
  /// **'Average {hours}h per night.'**
  String healthAgentWeeklyInsightSleepBody(Object hours);

  /// No description provided for @healthAgentWeeklyInsightActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get healthAgentWeeklyInsightActivityTitle;

  /// No description provided for @healthAgentWeeklyInsightActivityBody.
  ///
  /// In en, this message translates to:
  /// **'{steps} steps this week.'**
  String healthAgentWeeklyInsightActivityBody(Object steps);

  /// No description provided for @healthAgentWeeklyInsightWorkoutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get healthAgentWeeklyInsightWorkoutsTitle;

  /// No description provided for @healthAgentWeeklyInsightWorkoutsBody.
  ///
  /// In en, this message translates to:
  /// **'{count} workouts, {minutes} minutes total.'**
  String healthAgentWeeklyInsightWorkoutsBody(Object count, Object minutes);

  /// No description provided for @healthAgentWeeklyEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly health rollup'**
  String get healthAgentWeeklyEvidenceLabel;

  /// No description provided for @healthAgentWeeklyAction.
  ///
  /// In en, this message translates to:
  /// **'Review weekly summary'**
  String get healthAgentWeeklyAction;

  /// No description provided for @executionAgentReviewSkipNoSignals.
  ///
  /// In en, this message translates to:
  /// **'no execution signals to review'**
  String get executionAgentReviewSkipNoSignals;

  /// No description provided for @executionAgentReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution review'**
  String get executionAgentReviewTitle;

  /// No description provided for @executionAgentReviewSummary.
  ///
  /// In en, this message translates to:
  /// **'Execution review: {details}.{sample}'**
  String executionAgentReviewSummary(Object details, Object sample);

  /// No description provided for @executionAgentReviewSummaryPartToday.
  ///
  /// In en, this message translates to:
  /// **'{count} today actions'**
  String executionAgentReviewSummaryPartToday(Object count);

  /// No description provided for @executionAgentReviewSummaryPartOpen.
  ///
  /// In en, this message translates to:
  /// **'{count} open actions'**
  String executionAgentReviewSummaryPartOpen(Object count);

  /// No description provided for @executionAgentReviewSummaryPartProjects.
  ///
  /// In en, this message translates to:
  /// **'{count} active projects'**
  String executionAgentReviewSummaryPartProjects(Object count);

  /// No description provided for @executionAgentReviewSummaryPartCommitments.
  ///
  /// In en, this message translates to:
  /// **'{count} active commitments'**
  String executionAgentReviewSummaryPartCommitments(Object count);

  /// No description provided for @executionAgentReviewSummaryPartProgress.
  ///
  /// In en, this message translates to:
  /// **'{count} progress entries this week'**
  String executionAgentReviewSummaryPartProgress(Object count);

  /// No description provided for @executionAgentReviewSummaryPartBlocked.
  ///
  /// In en, this message translates to:
  /// **'{count} blocked'**
  String executionAgentReviewSummaryPartBlocked(Object count);

  /// No description provided for @executionAgentReviewSummaryPartDue.
  ///
  /// In en, this message translates to:
  /// **'{count} due'**
  String executionAgentReviewSummaryPartDue(Object count);

  /// No description provided for @executionAgentReviewSummaryFirst.
  ///
  /// In en, this message translates to:
  /// **' First: {title}.'**
  String executionAgentReviewSummaryFirst(Object title);

  /// No description provided for @executionAgentReviewInsightTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today focus'**
  String get executionAgentReviewInsightTodayTitle;

  /// No description provided for @executionAgentReviewInsightTodayBody.
  ///
  /// In en, this message translates to:
  /// **'{todayCount} today-worthy actions out of {openCount} open actions.'**
  String executionAgentReviewInsightTodayBody(
    Object openCount,
    Object todayCount,
  );

  /// No description provided for @executionAgentReviewInsightBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked work'**
  String get executionAgentReviewInsightBlockedTitle;

  /// No description provided for @executionAgentReviewInsightBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'{count} actions are blocked.'**
  String executionAgentReviewInsightBlockedBody(Object count);

  /// No description provided for @executionAgentReviewInsightDueTitle.
  ///
  /// In en, this message translates to:
  /// **'Due work'**
  String get executionAgentReviewInsightDueTitle;

  /// No description provided for @executionAgentReviewInsightDueBody.
  ///
  /// In en, this message translates to:
  /// **'{count} actions are due.'**
  String executionAgentReviewInsightDueBody(Object count);

  /// No description provided for @executionAgentReviewInsightProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly progress'**
  String get executionAgentReviewInsightProgressTitle;

  /// No description provided for @executionAgentReviewInsightProgressBody.
  ///
  /// In en, this message translates to:
  /// **'{progressCount} progress entries across {projectCount} active projects and {commitmentCount} active commitments.'**
  String executionAgentReviewInsightProgressBody(
    Object commitmentCount,
    Object progressCount,
    Object projectCount,
  );

  /// No description provided for @executionAgentReviewInsightStalledTitle.
  ///
  /// In en, this message translates to:
  /// **'Stalled work'**
  String get executionAgentReviewInsightStalledTitle;

  /// No description provided for @executionAgentReviewInsightStalledBody.
  ///
  /// In en, this message translates to:
  /// **'{count} in-progress actions have not changed for at least 7 days.'**
  String executionAgentReviewInsightStalledBody(Object count);

  /// No description provided for @executionAgentReviewInsightNoNextActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Missing next actions'**
  String get executionAgentReviewInsightNoNextActionTitle;

  /// No description provided for @executionAgentReviewInsightNoNextActionBody.
  ///
  /// In en, this message translates to:
  /// **'{projectCount} active projects and {commitmentCount} active commitments have no open next action.'**
  String executionAgentReviewInsightNoNextActionBody(
    Object commitmentCount,
    Object projectCount,
  );

  /// No description provided for @executionAgentReviewInsightOverdueTargetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Overdue targets'**
  String get executionAgentReviewInsightOverdueTargetsTitle;

  /// No description provided for @executionAgentReviewInsightOverdueTargetsBody.
  ///
  /// In en, this message translates to:
  /// **'{projectCount} projects and {commitmentCount} commitments are past their target date.'**
  String executionAgentReviewInsightOverdueTargetsBody(
    Object commitmentCount,
    Object projectCount,
  );

  /// No description provided for @executionAgentReviewInsightRepeatedBlockerTitle.
  ///
  /// In en, this message translates to:
  /// **'Repeated blockers'**
  String get executionAgentReviewInsightRepeatedBlockerTitle;

  /// No description provided for @executionAgentReviewInsightRepeatedBlockerBody.
  ///
  /// In en, this message translates to:
  /// **'{count} actions recorded blockers more than once this week.'**
  String executionAgentReviewInsightRepeatedBlockerBody(Object count);

  /// No description provided for @executionAgentReviewInsightOverloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Today is overloaded'**
  String get executionAgentReviewInsightOverloadTitle;

  /// No description provided for @executionAgentReviewInsightOverloadBody.
  ///
  /// In en, this message translates to:
  /// **'{count} actions compete for today. Narrow the focus to about {limit}.'**
  String executionAgentReviewInsightOverloadBody(Object count, Object limit);

  /// No description provided for @executionAgentReviewInsightThroughputTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly throughput'**
  String get executionAgentReviewInsightThroughputTitle;

  /// No description provided for @executionAgentReviewInsightThroughputBody.
  ///
  /// In en, this message translates to:
  /// **'{completedCount} actions completed and {droppedCount} dropped this week.'**
  String executionAgentReviewInsightThroughputBody(
    Object completedCount,
    Object droppedCount,
  );

  /// No description provided for @executionAgentReviewInsightOutcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Source signals after completion'**
  String get executionAgentReviewInsightOutcomeTitle;

  /// No description provided for @executionAgentReviewInsightOutcomeBody.
  ///
  /// In en, this message translates to:
  /// **'{clearedCount} source signals are no longer detected and {activeCount} are still detected after their actions closed.'**
  String executionAgentReviewInsightOutcomeBody(
    Object activeCount,
    Object clearedCount,
  );

  /// No description provided for @executionAgentReviewPlanAction.
  ///
  /// In en, this message translates to:
  /// **'Create a recovery plan'**
  String get executionAgentReviewPlanAction;

  /// No description provided for @executionAgentReviewPlanActionBody.
  ///
  /// In en, this message translates to:
  /// **'Review stalled and unowned work, then propose concrete next actions or status updates for confirmation.'**
  String get executionAgentReviewPlanActionBody;

  /// No description provided for @executionAgentReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review execution'**
  String get executionAgentReviewAction;

  /// No description provided for @knowledgeAgentReviewArtifactTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Knowledge Review'**
  String get knowledgeAgentReviewArtifactTitle;

  /// No description provided for @knowledgeAgentReviewInsightDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Decisions due'**
  String get knowledgeAgentReviewInsightDecisionsTitle;

  /// No description provided for @knowledgeAgentReviewInsightDecisionsBody.
  ///
  /// In en, this message translates to:
  /// **'{count} decision review{plural} need attention.'**
  String knowledgeAgentReviewInsightDecisionsBody(Object count, Object plural);

  /// No description provided for @knowledgeAgentReviewInsightAssumptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stale assumptions'**
  String get knowledgeAgentReviewInsightAssumptionsTitle;

  /// No description provided for @knowledgeAgentReviewInsightAssumptionsBody.
  ///
  /// In en, this message translates to:
  /// **'{count} assumption{plural} crossed the {days} day verification window.'**
  String knowledgeAgentReviewInsightAssumptionsBody(
    Object count,
    Object days,
    Object plural,
  );

  /// No description provided for @knowledgeAgentReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review knowledge items'**
  String get knowledgeAgentReviewAction;

  /// No description provided for @knowledgeAgentAssumptionArtifactTitle.
  ///
  /// In en, this message translates to:
  /// **'Assumption Review'**
  String get knowledgeAgentAssumptionArtifactTitle;

  /// No description provided for @knowledgeAgentAssumptionInsightTitle.
  ///
  /// In en, this message translates to:
  /// **'Stale assumptions'**
  String get knowledgeAgentAssumptionInsightTitle;

  /// No description provided for @knowledgeAgentAssumptionInsightBody.
  ///
  /// In en, this message translates to:
  /// **'{count} assumption{plural} crossed the {days} day verification window.'**
  String knowledgeAgentAssumptionInsightBody(
    Object count,
    Object days,
    Object plural,
  );

  /// No description provided for @knowledgeAgentAssumptionAction.
  ///
  /// In en, this message translates to:
  /// **'Review assumptions'**
  String get knowledgeAgentAssumptionAction;

  /// No description provided for @knowledgeAgentContradictionArtifactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contradiction Check'**
  String get knowledgeAgentContradictionArtifactTitle;

  /// No description provided for @knowledgeAgentContradictionInsightInvalidatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Invalidated assumptions'**
  String get knowledgeAgentContradictionInsightInvalidatedTitle;

  /// No description provided for @knowledgeAgentContradictionInsightInvalidatedBody.
  ///
  /// In en, this message translates to:
  /// **'{count} decision{plural} cite assumptions that are no longer open.'**
  String knowledgeAgentContradictionInsightInvalidatedBody(
    Object count,
    Object plural,
  );

  /// No description provided for @knowledgeAgentContradictionInsightPrincipleTitle.
  ///
  /// In en, this message translates to:
  /// **'Principle drift'**
  String get knowledgeAgentContradictionInsightPrincipleTitle;

  /// No description provided for @knowledgeAgentContradictionInsightPrincipleBody.
  ///
  /// In en, this message translates to:
  /// **'{count} recent item{plural} may conflict with active principles.'**
  String knowledgeAgentContradictionInsightPrincipleBody(
    Object count,
    Object plural,
  );

  /// No description provided for @knowledgeAgentContradictionAction.
  ///
  /// In en, this message translates to:
  /// **'Review contradictions'**
  String get knowledgeAgentContradictionAction;

  /// No description provided for @knowledgeAgentInboxSkipNoNotes.
  ///
  /// In en, this message translates to:
  /// **'no untriaged notes'**
  String get knowledgeAgentInboxSkipNoNotes;

  /// No description provided for @knowledgeAgentInboxSummaryNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Reviewed {noteCount} notes and found no suggestions worth proposing.'**
  String knowledgeAgentInboxSummaryNoSuggestions(Object noteCount);

  /// No description provided for @knowledgeAgentInboxSummarySuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generated {proposalCount} suggestions for {noteCount} notes.'**
  String knowledgeAgentInboxSummarySuggestions(
    Object noteCount,
    Object proposalCount,
  );

  /// No description provided for @knowledgeAgentInboxArtifactTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox Triage'**
  String get knowledgeAgentInboxArtifactTitle;

  /// No description provided for @knowledgeAgentInboxInsightSuggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'New suggestions'**
  String get knowledgeAgentInboxInsightSuggestionsTitle;

  /// No description provided for @knowledgeAgentInboxInsightSuggestionsBody.
  ///
  /// In en, this message translates to:
  /// **'{proposalCount} suggestion{proposalPlural} across {noteCount} note{notePlural}.'**
  String knowledgeAgentInboxInsightSuggestionsBody(
    Object noteCount,
    Object notePlural,
    Object proposalCount,
    Object proposalPlural,
  );

  /// No description provided for @knowledgeAgentInboxSuggestionKindBody.
  ///
  /// In en, this message translates to:
  /// **'{count} {label}.'**
  String knowledgeAgentInboxSuggestionKindBody(Object count, Object label);

  /// No description provided for @knowledgeAgentInboxUntitledNote.
  ///
  /// In en, this message translates to:
  /// **'Untitled note'**
  String get knowledgeAgentInboxUntitledNote;

  /// No description provided for @knowledgeAgentInboxProposalClassification.
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get knowledgeAgentInboxProposalClassification;

  /// No description provided for @knowledgeAgentInboxProposalTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get knowledgeAgentInboxProposalTags;

  /// No description provided for @knowledgeAgentInboxProposalDecisionLinks.
  ///
  /// In en, this message translates to:
  /// **'Decision links'**
  String get knowledgeAgentInboxProposalDecisionLinks;

  /// No description provided for @knowledgeAgentInboxProposalSuggestionSingular.
  ///
  /// In en, this message translates to:
  /// **'suggestion'**
  String get knowledgeAgentInboxProposalSuggestionSingular;

  /// No description provided for @knowledgeAgentInboxProposalSuggestionPlural.
  ///
  /// In en, this message translates to:
  /// **'suggestions'**
  String get knowledgeAgentInboxProposalSuggestionPlural;

  /// No description provided for @knowledgeAgentInboxAction.
  ///
  /// In en, this message translates to:
  /// **'Review inbox suggestions'**
  String get knowledgeAgentInboxAction;

  /// No description provided for @ingestKindExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get ingestKindExpense;

  /// No description provided for @ingestKindIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get ingestKindIncome;

  /// No description provided for @ingestKindTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get ingestKindTransfer;

  /// No description provided for @ingestKindTrade.
  ///
  /// In en, this message translates to:
  /// **'Security trade'**
  String get ingestKindTrade;

  /// No description provided for @ingestRecordTransfer.
  ///
  /// In en, this message translates to:
  /// **'Open transfer form'**
  String get ingestRecordTransfer;

  /// No description provided for @ingestRecordTrade.
  ///
  /// In en, this message translates to:
  /// **'Open trade form'**
  String get ingestRecordTrade;

  /// No description provided for @ingestTransferRecorded.
  ///
  /// In en, this message translates to:
  /// **'Transfer recorded and draft completed.'**
  String get ingestTransferRecorded;

  /// No description provided for @ingestTradeRecorded.
  ///
  /// In en, this message translates to:
  /// **'Trade recorded and draft completed.'**
  String get ingestTradeRecorded;

  /// No description provided for @databaseUnlockLoading.
  ///
  /// In en, this message translates to:
  /// **'Unlocking your local data…'**
  String get databaseUnlockLoading;

  /// No description provided for @databaseRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Local data is locked'**
  String get databaseRecoveryTitle;

  /// No description provided for @databaseRecoveryMissingKeyMessage.
  ///
  /// In en, this message translates to:
  /// **'This device no longer has the key for the encrypted local database. Your data has not been overwritten. If you have an encrypted backup, reset this unreadable local copy and restore the backup from Settings.'**
  String get databaseRecoveryMissingKeyMessage;

  /// No description provided for @databaseRecoveryInvalidKeyMessage.
  ///
  /// In en, this message translates to:
  /// **'The stored database key is damaged. Your encrypted local data has not been modified. You can retry or reset this unreadable copy before restoring an encrypted backup.'**
  String get databaseRecoveryInvalidKeyMessage;

  /// No description provided for @databaseRecoveryUnlockFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The device key could not unlock this local database. No data was changed. You can retry or reset the unreadable copy before restoring an encrypted backup.'**
  String get databaseRecoveryUnlockFailedMessage;

  /// No description provided for @databaseRecoveryMigrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Local data upgrade paused'**
  String get databaseRecoveryMigrationTitle;

  /// No description provided for @databaseRecoveryMigrationMessage.
  ///
  /// In en, this message translates to:
  /// **'NaviWealth could not safely finish encrypting the existing database. The original copy is preserved. Retry after checking free storage; do not reset unless you have a verified backup.'**
  String get databaseRecoveryMigrationMessage;

  /// No description provided for @databaseRecoveryUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Local data is unavailable'**
  String get databaseRecoveryUnavailableTitle;

  /// No description provided for @databaseRecoveryUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The secure database could not be opened. Retry first. If the problem continues, keep the app data intact and review the diagnostic log before taking destructive action.'**
  String get databaseRecoveryUnavailableMessage;

  /// No description provided for @databaseRecoveryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry unlock'**
  String get databaseRecoveryRetry;

  /// No description provided for @databaseRecoveryResetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset unreadable local data'**
  String get databaseRecoveryResetAction;

  /// No description provided for @databaseRecoveryResetting.
  ///
  /// In en, this message translates to:
  /// **'Resetting local data…'**
  String get databaseRecoveryResetting;

  /// No description provided for @databaseRecoveryResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset unreadable local data?'**
  String get databaseRecoveryResetConfirmTitle;

  /// No description provided for @databaseRecoveryResetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the encrypted database on this device. It cannot recover a missing device key. Continue only if this local copy is unrecoverable or you have an encrypted backup to restore afterward.'**
  String get databaseRecoveryResetConfirmBody;

  /// No description provided for @databaseRecoveryResetConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Reset local data'**
  String get databaseRecoveryResetConfirmAction;

  /// No description provided for @databaseRecoveryResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Local data could not be reset. Nothing else was changed.'**
  String get databaseRecoveryResetFailed;

  /// No description provided for @financialInboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial inbox'**
  String get financialInboxTitle;

  /// No description provided for @financialInboxPriorityImportant.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get financialInboxPriorityImportant;

  /// No description provided for @financialInboxPriorityAttention.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get financialInboxPriorityAttention;

  /// No description provided for @financialInboxLastCheckedCompact.
  ///
  /// In en, this message translates to:
  /// **'Checked {date}'**
  String financialInboxLastCheckedCompact(String date);

  /// No description provided for @monthlyCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly close'**
  String get monthlyCloseTitle;

  /// No description provided for @monthlyCloseStart.
  ///
  /// In en, this message translates to:
  /// **'Start monthly close'**
  String get monthlyCloseStart;

  /// No description provided for @monthlyCloseStartBody.
  ///
  /// In en, this message translates to:
  /// **'Review this month\'s evidence, reconcile balances, and close with a clear audit trail.'**
  String get monthlyCloseStartBody;

  /// No description provided for @monthlyClosePeriod.
  ///
  /// In en, this message translates to:
  /// **'Close {period}'**
  String monthlyClosePeriod(String period);

  /// No description provided for @monthlyCloseIntro.
  ///
  /// In en, this message translates to:
  /// **'Complete each evidence check before closing the month.'**
  String get monthlyCloseIntro;

  /// No description provided for @monthlyCloseImport.
  ///
  /// In en, this message translates to:
  /// **'Review imported transactions'**
  String get monthlyCloseImport;

  /// No description provided for @monthlyCloseInbox.
  ///
  /// In en, this message translates to:
  /// **'Clear the Financial Inbox'**
  String get monthlyCloseInbox;

  /// No description provided for @monthlyCloseAccounts.
  ///
  /// In en, this message translates to:
  /// **'Reconcile account balances'**
  String get monthlyCloseAccounts;

  /// No description provided for @monthlyCloseRunway.
  ///
  /// In en, this message translates to:
  /// **'Review the next 90 days'**
  String get monthlyCloseRunway;

  /// No description provided for @monthlyCloseActions.
  ///
  /// In en, this message translates to:
  /// **'Review follow-up actions'**
  String get monthlyCloseActions;

  /// No description provided for @monthlyCloseMarkDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get monthlyCloseMarkDone;

  /// No description provided for @monthlyCloseUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get monthlyCloseUndo;

  /// No description provided for @monthlyCloseComplete.
  ///
  /// In en, this message translates to:
  /// **'Close month'**
  String get monthlyCloseComplete;

  /// No description provided for @monthlyCloseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Month closed'**
  String get monthlyCloseCompleted;

  /// No description provided for @monthlyCloseReconciliationTitle.
  ///
  /// In en, this message translates to:
  /// **'Account reconciliation'**
  String get monthlyCloseReconciliationTitle;

  /// No description provided for @monthlyCloseLedgerBalance.
  ///
  /// In en, this message translates to:
  /// **'Ledger balance at the end of this period'**
  String get monthlyCloseLedgerBalance;

  /// No description provided for @monthlyCloseDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference: {amount} {unit}'**
  String monthlyCloseDifference(String amount, String unit);

  /// No description provided for @monthlyCloseEnterStatementBalance.
  ///
  /// In en, this message translates to:
  /// **'Enter statement balance'**
  String get monthlyCloseEnterStatementBalance;

  /// No description provided for @monthlyCloseStatementBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Statement balance for {account}'**
  String monthlyCloseStatementBalanceTitle(String account);

  /// No description provided for @monthlyCloseAcceptDifference.
  ///
  /// In en, this message translates to:
  /// **'Accept difference'**
  String get monthlyCloseAcceptDifference;

  /// No description provided for @monthlyCloseDifferenceReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Why is this difference accepted?'**
  String get monthlyCloseDifferenceReasonTitle;

  /// No description provided for @monthlyCloseDifferenceReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Record the unresolved reason'**
  String get monthlyCloseDifferenceReasonHint;

  /// No description provided for @monthlyCloseWithException.
  ///
  /// In en, this message translates to:
  /// **'Close with exception'**
  String get monthlyCloseWithException;

  /// No description provided for @monthlyCloseExceptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Explain the close exception'**
  String get monthlyCloseExceptionTitle;

  /// No description provided for @monthlyCloseExceptionHint.
  ///
  /// In en, this message translates to:
  /// **'Record why the remaining evidence is accepted'**
  String get monthlyCloseExceptionHint;

  /// No description provided for @monthlyCloseStateBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get monthlyCloseStateBlocked;

  /// No description provided for @monthlyCloseStateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get monthlyCloseStateReady;

  /// No description provided for @monthlyCloseStateVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get monthlyCloseStateVerified;

  /// No description provided for @monthlyCloseStateOverridden.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get monthlyCloseStateOverridden;

  /// No description provided for @monthlyCloseVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Every evidence check was verified when this month was closed.'**
  String get monthlyCloseVerifiedBody;

  /// No description provided for @monthlyCloseOverriddenBody.
  ///
  /// In en, this message translates to:
  /// **'Closed with exception: {reason}'**
  String monthlyCloseOverriddenBody(String reason);

  /// No description provided for @financialInboxCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items need attention'**
  String financialInboxCount(int count);

  /// No description provided for @financialInboxEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get financialInboxEmptyTitle;

  /// No description provided for @financialInboxEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'New imports and confirmed money risks will appear here.'**
  String get financialInboxEmptyBody;

  /// No description provided for @financialInboxResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get financialInboxResolve;

  /// No description provided for @financialInboxSnooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get financialInboxSnooze;

  /// No description provided for @financialInboxChooseSnooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze until'**
  String get financialInboxChooseSnooze;

  /// No description provided for @financialInboxSnoozeTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get financialInboxSnoozeTomorrow;

  /// No description provided for @financialInboxSnoozeWeek.
  ///
  /// In en, this message translates to:
  /// **'In 7 days'**
  String get financialInboxSnoozeWeek;

  /// No description provided for @financialInboxSnoozeMonth.
  ///
  /// In en, this message translates to:
  /// **'In 30 days'**
  String get financialInboxSnoozeMonth;

  /// No description provided for @financialInboxResolveGroup.
  ///
  /// In en, this message translates to:
  /// **'Resolve group'**
  String get financialInboxResolveGroup;

  /// No description provided for @financialInboxResolveGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Resolve all {count} items in this priority group?'**
  String financialInboxResolveGroupBody(int count);

  /// No description provided for @financialInboxResolvedCount.
  ///
  /// In en, this message translates to:
  /// **'Resolved {count} items'**
  String financialInboxResolvedCount(int count);

  /// No description provided for @financialInboxImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Review {count} imported items'**
  String financialInboxImportTitle(int count);

  /// No description provided for @financialInboxImportBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm the records before they enter your ledger.'**
  String get financialInboxImportBody;

  /// No description provided for @financialInboxRunwayTitle.
  ///
  /// In en, this message translates to:
  /// **'Review your money runway'**
  String get financialInboxRunwayTitle;

  /// No description provided for @financialInboxRunwayBody.
  ///
  /// In en, this message translates to:
  /// **'A projected balance is below your safety reserve.'**
  String get financialInboxRunwayBody;

  /// No description provided for @financialInboxFxTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {count} missing exchange rates'**
  String financialInboxFxTitle(int count);

  /// No description provided for @financialInboxFxBody.
  ///
  /// In en, this message translates to:
  /// **'Missing rates reduce forecast confidence.'**
  String get financialInboxFxBody;

  /// No description provided for @financialInboxBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Resolve {count} balance differences'**
  String financialInboxBalanceTitle(int count);

  /// No description provided for @financialInboxBalanceBody.
  ///
  /// In en, this message translates to:
  /// **'Statement and ledger balances do not match.'**
  String get financialInboxBalanceBody;

  /// No description provided for @financialInboxAnomalyTitle.
  ///
  /// In en, this message translates to:
  /// **'Review unusual spending'**
  String get financialInboxAnomalyTitle;

  /// No description provided for @financialInboxAnomalyBody.
  ///
  /// In en, this message translates to:
  /// **'Projected spending differs materially from recent months.'**
  String get financialInboxAnomalyBody;

  /// No description provided for @financialInboxSubscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Review {count} subscription changes'**
  String financialInboxSubscriptionTitle(int count);

  /// No description provided for @financialInboxSubscriptionBody.
  ///
  /// In en, this message translates to:
  /// **'A recurring payment changed beyond the local threshold.'**
  String get financialInboxSubscriptionBody;

  /// No description provided for @financialInboxValuationTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh {count} stale valuations'**
  String financialInboxValuationTitle(int count);

  /// No description provided for @financialInboxValuationBody.
  ///
  /// In en, this message translates to:
  /// **'Stale prices reduce the reliability of your current position.'**
  String get financialInboxValuationBody;

  /// No description provided for @financialInboxDecisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Review a financial decision'**
  String get financialInboxDecisionTitle;

  /// No description provided for @financialInboxDecisionBody.
  ///
  /// In en, this message translates to:
  /// **'The scheduled outcome review is now due.'**
  String get financialInboxDecisionBody;

  /// No description provided for @financialInboxConcentrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Review {count} concentration risks'**
  String financialInboxConcentrationTitle(int count);

  /// No description provided for @financialInboxConcentrationBody.
  ///
  /// In en, this message translates to:
  /// **'A holding or sector exceeds your configured concentration thresholds.'**
  String get financialInboxConcentrationBody;

  /// No description provided for @financialInboxRebalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebalance {count} allocation drifts'**
  String financialInboxRebalanceTitle(int count);

  /// No description provided for @financialInboxRebalanceBody.
  ///
  /// In en, this message translates to:
  /// **'Asset-level target weights have drifted past your rebalance warning threshold.'**
  String get financialInboxRebalanceBody;

  /// No description provided for @financialInboxDividendTitle.
  ///
  /// In en, this message translates to:
  /// **'Review {count} dividend declines'**
  String financialInboxDividendTitle(int count);

  /// No description provided for @financialInboxDividendBody.
  ///
  /// In en, this message translates to:
  /// **'Trailing dividends for a holding fell materially versus the prior year.'**
  String get financialInboxDividendBody;

  /// No description provided for @financialInboxEvidenceDimension.
  ///
  /// In en, this message translates to:
  /// **'Dimension'**
  String get financialInboxEvidenceDimension;

  /// No description provided for @financialInboxEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get financialInboxEvidenceLabel;

  /// No description provided for @financialInboxEvidenceWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get financialInboxEvidenceWeight;

  /// No description provided for @financialInboxEvidenceThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get financialInboxEvidenceThreshold;

  /// No description provided for @financialInboxEvidenceSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get financialInboxEvidenceSeverity;

  /// No description provided for @financialInboxEvidenceBreachCount.
  ///
  /// In en, this message translates to:
  /// **'Breaches'**
  String get financialInboxEvidenceBreachCount;

  /// No description provided for @financialInboxEvidenceMaxDeviation.
  ///
  /// In en, this message translates to:
  /// **'Max deviation'**
  String get financialInboxEvidenceMaxDeviation;

  /// No description provided for @financialInboxEvidenceDropRatio.
  ///
  /// In en, this message translates to:
  /// **'Drop ratio'**
  String get financialInboxEvidenceDropRatio;

  /// No description provided for @financialInboxEvidenceTtmGross.
  ///
  /// In en, this message translates to:
  /// **'TTM gross'**
  String get financialInboxEvidenceTtmGross;

  /// No description provided for @financialInboxEvidencePriorTtmGross.
  ///
  /// In en, this message translates to:
  /// **'Prior TTM gross'**
  String get financialInboxEvidencePriorTtmGross;

  /// No description provided for @financialInboxEvidenceAssetId.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get financialInboxEvidenceAssetId;

  /// No description provided for @settingsProductMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Local product metrics'**
  String get settingsProductMetricsTitle;

  /// No description provided for @settingsProductMetricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Opt in to device-only funnel counters. No financial values or identifiers are recorded or uploaded.'**
  String get settingsProductMetricsSubtitle;

  /// No description provided for @settingsProductMetricsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy product evidence'**
  String get settingsProductMetricsCopy;

  /// No description provided for @settingsProductMetricsCopySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export privacy-safe daily and total aggregates from this device.'**
  String get settingsProductMetricsCopySubtitle;

  /// No description provided for @settingsProductMetricsCopied.
  ///
  /// In en, this message translates to:
  /// **'Product evidence copied'**
  String get settingsProductMetricsCopied;

  /// No description provided for @lifeEventScenariosTitle.
  ///
  /// In en, this message translates to:
  /// **'Life-event scenarios'**
  String get lifeEventScenariosTitle;

  /// No description provided for @lifeEventScenariosIntro.
  ///
  /// In en, this message translates to:
  /// **'Compare deterministic outcomes before making a choice. Assumptions, your selection, and the later review stay together.'**
  String get lifeEventScenariosIntro;

  /// No description provided for @lifeEventOptimistic.
  ///
  /// In en, this message translates to:
  /// **'Optimistic'**
  String get lifeEventOptimistic;

  /// No description provided for @lifeEventBaseline.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get lifeEventBaseline;

  /// No description provided for @lifeEventConservative.
  ///
  /// In en, this message translates to:
  /// **'Conservative'**
  String get lifeEventConservative;

  /// No description provided for @lifeEventScenariosEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your financial baseline first'**
  String get lifeEventScenariosEmptyTitle;

  /// No description provided for @lifeEventScenariosEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add accounts and spending history so scenarios can use your real liquid balance and monthly outflow.'**
  String get lifeEventScenariosEmptyBody;

  /// No description provided for @lifeEventLargePurchase.
  ///
  /// In en, this message translates to:
  /// **'Large purchase'**
  String get lifeEventLargePurchase;

  /// No description provided for @lifeEventCareerBreak.
  ///
  /// In en, this message translates to:
  /// **'Career break'**
  String get lifeEventCareerBreak;

  /// No description provided for @lifeEventHomePurchase.
  ///
  /// In en, this message translates to:
  /// **'Home purchase'**
  String get lifeEventHomePurchase;

  /// No description provided for @lifeEventLargePurchaseAssumption.
  ///
  /// In en, this message translates to:
  /// **'Preset: one-time cost equal to 20% of current liquid funds.'**
  String get lifeEventLargePurchaseAssumption;

  /// No description provided for @lifeEventCareerBreakAssumption.
  ///
  /// In en, this message translates to:
  /// **'Preset: no income for {months} months.'**
  String lifeEventCareerBreakAssumption(int months);

  /// No description provided for @lifeEventHomePurchaseAssumption.
  ///
  /// In en, this message translates to:
  /// **'Preset: 30% of liquid funds upfront and 10% higher monthly outflow for one year.'**
  String get lifeEventHomePurchaseAssumption;

  /// No description provided for @lifeEventAfter90Days.
  ///
  /// In en, this message translates to:
  /// **'Liquid funds after 90 days'**
  String get lifeEventAfter90Days;

  /// No description provided for @lifeEventAfter12Months.
  ///
  /// In en, this message translates to:
  /// **'Liquid funds after 12 months'**
  String get lifeEventAfter12Months;

  /// No description provided for @lifeEventMonthlySurplus.
  ///
  /// In en, this message translates to:
  /// **'Monthly surplus during event'**
  String get lifeEventMonthlySurplus;

  /// No description provided for @lifeEventEditAssumptions.
  ///
  /// In en, this message translates to:
  /// **'Edit assumptions'**
  String get lifeEventEditAssumptions;

  /// No description provided for @lifeEventUpfrontCost.
  ///
  /// In en, this message translates to:
  /// **'Upfront cost'**
  String get lifeEventUpfrontCost;

  /// No description provided for @lifeEventIncomeDelta.
  ///
  /// In en, this message translates to:
  /// **'Monthly income change'**
  String get lifeEventIncomeDelta;

  /// No description provided for @lifeEventOutflowDelta.
  ///
  /// In en, this message translates to:
  /// **'Monthly outflow change'**
  String get lifeEventOutflowDelta;

  /// No description provided for @lifeEventDurationMonths.
  ///
  /// In en, this message translates to:
  /// **'Duration in months'**
  String get lifeEventDurationMonths;

  /// No description provided for @lifeEventFireImpact.
  ///
  /// In en, this message translates to:
  /// **'Estimated FIRE impact'**
  String get lifeEventFireImpact;

  /// No description provided for @lifeEventFireDelay.
  ///
  /// In en, this message translates to:
  /// **'About {months} months later'**
  String lifeEventFireDelay(int months);

  /// No description provided for @lifeEventFireNoDelay.
  ///
  /// In en, this message translates to:
  /// **'No material delay'**
  String get lifeEventFireNoDelay;

  /// No description provided for @lifeEventAskAi.
  ///
  /// In en, this message translates to:
  /// **'Explore with assistant'**
  String get lifeEventAskAi;

  /// No description provided for @lifeEventChooseScenario.
  ///
  /// In en, this message translates to:
  /// **'Save decision'**
  String get lifeEventChooseScenario;

  /// No description provided for @lifeEventOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open follow-up'**
  String get lifeEventOpenAction;

  /// No description provided for @lifeEventAdjustPlan.
  ///
  /// In en, this message translates to:
  /// **'Adjust budget'**
  String get lifeEventAdjustPlan;

  /// No description provided for @lifeEventDecisionSaved.
  ///
  /// In en, this message translates to:
  /// **'Decision and assumptions saved'**
  String get lifeEventDecisionSaved;

  /// No description provided for @lifeEventReviewActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Review decision: {decision}'**
  String lifeEventReviewActionTitle(String decision);

  /// No description provided for @lifeEventReviewActionBody.
  ///
  /// In en, this message translates to:
  /// **'Compare the deterministic forecast with observed financial data. Do not infer causality.'**
  String get lifeEventReviewActionBody;

  /// No description provided for @lifeEventDecisionHistory.
  ///
  /// In en, this message translates to:
  /// **'Decisions to review'**
  String get lifeEventDecisionHistory;

  /// No description provided for @lifeEventPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get lifeEventPendingReview;

  /// No description provided for @lifeEventReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get lifeEventReviewed;

  /// No description provided for @lifeEventReviewOn.
  ///
  /// In en, this message translates to:
  /// **'Review on {date}'**
  String lifeEventReviewOn(String date);

  /// No description provided for @lifeEventChooseReviewDate.
  ///
  /// In en, this message translates to:
  /// **'Choose review timing'**
  String get lifeEventChooseReviewDate;

  /// No description provided for @lifeEventReviewIn30Days.
  ///
  /// In en, this message translates to:
  /// **'In 30 days'**
  String get lifeEventReviewIn30Days;

  /// No description provided for @lifeEventReviewIn90Days.
  ///
  /// In en, this message translates to:
  /// **'In 90 days'**
  String get lifeEventReviewIn90Days;

  /// No description provided for @lifeEventReviewIn180Days.
  ///
  /// In en, this message translates to:
  /// **'In 180 days'**
  String get lifeEventReviewIn180Days;

  /// No description provided for @lifeEventCaptureActual.
  ///
  /// In en, this message translates to:
  /// **'Capture current outcome'**
  String get lifeEventCaptureActual;

  /// No description provided for @lifeEventObservedDifference.
  ///
  /// In en, this message translates to:
  /// **'Observed 90-day balance difference: {amount}. This is a comparison, not a causal claim.'**
  String lifeEventObservedDifference(String amount);

  /// No description provided for @moneyRunwayCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Turn risk into an action'**
  String get moneyRunwayCreateAction;

  /// No description provided for @moneyRunwayActionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an Execution action?'**
  String get moneyRunwayActionConfirmTitle;

  /// No description provided for @moneyRunwayActionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The current runway evidence will be attached. Nothing is created until you confirm.'**
  String get moneyRunwayActionConfirmBody;

  /// No description provided for @moneyRunwayActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Improve short-term money runway'**
  String get moneyRunwayActionTitle;

  /// No description provided for @moneyRunwayActionCreated.
  ///
  /// In en, this message translates to:
  /// **'Execution action created'**
  String get moneyRunwayActionCreated;

  /// No description provided for @moneyRunwayTitle.
  ///
  /// In en, this message translates to:
  /// **'Money runway'**
  String get moneyRunwayTitle;

  /// No description provided for @moneyRunwayNinetyDayBalance.
  ///
  /// In en, this message translates to:
  /// **'Expected balance in 90 days'**
  String get moneyRunwayNinetyDayBalance;

  /// No description provided for @moneyRunwayEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Build your first runway'**
  String get moneyRunwayEmptyTitle;

  /// No description provided for @moneyRunwayEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Import a statement or add an account to see the next 90 days.'**
  String get moneyRunwayEmptyBody;

  /// No description provided for @moneyRunwayHorizonsTitle.
  ///
  /// In en, this message translates to:
  /// **'Forward balance'**
  String get moneyRunwayHorizonsTitle;

  /// No description provided for @moneyRunwayMinimumBalance.
  ///
  /// In en, this message translates to:
  /// **'Lowest expected balance: {amount}'**
  String moneyRunwayMinimumBalance(String amount);

  /// No description provided for @moneyRunwayMinimumBalanceDate.
  ///
  /// In en, this message translates to:
  /// **'Lowest point: {date}'**
  String moneyRunwayMinimumBalanceDate(String date);

  /// No description provided for @moneyRunwayRiskDate.
  ///
  /// In en, this message translates to:
  /// **'Cash shortfall expected {date}'**
  String moneyRunwayRiskDate(String date);

  /// No description provided for @moneyRunwayReserveBreachDate.
  ///
  /// In en, this message translates to:
  /// **'Below reserve target {date}'**
  String moneyRunwayReserveBreachDate(String date);

  /// No description provided for @moneyRunwayDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String moneyRunwayDays(Object days);

  /// No description provided for @moneyRunwayStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get moneyRunwayStatusHealthy;

  /// No description provided for @moneyRunwayStatusHealthyBody.
  ///
  /// In en, this message translates to:
  /// **'Expected cash stays above your reserve target.'**
  String get moneyRunwayStatusHealthyBody;

  /// No description provided for @moneyRunwayStatusWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get moneyRunwayStatusWatch;

  /// No description provided for @moneyRunwayStatusWatchBody.
  ///
  /// In en, this message translates to:
  /// **'Expected cash remains positive but falls below your reserve target.'**
  String get moneyRunwayStatusWatchBody;

  /// No description provided for @moneyRunwayStatusShortfall.
  ///
  /// In en, this message translates to:
  /// **'Shortfall'**
  String get moneyRunwayStatusShortfall;

  /// No description provided for @moneyRunwayStatusShortfallBody.
  ///
  /// In en, this message translates to:
  /// **'Expected cash falls below zero within this window.'**
  String get moneyRunwayStatusShortfallBody;

  /// No description provided for @moneyRunwayConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {confidence}'**
  String moneyRunwayConfidence(Object confidence);

  /// No description provided for @moneyRunwayConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get moneyRunwayConfidenceLow;

  /// No description provided for @moneyRunwayConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get moneyRunwayConfidenceMedium;

  /// No description provided for @moneyRunwayConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get moneyRunwayConfidenceHigh;

  /// No description provided for @moneyRunwayAssumptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Assumptions'**
  String get moneyRunwayAssumptionsTitle;

  /// No description provided for @moneyRunwayStartingCash.
  ///
  /// In en, this message translates to:
  /// **'Liquid balance'**
  String get moneyRunwayStartingCash;

  /// No description provided for @moneyRunwayReserveTarget.
  ///
  /// In en, this message translates to:
  /// **'Reserve target'**
  String get moneyRunwayReserveTarget;

  /// No description provided for @moneyRunwayVariableEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated variable spending / month'**
  String get moneyRunwayVariableEstimate;

  /// No description provided for @moneyRunwaySourceObservedHistory.
  ///
  /// In en, this message translates to:
  /// **'Observed 90-day history'**
  String get moneyRunwaySourceObservedHistory;

  /// No description provided for @moneyRunwaySourceFirePlan.
  ///
  /// In en, this message translates to:
  /// **'FIRE plan'**
  String get moneyRunwaySourceFirePlan;

  /// No description provided for @moneyRunwaySourceDefaultPolicy.
  ///
  /// In en, this message translates to:
  /// **'Default 3-month reserve'**
  String get moneyRunwaySourceDefaultPolicy;

  /// No description provided for @moneyRunwayCoverage.
  ///
  /// In en, this message translates to:
  /// **'Emergency coverage'**
  String get moneyRunwayCoverage;

  /// No description provided for @moneyRunwayCompleteness.
  ///
  /// In en, this message translates to:
  /// **'Data completeness'**
  String get moneyRunwayCompleteness;

  /// No description provided for @moneyRunwayHistoricalError.
  ///
  /// In en, this message translates to:
  /// **'Recent forecast error'**
  String get moneyRunwayHistoricalError;

  /// No description provided for @moneyRunwayScenariosTitle.
  ///
  /// In en, this message translates to:
  /// **'Stress test'**
  String get moneyRunwayScenariosTitle;

  /// No description provided for @moneyRunwayScenarioPurchase.
  ///
  /// In en, this message translates to:
  /// **'Spend one month of expenses now'**
  String get moneyRunwayScenarioPurchase;

  /// No description provided for @moneyRunwayScenarioDelayedIncome.
  ///
  /// In en, this message translates to:
  /// **'Delay expected income by 14 days'**
  String get moneyRunwayScenarioDelayedIncome;

  /// No description provided for @moneyRunwayScenarioReducedIncome.
  ///
  /// In en, this message translates to:
  /// **'Reduce expected income by 30%'**
  String get moneyRunwayScenarioReducedIncome;

  /// No description provided for @moneyRunwayCustomScenarioAction.
  ///
  /// In en, this message translates to:
  /// **'Custom stress test'**
  String get moneyRunwayCustomScenarioAction;

  /// No description provided for @moneyRunwayCustomScenarioTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom runway scenario'**
  String get moneyRunwayCustomScenarioTitle;

  /// No description provided for @moneyRunwayCustomPurchase.
  ///
  /// In en, this message translates to:
  /// **'One-time expense ({currency})'**
  String moneyRunwayCustomPurchase(String currency);

  /// No description provided for @moneyRunwayCustomDelayDays.
  ///
  /// In en, this message translates to:
  /// **'Income delay (days)'**
  String get moneyRunwayCustomDelayDays;

  /// No description provided for @moneyRunwayCustomReductionPercent.
  ///
  /// In en, this message translates to:
  /// **'Income reduction (%)'**
  String get moneyRunwayCustomReductionPercent;

  /// No description provided for @moneyRunwayCustomDurationDays.
  ///
  /// In en, this message translates to:
  /// **'Reduction duration (days)'**
  String get moneyRunwayCustomDurationDays;

  /// No description provided for @moneyRunwayCustomInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter non-negative values, a reduction from 0 to 100%, and at least one stress factor.'**
  String get moneyRunwayCustomInvalid;

  /// No description provided for @moneyRunwayCustomRun.
  ///
  /// In en, this message translates to:
  /// **'Run scenario'**
  String get moneyRunwayCustomRun;

  /// No description provided for @moneyRunwayCustomResult.
  ///
  /// In en, this message translates to:
  /// **'Custom minimum balance'**
  String get moneyRunwayCustomResult;

  /// No description provided for @moneyRunwayCustomReset.
  ///
  /// In en, this message translates to:
  /// **'Clear custom scenario'**
  String get moneyRunwayCustomReset;

  /// No description provided for @moneyRunwayCoverageMonths.
  ///
  /// In en, this message translates to:
  /// **'{months} months'**
  String moneyRunwayCoverageMonths(Object months);

  /// No description provided for @moneyRunwayScheduledTitle.
  ///
  /// In en, this message translates to:
  /// **'Known upcoming flows'**
  String get moneyRunwayScheduledTitle;

  /// No description provided for @moneyRunwayScheduledEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recurring income or bills are configured.'**
  String get moneyRunwayScheduledEmpty;

  /// No description provided for @moneyRunwayScheduledCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 upcoming item included} other{{count} upcoming items included}}'**
  String moneyRunwayScheduledCount(int count);

  /// No description provided for @moneyRunwayTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming cash timeline'**
  String get moneyRunwayTimelineTitle;

  /// No description provided for @moneyRunwayTimelineMore.
  ///
  /// In en, this message translates to:
  /// **'Show all {count}'**
  String moneyRunwayTimelineMore(int count);

  /// No description provided for @moneyRunwayTimelineLess.
  ///
  /// In en, this message translates to:
  /// **'Collapse timeline'**
  String get moneyRunwayTimelineLess;

  /// No description provided for @moneyRunwayTimelineBalanceAfter.
  ///
  /// In en, this message translates to:
  /// **'Expected balance that day: {amount}'**
  String moneyRunwayTimelineBalanceAfter(String amount);

  /// No description provided for @moneyRunwayTimelineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scheduled flows in the next 90 days. Add recurring income or bills to make this forecast more useful.'**
  String get moneyRunwayTimelineEmpty;

  /// No description provided for @moneyRunwayManageScheduled.
  ///
  /// In en, this message translates to:
  /// **'Manage scheduled flows'**
  String get moneyRunwayManageScheduled;

  /// No description provided for @moneyRunwayDeclaredDividend.
  ///
  /// In en, this message translates to:
  /// **'Declared after-tax dividend'**
  String get moneyRunwayDeclaredDividend;

  /// No description provided for @moneyRunwayEstimatedDividend.
  ///
  /// In en, this message translates to:
  /// **'Estimated after-tax dividend'**
  String get moneyRunwayEstimatedDividend;

  /// No description provided for @moneyRunwayEstimatedFlow.
  ///
  /// In en, this message translates to:
  /// **'estimate'**
  String get moneyRunwayEstimatedFlow;

  /// No description provided for @moneyRunwayMissingFx.
  ///
  /// In en, this message translates to:
  /// **'Excluded because FX rates are missing: {currencies}'**
  String moneyRunwayMissingFx(Object currencies);

  /// No description provided for @financeActivationTitle.
  ///
  /// In en, this message translates to:
  /// **'Your first useful result'**
  String get financeActivationTitle;

  /// No description provided for @financeActivationDismiss.
  ///
  /// In en, this message translates to:
  /// **'Hide setup guide'**
  String get financeActivationDismiss;

  /// No description provided for @financeActivationProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total}'**
  String financeActivationProgress(int completed, int total);

  /// No description provided for @financeActivationDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with real activity'**
  String get financeActivationDataTitle;

  /// No description provided for @financeActivationDataBody.
  ///
  /// In en, this message translates to:
  /// **'Add an entry manually or import a statement so the result is grounded in your own data.'**
  String get financeActivationDataBody;

  /// No description provided for @financeActivationDataAction.
  ///
  /// In en, this message translates to:
  /// **'Add financial data'**
  String get financeActivationDataAction;

  /// No description provided for @financeActivationReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review only the exceptions'**
  String get financeActivationReviewTitle;

  /// No description provided for @financeActivationReviewBody.
  ///
  /// In en, this message translates to:
  /// **'{count} items still need confirmation or recovery.'**
  String financeActivationReviewBody(int count);

  /// No description provided for @financeActivationReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Continue review'**
  String get financeActivationReviewAction;

  /// No description provided for @financeActivationRunwayTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the next 90 days'**
  String get financeActivationRunwayTitle;

  /// No description provided for @financeActivationRunwayBody.
  ///
  /// In en, this message translates to:
  /// **'Your entries are ready. Verify the resulting cash runway and its missing data.'**
  String get financeActivationRunwayBody;

  /// No description provided for @financeActivationRunwayAction.
  ///
  /// In en, this message translates to:
  /// **'Review runway'**
  String get financeActivationRunwayAction;

  /// No description provided for @financialInboxEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get financialInboxEvidenceTitle;

  /// No description provided for @financialInboxFirstDetected.
  ///
  /// In en, this message translates to:
  /// **'First detected'**
  String get financialInboxFirstDetected;

  /// No description provided for @financialInboxLastChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked'**
  String get financialInboxLastChecked;

  /// No description provided for @financialInboxLinkedAction.
  ///
  /// In en, this message translates to:
  /// **'Linked action'**
  String get financialInboxLinkedAction;

  /// No description provided for @financialInboxFixSource.
  ///
  /// In en, this message translates to:
  /// **'Fix the source'**
  String get financialInboxFixSource;

  /// No description provided for @financialInboxCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create action'**
  String get financialInboxCreateAction;

  /// No description provided for @financialInboxViewAction.
  ///
  /// In en, this message translates to:
  /// **'View action'**
  String get financialInboxViewAction;

  /// No description provided for @financialInboxActionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Enable ExecutionOS to create an action.'**
  String get financialInboxActionUnavailable;

  /// No description provided for @financialInboxEvidencePeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get financialInboxEvidencePeriod;

  /// No description provided for @financialInboxEvidenceMismatchCount.
  ///
  /// In en, this message translates to:
  /// **'Balance differences'**
  String get financialInboxEvidenceMismatchCount;

  /// No description provided for @financialInboxEvidenceChangeRatio.
  ///
  /// In en, this message translates to:
  /// **'Change ratio'**
  String get financialInboxEvidenceChangeRatio;

  /// No description provided for @financialInboxEvidenceExpenseCount.
  ///
  /// In en, this message translates to:
  /// **'Expenses this month'**
  String get financialInboxEvidenceExpenseCount;

  /// No description provided for @financialInboxExpenseDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense details'**
  String get financialInboxExpenseDetailsTitle;

  /// No description provided for @financialInboxExpenseUntitled.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get financialInboxExpenseUntitled;

  /// No description provided for @financialInboxEvidenceChangeCount.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get financialInboxEvidenceChangeCount;

  /// No description provided for @financialInboxEvidenceStaleCount.
  ///
  /// In en, this message translates to:
  /// **'Stale values'**
  String get financialInboxEvidenceStaleCount;

  /// No description provided for @financialInboxEvidenceReviewDate.
  ///
  /// In en, this message translates to:
  /// **'Review date'**
  String get financialInboxEvidenceReviewDate;

  /// No description provided for @financialInboxEvidenceCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Currencies'**
  String get financialInboxEvidenceCurrencies;

  /// No description provided for @financialInboxEvidenceCompleteness.
  ///
  /// In en, this message translates to:
  /// **'Data completeness'**
  String get financialInboxEvidenceCompleteness;

  /// No description provided for @financialInboxActionTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get financialInboxActionTodo;

  /// No description provided for @financialInboxActionDoing.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get financialInboxActionDoing;

  /// No description provided for @financialInboxActionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get financialInboxActionBlocked;

  /// No description provided for @financialInboxActionDone.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get financialInboxActionDone;

  /// No description provided for @financialInboxActionDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get financialInboxActionDropped;

  /// No description provided for @financialInboxActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get financialInboxActionUnknown;

  /// No description provided for @financialInboxRevalidation.
  ///
  /// In en, this message translates to:
  /// **'Source revalidation'**
  String get financialInboxRevalidation;

  /// No description provided for @financialInboxRevalidationCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared in a later complete check'**
  String get financialInboxRevalidationCleared;

  /// No description provided for @financialInboxRevalidationStillDetected.
  ///
  /// In en, this message translates to:
  /// **'Still detected after completion'**
  String get financialInboxRevalidationStillDetected;

  /// No description provided for @financialInboxRevalidationInconclusive.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the source check'**
  String get financialInboxRevalidationInconclusive;

  /// No description provided for @financialInboxRevalidationActionDropped.
  ///
  /// In en, this message translates to:
  /// **'Action dropped; signal remains open'**
  String get financialInboxRevalidationActionDropped;

  /// No description provided for @financialInboxRevalidatedAt.
  ///
  /// In en, this message translates to:
  /// **'Revalidated at'**
  String get financialInboxRevalidatedAt;

  /// No description provided for @monthlyCloseCoverageTitle.
  ///
  /// In en, this message translates to:
  /// **'Account coverage'**
  String get monthlyCloseCoverageTitle;

  /// No description provided for @monthlyCloseCoverageValue.
  ///
  /// In en, this message translates to:
  /// **'{accepted}/{total}'**
  String monthlyCloseCoverageValue(int accepted, int total);

  /// No description provided for @monthlyCloseSincePrevious.
  ///
  /// In en, this message translates to:
  /// **'Since the previous close: {newCount} new signals, {clearedCount} cleared.'**
  String monthlyCloseSincePrevious(int newCount, int clearedCount);

  /// No description provided for @monthlyClosePreviousDuration.
  ///
  /// In en, this message translates to:
  /// **'Previous close took {minutes} minutes.'**
  String monthlyClosePreviousDuration(int minutes);

  /// No description provided for @monthlyCloseCarriedForward.
  ///
  /// In en, this message translates to:
  /// **'Still open from last close: {signals} signals, {reconciliations} reconciliation exceptions.'**
  String monthlyCloseCarriedForward(int signals, int reconciliations);

  /// No description provided for @monthlyCloseHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Close history'**
  String get monthlyCloseHistoryTitle;

  /// No description provided for @monthlyCloseHistoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} previous closes'**
  String monthlyCloseHistoryCount(int count);

  /// No description provided for @monthlyCloseHistoryExceptions.
  ///
  /// In en, this message translates to:
  /// **'{count} exceptions'**
  String monthlyCloseHistoryExceptions(int count);

  /// No description provided for @monthlyCloseHistoryDuration.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String monthlyCloseHistoryDuration(int minutes);

  /// No description provided for @expenseCategoriesManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense categories'**
  String get expenseCategoriesManageTitle;

  /// No description provided for @expenseCategoriesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get expenseCategoriesAdd;

  /// No description provided for @expenseCategoriesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get expenseCategoriesEdit;

  /// No description provided for @expenseCategoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No expense categories'**
  String get expenseCategoriesEmpty;

  /// No description provided for @expenseCategoriesArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get expenseCategoriesArchived;

  /// No description provided for @expenseCategoriesBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get expenseCategoriesBuiltIn;

  /// No description provided for @expenseCategoriesCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get expenseCategoriesCustom;

  /// No description provided for @expenseCategoriesMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get expenseCategoriesMoveUp;

  /// No description provided for @expenseCategoriesMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get expenseCategoriesMoveDown;

  /// No description provided for @expenseCategoriesArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive category'**
  String get expenseCategoriesArchive;

  /// No description provided for @expenseCategoriesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore category'**
  String get expenseCategoriesRestore;

  /// No description provided for @expenseCategoriesNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get expenseCategoriesNameLabel;

  /// No description provided for @expenseCategoriesNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a category name'**
  String get expenseCategoriesNameRequired;

  /// No description provided for @expenseCategoriesParentLabel.
  ///
  /// In en, this message translates to:
  /// **'Parent category'**
  String get expenseCategoriesParentLabel;

  /// No description provided for @expenseCategoriesParentHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. Leave empty for a top-level category.'**
  String get expenseCategoriesParentHelper;

  /// No description provided for @expenseCategoriesMakeTopLevel.
  ///
  /// In en, this message translates to:
  /// **'Move to top level'**
  String get expenseCategoriesMakeTopLevel;

  /// No description provided for @expenseCategoriesIconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon token'**
  String get expenseCategoriesIconLabel;

  /// No description provided for @expenseCategoriesColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get expenseCategoriesColorLabel;

  /// No description provided for @expenseCategoriesColorHelper.
  ///
  /// In en, this message translates to:
  /// **'Choose a color used in lists and reports.'**
  String get expenseCategoriesColorHelper;

  /// No description provided for @leapsOverlayTitle.
  ///
  /// In en, this message translates to:
  /// **'LEAPS upside overlay'**
  String get leapsOverlayTitle;

  /// No description provided for @leapsOverlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Long calls tracked separately from the Wheel'**
  String get leapsOverlaySubtitle;

  /// No description provided for @leapsOverlayAdd.
  ///
  /// In en, this message translates to:
  /// **'Add LEAPS call'**
  String get leapsOverlayAdd;

  /// No description provided for @leapsOverlayEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit LEAPS call'**
  String get leapsOverlayEdit;

  /// No description provided for @leapsOverlayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No long calls recorded'**
  String get leapsOverlayEmpty;

  /// No description provided for @leapsOverlayOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{count} open LEAPS'**
  String leapsOverlayOpenCount(int count);

  /// No description provided for @leapsOverlayCost.
  ///
  /// In en, this message translates to:
  /// **'Open premium at risk'**
  String get leapsOverlayCost;

  /// No description provided for @leapsOverlayCoverage.
  ///
  /// In en, this message translates to:
  /// **'Wheel income coverage'**
  String get leapsOverlayCoverage;

  /// No description provided for @leapsOverlayDeltaShares.
  ///
  /// In en, this message translates to:
  /// **'Delta-equivalent shares'**
  String get leapsOverlayDeltaShares;

  /// No description provided for @leapsOverlayCombinedRealized.
  ///
  /// In en, this message translates to:
  /// **'Combined realized P&L'**
  String get leapsOverlayCombinedRealized;

  /// No description provided for @leapsOverlayUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get leapsOverlayUnknown;

  /// No description provided for @leapsOverlayCoverageValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}% covered'**
  String leapsOverlayCoverageValue(String percent);

  /// No description provided for @leapsOverlayOptionSymbol.
  ///
  /// In en, this message translates to:
  /// **'Call contract'**
  String get leapsOverlayOptionSymbol;

  /// No description provided for @leapsOverlayOpenedAt.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get leapsOverlayOpenedAt;

  /// No description provided for @leapsOverlayExpiration.
  ///
  /// In en, this message translates to:
  /// **'Expiration'**
  String get leapsOverlayExpiration;

  /// No description provided for @leapsOverlayStrike.
  ///
  /// In en, this message translates to:
  /// **'Strike'**
  String get leapsOverlayStrike;

  /// No description provided for @leapsOverlayEntryDebit.
  ///
  /// In en, this message translates to:
  /// **'Entry debit per contract'**
  String get leapsOverlayEntryDebit;

  /// No description provided for @leapsOverlayExitCredit.
  ///
  /// In en, this message translates to:
  /// **'Exit credit per contract'**
  String get leapsOverlayExitCredit;

  /// No description provided for @leapsOverlayCurrentMark.
  ///
  /// In en, this message translates to:
  /// **'Current mark per contract'**
  String get leapsOverlayCurrentMark;

  /// No description provided for @leapsOverlayCurrentDelta.
  ///
  /// In en, this message translates to:
  /// **'Current delta (0–1)'**
  String get leapsOverlayCurrentDelta;

  /// No description provided for @leapsOverlayMarkedAt.
  ///
  /// In en, this message translates to:
  /// **'Mark date'**
  String get leapsOverlayMarkedAt;

  /// No description provided for @leapsOverlayStatus.
  ///
  /// In en, this message translates to:
  /// **'Position status'**
  String get leapsOverlayStatus;

  /// No description provided for @leapsOverlayStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get leapsOverlayStatusOpen;

  /// No description provided for @leapsOverlayStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get leapsOverlayStatusClosed;

  /// No description provided for @leapsOverlayStatusExercised.
  ///
  /// In en, this message translates to:
  /// **'Exercised'**
  String get leapsOverlayStatusExercised;

  /// No description provided for @leapsOverlayStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get leapsOverlayStatusExpired;

  /// No description provided for @leapsOverlayDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete LEAPS position?'**
  String get leapsOverlayDeleteTitle;

  /// No description provided for @leapsOverlayDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the position from the synced strategy record.'**
  String get leapsOverlayDeleteBody;

  /// No description provided for @leapsOverlayDurationHint.
  ///
  /// In en, this message translates to:
  /// **'LEAPS are long-dated at listing. Record the actual expiration even when less than one year remains.'**
  String get leapsOverlayDurationHint;

  /// No description provided for @leapsOverlayDeltaHint.
  ///
  /// In en, this message translates to:
  /// **'Optional manual snapshot. Leave empty when unknown; NaviWealth will not invent a value.'**
  String get leapsOverlayDeltaHint;

  /// No description provided for @leapsOverlayDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Expiration must be after the open date.'**
  String get leapsOverlayDateInvalid;

  /// No description provided for @leapsOverlayDeltaInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a delta from 0 to 1.'**
  String get leapsOverlayDeltaInvalid;

  /// No description provided for @aiChatProposalKindLeapsCall.
  ///
  /// In en, this message translates to:
  /// **'LEAPS call position'**
  String get aiChatProposalKindLeapsCall;

  /// No description provided for @incomeStrategyTitle.
  ///
  /// In en, this message translates to:
  /// **'Income strategy'**
  String get incomeStrategyTitle;

  /// No description provided for @incomeStrategyTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get incomeStrategyTabOverview;

  /// No description provided for @incomeStrategyTabUnderlyings.
  ///
  /// In en, this message translates to:
  /// **'Underlyings'**
  String get incomeStrategyTabUnderlyings;

  /// No description provided for @incomeStrategyTabActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get incomeStrategyTabActivity;

  /// No description provided for @incomeStrategyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No income strategy yet'**
  String get incomeStrategyEmptyTitle;

  /// No description provided for @incomeStrategyEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Compose dividends, Wheel and LEAPS sleeves around an underlying. Existing positions remain visible even when they are outside the plan.'**
  String get incomeStrategyEmptyBody;

  /// No description provided for @incomeStrategyRealizedResult.
  ///
  /// In en, this message translates to:
  /// **'Realized result'**
  String get incomeStrategyRealizedResult;

  /// No description provided for @incomeStrategyProjectedCash.
  ///
  /// In en, this message translates to:
  /// **'Projected cash'**
  String get incomeStrategyProjectedCash;

  /// No description provided for @incomeStrategyCapitalAtRisk.
  ///
  /// In en, this message translates to:
  /// **'Capital at risk'**
  String get incomeStrategyCapitalAtRisk;

  /// No description provided for @incomeStrategyRiskCount.
  ///
  /// In en, this message translates to:
  /// **'Risks to review'**
  String get incomeStrategyRiskCount;

  /// No description provided for @incomeStrategyRisksTitle.
  ///
  /// In en, this message translates to:
  /// **'Coordination risks'**
  String get incomeStrategyRisksTitle;

  /// No description provided for @incomeStrategyUnderlyingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Strategy tracks'**
  String get incomeStrategyUnderlyingsTitle;

  /// No description provided for @incomeStrategyRiskSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} risks'**
  String incomeStrategyRiskSummary(int count);

  /// No description provided for @incomeStrategyPlanAligned.
  ///
  /// In en, this message translates to:
  /// **'Aligned'**
  String get incomeStrategyPlanAligned;

  /// No description provided for @incomeStrategyEnabled.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get incomeStrategyEnabled;

  /// No description provided for @incomeStrategyDisabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get incomeStrategyDisabled;

  /// No description provided for @incomeStrategyNoPosition.
  ///
  /// In en, this message translates to:
  /// **'No current position'**
  String get incomeStrategyNoPosition;

  /// No description provided for @incomeStrategyActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No strategy activity yet'**
  String get incomeStrategyActivityEmpty;

  /// No description provided for @incomeStrategyOpenDividendCenter.
  ///
  /// In en, this message translates to:
  /// **'Dividend center'**
  String get incomeStrategyOpenDividendCenter;

  /// No description provided for @incomeStrategyOpenOptionsPlanner.
  ///
  /// In en, this message translates to:
  /// **'Options workspace'**
  String get incomeStrategyOpenOptionsPlanner;

  /// No description provided for @incomeStrategySleeveDividends.
  ///
  /// In en, this message translates to:
  /// **'Dividends'**
  String get incomeStrategySleeveDividends;

  /// No description provided for @incomeStrategySleeveWheel.
  ///
  /// In en, this message translates to:
  /// **'Wheel'**
  String get incomeStrategySleeveWheel;

  /// No description provided for @incomeStrategySleeveLeaps.
  ///
  /// In en, this message translates to:
  /// **'LEAPS call'**
  String get incomeStrategySleeveLeaps;

  /// No description provided for @incomeStrategyStatusHolding.
  ///
  /// In en, this message translates to:
  /// **'Holding'**
  String get incomeStrategyStatusHolding;

  /// No description provided for @incomeStrategyStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get incomeStrategyStatusPlanned;

  /// No description provided for @incomeStrategyStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get incomeStrategyStatusOpen;

  /// No description provided for @incomeStrategyStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get incomeStrategyStatusResolved;

  /// No description provided for @incomeStrategyMetricPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial valuation'**
  String get incomeStrategyMetricPartial;

  /// No description provided for @incomeStrategyCashFlowDividend.
  ///
  /// In en, this message translates to:
  /// **'Gross dividend'**
  String get incomeStrategyCashFlowDividend;

  /// No description provided for @incomeStrategyCashFlowWithholding.
  ///
  /// In en, this message translates to:
  /// **'Dividend withholding'**
  String get incomeStrategyCashFlowWithholding;

  /// No description provided for @incomeStrategyCashFlowWheel.
  ///
  /// In en, this message translates to:
  /// **'Wheel realized result'**
  String get incomeStrategyCashFlowWheel;

  /// No description provided for @incomeStrategyCashFlowLeapsPurchase.
  ///
  /// In en, this message translates to:
  /// **'LEAPS purchase'**
  String get incomeStrategyCashFlowLeapsPurchase;

  /// No description provided for @incomeStrategyCashFlowLeapsSale.
  ///
  /// In en, this message translates to:
  /// **'LEAPS sale'**
  String get incomeStrategyCashFlowLeapsSale;

  /// No description provided for @incomeStrategyCashFlowLeapsExercise.
  ///
  /// In en, this message translates to:
  /// **'LEAPS exercise cash'**
  String get incomeStrategyCashFlowLeapsExercise;

  /// No description provided for @incomeStrategyRiskUnplanned.
  ///
  /// In en, this message translates to:
  /// **'A live sleeve is outside the current strategy plan. Review it instead of hiding the exposure.'**
  String get incomeStrategyRiskUnplanned;

  /// No description provided for @incomeStrategyRiskCapitalBudget.
  ///
  /// In en, this message translates to:
  /// **'Combined sleeve capital exceeds the plan budget.'**
  String get incomeStrategyRiskCapitalBudget;

  /// No description provided for @incomeStrategyRiskAssignment.
  ///
  /// In en, this message translates to:
  /// **'Open put assignment value exceeds the configured limit.'**
  String get incomeStrategyRiskAssignment;

  /// No description provided for @incomeStrategyRiskConcentration.
  ///
  /// In en, this message translates to:
  /// **'The underlying exceeds the configured portfolio weight.'**
  String get incomeStrategyRiskConcentration;

  /// No description provided for @incomeStrategyRiskDividend.
  ///
  /// In en, this message translates to:
  /// **'An open covered call may remove shares while the plan is configured to preserve dividend income.'**
  String get incomeStrategyRiskDividend;

  /// No description provided for @incomeStrategyRiskStacked.
  ///
  /// In en, this message translates to:
  /// **'The Wheel short put and LEAPS call stack downside-sensitive capital on the same underlying.'**
  String get incomeStrategyRiskStacked;

  /// No description provided for @incomeStrategyRiskLeapsBudget.
  ///
  /// In en, this message translates to:
  /// **'Open LEAPS cost exceeds the configured budget.'**
  String get incomeStrategyRiskLeapsBudget;

  /// No description provided for @incomeStrategyRiskLeapsCoverage.
  ///
  /// In en, this message translates to:
  /// **'Realized income does not yet cover the open LEAPS cost.'**
  String get incomeStrategyRiskLeapsCoverage;

  /// No description provided for @incomeStrategyRiskMissingMark.
  ///
  /// In en, this message translates to:
  /// **'A LEAPS position has no current mark, so market value is incomplete.'**
  String get incomeStrategyRiskMissingMark;

  /// No description provided for @incomeStrategyRiskMissingDelta.
  ///
  /// In en, this message translates to:
  /// **'A LEAPS position has no delta, so equivalent-share exposure is incomplete.'**
  String get incomeStrategyRiskMissingDelta;

  /// No description provided for @incomeStrategyRiskMissingFx.
  ///
  /// In en, this message translates to:
  /// **'An FX rate is missing, so one or more monetary totals are incomplete.'**
  String get incomeStrategyRiskMissingFx;

  /// No description provided for @incomeStrategyRiskStaleValuation.
  ///
  /// In en, this message translates to:
  /// **'A position mark is stale and should be refreshed.'**
  String get incomeStrategyRiskStaleValuation;

  /// No description provided for @incomeStrategyRiskIncomeTarget.
  ///
  /// In en, this message translates to:
  /// **'Year-to-date realized income is materially behind the configured annual target.'**
  String get incomeStrategyRiskIncomeTarget;

  /// No description provided for @incomeStrategyRiskExpiration.
  ///
  /// In en, this message translates to:
  /// **'An option is near expiration and needs review.'**
  String get incomeStrategyRiskExpiration;

  /// No description provided for @incomeStrategyPlanAdd.
  ///
  /// In en, this message translates to:
  /// **'Add strategy plan'**
  String get incomeStrategyPlanAdd;

  /// No description provided for @incomeStrategyPlanEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit strategy plan'**
  String get incomeStrategyPlanEdit;

  /// No description provided for @incomeStrategyPlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose any combination of sleeves and set shared risk limits.'**
  String get incomeStrategyPlanSubtitle;

  /// No description provided for @incomeStrategyPlanAsset.
  ///
  /// In en, this message translates to:
  /// **'Underlying'**
  String get incomeStrategyPlanAsset;

  /// No description provided for @incomeStrategyPlanSleeves.
  ///
  /// In en, this message translates to:
  /// **'Enabled sleeves'**
  String get incomeStrategyPlanSleeves;

  /// No description provided for @incomeStrategyPlanGroup.
  ///
  /// In en, this message translates to:
  /// **'Strategy group'**
  String get incomeStrategyPlanGroup;

  /// No description provided for @incomeStrategyPlanGroupHint.
  ///
  /// In en, this message translates to:
  /// **'Coordinate wheel and LEAPS legs across underlyings — e.g. a TQQQ wheel funding a QQQ LEAPS call.'**
  String get incomeStrategyPlanGroupHint;

  /// No description provided for @incomeStrategyPlanGroupNone.
  ///
  /// In en, this message translates to:
  /// **'None (standalone)'**
  String get incomeStrategyPlanGroupNone;

  /// No description provided for @incomeStrategyPlanGroupNew.
  ///
  /// In en, this message translates to:
  /// **'New group…'**
  String get incomeStrategyPlanGroupNew;

  /// No description provided for @incomeStrategyPlanGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get incomeStrategyPlanGroupNameLabel;

  /// No description provided for @incomeStrategyPlanGroupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for the new group.'**
  String get incomeStrategyPlanGroupNameRequired;

  /// No description provided for @incomeStrategyPlanPreserveDividend.
  ///
  /// In en, this message translates to:
  /// **'Preserve dividend income'**
  String get incomeStrategyPlanPreserveDividend;

  /// No description provided for @incomeStrategyPlanAllowCalledAway.
  ///
  /// In en, this message translates to:
  /// **'Allow shares to be called away'**
  String get incomeStrategyPlanAllowCalledAway;

  /// No description provided for @incomeStrategyPlanLimits.
  ///
  /// In en, this message translates to:
  /// **'Shared limits'**
  String get incomeStrategyPlanLimits;

  /// No description provided for @incomeStrategyPlanLimitsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional portfolio and sleeve guardrails'**
  String get incomeStrategyPlanLimitsHint;

  /// No description provided for @incomeStrategyPlanCapitalBudget.
  ///
  /// In en, this message translates to:
  /// **'Total capital budget'**
  String get incomeStrategyPlanCapitalBudget;

  /// No description provided for @incomeStrategyPlanAnnualTarget.
  ///
  /// In en, this message translates to:
  /// **'Annual income target'**
  String get incomeStrategyPlanAnnualTarget;

  /// No description provided for @incomeStrategyPlanMaxWeight.
  ///
  /// In en, this message translates to:
  /// **'Maximum portfolio weight (%)'**
  String get incomeStrategyPlanMaxWeight;

  /// No description provided for @incomeStrategyPlanMaxLeapsCost.
  ///
  /// In en, this message translates to:
  /// **'Maximum open LEAPS cost'**
  String get incomeStrategyPlanMaxLeapsCost;

  /// No description provided for @incomeStrategyPlanMaxAssignment.
  ///
  /// In en, this message translates to:
  /// **'Maximum put assignment value'**
  String get incomeStrategyPlanMaxAssignment;

  /// No description provided for @incomeStrategyPlanAssetRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an underlying.'**
  String get incomeStrategyPlanAssetRequired;

  /// No description provided for @incomeStrategyPlanSleeveRequired.
  ///
  /// In en, this message translates to:
  /// **'Enable at least one sleeve.'**
  String get incomeStrategyPlanSleeveRequired;

  /// No description provided for @incomeStrategyPlanNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter non-negative limits and a portfolio weight from 0 to 100.'**
  String get incomeStrategyPlanNumberInvalid;

  /// No description provided for @incomeStrategyPlanDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete strategy plan?'**
  String get incomeStrategyPlanDeleteTitle;

  /// No description provided for @incomeStrategyPlanDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Live holdings and trades remain visible, but the shared sleeve settings and limits will be removed.'**
  String get incomeStrategyPlanDeleteBody;

  /// No description provided for @rebalanceStagePortfolioTitle.
  ///
  /// In en, this message translates to:
  /// **'1 · Move capital between portfolios'**
  String get rebalanceStagePortfolioTitle;

  /// No description provided for @rebalanceStageStrategyTitle.
  ///
  /// In en, this message translates to:
  /// **'2 · Allocate capital between sleeves'**
  String get rebalanceStageStrategyTitle;

  /// No description provided for @rebalanceStageAssetTitle.
  ///
  /// In en, this message translates to:
  /// **'3 · Rebalance assets inside the sleeve'**
  String get rebalanceStageAssetTitle;

  /// No description provided for @rebalanceDecisionPolicyBlocked.
  ///
  /// In en, this message translates to:
  /// **'{name} is outside its allowed deviation, but its transfer rule blocks the required movement.'**
  String rebalanceDecisionPolicyBlocked(String name);

  /// No description provided for @rebalanceDecisionNoCounterparty.
  ///
  /// In en, this message translates to:
  /// **'{name} is outside its allowed deviation, but there is no eligible source or destination.'**
  String rebalanceDecisionNoCounterparty(String name);

  /// No description provided for @rebalanceCapitalBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get rebalanceCapitalBlockedTitle;

  /// No description provided for @rebalanceConfigurePlanAction.
  ///
  /// In en, this message translates to:
  /// **'Edit allocation plan'**
  String get rebalanceConfigurePlanAction;

  /// No description provided for @portfolioCapitalAssignmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Asset assignment'**
  String get portfolioCapitalAssignmentTitle;

  /// No description provided for @portfolioCapitalAssignmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Assign positions and cash to exactly one portfolio and strategy.'**
  String get portfolioCapitalAssignmentSubtitle;

  /// No description provided for @portfolioCapitalAssignmentLotsAction.
  ///
  /// In en, this message translates to:
  /// **'Assign positions'**
  String get portfolioCapitalAssignmentLotsAction;

  /// No description provided for @portfolioCapitalAssignmentLotsHint.
  ///
  /// In en, this message translates to:
  /// **'Place whole or partial tax lots under a strategy.'**
  String get portfolioCapitalAssignmentLotsHint;

  /// No description provided for @portfolioCapitalAssignmentCashAction.
  ///
  /// In en, this message translates to:
  /// **'Assign cash'**
  String get portfolioCapitalAssignmentCashAction;

  /// No description provided for @portfolioCapitalAssignmentCashHint.
  ///
  /// In en, this message translates to:
  /// **'Reserve account cash for a strategy.'**
  String get portfolioCapitalAssignmentCashHint;

  /// No description provided for @portfolioStrategyLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Strategy library'**
  String get portfolioStrategyLibraryTitle;

  /// No description provided for @portfolioStrategyLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in and custom strategy types used when adding a strategy.'**
  String get portfolioStrategyLibrarySubtitle;

  /// No description provided for @portfolioStrategyBuiltInBadge.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get portfolioStrategyBuiltInBadge;

  /// No description provided for @portfolioStrategyCustomBadge.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get portfolioStrategyCustomBadge;

  /// No description provided for @portfolioStrategyEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get portfolioStrategyEditAction;

  /// No description provided for @portfolioStrategyArchiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get portfolioStrategyArchiveAction;

  /// No description provided for @portfolioStrategyArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive this strategy type?'**
  String get portfolioStrategyArchiveTitle;

  /// No description provided for @portfolioStrategyArchiveBody.
  ///
  /// In en, this message translates to:
  /// **'Existing strategies keep their current configuration. This type will no longer appear when adding a strategy.'**
  String get portfolioStrategyArchiveBody;

  /// No description provided for @portfolioStrategyArchiveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t archive this strategy type.'**
  String get portfolioStrategyArchiveFailed;

  /// No description provided for @rebalanceCapitalFirstHint.
  ///
  /// In en, this message translates to:
  /// **'Complete the capital movements above by updating asset assignment. Asset trades unlock after the portfolio and strategy balances are within tolerance.'**
  String get rebalanceCapitalFirstHint;

  /// No description provided for @rebalanceCapitalBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'This allocation cannot be completed automatically. Adjust its transfer policy or target, or add eligible capital; the next stage will be recalculated after it is resolved.'**
  String get rebalanceCapitalBlockedHint;

  /// No description provided for @rebalanceTransferTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Current transfer task'**
  String get rebalanceTransferTaskTitle;

  /// No description provided for @rebalanceTransferTaskSummary.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to} · {amount}'**
  String rebalanceTransferTaskSummary(String from, String to, String amount);

  /// No description provided for @rebalanceTransferTaskHint.
  ///
  /// In en, this message translates to:
  /// **'Move cash first, then adjust position ownership if needed. Return to rebalancing when done to recalculate the next stage from the latest assignments.'**
  String get rebalanceTransferTaskHint;

  /// No description provided for @rebalanceTransferTaskRecalculateAction.
  ///
  /// In en, this message translates to:
  /// **'Done, recalculate'**
  String get rebalanceTransferTaskRecalculateAction;

  /// No description provided for @rebalanceCapitalFirstAction.
  ///
  /// In en, this message translates to:
  /// **'Resolve capital movements first'**
  String get rebalanceCapitalFirstAction;

  /// No description provided for @rebalanceResolveTransferAction.
  ///
  /// In en, this message translates to:
  /// **'Resolve transfer'**
  String get rebalanceResolveTransferAction;

  /// No description provided for @healthActivationTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect your health data'**
  String get healthActivationTitle;

  /// No description provided for @healthActivationBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the source you already use. HealthOS stays useful with manual entries, and every connection is read-only.'**
  String get healthActivationBody;

  /// No description provided for @healthActivationAction.
  ///
  /// In en, this message translates to:
  /// **'Connect system health'**
  String get healthActivationAction;

  /// No description provided for @healthActivationGarminAction.
  ///
  /// In en, this message translates to:
  /// **'Connect Garmin'**
  String get healthActivationGarminAction;

  /// No description provided for @healthActivationManualAction.
  ///
  /// In en, this message translates to:
  /// **'Record manually'**
  String get healthActivationManualAction;

  /// No description provided for @healthRefreshFresh.
  ///
  /// In en, this message translates to:
  /// **'Health data updated {time}'**
  String healthRefreshFresh(String time);

  /// No description provided for @healthRefreshStale.
  ///
  /// In en, this message translates to:
  /// **'Health data may be out of date · updated {time}'**
  String healthRefreshStale(String time);

  /// No description provided for @healthRefreshPartialFailure.
  ///
  /// In en, this message translates to:
  /// **'{count} data source failed to refresh'**
  String healthRefreshPartialFailure(int count);

  /// No description provided for @healthRefreshPullHint.
  ///
  /// In en, this message translates to:
  /// **'Pull down to sync every connected source'**
  String get healthRefreshPullHint;

  /// No description provided for @healthRecoveryConfidence.
  ///
  /// In en, this message translates to:
  /// **'{confidence} confidence · {coverage}% coverage'**
  String healthRecoveryConfidence(String confidence, int coverage);

  /// No description provided for @healthRecoveryConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get healthRecoveryConfidenceHigh;

  /// No description provided for @healthRecoveryConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get healthRecoveryConfidenceMedium;

  /// No description provided for @healthRecoveryConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get healthRecoveryConfidenceLow;

  /// No description provided for @healthRecoveryConfidenceInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient'**
  String get healthRecoveryConfidenceInsufficient;

  /// No description provided for @healthRecoveryFreshness.
  ///
  /// In en, this message translates to:
  /// **'Latest input {time}'**
  String healthRecoveryFreshness(String time);

  /// No description provided for @healthRecoveryWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why this score'**
  String get healthRecoveryWhyTitle;

  /// No description provided for @healthRecoveryWhyLess.
  ///
  /// In en, this message translates to:
  /// **'Hide score details'**
  String get healthRecoveryWhyLess;

  /// No description provided for @healthRecoveryEvidence.
  ///
  /// In en, this message translates to:
  /// **'{metric}: {recent} now · {delta} vs baseline'**
  String healthRecoveryEvidence(String metric, String recent, String delta);

  /// No description provided for @healthRecoveryEvidenceNoBaseline.
  ///
  /// In en, this message translates to:
  /// **'{metric}: {recent} · building your baseline'**
  String healthRecoveryEvidenceNoBaseline(String metric, String recent);

  /// No description provided for @healthRecoveryEvidenceBaseline.
  ///
  /// In en, this message translates to:
  /// **'Baseline {baseline} · {recentSamples} recent / {baselineSamples} baseline samples'**
  String healthRecoveryEvidenceBaseline(
    String baseline,
    int recentSamples,
    int baselineSamples,
  );

  /// No description provided for @healthRecoveryEvidenceNoBaselineSamples.
  ///
  /// In en, this message translates to:
  /// **'{recentSamples} recent samples · baseline forming'**
  String healthRecoveryEvidenceNoBaselineSamples(int recentSamples);

  /// No description provided for @healthRecoveryDeltaUp.
  ///
  /// In en, this message translates to:
  /// **'{value}% above'**
  String healthRecoveryDeltaUp(String value);

  /// No description provided for @healthRecoveryDeltaDown.
  ///
  /// In en, this message translates to:
  /// **'{value}% below'**
  String healthRecoveryDeltaDown(String value);

  /// No description provided for @healthRecoveryMetricHrv.
  ///
  /// In en, this message translates to:
  /// **'HRV'**
  String get healthRecoveryMetricHrv;

  /// No description provided for @healthRecoveryMetricRhr.
  ///
  /// In en, this message translates to:
  /// **'Resting heart rate'**
  String get healthRecoveryMetricRhr;

  /// No description provided for @healthRecoveryMetricSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get healthRecoveryMetricSleep;

  /// No description provided for @healthRecoveryMetricVo2.
  ///
  /// In en, this message translates to:
  /// **'VO₂ max'**
  String get healthRecoveryMetricVo2;

  /// No description provided for @healthRecoveryMetricBodyBattery.
  ///
  /// In en, this message translates to:
  /// **'Body Battery'**
  String get healthRecoveryMetricBodyBattery;

  /// No description provided for @healthRecoveryMetricStress.
  ///
  /// In en, this message translates to:
  /// **'Stress'**
  String get healthRecoveryMetricStress;

  /// No description provided for @healthSettingsSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected data sources'**
  String get healthSettingsSourcesTitle;

  /// No description provided for @healthSettingsSourcesHelp.
  ///
  /// In en, this message translates to:
  /// **'Manage connections, secure Garmin sessions, and source freshness in one place.'**
  String get healthSettingsSourcesHelp;

  /// No description provided for @executionDailyFocusTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Top 3'**
  String get executionDailyFocusTitle;

  /// No description provided for @executionDailyFocusEmpty.
  ///
  /// In en, this message translates to:
  /// **'Choose up to three actions that deserve your attention today.'**
  String get executionDailyFocusEmpty;

  /// No description provided for @executionTodayNextActions.
  ///
  /// In en, this message translates to:
  /// **'Next actions'**
  String get executionTodayNextActions;

  /// No description provided for @executionDailyFocusSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggested from your latest review: {titles}'**
  String executionDailyFocusSuggestion(String titles);

  /// No description provided for @executionDailyFocusUseSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Use these'**
  String get executionDailyFocusUseSuggestion;

  /// No description provided for @executionActionStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Action moved to {status}'**
  String executionActionStatusUpdated(String status);

  /// No description provided for @executionQuickWhenField.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get executionQuickWhenField;

  /// No description provided for @executionQuickWhenInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get executionQuickWhenInbox;

  /// No description provided for @executionQuickWhenToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get executionQuickWhenToday;

  /// No description provided for @executionQuickWhenTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get executionQuickWhenTomorrow;

  /// No description provided for @executionShowDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get executionShowDetails;

  /// No description provided for @executionHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Fewer details'**
  String get executionHideDetails;

  /// No description provided for @executionScheduleAfterDue.
  ///
  /// In en, this message translates to:
  /// **'The scheduled date must be on or before the deadline.'**
  String get executionScheduleAfterDue;

  /// No description provided for @executionBlockReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'What is blocking this action?'**
  String get executionBlockReasonTitle;

  /// No description provided for @executionBlockReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Name the dependency, decision, or missing information'**
  String get executionBlockReasonHint;

  /// No description provided for @executionDailyFocusToggle.
  ///
  /// In en, this message translates to:
  /// **'Top 3'**
  String get executionDailyFocusToggle;

  /// No description provided for @executionDailyFocusCount.
  ///
  /// In en, this message translates to:
  /// **'{count}/3'**
  String executionDailyFocusCount(int count);

  /// No description provided for @executionDailyFocusReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace a Top 3 action'**
  String get executionDailyFocusReplaceTitle;

  /// No description provided for @executionDailyFocusReplaceBody.
  ///
  /// In en, this message translates to:
  /// **'Your Top 3 is full. Choose which action to replace with “{title}”.'**
  String executionDailyFocusReplaceBody(String title);

  /// No description provided for @executionDailyFocusReplaceAction.
  ///
  /// In en, this message translates to:
  /// **'Replace this action'**
  String get executionDailyFocusReplaceAction;

  /// No description provided for @executionDailyFocusMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get executionDailyFocusMoveUp;

  /// No description provided for @executionDailyFocusMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get executionDailyFocusMoveDown;

  /// No description provided for @executionDailyFocusRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from Top 3'**
  String get executionDailyFocusRemove;

  /// No description provided for @executionDueAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions due soon'**
  String get executionDueAgentTitle;

  /// No description provided for @executionDueAgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Checks daily for open actions due by tomorrow and can send a local reminder.'**
  String get executionDueAgentDescription;

  /// No description provided for @executionDueAgentNothingDue.
  ///
  /// In en, this message translates to:
  /// **'No actions are due in the next day.'**
  String get executionDueAgentNothingDue;

  /// No description provided for @executionDueAgentSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} actions are due by tomorrow. First: {title}'**
  String executionDueAgentSummary(int count, String title);

  /// No description provided for @executionReviewCreateNextActions.
  ///
  /// In en, this message translates to:
  /// **'Create {count} next actions'**
  String executionReviewCreateNextActions(int count);

  /// No description provided for @executionReviewCreateNextActionsBody.
  ///
  /// In en, this message translates to:
  /// **'Create one high-priority action for every project or commitment that still has no open next action?'**
  String get executionReviewCreateNextActionsBody;

  /// No description provided for @executionReviewCreatedNextActions.
  ///
  /// In en, this message translates to:
  /// **'Created {count} next actions'**
  String executionReviewCreatedNextActions(int count);

  /// No description provided for @executionReviewDraftNextActions.
  ///
  /// In en, this message translates to:
  /// **'Review {count} missing next actions'**
  String executionReviewDraftNextActions(int count);

  /// No description provided for @executionReviewAgentNotRun.
  ///
  /// In en, this message translates to:
  /// **'The weekly Execution Review has not run yet.'**
  String get executionReviewAgentNotRun;

  /// No description provided for @executionReviewAgentRunning.
  ///
  /// In en, this message translates to:
  /// **'Execution Review is running now.'**
  String get executionReviewAgentRunning;

  /// No description provided for @executionReviewAgentFailed.
  ///
  /// In en, this message translates to:
  /// **'The latest Execution Review failed. Your activity summary is still available.'**
  String get executionReviewAgentFailed;

  /// No description provided for @executionReviewAgentLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last Execution Review: {date}'**
  String executionReviewAgentLastRun(String date);

  /// No description provided for @executionReviewRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run review'**
  String get executionReviewRunNow;

  /// No description provided for @executionReviewNextActionFor.
  ///
  /// In en, this message translates to:
  /// **'Define the next step for {title}'**
  String executionReviewNextActionFor(String title);

  /// No description provided for @agentSettingsTriggerEvent.
  ///
  /// In en, this message translates to:
  /// **'Data change'**
  String get agentSettingsTriggerEvent;

  /// No description provided for @executionSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search ExecutionOS'**
  String get executionSearchTitle;

  /// No description provided for @executionSearchFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Result type'**
  String get executionSearchFilterTitle;

  /// No description provided for @executionSearchFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get executionSearchFilterAll;

  /// No description provided for @executionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search actions and plans'**
  String get executionSearchHint;

  /// No description provided for @executionSearchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Search all execution work'**
  String get executionSearchEmptyTitle;

  /// No description provided for @executionSearchEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Results include open and closed actions and plans.'**
  String get executionSearchEmptyBody;

  /// No description provided for @executionSearchStartAction.
  ///
  /// In en, this message translates to:
  /// **'Start searching'**
  String get executionSearchStartAction;

  /// No description provided for @executionSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching work'**
  String get executionSearchNoResults;

  /// No description provided for @executionSearchTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try a title, note, or description.'**
  String get executionSearchTryAgain;

  /// No description provided for @executionSearchClearAction.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get executionSearchClearAction;

  /// No description provided for @executionSearchKindAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get executionSearchKindAction;

  /// No description provided for @executionSearchKindProject.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get executionSearchKindProject;

  /// No description provided for @executionSearchKindProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get executionSearchKindProgress;

  /// No description provided for @knowledgeSettingsReviewCadence.
  ///
  /// In en, this message translates to:
  /// **'Review cadence'**
  String get knowledgeSettingsReviewCadence;

  /// No description provided for @knowledgeSettingsStaleThreshold.
  ///
  /// In en, this message translates to:
  /// **'Stale assumption threshold'**
  String get knowledgeSettingsStaleThreshold;

  /// No description provided for @knowledgeSettingsEveryDays.
  ///
  /// In en, this message translates to:
  /// **'Every {days} days'**
  String knowledgeSettingsEveryDays(int days);

  /// No description provided for @knowledgeSettingsAfterDays.
  ///
  /// In en, this message translates to:
  /// **'After {days} days without verification'**
  String knowledgeSettingsAfterDays(int days);

  /// No description provided for @knowledgeCaptureNeedsStructure.
  ///
  /// In en, this message translates to:
  /// **'{kind} needs its structured fields before it can be created. Add decision options, assumption confidence, or experiment method and metrics.'**
  String knowledgeCaptureNeedsStructure(String kind);

  /// No description provided for @knowledgeMarkdownInsertImage.
  ///
  /// In en, this message translates to:
  /// **'Insert image'**
  String get knowledgeMarkdownInsertImage;

  /// No description provided for @knowledgeImageSourceCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get knowledgeImageSourceCamera;

  /// No description provided for @knowledgeImageSourceGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo library'**
  String get knowledgeImageSourceGallery;

  /// No description provided for @knowledgeImageSourceFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get knowledgeImageSourceFile;

  /// No description provided for @knowledgeImageImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the image'**
  String get knowledgeImageImportFailed;

  /// No description provided for @knowledgeImageLocalOnlyToast.
  ///
  /// In en, this message translates to:
  /// **'Image inserted. It is currently stored on this device only.'**
  String get knowledgeImageLocalOnlyToast;

  /// No description provided for @developerIssuesTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a product issue'**
  String get developerIssuesTitle;

  /// No description provided for @developerIssuesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save a local dogfood report with bounded diagnostics. Nothing is sent until you export it.'**
  String get developerIssuesSubtitle;

  /// No description provided for @developerIssuesDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'What should be improved?'**
  String get developerIssuesDescriptionLabel;

  /// No description provided for @developerIssuesDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Example: The FIRE card\'s information hierarchy makes the recommended action hard to find.'**
  String get developerIssuesDescriptionHint;

  /// No description provided for @developerIssuesDescriptionHelp.
  ///
  /// In en, this message translates to:
  /// **'Describe the observed problem and the result you expected. Do not include secrets.'**
  String get developerIssuesDescriptionHelp;

  /// No description provided for @developerIssuesDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Describe the product issue before saving.'**
  String get developerIssuesDescriptionRequired;

  /// No description provided for @developerIssuesCaptureAction.
  ///
  /// In en, this message translates to:
  /// **'Save local report'**
  String get developerIssuesCaptureAction;

  /// No description provided for @developerIssuesCapturingAction.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get developerIssuesCapturingAction;

  /// No description provided for @developerIssuesSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Report saved on this device'**
  String get developerIssuesSavedToast;

  /// No description provided for @developerIssuesSaveFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the report. Review the description and try again.'**
  String get developerIssuesSaveFailedToast;

  /// No description provided for @developerIssuesContextSection.
  ///
  /// In en, this message translates to:
  /// **'Captured context'**
  String get developerIssuesContextSection;

  /// No description provided for @developerIssuesRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Source route'**
  String get developerIssuesRouteLabel;

  /// No description provided for @developerIssuesDomainLabel.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get developerIssuesDomainLabel;

  /// No description provided for @developerIssuesShellDomain.
  ///
  /// In en, this message translates to:
  /// **'LifeOS shell'**
  String get developerIssuesShellDomain;

  /// No description provided for @developerIssuesHistorySection.
  ///
  /// In en, this message translates to:
  /// **'Local reports'**
  String get developerIssuesHistorySection;

  /// No description provided for @developerIssuesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports saved on this device.'**
  String get developerIssuesEmpty;

  /// No description provided for @developerIssuesExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get developerIssuesExportAction;

  /// No description provided for @developerIssuesExportedLabel.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get developerIssuesExportedLabel;

  /// No description provided for @developerIssuesLocalLabel.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get developerIssuesLocalLabel;

  /// No description provided for @developerIssuesTraceAttached.
  ///
  /// In en, this message translates to:
  /// **'Trace attached'**
  String get developerIssuesTraceAttached;

  /// No description provided for @developerIssuesToolErrorsAttached.
  ///
  /// In en, this message translates to:
  /// **'{count} tool error codes'**
  String developerIssuesToolErrorsAttached(int count);

  /// No description provided for @developerIssuesExportFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the export sheet. Try again.'**
  String get developerIssuesExportFailedToast;

  /// No description provided for @developerIssuesAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Product issue reports'**
  String get developerIssuesAdvancedTitle;

  /// No description provided for @developerIssuesAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture route, build, latest trace, and bounded tool error codes locally'**
  String get developerIssuesAdvancedSubtitle;
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
