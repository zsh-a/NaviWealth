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
  String get navExpenses => '支出';

  @override
  String get navAnalytics => '分析';

  @override
  String get navSettings => '设置';

  @override
  String get navPortfolio => '投资组合';

  @override
  String get navMore => '更多';

  @override
  String get navAI => 'AI';

  @override
  String get navAccounts => '账户';

  @override
  String get portfolioAssetsTab => '资产';

  @override
  String get portfolioLiabilitiesTab => '负债';

  @override
  String get moreAccountsSubtitle => '银行、券商与钱包';

  @override
  String get moreAnalyticsSubtitle => '配置、风险与基准';

  @override
  String get moreFireSubtitle => '财务自由追踪';

  @override
  String get moreAiSubtitle => 'AI 财务助手';

  @override
  String get moreRebalanceSubtitle => '目标与实际配置';

  @override
  String get moreSettingsSubtitle => '应用设置与设备';

  @override
  String get superFabTrade => '交易';

  @override
  String get superFabExpense => '记账';

  @override
  String get superFabAsset => '资产';

  @override
  String get superFabTransfer => '转账';

  @override
  String get superFabLiability => '负债';

  @override
  String get homeAppBarTitle => '总览';

  @override
  String get homeAiAssistantTooltip => 'AI 助手';

  @override
  String get homeRecordTradeTooltip => '录入交易';

  @override
  String get homeNetWorthTitle => '净资产';

  @override
  String homeNetWorthSubtitle(String currency) {
    return '基础货币 $currency · 等数据接入后展示';
  }

  @override
  String get assetsAppBarTitle => '资产';

  @override
  String get assetsDetailEmpty => '请在左侧选择资产以查看详情。';

  @override
  String get assetsEmptyHint => '尚未录入资产。点击右下角添加现金、存款、理财、房产或车辆。';

  @override
  String get assetsAddAction => '录入资产';

  @override
  String get assetsCorporateActionAction => '录入公司行动';

  @override
  String get assetsAccountsTooltip => '账户管理';

  @override
  String get assetsLiabilitiesTooltip => '负债与还款计划';

  @override
  String assetsLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get assetsAddCashTitle => '现金 / 多币种余额';

  @override
  String get assetsAddCashSubtitle => '登记银行活期或现金账户中的可用余额';

  @override
  String get assetsAddDepositTitle => '存款（定期 / 活期）';

  @override
  String get assetsAddDepositSubtitle => '记录利率、起息日、到期日';

  @override
  String get assetsAddWealthTitle => '理财产品';

  @override
  String get assetsAddWealthSubtitle => '预期年化、当前估值手动维护';

  @override
  String get assetsAddRealEstateSubtitle => '地址、购入价、当前估值，可关联房贷';

  @override
  String get assetsAddVehicleSubtitle => '购入价、年度残值率、自动折旧';

  @override
  String get assetsAddLiabilityTitle => '负债（房贷 / 车贷 / 信用卡 / 消费贷）';

  @override
  String get assetsAddLiabilitySubtitle => '录入并跟踪还款计划';

  @override
  String get assetsAddCorporateActionSubtitle => '分红 / 拆股 / 配股 / 红股 / DRIP';

  @override
  String get assetsAddTradeTitle => '证券交易';

  @override
  String get assetsAddTradeSubtitle => '买入 / 卖出股票、ETF、加密货币';

  @override
  String assetsChipInterestRate(String rate) {
    return '利率 $rate%';
  }

  @override
  String assetsChipExpectedReturn(String rate) {
    return '预期 $rate%';
  }

  @override
  String assetsChipMaturityDate(String date) {
    return '$date 到期';
  }

  @override
  String get assetTypeCash => '现金';

  @override
  String get assetTypeBankDepositTerm => '定期存款';

  @override
  String get assetTypeBankDepositDemand => '活期存款';

  @override
  String get assetTypeWealthProduct => '理财产品';

  @override
  String get assetTypeStock => '股票';

  @override
  String get assetTypeEtf => 'ETF';

  @override
  String get assetTypeMutualFund => '基金';

  @override
  String get assetTypeBond => '债券';

  @override
  String get assetTypeCrypto => '加密货币';

  @override
  String securitiesHoldingQuantity(String quantity) {
    return '持仓 $quantity';
  }

  @override
  String get securitiesHoldingFlat => '暂无持仓';

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
  String get settingsBaseCurrencyHint => '总览、资产分布、净资产趋势的汇总数字均以此币种展示。';

  @override
  String get settingsBaseCurrencySheetTitle => '选择基础货币';

  @override
  String get settingsFxRatesTitle => '汇率管理';

  @override
  String get settingsFxRatesSubtitle => '汇率自动从 Yahoo Finance 同步，支持手动录入作为备用。';

  @override
  String get fxRatesAppBarTitle => '汇率';

  @override
  String get fxRatesEmpty => '尚无汇率数据。汇率会在启动时自动同步 — 请先添加不同币种的账户。';

  @override
  String get fxRatesRefreshing => '正在同步汇率…';

  @override
  String get fxRatesSyncedFrom => '来源';

  @override
  String get fxRatesAddAction => '添加汇率';

  @override
  String get fxRatesEntrySheetTitle => '新增汇率';

  @override
  String get fxRatesFromLabel => '源币种';

  @override
  String get fxRatesToLabel => '目标币种';

  @override
  String get fxRatesRateLabel => '汇率';

  @override
  String get fxRatesAsOfLabel => '日期';

  @override
  String get fxRatesSamePairError => '源币种与目标币种不能相同。';

  @override
  String get fxRatesInvalidRateError => '汇率必须为正数。';

  @override
  String dashboardCurrencyMismatchBanner(int count, String currency) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 项资产因缺少到 $currency 的汇率而未计入合计',
    );
    return '$_temp0';
  }

  @override
  String get dashboardCurrencyMismatchAction => '查看';

  @override
  String get dashboardCurrencyMismatchSheetTitle => '未计入合计的资产';

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
  String get commonSaving => '保存中…';

  @override
  String get commonDelete => '删除';

  @override
  String get commonClose => '关闭';

  @override
  String get commonLoading => '加载中…';

  @override
  String get commonError => '出错了';

  @override
  String commonLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get commonSaveFailed => '保存失败，点击重试';

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
  String get shortcutToggleSidebar => '收起 / 展开侧边栏';

  @override
  String shortcutSwitchTab(int position, String label) {
    return '切换到第 $position 个标签 ($label)';
  }

  @override
  String get shortcutOpenAiChat => '打开 AI 对话';

  @override
  String shortcutVimGoto(String target) {
    return 'Vim 风格跳转到 $target';
  }

  @override
  String get shortcutListSearch => '聚焦列表搜索';

  @override
  String get shortcutListNext => '选择下一项';

  @override
  String get shortcutListPrevious => '选择上一项';

  @override
  String get commandPaletteSearchHint => '搜索命令…';

  @override
  String get commandPaletteEmpty => '没有匹配的命令';

  @override
  String commandPaletteAskAi(String query) {
    return '问 AI：$query';
  }

  @override
  String get commandPaletteGoOverview => '前往 总览';

  @override
  String get commandPaletteGoAssets => '前往 资产';

  @override
  String get commandPaletteGoAccounts => '前往 账户';

  @override
  String get commandPaletteGoExpenses => '前往 支出';

  @override
  String get commandPaletteGoAnalytics => '前往 分析';

  @override
  String get commandPaletteGoFire => '前往 FIRE';

  @override
  String get commandPaletteGoSettings => '前往 设置';

  @override
  String get commandPaletteNewTrade => '新增交易';

  @override
  String get commandPaletteNewExpense => '新增支出';

  @override
  String get commandPaletteOpenAi => '打开 AI 助手';

  @override
  String get commandPaletteToggleTheme => '切换主题（亮色 / 暗色）';

  @override
  String get commandPaletteToggleColorMode => '切换涨跌颜色模式';

  @override
  String get commandPaletteToggleLanguage => '切换语言';

  @override
  String get commandPaletteShortcutHelp => '显示键盘快捷键';

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
  String get dashboardHeaderDeltaTodayLabel => '今日';

  @override
  String get dashboardHeaderDeltaMonthLabel => '本月';

  @override
  String get dashboardHeaderDeltaYtdLabel => '年初至今';

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
  String get navFire => 'FIRE';

  @override
  String get fireAppBarTitle => 'FIRE 仪表盘';

  @override
  String fireLoadError(String detail) {
    return 'FIRE 仪表盘加载失败。$detail';
  }

  @override
  String get fireRetry => '重试';

  @override
  String get fireEmptyTitle => '设定 FIRE 目标';

  @override
  String get fireEmptyHint => '填写目标净资产、月支出与月结余，量化追踪距离财务自由还有多远。';

  @override
  String get fireEmptySetGoalCta => '设定目标';

  @override
  String get fireEditGoal => '修改目标';

  @override
  String get fireGoalSheetTitle => 'FIRE 目标';

  @override
  String get fireGoalSheetSubtitle => '数据仅保存在本地，目标按下方通胀率折算购买力。';

  @override
  String get fireGoalSheetCancel => '取消';

  @override
  String get fireGoalSheetSave => '保存';

  @override
  String get fireGoalFieldTarget => '目标净资产';

  @override
  String get fireGoalFieldTargetHelper => '退休所需净资产，以今日购买力计。';

  @override
  String get fireGoalFieldMonthlyExpenses => '退休后月支出';

  @override
  String get fireGoalFieldMonthlyExpensesHelper => '用于 4% 提取规则校验目标是否能覆盖生活开销。';

  @override
  String get fireGoalFieldMonthlySurplus => '当前月结余';

  @override
  String get fireGoalFieldMonthlySurplusHelper => '每月可投入的金额，是模拟曲线的现金流来源。';

  @override
  String fireGoalFieldInflation(String rate) {
    return '通胀率：$rate%';
  }

  @override
  String get fireGoalValidationRequired => '必填';

  @override
  String get fireGoalValidationInvalidNumber => '请输入有效数字';

  @override
  String get fireGoalValidationNonNegative => '不能为负数';

  @override
  String get fireGoalValidationPositive => '请输入大于 0 的数字';

  @override
  String get fireProgressTitle => '进度';

  @override
  String get fireProgressGaugeCaption => '已达成目标比例';

  @override
  String get fireProgressCurrent => '当前净资产';

  @override
  String get fireProgressTarget => '目标';

  @override
  String get fireProgressGap => '距 FIRE 差额';

  @override
  String fireCountdownTitle(String scenario) {
    return '倒计时 · $scenario';
  }

  @override
  String get fireCountdownReachedTitle => '已达成 FIRE';

  @override
  String get fireCountdownReachedSubtitle => '净资产已超过目标，可关注 4% 安全提取下的可持续支出。';

  @override
  String get fireCountdownUnreachable => '按当前结余与收益率，100 年内无法达成目标。请提高储蓄或调整收益预期。';

  @override
  String get fireCountdownUnreachableShort => '100年+';

  @override
  String fireCountdownYearsOnly(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years 年',
    );
    return '$_temp0';
  }

  @override
  String fireCountdownMonthsOnly(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months 个月',
    );
    return '$_temp0';
  }

  @override
  String fireCountdownYearsMonths(int years, int months) {
    return '$years 年 $months 个月';
  }

  @override
  String fireCountdownDaysAprox(int days) {
    return '约 $days 天';
  }

  @override
  String get fireProjectionTitle => '多场景模拟';

  @override
  String get fireProjectionSubtitle => '各收益场景下的净资产路径；虚线为通胀调整后的目标。';

  @override
  String get fireProjectionTargetLineLegend => '目标（通胀调整）';

  @override
  String get fireScenariosTableTitle => '场景对比';

  @override
  String get fireScenarioConservative => '保守';

  @override
  String get fireScenarioNeutral => '中性';

  @override
  String get fireScenarioAggressive => '激进';

  @override
  String get fireScenarioLive => '实际（XIRR）';

  @override
  String fireScenarioRateLabel(String rate) {
    return '年化 $rate%';
  }

  @override
  String get fireScenarioReachedNow => '现在';

  @override
  String get fireSafeWithdrawalTitle => '4% 提取规则';

  @override
  String get fireSafeWithdrawalSubtitle => 'Trinity 研究安全提取率：每年取目标的 4%，按今日购买力计。';

  @override
  String get fireSafeWithdrawalMonthly => '安全月提取';

  @override
  String get fireSafeWithdrawalAnnual => '安全年提取';

  @override
  String get fireSafeWithdrawalNoExpenses => '填写月支出后可与提取额对比。';

  @override
  String fireSafeWithdrawalCovers(String amount) {
    return '覆盖计划支出，每月剩余 $amount。';
  }

  @override
  String fireSafeWithdrawalShortfall(String amount) {
    return '每月仍缺口 $amount。';
  }

  @override
  String get fireSensitivityTitle => '结余敏感度';

  @override
  String get fireSensitivitySubtitle => '月结余 ±20% 对达成时间的影响。';

  @override
  String get fireSensitivityHigherSurplus => '结余 +20%';

  @override
  String get fireSensitivityBaseline => '当前结余';

  @override
  String get fireSensitivityLowerSurplus => '结余 -20%';

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

  @override
  String get rebalanceTitle => '再平衡';

  @override
  String get rebalanceSchemeTitle => '目标方案';

  @override
  String get rebalanceSchemeConservative => '保守';

  @override
  String get rebalanceSchemeBalanced => '平衡';

  @override
  String get rebalanceSchemeAggressive => '激进';

  @override
  String get rebalanceSchemeCustom => '自定义';

  @override
  String get rebalanceDriftTitle => '偏离总览';

  @override
  String rebalanceOverallDrift(String value) {
    return '整体偏离：$value';
  }

  @override
  String get rebalanceBalanced => '在目标范围内';

  @override
  String get rebalanceTradeTitle => '建议交易';

  @override
  String get rebalanceBuy => '买入';

  @override
  String get rebalanceSell => '卖出';

  @override
  String get rebalanceEstimatedFees => '估算费用';

  @override
  String get rebalanceEstimatedTaxes => '估算税费';

  @override
  String get rebalanceDriftAfter => '再平衡后偏离';

  @override
  String get rebalanceEmptyTitle => '暂无数据';

  @override
  String get rebalanceEmptyHint => '添加资产后即可查看偏离与再平衡建议。';

  @override
  String get rebalanceSettingsTooltip => '再平衡设置';

  @override
  String get rebalanceSettingsTitle => '设置';

  @override
  String get rebalanceWarningThreshold => '预警阈值';

  @override
  String get rebalanceCriticalThreshold => '严重阈值';

  @override
  String get rebalanceNavLink => '再平衡';

  @override
  String get riskAlertTitle => '集中度预警';

  @override
  String riskAlertAssetTitle(String name) {
    return '$name 持仓过重';
  }

  @override
  String riskAlertSectorTitle(String sector) {
    return '$sector 板块过重';
  }

  @override
  String riskAlertRegionTitle(String region) {
    return '$region 地域过重';
  }

  @override
  String riskAlertCurrencyTitle(String currency) {
    return '$currency 敞口过大';
  }

  @override
  String riskAlertThresholdBreached(String dimension, String threshold) {
    return '$dimension 阈值：$threshold';
  }

  @override
  String get riskDimensionAsset => '资产';

  @override
  String get riskDimensionSector => '行业';

  @override
  String get riskDimensionRegion => '地域';

  @override
  String get riskDimensionCurrency => '币种';

  @override
  String get settingsRiskSection => '风险偏好';

  @override
  String get settingsRiskAssetLabel => '单一资产上限';

  @override
  String get settingsRiskAssetSubtitle => '单只资产占总资产比例超过此值时预警。';

  @override
  String get settingsRiskSectorLabel => '行业上限';

  @override
  String get settingsRiskSectorSubtitle => '单一行业占比超过此值时预警。';

  @override
  String get settingsRiskRegionLabel => '地域上限';

  @override
  String get settingsRiskRegionSubtitle => '单一市场 / 地域占比超过此值时预警。';

  @override
  String get settingsRiskCurrencyLabel => '币种上限';

  @override
  String get settingsRiskCurrencySubtitle => '单一币种敞口超过此值时预警。';

  @override
  String get settingsRiskResetDefaults => '恢复默认';

  @override
  String get tradeEntryAppBarTitle => '录入交易';

  @override
  String get tradeEntrySuccess => '交易录入成功';

  @override
  String tradeEntryFailure(String error) {
    return '录入失败：$error';
  }

  @override
  String get tradeEntryQuantityLabel => '数量';

  @override
  String get tradeEntryPriceLabel => '价格';

  @override
  String get tradeEntryPriceHelper => '留空则自动从市场数据获取';

  @override
  String get tradeEntryDateLabel => '交易日期';

  @override
  String get tradeEntryFeeLabel => '手续费';

  @override
  String get tradeEntryTaxLabel => '税费';

  @override
  String get tradeEntryCashAccountLabel => '资金账户';

  @override
  String tradeEntryCatalogLoadError(String error) {
    return '目录加载失败：$error';
  }

  @override
  String get tradeEntryDecimalScaleHintGeneric => '股票/ETF 最多 8 位小数，加密最多 18 位';

  @override
  String tradeEntryDecimalScaleHint(int scale) {
    return '最多 $scale 位小数';
  }

  @override
  String get tradeTypeBuy => '买入';

  @override
  String get tradeTypeSell => '卖出';

  @override
  String get tradeTypeTransferIn => '转入';

  @override
  String get tradeTypeTransferOut => '转出';

  @override
  String get tradeTypeValuationAdjust => '估值调整';

  @override
  String get tradeTypeDividend => '分红';

  @override
  String get tradeTypeReinvest => '再投资';

  @override
  String get tradeTypeInterest => '利息';

  @override
  String get tradeTypeDeposit => '存入';

  @override
  String get tradeTypeWithdraw => '取出';

  @override
  String get tradeTypeFee => '费用';

  @override
  String get tradeTypeTax => '税费';

  @override
  String get tradeTypeSplit => '拆股';

  @override
  String get tradeTypeLiabilityPayment => '还款';

  @override
  String get tradeTypeExpense => '支出';

  @override
  String get expensesReportTooltip => '月度报表';

  @override
  String get expenseFormCreateTitle => '新建支出';

  @override
  String get expenseFormEditTitle => '编辑支出';

  @override
  String get expenseFormDeleteTooltip => '删除';

  @override
  String get expenseFormAmountLabel => '金额';

  @override
  String get expenseFormAmountInvalid => '金额必须大于 0';

  @override
  String get expenseFormCategoryAccountRequired => '请选择类目、账户和币种';

  @override
  String get expenseFormCategoriesLoading => '正在准备默认类目，请稍候…';

  @override
  String expenseFormCategoriesLoadError(String error) {
    return '类目加载失败：$error';
  }

  @override
  String get expenseFormAccountLabel => '账户';

  @override
  String expenseFormAccountsLoadError(String error) {
    return '账户加载失败：$error';
  }

  @override
  String get expenseFormDateLabel => '日期';

  @override
  String get expenseFormDeleteDialogTitle => '删除支出';

  @override
  String get expenseFormDeleteDialogBody => '确认删除此支出？该操作可同步给其他设备。';

  @override
  String get expenseFormNoAccountsTitle => '先创建一个账户';

  @override
  String get expenseFormNoAccountsBody => '支出需要选择资金账户。前往「账户」新建后再来录入。';

  @override
  String get expenseFormNoAccountsCta => '去创建';

  @override
  String get expenseHistorySectionTitle => '变更历史';

  @override
  String get expenseHistoryEmpty => '暂无变更记录。';

  @override
  String expenseHistoryLoadError(String error) {
    return '变更历史加载失败：$error';
  }

  @override
  String get expenseHistoryEventCreated => '新建';

  @override
  String get expenseHistoryEventChanged => '修改';

  @override
  String get expenseHistoryEventDeleted => '删除';

  @override
  String get expenseHistoryEventRestored => '恢复';

  @override
  String get expenseHistoryCreatedBody => '已记录该支出。';

  @override
  String get expenseHistoryDeletedBody => '已删除该支出。';

  @override
  String get expenseHistoryRestoredBody => '已恢复该支出。';

  @override
  String get expenseHistoryFieldAmount => '金额';

  @override
  String get expenseHistoryFieldCurrency => '币种';

  @override
  String get expenseHistoryFieldAccount => '账户';

  @override
  String get expenseHistoryFieldCategory => '类目';

  @override
  String get expenseHistoryFieldDate => '日期';

  @override
  String get expenseHistoryFieldNote => '备注';

  @override
  String get expenseHistoryFieldTags => '标签';

  @override
  String get expenseHistoryEmptyValue => '—';

  @override
  String get expenseHistoryUnknownReference => '（未知）';

  @override
  String expenseHistoryReasonLabel(String reason) {
    return '原因：$reason';
  }

  @override
  String get aiChatAppBarTitle => 'AI 助手';

  @override
  String get aiChatHistoryTooltip => '历史对话';

  @override
  String get aiChatNewSessionTooltip => '新建对话';

  @override
  String get aiChatLoginRequired => '请先登录后再使用 AI 助手。';

  @override
  String get aiChatEmptyTitle => '你的财务助手';

  @override
  String get aiChatEmptyBody => '基于你的持仓与账本分录回答问题。所有金额来自你本地同步的账本，模型不会自行计算关键数字。';

  @override
  String get aiChatEmptySuggestion1 => '我最近三个月赚了多少？';

  @override
  String get aiChatEmptySuggestion2 => '帮我看看持仓里风险最高的资产。';

  @override
  String get aiChatEmptySuggestion3 => '我的行业分布是怎样的？';

  @override
  String get aiChatEmptySuggestion4 => '从开户到现在我的 XIRR 是多少？';

  @override
  String get aiChatSessionsHeader => '对话';

  @override
  String get aiChatSessionsEmpty => '点击右上角的 + 开始第一个对话。';

  @override
  String get aiChatSessionMoreTooltip => '更多';

  @override
  String get aiChatSessionRenameAction => '重命名';

  @override
  String get aiChatSessionRenameTitle => '重命名';

  @override
  String get aiChatSessionTitleLabel => '标题';

  @override
  String get aiChatSessionDeleteTitle => '删除对话？';

  @override
  String aiChatSessionDeleteBody(String title) {
    return '「$title」中的所有消息都会被删除。';
  }

  @override
  String get aiChatRelativeJustNow => '刚刚';

  @override
  String aiChatRelativeMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String aiChatRelativeHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String aiChatRelativeDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get aiChatComposerHintIdle => '问问 NaviWealth：例如\"我最近一个月赚了多少？\"';

  @override
  String get aiChatComposerHintStreaming => '正在生成回答…';

  @override
  String get aiChatComposerHintFlushing => '正在同步本地数据…';

  @override
  String get aiChatComposerSendTooltip => '发送 (⌘/Ctrl + Enter)';

  @override
  String get aiChatComposerStopTooltip => '停止生成';

  @override
  String get aiChatThinking => '正在思考…';

  @override
  String get aiChatStaleSyncNotice => '本地数据未完成同步，回答可能滞后于你刚刚的录入。';

  @override
  String get aiChatProposalKindTrade => '交易';

  @override
  String get aiChatProposalKindExpense => '支出';

  @override
  String get aiChatProposalKindLiabilityPayment => '还款';

  @override
  String get aiChatProposalKindAccountCreate => '新账户';

  @override
  String get aiChatProposalKindAssetValuation => '估值更新';

  @override
  String get aiChatProposalKindUnknown => '未知';

  @override
  String aiChatProposalPendingHeader(String kind) {
    return '待确认 · $kind';
  }

  @override
  String aiChatProposalNeedsClarificationHeader(String kind) {
    return '需要澄清 · $kind';
  }

  @override
  String get aiChatProposalCandidatesHeading => '候选：';

  @override
  String aiChatProposalSummaryEdited(String summary) {
    return '$summary（已编辑）';
  }

  @override
  String get aiChatProposalConfirm => '确认';

  @override
  String get aiChatProposalApplying => '记录中…';

  @override
  String get aiChatProposalEdit => '编辑';

  @override
  String aiChatProposalEditKindTitle(String kind) {
    return '编辑$kind';
  }

  @override
  String get aiChatProposalSaveEdits => '保存修改';

  @override
  String aiChatProposalFailure(String error) {
    return '失败：$error';
  }

  @override
  String aiChatProposalUndoFailure(String error) {
    return '撤销失败：$error';
  }

  @override
  String aiChatProposalAppliedFallback(String summary) {
    return '已记录$summary';
  }

  @override
  String aiChatProposalUndoneLabel(String summary) {
    return '已撤销$summary';
  }

  @override
  String aiChatProposalCancelledLabel(String summary) {
    return '已取消：$summary';
  }

  @override
  String aiChatProposalUndoCountdown(int seconds) {
    return '撤销 (${seconds}s)';
  }

  @override
  String aiChatProposalBatchPending(int count) {
    return '本轮共有 $count 项待确认';
  }

  @override
  String get aiChatProposalBatchConfirmAll => '全部确认';

  @override
  String get aiChatFieldQuantity => '数量';

  @override
  String get aiChatFieldPrice => '价格 (留空则市场回填)';

  @override
  String get aiChatFieldFee => '手续费';

  @override
  String get aiChatFieldTax => '税费';

  @override
  String get aiChatFieldNote => '备注';

  @override
  String get aiChatFieldAmount => '金额';

  @override
  String get aiChatFieldDate => '日期 (RFC3339)';

  @override
  String get aiChatFieldDateHint => '2026-04-30T12:00:00Z';

  @override
  String get aiChatFieldAccountName => '账户名';

  @override
  String get aiChatFieldInstitution => '机构 (可选)';

  @override
  String get aiChatFieldNewValuation => '新估值';

  @override
  String get aiChatRowOperation => '操作';

  @override
  String get aiChatRowAsset => '资产';

  @override
  String get aiChatRowAccount => '账户';

  @override
  String get aiChatRowQuantity => '数量';

  @override
  String get aiChatRowPrice => '价格';

  @override
  String get aiChatRowFee => '手续费';

  @override
  String get aiChatRowDate => '日期';

  @override
  String get aiChatRowNote => '备注';

  @override
  String get aiChatRowAmount => '金额';

  @override
  String get aiChatRowCategory => '类目';

  @override
  String get aiChatRowLiability => '负债';

  @override
  String get aiChatRowRepayAccount => '还款账户';

  @override
  String get aiChatRowName => '名称';

  @override
  String get aiChatRowType => '类型';

  @override
  String get aiChatRowCurrency => '币种';

  @override
  String get aiChatRowInstitution => '机构';

  @override
  String get aiChatRowNewValue => '新估值';

  @override
  String get aiChatToolGetHoldings => '查询持仓';

  @override
  String get aiChatToolComputeXirr => '计算 XIRR';

  @override
  String get aiChatToolComputeNetWorth => '计算净资产';

  @override
  String get aiChatToolGetIndustryBreakdown => '行业分布';

  @override
  String get aiChatToolGetGeoBreakdown => '地域分布';

  @override
  String get aiChatToolGetMarketCapBreakdown => '市值分布';

  @override
  String get aiChatToolGetRiskAlerts => '风险预警';

  @override
  String get aiChatToolFallback => '工具';

  @override
  String get aiChatToolInputLabel => '参数';

  @override
  String get aiChatToolOutputLabel => '结果';

  @override
  String aiChatToolJumpAsset(String id) {
    return '资产 $id';
  }

  @override
  String aiChatToolJumpAccount(String id) {
    return '账户 $id';
  }

  @override
  String aiChatToolJumpLiability(String id) {
    return '负债 $id';
  }

  @override
  String get aiChatToolShowRawJson => '查看 raw JSON';

  @override
  String get aiChatToolShowCompactView => '返回精简视图';

  @override
  String get aiFloatingPillLabel => '问问 AI';

  @override
  String get aiChatSheetTitle => 'AI 助手';

  @override
  String get aiChatSheetEmpty => '随便问问你的财务情况。';

  @override
  String get aiChatSheetExpandTooltip => '展开全屏';

  @override
  String get chartEmptyDefault => '暂无数据';

  @override
  String get formAmountFieldLabelDefault => '金额';

  @override
  String get formAmountFieldRequired => '请输入金额';

  @override
  String get formAmountFieldInvalid => '金额格式不正确';

  @override
  String get formAmountFieldNegativeNotAllowed => '金额不能为负';

  @override
  String get formNoteFieldLabelDefault => '备注';

  @override
  String get formDateFieldClearTooltip => '清除';

  @override
  String get formDateFieldRequired => '请选择日期';

  @override
  String get formAccountPickerLabelDefault => '账户';

  @override
  String get formAccountPickerRequired => '请选择账户';

  @override
  String get formCurrencyPickerLabelDefault => '币种';

  @override
  String get formCurrencyPickerRequired => '请选择币种';

  @override
  String currencyOptionLabel(String code, String name) {
    return '$code · $name';
  }

  @override
  String get currencyNameCNY => '人民币';

  @override
  String get currencyNameUSD => '美元';

  @override
  String get currencyNameHKD => '港币';

  @override
  String get currencyNameEUR => '欧元';

  @override
  String get currencyNameJPY => '日元';

  @override
  String get currencyNameGBP => '英镑';

  @override
  String get currencyNameSGD => '新加坡元';

  @override
  String get currencyNameAUD => '澳大利亚元';

  @override
  String get currencyNameCAD => '加拿大元';

  @override
  String get currencyNameTWD => '新台币';

  @override
  String get expenseCategoryPickerLabelDefault => '类目';

  @override
  String get expenseCategoryPickerRequired => '请选择类目';

  @override
  String get physicalAssetValuationProjected => '预计估值';

  @override
  String get physicalAssetValuationHistorical => '历史估值';

  @override
  String get physicalAssetValuationTrendSemanticLabel => '估值走势';

  @override
  String get accountsAppBarTitle => '账户';

  @override
  String get accountsDetailEmpty => '请在左侧选择账户以编辑详情。';

  @override
  String get accountsCreateAction => '新建账户';

  @override
  String accountsLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get accountsEmptyHint => '还没有账户。点击右下角新建一个，再去录入资产。';

  @override
  String get accountTypeBrokerage => '券商账户';

  @override
  String get accountTypeBank => '银行账户';

  @override
  String get accountTypeCryptoWallet => '加密钱包';

  @override
  String get accountTypeRealEstate => '不动产账户';

  @override
  String get accountTypeVehicle => '车辆账户';

  @override
  String get accountTypeLiability => '负债账户';

  @override
  String get accountTypeCash => '现金账户';

  @override
  String get accountTypeOther => '其他账户';

  @override
  String get accountCategoryAsset => '资产';

  @override
  String get accountCategoryLiability => '负债';

  @override
  String get accountCategoryIncome => '收入';

  @override
  String get accountCategoryExpense => '支出';

  @override
  String get accountCategoryEquity => '权益';

  @override
  String get accountFormCreateTitle => '新建账户';

  @override
  String get accountFormEditTitle => '编辑账户';

  @override
  String get accountFormDeleteTooltip => '删除';

  @override
  String get accountFormDeleteTitle => '删除账户';

  @override
  String accountFormDeleteContent(String name) {
    return '确认删除“$name”？该操作可同步给其他设备。';
  }

  @override
  String get accountFormCancelAction => '取消';

  @override
  String get accountFormDeleteAction => '删除';

  @override
  String get accountFormTypeLabel => '账户类型';

  @override
  String get accountFormCategoryLabel => '账户类别';

  @override
  String get accountFormCategoryHelper => '用于复式记账的会计分类。默认根据账户类型推荐，可手动调整。';

  @override
  String get accountFormNameLabel => '账户名称';

  @override
  String get accountFormNameRequired => '请输入账户名称';

  @override
  String get accountFormInstitutionLabel => '机构';

  @override
  String get accountFormInstitutionHelper => '银行 / 券商 / 平台名称（可选）';

  @override
  String get accountFormAccountNumberLabel => '账号 / 末位号（可选）';

  @override
  String get accountFormArchivedTitle => '归档';

  @override
  String get accountFormArchivedSubtitle => '归档后不会出现在主列表中。';

  @override
  String get accountFormSaving => '保存中…';

  @override
  String get accountFormSave => '保存';

  @override
  String get cashFormCreateTitle => '录入现金余额';

  @override
  String get cashFormEditTitle => '编辑现金余额';

  @override
  String get cashFormDeleteTooltip => '删除';

  @override
  String cashFormLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get cashFormNeedAccountHint => '请先创建一个银行 / 现金账户。';

  @override
  String get cashFormCreateAccountAction => '新建账户';

  @override
  String get cashFormBalanceLabel => '余额';

  @override
  String get cashFormNicknameLabel => '备注名（可选）';

  @override
  String get cashFormNicknameHelper => '例如：招行港币活期、零钱通';

  @override
  String get cashFormSaving => '保存中…';

  @override
  String get cashFormSave => '保存';

  @override
  String get manualAssetDeleteTitle => '删除资产';

  @override
  String get manualAssetDeleteContent => '确认删除该资产记录？';

  @override
  String get manualAssetDeleteCancel => '取消';

  @override
  String get manualAssetDeleteConfirm => '删除';
}
