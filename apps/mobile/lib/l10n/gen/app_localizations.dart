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

  /// Action that opens the corporate-action entry form (dividend, split, rights issue, DRIP).
  ///
  /// In en, this message translates to:
  /// **'Record corporate action'**
  String get assetsCorporateActionAction;

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
