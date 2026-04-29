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
  String get navAssets => 'Assets';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeAppBarTitle => 'Overview';

  @override
  String get homeNetWorthTitle => 'Net Worth';

  @override
  String homeNetWorthSubtitle(String currency) {
    return 'Base currency $currency · shown once data is connected';
  }

  @override
  String get homeTodayReturnTitle => 'Today\'s Return';

  @override
  String get homeTodayReturnSubtitle =>
      'Live quotes pending. FIR-4 will populate this card.';

  @override
  String get homeAllocationTitle => 'Asset Allocation';

  @override
  String get homeAllocationSubtitle =>
      'FIR-7 will surface category, sector, and region breakdowns here.';

  @override
  String get homeFireTitle => 'FIRE Progress';

  @override
  String get homeFireSubtitle =>
      'FIR-9 will show days to financial independence and milestones.';

  @override
  String get assetsAppBarTitle => 'Assets';

  @override
  String get assetsEmptyHint =>
      'Asset entry & management (FIR-5) — coming soon';

  @override
  String get assetsAddAction => 'Add asset';

  @override
  String get assetsCorporateActionAction => 'Record corporate action';

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
  String get analyticsAppBarTitle => 'Analytics';

  @override
  String get settingsAppBarTitle => 'Settings';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsAccountSubtitle =>
      'Sign-in & multi-device sync (FIR-27 / FIR-28)';

  @override
  String get settingsBaseCurrencyTitle => 'Base currency';

  @override
  String settingsBaseCurrencySubtitle(String currency) {
    return '$currency (default)';
  }

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
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonError => 'Something went wrong';

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
  String shortcutSwitchTab(int position, String label) {
    return 'Switch to tab $position ($label)';
  }

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
}
