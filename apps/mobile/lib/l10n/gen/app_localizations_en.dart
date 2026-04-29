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
}
