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
  String get navExpenses => '支出';

  @override
  String get navSettings => '设置';

  @override
  String get navActivity => '流水';

  @override
  String get navAccounts => '账户';

  @override
  String get navSearch => '搜索';

  @override
  String get cashFlowTitle => '现金流';

  @override
  String get cashFlowCommandOpen => '打开现金流';

  @override
  String get cashFlowCommandViewIncome => '查看收入流水';

  @override
  String get cashFlowPeriodMonth => '月';

  @override
  String get cashFlowPeriodQuarter => '季';

  @override
  String get cashFlowPeriodYear => '年';

  @override
  String get cashFlowKpiInflow => '流入';

  @override
  String get cashFlowKpiOutflow => '流出';

  @override
  String get cashFlowKpiNet => '净额';

  @override
  String get cashFlowIncomeExpenseTitle => '收入 vs 支出';

  @override
  String get cashFlowNetTrendTitle => '净现金流趋势';

  @override
  String get cashFlowCategoryTitle => '类目分布';

  @override
  String get cashFlowViewDividendCenter => '查看股息中心';

  @override
  String get cashFlowEmptyTitle => '暂无现金流';

  @override
  String get cashFlowEmptyBody => '记录交易后，收入与支出会显示在这里。';

  @override
  String cashFlowLoadError(String error) {
    return '现金流加载失败：$error';
  }

  @override
  String get recurringListTitle => '周期收支';

  @override
  String get recurringCommandOpen => '周期收支';

  @override
  String get commandKeywordRecurringCn => '周期';

  @override
  String recurringLoadError(String error) {
    return '周期规则加载失败：$error';
  }

  @override
  String get recurringEmptyTitle => '暂无周期规则';

  @override
  String get recurringEmptyBody => '为工资、订阅或其他重复现金流设置规则。';

  @override
  String get recurringEmptyCta => '新增周期规则';

  @override
  String recurringNextDue(String date) {
    return '下次：$date';
  }

  @override
  String get recurringTemplateCorrupt => '模板无法读取';

  @override
  String get recurringRowActionsTitle => '周期规则';

  @override
  String get recurringActionEdit => '编辑';

  @override
  String get recurringActionEditHint => '修改金额或周期';

  @override
  String get recurringActionDisable => '停用';

  @override
  String get recurringActionDisableHint => '停止生成新记录';

  @override
  String get recurringActionDeleteHint => '永久删除该规则';

  @override
  String get recurringDisableTitle => '停用规则？';

  @override
  String get recurringDisableBody => '将停止生成新记录，之后可重新创建。';

  @override
  String get recurringDeleteTitle => '删除规则？';

  @override
  String get recurringDeleteBody => '该周期规则将被删除，此操作不可撤销。';

  @override
  String get recurringDisabled => '规则已停用';

  @override
  String get recurringDeleted => '规则已删除';

  @override
  String get recurringActionFailed => '操作失败';

  @override
  String recurringEveryDay(int n) {
    return '每 $n 天';
  }

  @override
  String recurringEveryWeek(int n) {
    return '每 $n 周';
  }

  @override
  String recurringEveryMonth(int n) {
    return '每 $n 个月';
  }

  @override
  String recurringEveryYear(int n) {
    return '每 $n 年';
  }

  @override
  String recurringByMonthDay(int day) {
    return '每月 $day 号';
  }

  @override
  String recurringUntil(String date) {
    return '至 $date';
  }

  @override
  String get recurringFormNewTitle => '新建周期规则';

  @override
  String get recurringFormEditTitle => '编辑周期规则';

  @override
  String get recurringFormSubtitle => '每次到期生成一笔记账分录';

  @override
  String get recurringFormSave => '保存';

  @override
  String get recurringFieldKind => '类型';

  @override
  String get recurringKindIncome => '收入';

  @override
  String get recurringKindExpense => '支出';

  @override
  String get recurringFieldAmount => '金额';

  @override
  String get recurringFieldCashAccount => '现金账户';

  @override
  String get recurringFieldCategoryAccount => '对方科目';

  @override
  String get recurringFieldNote => '备注';

  @override
  String get recurringFieldStart => '起始日';

  @override
  String get recurringFieldFrequency => '频率';

  @override
  String get recurringFreqDaily => '每天';

  @override
  String get recurringFreqWeekly => '每周';

  @override
  String get recurringFreqMonthly => '每月';

  @override
  String get recurringFreqYearly => '每年';

  @override
  String get recurringFieldInterval => '每隔几个周期';

  @override
  String get recurringFieldByMonthDay => '每月几号';

  @override
  String get recurringFieldByMonthDayHelper => '可选，1–31';

  @override
  String get recurringFieldUntil => '结束日期';

  @override
  String get recurringFieldUntilHelper => '可选';

  @override
  String get recurringValidationRequired => '必填';

  @override
  String get recurringValidationPositive => '请输入大于 0 的金额';

  @override
  String get recurringValidationInterval => '请输入正整数';

  @override
  String get recurringValidationByMonthDay => '日期需在 1–31 之间';

  @override
  String get recurringValidationAccounts => '请选择两个账户';

  @override
  String get recurringValidationSameAccount => '现金账户与对方科目不能相同';

  @override
  String get recurringValidationCurrency => '请选择币种';

  @override
  String get recurringDefaultNarration => '周期交易';

  @override
  String get recurringSaveFailed => '无法保存该规则';

  @override
  String get cashFlowKindSalary => '工资';

  @override
  String get cashFlowKindDividend => '股息';

  @override
  String get cashFlowKindInterest => '利息';

  @override
  String get cashFlowKindCapitalGains => '资本利得';

  @override
  String get cashFlowKindOtherIncome => '其他收入';

  @override
  String get cashFlowKindExpense => '支出';

  @override
  String get cashFlowKindTransfer => '转账';

  @override
  String get cashFlowKindOpening => '期初';

  @override
  String get cashFlowKindOther => '其他';

  @override
  String get dividendCenterTitle => '股息中心';

  @override
  String get dividendCenterMetricYtd => '年初至今';

  @override
  String get dividendCenterMetricTtm => '近 12 个月';

  @override
  String get dividendCenterMetricYoy => '同比同期';

  @override
  String get dividendCenterMetricWithholding => '预扣税';

  @override
  String get dividendCenterHoldingRanking => '持仓排行';

  @override
  String get dividendCenterHistoryTimeline => '历史时间线';

  @override
  String get dividendCenterForecastTitle => '未来 12 个月';

  @override
  String get dividendCenterForecastUnavailable => '预测尚未启用。';

  @override
  String dividendCenterForecastSource(String source) {
    return '来源：$source';
  }

  @override
  String get dividendCenterEmptyTitle => '暂无股息记录';

  @override
  String get dividendCenterEmptyBody => '记录现金分红或公司行动后开始生成时间线。';

  @override
  String get dividendCenterRecordAction => '记录股息';

  @override
  String dividendCenterLoadError(String error) {
    return '股息中心加载失败：$error';
  }

  @override
  String get dividendEventActionsTitle => '股息记录';

  @override
  String get dividendEventViewInActivity => '在流水中查看';

  @override
  String get dividendEventViewInActivityHint => '打开对应的记账分录';

  @override
  String get dividendEventEdit => '编辑（重新记录）';

  @override
  String get dividendEventEditHint => '通过公司行动表单修正记录';

  @override
  String get dividendEventDeleteHint => '删除这条股息记录';

  @override
  String get dividendEventDeleteTitle => '删除股息？';

  @override
  String dividendEventDeleteBody(String asset) {
    return '确定删除 $asset 的股息记录？此操作不可撤销。';
  }

  @override
  String get dividendEventDeleted => '股息已删除';

  @override
  String get dividendEventDeleteFailed => '无法删除该股息';

  @override
  String get dividendEventOpenFailed => '无法打开该记录';

  @override
  String get dividendForecastStrategyDeclared => '已声明';

  @override
  String get dividendForecastStrategyDps => 'DPS';

  @override
  String get dividendForecastStrategyTtm => 'TTM';

  @override
  String get dividendForecastStrategyComposite => '组合';

  @override
  String get dividendForecastStrategyUnknown => '预测';

  @override
  String get commonNotAvailable => '暂无';

  @override
  String get commandKeywordCashFlowCn => '现金流';

  @override
  String get commandKeywordIncomeCn => '收入';

  @override
  String get commandKeywordDividendCn => '股息';

  @override
  String get commandKeywordSalaryCn => '工资';

  @override
  String get commandKeywordDividendCenterCn => '股息中心';

  @override
  String get commandKeywordMyDividendsCn => '我的股息';

  @override
  String get commandKeywordPassiveIncomeCn => '被动收入';

  @override
  String get commandKeywordBonusDividendCn => '分红';

  @override
  String get commandKeywordWithholdingTaxCn => '代扣税';

  @override
  String get commandKeywordCorporateActionCn => '公司行动';

  @override
  String get commandKeywordSplitCn => '拆股';

  @override
  String get commandKeywordRightsIssueCn => '配股';

  @override
  String get commandKeywordRebalanceCn => '再平衡';

  @override
  String get commandKeywordTargetAllocationCn => '目标配置';

  @override
  String get accountsHubSectionCashDeposits => '现金与存款';

  @override
  String get accountsHubSectionInvestments => '投资';

  @override
  String get accountsHubSectionPhysical => '实物资产';

  @override
  String get accountsHubSectionLiabilities => '负债';

  @override
  String get accountsHubManageBankAccounts => '管理银行账户';

  @override
  String get portfolioHubTitle => '投资组合';

  @override
  String get portfolioHubAccountsEntrySubtitle => '持仓、收益与分布视角';

  @override
  String get portfolioHubMarketValueLabel => '市值';

  @override
  String get portfolioHubYtdXirrLabel => '年初至今 XIRR';

  @override
  String get portfolioHubAbsoluteReturnLabel => '绝对收益';

  @override
  String get portfolioHubViewAccount => '账户';

  @override
  String get portfolioHubViewCurrency => '币种';

  @override
  String get portfolioHubViewAssetClass => '类别';

  @override
  String get portfolioHubHoldingsTitle => '分布';

  @override
  String get portfolioHubPositionsTitle => '持仓';

  @override
  String portfolioHubHoldingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个持仓',
      one: '1 个持仓',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubUnknownAccount => '未知账户';

  @override
  String get portfolioHubAccountGroupSubtitle => '券商账户';

  @override
  String get portfolioHubCurrencyGroupSubtitle => '结算币种';

  @override
  String get portfolioHubAssetClassGroupSubtitle => '资产类别';

  @override
  String get portfolioHubEmpty => '暂无投资持仓。';

  @override
  String portfolioHubLoadError(String error) {
    return '投资组合加载失败：$error';
  }

  @override
  String get portfolioHubAssetTypeStock => '股票';

  @override
  String get portfolioHubAssetTypeEtf => 'ETF';

  @override
  String get portfolioHubAssetTypeMutualFund => '基金';

  @override
  String get portfolioHubAssetTypeBond => '债券';

  @override
  String get portfolioHubAssetTypeCrypto => '加密资产';

  @override
  String get portfolioHubAssetTypeCash => '现金';

  @override
  String get portfolioHubAssetTypeCommodity => '商品';

  @override
  String get portfolioHubAssetTypeCustom => '其他';

  @override
  String get portfolioHubAssetTypeBankDepositTerm => '定期存款';

  @override
  String get portfolioHubAssetTypeBankDepositDemand => '活期存款';

  @override
  String get portfolioHubAssetTypeWealthProduct => '理财产品';

  @override
  String get portfolioHubEnginesTitle => '引擎视图';

  @override
  String get portfolioHubRealizedPnlTitle => '已实现盈亏';

  @override
  String portfolioHubRealizedPnlCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个批次',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubRealizedPnlEmpty => '暂无已平仓批次。';

  @override
  String portfolioHubHoldingPeriod(String period) {
    return '持有 $period';
  }

  @override
  String portfolioHubHoldingYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 年',
    );
    return '$_temp0';
  }

  @override
  String portfolioHubHoldingMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个月',
    );
    return '$_temp0';
  }

  @override
  String portfolioHubHoldingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubDividendForecastTitle => '股息预测';

  @override
  String get portfolioHubDividendForecastEmpty => '暂无预测股息。';

  @override
  String get portfolioHubDividendForecastEvent => '预计派息';

  @override
  String get portfolioHubForecastConfidenceHigh => '高置信度';

  @override
  String get portfolioHubForecastConfidenceMedium => '中置信度';

  @override
  String get portfolioHubForecastConfidenceLow => '低置信度';

  @override
  String get portfolioHubEventTimelineTitle => '事件时间线';

  @override
  String portfolioHubEventTimelineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个事件',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubEventTimelineEmpty => '暂无分红或公司行动事件。';

  @override
  String get assetDetailFxPnlTitle => '价格 vs 汇率贡献';

  @override
  String get assetDetailFxPnlMarketLeg => '价格贡献';

  @override
  String get assetDetailFxPnlCurrencyLeg => '汇率贡献';

  @override
  String get assetDetailFxPnlTotal => '本位币总盈亏';

  @override
  String assetDetailFxPnlLoadError(String error) {
    return 'FX 盈亏加载失败：$error';
  }

  @override
  String get dashboardAiInsightsTitle => 'AI 洞察';

  @override
  String get dashboardActivityPreviewTitle => '近期活动';

  @override
  String get dashboardActivityPreviewViewAll => '查看全部';

  @override
  String get dashboardAllocationSummaryTitle => '资产分配';

  @override
  String get dashboardAllocationViewBreakdown => '查看分布';

  @override
  String get homeGreetingMorning => '早上好';

  @override
  String get homeGreetingAfternoon => '下午好';

  @override
  String get homeGreetingEvening => '晚上好';

  @override
  String get homeGreetingNight => '夜深了';

  @override
  String homeGreetingNetWorthFragment(String pct) {
    return '本月净值 $pct';
  }

  @override
  String homeGreetingInsightsFragment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条洞察待查看',
    );
    return '$_temp0';
  }

  @override
  String get activityFilterChipAll => '全部';

  @override
  String get activityFilterChipIncome => '收入';

  @override
  String get activityFilterChipExpense => '支出';

  @override
  String get activityFilterChipTransfer => '转账';

  @override
  String get activityFilterChipTrade => '交易';

  @override
  String get activityEntryDetailTitle => '交易明细';

  @override
  String get activityEntryDetailAiExplanation => 'AI 洞察';

  @override
  String get activityEntryDetailNoExplanation => '暂无该笔记录的 AI 洞察。';

  @override
  String get activityEntryDetailInsightSubscription =>
      '识别为周期订阅。下次续费前可复核是否仍符合当前计划。';

  @override
  String get activityEntryDetailInsightHousing => '识别为周期居住支出。可纳入必要支出基线持续跟踪。';

  @override
  String get activityEntryDetailInsightIncome => '识别为主要收入流入。可作为现金流预测的稳定基线。';

  @override
  String get aiContextSummaryThisMonth => '本月概览';

  @override
  String aiContextSummaryNetWorthLine(String pct) {
    return '本月净值 $pct';
  }

  @override
  String aiContextSummaryUnusualLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '发现 $count 笔异常支出',
    );
    return '$_temp0';
  }

  @override
  String aiContextSummaryUpcomingLine(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔存款将在 $days 天内到期',
    );
    return '$_temp0';
  }

  @override
  String get aiActionCardsTitle => '建议操作';

  @override
  String get aiActionCardsOpen => '打开 →';

  @override
  String get aiInsightsPanelTitle => '深度洞察';

  @override
  String get aiInsightsRebalanceTitle => '再平衡';

  @override
  String get aiChatSessionActionsTitle => '会话操作';

  @override
  String get dashboardNetWorthAssetsLabel => '资产';

  @override
  String get dashboardNetWorthLiabilitiesLabel => '负债';

  @override
  String get dashboardValuationUpdating => '正在更新估值…';

  @override
  String get dashboardLedgerSyncing => '正在同步最新账本…';

  @override
  String get dashboardValuationUpdated => '估值刚刚更新';

  @override
  String get portfolioAssetsTab => '资产';

  @override
  String get portfolioLiabilitiesTab => '负债';

  @override
  String get activityActionsTitle => '记录活动';

  @override
  String get activityActionExpenseHint => '记一笔支出';

  @override
  String get activityActionTradeHint => '买入或卖出证券';

  @override
  String get activityActionTransferHint => '在两个账户间转账';

  @override
  String get activityActionConvertHint => '在同一账户内换汇';

  @override
  String get accountsActionsTitle => '添加财富容器';

  @override
  String get accountsActionAccountHint => '银行、券商或加密账户';

  @override
  String get accountsActionLiabilityHint => '房贷、车贷或信用余额';

  @override
  String get superFabTrade => '交易';

  @override
  String get superFabExpense => '记账';

  @override
  String get superFabAsset => '资产';

  @override
  String get superFabTransfer => '转账';

  @override
  String get superFabTransferSubtitle => '在两个账户之间转移资金';

  @override
  String get superFabConvert => '换汇';

  @override
  String get superFabConvertSubtitle => '在同一账户内兑换币种';

  @override
  String get superFabLiability => '负债';

  @override
  String get transferConvertModeBanner => '在同一账户内换汇 — 两侧请选同一账户并选择不同币种。';

  @override
  String get homeAppBarTitle => '总览';

  @override
  String get homeAiAssistantTooltip => 'AI 助手';

  @override
  String get homeNetWorthTitle => '净资产';

  @override
  String homeNetWorthSubtitle(String currency) {
    return '基础货币 $currency · 等数据接入后展示';
  }

  @override
  String get homePassiveIncomeTitle => '被动收入';

  @override
  String get homePassiveIncomeSubtitle => 'TTM 股息、利息与其他被动收入';

  @override
  String homePassiveIncomeSubtitleWithNextMonth(String amount) {
    return 'TTM 被动收入 · 预计下月 $amount';
  }

  @override
  String get homePassiveIncomeEmpty => '记录股息或利息后开始跟踪 TTM';

  @override
  String get homePassiveIncomeDeltaNew => '新增';

  @override
  String get homeMonthlyCashFlowTitle => '本月现金流';

  @override
  String homeMonthlyCashFlowSubtitle(String inflow, String outflow) {
    return '流入 $inflow · 流出 $outflow';
  }

  @override
  String get homeMonthlyCashFlowEmpty => '添加收入或支出后显示本月现金流';

  @override
  String homeMonthlyCashFlowBaseline(String average) {
    return '对比近 3 月均值 $average';
  }

  @override
  String get homeMonthlyCashFlowBaselineEmpty => '入账后显示近 3 月均值';

  @override
  String get homeCashFlowEmptyValue => '暂无数据';

  @override
  String get homeCashFlowCardError => '现金流汇总暂不可用';

  @override
  String get assetsAppBarTitle => '资产';

  @override
  String get assetsDetailEmpty => '请在左侧选择资产以查看详情。';

  @override
  String get assetsEmptyHint => '尚未录入资产。点击右下角添加现金、存款、理财、房产或车辆。';

  @override
  String get assetsAddAction => '录入资产';

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
  String get settingsAccountSubtitle => '登录与多端同步';

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
  String get settingsLanguageTitle => '语言';

  @override
  String get langSystem => '跟随系统';

  @override
  String get langEnglish => '英文';

  @override
  String get langChinese => '中文';

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
  String get commonLoadFailed => '加载失败，请稍后重试。';

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
  String get commandPaletteMobileEntryHint => '搜索、跳转、提问…';

  @override
  String get commandPaletteEmpty => '没有匹配的命令';

  @override
  String commandPaletteAskAi(String query) {
    return '问 AI：$query';
  }

  @override
  String get askAiResultLocalBadge => '本地处理';

  @override
  String get askAiResultNoLocalMatch => '命令栏暂无法本地解析这个问题。可去 AI 历史里继续追问。';

  @override
  String get askAiResultContinueInChat => '去 AI 历史继续追问 →';

  @override
  String get askAiResultIrreversibleBlocked => '命令栏不执行转账 / 下单 / 删除账户。请到对应页面操作。';

  @override
  String askAiResultError(String error) {
    return '查询执行失败：$error';
  }

  @override
  String get askAiResultEmpty => '没有匹配的记录。';

  @override
  String askAiResultMoreRows(int count) {
    return '还有 $count 条';
  }

  @override
  String askAiResultRowCount(int count) {
    return '$count 条';
  }

  @override
  String get askAiResultTitleSpending => '支出分类';

  @override
  String get askAiResultTitleTransactions => '交易明细';

  @override
  String get askAiResultTitleNetWorth => '净资产趋势';

  @override
  String get askAiResultTitleSubscriptions => '订阅';

  @override
  String get askAiResultTitleRefunds => '退款匹配';

  @override
  String get askAiResultTitleGeneric => '查询结果';

  @override
  String get commandPaletteGoOverview => '前往 总览';

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
  String get rebalanceExecuteAction => '按此调仓';

  @override
  String get rebalanceExecutionSheetTitle => '确认调仓';

  @override
  String rebalanceExecutionSheetSubtitle(int count) {
    return '继续前请核对 $count 笔交易草稿。';
  }

  @override
  String get rebalanceExecutionCreateDrafts => '生成草稿';

  @override
  String get rebalanceExecutionTradeValue => '建议金额';

  @override
  String rebalanceExecutionDraftNote(
    Object direction,
    Object category,
    Object amount,
    Object currency,
  ) {
    return '再平衡建议：$direction$category，金额 $amount $currency';
  }

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
  String get rebalanceCommandOpen => '前往再平衡';

  @override
  String get rebalanceCommandAdjustTarget => '调整目标配置';

  @override
  String get targetAllocationEditorTitle => '自定义目标';

  @override
  String get targetAllocationEditorSubtitle => '调整各类别权重，合计必须等于 100%。';

  @override
  String get targetAllocationEditorEditAction => '自定义目标';

  @override
  String get targetAllocationEditorTotalLabel => '合计配置';

  @override
  String targetAllocationEditorTotalHint(String value) {
    return '合计必须为 100%。当前合计：$value%。';
  }

  @override
  String get targetAllocationEditorPercentLabel => '权重';

  @override
  String get targetAllocationEditorRequiredError => '必填';

  @override
  String get targetAllocationEditorRangeError => '请输入 0–100';

  @override
  String get targetAllocationEditorPreviewTitle => '目标结构';

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
  String get aiChatEmptySuggestionsHeader => '试试这些';

  @override
  String get aiChatBootstrappingLabel => '正在准备会话…';

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
  String aiChatRunningTool(String tool) {
    return '正在 $tool';
  }

  @override
  String get aiChatStaleSyncNotice => '本地数据未完成同步，回答可能滞后于你刚刚的录入。';

  @override
  String get aiChatTruncatedMaxTokens => '回复因长度上限被截断';

  @override
  String get aiChatTruncatedToolBudget => '工具调用次数用尽，已提前结束';

  @override
  String get aiChatTruncatedRefusal => '模型拒绝回答此问题';

  @override
  String get aiChatTruncatedNetwork => '连接中断，回复未完整接收';

  @override
  String get aiChatTruncatedUnknown => '回复异常结束';

  @override
  String get aiChatTruncatedContinue => '继续';

  @override
  String get aiChatTruncatedContinuePrompt => '请继续。';

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
  String get accountCategoryCash => '现金';

  @override
  String get accountCategoryBank => '银行';

  @override
  String get accountCategoryBroker => '券商';

  @override
  String get accountCategoryCrypto => '加密钱包';

  @override
  String get accountCategoryCredit => '信用';

  @override
  String get accountCategoryLoan => '贷款';

  @override
  String get accountCategoryAsset => '其他资产';

  @override
  String get accountCategoryLiability => '其他负债';

  @override
  String get accountCategoryCashHint => '现金、电子钱包（支付宝/微信）';

  @override
  String get accountCategoryBankHint => '活期、储蓄、定期存款';

  @override
  String get accountCategoryBrokerHint => '股票、ETF、基金';

  @override
  String get accountCategoryCryptoHint => '链上钱包、交易所';

  @override
  String get accountCategoryCreditHint => '信用卡、循环信用';

  @override
  String get accountCategoryLoanHint => '房贷、车贷、学生贷';

  @override
  String get accountCategoryAssetHint => '不动产、车辆、收藏品';

  @override
  String get accountCategoryLiabilityHint => '信用 / 贷款之外的其他负债';

  @override
  String get accountSideAsset => '资产';

  @override
  String get accountSideLiability => '负债';

  @override
  String get accountSideIncome => '收入';

  @override
  String get accountSideExpense => '支出';

  @override
  String get accountSideEquity => '权益';

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
  String get cashFormDuplicateTitle => '现金已存在';

  @override
  String get cashFormDuplicateMessage => '该账户已有现金记录，是否编辑现有记录？';

  @override
  String get cashFormDuplicateCancel => '取消';

  @override
  String get cashFormDuplicateEdit => '编辑现有';

  @override
  String get manualAssetDeleteTitle => '删除资产';

  @override
  String get manualAssetDeleteContent => '确认删除该资产记录？';

  @override
  String get manualAssetDeleteCancel => '取消';

  @override
  String get manualAssetDeleteConfirm => '删除';

  @override
  String get activityFeedTab => '动态';

  @override
  String get activityFeedEmpty => '暂无动态 — 记录一笔转账、支出或交易即可在此查看。';

  @override
  String get tradeEntryCashOverdrawTitle => '现金余额将变为负数';

  @override
  String tradeEntryCashOverdrawMessage(Object amount) {
    return '此次购买后，您的现金账户余额将为 $amount。是否继续？';
  }

  @override
  String get tradeEntryCashOverdrawProceed => '继续';

  @override
  String get activityFeedToday => '今天';

  @override
  String get activityFeedYesterday => '昨天';

  @override
  String get activityFeedThisWeek => '本周';

  @override
  String get activityFeedEarlier => '更早';

  @override
  String get accountsTransferAction => '转账';

  @override
  String get accountsJournalAction => '日记账';

  @override
  String get expenseReportTitle => '支出报表';

  @override
  String get planFireTitle => 'FIRE';

  @override
  String get planFireSubtitle => '财务自由计算器';

  @override
  String get planAnalyticsTitle => '分析';

  @override
  String get planAnalyticsSubtitle => '投资组合配置分析';

  @override
  String get planRebalanceTitle => '再平衡';

  @override
  String get planRebalanceSubtitle => '投资组合偏离与再平衡';

  @override
  String get planSummaryLoadError => '需要关注';

  @override
  String get planSummaryConfigureGoal => '设置目标';

  @override
  String planSummaryProgress(String value) {
    return '进度 $value';
  }

  @override
  String planSummaryEta(String value) {
    return '预计 $value';
  }

  @override
  String get planSummaryNoRiskAlerts => '无集中度风险';

  @override
  String planSummaryRiskAlerts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条提醒',
    );
    return '$_temp0';
  }

  @override
  String planSummaryCriticalAlerts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条严重',
    );
    return '$_temp0';
  }

  @override
  String get planSummaryNoPortfolio => '暂无组合数据';

  @override
  String get planSummaryBalanced => '已平衡';

  @override
  String planSummaryDrift(String value) {
    return '偏离 $value';
  }

  @override
  String planSummaryTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔建议交易',
    );
    return '$_temp0';
  }

  @override
  String get settingsAccountSection => '账户';

  @override
  String get settingsDataSection => '数据';

  @override
  String get settingsDataTitle => '备份与恢复';

  @override
  String get settingsDataSubtitle => '导出或导入加密数据备份';

  @override
  String get settingsAiPrivacyTitle => 'AI 隐私';

  @override
  String get settingsAiPrivacySubtitle => '选择 AI 可以上传到云端的数据范围';

  @override
  String get aiPrivacyTitle => 'AI 隐私';

  @override
  String get aiPrivacyIntro => '选择 AI 离开本机时可以看到多少细节。可以随时更改。';

  @override
  String get aiPrivacyModeAmountsAllowedLabel => '金额可上行';

  @override
  String get aiPrivacyModeAmountsAllowedDescription => '上传精确金额和账户上下文，回答质量最佳。';

  @override
  String get aiPrivacyModeAmountsBucketedLabel => '金额做掩码';

  @override
  String get aiPrivacyModeAmountsBucketedDescription =>
      '金额按数量级取整后再上传。云端能看到模式但看不到具体数字。';

  @override
  String get aiPrivacyModeAmountsLocalLabel => '金额完全本地';

  @override
  String get aiPrivacyModeAmountsLocalDescription => '只把意图和分类名上传，云端只能给定性建议。';

  @override
  String get aiPrivacyMaskAccountsLabel => '脱敏账户 / 机构名';

  @override
  String get aiPrivacyMaskAccountsDescription => '把银行 / 券商等名字替换成匿名 ID 后再上传。';

  @override
  String get aiPrivacyOnboardingTitle => '选择你的 AI 隐私偏好';

  @override
  String get aiPrivacyOnboardingBody =>
      'NaviWealth 的 AI 默认本地优先。当需要走云端时，这个设置决定能上传什么。后续可在设置里改。';

  @override
  String get aiPrivacyOnboardingConfirm => '好的';

  @override
  String get aiTransparencyUndoSectionTitle => '待撤销的 AI 改动';

  @override
  String get aiTransparencyUndoEmpty => '暂无待撤销的 AI 改动。';

  @override
  String get aiTransparencyUndoAction => '撤销';

  @override
  String get settingsDeveloperSection => '开发者';

  @override
  String get settingsLogsTitle => '应用日志';

  @override
  String get settingsLogsSubtitle => '查看实时诊断日志';

  @override
  String get backupExportTitle => '导出备份';

  @override
  String get backupExportSubtitle => '创建所有数据的加密备份';

  @override
  String get backupImportTitle => '导入备份';

  @override
  String get backupImportSubtitle => '从备份文件恢复数据';

  @override
  String get backupPassphraseLabel => '密码';

  @override
  String get backupPassphraseHint => '输入密码以加密备份';

  @override
  String get backupPassphraseRequired => '请输入密码';

  @override
  String get backupConfirmRestoreTitle => '恢复备份';

  @override
  String get backupConfirmRestoreMessage => '此操作将替换所有本地数据为备份内容，且无法撤销。是否继续？';

  @override
  String get backupConfirmRestoreAction => '恢复';

  @override
  String get backupExportAction => '导出';

  @override
  String get backupCancelAction => '取消';

  @override
  String get backupExportProgress => '正在加密备份…';

  @override
  String get backupImportProgress => '正在恢复备份…';

  @override
  String get backupExportSuccess => '备份导出成功';

  @override
  String backupImportSuccess(int count) {
    return '备份恢复成功，共导入 $count 条记录。';
  }

  @override
  String get backupWrongPassphrase => '密码错误或备份文件损坏';

  @override
  String get backupSchemaTooNew => '此备份由更新版本的 NaviWealth 创建，请先更新应用。';

  @override
  String get backupInvalidFile => '无效的备份文件';

  @override
  String get backupFilePickerError => '无法读取所选文件';

  @override
  String get backupRestorePassphraseHint => '输入备份密码';

  @override
  String get logViewerClearTooltip => '清除';

  @override
  String activityFeedLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get expenseFormLoadError => '无法加载支出，请新建一条记录。';

  @override
  String get accountsJournalTooltip => '日记账';

  @override
  String get accountsTransferTooltip => '新转账';

  @override
  String get accountFormParentLabel => '父账户（可选）';

  @override
  String get accountFormParentHelper => '将此账户归入另一个账户之下。';

  @override
  String get accountFormMakeTopLevelTooltip => '设为顶级';

  @override
  String get accountFormIconHeading => '图标';

  @override
  String get accountFormNoIconTooltip => '无图标';

  @override
  String get accountFormColorHeading => '颜色';

  @override
  String get accountFormNoColorTooltip => '无颜色';

  @override
  String get transferTitle => '新转账';

  @override
  String transferLoadError(String error) {
    return '加载账户失败：$error';
  }

  @override
  String get transferFromLabel => '转出账户';

  @override
  String get transferToLabel => '转入账户';

  @override
  String get transferValidationRequired => '必填';

  @override
  String get transferValidationDifferentAccount => '请选择不同账户';

  @override
  String get transferAmountLabel => '金额';

  @override
  String transferAmountWithCurrencyLabel(String currency) {
    return '金额（$currency）';
  }

  @override
  String transferToAmountLabel(String currency) {
    return '转入金额（$currency）';
  }

  @override
  String get transferFxRateHelper => '无汇率记录 — 请手动输入折算金额。';

  @override
  String get transferFxRateEditHelper => '可编辑以覆盖自动填充的汇率。';

  @override
  String get transferDateLabel => '日期';

  @override
  String get transferPreviewTitle => '转账';

  @override
  String get transferSubmitAction => '转账';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return '汇率：1 $from = $rate $to';
  }

  @override
  String transferRejectedError(String message) {
    return '转账被拒绝：$message';
  }

  @override
  String transferFailedError(String error) {
    return '转账失败：$error';
  }

  @override
  String get transferRetryLabel => '重试';

  @override
  String get journalTitle => '日记账';

  @override
  String journalLoadError(String error) {
    return '加载日记账失败：$error';
  }

  @override
  String get journalEmptyHint => '暂无日记账记录 — 记录一笔转账、支出或交易即可在此查看。';

  @override
  String get entryKindTrade => '交易';

  @override
  String get entryKindTransfer => '转账';

  @override
  String get entryKindIncome => '收入';

  @override
  String get entryKindExpense => '支出';

  @override
  String get entryKindPayment => '还款';

  @override
  String get entryKindAdjustment => '调整';

  @override
  String get entryKindOpening => '期初';

  @override
  String get entryKindOther => '其他';

  @override
  String get entryKindEntry => '记录';

  @override
  String entryKindSemanticLabel(String kind) {
    return '日记账 · $kind';
  }

  @override
  String get chatCancelled => '已取消';

  @override
  String get chatNewSession => '新对话';

  @override
  String chatContextTruncated(int count) {
    return '已折叠 $count 条更早的历史以控制上下文长度。';
  }

  @override
  String get expenseReportAppBarTitle => '支出报表';

  @override
  String expenseReportLoadError(String error) {
    return '报表加载失败：$error';
  }

  @override
  String get expenseReportRangeThisMonth => '本月';

  @override
  String get expenseReportRangeLast3Months => '近 3 月';

  @override
  String get expenseReportRangeLast6Months => '近 6 月';

  @override
  String get expenseReportRangeLast12Months => '近 12 月';

  @override
  String get expenseReportRangeCustom => '自定义';

  @override
  String get expenseReportTotalExpenses => '总支出';

  @override
  String get expenseReportMonthlyAverage => '月均';

  @override
  String get expenseReportEntryCount => '记账数';

  @override
  String get expenseReportCategoryCount => '类目数';

  @override
  String expenseReportSkippedFx(int count) {
    return '$count 笔支出因汇率缺失未计入合计。';
  }

  @override
  String expenseReportBaseCurrency(String currency, int months) {
    return '基础货币 $currency · 月均按 $months 个月折算';
  }

  @override
  String get expenseReportCategoryShare => '类目占比';

  @override
  String get expenseReportUncategorized => '未分类';

  @override
  String get expenseReportNoExpenses => '本期没有支出记录。';

  @override
  String expenseReportMonthLabel(int month) {
    return '$month月';
  }

  @override
  String get expenseReportMonthlyTrend => '月度趋势';

  @override
  String get expenseReportSeriesExpenses => '支出';

  @override
  String get expenseReportMonthlyTrendSemantic => '月度支出趋势';

  @override
  String get expenseReportCategoryDetail => '类目明细';

  @override
  String expenseReportItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔',
    );
    return '$_temp0';
  }

  @override
  String get expenseListSearchHint => '按备注搜索';

  @override
  String get expenseListAllCategories => '全部类目';

  @override
  String get expenseListGroupMonth => '月';

  @override
  String get expenseListGroupWeek => '周';

  @override
  String expenseListTotal(String amount) {
    return '合计 $amount';
  }

  @override
  String get expenseListUncategorized => '未分类';

  @override
  String get expenseListEmptyFiltered => '没有匹配的支出。';

  @override
  String get expenseListEmptyDefault => '还没有记账。点底部加号按钮，开始追踪日常消费。';

  @override
  String expenseListMonthGroup(int year, int month) {
    return '$year 年 $month 月';
  }

  @override
  String expenseListWeekGroup(int year, int week) {
    return '$year 年第 $week 周';
  }

  @override
  String assetDetailLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get assetDetailNotFound => '资产不存在或已删除';

  @override
  String get assetDetailUnsupportedType => '该资产类型暂不支持手动编辑';

  @override
  String get assetDetailNoMetadataMatch => '未找到匹配的元数据';

  @override
  String get assetDetailMetadataSynced => '已补全元数据';

  @override
  String get assetDetailMetadataUpToDate => '元数据已是最新';

  @override
  String get assetDetailNetworkUnavailable => '网络不可用，无法同步元数据';

  @override
  String get assetDetailSyncMetadataTooltip => '同步元数据';

  @override
  String get assetDetailNewTradeLabel => '新交易';

  @override
  String get assetDetailUnknown => '未知';

  @override
  String assetDetailHoldingsLoadError(String error) {
    return '持仓加载失败：$error';
  }

  @override
  String get assetDetailHoldingsTitle => '持仓';

  @override
  String get assetDetailCurrentQuantity => '当前数量';

  @override
  String get assetDetailAverageCost => '平均成本';

  @override
  String get assetDetailCurrentMarketValue => '当前市值';

  @override
  String get assetDetailPriceUnavailable => '价格暂不可用，市值显示为零';

  @override
  String assetDetailPnLLoadError(String error) {
    return '盈亏加载失败：$error';
  }

  @override
  String get assetDetailPnLTitle => '盈亏';

  @override
  String get assetDetailUnrealizedPnL => '未实现盈亏';

  @override
  String assetDetailBaseCurrency(String currency) {
    return '基础货币：$currency';
  }

  @override
  String get assetDetailTodayChange => '今日变动';

  @override
  String get assetDetailQuoteStale => '行情滞后';

  @override
  String get assetDetailQuoteUnavailable => '行情不可用';

  @override
  String get assetDetailTrend30d => '近 30 日走势';

  @override
  String get assetDetailNoMarketLinked => '该资产暂未关联市场，无走势可显示';

  @override
  String assetDetailTrendLoadError(String error) {
    return '无法获取行情：$error';
  }

  @override
  String get assetDetailSeriesClosePrice => '收盘价';

  @override
  String get assetDetailSeriesCostBasis => '成本基准';

  @override
  String get assetDetailTrendSemanticLabel => '近 30 日收盘价走势';

  @override
  String get assetDetailStaleBadge => '行情滞后';

  @override
  String get assetDetailCategoryShareSemantic => '类目占比';

  @override
  String get depositMaturityRequired => '定期存款必须填写到期日';

  @override
  String get depositDeleteTitle => '删除存款';

  @override
  String get depositDeleteBody => '确认删除该存款记录？';

  @override
  String get depositCreateTitle => '录入存款';

  @override
  String get depositEditTitle => '编辑存款';

  @override
  String get depositDeleteTooltip => '删除';

  @override
  String get depositTypeTerm => '定期';

  @override
  String get depositTypeDemand => '活期';

  @override
  String get depositNameLabel => '名称';

  @override
  String get depositNameHelper => '例如：招行 1 年期定期、工行活期储蓄';

  @override
  String get depositNameRequired => '请输入名称';

  @override
  String get depositPrincipalLabel => '本金';

  @override
  String get depositRateLabel => '年化利率 (%)';

  @override
  String get depositRateHelper => '例如：3.25 表示 3.25%';

  @override
  String get depositRateRequired => '请输入利率';

  @override
  String get depositRateInvalid => '利率格式不正确';

  @override
  String get depositRateNegative => '利率不能为负';

  @override
  String get depositValueDateLabel => '起息日';

  @override
  String get depositMaturityDateLabel => '到期日';

  @override
  String get depositCurrentValuationLabel => '当前估值（可选）';

  @override
  String get depositCurrentValuationHelper => '不填则使用本金作为当前估值';

  @override
  String get depositAutoRenewTitle => '自动续存';

  @override
  String get depositAutoRenewSubtitle => '到期后系统提示重新登记，不会自动创建新存款';

  @override
  String get depositNoAccountHint => '请先创建一个银行账户。';

  @override
  String get depositCreateAccountAction => '新建账户';

  @override
  String get wealthProductDeleteTitle => '删除理财产品';

  @override
  String get wealthProductDeleteBody => '确认删除该理财产品记录？';

  @override
  String get wealthProductCreateTitle => '录入理财产品';

  @override
  String get wealthProductEditTitle => '编辑理财产品';

  @override
  String get wealthProductDeleteTooltip => '删除';

  @override
  String get wealthProductNoAccountHint => '请先创建银行 / 券商账户。';

  @override
  String get wealthProductCreateAccountAction => '新建账户';

  @override
  String get wealthProductNameLabel => '产品名称';

  @override
  String get wealthProductNameRequired => '请输入产品名称';

  @override
  String get wealthProductIssuerLabel => '发行机构（可选）';

  @override
  String get wealthProductCodeLabel => '产品代码（可选）';

  @override
  String get wealthProductAmountLabel => '认购金额';

  @override
  String get wealthProductExpectedReturnLabel => '预期年化收益率 (%)';

  @override
  String get wealthProductExpectedReturnHelper => '例如：4.5 表示 4.5%';

  @override
  String get wealthProductExpectedReturnRequired => '请输入预期年化';

  @override
  String get wealthProductInvalidFormat => '格式不正确';

  @override
  String get wealthProductValueDateLabel => '起息日';

  @override
  String get wealthProductMaturityDateLabel => '到期日（可选）';

  @override
  String get wealthProductValuationLabel => '当前估值（手动维护）';

  @override
  String get wealthProductValuationHelper => '不填则以认购金额作为当前估值';

  @override
  String get manualSecurityMarketCnA => 'A 股';

  @override
  String get manualSecurityMarketHk => '港股';

  @override
  String get manualSecurityMarketUs => '美股';

  @override
  String get manualSecurityMarketCrypto => '加密';

  @override
  String get manualSecurityTypeStock => '股票';

  @override
  String get manualSecurityTypeEtf => 'ETF';

  @override
  String get manualSecurityTypeMutualFund => '基金';

  @override
  String get manualSecurityTypeBond => '债券';

  @override
  String get manualSecurityTypeCrypto => '加密货币';

  @override
  String get manualSecurityEnterCodeOrName => '请先输入代码或名称';

  @override
  String get manualSecurityNetworkUnavailable => '网络不可用，请使用手动输入';

  @override
  String get manualSecurityNoMatch => '未找到匹配项，请使用手动输入';

  @override
  String get manualSecurityImported => '已从网络导入元数据';

  @override
  String get manualSecuritySelectMatchTitle => '选择匹配项';

  @override
  String get manualSecuritySheetTitle => '手动添加证券';

  @override
  String get manualSecuritySheetDescription =>
      '本地保存。点击「从网络导入」可选择性地用 Yahoo / CoinGecko 元数据补全字段。';

  @override
  String get manualSecurityCodeLabel => '代码';

  @override
  String get manualSecurityCodeRequired => '请输入代码';

  @override
  String get manualSecurityCodeNoColon => '代码不能包含 \":\"';

  @override
  String get manualSecurityImportAction => '从网络导入';

  @override
  String get manualSecurityImporting => '导入中…';

  @override
  String get manualSecurityNameLabel => '名称（可选）';

  @override
  String get manualSecurityMarketLabel => '市场';

  @override
  String get manualSecurityTypeLabel => '类型';

  @override
  String get manualSecurityIsinLabel => 'ISIN（可选）';

  @override
  String get manualSecurityAddAction => '添加';

  @override
  String get localSecuritiesSearchLabel => '资产搜索';

  @override
  String get localSecuritiesSearchHint => '输入代码、名称或拼音';

  @override
  String get localSecuritiesValidationRequired => '请选择一个资产';

  @override
  String get localSecuritiesMyAssets => '我的资产';

  @override
  String get localSecuritiesCatalog => '本地目录';

  @override
  String get localSecuritiesManualAdd => '未找到？手动添加';

  @override
  String localSecuritiesUseQueryAsCode(String query) {
    return '使用 \"$query\" 作为代码';
  }

  @override
  String get dashboardInsightFireLabel => 'FIRE';

  @override
  String dashboardInsightFireToGoYears(int years, int months) {
    return '还需 $years 年 $months 个月';
  }

  @override
  String dashboardInsightFireToGoMonths(int months) {
    return '还需 $months 个月';
  }

  @override
  String get dashboardInsightFireReached => '已达成目标';

  @override
  String get dashboardInsightDriftLabel => '组合偏离';

  @override
  String get dashboardInsightDriftOver => '超配';

  @override
  String get dashboardInsightDriftUnder => '低配';

  @override
  String dashboardInsightDriftValue(
    String category,
    String direction,
    int points,
  ) {
    return '$category $direction ${points}pp';
  }

  @override
  String get dashboardInsightMaturityLabel => '到期提醒';

  @override
  String dashboardInsightMaturityValue(int count, int days) {
    return '$count 笔定期 ${days}d 内到期';
  }

  @override
  String get dashboardInsightAnomalyLabel => '支出趋势';

  @override
  String dashboardInsightAnomalyValue(String percent) {
    return '预计 $percent';
  }

  @override
  String get dashboardInsightDuplicateChargeLabel => '疑似重复扣款';

  @override
  String dashboardInsightDuplicateChargeValue(int count, String amount) {
    return '$count 组，共 $amount';
  }

  @override
  String get dashboardInsightMonthlySummaryLabel => '上月回顾';

  @override
  String dashboardInsightMonthlySummaryUp(String amount) {
    return '净资产 +$amount';
  }

  @override
  String dashboardInsightMonthlySummaryDown(String amount) {
    return '净资产 -$amount';
  }

  @override
  String get dashboardInsightMonthlySummaryFlat => '净资产基本持平';

  @override
  String get dashboardInsightActionExpand => '展开';

  @override
  String get dashboardInsightActionAsk => '问一下';

  @override
  String get dashboardInsightActionDismiss => '忽略';

  @override
  String get portfolioViewAssets => '资产';

  @override
  String get portfolioViewAccount => '账户';

  @override
  String get portfolioViewCurrency => '币种';

  @override
  String get portfolioViewClass => '类别';

  @override
  String portfolioAggregateItems(int count) {
    return '$count 项';
  }

  @override
  String portfolioCurrencyNative(String amount) {
    return '原币 $amount';
  }

  @override
  String get portfolioUnassignedAccount => '未分配';

  @override
  String get activityAddAction => '添加';

  @override
  String get activityFeedFilterTitle => '筛选';

  @override
  String get activityFeedFilterClear => '清除';

  @override
  String get activityFeedFilterKind => '类型';

  @override
  String get activityFeedFilterAccount => '账户';

  @override
  String get activityFeedFilterAccountEmpty => '还没有账户 — 请到「账户」标签创建。';

  @override
  String get activityFeedFilterDateRange => '日期范围';

  @override
  String get activityFeedFilterRangeThisWeek => '本周';

  @override
  String get activityFeedFilterRangeThisMonth => '本月';

  @override
  String get activityFeedFilterRangeLastMonth => '上月';

  @override
  String get activityFeedFilterRangeThisYear => '今年';

  @override
  String get activityFeedFilterRangeCustom => '自定义…';

  @override
  String get activityFeedFilterThisMonth => '本月';

  @override
  String get activityFeedFilteredEmpty => '没有符合筛选条件的动态。';

  @override
  String get activityFeedLoadMore => '加载更多';

  @override
  String get activityFeedAllLoaded => '已加载全部动态';

  @override
  String get backupWebSecurityWarning =>
      'Web 端本地数据库未启用 SQLCipher。备份文件会使用你的密码加密；不建议在 Web 端长期保存敏感账户。';

  @override
  String get formSaving => '保存中…';

  @override
  String get formSave => '保存';

  @override
  String get settingsSyncTitle => '同步';

  @override
  String get settingsSyncSubtitle => '查看同步状态与最近活动';

  @override
  String get syncStatusTitle => '同步状态';

  @override
  String get syncStatusRefreshNow => '立即同步';

  @override
  String syncStatusBusError(String error) {
    return '无法读取同步状态：$error';
  }

  @override
  String get syncStatusHeadlineIdle => '尚未同步';

  @override
  String get syncStatusHeadlineSyncing => '同步中…';

  @override
  String get syncStatusHeadlineOnline => '已全部同步';

  @override
  String get syncStatusHeadlineOffline => '网络离线';

  @override
  String get syncStatusHeadlineFailed => '同步失败';

  @override
  String get syncStatusSubtitleNeverSynced => '本设备尚未成功同步过';

  @override
  String syncStatusSubtitleLastSynced(String when) {
    return '上次同步：$when';
  }

  @override
  String get syncStatusJustNow => '刚刚';

  @override
  String syncStatusMinutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String syncStatusHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String syncStatusDaysAgo(int n) {
    return '$n 天前';
  }

  @override
  String get syncStatusPendingHeader => '待同步变更';

  @override
  String get syncStatusPendingLoading => '统计中…';

  @override
  String get syncStatusPendingNone => '已是最新';

  @override
  String syncStatusPendingCount(int n) {
    return '$n 条变更待推送';
  }

  @override
  String get syncStatusPendingCaption => '等待下次推送到服务器';

  @override
  String get syncStatusPendingCaptionEmpty => '所有本地变更已推送至服务器';

  @override
  String get syncStatusActionSyncNow => '立即同步';

  @override
  String get syncStatusErrorHeader => '上次错误';

  @override
  String get syncStatusDetailsHeader => '详情';

  @override
  String get syncStatusDetailState => '状态';

  @override
  String get syncStatusDetailUpdatedAt => '更新于';

  @override
  String get syncStatusDetailDevice => '设备';

  @override
  String get syncStatusDetailCursor => '拉取游标';

  @override
  String get syncStatusDetailCursorUnset => '未设置';

  @override
  String get syncStatusDetailEndpoint => '服务端地址';

  @override
  String get syncStatusLocalCountsHeader => '本地行数（调试）';

  @override
  String get syncStatusLocalAccountsUser => '账户（用户）';

  @override
  String get syncStatusLocalAccountsSystem => '账户（系统）';

  @override
  String get syncStatusLocalJournalEntries => '凭证条目';

  @override
  String get syncStatusLocalPostings => '凭证分录';

  @override
  String get syncStatusLocalAssets => '资产';

  @override
  String get syncStatusLocalPrices => '价格';

  @override
  String get syncStatusLocalLiabilities => '负债';

  @override
  String get syncStatusLocalTags => '标签';

  @override
  String get syncStatusHeroSyncing => '正在同步…';

  @override
  String get syncStatusStatPending => '待推送';

  @override
  String get syncStatusStatLocal => '本地行';

  @override
  String get syncStatusStatLastSync => '上次同步';

  @override
  String get syncStatusStatNever => '尚未';

  @override
  String get syncStatusStatJustNow => '刚刚';

  @override
  String get aiReplyChipCompareLastPeriod => '对比上一周期';

  @override
  String get aiReplyChipFindKeyDrivers => '找出主要驱动';

  @override
  String get aiReplyChipHowControlSpending => '如何控制支出';

  @override
  String get aiReplyChipViewHoldings => '看持仓明细';

  @override
  String get aiReplyChipComputeXirr => '计算 XIRR';

  @override
  String get aiReplyChipCompareLastMonth => '对比上月';

  @override
  String get aiReplyChipMarketDrop20 => '如果市场下跌 20%?';

  @override
  String get aiReplyChipMonthlySaveDelta => '需要每月多存多少?';

  @override
  String get aiReplyChipRebalanceAdvice => '调整资产配置建议';

  @override
  String get aiReplyChipCompareAnotherPeriod => '再对比一个时段';

  @override
  String get aiReplyChipBiggestCategoryChange => '哪些类目变化最大';

  @override
  String get aiReplyChipTrendSummary => '给出趋势小结';

  @override
  String get aiReplyChipHandleInsight => '如何处理这条洞察?';

  @override
  String get aiReplyChipSimilarHistory => '看历史相似情况';

  @override
  String get aiReplyChipActionPlan => '给我具体行动方案';

  @override
  String get aiReplyChipRiskConcentration => '风险集中度评估';

  @override
  String get aiReplyChipUnusedSubscriptions => '哪些订阅没在用';

  @override
  String get aiReplyChipCancelPriciestSub => '取消最贵的订阅?';

  @override
  String get aiReplyChipUnmatchedRefunds => '未匹配的退款';

  @override
  String get aiReplyChipCompareBenchmark => '与基准对比';

  @override
  String get aiReplyChipForecast12mo => '未来 12 月预测';

  @override
  String get aiReplyChipExpandDetails => '展开细节';

  @override
  String get aiReplyChipActionPlanGeneric => '给出行动方案';

  @override
  String get aiReplyChipVsLastMonth => '与上月对比';

  @override
  String get aiCapsuleExpandFallback => '展开';

  @override
  String get dashboardInsightIngestQueueLabel => '录入待确认';

  @override
  String dashboardInsightIngestQueueValue(int count, int fresh) {
    return '解析 $count 条 · $fresh 条可入账';
  }

  @override
  String get dashboardInsightCashFlowDeficitLabel => '现金流缺口';

  @override
  String dashboardInsightCashFlowDeficitValue(String amount) {
    return '本月缺口 $amount';
  }

  @override
  String get ingestReviewTitle => '录入待确认';

  @override
  String ingestAccountsLoadError(String error) {
    return '账户加载失败：$error';
  }

  @override
  String ingestQueueLoadError(String error) {
    return '待确认队列加载失败：$error';
  }

  @override
  String get ingestExpenseAccountLabel => '支出账户';

  @override
  String ingestConfirmAllFresh(int count) {
    return '全部确认 · 仅新增（$count）';
  }

  @override
  String get ingestSelectAccountFirst => '请先选择支出账户';

  @override
  String get ingestServiceNotReady => '服务尚未就绪';

  @override
  String get ingestRecorded => '已记录';

  @override
  String ingestRecordedN(int count) {
    return '已记录 $count 笔';
  }

  @override
  String get ingestPasteTitle => '粘贴账单文本';

  @override
  String get ingestPasteHint => '粘贴 CSV / 账单文本\n例如：2026-05-10,星巴克,-38.00,CNY';

  @override
  String get ingestParseAction => '解析';

  @override
  String get ingestNoTransactions => '未解析出可识别的交易';

  @override
  String ingestParseSummary(int total, int fresh, int dup) {
    return '解析 $total 笔（新增 $fresh · 疑似重复 $dup）';
  }

  @override
  String get ingestUncategorized => '未分类';

  @override
  String get ingestSkip => '跳过';

  @override
  String get ingestConfirm => '记录';

  @override
  String get ingestVerdictNew => '新增';

  @override
  String get ingestVerdictLikely => '疑似重复';

  @override
  String get ingestVerdictDuplicate => '重复';

  @override
  String get ingestEmptyTitle => '没有待确认的记录';

  @override
  String get ingestEmptyBody => '粘贴账单 / CSV 文本，自动解析为草稿，\n去重对账后在这里确认入账。';

  @override
  String get ingestPasteAction => '粘贴文本';

  @override
  String get ingestImportFileAction => '导入文件';

  @override
  String get ingestCameraAction => '拍照';

  @override
  String get settingsAiTransparencyTitle => 'AI 透明度';

  @override
  String get settingsAiTransparencySubtitle => '查看最近 AI 调用的详细轨迹';

  @override
  String get settingsAiLlmTitle => '端侧 AI · 自带 Key';

  @override
  String get settingsAiLlmSubtitle => '管理多个 Provider Key，一键切换本机直连';

  @override
  String get aiLlmMissingApiKey => '请先填入 API Key';

  @override
  String get aiLlmSaved => '已保存到设备安全存储';

  @override
  String get aiLlmSwitched => '已切换';

  @override
  String get aiLlmRemoved => '已从设备移除';

  @override
  String get aiLlmEmpty => '还没有 Provider。添加一个 API Key 即可让 AI 在本机直连运行。';

  @override
  String get aiLlmAddProvider => '添加 Provider';

  @override
  String get aiLlmEditProvider => '编辑 Provider';

  @override
  String get aiLlmActiveTag => '使用中';

  @override
  String get aiLlmTapToSwitch => '点按切换';

  @override
  String get aiLlmNameLabel => '名称（可选）';

  @override
  String get aiLlmNameHint => 'Anthropic 官方 / 公司网关 …';

  @override
  String get aiLlmProviderLabel => '提供商';

  @override
  String get aiLlmStoredKeyHint => '已配置 · 留空则保持不变';

  @override
  String get aiLlmBaseUrlLabel => '自定义 Base URL（可选）';

  @override
  String get aiLlmModelLabel => '模型（可选，留空用默认）';

  @override
  String get aiLlmTestConnectivity => '测试连通性';

  @override
  String get aiLlmTesting => '测试中…';

  @override
  String get aiLlmSaving => '保存中…';

  @override
  String get aiLlmIntro =>
      '使用你自己的 LLM API Key，让 AI 在本机直连提供商运行。可保存多个 Provider 并随时切换。Key 仅存于本设备安全存储（Keychain/Keystore），不会上传、不进云同步、不进备份。费用与限流由你的提供商账户承担。';

  @override
  String get aiLlmUnsupportedTitle => '当前平台不支持端侧直连';

  @override
  String get aiLlmUnsupportedBody =>
      '自带 Key 的端侧 AI 在原生平台（iOS / Android / macOS / Windows / Linux）可用（需要系统级安全存储）。Web 继续使用云端 AI。';

  @override
  String aiLlmStatusActive(String name) {
    return '使用中：$name · 本机直连运行';
  }

  @override
  String get aiLlmStatusSavedNoActive => '已保存 Provider，但未选择可用项';

  @override
  String get aiLlmStatusReadFailed => '读取安全存储失败';

  @override
  String get aiLlmStatusNotConfigured => '未配置 · 当前无可用端侧 AI';

  @override
  String aiLlmAnthropicProtocol(String provider) {
    return '$provider（Anthropic Messages 协议）';
  }

  @override
  String aiLlmOpenAiProtocol(String provider) {
    return '$provider（Chat Completions 协议）';
  }

  @override
  String get aiTransparencyFilteredEmpty => '当前筛选下没有记录';

  @override
  String aiTransparencyLoadError(String error) {
    return '加载失败: $error';
  }

  @override
  String get aiTransparencyVerboseTitle => '详细采集';

  @override
  String get aiTransparencyVerboseSubtitle => '记录每步传参与返回（仅本机，30 天后清理）';

  @override
  String get aiTransparencyToggleOn => '开';

  @override
  String get aiTransparencyToggleOff => '关';

  @override
  String aiTransparencyRecentCalls(int count) {
    return '最近 $count 次调用';
  }

  @override
  String aiTransparencyErrors(int count) {
    return '错误 $count';
  }

  @override
  String get aiTransparencyEmpty => '暂无 AI 调用记录。\n下次发起对话后，会在此处看到完整轨迹。';

  @override
  String aiTransparencyToolsCount(int count) {
    return '工具 $count';
  }

  @override
  String aiTransparencyStaleCount(int count) {
    return '过期 x$count';
  }

  @override
  String get aiTransparencyUnnamedTurn => '(未命名调用)';

  @override
  String get aiTransparencyDetailTitle => '调用链路';

  @override
  String get aiTransparencyTraceNotFound => '未找到该次调用记录';

  @override
  String get aiTransparencyNoSpans => '该记录无执行链路（早于 span 模型，将在 30 天内自动清理）。';

  @override
  String aiTransparencyEventSummary(int count, String time) {
    return '$count 个事件 · 始于 $time';
  }

  @override
  String aiTraceRoundsCount(int count) {
    return '$count 轮';
  }

  @override
  String get aiTraceNoPayloadCaptured =>
      '未采集 input/output（精简模式）。在「AI 透明度」页打开“详细采集”后，新的调用会记录每步的传参与返回，便于调试。';

  @override
  String get aiChatDeviceUnavailable =>
      'AI 需要在设置中配置自带 API Key 后启用（本机直连模型，请求与数据不经我方服务器）。Web 端暂不支持设备侧 AI。';

  @override
  String get expenseFormAiTimeframeRecent90Days => '最近 90 天';

  @override
  String get unsavedChangesTitle => '放弃更改？';

  @override
  String get unsavedChangesBody => '如果现在离开，您的修改将不会保存。';

  @override
  String get unsavedChangesDiscard => '放弃';

  @override
  String get unsavedChangesKeepEditing => '继续编辑';

  @override
  String get pressBackAgainToExit => '再按一次返回退出';

  @override
  String get masterDetailBackToList => '返回列表';
}
