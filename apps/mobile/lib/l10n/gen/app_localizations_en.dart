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
  String get navExpenses => 'Expenses';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeAppBarTitle => 'Overview';

  @override
  String get homeAiAssistantTooltip => 'AI assistant';

  @override
  String get homeRecordTradeTooltip => 'Record trade';

  @override
  String get homeNetWorthTitle => 'Net Worth';

  @override
  String homeNetWorthSubtitle(String currency) {
    return 'Base currency $currency · shown once data is connected';
  }

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
  String get assetsCorporateActionAction => 'Record corporate action';

  @override
  String get assetsAccountsTooltip => 'Accounts';

  @override
  String get assetsLiabilitiesTooltip => 'Liabilities & repayment plans';

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
  String get assetsAddLiabilityTitle =>
      'Liability (mortgage / car loan / credit card / consumer loan)';

  @override
  String get assetsAddLiabilitySubtitle => 'Record and track repayment plans';

  @override
  String get assetsAddCorporateActionSubtitle =>
      'Dividend / split / rights issue / bonus shares / DRIP';

  @override
  String get assetsAddTradeTitle => 'Securities trade';

  @override
  String get assetsAddTradeSubtitle => 'Buy / sell stocks, ETFs, crypto';

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
  String get settingsAccountSubtitle =>
      'Sign-in & multi-device sync (FIR-27 / FIR-28)';

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
  String get commandPaletteEmpty => 'No commands match your search';

  @override
  String commandPaletteAskAi(String query) {
    return 'Ask AI: $query';
  }

  @override
  String get commandPaletteGoOverview => 'Go to Overview';

  @override
  String get commandPaletteGoAssets => 'Go to Assets';

  @override
  String get commandPaletteGoAccounts => 'Go to Accounts';

  @override
  String get commandPaletteGoExpenses => 'Go to Expenses';

  @override
  String get commandPaletteGoAnalytics => 'Go to Analytics';

  @override
  String get commandPaletteGoFire => 'Go to FIRE';

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
      'Once you record stock or ETF transactions, the breakdown will show up here.';

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
  String get navFire => 'FIRE';

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
      'Answers grounded in your holdings and transactions. Numbers come from your locally-synced ledger; the model never invents key figures.';

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
  String get aiChatStaleSyncNotice =>
      'Local data hasn\'t finished syncing; answers may lag behind your most recent edits.';

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
  String get aiChatToolGetTransactions => 'Query transactions';

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
  String get accountsAppBarTitle => 'Accounts';

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
  String get accountTypeBrokerage => 'Brokerage account';

  @override
  String get accountTypeBank => 'Bank account';

  @override
  String get accountTypeCryptoWallet => 'Crypto wallet';

  @override
  String get accountTypeRealEstate => 'Real estate account';

  @override
  String get accountTypeVehicle => 'Vehicle account';

  @override
  String get accountTypeLiability => 'Liability account';

  @override
  String get accountTypeCash => 'Cash account';

  @override
  String get accountTypeOther => 'Other account';

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
  String get manualAssetDeleteTitle => 'Delete asset';

  @override
  String get manualAssetDeleteContent => 'Delete this asset record?';

  @override
  String get manualAssetDeleteCancel => 'Cancel';

  @override
  String get manualAssetDeleteConfirm => 'Delete';
}
