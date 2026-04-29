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
  /// **'Once you record stock or ETF transactions, the breakdown will show up here.'**
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
