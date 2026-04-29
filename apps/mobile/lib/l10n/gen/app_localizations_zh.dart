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
  String get assetsCorporateActionAction => '录入公司行动';

  @override
  String get corpActionTitle => '公司行动';

  @override
  String get corpActionSelectAsset => '资产';

  @override
  String get corpActionSelectAssetHint => '选择本次事件所影响的持仓。';

  @override
  String get corpActionEventTypeTitle => '事件类型';

  @override
  String get corpActionTypeCashDividend => '现金分红';

  @override
  String get corpActionTypeStockDividend => '送股 / 红股';

  @override
  String get corpActionTypeSplit => '拆股 / 合股';

  @override
  String get corpActionTypeRightsIssue => '配股';

  @override
  String get corpActionTypeDrip => 'DRIP 自动再投';

  @override
  String get corpActionEffectiveDate => '登记日';

  @override
  String get corpActionAmountPerShare => '每股金额';

  @override
  String get corpActionWithholdingTax => '代扣税款（总额）';

  @override
  String get corpActionBonusRatio => '送股比例（每持有 1 股送 N 股）';

  @override
  String get corpActionSplitRatio => '拆股比例';

  @override
  String get corpActionSplitRatioHelp => '2 = 1 拆 2 · 0.1 = 10 合 1';

  @override
  String get corpActionSubscribedQuantity => '认购数量';

  @override
  String get corpActionPricePerUnit => '每股价格';

  @override
  String get corpActionFee => '手续费';

  @override
  String get corpActionPreviewAction => '预览影响';

  @override
  String get corpActionSubmitAction => '提交';

  @override
  String get corpActionPreviewHeading => '预览';

  @override
  String get corpActionNoEligibleHolding => '登记日当天该账户在此资产上没有可派息的持仓。';

  @override
  String get corpActionPreviewSharesOnRecord => '登记日持股';

  @override
  String get corpActionPreviewGross => '总额';

  @override
  String get corpActionPreviewTax => '税款';

  @override
  String get corpActionPreviewNet => '净额';

  @override
  String get corpActionPreviewCashFlow => '现金流';

  @override
  String corpActionPreviewLotChange(
    String id,
    String beforeQty,
    String afterQty,
    String beforeCost,
    String afterCost,
  ) {
    return 'Lot $id：$beforeQty → $afterQty @ $beforeCost → $afterCost';
  }

  @override
  String corpActionPreviewNewLot(String qty, String cost) {
    return '新 Lot：$qty @ $cost';
  }

  @override
  String get corpActionSubmitted => '已记录。';

  @override
  String get corpActionInvalidNumber => '请输入正数';

  @override
  String get corpActionInvalidNumberNonNegative => '请输入非负数';

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

  @override
  String get deferredLoadFailedTitle => '该页面加载失败';

  @override
  String get deferredLoadRetry => '重试';

  @override
  String get shortcutsHelpTitle => '键盘快捷键';

  @override
  String get shortcutCommandPalette => '打开命令面板';

  @override
  String get shortcutShowHelp => '显示快捷键帮助';

  @override
  String get shortcutDismissOverlay => '关闭当前弹窗';

  @override
  String shortcutSwitchTab(int position, String label) {
    return '切换到第 $position 个标签 ($label)';
  }

  @override
  String get pwaUpdateAvailable => 'NaviWealth 有新版本可用。';

  @override
  String get pwaUpdateApply => '立即刷新';

  @override
  String get pwaUpdateDismiss => '稍后';
}
