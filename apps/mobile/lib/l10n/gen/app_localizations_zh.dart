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
  String get assetsLiabilitiesLink => '负债与还款计划';

  @override
  String get liabilitiesAppBarTitle => '负债';

  @override
  String get liabilitiesEmptyHint => '尚未录入负债。添加房贷、车贷、信用卡或消费贷以跟踪还款。';

  @override
  String get liabilitiesAddAction => '添加负债';

  @override
  String get liabilityTypeMortgage => '房贷';

  @override
  String get liabilityTypeCarLoan => '车贷';

  @override
  String get liabilityTypeCreditCard => '信用卡';

  @override
  String get liabilityTypeConsumerLoan => '消费贷';

  @override
  String get liabilityTypeStudentLoan => '学生贷款';

  @override
  String get liabilityTypeMarginLoan => '融资融券';

  @override
  String get liabilityTypeOther => '其他';

  @override
  String get liabilityRateTypeFixed => '固定利率';

  @override
  String get liabilityRateTypeLpr => 'LPR 浮动';

  @override
  String get liabilityMethodEqualInstallment => '等额本息';

  @override
  String get liabilityMethodEqualPrincipal => '等额本金';

  @override
  String get liabilityFieldName => '名称';

  @override
  String get liabilityFieldType => '类型';

  @override
  String get liabilityFieldPrincipal => '本金';

  @override
  String get liabilityFieldInterestRate => '年利率 (%)';

  @override
  String get liabilityFieldRateType => '利率类型';

  @override
  String get liabilityFieldTerm => '期限（月）';

  @override
  String get liabilityFieldStartDate => '起还日';

  @override
  String get liabilityFieldMethod => '还款方式';

  @override
  String get liabilityFieldCurrency => '币种';

  @override
  String get liabilityFieldStatementDay => '账单日';

  @override
  String get liabilityFieldPaymentDueDay => '还款日';

  @override
  String get liabilitySaveAction => '保存';

  @override
  String get liabilityValidationRequired => '必填';

  @override
  String get liabilityValidationPositive => '必须大于零';

  @override
  String get liabilityValidationDayOfMonth => '必须为 1–31';

  @override
  String get liabilitySummaryRemaining => '剩余本金';

  @override
  String get liabilitySummaryInterestPaid => '已还利息';

  @override
  String get liabilitySummaryInterestTotal => '总利息支出';

  @override
  String get liabilitySummaryInterestRatio => '利息占比';

  @override
  String liabilitySummaryProgress(int paid, int total) {
    return '已还 $paid / $total 期';
  }

  @override
  String get liabilityScheduleHeading => '还款计划表';

  @override
  String get liabilityScheduleColPeriod => '#';

  @override
  String get liabilityScheduleColDue => '到期日';

  @override
  String get liabilityScheduleColPrincipal => '本金';

  @override
  String get liabilityScheduleColInterest => '利息';

  @override
  String get liabilityScheduleColRemaining => '剩余';

  @override
  String get liabilityScheduleColStatus => '状态';

  @override
  String get liabilityScheduleStatusPaid => '已还';

  @override
  String get liabilityScheduleStatusDue => '未还';

  @override
  String get liabilityScheduleMarkPaid => '标记已还';

  @override
  String liabilityScheduleMarkPaidConfirmTitle(int period) {
    return '标记第 $period 期已还？';
  }

  @override
  String liabilityScheduleMarkPaidConfirmBody(String amount) {
    return '这将记录一笔 $amount 的还款交易（日期为今天），且无法从本页撤销。';
  }

  @override
  String get liabilityScheduleMarkPaidNoAccount => '标记还款前请先指定还款账户。';

  @override
  String get liabilityNotFound => '未找到该负债';

  @override
  String get liabilityRevolvingNoSchedule => '信用卡 / 循环授信无固定还款计划表。';

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
