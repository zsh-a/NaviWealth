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
}
