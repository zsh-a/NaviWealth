// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'NaviWealth';

  @override
  String get navHome => '总览';

  @override
  String get navAssets => '资产';

  @override
  String get navAnalytics => '分析';

  @override
  String get navSettings => '设置';

  @override
  String get homeAppBarTitle => '总览';

  @override
  String get homeNetWorthTitle => '净资产';

  @override
  String homeNetWorthSubtitle(String currency) {
    return '基础货币 $currency · 等数据接入后展示';
  }

  @override
  String get homeTodayReturnTitle => '今日收益';

  @override
  String get homeTodayReturnSubtitle => '尚未接入实时行情。FIR-4 完成后此处显示当日净值变动。';

  @override
  String get homeAllocationTitle => '资产分布';

  @override
  String get homeAllocationSubtitle => '将在 FIR-7 完成后显示大类饼图与行业 / 地域分布。';

  @override
  String get homeFireTitle => 'FIRE 进度';

  @override
  String get homeFireSubtitle => 'FIR-9 完成后显示距离财务自由的天数与里程碑。';

  @override
  String get assetsAppBarTitle => '资产';

  @override
  String get assetsEmptyHint => '资产录入与管理 (FIR-5) — 待实现';

  @override
  String get assetsAddAction => '添加资产';

  @override
  String get analyticsAppBarTitle => '分析';

  @override
  String get settingsAppBarTitle => '设置';

  @override
  String get settingsAccountTitle => '账户';

  @override
  String get settingsAccountSubtitle => '登录与多端同步 (FIR-27 / FIR-28)';

  @override
  String get settingsBaseCurrencyTitle => '基础货币';

  @override
  String settingsBaseCurrencySubtitle(String currency) {
    return '$currency (默认)';
  }

  @override
  String get settingsAboutTitle => '关于 NaviWealth';

  @override
  String settingsAboutSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsThemeModeTitle => '主题模式';

  @override
  String get themeModeSystem => '跟随系统';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get settingsMarketColorTitle => '涨跌色';

  @override
  String get marketColorRedUpGreenDown => '红涨绿跌 (中国)';

  @override
  String get marketColorGreenUpRedDown => '绿涨红跌 (国际)';

  @override
  String get marketColorColorblind => '色盲友好 (蓝/橙)';

  @override
  String get commonRetry => '重试';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSave => '保存';

  @override
  String get commonClose => '关闭';

  @override
  String get commonLoading => '加载中…';

  @override
  String get commonError => '出错了';
}
