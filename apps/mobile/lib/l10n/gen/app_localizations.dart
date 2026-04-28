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

  /// Bottom nav: assets tab
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get navAssets;

  /// Bottom nav: analytics tab
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// Bottom nav: settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @homeAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get homeAppBarTitle;

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

  /// No description provided for @homeTodayReturnTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Return'**
  String get homeTodayReturnTitle;

  /// No description provided for @homeTodayReturnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live quotes pending. FIR-4 will populate this card.'**
  String get homeTodayReturnSubtitle;

  /// No description provided for @homeAllocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Asset Allocation'**
  String get homeAllocationTitle;

  /// No description provided for @homeAllocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FIR-7 will surface category, sector, and region breakdowns here.'**
  String get homeAllocationSubtitle;

  /// No description provided for @homeFireTitle.
  ///
  /// In en, this message translates to:
  /// **'FIRE Progress'**
  String get homeFireTitle;

  /// No description provided for @homeFireSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FIR-9 will show days to financial independence and milestones.'**
  String get homeFireSubtitle;

  /// No description provided for @assetsAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assetsAppBarTitle;

  /// No description provided for @assetsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Asset entry & management (FIR-5) — coming soon'**
  String get assetsEmptyHint;

  /// No description provided for @assetsAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add asset'**
  String get assetsAddAction;

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

  /// No description provided for @analyticsAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsAppBarTitle;

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
  /// **'Sign-in & multi-device sync (FIR-27 / FIR-28)'**
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

  /// No description provided for @shortcutSwitchTab.
  ///
  /// In en, this message translates to:
  /// **'Switch to tab {position} ({label})'**
  String shortcutSwitchTab(int position, String label);

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
