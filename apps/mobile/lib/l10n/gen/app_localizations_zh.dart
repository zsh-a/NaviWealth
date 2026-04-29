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
  String get physicalAssetsSectionTitle => '房产与车辆';

  @override
  String get physicalAssetsEmpty => '暂无房产或车辆。点击 + 添加。';

  @override
  String get physicalAssetTypeRealEstate => '房产';

  @override
  String get physicalAssetTypeVehicle => '车辆';

  @override
  String get physicalAssetAddRealEstate => '添加房产';

  @override
  String get physicalAssetAddVehicle => '添加车辆';

  @override
  String get physicalAssetFieldName => '名称';

  @override
  String get physicalAssetFieldAddress => '地址';

  @override
  String get physicalAssetFieldPurchaseDate => '购入日';

  @override
  String get physicalAssetFieldPurchasePrice => '购入价';

  @override
  String get physicalAssetFieldCurrentValuation => '当前估值';

  @override
  String get physicalAssetFieldCurrency => '币种';

  @override
  String get physicalAssetFieldAnnualResidualRate => '年度残值率';

  @override
  String get physicalAssetFieldAutoDepreciation => '估值之间自动折旧';

  @override
  String get physicalAssetFieldLinkedLiability => '关联房贷 / 车贷 ID';

  @override
  String get physicalAssetFieldNote => '备注';

  @override
  String get physicalAssetCreateSubmit => '保存';

  @override
  String get physicalAssetUpdateValuationAction => '更新估值';

  @override
  String get physicalAssetUpdateValuationTitle => '更新估值';

  @override
  String get physicalAssetUpdateValuationDate => '估值日期';

  @override
  String get physicalAssetUpdateValuationAmount => '新估值';

  @override
  String get physicalAssetUpdateValuationSubmit => '保存估值';

  @override
  String get physicalAssetDeleteAction => '删除';

  @override
  String get physicalAssetDeleteConfirmTitle => '确认删除该资产？';

  @override
  String get physicalAssetDeleteConfirmBody => '估值历史将被标记删除,但已同步过的设备仍可追溯。';

  @override
  String get physicalAssetDetailValuationTitle => '当前估值';

  @override
  String get physicalAssetDetailHistoryTitle => '估值历史';

  @override
  String get physicalAssetDetailDepreciationProjection => '折旧曲线';

  @override
  String get physicalAssetDetailPurchaseLabel => '购入';

  @override
  String get physicalAssetDetailManualUpdateLabel => '手动更新';

  @override
  String get physicalAssetDetailAutoEstimateLabel => '自动估算';

  @override
  String physicalAssetDetailEstimatedToday(String value) {
    return '今日估算:$value';
  }

  @override
  String get physicalAssetValidationRequired => '必填';

  @override
  String get physicalAssetValidationPositive => '必须大于 0';

  @override
  String get physicalAssetValidationResidualRange => '必须在 0 与 1 之间';

  @override
  String get physicalAssetNotFound => '资产不存在';

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
  String get routeNotFoundTitle => '页面不存在';

  @override
  String routeNotFoundMessage(String path) {
    return '找不到 $path。链接可能已失效或从未存在。';
  }

  @override
  String get routeErrorTitle => '出错了';

  @override
  String get routeGoHome => '返回总览';

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

  @override
  String get authLoginTitle => '欢迎回来';

  @override
  String get authLoginSubmit => '登录';

  @override
  String get authEmailLabel => '邮箱';

  @override
  String get authPasswordLabel => '密码';

  @override
  String get authPasswordShowTooltip => '显示密码';

  @override
  String get authPasswordHideTooltip => '隐藏密码';

  @override
  String get authEmailErrorEmpty => '请输入邮箱地址。';

  @override
  String get authEmailErrorInvalid => '邮箱格式不正确。';

  @override
  String get authPasswordErrorEmpty => '请输入密码。';

  @override
  String get authPasswordErrorTooShort => '密码至少需要 8 位。';

  @override
  String get authLoginErrorInvalidCredentials => '邮箱或密码不正确。';

  @override
  String get authLoginErrorNetwork => '无法连接服务器，请检查网络后重试。';

  @override
  String get authLoginErrorServer => '服务器暂时无响应，请稍后重试。';

  @override
  String get authLoginErrorGeneric => '登录失败，请重试。';

  @override
  String get authLoginNoticeSessionExpired => '登录已过期，请重新登录。';

  @override
  String get settingsDevicesTitle => '已登录设备';

  @override
  String get settingsDevicesSubtitle => '查看已登录的设备并远程登出';

  @override
  String get authDevicesTitle => '已登录设备';

  @override
  String get authDeviceUnnamed => '未命名设备';

  @override
  String get authDeviceCurrent => '当前设备';

  @override
  String authDeviceLastSeen(String timestamp) {
    return '最近活跃 $timestamp';
  }

  @override
  String get authDeviceRevokeTooltip => '登出此设备';

  @override
  String get authDeviceRevokeDialogTitle => '登出该设备？';

  @override
  String authDeviceRevokeDialogBody(String device) {
    return '确定要登出 $device 吗？该设备需重新登录后才能继续同步。';
  }

  @override
  String get authDeviceRevokeConfirm => '登出';

  @override
  String get authDeviceRevokeError => '登出失败，请重试。';

  @override
  String get authDevicesLoadError => '无法加载设备列表。';

  @override
  String get authLogoutCurrentTooltip => '登出';

  @override
  String get authLogoutDialogTitle => '确定要登出？';

  @override
  String get authLogoutDialogBody => '登出后需要在此设备上重新登录。';

  @override
  String get authLogoutDialogConfirm => '登出';

  @override
  String get dashboardAllocationTitle => '大类资产分布';

  @override
  String get dashboardTrendTitle => '净资产趋势';

  @override
  String get dashboardCategoryStock => '股票';

  @override
  String get dashboardCategoryEtf => 'ETF';

  @override
  String get dashboardCategoryBondsAndFunds => '债券与基金';

  @override
  String get dashboardCategoryCash => '现金';

  @override
  String get dashboardCategoryCrypto => '加密资产';

  @override
  String get dashboardCategoryRealEstate => '房产';

  @override
  String get dashboardCategoryVehicle => '车辆';

  @override
  String get dashboardCategoryLiability => '负债';

  @override
  String get dashboardRange1M => '1月';

  @override
  String get dashboardRange3M => '3月';

  @override
  String get dashboardRange6M => '6月';

  @override
  String get dashboardRange1Y => '1年';

  @override
  String get dashboardRange3Y => '3年';

  @override
  String get dashboardRangeAll => '全部';

  @override
  String get dashboardRangeCustom => '自定义';

  @override
  String dashboardDrillDownItemCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    return '共 $countString 项';
  }

  @override
  String dashboardNetWorthBreakdown(
    String assets,
    String liabilities,
    String currency,
  ) {
    return '资产 $assets − 负债 $liabilities ($currency)';
  }

  @override
  String dashboardSnapshotError(String error) {
    return '加载仪表盘失败：$error';
  }

  @override
  String dashboardTrendError(String error) {
    return '加载趋势图失败：$error';
  }

  @override
  String get dashboardTrendFlatHint => '当前数据未提供历史估值，趋势线显示为平直。后续接入估值变动后将自动展现波动。';

  @override
  String get analyticsAppBarTitle => '组合分析';

  @override
  String get analyticsEquityTitle => '股票透视';

  @override
  String get analyticsEquitySubtitle => '按行业、地域或市值切片查看股票 / ETF 持仓。';

  @override
  String get analyticsDimensionSector => '行业';

  @override
  String get analyticsDimensionRegion => '地域';

  @override
  String get analyticsDimensionMarketCap => '市值';

  @override
  String analyticsTotalValueLabel(String currency) {
    return '总持仓 $currency';
  }

  @override
  String get analyticsBucketUnclassified => '未分类';

  @override
  String get analyticsBucketRegionCnA => 'A 股';

  @override
  String get analyticsBucketRegionHk => '港股';

  @override
  String get analyticsBucketRegionUs => '美股';

  @override
  String get analyticsBucketRegionCrypto => '加密';

  @override
  String get analyticsBucketRegionFx => '外汇';

  @override
  String get analyticsBucketRegionUnknown => '其它';

  @override
  String get analyticsBucketMarketCapLarge => '大盘';

  @override
  String get analyticsBucketMarketCapMid => '中盘';

  @override
  String get analyticsBucketMarketCapSmall => '小盘';

  @override
  String analyticsHoldingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 只持仓',
    );
    return '$_temp0';
  }

  @override
  String analyticsUnclassifiedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还有 $count 只持仓缺少分类元数据。',
    );
    return '$_temp0';
  }

  @override
  String get analyticsUnclassifiedAction => '去补全';

  @override
  String get analyticsUnclassifiedRowCta => '点击持仓即可补全其分类信息。';

  @override
  String get analyticsEmptyTitle => '暂无股票持仓';

  @override
  String get analyticsEmptyHint => '录入股票或 ETF 交易后，此处将展示分布。';

  @override
  String get analyticsLoadError => '无法加载持仓分布。';

  @override
  String get analyticsRetry => '重试';

  @override
  String analyticsBucketSheetTitle(String label) {
    return '「$label」持仓';
  }

  @override
  String analyticsHoldingTooltip(String symbol, String value, String weight) {
    return '$symbol · $value · $weight';
  }

  @override
  String get benchmarkComparisonTitle => '基准指数对比';

  @override
  String get benchmarkComparisonSubtitle => '选定主流指数，与组合走势对照并查看超额收益。';

  @override
  String benchmarkComparisonError(String error) {
    return '无法加载基准对比：$error';
  }

  @override
  String get benchmarkSeriesPortfolio => '组合';

  @override
  String get benchmarkPortfolioAnnualizedLabel => '组合年化';

  @override
  String benchmarkAnnualizedSubtitle(String value) {
    return '年化 $value';
  }

  @override
  String get benchmarkIndexHs300 => '沪深 300';

  @override
  String get benchmarkIndexSp500 => '标普 500';

  @override
  String get benchmarkIndexNasdaq => '纳指';

  @override
  String get benchmarkIndexHsi => '恒生';
}
