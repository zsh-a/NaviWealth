// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String commonSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get rebalanceExecutionResumeInterruptedAction => '继续中断的操作';

  @override
  String get appTitle => 'NaviWealth';

  @override
  String get navHome => '今日';

  @override
  String get navToday => '今日';

  @override
  String get navExpenses => '支出';

  @override
  String get navSettings => '设置';

  @override
  String get navActivity => '流水';

  @override
  String get navAccounts => '资产';

  @override
  String get navWealth => '资产';

  @override
  String get navPlan => '规划';

  @override
  String get navSearch => '搜索';

  @override
  String get navSettingsTooltip => '设置';

  @override
  String get shellSwitchDomainTitle => '切换域';

  @override
  String get shellExpandSidebarShortcut => '展开侧边栏  (⌘B)';

  @override
  String get shellCollapseSidebarShortcut => '收起侧边栏  (⌘B)';

  @override
  String get planHubTitle => '规划';

  @override
  String get planHubSubtitle => '决策、模型与目标。';

  @override
  String get planCoreSectionTitle => '下一步';

  @override
  String get planCoreSectionSubtitle => '用清晰的行动持续推进计划';

  @override
  String get planStrategyToolsSectionTitle => '策略';

  @override
  String get planStrategyToolsSectionSubtitle => '探索可选的投资方法';

  @override
  String get planFireSectionTitle => 'FIRE';

  @override
  String get planFireSectionSubtitle => '距离财务自由还有几年';

  @override
  String get planRebalanceSectionTitle => '再平衡';

  @override
  String get planRebalanceSectionSubtitle => '偏离目标配置情况';

  @override
  String get planIncomeSectionTitle => '收入策略';

  @override
  String get planIncomeSectionSubtitle => '备兑认购与现金担保认沽';

  @override
  String get planDcaSectionTitle => 'DCA 模拟';

  @override
  String get planDcaSectionSubtitle => '定投计划';

  @override
  String get planBudgetSectionTitle => '预算';

  @override
  String get planBudgetSectionSubtitle => '按月按类别设定上限';

  @override
  String get planBudgetTitle => '预算';

  @override
  String get planBudgetEmptyTitle => '暂无预算';

  @override
  String get planBudgetEmptyBody => '为任意类别设定月度上限，本页会显示实际花销与上限的对比。';

  @override
  String planBudgetMonthHeader(String month) {
    return '$month 预算';
  }

  @override
  String get planBudgetTotalLabel => '月度预算合计';

  @override
  String planBudgetSpentOf(String spent, String budgeted, String currency) {
    return '已花 $spent / $budgeted $currency';
  }

  @override
  String planBudgetRemaining(String amount, String currency) {
    return '剩余 $amount $currency';
  }

  @override
  String planBudgetOverBy(String amount, String currency) {
    return '超出 $amount $currency';
  }

  @override
  String get planBudgetEditTitle => '编辑预算';

  @override
  String planBudgetAmountLabel(String currency) {
    return '金额（$currency）';
  }

  @override
  String get planBudgetNoteLabel => '备注';

  @override
  String get planBudgetInvalidAmount => '请输入非负金额。';

  @override
  String planBudgetSaveFailed(String error) {
    return '保存预算失败：$error';
  }

  @override
  String get planWheelSectionTitle => 'Wheel 周期';

  @override
  String get planWheelSectionSubtitle => '卖 put + 备兑 call 复盘';

  @override
  String get planWheelTitle => 'Wheel 周期';

  @override
  String get planWheelEmptyTitle => '暂无进行中的周期';

  @override
  String get planWheelEmptyBody => '录入一次卖 put 或备兑 call 交易后，周期会显示在这里。';

  @override
  String get investmentEventTimelineTitle => '即将到来的事件';

  @override
  String get investmentEventTimelineEmpty => '未来 90 天内没有分红或拆股事件。';

  @override
  String get investmentEventTimelineError => '无法加载即将到来的事件。';

  @override
  String get investmentEventDividend => '分红';

  @override
  String investmentEventSplit(String ratio) {
    return '拆股 $ratio';
  }

  @override
  String get investmentEventRights => '配股';

  @override
  String get investmentEventDrip => 'DRIP 红利再投';

  @override
  String get planHeroEmpty => '完成 FIRE 设置后，进度会显示在这里。';

  @override
  String get planHeroConfigure => '设置计划';

  @override
  String planHeroYearsToFire(String years) {
    return '距离 FIRE 还有 $years 年';
  }

  @override
  String get planHeroProgressLabel => '进度';

  @override
  String get planHeroNextRebalance => '下一步：复盘再平衡';

  @override
  String get planHeroSeePlan => '查看规划';

  @override
  String get wealthHubTitle => '资产';

  @override
  String get wealthHubSubtitle => '你拥有什么，欠了什么。';

  @override
  String get wealthEmptyTitle => '从一个账户开始';

  @override
  String get wealthEmptyBody => '先添加资金所在的账户，再按需记录持仓和负债。';

  @override
  String get wealthEmptyAction => '添加账户';

  @override
  String get wealthAccountsSectionTitle => '账户';

  @override
  String get wealthAccountsSectionSubtitle => '现金、银行、券商、加密';

  @override
  String get wealthHoldingsSectionTitle => '持仓';

  @override
  String get wealthHoldingsSectionSubtitle => '所有账户的持仓汇总';

  @override
  String get wealthDividendSectionSubtitle => '预测、到账记录与预扣税';

  @override
  String get wealthWatchlistSectionTitle => '自选';

  @override
  String get wealthWatchlistSectionSubtitle => '你在跟踪的标的';

  @override
  String get wealthLiabilitiesSectionTitle => '负债';

  @override
  String get wealthLiabilitiesSectionSubtitle => '贷款、按揭、信用';

  @override
  String get wealthTrendTitle => '资产趋势';

  @override
  String get wealthTrendFlatHint => '所选区间内暂无变化。';

  @override
  String get wealthTrendEstimatedDisclosure => '缺少市场价格，当前按成本估算；暂不提供区间变化。';

  @override
  String get wealthTrendExcludedDisclosure => '趋势及区间变化已排除较早的不完整或估算数据。';

  @override
  String get wealthTrendIncompleteDisclosure => '当前估值数据不完整，因此不会绘制部分资产合计。';

  @override
  String get wealthPerspectiveSectionTitle => '资产分布';

  @override
  String get wealthPerspectiveByCategory => '按类别';

  @override
  String get wealthPerspectiveByCurrency => '按币种';

  @override
  String wealthPerspectiveItemCount(int count) {
    return '$count项';
  }

  @override
  String get wealthPerspectiveEmpty => '暂无资产。可从财富页右上角的「+」添加资产后查看分布。';

  @override
  String get cashFlowTitle => '现金流';

  @override
  String get cashFlowCommandOpen => '打开现金流';

  @override
  String get cashFlowCommandViewIncome => '查看收入流水';

  @override
  String get cashFlowPeriodMonth => '按月';

  @override
  String get cashFlowPeriodQuarter => '按季';

  @override
  String get cashFlowPeriodYear => '按年';

  @override
  String get cashFlowPreviousPeriod => '上一周期';

  @override
  String get cashFlowNextPeriod => '下一周期';

  @override
  String cashFlowAnchorQuarter(int year, int quarter) {
    return '$year 年第 $quarter 季度';
  }

  @override
  String cashFlowFxIncomplete(int count, String currencies) {
    return '因缺少 $currencies 汇率，已有 $count 笔现金流未计入。';
  }

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
  String get cashFlowCategoryExpenses => '支出分类';

  @override
  String get cashFlowCategoryIncome => '收入来源';

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
  String get recurringFilterActive => '进行中';

  @override
  String get recurringFilterPaused => '已暂停';

  @override
  String get recurringPausedEmptyTitle => '暂无已暂停规则';

  @override
  String get recurringPausedEmptyBody => '暂停或已结束的规则会保留在这里。';

  @override
  String get recurringPausedBadge => '已暂停';

  @override
  String get recurringCompletedBadge => '已结束';

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
  String get recurringActionEnable => '恢复';

  @override
  String get recurringActionEnableHint => '重新开始生成记录';

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
  String get recurringEnabled => '规则已恢复';

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
  String get recurringFormDetailsTitle => '更多选项';

  @override
  String get recurringFormDetailsSummary => '间隔、结束日期与备注';

  @override
  String get recurringFormDetailsConfigured => '已设置自定义选项';

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
  String get recurringValidationUntilBeforeStart => '结束日期必须至少包含一次计划发生日';

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
  String get dividendCenterGross => '税前';

  @override
  String get dividendCenterWithholding => '税额';

  @override
  String dividendCenterHistoryShowAll(int count) {
    return '查看全部 $count 个月';
  }

  @override
  String get dividendCenterHistoryShowLess => '仅看近期';

  @override
  String get dividendCenterRankingShare => '占比';

  @override
  String get dividendCenterRankingYieldOnCost => '成本收益率';

  @override
  String get dividendCenterRankingWithholding => '税额';

  @override
  String get dividendCenterForecastTitle => '未来 12 个月';

  @override
  String get dividendCenterForecastUnavailable => '历史记录或已宣告派息不足，暂无法预测。';

  @override
  String dividendCenterForecastFxIncomplete(String currencies) {
    return '缺少 $currencies 汇率';
  }

  @override
  String dividendCenterFxIncomplete(int count, String currencies) {
    return '因缺少 $currencies 汇率，已有 $count 笔股息未计入。';
  }

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
  String get portfolioHubCostBasisLabel => '持仓成本';

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
  String get portfolioHubShowAllPositions => '查看全部持仓';

  @override
  String get portfolioHubShowFewerPositions => '收起持仓';

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
  String get portfolioHubEnginesTitle => '洞察';

  @override
  String get portfolioHubSectionPositions => '持仓';

  @override
  String get portfolioHubSectionAllocation => '分布';

  @override
  String get portfolioHubSectionInsights => '洞察';

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
  String get dcaSimulatorTitle => '定投模拟器';

  @override
  String get dcaSimulatorAccountsEntrySubtitle => '用月度缓存价格回测定期买入';

  @override
  String get dcaSimulatorSymbolField => '标的或篮子';

  @override
  String get dcaSimulatorSymbolHint => 'VOO 或 VOO, QQQ';

  @override
  String get dcaSimulatorAmountField => '金额';

  @override
  String get dcaSimulatorCurrencyField => '币种';

  @override
  String get dcaSimulatorMarketField => '市场';

  @override
  String get dcaSimulatorMarketUs => '美股';

  @override
  String get dcaSimulatorMarketHk => '港股';

  @override
  String get dcaSimulatorMarketCn => 'A 股';

  @override
  String get dcaSimulatorMarketCrypto => '加密资产';

  @override
  String get dcaSimulatorFrequencyField => '频率';

  @override
  String get dcaSimulatorFrequencyMonthly => '每月';

  @override
  String get dcaSimulatorFrequencyQuarterly => '每季度';

  @override
  String get dcaSimulatorWindowField => '窗口';

  @override
  String get dcaSimulatorWindow1y => '1 年';

  @override
  String get dcaSimulatorWindow3y => '3 年';

  @override
  String get dcaSimulatorWindow5y => '5 年';

  @override
  String get dcaSimulatorRunAction => '运行模拟';

  @override
  String get dcaSimulatorDraftAction => '生成下一笔买入草稿';

  @override
  String get dcaSimulatorFreshnessLive => '实时';

  @override
  String get dcaSimulatorFreshnessCache => '缓存';

  @override
  String get dcaSimulatorFreshnessStale => '延迟';

  @override
  String get dcaSimulatorResultTitle => '回测结果';

  @override
  String get dcaSimulatorTotalInvested => '投入';

  @override
  String get dcaSimulatorEndingValue => '期末价值';

  @override
  String get dcaSimulatorCumulativeReturn => '累计收益';

  @override
  String get dcaSimulatorAverageCost => '平均成本';

  @override
  String get dcaSimulatorMaxDrawdown => '最大回撤';

  @override
  String get dcaSimulatorChartTitle => '组合价值';

  @override
  String get dcaSimulatorChartSeries => '定投价值';

  @override
  String get dcaSimulatorEmpty => '该窗口内没有匹配的月度市场数据。';

  @override
  String get dcaSimulatorInvalidSymbols => '至少输入一个标的。';

  @override
  String get dcaSimulatorInvalidAmount => '请输入正数金额。';

  @override
  String get dcaSimulatorInvalidCurrency => '请输入币种代码。';

  @override
  String dcaSimulatorLoadError(String error) {
    return '定投模拟失败：$error';
  }

  @override
  String dcaSimulatorDraftNote(String symbol, String amount, String currency) {
    return '定投计划：买入 $symbol，金额 $amount $currency';
  }

  @override
  String dcaSimulatorPositionAverageCost(String currency, String averageCost) {
    return '$currency $averageCost 平均成本';
  }

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
  String get dashboardActivityPreviewTitle => '近期活动';

  @override
  String get dashboardActivityPreviewViewAll => '查看全部';

  @override
  String get homeGreetingMorning => '早上好';

  @override
  String get homeGreetingAfternoon => '下午好';

  @override
  String get homeGreetingEvening => '晚上好';

  @override
  String get homeGreetingNight => '夜深了';

  @override
  String get homeTodayBriefSubtitle => '这是你今天的财务简报';

  @override
  String get lifeBriefSubtitle => '跨域信号与工作区入口';

  @override
  String get lifeStageTitle => 'LifeOS';

  @override
  String get lifeHeroMetricAttention => '需关注';

  @override
  String get lifeHeroMetricSignals => '信号';

  @override
  String get lifeHeroMetricClear => '平稳';

  @override
  String get lifeHeroHeadlineCalm => '各域状态平稳';

  @override
  String lifeHeroHeadlineSignals(int count) {
    return '$count 条信号待看';
  }

  @override
  String lifeHeroHeadlineAttention(int count) {
    return '$count 条需要关注';
  }

  @override
  String lifeHeroBody(int count) {
    return '$count 个工作区 · 只汇总信号，不是第二本流水';
  }

  @override
  String lifeStickyAttention(int count) {
    return '$count 需关注';
  }

  @override
  String lifeStickySignals(int count) {
    return '$count 信号';
  }

  @override
  String get lifeStickyCalm => '各域平稳';

  @override
  String get lifeWorkbenchTitle => '工作区';

  @override
  String get lifeTimelineTitle => '关注';

  @override
  String get lifeTimelinePriorityTitle => '优先';

  @override
  String get lifeTimelineEmptyTitle => '今天很安静';

  @override
  String get lifeTimelineEmpty => '暂无跨域信号。需要时再进工作区深挖。';

  @override
  String lifeTimelineShowMore(int count) {
    return '还有 $count 条';
  }

  @override
  String get lifeTimelineShowLess => '收起';

  @override
  String get lifeDomainFinance => '财务';

  @override
  String get lifeDomainHealth => '健康';

  @override
  String get lifeDomainKnowledge => '知识';

  @override
  String get lifeDomainExecution => '执行';

  @override
  String get lifeNavLabel => 'Life';

  @override
  String lifeSignalFinanceDayTitle(String count) {
    return '今日 · $count 笔';
  }

  @override
  String lifeSignalFinanceDaySubtitle(String expense, String income) {
    return '支出 $expense · 收入 $income · 打开流水';
  }

  @override
  String get lifeSignalFinanceBudgetStrainedTitle => '本月预算需要关注';

  @override
  String get lifeSignalFinanceBudgetOverTitle => '本月预算已超支';

  @override
  String lifeSignalFinanceBudgetSubtitle(String periodMonth) {
    return '$periodMonth 支出状态 · 打开预算';
  }

  @override
  String get lifeSignalRecoveryTitle => '恢复需要关照';

  @override
  String get lifeSignalRecoverySubtitle => '打开健康简报';

  @override
  String lifeSignalExecBlockedTitle(String count) {
    return '$count 个受阻行动';
  }

  @override
  String get lifeSignalExecBlockedSubtitle => '打开执行今日';

  @override
  String lifeSignalExecDueTitle(String count) {
    return '$count 个到期行动';
  }

  @override
  String get lifeSignalExecDueSubtitle => '打开执行今日';

  @override
  String lifeSignalKnowledgeTitle(String count) {
    return '收件箱 $count 条笔记';
  }

  @override
  String get lifeSignalKnowledgeSubtitle => '在知识域复盘或捕获';

  @override
  String get lifeSignalAgentTitle => '有新的 Agent 洞察';

  @override
  String get lifeSignalAgentSubtitle => '打开财务简报';

  @override
  String get lifeSignalDetailTitle => '信号详情';

  @override
  String get lifeSignalEvidenceTitle => '本地证据';

  @override
  String lifeSignalRecoveryScoreEvidence(String score) {
    return '恢复分数：$score';
  }

  @override
  String get lifeSignalCreateAction => '创建行动';

  @override
  String get lifeSignalEnableExecution => '启用 ExecutionOS';

  @override
  String get lifeSignalOpenSource => '打开来源';

  @override
  String get lifeSignalActionConfirmTitle => '创建这条行动？';

  @override
  String lifeSignalActionConfirmBody(String title, String source) {
    return '$title\n\n来源：$source';
  }

  @override
  String get lifeSignalActionCreated => '行动已创建，并保留了来源证据。';

  @override
  String lifeSignalActionFailed(String error) {
    return '无法创建行动：$error';
  }

  @override
  String executionOutcomeSignalCleared(String source) {
    return '$source：当前未再检测到信号';
  }

  @override
  String executionOutcomeSignalStillActive(String source) {
    return '$source：当前仍检测到信号';
  }

  @override
  String get lifeSignalOpenExecution => '打开执行域';

  @override
  String get lifeSignalActionReviewFinance => '复核今日财务流水';

  @override
  String get lifeSignalActionReviewBudget => '复核本月预算';

  @override
  String get lifeSignalActionProtectRecovery => '今天优先保护恢复';

  @override
  String get lifeSignalActionReviewKnowledge => '整理知识收件箱';

  @override
  String get lifeSignalActionReviewAgent => '复核最新财务洞察';

  @override
  String lifeSignalActionNote(String source, String detail) {
    return '来自「$source」：$detail';
  }

  @override
  String get financeAgentResultsLoading => '正在检查 agent 结果';

  @override
  String get financeAgentResultsLoadingBody => '正在加载近期 FinanceOS 复盘。';

  @override
  String get financeAgentResultsEmptyTitle => '暂无 agent 结果';

  @override
  String get financeAgentResultsEmptyBody => '计划复盘有可展示结果时会出现在这里。';

  @override
  String get financeAgentResultsErrorTitle => '无法加载 agent 结果';

  @override
  String financeAgentResultsErrorBody(String error) {
    return '$error';
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
  String get activityEntryDetailAiExplanation => '记录洞察';

  @override
  String get activityEntryDetailNoExplanation => '暂无该笔记录的洞察。';

  @override
  String activityEntryDetailLegCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 行',
    );
    return '$_temp0';
  }

  @override
  String get activityEntryDetailLedgerTitle => '完整分录';

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
  String get accountsActionsTitle => '添加资产项目';

  @override
  String get wealthActionPanelSubtitle => '选择要纳入净资产的对象。';

  @override
  String get wealthActionPanelAccountsGroup => '账户容器';

  @override
  String get wealthActionPanelFinancialGroup => '存款与理财';

  @override
  String get wealthActionPanelPhysicalGroup => '实物资产';

  @override
  String get wealthActionPanelLiabilitiesGroup => '负债';

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
  String get transferConvertModeBanner => '请选择两个不同币种的账户，并确认转出与转入金额。';

  @override
  String get homeAppBarTitle => '总览';

  @override
  String get homeAiAssistantTooltip => 'AI 助手';

  @override
  String get homeNetWorthTitle => '净资产';

  @override
  String get homeQuickAddAccount => '添加账户';

  @override
  String get homeQuickRecordEntry => '记一笔';

  @override
  String get homeQuickImport => '导入';

  @override
  String get financePrivacyHideAmountsTooltip => '隐藏金额';

  @override
  String get financePrivacyShowAmountsTooltip => '显示金额';

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
  String get liabilityFieldPayerAccount => '还款账户';

  @override
  String get liabilityPayerAccountHint => '计划还款将记入此账户。';

  @override
  String get liabilityPayerAccountEmpty => '暂无可用还款账户，请先新建现金或银行账户。';

  @override
  String get liabilityPayerAccountRequired => '保存前请选择还款账户。';

  @override
  String get liabilityFieldStatementDay => '账单日';

  @override
  String get liabilityFieldPaymentDueDay => '还款日';

  @override
  String get liabilityFieldNote => '备注';

  @override
  String get liabilityDetailsTitle => '还款计划详情';

  @override
  String get liabilityDetailsLoanSummary => '利率类型、起还日与还款方式';

  @override
  String get liabilityDetailsCardSummary => '账单日期与备注';

  @override
  String get liabilityEditAction => '编辑负债';

  @override
  String get liabilityEditMetadataOnlyHint =>
      '此处可编辑名称、还款账户和备注。本金、利率和期限会驱动还款计划，因此保持锁定。';

  @override
  String get liabilitySaveAction => '保存';

  @override
  String get liabilityValidationRequired => '必填';

  @override
  String get liabilityValidationPositive => '必须大于零';

  @override
  String get liabilityValidationDayOfMonth => '必须为 1–31';

  @override
  String liabilityValidationAccountCurrency(String currency) {
    return '请使用还款账户币种：$currency';
  }

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
  String get physicalAssetDetailsTitle => '资产详情';

  @override
  String get physicalAssetVehicleDetailsSummary => '估值与折旧设置';

  @override
  String get physicalAssetRealEstateDetailsSummary => '地址、估值与关联贷款';

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
  String get fxRatesDeleteConfirmTitle => '删除这条汇率？';

  @override
  String get fxRatesDeleteConfirmBody => '这会删除该货币对在当前日期记录的汇率。';

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
  String get commonRefresh => '刷新';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDone => '完成';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSave => '保存';

  @override
  String get commonSaving => '保存中…';

  @override
  String get commonSaved => '已保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonDeleted => '已删除';

  @override
  String get commonClose => '关闭';

  @override
  String commonRevealMore(int count) {
    return '更多 · $count';
  }

  @override
  String get commonRevealLess => '收起';

  @override
  String get commonLoading => '加载中…';

  @override
  String get commonError => '出错了';

  @override
  String get commonSafeErrorMessage => '暂时无法完成，请稍后重试。';

  @override
  String get shellMoreActions => '更多操作';

  @override
  String commonLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get commonLoadFailed => '加载失败，请稍后重试。';

  @override
  String get commonSaveFailed => '保存失败，请重试';

  @override
  String get commonDeleteFailed => '删除失败，请重试';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonUndoSucceeded => '已撤销更改';

  @override
  String get commonUndoFailed => '撤销失败，请重试';

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
  String get routeGoBack => '返回上一页';

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
    return '助理：$query';
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
  String get commandPaletteOpenAi => '打开助理';

  @override
  String get navAskAi => '助手';

  @override
  String get commandPaletteAiHistory => 'AI 历史会话';

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
  String nativeUpdateAvailable(String version) {
    return 'NaviWealth $version 可更新。';
  }

  @override
  String get nativeUpdateApply => '更新';

  @override
  String get nativeUpdateDismiss => '稍后';

  @override
  String get nativeUpdateOpenFailed => '无法打开更新链接。';

  @override
  String get authLoginTitle => '欢迎回来';

  @override
  String get authRegisterTitle => '创建账号';

  @override
  String get authLoginSubmit => '登录';

  @override
  String get authRegisterSubmit => '创建账号';

  @override
  String get authRegisterSwitch => '创建账号';

  @override
  String get authLoginSwitch => '返回登录';

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
  String get authRegisterErrorAccountExists => '账号已存在，请直接登录。';

  @override
  String get authLoginNoticeSessionExpired => '登录已过期，请重新登录。';

  @override
  String get authUpgradeRegisterHint => '创建新账号并同步已有数据';

  @override
  String get authUpgradeConnectHint => '登录已有账号（本地数据将单独保留）';

  @override
  String get authUpgradeRegisterSubmit => '创建并同步';

  @override
  String get authUpgradeConnectSubmit => '登录并同步';

  @override
  String get settingsDevicesTitle => '已登录设备';

  @override
  String get settingsDevicesSubtitle => '查看已登录的设备并远程登出';

  @override
  String get settingsSignOutTitle => '登出';

  @override
  String get settingsSignOutSubtitle => '关闭云同步，并将此设备保留为本地模式';

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
  String get dashboardTrendMetricCurrent => '当前';

  @override
  String get dashboardTrendMetricChange => '区间变化';

  @override
  String get dashboardTrendMetricRange => '区间';

  @override
  String get dashboardHeaderDeltaTodayLabel => '今日';

  @override
  String get dashboardHeaderDeltaMonthLabel => '本月';

  @override
  String get dashboardHeaderDeltaYtdLabel => '年初至今';

  @override
  String get analyticsAppBarTitle => '组合分析';

  @override
  String get analyticsOverviewNetWorth => '净值';

  @override
  String get analyticsOverviewMonthlyChange => '本月变化';

  @override
  String get analyticsOverviewCashFlow => '现金流';

  @override
  String get analyticsOverviewFireEta => 'FIRE ETA';

  @override
  String analyticsOverviewFireEtaMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months 个月',
    );
    return '$_temp0';
  }

  @override
  String get analyticsOverviewFireNotConfigured => '未设置';

  @override
  String get analyticsOverviewUnavailable => '—';

  @override
  String get analyticsCashFlowTrendTitle => '现金流趋势';

  @override
  String get analyticsCashFlowTrendSubtitle => '最近 6 个月的经营性净现金流。';

  @override
  String get analyticsCashFlowTrendNetSeries => '净现金流';

  @override
  String get analyticsCashFlowTrendAverageNet => '6 月平均净额';

  @override
  String get analyticsCashFlowTrendInflow => '本月流入';

  @override
  String get analyticsCashFlowTrendOutflow => '本月流出';

  @override
  String get analyticsCashFlowTrendSemantic => '最近每月净现金流图表';

  @override
  String get analyticsCashFlowTrendLoadError => '无法加载现金流趋势。';

  @override
  String get analyticsFireProgressTitle => 'FIRE 进度';

  @override
  String get analyticsFireProgressSubtitle => '可投资资产相对目标净值与当前现金跑道。';

  @override
  String analyticsFireProgressPercent(String value) {
    return '已达目标 $value';
  }

  @override
  String get analyticsFireProgressInvestable => '可投资资产';

  @override
  String get analyticsFireProgressTarget => '目标';

  @override
  String get analyticsFireProgressWithdrawalRate => '提取率';

  @override
  String get analyticsFireProgressCashRunway => '现金跑道';

  @override
  String get analyticsFireProgressEta => 'ETA';

  @override
  String analyticsFireProgressMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months 个月',
    );
    return '$_temp0';
  }

  @override
  String get analyticsFireProgressUnlimited => '无限';

  @override
  String get analyticsFireProgressNotConfiguredTitle => '尚未设置 FIRE 计划';

  @override
  String get analyticsFireProgressNotConfiguredBody =>
      '设置 FIRE 目标后，这里会跟踪进度和现金跑道。';

  @override
  String get analyticsFireProgressLoadError => '无法加载 FIRE 进度。';

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
  String get fireDepthTitle => '压力测试与模拟';

  @override
  String get fireDepthSubtitle => '韧性检查与计划假设推演';

  @override
  String fireHeroProgressLine(String progress, String current, String target) {
    return '$progress · $current / $target';
  }

  @override
  String get fireHeroNextStepLabel => '下一步';

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
  String get fireBudgetNoDataTitle => '暂无预算信号';

  @override
  String get fireBudgetNoDataDetail => '设置月度预算后，可将当前支出压力联动到 FIRE 计划。';

  @override
  String get fireBudgetComfortableTitle => '预算支持当前计划';

  @override
  String get fireBudgetComfortableDetail => '本月支出仍处于舒适区间。';

  @override
  String get fireBudgetStrainedTitle => '预算压力正在上升';

  @override
  String get fireBudgetStrainedDetail => '支出已接近月度上限，请优先守住计划结余。';

  @override
  String get fireBudgetOverTitle => '本月预算已超支';

  @override
  String get fireBudgetOverDetail => '当前支出压力可能降低 FIRE 计划所依赖的月度结余。';

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
  String get fireOsHeroTitle => '自由状态';

  @override
  String get fireOsHeroSubtitle => '当前资产是否还能支撑你想要的生活方式。';

  @override
  String get fireOsHeroNetWorthLabel => '净资产';

  @override
  String get fireOsHeroInvestableLabel => '可投资资产';

  @override
  String get fireOsHeroLiquidLabel => '现金资产';

  @override
  String get fireOsHeroWithdrawalRateLabel => '提取率';

  @override
  String fireOsHeroWithdrawalRateValue(String rate, String swr) {
    return '$rate% / 安全提取率 $swr%';
  }

  @override
  String get fireOsHeroWithdrawalRateInfinite => '有支出但缺可投资资产';

  @override
  String get fireOsHeroCashBucketLabel => '现金桶';

  @override
  String fireOsHeroCashBucketValue(String months, int target) {
    return '$months 个月 / 目标 $target 个月';
  }

  @override
  String get fireOsHeroCashBucketInfinite => '暂无月度支出记录';

  @override
  String get fireOsHeroEtaLabel => 'FIRE 预计达成';

  @override
  String get fireOsHeroEtaReached => '已达成 FIRE';

  @override
  String get fireOsHeroEtaUnreachable => '100 年内不可达';

  @override
  String get fireOsHeroAnnualSpendLabel => '年度支出';

  @override
  String get fireOsAnnualSpendSourceTrailing => '最近 12 个月';

  @override
  String get fireOsAnnualSpendSourcePlan => '计划输入';

  @override
  String get fireOsSafetySafe => '安全';

  @override
  String get fireOsSafetyCautious => '谨慎';

  @override
  String get fireOsSafetyDanger => '危险';

  @override
  String get fireOsSafetyUnconfigured => '尚未配置';

  @override
  String get fireOsSuggestedActionsTitle => '下一步建议';

  @override
  String get fireOsSuggestedActionsEmpty => '暂无需要操作的事项——保持当前节奏。';

  @override
  String get fireOsActionConfigurePlanTitle => '配置你的 FIRE 计划';

  @override
  String get fireOsActionConfigurePlanDetail => '填写目标净值、月度支出与结余,系统才能判断安全度。';

  @override
  String get fireOsActionHoldSteadyTitle => '状态健康——继续保持';

  @override
  String get fireOsActionHoldSteadyDetail => '提取率低于 SWR,现金桶充足。';

  @override
  String get fireOsActionTopUpCashBucketTitle => '补足现金桶';

  @override
  String fireOsActionTopUpCashBucketDetail(String amount, int months) {
    return '需再增加 $amount,达到 $months 个月覆盖。';
  }

  @override
  String get fireOsActionReduceSpendingTitle => '降低支出';

  @override
  String fireOsActionReduceSpendingDetailPct(String pct) {
    return '提取率比 SWR 高出 $pct 个百分点。';
  }

  @override
  String get fireOsActionReduceSpendingDetailGeneric =>
      '支出已超过可投资资产承受范围——请复盘月度开支。';

  @override
  String get fireOsActionDelayDiscretionaryTitle => '推迟非必要支出';

  @override
  String get fireOsActionDelayDiscretionaryDetail => '暂缓旅行、升级或大额采购,待提取率回落后再恢复。';

  @override
  String get fireOsActionRebalanceTitle => '再平衡至目标权重';

  @override
  String get fireOsActionRebalanceDetail => '配置已偏离目标——调整各桶比例。';

  @override
  String get fireOsActionBuildRiskReserveTitle => '建立风险储备';

  @override
  String get fireOsActionBuildRiskReserveDetail => '净资产为负或单薄——先备好应急 / 医疗资金。';

  @override
  String get fireOsActionRunReviewTitle => '打开最新复盘';

  @override
  String get fireOsActionRunReviewDetail => '查看月度或季度复盘了解背景。';

  @override
  String get fireOsActionFixCurrencyGapTitle => '补全汇率';

  @override
  String fireOsActionFixCurrencyGapDetail(int count) {
    return '$count 项资产缺少到本币的汇率。';
  }

  @override
  String get fireOsPlanFormAdvancedTitle => '高级设置';

  @override
  String get fireOsPlanFormSwrLabel => '安全提取率';

  @override
  String fireOsPlanFormSwrValue(String rate) {
    return '$rate%';
  }

  @override
  String get fireOsPlanFormSwrHelper =>
      'Trinity 研究默认 4%。Lean FIRE 通常更低;Fat FIRE 留更多缓冲。';

  @override
  String get fireOsPlanFormCashBucketLabel => '现金桶覆盖月数';

  @override
  String get fireOsPlanFormCashBucketHelper => '现金桶要覆盖多少个月的支出。';

  @override
  String get fireOsPlanFormLifestyleLabel => '生活方式';

  @override
  String get fireOsPlanFormLifestyleLean => 'Lean';

  @override
  String get fireOsPlanFormLifestyleStandard => '标准';

  @override
  String get fireOsPlanFormLifestyleFat => 'Fat';

  @override
  String get fireOsPlanFormLifestyleCoast => 'Coast';

  @override
  String get fireOsPlanFormLifestyleBarista => 'Barista';

  @override
  String get fireOsBucketsTitle => '桶视图';

  @override
  String get fireOsBucketsSubtitle => '把每项资产解释为现金 / 防御 / 增长 / 风险储备 / 梦想之一。';

  @override
  String get fireOsBucketRoleCash => '现金桶';

  @override
  String get fireOsBucketRoleDefensive => '防御桶';

  @override
  String get fireOsBucketRoleGrowth => '增长桶';

  @override
  String get fireOsBucketRoleRiskReserve => '风险桶';

  @override
  String get fireOsBucketRoleDream => '梦想桶';

  @override
  String get fireOsBucketStatusOnTrack => '正常';

  @override
  String get fireOsBucketStatusUnder => '低于目标';

  @override
  String get fireOsBucketStatusOver => '超过目标';

  @override
  String get fireOsBucketStatusEmpty => '空';

  @override
  String get fireOsBucketNoTarget => '暂无明确目标';

  @override
  String fireOsBucketCoverage(String current, String target) {
    return '$current / $target';
  }

  @override
  String fireOsBucketAssets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项资产',
      one: '1 项资产',
    );
    return '$_temp0';
  }

  @override
  String get fireOsBucketsManageCta => '管理桶规则';

  @override
  String get fireOsBucketsMappingTitle => '桶规则';

  @override
  String get fireOsBucketsMappingSubtitle => '为每项资产指定所属桶。未设置的项目使用默认规则。';

  @override
  String get fireOsBucketsMappingSave => '保存';

  @override
  String get fireOsBucketsMappingCancel => '取消';

  @override
  String get fireOsBucketsMappingDefault => '默认';

  @override
  String get fireOsBucketsMappingEmpty => '暂无可分配的资产。请先添加账户或资产。';

  @override
  String get fireOsUnmappedTitle => '未分配资产';

  @override
  String get fireOsUnmappedSubtitle => '这些资产暂未归入任何桶。若需纳入计划,请配置桶规则。';

  @override
  String get fireOsSimulationsTitle => '情景模拟';

  @override
  String get fireOsSimulationsSubtitle =>
      '点击一个预设,看计划变动后提取率 / 现金桶覆盖 / 安全等级如何移动;不会写入任何更改。';

  @override
  String get fireOsSimulationsBaselineLabel => '基线';

  @override
  String get fireOsSimulationsPresetExpenseUp20 => '支出 +20%';

  @override
  String get fireOsSimulationsPresetExpenseDown10 => '支出 −10%';

  @override
  String get fireOsSimulationsPresetSurplusUp30 => '结余 +30%';

  @override
  String get fireOsSimulationsPresetHalfRetireIncome => '半退休 +¥5k/月';

  @override
  String get fireOsSimulationsPresetInflationUp1pp => '通胀 +1 个百分点';

  @override
  String get fireOsSimulationsPresetSwrTight => '安全提取率收紧到 3.5%';

  @override
  String get fireOsSimulationsPresetCashBucketUp24 => '现金桶目标 24 个月';

  @override
  String fireOsSimulationsDeltaWrPp(String sign, String pp) {
    return '提取率 $sign$pp pp';
  }

  @override
  String get fireOsSimulationsDeltaWrUnavailable => '提取率 —';

  @override
  String fireOsSimulationsDeltaCash(String sign, String months) {
    return '现金 $sign$months 个月';
  }

  @override
  String get fireOsSimulationsDeltaCashUnavailable => '现金 —';

  @override
  String get fireOsStressTitle => '压力测试';

  @override
  String get fireOsStressSubtitle => '在熊市、支出上升、一次性冲击、汇率波动和现金桶耗尽下验证韧性。';

  @override
  String get fireOsStressEmpty => '请先配置 FIRE 计划再运行压力测试。';

  @override
  String fireOsStressScenarioMarketDrawdown(String pct) {
    return '市场回撤 −$pct%';
  }

  @override
  String fireOsStressScenarioExpenseSurge(String pct) {
    return '支出 +$pct%';
  }

  @override
  String fireOsStressScenarioOneOffShock(String amount) {
    return '一次性冲击 $amount';
  }

  @override
  String fireOsStressScenarioFxShock(String pct) {
    return '汇率冲击 ±$pct%';
  }

  @override
  String fireOsStressScenarioCashDepletion(int months) {
    return '$months 个月内现金桶被消耗';
  }

  @override
  String get fireOsStressVerdictSafe => '安全';

  @override
  String get fireOsStressVerdictCautious => '谨慎';

  @override
  String get fireOsStressVerdictDanger => '危险';

  @override
  String fireOsStressMetricWr(String rate) {
    return '提取率 $rate%';
  }

  @override
  String get fireOsStressMetricWrInfinite => '提取率 ∞';

  @override
  String fireOsStressMetricCash(String months) {
    return '现金 $months 个月';
  }

  @override
  String fireOsStressMetricNetWorth(String amount) {
    return '净资产 $amount';
  }

  @override
  String get fireOsReviewTitle => '周期复盘';

  @override
  String get fireOsReviewSubtitle => '确定性的月度 / 季度 / 年度快照,AI 负责解读,不负责编造。';

  @override
  String get fireOsReviewKindMonthly => '月度';

  @override
  String get fireOsReviewKindQuarterly => '季度';

  @override
  String get fireOsReviewKindAnnual => '年度';

  @override
  String fireOsReviewGeneratedAt(String date) {
    return '生成于 $date';
  }

  @override
  String fireOsReviewDiffTitle(String key) {
    return '对比 $key';
  }

  @override
  String get fireOsReviewDiffNoBaseline => '暂无上一期快照可对比 — 保存一次以解锁月度变化。';

  @override
  String fireOsReviewDiffWr(String sign, String pp) {
    return '提取率 $sign$pp 个百分点';
  }

  @override
  String get fireOsReviewDiffWrUnavailable => '提取率两端有无穷值,无法计算差值';

  @override
  String fireOsReviewDiffNetWorth(String sign, String amount) {
    return '净资产 $sign$amount';
  }

  @override
  String get fireOsReviewDiffNetWorthCurrencyChanged => '净资产币种已变,跳过差值。';

  @override
  String fireOsReviewDiffSafetyChanged(String from, String to) {
    return '安全等级 $from → $to';
  }

  @override
  String fireOsReviewDiffSafetyHeld(String level) {
    return '安全等级保持 $level';
  }

  @override
  String get fireOsReviewSaveSnapshot => '保存快照';

  @override
  String fireOsReviewSaved(String key) {
    return '已保存 · $key';
  }

  @override
  String get fireOsReviewFindingsTitle => '关键发现';

  @override
  String get fireOsReviewFindingNetWorthHealthy => '净资产为正。';

  @override
  String get fireOsReviewFindingNetWorthBroken => '净资产为零或负数。';

  @override
  String fireOsReviewFindingWithdrawalRateBelowSwr(String pct) {
    return '提取率低于 SWR $pct 个百分点。';
  }

  @override
  String fireOsReviewFindingWithdrawalRateAboveSwr(String pct) {
    return '提取率高于 SWR $pct 个百分点。';
  }

  @override
  String get fireOsReviewFindingWithdrawalRateInfinite => '有支出但无可投资资产。';

  @override
  String fireOsReviewFindingWithinTargetCashBucket(int months) {
    return '现金桶覆盖 $months 个月 — 已达标。';
  }

  @override
  String fireOsReviewFindingBelowTargetCashBucket(int months) {
    return '现金桶未达 $months 个月目标。';
  }

  @override
  String get fireOsReviewFindingFireEtaReached => 'FIRE 目标已达成。';

  @override
  String get fireOsReviewFindingFireEtaUnreachable => '100 年内难以达成 FIRE 目标。';

  @override
  String fireOsReviewFindingFireEtaProgressing(int months) {
    return 'FIRE 预计 $months 个月。';
  }

  @override
  String fireOsReviewFindingCurrencyGap(int count) {
    return '$count 项资产缺少本币汇率。';
  }

  @override
  String fireOsReviewFindingUnmappedHoldings(int count) {
    return '$count 项资产暂未分配桶。';
  }

  @override
  String fireOsReviewFindingStressDanger(String scenario) {
    return '压力测试 \"$scenario\" 触发危险等级。';
  }

  @override
  String fireOsReviewFindingStressCautious(String scenario) {
    return '压力测试 \"$scenario\" 触发谨慎等级。';
  }

  @override
  String get fireOsReviewFindingStressSafe => '所有压力测试在当前假设下均为安全。';

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
  String get rebalanceExecutionWorkspaceTitle => '调仓执行台';

  @override
  String get rebalanceExecutionResumeAction => '继续执行';

  @override
  String get rebalanceExecutionReplaceTitle => '替换当前执行任务？';

  @override
  String get rebalanceExecutionReplaceBody =>
      '当前执行任务来自另一份方案。已经记账的交易会保留；替换会永久关闭旧队列的撤销能力，并按当前方案重新开始。';

  @override
  String get rebalanceExecutionReplaceAction => '替换并继续';

  @override
  String rebalanceExecutionProgress(int done, int total) {
    return '已处理 $done/$total';
  }

  @override
  String get rebalanceExecutionApplyAction => '执行';

  @override
  String get rebalanceExecutionUndoAction => '撤销';

  @override
  String get rebalanceExecutionStopAction => '当前项完成后停止';

  @override
  String get rebalanceExecutionStoppedToast => '已在当前交易完成后停止。';

  @override
  String get rebalanceExecutionCompletedToast => '批量操作已完成。';

  @override
  String rebalanceExecutionPartialToast(int completed, int failed) {
    return '已完成 $completed 项，$failed 项需要处理。';
  }

  @override
  String rebalanceExecutionFailedToast(int failed) {
    return '批量操作已停止，$failed 项需要处理。';
  }

  @override
  String get rebalanceExecutionRecoveryToast => '批量操作已停止，其中一项需要恢复处理。';

  @override
  String get rebalanceExecutionArchiveAction => '归档执行任务';

  @override
  String get rebalanceExecutionArchiveTitle => '归档该执行任务？';

  @override
  String get rebalanceExecutionArchiveBody =>
      '归档会关闭当前队列。已经记账的交易会保留，并永久关闭该队列的撤销能力。核对信息和执行进度仍可查看，但待处理与已跳过交易不能再修改。';

  @override
  String get rebalanceExecutionArchiveAppliedBody =>
      '已执行交易不会自动撤销。如需回滚账本记录，请先执行撤销。';

  @override
  String get rebalanceExecutionBusyLeaveBlocked => '请等待当前操作完成，或先停止操作再离开。';

  @override
  String get rebalanceExecutionReviewAction => '核对';

  @override
  String get rebalanceExecutionAddPriceAction => '填写价格';

  @override
  String get rebalanceExecutionRetryApplyAction => '重试执行';

  @override
  String get rebalanceExecutionRetryUndoAction => '重试撤销';

  @override
  String get rebalanceExecutionSkipAction => '跳过';

  @override
  String get rebalanceExecutionReopenAction => '重新打开';

  @override
  String get rebalanceExecutionNotFound => '该执行任务不可用，或不属于当前用户。';

  @override
  String get rebalanceExecutionEmptyQueue => '当前方案没有需要执行的交易。';

  @override
  String get rebalanceExecutionEditorTitle => '核对交易';

  @override
  String get rebalanceExecutionSaveReviewAction => '保存核对结果';

  @override
  String get rebalanceExecutionAssetLabel => '证券';

  @override
  String get rebalanceExecutionCashAccountLabel => '现金账户（可选）';

  @override
  String get rebalanceExecutionManualPriceHelper => '自动报价暂不可用。填写价格后可在无行情时继续。';

  @override
  String get rebalanceExecutionIssuePriceRequired => '当前没有可用价格，请填写价格后继续。';

  @override
  String get rebalanceExecutionIssueInvalidReview => '部分交易信息无效，请核对后继续。';

  @override
  String get rebalanceExecutionIssueStaleReview => '核对信息已经过期，请按最新数据重新核对。';

  @override
  String get rebalanceExecutionIssueHoldingsChanged => '可用持仓已经变化，请重新核对交易数量。';

  @override
  String get rebalanceExecutionIssueOwnerChanged => '当前用户环境已经变化，无法安全执行这笔交易。';

  @override
  String get rebalanceExecutionIssueApplyUnavailable =>
      '行情或执行服务暂不可用。可以重试执行；缺少价格时也可手动填写。';

  @override
  String get rebalanceExecutionIssueUndoUnavailable => '暂时无法撤销，请重试撤销操作。';

  @override
  String get rebalanceExecutionIssueUnsafe => '无法安全继续这笔交易。请跳过，或归档执行任务。';

  @override
  String get rebalanceExecutionIssueRecoveryCorrupt =>
      '恢复数据不完整。归档执行任务前，请先核对账本。';

  @override
  String get rebalanceExecutionIssueLegacyApplyFailure => '此前的执行尝试失败，请重试执行。';

  @override
  String get rebalanceExecutionIssueLegacyUndoFailure => '此前的撤销尝试失败，请重试撤销。';

  @override
  String get rebalanceExecutionStateNeedsDetails => '待补充';

  @override
  String get rebalanceExecutionStateReady => '就绪';

  @override
  String get rebalanceExecutionStateApplying => '执行中';

  @override
  String get rebalanceExecutionStateApplied => '已执行';

  @override
  String get rebalanceExecutionStateApplyFailed => '执行失败';

  @override
  String get rebalanceExecutionStateUndoing => '撤销中';

  @override
  String get rebalanceExecutionStateUndone => '已撤销';

  @override
  String get rebalanceExecutionStateUndoFailed => '撤销失败';

  @override
  String get rebalanceExecutionStateSkipped => '已跳过';

  @override
  String get rebalanceExecutionStateRecoveryBlocked => '待恢复';

  @override
  String get rebalanceEmptyTitle => '暂无数据';

  @override
  String get rebalanceEmptyHint => '添加资产后即可查看偏离与再平衡建议。';

  @override
  String get rebalanceSettingsTooltip => '再平衡设置';

  @override
  String get rebalanceSettingsTitle => '漂移阈值';

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
  String get targetAllocationEditorSubtitle => '调整类别与单项资产权重，合计必须等于 100%。';

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
  String get targetAllocationEditorCategoryTargets => '类别目标';

  @override
  String get targetAllocationEditorAssetTargets => '资产目标';

  @override
  String get targetAllocationEditorAddAssetTarget => '添加资产目标';

  @override
  String get targetAllocationEditorNoAssetTargets => '尚未设置单项资产目标。';

  @override
  String get targetAllocationEditorNoAssetsAvailable => '暂无可添加资产';

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
  String get settingsRiskSection => '投资偏好';

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
  String get settingsRiskAppetiteLabel => '风险偏好';

  @override
  String get settingsRiskAppetiteConservative => '保守';

  @override
  String get settingsRiskAppetiteModerate => '平衡';

  @override
  String get settingsRiskAppetiteAggressive => '激进';

  @override
  String get settingsRiskAppetiteCustom => '自定义';

  @override
  String get settingsRiskAppetiteCustomBadge => '已自定义目标配置';

  @override
  String get settingsRiskAppetiteConfirmTitle => '应用风险偏好？';

  @override
  String settingsRiskAppetiteConfirmBody(String appetite) {
    return '切换为「$appetite」？这会在资产配置和集中度警报仍为自动预设时同步调整它们。';
  }

  @override
  String get settingsRiskAppetiteConfirmAction => '应用';

  @override
  String get settingsTargetAllocationLabel => '目标资产配置';

  @override
  String settingsTargetAllocationSubtitlePreset(String preset) {
    return '$preset预设';
  }

  @override
  String get settingsTargetAllocationSubtitleCustom => '已手工调整权重';

  @override
  String get settingsRiskThresholdsLabel => '集中度警报阈值';

  @override
  String get settingsRiskThresholdsSubtitleAuto => '按风险偏好自动调整';

  @override
  String get settingsRiskThresholdsSubtitleCustom => '已自定义';

  @override
  String get settingsRiskThresholdsTitle => '集中度警报阈值';

  @override
  String get settingsRiskThresholdsHint =>
      '这些阈值决定何时把某项持仓标为集中度过高。系统已根据你的风险偏好自动调整 —— 除非想覆盖默认值，否则无需修改。';

  @override
  String get settingsStressTestLabel => 'FIRE 压力测试参数';

  @override
  String get settingsStressTestSubtitleAuto => '使用默认假设';

  @override
  String get settingsStressTestSubtitleCustom => '已自定义';

  @override
  String get settingsStressTestTitle => 'FIRE 压力测试参数';

  @override
  String get settingsStressTestHint =>
      'FIRE 页面的压力测试用这些假设跑\"如果……怎么办\"的场景。这些参数决定每个场景假设多坏 —— 想要更保守（调高）或更宽松（调低）才需要动。';

  @override
  String get settingsStressTestMarketDrawdownLabel => '市场下跌';

  @override
  String get settingsStressTestMarketDrawdownSubtitle => '熊市对成长资产的冲击幅度';

  @override
  String get settingsStressTestExpenseShockLabel => '支出冲击';

  @override
  String get settingsStressTestExpenseShockSubtitle => '持续性生活成本上升';

  @override
  String get settingsStressTestFxShockLabel => '汇率冲击';

  @override
  String get settingsStressTestFxShockSubtitle => '外币波动幅度';

  @override
  String get settingsStressTestLumpSumLabel => '一次性大额支出';

  @override
  String get settingsStressTestLumpSumSubtitle => '医疗 / 家庭支援等突发开销（基础币种）';

  @override
  String get settingsStressTestLumpSumHint => '0 表示不测试此项';

  @override
  String get settingsStressTestResetDefaults => '恢复默认';

  @override
  String get settingsMonthlyExpenseLabel => '月度支出模型';

  @override
  String settingsMonthlyExpenseSubtitleAuto(int months) {
    return '$months 个月滚动平均';
  }

  @override
  String get settingsMonthlyExpenseSubtitleOverride => '已手动覆盖';

  @override
  String get settingsMonthlyExpenseHint =>
      'FIRE 投影需要一个「月度支出」基线。默认用过去几个月的滚动均值；如果想手填一个数字，使用下方的「手动覆盖」。';

  @override
  String get settingsMonthlyExpenseWindowLabel => '滚动窗口';

  @override
  String get settingsMonthlyExpenseWindowSubtitle => '自动派生时使用的历史月份数';

  @override
  String settingsMonthlyExpenseWindowValue(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months 个月',
    );
    return '$_temp0';
  }

  @override
  String get settingsMonthlyExpenseOverrideLabel => '手动覆盖';

  @override
  String get settingsMonthlyExpenseOverrideSubtitle => '跳过自动派生。留空则继续用滚动均值。';

  @override
  String get settingsMonthlyExpenseOverrideHint => '留空则使用自动';

  @override
  String get settingsMonthlyExpenseResetDefaults => '恢复默认';

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
  String get tradeEntryDateLabel => '交易日期时间';

  @override
  String get tradeEntryFeeLabel => '手续费';

  @override
  String get tradeEntryTaxLabel => '税费';

  @override
  String get tradeEntryAdvancedTitle => '交易详情';

  @override
  String get tradeEntryAdvancedSummary => '当前时间 · 无费用与备注';

  @override
  String get tradeEntryAdvancedConfigured => '已设置日期、费用或备注';

  @override
  String get tradeEntryCashAccountLabel => '资金账户';

  @override
  String get tradeEntryHoldingAccountLabel => '持仓账户';

  @override
  String get tradeEntrySettlementTitle => '结算方式';

  @override
  String tradeEntrySettlementBrokerCash(String currency) {
    return '持仓账户内 $currency 现金';
  }

  @override
  String tradeEntrySettlementExternal(String account, String currency) {
    return '$account · $currency';
  }

  @override
  String get tradeEntrySettlementAccountLabel => '外部结算账户';

  @override
  String get tradeEntrySettlementHelper => '留空时使用券商或交易所账户内的现金结算。';

  @override
  String tradeEntryCrossCurrencyHint(
    String assetCurrency,
    String tradeCurrency,
  ) {
    return '该资产以 $assetCurrency 报价；价格、成本和现金将以 $tradeCurrency 记录。';
  }

  @override
  String get tradeEntryCashAccountCurrencyChanged => '原资金账户不支持当前币种，请重新选择资金账户。';

  @override
  String get tradeEntryBrokerAccountRequiredTitle => '需要券商账户';

  @override
  String get tradeEntryBrokerAccountRequiredMessage => '录入证券交易前，请先创建券商或加密账户。';

  @override
  String get tradeEntryCashAccountInvalid => '请选择有效且币种与交易一致的资金账户。';

  @override
  String get tradeEntryLotCurrencyMismatch =>
      '所选币种与该持仓的批次币种不一致。请修改页面上的“币种”；如果持仓包含多种批次币种，请先修复或拆分持仓。';

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
  String get tradeTypeAdjustShort => '调整';

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
  String get expenseFormAccountMissingNotice => '原付款账户已不可用，请重新选择账户后继续。';

  @override
  String expenseFormCurrencyConflictNotice(
    String accountCurrency,
    String expenseCurrency,
  ) {
    return '该支出以 $expenseCurrency 记录，但账户当前使用 $accountCurrency。保存前请选择正确币种。';
  }

  @override
  String expenseFormAccountsLoadError(String error) {
    return '账户加载失败：$error';
  }

  @override
  String get expenseFormDateLabel => '日期时间';

  @override
  String get expenseFormAdvancedTitle => '日期与备注';

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
  String get aiToolHoldingsEmpty => '暂无持仓数据';

  @override
  String get aiToolAssetColumn => '资产';

  @override
  String get aiToolQuantityColumn => '数量';

  @override
  String get aiToolCostColumn => '成本';

  @override
  String aiToolHiddenItems(int count) {
    return '还有 $count 项未展示';
  }

  @override
  String get aiToolPaymentAccountsEmpty => '没有可用的支付账户';

  @override
  String get aiToolPaymentAccountsTitle => '可用支付账户';

  @override
  String aiToolHiddenAccounts(int count) {
    return '还有 $count 个账户未展示';
  }

  @override
  String aiToolXirrAssetScope(String assetId) {
    return '资产 $assetId';
  }

  @override
  String get aiToolXirrPortfolioScope => '组合整体';

  @override
  String get aiToolAllHistory => '全部历史';

  @override
  String get aiToolXirrUnavailable => '无法计算（现金流方向单一或样本不足）';

  @override
  String aiToolCashFlowCount(int count) {
    return '$count 条现金流';
  }

  @override
  String get aiToolNetWorthEmpty => '区间内没有累计净现金流数据';

  @override
  String get aiToolCurrentNetWorth => '累计净现金流';

  @override
  String get aiToolNetWorthSeriesName => '累计净现金流';

  @override
  String get aiToolNetWorthMethodNote => '月度累计净现金流 · 非市值净资产';

  @override
  String get aiToolNetWorthVsStart => '相对区间起点';

  @override
  String aiToolSamplePointCount(int count) {
    return '$count 个采样点';
  }

  @override
  String get aiToolBreakdownCostEmpty => '没有可分布的成本';

  @override
  String aiToolOtherCategoriesSummary(int count, String share) {
    return '其他 $count 类共 $share';
  }

  @override
  String get aiToolRiskAlertsEmpty => '没有触发的风险预警';

  @override
  String get aiToolRiskAlertTitle => '风险预警';

  @override
  String get aiToolHoldingsDataMalformed => '持仓数据格式异常';

  @override
  String aiToolTotalCostSummary(String cost, int count) {
    return '合计成本 $cost · $count 类持仓';
  }

  @override
  String get aiToolRecurringPatternsEmpty => '尚未检测到稳定的周期性支出';

  @override
  String aiToolMoreItems(int count) {
    return '+ 还有 $count 项';
  }

  @override
  String get aiToolCadenceMonthly => '每月';

  @override
  String get aiToolCadenceWeekly => '每周';

  @override
  String aiToolOccurrences(int count) {
    return '$count 次';
  }

  @override
  String aiToolOccurrencesRecent(int count, String date) {
    return '$count 次 · 最近 $date';
  }

  @override
  String get aiToolSubscriptionChangesEmpty => '本期未检测到订阅价格变化';

  @override
  String aiToolSinceDate(String date) {
    return ' · 自 $date';
  }

  @override
  String get aiToolRefundLinksEmpty => '尚未检测到退款配对';

  @override
  String get aiChatEmptyTitle => '你的 Life OS 助手';

  @override
  String get aiChatEmptyBody =>
      '可以把财务、知识、健康和计划放在一起问。回答会优先基于本地数据与已启用的 domain 工具，缺少关键字段时会先向你确认。';

  @override
  String get aiChatEmptySuggestion1 => '我现在最需要关注什么？';

  @override
  String get aiChatEmptySuggestion2 => '总结一下最近的财务、知识和健康信号。';

  @override
  String get aiChatEmptySuggestion3 => '我的计划和复盘里有哪些风险？';

  @override
  String get aiChatEmptySuggestion4 => '基于当前状态，下一步最值得做什么？';

  @override
  String get aiChatEmptySuggestionsHeader => '试试这些';

  @override
  String get aiChatEmptyDynamicNetWorth => '聊聊本月净值变化';

  @override
  String aiChatEmptyDynamicAnomaly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '看看这 $count 笔异常支出',
    );
    return '$_temp0';
  }

  @override
  String aiChatEmptyDynamicMaturity(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '我有 $count 笔存款将在 $days 天内到期，怎么办？',
    );
    return '$_temp0';
  }

  @override
  String get aiChatBootstrappingLabel => '正在准备会话…';

  @override
  String get aiIntentDefaultTimeframe => '最近 30 天';

  @override
  String get aiIntentCurrentObject => '当前对象';

  @override
  String aiIntentFallbackPrompt(Object objectLabel) {
    return '请就 $objectLabel 提供分析。';
  }

  @override
  String get aiIntentExplainChangeLabel => '为什么变化';

  @override
  String aiIntentExplainChangePrompt(Object objectLabel, Object timeframe) {
    return '请解释 $objectLabel 在 $timeframe 内的变化原因，并指出相关趋势。';
  }

  @override
  String get aiIntentSummarizeAccountLabel => '账户概览';

  @override
  String aiIntentSummarizeAccountPrompt(Object objectLabel, Object timeframe) {
    return '请用要点总结账户 $objectLabel 在 $timeframe 的表现。';
  }

  @override
  String get aiIntentStressTestPlanLabel => '如何提高';

  @override
  String aiIntentStressTestPlanPrompt(Object objectLabel) {
    return '请评估 $objectLabel 在不利条件下的稳健性，并给出 2–3 个具体改进建议。';
  }

  @override
  String get aiIntentComparePeriodLabel => '对比';

  @override
  String aiIntentComparePeriodPrompt(Object objectLabel) {
    return '请对比 $objectLabel 在两个不同时期的差异并说明驱动因素。';
  }

  @override
  String get aiIntentExplainInsightLabel => '展开';

  @override
  String aiIntentExplainInsightPrompt(Object objectLabel) {
    return '请详细解释这条洞察（$objectLabel），说明触发原因、严重程度和可采取的行动。';
  }

  @override
  String get aiIntentExplainChartLabel => '问这张图';

  @override
  String aiIntentExplainChartPrompt(Object objectLabel, Object timeframe) {
    return '请解释这张图（$objectLabel）在 $timeframe 内的关键变化，以及背后的驱动因素。';
  }

  @override
  String get aiIntentTransactionsExplainSelectionLabel => '解读';

  @override
  String aiIntentTransactionsExplainSelectionPrompt(Object objectLabel) {
    return '请解读用户选中的这些交易（$objectLabel），给出共同点、异常和可能归类。';
  }

  @override
  String get aiIntentExplainFireStateLabel => '解读 FIRE 状态';

  @override
  String aiIntentExplainFireStatePrompt(Object objectLabel) {
    return '请基于 get_fire_state 的结果，向我解释当前 $objectLabel 的安全等级、提取率、现金桶覆盖和 FIRE ETA，并指出最值得关注的一两条 suggested_actions。';
  }

  @override
  String get aiIntentReviewCashBucketLabel => '检查现金覆盖';

  @override
  String aiIntentReviewCashBucketPrompt(Object objectLabel) {
    return '请用 get_fire_state 检查现金覆盖月数是否达到目标 $objectLabel；如不足，请给出补足金额，并准备好 propose_fire_plan_update 的建议。';
  }

  @override
  String get aiIntentSimulateFireChangeLabel => '模拟一下';

  @override
  String aiIntentSimulateFireChangePrompt(Object objectLabel) {
    return '请用 simulate_fire_plan 模拟 $objectLabel 的变化（支出、结余、SWR、现金桶月数等）对 FIRE 状态的影响。明确告诉我这只是模拟，没有写入计划。';
  }

  @override
  String get aiIntentExplainStressTestLabel => '解释压力测试';

  @override
  String aiIntentExplainStressTestPrompt(Object objectLabel) {
    return '请基于 get_fire_stress_tests 的结果逐条解释市场回撤、支出上升、一次性冲击、汇率冲击和现金桶耗尽对 $objectLabel 的影响。强调这是韧性检验，不是预测。';
  }

  @override
  String get aiIntentSuggestFireActionsLabel => '下一步怎么办';

  @override
  String get aiIntentSuggestFireActionsPrompt =>
      '请基于 get_fire_state 的 suggested_actions 给出三件最值得做的事；若涉及计划改动，请用 propose_fire_plan_update 让我确认。';

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
  String get aiChatComposerHintIdle => '问问 NaviWealth：财务、知识、健康或计划都可以';

  @override
  String get aiChatComposerHintStreaming => '正在生成回答…';

  @override
  String get aiChatComposerSendTooltip => '发送 (⌘/Ctrl + Enter)';

  @override
  String get aiChatComposerStopTooltip => '停止生成';

  @override
  String get speechInputStartTooltip => '开始语音输入';

  @override
  String get speechInputStopTooltip => '停止并保留文字';

  @override
  String get speechInputStartingTooltip => '正在准备端侧语音识别…';

  @override
  String get speechInputModelMissing => '请先下载中文实时语音模型';

  @override
  String get speechInputUnsupported => '当前平台暂不支持端侧语音输入';

  @override
  String get speechInputPermissionDenied => '需要麦克风权限才能使用语音输入';

  @override
  String get speechInputFailed => '语音识别启动失败，请稍后重试';

  @override
  String get aiChatThinking => '正在思考…';

  @override
  String aiChatToolsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '使用了 $count 个工具',
    );
    return '$_temp0';
  }

  @override
  String get aiChatToolsExpand => '展开详情';

  @override
  String get aiChatToolsCollapse => '收起';

  @override
  String aiChatRunningTool(String tool) {
    return '正在 $tool';
  }

  @override
  String get aiChatJumpToLatest => '最新';

  @override
  String aiChatJumpToLatestWithCount(int count) {
    return '最新 · $count';
  }

  @override
  String get aiChatDateToday => '今天';

  @override
  String get aiChatDateYesterday => '昨天';

  @override
  String get aiChatMessageActionsTitle => '消息操作';

  @override
  String aiChatDecisionSelected(String label) {
    return '已选择：$label';
  }

  @override
  String get aiChatDecisionCustomHint => '输入你的选项…';

  @override
  String get aiToolOpenWealth => '打开财富页';

  @override
  String get aiChatJumpToLatestTooltip => '跳到最新';

  @override
  String get aiChatMessageCopy => '复制';

  @override
  String get aiChatMessageCopied => '已复制到剪贴板';

  @override
  String get aiChatLinkConfirmTitle => '打开链接？';

  @override
  String get aiChatLinkConfirmBody => '请先确认目标地址——AI 输出的链接不可信，可能不是你预期的地址。';

  @override
  String get aiChatLinkOpen => '打开';

  @override
  String get aiChatLinkOpenFailed => '无法打开链接。';

  @override
  String get aiChatMessageRegenerate => '重新生成';

  @override
  String get aiChatSemanticsUserMessage => '你说：';

  @override
  String get aiChatSemanticsAssistantMessage => 'AI 回复';

  @override
  String get aiChatSemanticsAssistantError => 'AI 回复出错';

  @override
  String get aiChatSemanticsSystemNotice => '系统提示：';

  @override
  String get aiChatToolDebugTooltip => '查看工具原始数据';

  @override
  String get aiChatTransparencyOpenDetail => '查看完整透明度记录';

  @override
  String get aiChatProfileChipTooltip => '切换模型 Profile';

  @override
  String get aiChatEditUserMessage => '编辑';

  @override
  String get aiChatEditUserMessageTitle => '编辑后重发';

  @override
  String get aiChatEditUserMessageWarning => '保存后，原 AI 回复及之后的所有内容都会被丢弃并重新生成。';

  @override
  String get aiChatEditUserMessageSubmit => '保存并重发';

  @override
  String get aiChatEditUserMessageHint => '已填入输入框，发送后将替换本轮及之后内容';

  @override
  String get aiChatEditBannerTitle => '正在编辑消息 — 发送后将替换本轮';

  @override
  String get aiChatEditCancel => '取消';

  @override
  String aiChatSessionMessageCount(int count) {
    return '$count 条消息';
  }

  @override
  String get aiChatDecisionAllowCustom => '或在下方直接输入你的方案。';

  @override
  String aiChatDecisionReply(String label) {
    return '我选择「$label」。请在此方案下继续。';
  }

  @override
  String get aiChatProposalEditMoreFields => '更多字段';

  @override
  String get aiChatProposalEditStandardFields => '常用字段';

  @override
  String get aiChatSessionsSearchHint => '搜索对话…';

  @override
  String aiChatSessionsSearchEmpty(String query) {
    return '未找到与「$query」匹配的对话';
  }

  @override
  String get aiChatSessionsSearchClear => '清除搜索';

  @override
  String get aiChatSessionsGroupPinned => '置顶';

  @override
  String get aiChatSessionsGroupArchived => '已归档';

  @override
  String aiChatSessionsShowArchived(int count) {
    return '显示归档（$count）';
  }

  @override
  String get aiChatSessionsHideArchived => '隐藏归档';

  @override
  String get aiChatSessionsClearArchive => '清空归档';

  @override
  String get aiChatSessionsClearArchiveTitle => '清空归档？';

  @override
  String get aiChatSessionsClearArchiveBody => '将永久删除所有已归档对话，此操作不可撤销。';

  @override
  String aiChatSessionsClearArchiveDone(int count) {
    return '已删除 $count 个归档对话';
  }

  @override
  String get aiChatSessionsEmptyActive => '没有进行中的对话';

  @override
  String get aiChatSessionPinAction => '置顶';

  @override
  String get aiChatSessionUnpinAction => '取消置顶';

  @override
  String get aiChatSessionArchiveAction => '归档';

  @override
  String get aiChatSessionUnarchiveAction => '取消归档';

  @override
  String get aiChatSessionsGroupToday => '今天';

  @override
  String get aiChatSessionsGroupYesterday => '昨天';

  @override
  String get aiChatSessionsGroupThisWeek => '本周';

  @override
  String get aiChatSessionsGroupThisMonth => '本月';

  @override
  String get aiChatSessionsGroupOlder => '更早';

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
  String get aiChatProposalKindIncome => '收入';

  @override
  String get aiChatProposalKindLiabilityPayment => '还款';

  @override
  String get aiChatProposalKindAccountCreate => '新账户';

  @override
  String get aiChatProposalKindAssetValuation => '估值更新';

  @override
  String get aiChatProposalKindFirePlanUpdate => 'FIRE 计划更新';

  @override
  String get aiChatProposalKindFireBucketRule => 'FIRE 桶规则';

  @override
  String get aiChatProposalKindOptionsProfileUpdate => 'Income Planner 偏好';

  @override
  String get aiChatProposalKindOptionsJournalEntry => '期权流水';

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
  String aiChatProposalBatchProgress(int completed, int total) {
    return '正在处理第 $completed/$total 项';
  }

  @override
  String get aiChatProposalBatchRecover => '撤销已写入项';

  @override
  String aiChatProposalBatchRecoveryNeeded(int count) {
    return '仍有 $count 项已写入，撤销完成前不会重新执行批次';
  }

  @override
  String get aiChatProposalBatchRolledBack => '已撤销本批次中写入的项目，可以安全重试。';

  @override
  String aiChatProposalBatchResultAllOk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已记录 $count 项',
    );
    return '$_temp0';
  }

  @override
  String aiChatProposalBatchResultMixed(int applied, int failed) {
    return '已记录 $applied 项 · $failed 项失败';
  }

  @override
  String aiChatProposalBatchResultAllFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项全部失败',
    );
    return '$_temp0';
  }

  @override
  String aiChatProposalConfirmTokenWarning(String token) {
    return '此操作高风险。请输入「$token」启用确认。';
  }

  @override
  String aiChatProposalConfirmTokenPending(String token) {
    return '输入「$token」后即可点击确认。';
  }

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
  String get aiChatFieldNotes => '备注';

  @override
  String get aiChatFieldOptionPremium => '权利金';

  @override
  String get aiChatRecommendedBadge => '推荐';

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
  String get aiChatRowUnderlying => '标的';

  @override
  String get aiChatRowOptionContract => '合约';

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
  String aiChatToolJumpJournalEntry(String id) {
    return '日记账 $id';
  }

  @override
  String aiChatToolJumpTradeJournal(String id) {
    return '交易记录 $id';
  }

  @override
  String get aiChatToolEvidenceLabel => '依据';

  @override
  String get aiChatToolShowRawJson => '查看 raw JSON';

  @override
  String get aiChatToolShowCompactView => '返回精简视图';

  @override
  String get aiFloatingPillLabel => '打开助理';

  @override
  String get aiChatSheetTitle => 'AI 助手';

  @override
  String get aiChatSheetEmpty => '随便问问你的 Life OS 状态。';

  @override
  String get aiChatSheetExpandTooltip => '展开全屏';

  @override
  String get aiChatSheetNewTooltip => '新对话';

  @override
  String get chartEmptyDefault => '暂无数据';

  @override
  String get chartTotalLabel => '合计';

  @override
  String get formAmountFieldLabelDefault => '金额';

  @override
  String get formAmountFieldRequired => '请输入金额';

  @override
  String get formAmountFieldInvalid => '金额格式不正确';

  @override
  String get formAmountFieldNegativeNotAllowed => '金额不能为负';

  @override
  String get formAmountFieldZeroNotAllowed => '金额必须大于零';

  @override
  String get formNoteFieldLabelDefault => '备注';

  @override
  String get formDateFieldClearTooltip => '清除';

  @override
  String get formDateFieldTimeLabel => '时间';

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
  String get systemAccountIncome => '收入';

  @override
  String get systemAccountIncomeSalary => '工资';

  @override
  String get systemAccountIncomeDividend => '股息';

  @override
  String get systemAccountIncomeInterest => '利息收入';

  @override
  String get systemAccountIncomeCapitalGains => '资本利得';

  @override
  String get systemAccountIncomeOther => '其他收入';

  @override
  String get systemAccountExpense => '支出';

  @override
  String get systemAccountExpenseDining => '餐饮';

  @override
  String get systemAccountExpenseGroceries => '生鲜日用';

  @override
  String get systemAccountExpenseCoffee => '咖啡';

  @override
  String get systemAccountExpenseTransport => '公共交通';

  @override
  String get systemAccountExpenseRideHailing => '打车';

  @override
  String get systemAccountExpenseHousing => '住房';

  @override
  String get systemAccountExpenseUtilities => '水电燃气';

  @override
  String get systemAccountExpenseHousehold => '家居日用';

  @override
  String get systemAccountExpenseShopping => '购物';

  @override
  String get systemAccountExpenseSubscriptions => '订阅';

  @override
  String get systemAccountExpenseEntertainment => '娱乐';

  @override
  String get systemAccountExpenseMedical => '医疗';

  @override
  String get systemAccountExpenseFitness => '运动健身';

  @override
  String get systemAccountExpenseEducation => '教育';

  @override
  String get systemAccountExpenseTravel => '旅行';

  @override
  String get systemAccountExpenseCommunication => '通讯';

  @override
  String get systemAccountExpenseGift => '礼物';

  @override
  String get systemAccountExpenseFamilySupport => '家庭支持';

  @override
  String get systemAccountExpensePets => '宠物';

  @override
  String get systemAccountExpenseTrading => '交易';

  @override
  String get systemAccountExpenseTradingFee => '手续费';

  @override
  String get systemAccountExpenseTradingTax => '交易税费';

  @override
  String get systemAccountExpenseTradingInterest => '融资利息';

  @override
  String get systemAccountExpenseTax => '税务';

  @override
  String get systemAccountExpenseTaxWithholding => '预扣税';

  @override
  String get systemAccountExpenseOther => '其他支出';

  @override
  String get systemAccountEquity => '权益';

  @override
  String get systemAccountEquityOpeningBalance => '期初余额';

  @override
  String get systemAccountEquitySplits => '拆股';

  @override
  String get systemAccountEquityAdjustments => '调整';

  @override
  String get physicalAssetValuationProjected => '预计估值';

  @override
  String get physicalAssetValuationHistorical => '历史估值';

  @override
  String get physicalAssetValuationTrendSemanticLabel => '估值走势';

  @override
  String get accountsDetailEmpty => '请在左侧选择账户，查看余额与活动。';

  @override
  String get accountsCreateAction => '新建账户';

  @override
  String accountsLoadError(String error) {
    return '加载失败：$error';
  }

  @override
  String get accountsEmptyHint => '添加第一个账户，开始记录你的资产。';

  @override
  String get accountsOverviewTitle => '账户总览';

  @override
  String get accountsOverviewAccountsLabel => '账户';

  @override
  String get accountsOverviewInstitutionsLabel => '机构';

  @override
  String get accountsOverviewCurrenciesLabel => '币种';

  @override
  String accountsCategoryCount(int count) {
    return '$count 个账户';
  }

  @override
  String get accountDetailEditAction => '编辑账户';

  @override
  String get accountDetailNotFound => '未找到账户';

  @override
  String get accountDetailBalanceTitle => '可用余额';

  @override
  String get accountDetailTransferAction => '转账';

  @override
  String get accountDetailAdjustBalanceAction => '调整余额';

  @override
  String get accountDetailRecentActivityTitle => '最近活动';

  @override
  String get accountDetailNoActivity => '该账户暂无活动记录。';

  @override
  String get accountDetailTypeLabel => '账户类型';

  @override
  String get accountDetailCurrencyLabel => '主要币种';

  @override
  String get accountDetailInstitutionLabel => '机构';

  @override
  String get accountDetailNumberLabel => '账号';

  @override
  String get accountDetailNotesLabel => '备注';

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
  String get accountFormAdvancedTitle => '更多账户信息';

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
  String get cashFormAccountLockedHint =>
      '该现金余额已绑定上方账户。如需迁移到其他账户，请删除该余额后在目标账户重新录入。';

  @override
  String get cashFormCheckingExisting => '正在检查该账户是否已有现金余额…';

  @override
  String get cashFormExistingFoundTitle => '已找到现有现金余额';

  @override
  String get cashFormExistingFoundBody => '保存后将更新该账户的现有余额，不会创建重复记录。';

  @override
  String get cashFormMissingAccount => '关联账户不可用';

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
  String get activityFeedSummaryExpense => '支出';

  @override
  String get activityFeedSummaryIncome => '收入';

  @override
  String get activityFeedSummaryCount => '笔数';

  @override
  String activityFeedDayExpense(String amount) {
    return '出 $amount';
  }

  @override
  String activityFeedDayIncome(String amount) {
    return '入 $amount';
  }

  @override
  String get activityFeedSearchAction => '搜索';

  @override
  String get activityFeedSearchHint => '搜索备注或收款方';

  @override
  String activityFeedSearchTag(String query) {
    return '“$query”';
  }

  @override
  String get activityEntryDeleteTitle => '删除这笔流水？';

  @override
  String get activityEntryDeleteBody => '将从账本中移除该日记账分录。此操作无法在此页撤销。';

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
  String get settingsNumbersAndMoneySection => '货币与数字';

  @override
  String get settingsPlanningSection => '规划';

  @override
  String get settingsAiSection => 'AI';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsDataSection => '数据';

  @override
  String get settingsDataManagementTitle => '数据与存储';

  @override
  String get settingsDataManagementSubtitle => '集中查看、导出、清理和重置各个 OS 的数据';

  @override
  String get dataManagementBackupTitle => '加密备份与恢复';

  @override
  String get dataManagementBackupSubtitle => '执行破坏性维护前先创建备份';

  @override
  String get dataManagementSafetyNotice =>
      '缓存清理只移除本地可重建数据。OS 重置需要单独确认，不会与缓存维护混在一起。';

  @override
  String get dataManagementAutomaticTitle => '自动维护';

  @override
  String get dataManagementAutomaticSubtitle => '每日清理过期的 AI、Agent、导入草稿和事件历史';

  @override
  String get dataManagementRunMaintenanceTitle => '立即运行维护';

  @override
  String get dataManagementRunMaintenanceNever => '尚无维护记录';

  @override
  String dataManagementRunMaintenanceLast(int count) {
    return '上次维护移除了 $count 条数据';
  }

  @override
  String get dataManagementMaintenanceRunning => '运行中…';

  @override
  String dataManagementMaintenanceSuccess(int count) {
    return '维护完成，已移除 $count 条数据';
  }

  @override
  String get dataManagementDomainEnabled => '已启用';

  @override
  String get dataManagementDomainDisabled => '已关闭';

  @override
  String get dataManagementSourceRows => '主数据';

  @override
  String get dataManagementDeletedRows => '已删除';

  @override
  String get dataManagementCacheRows => '缓存';

  @override
  String dataManagementTableSummary(int sourceTables, int cacheTables) {
    return '$sourceTables 个主数据表 · $cacheTables 个缓存表';
  }

  @override
  String get dataManagementCacheHelp => '本地派生数据，相关功能会在需要时重新生成。';

  @override
  String get dataManagementClearCacheAction => '清理缓存';

  @override
  String get dataManagementClearing => '正在清理…';

  @override
  String dataManagementClearCacheConfirmTitle(String domain) {
    return '清理 $domain 缓存？';
  }

  @override
  String dataManagementClearCacheConfirmBody(int count) {
    return '将移除 $count 条本地缓存，不影响已同步的主数据。';
  }

  @override
  String dataManagementClearCacheSuccess(int count) {
    return '已清理 $count 条缓存';
  }

  @override
  String get dataManagementExportDomainAction => '导出 OS';

  @override
  String get dataManagementResetDeviceAction => '重置本设备';

  @override
  String get dataManagementResetEverywhereAction => '从所有设备删除';

  @override
  String get dataManagementResetting => '正在重置…';

  @override
  String dataManagementResetDeviceConfirmTitle(String domain) {
    return '重置本设备上的 $domain？';
  }

  @override
  String get dataManagementResetDeviceConfirmBody =>
      '将移除本 OS 的本地主数据、派生缓存、Memory 和 Agent 历史。开启云同步时，数据可能在下次同步后重新下载。';

  @override
  String dataManagementResetEverywhereConfirmTitle(String domain) {
    return '永久删除 $domain？';
  }

  @override
  String get dataManagementResetEverywhereConfirmBody =>
      '将从服务器和所有设备永久删除本 OS。离线设备重新上线后也无法恢复旧 generation。';

  @override
  String dataManagementResetSuccess(int count) {
    return '重置完成，已移除 $count 条本地数据';
  }

  @override
  String get dataManagementSharedTitle => 'AI 与跨域数据';

  @override
  String get dataManagementSharedSubtitle => '仅保存在本机的对话、审计轨迹、记忆、事件投影和 Agent 结果';

  @override
  String get dataManagementChatRows => '对话';

  @override
  String get dataManagementAiRows => 'AI 审计';

  @override
  String get dataManagementMemoryRows => '记忆';

  @override
  String get dataManagementAgentRows => 'Agent';

  @override
  String dataManagementStorageUsage(String used, String reclaimable) {
    return '数据库占用 $used · 可回收 $reclaimable';
  }

  @override
  String get dataManagementClearSharedAction => '清除本地历史';

  @override
  String get dataManagementClearSharedConfirmTitle => '清除 AI 与跨域历史？';

  @override
  String dataManagementClearSharedConfirmBody(int count) {
    return '将移除 $count 条本地对话、审计、记忆、事件和 Agent 历史。各 OS 的源数据与偏好设置会保留。';
  }

  @override
  String dataManagementClearSharedSuccess(int count) {
    return '已清除 $count 条本地历史';
  }

  @override
  String get dataManagementCompactAction => '压缩数据库';

  @override
  String get dataManagementCompacting => '压缩中…';

  @override
  String get dataManagementCompactSuccess => '数据库压缩完成';

  @override
  String get dataManagementResetAllTitle => '全部 OS 数据';

  @override
  String get dataManagementResetAllSubtitle =>
      '仅在需要重新开始 FinanceOS、HealthOS、KnowledgeOS 和 ExecutionOS 时使用。账户、设备、设置与汇率配置会保留。';

  @override
  String get dataManagementResetAllDeviceAction => '重置本机全部 OS';

  @override
  String get dataManagementResetAllEverywhereAction => '永久删除全部 OS 数据';

  @override
  String get dataManagementResetAllDeviceConfirmTitle => '重置本机的全部 OS？';

  @override
  String get dataManagementResetAllDeviceConfirmBody =>
      '本机的全部 OS 源数据、缓存、AI 历史、记忆和 Agent 结果都会被移除。云端数据可在下次同步时重新下载。';

  @override
  String get dataManagementResetAllEverywhereConfirmTitle => '永久删除全部 OS？';

  @override
  String get dataManagementResetAllEverywhereConfirmBody =>
      '全部 OS 数据会从服务器和所有设备永久删除。账户、设备、设置与汇率配置会保留。此操作无法撤销。';

  @override
  String backupDomainPageTitle(String domain) {
    return '$domain 备份';
  }

  @override
  String get settingsDomainsSection => 'LifeOS 域';

  @override
  String get settingsDomainsTitle => '域管理';

  @override
  String get settingsDomainsSubtitle =>
      'FinanceOS / HealthOS / KnowledgeOS / ExecutionOS 开关';

  @override
  String get settingsDomainsFinanceSubtitle =>
      '常驻财务域：货币、汇率、风险偏好、资产配置与 FIRE 规划假设';

  @override
  String get settingsDomainsFinanceAlwaysOnBadge => '常开';

  @override
  String settingsDomainsDisabledToast(String domain) {
    return '$domain 已关闭。你可以随时在这里重新启用。';
  }

  @override
  String get agentSettingsTitle => 'Agents';

  @override
  String get agentSettingsSubtitle => '管理当前已启用 LifeOS 域在本设备上的定时 Agent。';

  @override
  String get agentSettingsNoActiveTitle => '暂无可用 Agent';

  @override
  String get agentSettingsNoActiveMessage => '启用一个 LifeOS 域后，可在这里查看它的 Agent。';

  @override
  String get agentSettingsManageDomains => '管理域';

  @override
  String get agentSettingsManagedBadge => '托管';

  @override
  String get agentSettingsRunNow => '立即运行';

  @override
  String get agentSettingsViewResult => '查看结果';

  @override
  String get agentSettingsViewHistory => '历史';

  @override
  String agentSettingsHistoryTitle(String agentName) {
    return '$agentName 历史';
  }

  @override
  String get agentSettingsHistoryEmptyTitle => '暂无运行记录';

  @override
  String get agentSettingsHistoryEmptyMessage => '运行一次后，这里会显示本地历史。';

  @override
  String get agentSettingsRunning => '运行中';

  @override
  String get agentSettingsEnabled => '已启用';

  @override
  String get agentSettingsDisabled => '已停用';

  @override
  String get agentSettingsNotifications => '通知';

  @override
  String agentSettingsOverviewEnabled(int enabled, int total) {
    return '已启用 $enabled/$total';
  }

  @override
  String agentSettingsOverviewReady(int count) {
    return '可查看 $count';
  }

  @override
  String agentSettingsOverviewFailed(int count) {
    return '失败 $count';
  }

  @override
  String agentSettingsOverviewNotificationsOn(int count) {
    return '通知 $count';
  }

  @override
  String get agentQualityTitle => '近 30 天质量';

  @override
  String get agentQualityNoRuns => '此周期内暂无已完成运行';

  @override
  String agentQualityCompletedRuns(int count) {
    return '已完成 $count 次';
  }

  @override
  String agentQualityReadyRate(int percent, int count, int total) {
    return '有结果 $percent% · $count/$total';
  }

  @override
  String agentQualityNoFindingRate(int percent, int count, int total) {
    return '无发现 $percent% · $count/$total';
  }

  @override
  String agentQualityFailureRate(int percent, int count, int total) {
    return '失败 $percent% · $count/$total';
  }

  @override
  String agentQualitySuppressedRate(int percent, int count, int total) {
    return '隐藏或延后 $percent% · $count/$total';
  }

  @override
  String agentQualityEvidenceRate(int percent, int count, int total) {
    return '证据可达 $percent% · $count/$total';
  }

  @override
  String get agentQualityEvidenceNavigationNoSamples => '暂无证据打开样本';

  @override
  String agentQualityEvidenceNavigationRate(
    int percent,
    int successes,
    int attempts,
  ) {
    return '证据打开成功 $percent% · $successes/$attempts';
  }

  @override
  String get agentQualityPrivacyNote => '仅在设备本地汇总 · 不保留结果内容、证据 ID 或路由';

  @override
  String get agentSettingsNeverRun => '尚未运行';

  @override
  String agentSettingsLastRunAt(String date) {
    return '上次运行 $date';
  }

  @override
  String agentSettingsAroundTime(String time) {
    return '约 $time';
  }

  @override
  String agentSettingsEveryHours(int hours) {
    return '每 $hours 小时';
  }

  @override
  String get agentSettingsCadenceDaily => '每日';

  @override
  String get agentSettingsCadenceWeekly => '每周';

  @override
  String get agentSettingsCadenceMonthly => '每月';

  @override
  String get agentSettingsCadenceYearly => '每年';

  @override
  String agentSettingsRunFinished(String agentName) {
    return '$agentName 已完成';
  }

  @override
  String agentSettingsRunBusy(String agentName) {
    return '$agentName 正在运行';
  }

  @override
  String agentSettingsRunFailed(String error) {
    return '无法运行 Agent：$error';
  }

  @override
  String agentSettingsSaveFailed(String error) {
    return '无法更新 Agent 设置：$error';
  }

  @override
  String get agentSettingsMissingPresentationBadge => '缺少元数据';

  @override
  String get agentSettingsMissingPresentationDescription =>
      '这个 Agent 已注册，但缺少展示元数据。';

  @override
  String agentSettingsStatusWithDetail(String status, String detail) {
    return '$status · $detail';
  }

  @override
  String get agentSettingsTriggerManual => '手动';

  @override
  String get agentSettingsTriggerSchedule => '定时';

  @override
  String get agentSettingsTriggerBackgroundDue => '后台到期';

  @override
  String get agentSettingsTriggerCatchUp => '补跑';

  @override
  String get settingsAdvancedSection => '诊断';

  @override
  String get settingsAiModelsTitle => 'AI 模型';

  @override
  String get settingsAiModelsSubtitle => '下载与管理本地 AI 和语音模型';

  @override
  String get aiLlmRuntimeCheckTitle => 'Agent Runtime';

  @override
  String get aiLlmRuntimeCheckReady =>
      '通过 FRB 运行一次短的 active profile 回合，然后完成 native runtime step。';

  @override
  String get aiLlmRuntimeCheckNoProfile =>
      '请先保存并启用一个 provider profile，再检查 agent runtime。';

  @override
  String get aiLlmRuntimeCheckAction => '检查 runtime';

  @override
  String get aiLlmRuntimeCheckRunning => '检查中…';

  @override
  String get aiLlmRuntimeCheckPrompt =>
      '请用一句简短的话确认 NaviWealth agent runtime 可以访问。';

  @override
  String aiLlmRuntimeCheckSucceeded(String status) {
    return 'Agent runtime step 已完成：$status';
  }

  @override
  String aiLlmRuntimeCheckFailed(String error) {
    return 'Agent runtime 检查失败：$error';
  }

  @override
  String aiLlmRuntimeCheckStatus(String status) {
    return 'Native step：$status';
  }

  @override
  String get agentResultReviewAction => '查看';

  @override
  String get agentResultRetryAction => '重试';

  @override
  String get agentResultAskAction => '追问';

  @override
  String get agentResultLoadingBody => '正在检查当前页面的最新 Agent 结果。';

  @override
  String get agentResultKindBriefing => '简报';

  @override
  String get agentResultKindReview => '复盘';

  @override
  String get agentResultKindAlert => '提醒';

  @override
  String get agentResultKindReminder => '待办提醒';

  @override
  String get agentResultSeverityAttention => '需关注';

  @override
  String get agentResultSeverityWarning => '警告';

  @override
  String get agentRunStatusRunning => '运行中';

  @override
  String get agentRunStatusNoFinding => '无发现';

  @override
  String get agentRunStatusReady => '可查看';

  @override
  String get agentRunStatusFailed => '失败';

  @override
  String get agentResultInsightsSection => '洞察';

  @override
  String get agentResultEvidenceSection => '证据';

  @override
  String get agentResultEvidenceMethodSection => '依据与方法';

  @override
  String agentResultEvidenceCount(int count) {
    return '$count 项依据';
  }

  @override
  String get agentResultEvidenceAvailableBody => '查看这项依据对应的数据来源。';

  @override
  String agentResultEvidenceSupportCount(int count) {
    return '由 $count 项依据支持';
  }

  @override
  String get agentResultOpenRelatedPage => '查看相关页面';

  @override
  String get agentResultTechnicalDetailsTitle => '技术详情';

  @override
  String get agentResultTechnicalDetailsBody => '查看本次分析的运行步骤和工具活动。';

  @override
  String get agentResultTraceSection => '链路';

  @override
  String get agentResultTraceTitle => '运行 trace';

  @override
  String get agentResultTraceBody => '查看 AI 调用链路和工具活动。';

  @override
  String get agentResultTraceAction => '打开';

  @override
  String get agentResultActionsSection => '操作';

  @override
  String get agentResultAskFollowUpTitle => '问问 Agent';

  @override
  String get agentResultAskFollowUpBody => '解释这个结果与它使用的证据。';

  @override
  String get agentResultShowEvidenceTitle => '查看证据';

  @override
  String get agentResultShowEvidenceBody => '把证据对应到这份结果里的判断。';

  @override
  String get agentResultCreatePlanTitle => '制定计划';

  @override
  String get agentResultCreatePlanBody => '把这份结果转成建议的下一步。';

  @override
  String get agentResultSnoozeTitle => '稍后提醒';

  @override
  String get agentResultSnoozeBody => '把这份结果隐藏到明天。';

  @override
  String get agentResultSnoozeAction => '稍后';

  @override
  String get agentResultDismissTitle => '关闭';

  @override
  String get agentResultDismissBody => '从当前页面隐藏这份结果。';

  @override
  String get agentResultDismissAction => '关闭';

  @override
  String agentResultVisibilityActionFailed(String error) {
    return '无法更新这份结果：$error';
  }

  @override
  String get agentResultLocalMethodTitle => '结果生成方式';

  @override
  String get agentResultLocalMethodDeterministicBody => '基于本地领域数据，通过确定性规则计算。';

  @override
  String get agentResultLocalMethodAssistedBody => '在设备端结合本地领域数据生成，关键指标仍来自源数据。';

  @override
  String get agentResultLocalMethodSourceLabel => '数据来源';

  @override
  String get agentResultLocalMethodRuntimeLabel => '运行位置';

  @override
  String get agentResultLocalMethodRuntimeValue => '当前设备';

  @override
  String get agentResultMetricCurrent => '当前值';

  @override
  String get agentResultMetricBaseline => '基线';

  @override
  String get agentResultActionFallbackBody => '从这份 Agent 结果执行该操作。';

  @override
  String agentResultActionFallbackWithKey(String key) {
    return '操作键：$key';
  }

  @override
  String get agentPresentationWeeklyWealthReviewLabel => '每周财富复盘';

  @override
  String get agentPresentationWeeklyWealthReviewDescription =>
      '复盘净资产、配置集中度、价格新鲜度与汇率覆盖。';

  @override
  String get agentPresentationCashflowAnomalyReviewLabel => '现金流异常复盘';

  @override
  String get agentPresentationCashflowAnomalyReviewDescription =>
      '复盘端侧检测到的月度支出异常。';

  @override
  String get agentPresentationFirePlanDriftMonitorLabel => 'FIRE 计划漂移监控';

  @override
  String get agentPresentationFirePlanDriftMonitorDescription =>
      '复盘提款率、现金安全垫、计划 ETA 与压力测试漂移。';

  @override
  String get agentPresentationOptionsIncomeRiskReviewLabel => '期权收入风险复盘';

  @override
  String get agentPresentationOptionsIncomeRiskReviewDescription =>
      '复盘扫描时效、报价质量、标的集中度与合约风险。';

  @override
  String get agentPresentationMorningBriefingLabel => '早间简报';

  @override
  String get agentPresentationMorningBriefingDescription =>
      '基于最近的健康与财务信号生成每日简报。';

  @override
  String get agentPresentationRecoveryAlertLabel => '恢复提醒';

  @override
  String get agentPresentationRecoveryAlertDescription =>
      '标记短睡眠、低 HRV 和需要关注的恢复信号。';

  @override
  String get agentPresentationWeeklySummaryLabel => '每周总结';

  @override
  String get agentPresentationWeeklySummaryDescription => '复盘本周睡眠、活动、恢复与趋势证据。';

  @override
  String get agentPresentationKnowledgeReviewLabel => '知识复盘';

  @override
  String get agentPresentationKnowledgeReviewDescription =>
      '复盘到期 Decision 与长期未校验的 Assumption。';

  @override
  String get agentPresentationKnowledgeAssumptionLabel => '假设复核';

  @override
  String get agentPresentationKnowledgeAssumptionDescription => '找出需要重新校验的假设。';

  @override
  String get agentPresentationKnowledgeContradictionLabel => '矛盾复核';

  @override
  String get agentPresentationKnowledgeContradictionDescription =>
      '查找笔记、决策与假设之间的冲突。';

  @override
  String get agentPresentationKnowledgeInboxTriageLabel => 'Inbox 整理';

  @override
  String get agentPresentationKnowledgeInboxTriageDescription =>
      '找出需要分类或后续处理的捕获笔记。';

  @override
  String get agentPresentationKnowledgeRoutineLabel => 'Routine 到期';

  @override
  String get agentPresentationKnowledgeRoutineDescription =>
      '检查到期需要复盘的知识 Routine。';

  @override
  String get agentPresentationExecutionReviewLabel => '执行复盘';

  @override
  String get agentPresentationExecutionReviewDescription =>
      '复盘今日行动、阻塞事项、承诺与本周进展。';

  @override
  String aiLlmRuntimeProposalTitle(String kind) {
    return '待确认提案 · $kind';
  }

  @override
  String aiLlmRuntimeProposalWarning(String warning) {
    return '警告：$warning';
  }

  @override
  String get aiLlmRuntimeProposalApply => '应用提案';

  @override
  String get aiLlmRuntimeProposalApplying => '应用中…';

  @override
  String get aiLlmRuntimeProposalConfirmTitle => '应用这个提案？';

  @override
  String aiLlmRuntimeProposalConfirmBody(String summary) {
    return '$summary\n\n这会通过 AI Chat 相同的本地 proposal applier 写入。';
  }

  @override
  String aiLlmRuntimeProposalApplied(String status) {
    return '提案应用完成：$status';
  }

  @override
  String aiLlmRuntimeProposalStatus(String status) {
    return '提案应用：$status';
  }

  @override
  String aiLlmRuntimeProposalFailed(String error) {
    return '提案应用失败：$error';
  }

  @override
  String get settingsBadgeAuto => '自动';

  @override
  String get settingsBadgeCustom => '自定义';

  @override
  String get settingsDataTitle => '备份与恢复';

  @override
  String get settingsDataSubtitle => '导出或导入加密数据备份';

  @override
  String get settingsNotificationsTitle => '通知';

  @override
  String get settingsNotificationsSubtitle => '权限、Agent 提醒与 HealthOS 简报告警';

  @override
  String get settingsNotificationsMasterTitle => '允许应用通知';

  @override
  String get settingsNotificationsMasterSubtitle => '控制本地 Agent 通知和后台提醒任务。';

  @override
  String get settingsNotificationsHealthBriefingTitle => 'Morning Briefing';

  @override
  String settingsNotificationsHealthBriefingSubtitle(String hour) {
    return '大约 $hour:00 运行并推送 HealthOS 摘要。';
  }

  @override
  String get settingsNotificationsHealthBriefingBlockedSubtitle =>
      '开启应用通知后才会运行每日简报提醒。';

  @override
  String get settingsNotificationsPermissionChecking => '正在检查系统通知权限…';

  @override
  String get settingsNotificationsPermissionGranted => '系统通知已允许。';

  @override
  String get settingsNotificationsPermissionDenied => 'NaviWealth 的系统通知已关闭。';

  @override
  String get settingsNotificationsPermissionUnavailable => '当前平台不支持通知。';

  @override
  String settingsNotificationsPermissionFailed(String error) {
    return '读取通知权限失败：$error';
  }

  @override
  String get settingsNotificationsPermissionRequest => '启用';

  @override
  String get settingsNotificationsPermissionRequesting => '启用中…';

  @override
  String get settingsBiometricTitle => '生物识别解锁';

  @override
  String get settingsBiometricSubtitle => '打开 NaviWealth 时要求 Face ID 或指纹验证。';

  @override
  String get settingsBiometricChecking => '正在检查生物识别可用性…';

  @override
  String get settingsBiometricUnavailable => '当前设备不支持生物识别解锁。';

  @override
  String get settingsBiometricNotEnrolled => '请先在本机设置 Face ID 或指纹。';

  @override
  String get biometricUnlockTitle => 'NaviWealth 已锁定';

  @override
  String get biometricUnlockSubtitle => '使用本机生物识别解锁后继续。';

  @override
  String get biometricUnlockButton => '解锁';

  @override
  String get biometricUnlockChecking => '解锁中…';

  @override
  String get biometricUnlockFailed => '生物识别解锁失败。';

  @override
  String get biometricUnlockReason => '解锁 NaviWealth';

  @override
  String get settingsCrashReportingTitle => '崩溃报告';

  @override
  String get settingsCrashReportingSubtitle => '发送匿名错误报告以帮助修复问题。默认关闭。';

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
  String get settingsLogsCopiedToast => '日志已复制';

  @override
  String get settingsLogsClearTitle => '清空日志？';

  @override
  String get settingsLogsClearBody => '这会从当前设备移除内存中的诊断日志历史。';

  @override
  String get settingsLogsClearAction => '清空日志';

  @override
  String get settingsPerfTitle => '性能';

  @override
  String get settingsPerfSubtitle => '查看最近帧耗时与卡顿';

  @override
  String get settingsPerfRecentFrames => '最近帧数';

  @override
  String get settingsPerfJankFrames => '卡顿帧';

  @override
  String get settingsPerfFrameBudget => '帧预算';

  @override
  String get settingsPerfTimingTitle => '帧耗时';

  @override
  String get settingsPerfTotalP50 => '总耗时 p50';

  @override
  String get settingsPerfTotalP95 => '总耗时 p95';

  @override
  String get settingsPerfBuildP95 => '构建 p95';

  @override
  String get settingsPerfRasterP95 => '栅格 p95';

  @override
  String get settingsDomainsHealthEnabledSubtitle => 'AI 工具与 Memory 索引已启用';

  @override
  String get settingsDomainsHealthDisabledSubtitle => '打开后启用 AI 工具与 Memory 索引';

  @override
  String get settingsDomainsHealthTodaySubtitle => '查看今日恢复、指标与早间简报';

  @override
  String get settingsDomainsKnowledgeEnabledSubtitle =>
      'Inbox、Library、Review、AI 工具与 Memory 索引已启用';

  @override
  String get settingsDomainsKnowledgeDisabledSubtitle => '个人决策与认知演化记忆库';

  @override
  String get settingsDomainsKnowledgeInboxSubtitle => '捕获笔记、写决策、查看资料库与复盘';

  @override
  String get settingsDomainsKnowledgeLibrarySubtitle =>
      '浏览 Decision、Assumption、Routine、Concept 与 Note';

  @override
  String get settingsDomainsKnowledgeReviewSubtitle =>
      '复盘到期 Decision、过期 Assumption 与到期 Routine';

  @override
  String get settingsDomainsKnowledgeMemoryTitle => 'KnowledgeOS Memory';

  @override
  String get settingsDomainsKnowledgeMemorySubtitle => '管理用于召回、查重与语义搜索的本地模型';

  @override
  String get settingsDomainsHealthPermissionDenied =>
      '权限被拒绝 — 在系统 Health 设置里再试';

  @override
  String get settingsDomainsHealthSyncRunning => '正在拉取…';

  @override
  String get settingsDomainsHealthSyncIdle => '从系统健康平台拉取最近 30 天数据';

  @override
  String get settingsDomainsHealthSyncFailed => '上次同步失败';

  @override
  String settingsDomainsHealthSyncSummary(
    int upserted,
    int unchanged,
    int total,
  ) {
    return '上次同步：$upserted 新写入 / $unchanged 未变 · 拉取 $total 项';
  }

  @override
  String get settingsDomainsHealthSyncTitle => '同步健康数据';

  @override
  String get settingsDomainsBriefingTimeHelp => 'Morning Briefing 时间';

  @override
  String get settingsDomainsBriefingTimeTitle => 'Briefing 时间';

  @override
  String settingsDomainsBriefingTimeSubtitle(String hour) {
    return '每日大约 $hour:00 触发（后台调度窗口浮动）';
  }

  @override
  String get settingsAiModelsCheckingRuntime => '正在检查下次启动的 embedder 路径…';

  @override
  String settingsAiModelsRuntimeCheckFailed(String error) {
    return 'embedder 路径检查失败：$error';
  }

  @override
  String get settingsAiModelsRuntimeReady => '下次启动将加载 Rust EmbeddingGemma';

  @override
  String get settingsAiModelsRuntimeStub => '下次启动仍会使用 stub embedder';

  @override
  String get settingsAiModelsModelLabel => '模型';

  @override
  String get settingsAiModelsModelMissing => '缺失：EmbeddingGemma model dir';

  @override
  String get settingsAiModelsOrtMissing => '缺失：ONNX Runtime dylib';

  @override
  String get settingsAiModelsNativeLibLabel => 'native lib';

  @override
  String get settingsAiModelsNativeLibPlatform => '由平台插件加载';

  @override
  String get settingsAiModelsInstalledSource => '已安装';

  @override
  String get settingsAiModelsMissingSource => '缺失';

  @override
  String get settingsAiModelsHint =>
      '模型文件仅保存在本机，不会上传。EmbeddingGemma 用于本地记忆检索；Zipformer 用于普通话实时语音输入。ONNX Runtime 已随应用构建，无需单独管理。';

  @override
  String get settingsAiModelsFootnote =>
      '语音模型下载后可在下一次点击麦克风时直接使用。EmbeddingGemma 下载后需重启应用，已有记忆会在下次索引周期自动重新生成向量，原始记录保持不变。';

  @override
  String settingsAiModelsStateLoadFailed(String error) {
    return '加载状态失败：$error';
  }

  @override
  String get settingsAiModelsStatusInstalled => '已安装';

  @override
  String get settingsAiModelsStatusDownloading => '下载中…';

  @override
  String get settingsAiModelsStatusFailed => '失败';

  @override
  String get settingsAiModelsStatusNotInstalled => '未安装';

  @override
  String get settingsAiModelsCancel => '取消';

  @override
  String get settingsAiModelsDelete => '删除';

  @override
  String get settingsAiModelsRedownload => '重新下载';

  @override
  String get settingsAiModelsDownload => '下载';

  @override
  String get settingsAiModelsDeleteTitle => '删除模型？';

  @override
  String get settingsAiModelsDeleteBody =>
      '删除后，对应的端侧能力将不可用或回退到轻量实现。重新启用需要再次联网下载。';

  @override
  String get settingsAiModelsActiveRuntimeTitle => '当前运行的 embedder';

  @override
  String get settingsAiModelsActiveRuntimeLoading => '正在检查当前运行的 embedder…';

  @override
  String settingsAiModelsActiveRuntimeFailed(String error) {
    return '当前 embedder 检查失败：$error';
  }

  @override
  String get settingsAiModelsActiveRuntimeNative => 'Native';

  @override
  String get settingsAiModelsActiveRuntimeStub => 'Stub';

  @override
  String get settingsAiModelsActiveRuntimeUnknown => '不可用';

  @override
  String get settingsAiModelsFingerprintLabel => 'fingerprint';

  @override
  String get settingsAiModelsDimensionLabel => '维度';

  @override
  String get settingsAiModelsMemoryRowsLabel => '记忆';

  @override
  String get settingsAiModelsVectorRowsLabel => '向量';

  @override
  String get settingsAiModelsCurrentVectorsLabel => '当前';

  @override
  String get settingsAiModelsStaleVectorsLabel => '过期';

  @override
  String get settingsAiModelsEventsLabel => '事件';

  @override
  String get settingsAiModelsSourcesTitle => '已索引来源';

  @override
  String get settingsAiModelsNoSources => '还没有索引任何记忆来源。';

  @override
  String get settingsAiModelsStaleVectorsHint =>
      '部分向量由其他 embedder fingerprint 生成，会在下次 indexer 周期刷新。';

  @override
  String get knowledgeAiSuggestionsTitle => 'AI 建议';

  @override
  String knowledgeAiSuggestionsTitleWithCount(int count) {
    return 'AI 建议（$count）';
  }

  @override
  String knowledgeAiSuggestionsSubtitle(Object count) {
    return '$count 条待处理建议，来自收件箱 Note 的端侧 triage。';
  }

  @override
  String get knowledgeAiSuggestionsEmpty =>
      '当前无待处理的 AI 建议。新写的 Note 会在 15 分钟内被 triage。';

  @override
  String knowledgeAiSuggestionCount(Object count) {
    return '$count 条';
  }

  @override
  String get knowledgeAiSuggestionKindClassification => '分类';

  @override
  String get knowledgeAiSuggestionKindTags => '标签';

  @override
  String get knowledgeAiSuggestionKindLinkToDecision => '关联决策';

  @override
  String get knowledgeAiSuggestionDetails => '详情';

  @override
  String get knowledgeAiSuggestionHideDetails => '收起详情';

  @override
  String get knowledgeAiSuggestionAccept => '接受建议';

  @override
  String get knowledgeAiSuggestionDismiss => '忽略建议';

  @override
  String get knowledgeAiSuggestionPayloadTitle => '建议字段';

  @override
  String get knowledgeAiSuggestionSnoozeOneDay => '明天提醒';

  @override
  String get knowledgeAiSuggestionSnoozedToast => '这条建议会在明天重新出现。';

  @override
  String get knowledgeAiSuggestionAppliedToast => '建议已应用到笔记。';

  @override
  String get knowledgeAiSuggestionFeedbackLabel => '这条建议有帮助吗？';

  @override
  String get knowledgeAiSuggestionFeedbackGood => '有帮助';

  @override
  String get knowledgeAiSuggestionFeedbackBad => '没帮助';

  @override
  String get knowledgeAiSuggestionFeedbackToast => '反馈已保存。';

  @override
  String get knowledgeAgentAssumptionTitle => '本月待校验假设';

  @override
  String get knowledgeAgentAssumptionNoStale => '暂无长期未校验的 active 假设。';

  @override
  String knowledgeAgentAssumptionSummaryOne(Object days, Object first) {
    return '1 条 active 假设超过 $days 天未校验：$first';
  }

  @override
  String knowledgeAgentAssumptionSummaryMany(
    Object count,
    Object days,
    Object first,
  ) {
    return '$count 条 active 假设超过 $days 天未校验，首条：$first';
  }

  @override
  String get knowledgeAgentReviewTitle => '本周复盘';

  @override
  String get knowledgeAgentReviewNothingDue => '本周暂无待复盘事项。';

  @override
  String knowledgeAgentReviewDecisionOne(Object first) {
    return '1 个 Decision 到期可复盘：$first';
  }

  @override
  String knowledgeAgentReviewDecisionMany(Object count, Object first) {
    return '$count 个 Decision 到期可复盘，首条：$first';
  }

  @override
  String knowledgeAgentReviewAssumptionOne(Object days, Object first) {
    return '1 条假设超过 $days 天未校验：$first';
  }

  @override
  String knowledgeAgentReviewAssumptionMany(
    Object count,
    Object days,
    Object first,
  ) {
    return '$count 条假设超过 $days 天未校验，首条：$first';
  }

  @override
  String get knowledgeAgentRoutineTitle => '本周到期的 Routine';

  @override
  String knowledgeAgentRoutineNoneDue(Object days) {
    return '未来 $days 天内暂无到期 Routine。';
  }

  @override
  String knowledgeAgentRoutineLeadOverdue(Object days, Object statement) {
    return '$statement（已逾期 $days 天）';
  }

  @override
  String knowledgeAgentRoutineLeadToday(Object statement) {
    return '$statement（今日到期）';
  }

  @override
  String knowledgeAgentRoutineLeadUpcoming(Object days, Object statement) {
    return '$statement（$days 天后到期）';
  }

  @override
  String knowledgeAgentRoutineSummaryMixed(
    Object first,
    Object overdueCount,
    Object upcomingCount,
  ) {
    return '$overdueCount 条已逾期 + $upcomingCount 条本周到期，首条：$first';
  }

  @override
  String knowledgeAgentRoutineSummaryOverdueOne(Object first) {
    return '1 条 Routine 已逾期：$first';
  }

  @override
  String knowledgeAgentRoutineSummaryOverdueMany(Object count, Object first) {
    return '$count 条 Routine 已逾期，首条：$first';
  }

  @override
  String knowledgeAgentRoutineSummaryUpcomingOne(Object first) {
    return '1 条 Routine 本周到期：$first';
  }

  @override
  String knowledgeAgentRoutineSummaryUpcomingMany(Object count, Object first) {
    return '$count 条 Routine 本周到期，首条：$first';
  }

  @override
  String get knowledgeAgentContradictionTitle => '检测到 Decision 冲突';

  @override
  String get knowledgeAgentContradictionNone => '过去 90 天未检测到冲突。';

  @override
  String knowledgeAgentContradictionInvalidatedAssumption(Object assumptionId) {
    return '这个 Decision 仍引用 assumption $assumptionId，但该假设当前不在 active 集合（可能已 falsified / retired）。';
  }

  @override
  String knowledgeAgentContradictionSummaryOne(Object detail, Object kind) {
    return '检出 1 处 $kind：$detail';
  }

  @override
  String knowledgeAgentContradictionSummaryMany(
    Object count,
    Object detail,
    Object kind,
  ) {
    return '检出 $count 处冲突，首条：$kind → $detail';
  }

  @override
  String knowledgeLoadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String knowledgeNoteDeleted(String noteId) {
    return 'Note $noteId 已删除';
  }

  @override
  String get knowledgeUntitled => '无标题';

  @override
  String get knowledgeMarkdownEdit => '编辑';

  @override
  String get knowledgeMarkdownPreview => '预览';

  @override
  String get knowledgeMarkdownPreviewEmpty => '暂无内容预览。切回编辑模式输入。';

  @override
  String get knowledgeDecisionNotFound => 'Decision 不存在或已删除';

  @override
  String get knowledgeDecisionDetailTitle => '决策详情';

  @override
  String knowledgeDecisionDecidedAt(Object date) {
    return '决策于 $date';
  }

  @override
  String knowledgeDecisionDecidedAtWithReview(
    Object decidedDate,
    Object reviewDate,
  ) {
    return '决策于 $decidedDate · 复盘 $reviewDate';
  }

  @override
  String get knowledgeNoteDetailTitle => '笔记';

  @override
  String get knowledgeNoteEditTitle => '编辑笔记';

  @override
  String get knowledgeNoteEditSubtitle => '修改标题、内容和元数据。';

  @override
  String get knowledgeNoteSourceUrlLabel => '来源链接';

  @override
  String get knowledgeNoteTagsHint => '\"投资\", \"fire\", \"银行卡\"';

  @override
  String get knowledgeNoteProjectHint => '\"fire计划\", \"健康2026\"';

  @override
  String get knowledgeConceptDetailTitle => '概念';

  @override
  String get knowledgeExperimentDetailTitle => '实验';

  @override
  String get knowledgePrincipleDetailTitle => '原则';

  @override
  String get knowledgeAssumptionDetailTitle => '假设';

  @override
  String get knowledgeRoutineDetailTitle => '例行事项';

  @override
  String get knowledgeObjectDetailTitle => '详情';

  @override
  String get knowledgeDetailOptionsTitle => '选项';

  @override
  String get knowledgeDetailMetadataTitle => '元数据';

  @override
  String get knowledgeDetailRationaleTitle => '理由';

  @override
  String get knowledgeDetailPrinciplesTitle => '引用的 Principle';

  @override
  String get knowledgeDetailAssumptionsTitle => '引用的 Assumption';

  @override
  String get knowledgeDetailActualOutcomeTitle => '实际结果';

  @override
  String get knowledgeDetailExpectedOutcomeTitle => '预期结果';

  @override
  String get knowledgeDetailMetricsTitle => '指标';

  @override
  String get knowledgeDetailEvolutionTitle => '认知演化链';

  @override
  String get knowledgeDetailSummaryTitle => '摘要';

  @override
  String get knowledgeDetailRelatedConceptsTitle => '相关概念';

  @override
  String get knowledgeDetailMethodTitle => '方法';

  @override
  String get knowledgeDetailResultTitle => '结果';

  @override
  String get knowledgeDetailConclusionTitle => '结论';

  @override
  String get knowledgeDetailEvidenceTitle => '证据';

  @override
  String get knowledgeDetailBodyTitle => '正文';

  @override
  String get knowledgeDetailSourceTitle => '来源';

  @override
  String knowledgeDetailAliases(Object aliases) {
    return '别名：$aliases';
  }

  @override
  String knowledgeDetailRelatedConceptCount(Object count) {
    return '$count 个关联';
  }

  @override
  String knowledgeDetailEvidenceCount(Object count) {
    return '$count 条引用';
  }

  @override
  String knowledgeDetailScope(Object scope) {
    return '范围：$scope';
  }

  @override
  String knowledgeDetailConfidenceScope(Object confidence, Object scope) {
    return '置信度 $confidence · 范围 $scope';
  }

  @override
  String get knowledgeDetailContextSnapshotTitle => '当时的跨域状态';

  @override
  String knowledgeDetailContextSnapshotCaptured(Object date, Object days) {
    return '采样于 $date · $days 天窗口';
  }

  @override
  String get knowledgeDetailContextSnapshotEmpty => '当时窗口内无跨域事件。';

  @override
  String get knowledgeDetailContextSnapshotFinance => '财务';

  @override
  String get knowledgeDetailContextSnapshotHealth => '健康';

  @override
  String get knowledgeDetailCreatedLabel => '创建';

  @override
  String get knowledgeDetailUpdatedLabel => '更新';

  @override
  String knowledgeDetailUpdatedAt(Object date) {
    return '更新于 $date';
  }

  @override
  String get knowledgeDetailProjectLabel => '项目';

  @override
  String get knowledgeDetailTagsLabel => '标签';

  @override
  String get knowledgeDetailAliasesLabel => '别名';

  @override
  String get knowledgeDetailStartedLabel => '开始';

  @override
  String get knowledgeDetailEndedLabel => '结束';

  @override
  String get knowledgeDetailNextDueLabel => '下次到期';

  @override
  String get knowledgeDetailLastDoneLabel => '上次完成';

  @override
  String get knowledgeDetailIntervalLabel => '周期';

  @override
  String get knowledgeDetailTargetAssumptionTitle => '目标 Assumption';

  @override
  String get knowledgeDetailScopeLabel => '范围';

  @override
  String get knowledgeDetailDeclaredLabel => '声明';

  @override
  String get knowledgeDetailConfidenceLabel => '置信度';

  @override
  String get knowledgeDetailLastVerifiedLabel => '上次验证';

  @override
  String get knowledgeDetailDecisionsTitle => '相关 Decision';

  @override
  String get knowledgeDetailExperimentsTitle => '相关 Experiment';

  @override
  String get knowledgeLibraryDeleteTooltip => '删除';

  @override
  String get knowledgeLibraryDeleteTitle => '删除条目？';

  @override
  String knowledgeLibraryDeleteBody(Object title) {
    return '“$title” 会从资料库移除，并在下次索引同步后从 AI 记忆中清理。';
  }

  @override
  String get knowledgeObjectNotFound => '条目不存在或已删除';

  @override
  String get knowledgeDeletedToast => '已删除';

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
  String get transferSwapAccountsAction => '交换账户';

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
  String get transferDateLabel => '日期时间';

  @override
  String get transferDetailsTitle => '日期与备注';

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
  String get expenseReportOtherCategories => '其他';

  @override
  String expenseReportOtherCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个类目',
    );
    return '$_temp0';
  }

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
  String expenseListSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择 $count 笔交易',
    );
    return '$_temp0';
  }

  @override
  String get expenseListClearSelection => '清除选择';

  @override
  String get expenseListExplainSelected => '解读所选';

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
  String get manualAssetDetailEditAction => '编辑资产';

  @override
  String get manualAssetDetailCurrentValue => '当前价值';

  @override
  String get manualAssetDetailAccount => '持有账户';

  @override
  String get manualAssetDetailPrincipal => '本金';

  @override
  String get manualAssetDetailAnnualRate => '年利率';

  @override
  String get manualAssetDetailExpectedReturn => '预期年化收益';

  @override
  String get manualAssetDetailStartDate => '起息日';

  @override
  String get manualAssetDetailMaturityDate => '到期日';

  @override
  String get manualAssetDetailIssuer => '发行机构';

  @override
  String get manualAssetDetailProductCode => '产品代码';

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
  String get assetDetailLastClose => '最新收盘价';

  @override
  String get assetDetailValuationPrice => '估值单价';

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
  String get depositDetailsTitle => '日期与估值';

  @override
  String get depositDetailsTermSummary => '到期日、续存与当前价值';

  @override
  String get depositDetailsDemandSummary => '起息日与当前价值';

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
  String get wealthProductDetailsTitle => '产品详情';

  @override
  String get wealthProductDetailsSummary => '发行机构、日期与当前价值';

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
  String get localSecuritiesMarketLabel => '市场';

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
  String get activityAddAction => '记一笔';

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
  String get syncStatusConflictsHeader => '冲突诊断';

  @override
  String syncStatusConflictsLocalWins(int n) {
    return '$n 条远端行旧于本地状态';
  }

  @override
  String syncStatusConflictsIgnored(int n) {
    return '$n 条远端行因命名空间不支持而被忽略';
  }

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
  String get syncStatusDetailRemoteRows => '远端行';

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
  String get syncStabilityPassing => '稳定性门禁已通过';

  @override
  String get syncStabilityFailing => '同步稳定性需要处理';

  @override
  String get syncStabilityCollecting => '正在积累稳定性证据';

  @override
  String syncStabilityWindow(int successful, int total, int days) {
    return '成功 $successful/$total · 已观察 $days 天';
  }

  @override
  String syncStabilitySuccessRate(int percent) {
    return '成功率 $percent%';
  }

  @override
  String syncStabilityFatal(int count) {
    return '致命错误 $count';
  }

  @override
  String syncStabilityResetFailures(int count) {
    return '重置失败 $count';
  }

  @override
  String syncStabilityRecoveries(int count) {
    return '恢复成功 $count';
  }

  @override
  String get syncStabilityPassingDetail => '当前已满足全部本地发布门槛';

  @override
  String syncStabilityNeedSamples(int count) {
    return '还需 $count 个终态同步周期';
  }

  @override
  String syncStabilityNeedDuration(int days) {
    return '还需观察 $days 天';
  }

  @override
  String syncStabilityBelowSuccess(int percent) {
    return '成功率需至少达到 $percent%';
  }

  @override
  String get syncStabilityFatalBlocker => '致命协议错误必须归零';

  @override
  String get syncStabilityResetBlocker => '代际重置失败必须归零';

  @override
  String get syncStabilityPrivacyNote => '仅设备本地汇总 · 不保留行数据或 ID';

  @override
  String get syncStabilityCopyEvidence => '复制证据';

  @override
  String get syncStabilityEvidenceCopied => '同步稳定性证据已复制。';

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
  String get ingestExpenseAccountLabel => '账单账户';

  @override
  String ingestConfirmAllFresh(int count) {
    return '全部确认 · 仅新增（$count）';
  }

  @override
  String get ingestSelectAccountFirst => '请先选择账单账户';

  @override
  String get ingestServiceNotReady => '服务尚未就绪';

  @override
  String get ingestRecorded => '已记录';

  @override
  String ingestRecordedN(int count) {
    return '已记录 $count 笔';
  }

  @override
  String ingestRecordedPartial(int success, int failed) {
    return '已记录 $success 笔，$failed 笔需要处理';
  }

  @override
  String ingestRecordingProgress(int completed, int total) {
    return '正在记录第 $completed/$total 笔。';
  }

  @override
  String get ingestRecordFailed => '暂时无法记录，请重试。';

  @override
  String get ingestRecordNeedsReview => '此记录可能已写入，请先修复待确认状态，再执行其他操作。';

  @override
  String get ingestNeedsReviewHint => '此记录可能已出现在流水中，请修复待确认状态，不要重复记录。';

  @override
  String get ingestRecoveryUnavailableHint => '此记录可能已出现在流水中，但恢复信息不可用，已阻止重复记录。';

  @override
  String get ingestResolveAction => '修复待确认状态';

  @override
  String get ingestResolvingTitle => '正在修复待确认状态';

  @override
  String get ingestResolvingBody => '仅完成待确认状态，不会再次写入记录。';

  @override
  String get ingestResolveSucceeded => '待确认状态已修复';

  @override
  String get ingestResolveFailed => '暂时无法修复，请先检查流水后再重试。';

  @override
  String get ingestSkipped => '已跳过此记录';

  @override
  String get ingestSkipFailed => '暂时无法跳过，请重试。';

  @override
  String get ingestRestored => '记录已恢复';

  @override
  String get ingestUndoSucceeded => '记录已恢复至待确认';

  @override
  String get ingestUndoingTitle => '正在恢复记录';

  @override
  String get ingestUndoFailed => '部分记录未能撤销，请检查剩余记录。';

  @override
  String ingestUndoProgress(int completed, int total) {
    return '正在恢复第 $completed/$total 笔。';
  }

  @override
  String get ingestPasteTitle => '粘贴账单文本';

  @override
  String get ingestPasteHint =>
      '粘贴支付宝 / 微信 / 银行 CSV 账单文本\n例如：2026-05-10,星巴克,-38.00,CNY';

  @override
  String get ingestPasteRequired => '请先粘贴账单文本再解析。';

  @override
  String get ingestParseAction => '解析';

  @override
  String get ingestParseFailed => '暂时无法解析导入内容，请重试。';

  @override
  String get ingestCaptureFailed => '暂时无法读取此来源，请重试。';

  @override
  String get ingestCaptureUnsupported => '暂不支持此文件类型。';

  @override
  String get ingestCaptureEmpty => '此来源没有可导入的内容。';

  @override
  String ingestCaptureTooLarge(int maxMiB) {
    return '文件超过 $maxMiB MiB 的导入上限。';
  }

  @override
  String ingestCaptureTextTooLong(int maxCharacters) {
    return '文本超过 $maxCharacters 字符的导入上限。';
  }

  @override
  String get ingestCaptureUnreadable => '无法读取此来源，请重新选择。';

  @override
  String get ingestChooseAnotherFile => '重新选择';

  @override
  String get ingestRetakePhoto => '重新拍摄';

  @override
  String ingestDroppedSourcesRejected(int count) {
    return '有 $count 个拖入文件无法导入。';
  }

  @override
  String get ingestSharedParseRejected => '无法解析此共享来源。';

  @override
  String get ingestSharedParseFailed => '共享导入被意外中断。';

  @override
  String get ingestNoTransactions => '未解析出可识别的交易';

  @override
  String ingestParseSummary(int total, int fresh, int dup) {
    return '解析 $total 笔（新增 $fresh · 疑似重复 $dup）';
  }

  @override
  String ingestParseSummaryWithSkipped(
    int total,
    int fresh,
    int dup,
    int skipped,
  ) {
    return '解析 $total 笔（新增 $fresh · 疑似重复 $dup · 跳过 $skipped）';
  }

  @override
  String get ingestProcessingTitle => '正在解析导入内容';

  @override
  String ingestProcessingBody(String source) {
    return '正在读取 $source，提取支出并与本地流水、待确认导入去重。';
  }

  @override
  String get ingestRecordingTitle => '正在入账';

  @override
  String get ingestRecordingBody => '正在写入已确认记录，并刷新待确认队列。';

  @override
  String get ingestSourceCsv => 'CSV 文件';

  @override
  String get ingestSourcePaste => '粘贴文本';

  @override
  String get ingestSourceImage => '票据图片';

  @override
  String get ingestSourcePdf => 'PDF 账单';

  @override
  String get ingestSourceEmail => '邮件';

  @override
  String ingestDraftConfidence(int percent) {
    return '置信度 $percent%';
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
  String get ingestEmptyBody =>
      '可定期导入支付宝、微信或银行 CSV / 文本账单，\n重叠账期会先标记重复，再由你确认入账。';

  @override
  String get ingestPasteAction => '粘贴文本';

  @override
  String get ingestImportFileAction => '导入文件';

  @override
  String get ingestCameraAction => '拍照';

  @override
  String get ingestCaptureMenuAction => '添加来源';

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
  String get aiLlmDeleteTitle => '删除 Provider？';

  @override
  String aiLlmDeleteBody(String name) {
    return '这会从此设备移除 $name 及其已保存的 API Key。';
  }

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
      '自带 Key 的端侧 AI 在原生平台（iOS / Android / macOS / Windows / Linux）可用（需要系统级安全存储）。Web 暂不运行本地 AI runtime。';

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
  String get watchlistTitle => '自选清单';

  @override
  String get watchlistAccountsEntrySubtitle => '跟踪标的并设置本地价格告警';

  @override
  String get watchlistAddAction => '添加标的';

  @override
  String get watchlistAddTitle => '添加到自选';

  @override
  String watchlistEditAlertTitle(String symbol) {
    return '$symbol 告警';
  }

  @override
  String get watchlistEmptyTitle => '暂无自选标的';

  @override
  String get watchlistEmptyBody => '添加代码后会优先读取缓存价格，并在当前页打开时轮询触发阈值告警。';

  @override
  String get watchlistSymbolField => '代码';

  @override
  String get watchlistMarketField => '市场';

  @override
  String get watchlistAlertAboveField => '高于此价告警';

  @override
  String get watchlistAlertBelowField => '低于此价告警';

  @override
  String get watchlistSaveAlertsAction => '保存告警';

  @override
  String get watchlistEditAlertsAction => '告警';

  @override
  String get watchlistRemoveAction => '移除';

  @override
  String get watchlistPriceUnavailable => '暂无价格';

  @override
  String get watchlistFreshnessLive => '实时';

  @override
  String get watchlistFreshnessCache => '缓存';

  @override
  String get watchlistFreshnessStale => '旧缓存';

  @override
  String watchlistAlertAboveChip(String price) {
    return '高于 $price';
  }

  @override
  String watchlistAlertBelowChip(String price) {
    return '低于 $price';
  }

  @override
  String watchlistAlertTriggeredAbove(String symbol, String price) {
    return '$symbol 当前 $price，已高于告警价';
  }

  @override
  String watchlistAlertTriggeredBelow(String symbol, String price) {
    return '$symbol 当前 $price，已低于告警价';
  }

  @override
  String get watchlistSymbolRequired => '请输入代码';

  @override
  String get watchlistInvalidNumber => '请输入大于 0 的价格';

  @override
  String get watchlistMarketCnA => 'A 股';

  @override
  String get watchlistMarketHkStock => '港股';

  @override
  String get watchlistMarketUsStock => '美股';

  @override
  String get watchlistMarketCrypto => '加密货币';

  @override
  String get watchlistMarketFx => '外汇';

  @override
  String get watchlistMarketUnknown => '未知';

  @override
  String get masterDetailBackToList => '返回列表';

  @override
  String get incomePlannerTitle => '期权现金流';

  @override
  String get incomePlannerAccountsEntrySubtitle => '扫描卖看跌 / 备兑看涨 现金流机会';

  @override
  String get commandKeywordOptionsCn => '期权';

  @override
  String get commandKeywordSellPutCn => '卖看跌';

  @override
  String get commandKeywordCoveredCallCn => '备兑';

  @override
  String get incomePlannerUnsupportedOnWeb => '期权现金流仅在移动端可用。';

  @override
  String get incomePlannerOccTitle => '期权风险披露';

  @override
  String get incomePlannerOccSubtitle => '使用前请阅读';

  @override
  String get incomePlannerOccBody =>
      '卖出现金担保看跌(sell put)与备兑看涨(covered call)同时存在已知与未知风险。被行权时,卖看跌可能要求你以 strike 价买入 100 股;备兑看涨会让你失去 strike 以上的全部上涨。Income Planner 只筛选符合你已声明风险偏好的机会 —— 不预测价格,也不下达任何订单。继续即表示你已阅读 OCC《Characteristics and Risks of Standardized Options》。';

  @override
  String get incomePlannerOccAccept => '我已阅读并接受';

  @override
  String get incomePlannerOccCancel => '暂不';

  @override
  String get incomePlannerOccLearnMore => '打开 OCC ODD';

  @override
  String get incomePlannerStartTitle => '设置你的策略偏好';

  @override
  String get incomePlannerStartBody =>
      '告诉 Income Planner 你愿意采用的策略与风险水平,然后批准你愿意持有或卖出的标的。';

  @override
  String get incomePlannerStartCta => '配置偏好';

  @override
  String get incomePlannerNoApprovedTitle => '暂无已批准标的';

  @override
  String get incomePlannerNoApprovedBody =>
      '添加你愿意长期持有(用于卖看跌)或愿意在更高价卖出(用于备兑看涨)的股票或 ETF。Income Planner 只扫描清单内的标的。';

  @override
  String get incomePlannerAddApprovedCta => '添加标的';

  @override
  String get incomePlannerProfileTitle => '偏好设置';

  @override
  String get incomePlannerProfileMode => '风险模式';

  @override
  String get incomePlannerProfileModeConservative => '保守';

  @override
  String get incomePlannerProfileModeBalanced => '平衡';

  @override
  String get incomePlannerProfileModeAggressive => '激进';

  @override
  String get incomePlannerProfileModeCustom => '自定义';

  @override
  String get incomePlannerProfileAvoidEarnings => '跳过 7 天内有业绩公告的候选';

  @override
  String get incomePlannerProfileAvoidMacroEvents => '跳过 7 天内有 CPI / FOMC 的候选';

  @override
  String get incomePlannerProfileOnlyApproved => '仅扫描已批准清单内的标的(推荐)';

  @override
  String get incomePlannerProfileAllowedStrategies => '策略';

  @override
  String get incomePlannerProfileAllowPut => '卖看跌(现金担保)';

  @override
  String get incomePlannerProfileAllowCall => '备兑看涨';

  @override
  String get incomePlannerProfileAdvancedFilters => '高级筛选';

  @override
  String get incomePlannerProfileMinDte => '最小 DTE';

  @override
  String get incomePlannerProfileMaxDte => '最大 DTE';

  @override
  String get incomePlannerProfileMinYield => '最低年化收益';

  @override
  String get incomePlannerProfileMinOpenInterest => '最低未平仓量';

  @override
  String get incomePlannerProfileMinVolume => '最低成交量';

  @override
  String get incomePlannerProfileMaxSpread => '最大价差';

  @override
  String get incomePlannerProfileMaxCapitalPerTrade => '单笔最大资金占用';

  @override
  String get incomePlannerProfilePercentHelper => '输入百分数,例如 12 表示 12%。';

  @override
  String get incomePlannerProfileValidationNumber => '请输入有效数字。';

  @override
  String incomePlannerProfileValidationRange(int min, int max) {
    return '请输入 $min 到 $max 之间的值。';
  }

  @override
  String get incomePlannerProfileValidationDteOrder => '最大 DTE 必须大于或等于最小 DTE。';

  @override
  String get incomePlannerProfileSave => '保存';

  @override
  String get incomePlannerProfileCancel => '取消';

  @override
  String get incomePlannerAddUnderlyingTitle => '添加已批准标的';

  @override
  String get incomePlannerEditUnderlyingTitle => '编辑标的';

  @override
  String get incomePlannerSymbolLabel => '代码';

  @override
  String get incomePlannerSymbolHint => 'AAPL';

  @override
  String get incomePlannerMarketLabel => '市场';

  @override
  String get incomePlannerAllowPutLabel => '允许卖看跌(现金担保)';

  @override
  String get incomePlannerAllowCallLabel => '允许备兑看涨';

  @override
  String get incomePlannerSaveAction => '保存';

  @override
  String get incomePlannerDeleteAction => '删除';

  @override
  String get incomePlannerCancelAction => '取消';

  @override
  String get incomePlannerApprovedSectionTitle => '已批准标的';

  @override
  String get incomePlannerOpportunitiesSectionTitle => '机会';

  @override
  String get incomePlannerOpportunitiesEmpty => '暂无缓存机会。点击 \"刷新机会\" 扫描你的已批准标的。';

  @override
  String get incomePlannerRefreshAction => '刷新机会';

  @override
  String get incomePlannerRefreshRunning => '扫描中…';

  @override
  String get incomePlannerRefreshFailedTitle => '扫描失败';

  @override
  String get incomePlannerRefreshUniverseEmpty =>
      '没有可扫描的标的。请至少添加一个启用 put/call 的已批准标的,或确认 covered call 标的持仓 ≥ 100 股。';

  @override
  String get incomePlannerLastScanLabel => '上次扫描';

  @override
  String get incomePlannerLastScanStale => '缓存数据已超过 24 小时 —— 刷新以获取最新数据。';

  @override
  String get incomePlannerOpportunitiesAllRejected =>
      '本次扫描没有候选通过你的硬条件。请放宽偏好(如降低收益下限、扩大 DTE 窗口)后重试。';

  @override
  String get incomePlannerNoMatchesTitle => '本次没有符合条件的机会';

  @override
  String get incomePlannerScanNoMatchesToast => '扫描完成:没有机会符合当前筛选条件。';

  @override
  String incomePlannerScanSummary(int symbols, int rejected, int errors) {
    return '已扫描 $symbols 个标的 · 拒绝 $rejected 张合约 · $errors 个抓取错误';
  }

  @override
  String get incomePlannerChipCashSecuredPut => '卖看跌';

  @override
  String get incomePlannerChipCoveredCall => '备兑看涨';

  @override
  String get incomePlannerRiskLow => '低风险';

  @override
  String get incomePlannerRiskModerate => '中等';

  @override
  String get incomePlannerRiskElevated => '偏高';

  @override
  String get incomePlannerMetricAnnualized => '年化';

  @override
  String get incomePlannerMetricCash => '占用现金';

  @override
  String get incomePlannerMetricBreakeven => '盈亏平衡';

  @override
  String get incomePlannerMetricDte => '到期天数';

  @override
  String get incomePlannerMetricStrike => '行权价';

  @override
  String get incomePlannerMetricOptionPrice => '期权价';

  @override
  String get incomePlannerMetricBidAsk => '买/卖价';

  @override
  String get incomePlannerMetricMargin => '安全边际';

  @override
  String get incomePlannerCardDetailsCta => '详情';

  @override
  String get incomePlannerDetailWhyGood => '为什么值得考虑';

  @override
  String get incomePlannerDetailWhyRisky => '为什么有风险';

  @override
  String get incomePlannerDetailWorstCase => '最坏情况';

  @override
  String get incomePlannerDetailBestFor => '适合';

  @override
  String get incomePlannerDetailAvoidIf => '不适合';

  @override
  String get incomePlannerDetailScoreBreakdown => '评分明细';

  @override
  String get incomePlannerDetailLogTrade => '记录此交易';

  @override
  String get incomePlannerJournalSectionTitle => '交易日记';

  @override
  String get incomePlannerJournalEmpty => '你记录的未平仓与已平仓交易会显示在这里。';

  @override
  String get incomePlannerJournalAddCta => '记录交易';

  @override
  String get incomePlannerJournalEditTitle => '编辑交易日记';

  @override
  String get incomePlannerJournalCreditLabel => '收取权利金';

  @override
  String get incomePlannerJournalDebitLabel => '平仓支付';

  @override
  String get incomePlannerJournalOptionSymbolLabel => '期权代码';

  @override
  String get incomePlannerJournalOptionSymbolHint => 'AAPL250620P00190000';

  @override
  String get incomePlannerJournalAmountHint => '0.00';

  @override
  String get incomePlannerJournalBrokerageAccountLabel => '证券账户';

  @override
  String get incomePlannerJournalCashAccountLabel => '现金账户';

  @override
  String get incomePlannerJournalStrikeLabel => '行权价';

  @override
  String get incomePlannerJournalContractSizeLabel => '合约乘数';

  @override
  String get incomePlannerJournalNotesLabel => '备注';

  @override
  String get incomePlannerJournalStatusOpen => '未平仓';

  @override
  String get incomePlannerJournalStatusClosed => '已平仓';

  @override
  String get incomePlannerJournalStatusAssigned => '已行权';

  @override
  String get incomePlannerJournalStatusExpired => '已到期';

  @override
  String get incomePlannerStatsAction => '统计';

  @override
  String get incomePlannerStatsTitle => '期权复盘';

  @override
  String get incomePlannerStatsEmptyTitle => '暂无交易';

  @override
  String get incomePlannerStatsEmptyBody =>
      '在 Income Planner 记录期权交易后，可在这里复盘权利金、已实现盈亏和行权情况。';

  @override
  String get incomePlannerStatsOverviewTitle => '日记汇总';

  @override
  String get incomePlannerStatsTotalTrades => '交易';

  @override
  String get incomePlannerStatsOpenTrades => '未平仓';

  @override
  String get incomePlannerStatsAssignedTrades => '已行权';

  @override
  String get incomePlannerStatsExpiredTrades => '已到期';

  @override
  String get incomePlannerStatsPremium => '权利金';

  @override
  String get incomePlannerStatsRealizedPnl => '已跟踪盈亏';

  @override
  String get incomePlannerStatsWinRate => '盈利率';

  @override
  String get incomePlannerStatsAvgHoldingDays => '平均天数';

  @override
  String incomePlannerStatsMultiCurrencyNote(String currencies) {
    return '此日记包含 $currencies，金额按币种分别展示，不强行合并。';
  }

  @override
  String get incomePlannerStatsStrategySectionTitle => '按策略';

  @override
  String get incomePlannerStatsSymbolSectionTitle => '按标的';

  @override
  String incomePlannerStatsTradeCount(int total, int open) {
    return '$total 笔 · $open 笔未平仓';
  }

  @override
  String incomePlannerStatsSymbolDetail(
    int total,
    int open,
    int assigned,
    int expired,
  ) {
    return '$total 笔 · $open 未平仓 · $assigned 行权 · $expired 到期';
  }

  @override
  String get incomePlannerSymbolRequired => '请输入代码';

  @override
  String get incomePlannerDuplicateSymbol => '该代码已在清单中';

  @override
  String get incomePlannerProfileSaveError => '无法保存偏好';

  @override
  String get incomePlannerUnderlyingSaveError => '无法保存标的';

  @override
  String get incomePlannerPreferencesAction => '偏好';

  @override
  String get incomePlannerEditAction => '编辑';

  @override
  String incomePlannerLastScanMinutes(int n) {
    return '$n 分钟前';
  }

  @override
  String incomePlannerLastScanHours(int n) {
    return '$n 小时前';
  }

  @override
  String incomePlannerLastScanDays(int n) {
    return '$n 天前';
  }

  @override
  String incomePlannerLastScanFresh(String label, String ago, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个候选',
      one: '1 个候选',
    );
    return '$label:$ago · $_temp0';
  }

  @override
  String incomePlannerLastScanStaleSummary(
    String label,
    String ago,
    String stale,
  ) {
    return '$label:$ago · $stale';
  }

  @override
  String get onboardingTitle => '欢迎使用 NaviWealth';

  @override
  String get onboardingSubtitle => '选择你的使用方式';

  @override
  String get onboardingCloudTitle => '云账号';

  @override
  String get onboardingCloudDescription => '多设备同步数据';

  @override
  String get onboardingLocalOnlyTitle => '仅本地';

  @override
  String get onboardingLocalOnlyDescription => '数据留在本机，不进行同步';

  @override
  String get settingsAccountLocalOnlyBadge => '本地模式';

  @override
  String get settingsUpgradeToCloudHint => '跨设备同步数据';

  @override
  String get settingsSwitchToLocal => '切换到本地模式';

  @override
  String get settingsSwitchToLocalConfirmTitle => '切换到本地模式？';

  @override
  String get settingsSwitchToLocalConfirmBody => '云同步将被禁用。数据将保留在本机，但不再同步到其他设备。';

  @override
  String get commonDate => '日期';

  @override
  String get commonNote => '备注';

  @override
  String get commonOk => '好的';

  @override
  String get healthTodayTitle => '今日';

  @override
  String get healthTrendTitle => '趋势';

  @override
  String get healthPlanTitle => '计划';

  @override
  String get healthTabToday => '今日';

  @override
  String get healthTabTrend => '趋势';

  @override
  String get healthTabPlan => '计划';

  @override
  String get healthSourcesTitle => '数据源';

  @override
  String get healthSourcesSubtitle => 'HealthKit / Health Connect 与 Garmin';

  @override
  String get healthNoDataSyncHint => '展开下方「数据源」进行同步或连接设备';

  @override
  String get healthCommandToday => '健康 · 今日';

  @override
  String get healthCommandTrend => '健康 · 趋势';

  @override
  String get healthCommandPlan => '健康 · 计划';

  @override
  String get healthInputMetricsTitle => '输入指标';

  @override
  String get healthConfidenceLabel => '置信度';

  @override
  String get healthConfidenceLow => '低';

  @override
  String get healthConfidenceMedium => '中';

  @override
  String get healthRecentHrvLabel => 'HRV（近期均值）';

  @override
  String get healthRecentSleepLabel => '睡眠（近期均值）';

  @override
  String get healthRecentRhrLabel => '静息心率（近期均值）';

  @override
  String get healthRecentVo2MaxLabel => 'VO₂max（近期均值）';

  @override
  String get healthSleepMetricLabel => '睡眠';

  @override
  String get healthHrvMetricLabel => 'HRV';

  @override
  String get healthHeartRateMetricLabel => '心率';

  @override
  String get healthWorkoutMetricLabel => '运动';

  @override
  String healthWorkoutDurationHoursMinutes(Object hours, Object minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String healthWorkoutDurationMinutes(Object minutes) {
    return '$minutes 分钟';
  }

  @override
  String healthWeeklyWorkoutValue(Object count, Object duration) {
    return '$duration · $count 次';
  }

  @override
  String get healthStepsMetricLabel => '步数';

  @override
  String get healthEnergyMetricLabel => '能量';

  @override
  String get healthLoadingLabel => '加载中…';

  @override
  String get healthTrendGroupRecovery => '恢复';

  @override
  String get healthTrendGroupActivity => '活动';

  @override
  String get healthTrendGroupBody => '身体';

  @override
  String healthTrendLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get healthTrendNotEnoughData => '数据还不够。';

  @override
  String get healthTrendHrvSubtitle => '心率变异性';

  @override
  String get healthTrendSleepSubtitle => '每晚小时数';

  @override
  String get healthTrendHeartRateSubtitle => '每日平均心率';

  @override
  String get healthTrendRespiratoryTitle => '呼吸';

  @override
  String get healthTrendRespiratorySubtitle => '每日平均呼吸率';

  @override
  String get healthTrendRhrTitle => '静息心率';

  @override
  String get healthTrendRhrSubtitle => '每日静息心率';

  @override
  String get healthTrendWorkoutSubtitle => '每天分钟数';

  @override
  String get healthTrendStepsSubtitle => '每天步数';

  @override
  String get healthTrendWalkingDistanceTitle => '步行距离';

  @override
  String get healthTrendWalkingDistanceSubtitle => '每天公里数';

  @override
  String get healthTrendFlightsTitle => '楼层';

  @override
  String get healthTrendFlightsSubtitle => '每天爬楼层数';

  @override
  String get healthTrendWeightTitle => '体重';

  @override
  String get healthTrendWeightSubtitle => '体重记录';

  @override
  String get healthTrendBodyFatTitle => '体脂';

  @override
  String get healthTrendBodyFatSubtitle => '体脂比例';

  @override
  String get healthTrendVo2MaxTitle => 'VO₂max';

  @override
  String get healthTrendVo2MaxSubtitle => '最大摄氧量';

  @override
  String get healthBodyBatteryMetricLabel => '电量';

  @override
  String get healthStressMetricLabel => '压力';

  @override
  String get healthRhrMetricLabel => '静息心率';

  @override
  String get healthTrainingLoadMetricLabel => '负荷';

  @override
  String get healthSleepDeepLabel => '深睡';

  @override
  String get healthSleepRemLabel => 'REM';

  @override
  String get healthSleepLightLabel => '浅睡';

  @override
  String get healthSleepAwakeLabel => '清醒';

  @override
  String get healthTrendBodyBatteryTitle => '电量';

  @override
  String get healthTrendBodyBatterySubtitle => '每日最高电量';

  @override
  String get healthTrendStressTitle => '压力';

  @override
  String get healthTrendStressSubtitle => '每日平均压力';

  @override
  String get healthTrendTrainingLoadTitle => '训练负荷';

  @override
  String get healthTrendTrainingLoadSubtitle => '每周训练负荷';

  @override
  String get healthTrendTrainingEffectTitle => '训练效果';

  @override
  String get healthTrendTrainingEffectSubtitle => '体能提升信号';

  @override
  String get healthWeeklySummaryTitle => '本周状态';

  @override
  String get healthWeeklySummarySubtitle => '最近 7 天关键健康信号';

  @override
  String get healthWeeklySummaryEmpty => '同步几天数据后，这里会汇总步数、睡眠、训练和恢复指标。';

  @override
  String get healthSpo2MetricLabel => '血氧';

  @override
  String get healthTrendSpo2Title => '血氧';

  @override
  String get healthTrendSpo2Subtitle => '每日平均血氧饱和度';

  @override
  String get healthTrendTotalEnergyTitle => '总能量';

  @override
  String get healthTrendTotalEnergySubtitle => '每日总消耗卡路里';

  @override
  String get healthKitTitle => 'HealthKit / Health Connect';

  @override
  String get healthSyncAction => '同步';

  @override
  String get healthSyncPermissionDenied => '权限被拒绝';

  @override
  String get healthSyncingData => '正在同步健康数据…';

  @override
  String get healthSyncReady => '同步最近 30 天健康数据';

  @override
  String healthSyncResult(Object unchanged, Object upserted) {
    return '已同步 $upserted 新数据 · $unchanged 未变';
  }

  @override
  String get healthSyncFailed => '同步失败';

  @override
  String get healthSyncButton => '同步';

  @override
  String get healthSyncingButton => '同步中';

  @override
  String get healthRecoveryTitle => '今日恢复';

  @override
  String get healthRecoveryRested => '充分恢复';

  @override
  String get healthRecoveryBalanced => '平衡';

  @override
  String get healthRecoveryStrained => '过载';

  @override
  String get healthRecoveryInsufficient => '数据不足';

  @override
  String get healthRecoveryRestedTip => '今天可以安排高强度训练或高认知负荷工作。';

  @override
  String get healthRecoveryBalancedTip => '维持平时节奏，训练和会议都不要推到极限。';

  @override
  String get healthRecoveryStrainedTip => '建议减负：轻量活动、补眠，避免连续高压安排。';

  @override
  String get healthRecoveryInsufficientTip => '先同步并连续记录几天，恢复建议会更稳定。';

  @override
  String get healthBriefingTitle => '早间简报';

  @override
  String get healthBriefingEmpty => '暂无简报';

  @override
  String get healthBriefingEmptyHint => '同步数据后可生成今日简报。';

  @override
  String get healthBriefingGenerating => '生成中';

  @override
  String get healthBriefingUpdate => '更新';

  @override
  String get healthBriefingGenerate => '生成';

  @override
  String healthBriefingUpdated(Object time) {
    return '更新于 $time';
  }

  @override
  String healthBriefingLoadFailed(Object message) {
    return '简报加载失败：$message';
  }

  @override
  String get healthNoData => '暂无数据';

  @override
  String get healthShowAllMetrics => '显示全部指标';

  @override
  String get healthShowKeyMetrics => '只看关键指标';

  @override
  String healthMoreMetrics(int count) {
    return '更多 · $count';
  }

  @override
  String get healthCollapseMetrics => '收起';

  @override
  String get healthMorePlanActions => '更多建议';

  @override
  String get healthCollapsePlanActions => '收起';

  @override
  String get healthPlanTodayActions => '今日建议';

  @override
  String get healthPlanHighIntensity => '可安排高强度训练或关键深度工作。';

  @override
  String get healthPlanKeepSleep => '保持正常睡眠窗口，避免过度透支。';

  @override
  String get healthPlanTrainAsPlanned => '按原计划训练，保留 1-2 成余量。';

  @override
  String get healthPlanReduceCaffeine => '下午减少咖啡因，保持晚间恢复。';

  @override
  String get healthPlanLightActivity => '换成散步、拉伸或 Zone 2 轻量活动。';

  @override
  String get healthPlanAvoidPressure => '避免连续高压会议和晚间训练。';

  @override
  String get healthPlanSyncFirst => '先同步 Health Connect 数据。';

  @override
  String get healthPlanTrackMore => '连续记录几天后再判断趋势。';

  @override
  String get healthPlanEnableHint => '请在 设置 → Domains 中启用 HealthOS，才能查看恢复建议。';

  @override
  String get healthPlanDisclaimerTitle => '仅供健康参考';

  @override
  String get healthPlanDisclaimer => '不是医学诊断，仅供日常作息判断。HealthOS 不会自动调整你的日程。';

  @override
  String get healthRecordBodyMetricAction => '记录身体指标';

  @override
  String get healthBodyMeasurementTitle => '记录身体指标';

  @override
  String get healthBodyMeasurementSubtitle => '适合体重、体脂这类低频手动录入数据';

  @override
  String get healthMetricWeight => '体重';

  @override
  String get healthMetricBodyFat => '体脂';

  @override
  String get healthBodyMeasurementWeightHelper => '单位：kg';

  @override
  String get healthBodyMeasurementBodyFatHelper => '单位：%，例如 18.5';

  @override
  String get healthBodyFatMaxError => '体脂不能超过 100%';

  @override
  String healthBodyMeasurementSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get knowledgeInboxTitle => '收件箱 · KnowledgeOS';

  @override
  String get knowledgeTabInbox => '收件箱';

  @override
  String get knowledgeTabLibrary => '资料库';

  @override
  String get knowledgeTabReview => '复盘';

  @override
  String get knowledgeCommandInbox => '知识 · 收件箱';

  @override
  String get knowledgeCommandLibrary => '知识 · 资料库';

  @override
  String get knowledgeCommandReview => '知识 · 复盘';

  @override
  String get knowledgeProposalCaptureUpgrade => '捕获升级';

  @override
  String get knowledgeProposalMerge => '合并去重';

  @override
  String get knowledgeProposalRoutine => '定期事项';

  @override
  String get knowledgeProposalConceptLink => '概念关联';

  @override
  String get knowledgeProposalRowType => '类型';

  @override
  String get knowledgeProposalRowContent => '内容';

  @override
  String get knowledgeProposalRowScope => '范围';

  @override
  String get knowledgeProposalRowConfidence => '置信度';

  @override
  String get knowledgeProposalRowLink => '关联';

  @override
  String get knowledgeProposalRowRelation => '关系';

  @override
  String get knowledgeProposalRowKeep => '保留';

  @override
  String get knowledgeProposalRowSoftMerge => '合并（软删）';

  @override
  String get knowledgeProposalRowMergedTags => '合并后标签';

  @override
  String get knowledgeProposalRowItem => '事项';

  @override
  String get knowledgeProposalRowInterval => '周期';

  @override
  String knowledgeProposalIntervalDays(int days) {
    return '每 $days 天';
  }

  @override
  String get knowledgeInboxEmptyTitle => '收件箱空空如也';

  @override
  String get knowledgeInboxEmptyBody =>
      '使用创建入口写一条想法。AI 会判断它适合保留为 Note，还是升级为 Routine、Decision 或其他知识对象。';

  @override
  String get knowledgeInboxLoadFailedTitle => '收件箱加载失败';

  @override
  String get knowledgeCaptureAction => '新建捕获';

  @override
  String get knowledgeCreateEntry => '新建条目';

  @override
  String get knowledgeCaptureTitle => '写一条想法';

  @override
  String get knowledgeCaptureTitleField => '标题（可选）';

  @override
  String get knowledgeCaptureBodyField => '内容';

  @override
  String get knowledgeCaptureTitleHint => '\"港卡需要定期活跃\"';

  @override
  String get knowledgeCaptureBodyHint => '\"港卡每 6 个月做一次活跃交易，否则会休眠\"';

  @override
  String get knowledgeCaptureSavedClassifyingTitle => '已保存 · AI 思考中';

  @override
  String get knowledgeCaptureSavedPreviewTitle => '已保存的捕获';

  @override
  String get knowledgeCaptureSuggestionTitle => 'AI 建议';

  @override
  String get knowledgeCaptureComposeSubtitle =>
      '自由格式 Markdown。保存后 AI 会判断是否值得升级。';

  @override
  String get knowledgeCaptureClassifyingSubtitle =>
      'Note 已经落库，AI 正在判断是否适合升级为 Routine / Decision 等知识对象。';

  @override
  String get knowledgeCaptureSuggestionSubtitle => '应用前先确认 AI 抽取的类型和字段。';

  @override
  String get knowledgeCaptureTypeLabel => '保存为';

  @override
  String get knowledgeCaptureKindAuto => '自动';

  @override
  String get knowledgeCaptureKindNote => 'Note';

  @override
  String get knowledgeCaptureKindRoutine => 'Routine';

  @override
  String get knowledgeCaptureKindDecision => 'Decision';

  @override
  String get knowledgeCaptureKindAssumption => 'Assumption';

  @override
  String get knowledgeCaptureKindPrinciple => 'Principle';

  @override
  String get knowledgeCaptureKindConcept => 'Concept';

  @override
  String get knowledgeCaptureKindExperiment => 'Experiment';

  @override
  String get knowledgeCaptureSave => '保存并分析';

  @override
  String knowledgeCaptureSaveTyped(String kind) {
    return '保存为 $kind';
  }

  @override
  String get knowledgeCaptureSaving => '保存中…';

  @override
  String get knowledgeCaptureCancel => '取消';

  @override
  String get knowledgeCaptureClassifyingBody =>
      '推理模型可能需要 20-30 秒。Note 已经保存，等不及可以直接跳过。';

  @override
  String get knowledgeCaptureSkipClassification => '保留为 Note，不等了';

  @override
  String get knowledgeCaptureApplySuggestion => '应用建议';

  @override
  String get knowledgeCaptureApplyPolish => '应用润色';

  @override
  String get knowledgeCaptureApplying => '应用中…';

  @override
  String get knowledgeCaptureKeepOriginal => '保留原文';

  @override
  String knowledgeCaptureNotePolishOnly(Object reason) {
    return 'AI 判定 kind = note，只润色不升级。原因：$reason';
  }

  @override
  String get knowledgeCapturePolishedVersionTitle => 'AI 润色后的版本';

  @override
  String get knowledgeCaptureTitleDiffLabel => '标题';

  @override
  String get knowledgeCaptureBodyDiffLabel => '正文';

  @override
  String get knowledgeCaptureEmptyValue => '（空）';

  @override
  String knowledgeCaptureOriginalDiffValue(Object value) {
    return '原：$value';
  }

  @override
  String get knowledgeCaptureKindRoutineDescription => '看起来是一个定期事项';

  @override
  String get knowledgeCaptureKindDecisionDescription => '看起来在权衡某个选项';

  @override
  String get knowledgeCaptureKindAssumptionDescription => '看起来在声明一条信念';

  @override
  String get knowledgeCaptureKindPrincipleDescription => '看起来在声明一条原则';

  @override
  String get knowledgeCaptureKindConceptDescription => '看起来在定义一个概念';

  @override
  String get knowledgeCaptureKindExperimentDescription => '看起来在描述一个实验';

  @override
  String get knowledgeCaptureKindNoteDescription => '保留为 Note';

  @override
  String knowledgeCaptureRoutineUpgradeDetail(
    Object intervalDays,
    Object statement,
  ) {
    return '会建一条 Routine：“$statement”，每 $intervalDays 天提醒一次';
  }

  @override
  String knowledgeCaptureRoutineScopeDetail(Object scope) {
    return 'scope = $scope。';
  }

  @override
  String get knowledgeCaptureRoutineReminderDetail => 'AI 会在到期前 7 天自动提醒。';

  @override
  String knowledgeCaptureSuggestionReasonConfidence(
    Object confidence,
    Object reason,
  ) {
    return '原因：$reason · 置信度 $confidence';
  }

  @override
  String knowledgeCaptureSaveFailed(Object error) {
    return '捕捉失败：$error';
  }

  @override
  String knowledgeCaptureApplyFailed(Object error) {
    return '应用建议失败：$error';
  }

  @override
  String get knowledgeAiPromptHint => '记点什么 / 问点什么…';

  @override
  String get knowledgeAiDedupeAction => '查重';

  @override
  String get knowledgeAiDedupePrompt => '帮我查一下知识库里有没有内容相近、可能重复的笔记或概念，重复的建议合并。';

  @override
  String get knowledgeAiWeeklyAction => '本周建议';

  @override
  String get knowledgeAiWeeklyPrompt =>
      '根据我的知识库给我这周的建议：到期复盘的决策、长期未校验的假设、本周到期的定期事项、没有标签或链接的孤儿笔记。';

  @override
  String get knowledgeAiSearchAction => '搜知识';

  @override
  String get knowledgeAiSearchPrompt => '搜索我的知识库：';

  @override
  String get knowledgeLibraryTitle => '资料库 · KnowledgeOS';

  @override
  String get knowledgeLibraryEmptyAllTitle => '资料库还没有内容';

  @override
  String get knowledgeLibraryEmptyAllBody =>
      '先从收件箱记录 Note，或用右下角 + 创建 Decision、Assumption、Routine 等知识对象。';

  @override
  String get knowledgeLibraryEmptyDecisionsTitle => '还没有 Decision';

  @override
  String get knowledgeLibraryEmptyDecisionsBody =>
      '点右下角 + 新建 Decision，记录第一条值得复盘的判断。';

  @override
  String get knowledgeLibraryEmptyPrinciplesTitle => '还没有 Principle';

  @override
  String get knowledgeLibraryEmptyPrinciplesBody =>
      'Principle 用来记录长期稳定、会影响判断的世界观规则。';

  @override
  String get knowledgeLibraryEmptyAssumptionsTitle => '还没有 Assumption';

  @override
  String get knowledgeLibraryEmptyAssumptionsBody =>
      'Assumption 用来记录可证伪的信念、置信度和后续验证。';

  @override
  String get knowledgeLibraryEmptyNotesTitle => '资料库里还没有 Note';

  @override
  String get knowledgeLibraryEmptyNotesBody => 'Note 在收件箱录入；这里只做浏览。';

  @override
  String get knowledgeLibraryEmptyConceptsTitle => '还没有 Concept 节点';

  @override
  String get knowledgeLibraryEmptyConceptsBody =>
      'Concept 用于 [[soft links]] 和 AI 关联。';

  @override
  String get knowledgeLibraryEmptyExperimentsTitle => '没有进行中的 Experiment';

  @override
  String get knowledgeLibraryEmptyExperimentsBody =>
      'Experiment 通常挂在一条待验证的 Assumption 上。';

  @override
  String get knowledgeLibraryEmptyRoutinesTitle => '还没有 Routine';

  @override
  String get knowledgeLibraryEmptyRoutinesBody =>
      '定期提醒（例如「港卡每 6 个月活跃一次」）。新建后 AI 会在到期前主动提示。';

  @override
  String knowledgeRoutineOverdueDays(Object days) {
    return '已逾期 $days 天';
  }

  @override
  String get knowledgeRoutineDueToday => '今日到期';

  @override
  String knowledgeRoutineDueInDays(Object days) {
    return '$days 天后到期';
  }

  @override
  String knowledgeRoutineLibraryMeta(
    Object dueLabel,
    Object intervalDays,
    Object scope,
  ) {
    return '$dueLabel · 每 $intervalDays 天 · $scope';
  }

  @override
  String get knowledgeLibrarySearchHint => '搜索当前分段';

  @override
  String knowledgeLibrarySearchSegmentHint(Object segment) {
    return '搜索 $segment';
  }

  @override
  String get knowledgeLibraryFilterAll => '全部';

  @override
  String get knowledgeLibraryFilterTitle => '筛选';

  @override
  String get knowledgeLibraryFilterClear => '清除筛选';

  @override
  String get knowledgeLibraryFilterStatus => '状态';

  @override
  String get knowledgeLibraryFilterDate => '日期';

  @override
  String get knowledgeLibraryFilterFacet => '标签与范围';

  @override
  String get knowledgeLibraryDateFilterAll => '任意日期';

  @override
  String get knowledgeLibraryDateFilterToday => '今天';

  @override
  String get knowledgeLibraryDateFilterWeek => '7 天内';

  @override
  String get knowledgeLibraryDateFilterMonth => '30 天内';

  @override
  String get knowledgeLibraryDateFilterOutsideMonth => '30 天外';

  @override
  String get knowledgeLibrarySearchClear => '清除搜索';

  @override
  String get knowledgeLibrarySearchRecent => '最近';

  @override
  String get knowledgeLibrarySearchSuggestions => '建议';

  @override
  String get knowledgeLibrarySearchEmptyTitle => '没有匹配的知识';

  @override
  String get knowledgeLibrarySearchEmptyBody => '换个关键词，或切换到其他分段。';

  @override
  String knowledgeLibraryLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String knowledgeLibraryDeleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String get knowledgeReviewTitle => '复盘 · KnowledgeOS';

  @override
  String get knowledgeReviewRoutinesTitle => '本周到期的 Routine';

  @override
  String get knowledgeReviewRoutinesEmpty => '未来 7 天内没有到期的 Routine。';

  @override
  String get knowledgeReviewDecisionsTitle => '待复盘的 Decision';

  @override
  String get knowledgeReviewDecisionsEmpty => '当前没有到期的 Decision 复盘。';

  @override
  String knowledgeReviewDecisionOverdueDays(Object days) {
    return '$days 天';
  }

  @override
  String get knowledgeReviewDecisionReviewed => '已复盘';

  @override
  String get knowledgeReviewMarkAllDecisionsReviewed => '全部标记复盘';

  @override
  String get knowledgeReviewMarkSelectedDecisionsReviewed => '标记所选复盘';

  @override
  String get knowledgeReviewBatchActions => '批量处理';

  @override
  String knowledgeReviewTotalCount(Object count) {
    return '共 $count 项';
  }

  @override
  String knowledgeReviewVisibleCount(Object total, Object visible) {
    return '显示前 $visible 项，共 $total 项';
  }

  @override
  String knowledgeReviewDecisionNextReview(Object date) {
    return '下次复盘 $date';
  }

  @override
  String knowledgeReviewDecisionsBulkReviewed(int count) {
    return '已为 $count 个 Decision 安排下次复盘';
  }

  @override
  String knowledgeReviewDecisionReviewFailed(Object error) {
    return '更新复盘日期失败：$error';
  }

  @override
  String get knowledgeReviewAssumptionsTitle => '未校验的 Assumption';

  @override
  String knowledgeReviewAssumptionsEmpty(Object days) {
    return '所有 active 的 Assumption 都在 $days 天内校验过。';
  }

  @override
  String knowledgeReviewRoutineMeta(Object dueLabel, Object intervalDays) {
    return '$dueLabel · 每 $intervalDays 天';
  }

  @override
  String knowledgeReviewAssumptionStaleSummary(
    Object confidence,
    Object days,
    Object statement,
  ) {
    return '· $statement（$days 天，conf $confidence）';
  }

  @override
  String knowledgeReviewLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String knowledgeReviewRoutineDone(Object date) {
    return '已完成，下次 $date';
  }

  @override
  String knowledgeReviewRoutineDoneFailed(Object error) {
    return '完成失败：$error';
  }

  @override
  String get knowledgeReviewMarkDone => '完成';

  @override
  String get knowledgeReviewMarkAllDone => '全部完成';

  @override
  String get knowledgeReviewMarkSelectedDone => '完成所选';

  @override
  String knowledgeReviewRoutinesBulkDone(int count) {
    return '已完成 $count 个 Routine';
  }

  @override
  String get knowledgeReviewVerifyAssumption => '校验';

  @override
  String get knowledgeReviewVerifyAllAssumptions => '全部校验';

  @override
  String get knowledgeReviewVerifySelectedAssumptions => '校验所选';

  @override
  String knowledgeReviewAssumptionsBulkVerified(int count) {
    return '已校验 $count 个 Assumption';
  }

  @override
  String get knowledgeReviewAssumptionVerified => 'Assumption 已校验。';

  @override
  String knowledgeReviewAssumptionVerifyFailed(Object error) {
    return '校验失败：$error';
  }

  @override
  String get knowledgeReviewSelectAll => '全选';

  @override
  String get knowledgeReviewClearSelection => '清空';

  @override
  String knowledgeReviewSelectedCount(int count) {
    return '已选 $count 个';
  }

  @override
  String get knowledgeSegmentAll => '全部';

  @override
  String get knowledgeSegmentDecisions => '决策';

  @override
  String get knowledgeSegmentPrinciples => '原则';

  @override
  String get knowledgeSegmentAssumptions => '假设';

  @override
  String get knowledgeSegmentNotes => '笔记';

  @override
  String get knowledgeSegmentConcepts => '概念';

  @override
  String get knowledgeSegmentExperiments => '实验';

  @override
  String get knowledgeSegmentRoutines => '例行事项';

  @override
  String get knowledgeNewDecision => '新建 Decision';

  @override
  String get knowledgeNewPrinciple => '新建 Principle';

  @override
  String get knowledgeNewAssumption => '新建 Assumption';

  @override
  String get knowledgeNewNote => '新建 Note';

  @override
  String get knowledgeNewConcept => '新建 Concept';

  @override
  String get knowledgeNewExperiment => '新建 Experiment';

  @override
  String get knowledgeNewRoutine => '新建 Routine';

  @override
  String get knowledgeNewChooserTitle => '新建…';

  @override
  String get knowledgeNewChooserSubtitle => '选择要创建的结构化知识对象。快速 Note 走收件箱捕获。';

  @override
  String get knowledgeNewDecisionHint => '主路径：question / options / rationale';

  @override
  String get knowledgeNewPrincipleHint => '世界观原语，例如 \"edge-first\"';

  @override
  String get knowledgeNewAssumptionHint => '可证伪的信念 + 置信度';

  @override
  String get knowledgeDecisionWriterTitle => '新建 Decision';

  @override
  String get knowledgeDecisionWriterSubtitle => '决策即记忆：问题 / 选项 / 理由 / 复盘';

  @override
  String get knowledgeDecisionAddOption => '添加选项';

  @override
  String get knowledgeDecisionClear => '清除';

  @override
  String get knowledgeDecisionExpectedOutcomeLabel => '预期结果（可选）';

  @override
  String get knowledgeAssumptionWriterSubtitle2 => '可证伪的信念，设置置信度以便后续复盘';

  @override
  String get knowledgeConceptWriterSubtitle2 => '用于 soft links 和 AI 交叉引用的锚点';

  @override
  String get knowledgeExperimentWriterSubtitle2 => '用明确方法验证一条 Assumption';

  @override
  String get knowledgeWriterAliasLabel => '别名';

  @override
  String get knowledgeRoutineMonthly => '每月';

  @override
  String get knowledgeRoutineQuarterly => '每季';

  @override
  String get knowledgeRoutineSemiannual => '每 6 个月';

  @override
  String get knowledgeRoutineYearly => '每年';

  @override
  String get knowledgeDecisionQuestionLabel => '问题';

  @override
  String get knowledgeDecisionQuestionHint => '\"是否升级到 QQQ + BOXX 动态对冲?\"';

  @override
  String get knowledgeDecisionOptionsLabel => '选项';

  @override
  String knowledgeDecisionOptionLabelHint(Object index) {
    return '选项 $index';
  }

  @override
  String get knowledgeDecisionOptionRationaleHint => '为什么选这个选项（可选）';

  @override
  String get knowledgeDecisionNoReferenceCandidates =>
      '还没声明 Principle / Assumption — Decision 可以先存，之后回来挂引用。';

  @override
  String get knowledgeDecisionRationaleLabel => '理由（Markdown）';

  @override
  String get knowledgeDecisionRationaleHint => '为什么选这个选项 — 限制条件、当时的判断';

  @override
  String get knowledgeDecisionExpectedOutcomeHint => '如何判断成功 — 用什么指标 / 信号';

  @override
  String get knowledgeDecisionReviewDateTitle => '复盘日期';

  @override
  String get knowledgeDecisionReviewDateOptional => '复盘日期（可选）';

  @override
  String knowledgeDecisionReviewDateScheduled(Object date) {
    return '复盘于 $date';
  }

  @override
  String get knowledgeDecisionReviewDateChoose => '选择';

  @override
  String get knowledgeDecisionReviewDateChange => '修改';

  @override
  String knowledgeDecisionReviewDateInDays(Object days) {
    return '+$days 天';
  }

  @override
  String get knowledgeDecisionReviewDateInOneYear => '+1 年';

  @override
  String get knowledgeDecisionReviewDateCustomLabel => '自定义日期';

  @override
  String get knowledgeDecisionReviewDateCustomHint => 'YYYY-MM-DD';

  @override
  String get knowledgeDecisionReviewDateCustomApply => '使用日期';

  @override
  String get knowledgeDecisionReviewDateInvalid => '请输入有效日期，格式为 YYYY-MM-DD。';

  @override
  String get knowledgeDecisionReviewDatePast => '请选择今天或未来日期。';

  @override
  String get knowledgeDecisionLifecycleTitle => '更新 Decision';

  @override
  String get knowledgeDecisionLifecycleSubtitle => '状态 / 实际结果 / 认知演化链';

  @override
  String get knowledgeDecisionActualOutcomeLabel => '实际结果（Markdown，可选）';

  @override
  String get knowledgeDecisionStatusLabel => '状态';

  @override
  String get knowledgeDecisionStatusDraft => '草稿';

  @override
  String get knowledgeDecisionStatusActive => '进行中';

  @override
  String get knowledgeDecisionStatusPaused => '暂停';

  @override
  String get knowledgeDecisionStatusExpired => '已过期';

  @override
  String get knowledgeDecisionStatusVerified => '已验证';

  @override
  String get knowledgeDecisionStatusFalsified => '已证伪';

  @override
  String get knowledgeDecisionStatusSuperseded => '已被取代';

  @override
  String get knowledgeDecisionActualOutcomeHint => '复盘时填：实际发生了什么、和预期的差距';

  @override
  String get knowledgeDecisionSupersededByLabel => '被哪条 Decision 取代';

  @override
  String get knowledgeDecisionSupersededByEmpty =>
      '还没有其它 Decision 可指向——先记录新决策，再回来标记取代关系。';

  @override
  String get knowledgePrincipleWriterTitle => '新建 Principle';

  @override
  String get knowledgePrincipleWriterSubtitle => '长期世界观原语，不可证伪';

  @override
  String get knowledgePrincipleStatementHint =>
      '\"默认 edge-first\" / \"避免高维护成本系统\"';

  @override
  String get knowledgePrincipleRationaleHint => '为什么把这个世界观定为 Principle';

  @override
  String get knowledgeAssumptionWriterTitle => '新建 Assumption';

  @override
  String get knowledgeAssumptionWriterSubtitle => '可证伪的信念 + 置信度';

  @override
  String get knowledgeAssumptionStatementHint => '\"长期指数增长高于通胀\"';

  @override
  String get knowledgeConceptWriterTitle => '新建 Concept';

  @override
  String get knowledgeConceptWriterSubtitle => '用于搜索和 soft links 的命名节点';

  @override
  String get knowledgeConceptNameHint => 'Concept 名称（例如 \"edge-first\"）';

  @override
  String get knowledgeConceptAliasesHint => '逗号分隔的同义词';

  @override
  String get knowledgeConceptSummaryHint =>
      '1–2 句定义，用作 [[soft link]] 的 tooltip';

  @override
  String get knowledgeExperimentWriterTitle => '新建 Experiment';

  @override
  String get knowledgeExperimentWriterSubtitle => '用方法和指标验证一条 Assumption';

  @override
  String get knowledgeExperimentHypothesisHint =>
      '\"covered call 60 DTE on QQQ 优于 30 DTE\"';

  @override
  String get knowledgeExperimentMethodHint => '怎么做、跑多久、用什么数据';

  @override
  String get knowledgeExperimentMetricsHint =>
      '逗号分隔（例如 \"yield, drawdown, sharpe\"）';

  @override
  String get knowledgeExperimentNoActiveAssumptions =>
      '没有 active 的 Assumption 可挂（留空也可以）';

  @override
  String get knowledgeExperimentTargetAssumptionLabel => '目标 Assumption（可选）';

  @override
  String get knowledgeRoutineWriterTitle => '新建 Routine';

  @override
  String get knowledgeRoutineWriterSubtitle => '定期提醒，AI 会在临近 next_due_at 时主动提示';

  @override
  String get knowledgeRoutineStatementHint => '\"港卡做一次活跃交易\" / \"每月对账\"';

  @override
  String get knowledgeWriterStatementLabel => '陈述';

  @override
  String get knowledgeWriterRationaleMarkdownLabel => '理由（Markdown）';

  @override
  String get knowledgeWriterScopeLabel => '适用范围';

  @override
  String get knowledgeWriterScopeOptionalLabel => '范围标签（可选）';

  @override
  String get knowledgeWriterEvidenceLabel => '证据 ID';

  @override
  String get knowledgeWriterConfidenceLabel => '置信度';

  @override
  String get knowledgeWriterStatusLabel => '状态';

  @override
  String get knowledgeWriterNameLabel => '名称';

  @override
  String get knowledgeWriterAliasesLabel => '别名';

  @override
  String get knowledgeWriterSummaryMarkdownLabel => '摘要（Markdown）';

  @override
  String get knowledgeWriterHypothesisLabel => '假设';

  @override
  String get knowledgeWriterMethodMarkdownLabel => '方法（Markdown）';

  @override
  String get knowledgeWriterMetricsLabel => '指标';

  @override
  String get knowledgeWriterResultMarkdownLabel => '结果（Markdown，可选）';

  @override
  String get knowledgeWriterConclusionMarkdownLabel => '结论（Markdown，可选）';

  @override
  String get knowledgeWriterCoreSectionTitle => '核心内容';

  @override
  String get knowledgeWriterEvidenceSectionTitle => '证据与理由';

  @override
  String get knowledgeWriterReferencesSectionTitle => '关联';

  @override
  String get knowledgeWriterPlanningSectionTitle => '计划';

  @override
  String get knowledgeWriterCadenceSectionTitle => '节奏';

  @override
  String get knowledgeRoutineStatementLabel => '要做什么';

  @override
  String get knowledgeRoutineFrequencyLabel => '频率';

  @override
  String get knowledgeNotesHintTitle => 'Note 在收件箱录入';

  @override
  String get knowledgeNotesHintBody =>
      '资料库的 Note 段是浏览面；录入走收件箱。关闭这个面板，切到收件箱标签页，使用创建入口即可。';

  @override
  String get amountHidden => '金额已隐藏';

  @override
  String get activityExpenseListLink => '支出';

  @override
  String get activityExpenseReportLink => '支出报表';

  @override
  String get tradeVerbBuy => '买入';

  @override
  String get tradeVerbSell => '卖出';

  @override
  String get healthNotEnabled => 'HealthOS 未启用';

  @override
  String healthPlanLoadFailed(String message) {
    return 'Plan 加载失败：$message';
  }

  @override
  String get healthBriefingAuto => '自动';

  @override
  String get healthGarminTitle => 'Garmin Connect';

  @override
  String get healthGarminDisconnected => '未连接';

  @override
  String get healthGarminConnected => '已连接';

  @override
  String get healthGarminSyncingBadge => '同步中';

  @override
  String get healthGarminErrorBadge => '错误';

  @override
  String get healthGarminRestoringBadge => '恢复中';

  @override
  String get healthGarminVerifyBadge => '验证';

  @override
  String get healthGarminMfaRequired => '需要 MFA 验证';

  @override
  String get healthGarminConnectSheetTitle => '连接 Garmin';

  @override
  String get healthGarminMfaCodeLabel => 'MFA 验证码';

  @override
  String get healthGarminEmailLabel => '邮箱';

  @override
  String get healthGarminEmailHint => 'you@example.com';

  @override
  String get healthGarminPasswordLabel => '密码';

  @override
  String get healthGarminRegionLabel => '地区';

  @override
  String get healthGarminRegionChina => '中国';

  @override
  String get healthGarminRegionGlobal => '全球';

  @override
  String get healthGarminConnect => '连接';

  @override
  String get healthGarminDisconnect => '断开连接';

  @override
  String get healthGarminSync => '同步';

  @override
  String get healthGarminRetry => '重试';

  @override
  String get healthGarminEnterCode => '输入验证码';

  @override
  String get healthGarminRestoringSession => '正在恢复会话…';

  @override
  String get healthGarminSyncingData => '正在同步数据…';

  @override
  String get healthGarminSyncError => '同步错误';

  @override
  String get healthGarminDisconnectTitle => '断开 Garmin 连接？';

  @override
  String get healthGarminDisconnectBody => '已同步的数据将保留在应用中。';

  @override
  String get healthGarminCancel => '取消';

  @override
  String healthGarminLastSync(String time, String count) {
    return '上次同步 $time · $count 条数据';
  }

  @override
  String healthGarminSyncProgress(String current, String total, String count) {
    return '第 $current/$total 天 · $count 条数据';
  }

  @override
  String get healthGarminCancelSync => '取消同步';

  @override
  String get healthGarminErrorAuthExpired => 'Garmin 会话已过期，请重新连接账号。';

  @override
  String get healthGarminErrorRateLimited => 'Garmin 暂时限制了请求，请稍后再试。';

  @override
  String get healthGarminErrorEndpointUnavailable =>
      '当前账号或地区暂不支持部分 Garmin 数据接口。';

  @override
  String get healthGarminErrorPersistFailed => 'Garmin 数据已获取，但未能保存到本地，请重新同步。';

  @override
  String get healthGarminErrorUnsupportedSnapshot =>
      'Garmin 返回了 HealthOS 暂未支持的数据结构。';

  @override
  String get healthGarminErrorGeneric => 'Garmin 同步失败，请重试。';

  @override
  String get settingsDomainsExecutionEnabledSubtitle => 'Today、承诺、进展与个人 todo';

  @override
  String get settingsDomainsExecutionDisabledSubtitle => '把决策与计划转成可追踪的行动';

  @override
  String get settingsDomainsExecutionTodaySubtitle => '查看今天的行动、阻塞与进展';

  @override
  String get executionTabToday => '今天';

  @override
  String get executionTabCommitments => '承诺';

  @override
  String get executionTabReview => '复盘';

  @override
  String get executionCommandToday => 'ExecutionOS 今天';

  @override
  String get executionCommandCommitments => 'ExecutionOS 承诺';

  @override
  String get executionCommandReview => 'ExecutionOS 复盘';

  @override
  String get executionTodayTitle => '今天';

  @override
  String get executionCommitmentsTitle => '承诺';

  @override
  String get executionReviewTitle => '复盘';

  @override
  String get executionCreateActionTitle => '新建 Action';

  @override
  String get executionCreateProjectTitle => '新建 Project';

  @override
  String get executionCreateCommitmentTitle => '新建 Commitment';

  @override
  String get executionCreateProgressTitle => '新建进展';

  @override
  String get executionEditActionTitle => '编辑 Action';

  @override
  String get executionEditProjectTitle => '编辑 Project';

  @override
  String get executionEditCommitmentTitle => '编辑 Commitment';

  @override
  String get executionActionField => '行动';

  @override
  String get executionProjectField => '项目';

  @override
  String get executionCommitmentField => '承诺';

  @override
  String get executionStatusField => '状态';

  @override
  String get executionPriorityField => '优先级';

  @override
  String get executionHorizonField => '周期';

  @override
  String get executionTargetDateField => '目标日期';

  @override
  String get executionScheduledForField => '计划执行';

  @override
  String get executionDueAtField => '截止';

  @override
  String get executionDescriptionField => '说明';

  @override
  String get executionTitleRequired => '请填写标题';

  @override
  String get executionActionTitleHint => '下一步具体要做什么？';

  @override
  String get executionActionNoteHint => '可选备注';

  @override
  String get executionProjectTitleHint => '你正在推进哪个项目？';

  @override
  String get executionProjectDescriptionHint => '可选结果、范围或完成标准';

  @override
  String get executionCommitmentTitleHint => '你承诺推进什么？';

  @override
  String get executionCommitmentDescriptionHint => '可选范围、原因或目标结果';

  @override
  String get executionOverviewFocus => '焦点';

  @override
  String get executionOverviewBacklog => '待排期';

  @override
  String get executionOverviewOpen => '全部';

  @override
  String get executionOverviewBlocked => '阻塞';

  @override
  String get executionOverviewHigh => '高优先';

  @override
  String get executionOverviewDue => '到期';

  @override
  String get executionOverviewProjects => '项目';

  @override
  String get executionOverviewCommitments => '承诺';

  @override
  String get executionOverviewProgress7d => '7 日进展';

  @override
  String get executionTodayEmptyTitle => '今天没有行动';

  @override
  String get executionTodayEmptyBody => '需要跟进的事情先捕获成一个具体下一步。';

  @override
  String get executionTodayFilteredEmptyTitle => '没有匹配行动';

  @override
  String get executionTodayFilteredEmptyBody => '切换筛选；有需要跟进的事情再捕获为 Action。';

  @override
  String executionDeleteConfirmTitle(Object item) {
    return '删除「$item」？';
  }

  @override
  String get executionDeleteConfirmBody => '这会从 ExecutionOS 移除该项目，并同步删除记录。';

  @override
  String get executionCommitmentsEmptyTitle => '没有未完成行动';

  @override
  String get executionCommitmentsEmptyBody =>
      '个人 todo 先用 Action；事情变大后再归入 Project 或 Commitment。';

  @override
  String get executionCommitmentsClosedEmptyTitle => '没有已关闭承诺';

  @override
  String get executionCommitmentsClosedEmptyBody =>
      '已完成或已归档的 Project 与 Commitment 会出现在这里。';

  @override
  String get executionReviewEmptyTitle => '还没有进展记录';

  @override
  String get executionReviewEmptyBody => '完成与阻塞记录会出现在这里，方便复盘。';

  @override
  String get executionClosedActionsSection => '最近已关闭行动';

  @override
  String get executionProjectsSection => '项目';

  @override
  String get executionCommitmentsSection => '承诺';

  @override
  String get executionActionsSection => '行动';

  @override
  String get executionRelatedActionsSection => '关联行动';

  @override
  String get executionTimelineSection => '时间线';

  @override
  String get executionDetailMissingTitle => '未找到项目';

  @override
  String get executionDetailMissingBody => '它可能已被删除，或暂时不在当前设备上。';

  @override
  String get executionProjectStatusActive => '活跃';

  @override
  String get executionProjectStatusPaused => '暂停';

  @override
  String get executionProjectStatusCompleted => '完成';

  @override
  String get executionProjectStatusArchived => '归档';

  @override
  String get executionStatusTodo => '待办';

  @override
  String get executionStatusDoing => '进行中';

  @override
  String get executionStatusBlocked => '阻塞';

  @override
  String get executionStatusDone => '完成';

  @override
  String get executionStatusDropped => '放弃';

  @override
  String get executionPriorityLow => '低';

  @override
  String get executionPriorityNormal => '普通';

  @override
  String get executionPriorityHigh => '高优先级';

  @override
  String get executionHorizonWeek => '本周';

  @override
  String get executionHorizonMonth => '本月';

  @override
  String get executionHorizonQuarter => '本季度';

  @override
  String get executionHorizonOpen => '开放';

  @override
  String executionDueBadge(String date) {
    return '截止 $date';
  }

  @override
  String executionTargetBadge(String date) {
    return '目标 $date';
  }

  @override
  String get executionNoAction => '不关联行动';

  @override
  String get executionUnknownAction => '未知行动';

  @override
  String get executionNoActionsAvailable => '暂无可关联的未完成行动';

  @override
  String get executionNoProject => '不关联项目';

  @override
  String get executionUnknownProject => '未知项目';

  @override
  String get executionNoProjectsAvailable => '暂无可关联的活跃项目';

  @override
  String get executionNoCommitment => '不关联承诺';

  @override
  String get executionUnknownCommitment => '未知承诺';

  @override
  String get executionNoCommitmentsAvailable => '暂无可关联的活跃承诺';

  @override
  String get executionPickerSearchHint => '按标题或备注搜索';

  @override
  String get executionPickerSearchEmpty => '没有匹配项';

  @override
  String get executionActionStart => '开始';

  @override
  String get executionActionBlock => '阻塞';

  @override
  String get executionActionResume => '恢复';

  @override
  String get executionActionDone => '完成';

  @override
  String get executionActionDrop => '放弃';

  @override
  String get executionActionStatusUpdateFailed => '更新行动状态失败。';

  @override
  String get executionLifecyclePause => '暂停';

  @override
  String get executionLifecycleResume => '恢复';

  @override
  String get executionLifecycleComplete => '完成';

  @override
  String get executionLifecycleActiveView => '进行中';

  @override
  String get executionLifecycleClosedView => '已关闭';

  @override
  String get executionProjectStatusUpdateFailed => '更新项目状态失败。';

  @override
  String get executionCommitmentStatusUpdateFailed => '更新承诺状态失败。';

  @override
  String get executionProgressBlockedDefault => '已标记为阻塞。';

  @override
  String get executionProgressDoneDefault => '已标记为完成。';

  @override
  String get executionProgressDroppedDefault => '已标记为放弃。';

  @override
  String get executionProgressKindField => '进展类型';

  @override
  String get executionProgressNoteField => '进展记录';

  @override
  String get executionProgressNoteHint => '记录变化、阻塞或已完成的事情。';

  @override
  String get executionProgressNoteRequired => '请填写进展记录';

  @override
  String get executionProgressKindBlocker => '阻塞';

  @override
  String get executionProgressKindCompletion => '完成';

  @override
  String get executionProgressKindDropped => '放弃';

  @override
  String get executionProgressKindScope => '范围变化';

  @override
  String get executionProgressKindCheckin => '进展记录';

  @override
  String get executionProgressSyncActionStatus => '同步更新关联行动';

  @override
  String executionProgressSyncActionStatusBody(Object status) {
    return '同时把行动状态改为「$status」。';
  }

  @override
  String get executionProposalActionLabel => 'Action';

  @override
  String get executionProposalActionStatusLabel => '行动状态';

  @override
  String get executionProposalProjectLabel => 'Project';

  @override
  String get executionProposalCommitmentLabel => 'Commitment';

  @override
  String get executionProposalProgressLabel => '进展';

  @override
  String get executionProposalRowAction => '行动';

  @override
  String get executionProposalRowPriority => '优先级';

  @override
  String get executionProposalRowProject => '项目';

  @override
  String get executionProposalRowCommitment => '承诺';

  @override
  String get executionProposalRowProgress => '进展';

  @override
  String get executionProposalRowDue => '截止';

  @override
  String get executionProposalRowSource => '来源';

  @override
  String get agentOutputLanguageEnglish => '英文';

  @override
  String get agentOutputLanguageChinese => '中文';

  @override
  String get financeAgentWeeklyWealthSkipNoSnapshot => '暂无可复盘的财务快照';

  @override
  String financeAgentWeeklyWealthMemoryTitle(Object dayKey) {
    return '每周财富复盘 · $dayKey';
  }

  @override
  String get financeAgentWeeklyWealthTitle => '每周财富复盘';

  @override
  String financeAgentWeeklyWealthSummary(Object details) {
    return '每周财富复盘：$details。';
  }

  @override
  String financeAgentWeeklyWealthPartNetWorth(Object value) {
    return '净资产 $value';
  }

  @override
  String financeAgentWeeklyWealthPartAssets(Object value) {
    return '资产 $value';
  }

  @override
  String financeAgentWeeklyWealthPartLiabilities(Object value) {
    return '负债 $value';
  }

  @override
  String financeAgentWeeklyWealthPartLargestAllocation(
    Object amount,
    Object category,
    Object ratio,
  ) {
    return '最大配置 $category $amount（$ratio）';
  }

  @override
  String financeAgentWeeklyWealthPartStalePrices(Object count) {
    return '$count 个价格过期';
  }

  @override
  String financeAgentWeeklyWealthPartFxGaps(Object count) {
    return '$count 个汇率缺口';
  }

  @override
  String get financeAgentAssetCategoryStock => '股票';

  @override
  String get financeAgentAssetCategoryEtf => 'ETF';

  @override
  String get financeAgentAssetCategoryBondsAndFunds => '债券和基金';

  @override
  String get financeAgentAssetCategoryCash => '现金';

  @override
  String get financeAgentAssetCategoryCrypto => '加密资产';

  @override
  String get financeAgentAssetCategoryRealEstate => '房地产';

  @override
  String get financeAgentAssetCategoryVehicle => '车辆';

  @override
  String get financeAgentAssetCategoryLiability => '负债';

  @override
  String get financeAgentWeeklyWealthInsightNetWorthTitle => '净资产';

  @override
  String financeAgentWeeklyWealthInsightNetWorthBody(
    Object assets,
    Object liabilities,
    Object netWorth,
  ) {
    return '净资产 $netWorth，由 $assets 资产和 $liabilities 负债构成。';
  }

  @override
  String get financeAgentWeeklyWealthInsightLargestAllocationTitle => '最大配置';

  @override
  String financeAgentWeeklyWealthInsightLargestAllocationBody(
    Object amount,
    Object category,
    Object ratio,
  ) {
    return '$category 为 $amount，约占资产 $ratio。';
  }

  @override
  String get financeAgentWeeklyWealthInsightPriceFreshnessTitle => '价格新鲜度';

  @override
  String financeAgentWeeklyWealthInsightPriceFreshnessBody(Object count) {
    return '$count 个持仓价格已过期。';
  }

  @override
  String get financeAgentWeeklyWealthInsightFxCoverageTitle => '汇率覆盖';

  @override
  String financeAgentWeeklyWealthInsightFxCoverageBody(Object count) {
    return '$count 个持仓因缺少汇率换算被排除。';
  }

  @override
  String get financeAgentWeeklyWealthAction => '查看财富复盘';

  @override
  String get financeAgentCashflowSkipNoAnomaly => '未检测到现金流异常';

  @override
  String financeAgentCashflowMemoryTitle(Object dayKey) {
    return '现金流异常复盘 · $dayKey';
  }

  @override
  String get financeAgentCashflowTitle => '现金流异常复盘';

  @override
  String get financeAgentCashflowDirectionHigher => '更高';

  @override
  String get financeAgentCashflowDirectionLower => '更低';

  @override
  String financeAgentCashflowSummary(Object delta) {
    return '现金流异常复盘：本月支出预测较过去 3 个月均值为 $delta。';
  }

  @override
  String get financeAgentCashflowInsightProjectionTitle => '月度支出预测';

  @override
  String financeAgentCashflowInsightProjectionBody(
    Object delta,
    Object direction,
  ) {
    return '当前月支出预计比过去 3 个月均值$direction $delta。';
  }

  @override
  String get financeAgentCashflowInsightDetectorTitle => '检测来源';

  @override
  String get financeAgentCashflowInsightDetectorBody =>
      '该结果来自 get_anomaly_flags 使用的本机异常检测器。';

  @override
  String get financeAgentCashflowEvidenceLabel => '月度支出异常';

  @override
  String get financeAgentCashflowAction => '查看异常';

  @override
  String get financeAgentFireSkipNoPlan => '尚未配置 FIRE 计划';

  @override
  String get financeAgentFireSkipNoDrift => '未检测到 FIRE 计划偏移';

  @override
  String financeAgentFireMemoryTitle(Object dayKey) {
    return 'FIRE 计划偏移监控 · $dayKey';
  }

  @override
  String get financeAgentFireTitle => 'FIRE 计划偏移监控';

  @override
  String get financeAgentFireInsightPlanSnapshotTitle => '计划快照';

  @override
  String financeAgentFireInsightPlanSnapshotBody(
    Object cashBucketMonths,
    Object safeRate,
    Object targetCashBucketMonths,
    Object withdrawalRate,
  ) {
    return '提取率 $withdrawalRate vs 安全提取率 $safeRate，现金桶 $cashBucketMonths / $targetCashBucketMonths 个月。';
  }

  @override
  String financeAgentFireEvidenceReviewLabel(Object periodKey) {
    return 'FIRE 复盘 $periodKey';
  }

  @override
  String get financeAgentFireEvidenceReviewBody => '当前计划指标、资产状态与风险阈值的确定性快照。';

  @override
  String get financeAgentFireAction => '查看 FIRE 计划';

  @override
  String get financeAgentFireActionBody => '打开 FIRE 页面，检查并调整计划参数。';

  @override
  String financeAgentFireSummaryWithdrawal(
    Object safeRate,
    Object withdrawalRate,
  ) {
    return '当前提取率 $withdrawalRate，安全线 $safeRate';
  }

  @override
  String financeAgentFireSummaryStress(int failedCount) {
    return '$failedCount 个压力场景未通过';
  }

  @override
  String get financeAgentFireSummarySeparator => '；';

  @override
  String get financeAgentFireMetricWithdrawalRate => '当前提取率';

  @override
  String get financeAgentFireMetricSafeRate => '安全提取率';

  @override
  String get financeAgentFireMetricCashBucket => '现金缓冲';

  @override
  String get financeAgentFireMetricTarget => '计划目标';

  @override
  String financeAgentFireMetricTargetMonths(int months) {
    return '目标 $months 个月';
  }

  @override
  String get financeAgentFireMetricExcess => '高出安全线';

  @override
  String get financeAgentFireMetricAffectedItems => '受影响项目';

  @override
  String get financeAgentFireMetricNetWorthAfter => '测试后净资产';

  @override
  String get financeAgentFireMetricWithdrawalAfter => '测试后提取率';

  @override
  String get financeAgentFireMetricCashAfter => '测试后现金缓冲';

  @override
  String financeAgentFireMonthsValue(Object value) {
    return '$value 个月';
  }

  @override
  String financeAgentFirePercentagePoints(Object value) {
    return '$value 个百分点';
  }

  @override
  String financeAgentFireStressGroupTitle(int count) {
    return '$count 个压力场景未通过';
  }

  @override
  String financeAgentFireStressGroupBody(Object scenarios) {
    return '风险集中在：$scenarios。';
  }

  @override
  String get financeAgentFireScenarioSeparator => '、';

  @override
  String get financeAgentFireScenarioMarketDrawdown => '市场回撤';

  @override
  String get financeAgentFireScenarioExpenseSurge => '生活成本上升';

  @override
  String get financeAgentFireScenarioOneOffShock => '一次性大额支出';

  @override
  String get financeAgentFireScenarioFxShock => '汇率冲击';

  @override
  String get financeAgentFireScenarioCashDepletion => '现金耗尽';

  @override
  String get financeAgentFireScenarioUnknown => '其他压力场景';

  @override
  String get financeAgentFireStressVerdictSafe => '通过';

  @override
  String get financeAgentFireStressVerdictCautious => '需关注';

  @override
  String get financeAgentFireStressVerdictDanger => '危险';

  @override
  String financeAgentFireStressResultContext(
    Object cashBucketMonths,
    Object withdrawalRate,
  ) {
    return '提取率 $withdrawalRate · 现金缓冲 $cashBucketMonths 个月';
  }

  @override
  String get financeAgentFireTrendTitle => '相比上次';

  @override
  String financeAgentFireTrendBody(Object changes) {
    return '$changes。';
  }

  @override
  String get financeAgentFireTrendWithdrawal => '提取率';

  @override
  String get financeAgentFireTrendNetWorth => '净资产';

  @override
  String get financeAgentFireTrendSafety => '安全等级';

  @override
  String get financeAgentFireMethodTitle => '本地确定性计算';

  @override
  String get financeAgentFireMethodBody =>
      '基于 FIRE 计划、资产负债、年度支出与压力测试计算；AI 不参与指标判定。';

  @override
  String get financeAgentFireMethodPeriodLabel => '分析周期';

  @override
  String get financeAgentFireMethodModeLabel => '计算方式';

  @override
  String get financeAgentFireMethodModeValue => '设备本地 · 无云端推断';

  @override
  String get financeAgentFireFindingCashBucketBelowTargetTitle => '现金桶低于目标';

  @override
  String get financeAgentFireFindingWithdrawalRateAboveSwrTitle => '提取率高于安全线';

  @override
  String get financeAgentFireFindingWithdrawalRateInfiniteTitle => '提取率不可用';

  @override
  String get financeAgentFireFindingEtaUnreachableTitle => '无法到达 FIRE 目标';

  @override
  String get financeAgentFireFindingCurrencyGapTitle => '汇率覆盖缺口';

  @override
  String get financeAgentFireFindingUnmappedHoldingsTitle => '未映射 FIRE 持仓';

  @override
  String get financeAgentFireFindingStressDangerTitle => '压力测试危险';

  @override
  String get financeAgentFireFindingStressCautiousTitle => '压力测试需关注';

  @override
  String get financeAgentFireFindingNetWorthBrokenTitle => '净资产低于零';

  @override
  String financeAgentFireFindingCashBucketBelowTargetBody(Object months) {
    return '现金续航低于已配置的 $months 个月目标。';
  }

  @override
  String financeAgentFireFindingWithdrawalRateAboveSwrBody(Object rate) {
    return '提取率高于安全提取率 $rate。';
  }

  @override
  String get financeAgentFireFindingWithdrawalRateInfiniteBody =>
      '存在年度支出，但可投资资产为零。';

  @override
  String get financeAgentFireFindingEtaUnreachableBody =>
      '预测在建模周期内未达到 FIRE 目标。';

  @override
  String financeAgentFireFindingCurrencyGapBody(Object count) {
    return '$count 个持仓因缺少汇率换算被排除。';
  }

  @override
  String financeAgentFireFindingUnmappedHoldingsBody(Object count) {
    return '$count 个持仓尚未映射到 FIRE 桶。';
  }

  @override
  String financeAgentFireFindingStressDangerBody(Object scenario) {
    return '压力场景 $scenario 会击穿计划。';
  }

  @override
  String financeAgentFireFindingStressCautiousBody(Object scenario) {
    return '压力场景 $scenario 需要关注。';
  }

  @override
  String get financeAgentFireFindingNetWorthBrokenBody => '净资产低于零，FIRE 计划需要复核。';

  @override
  String financeAgentFireFindingDefaultBody(Object code) {
    return '复核发现 $code。';
  }

  @override
  String get financeAgentOptionsSkipNoScan => '暂无期权收入扫描';

  @override
  String get financeAgentOptionsSkipNoFinding => '未发现期权收入风险';

  @override
  String financeAgentOptionsMemoryTitle(Object dayKey) {
    return '期权收入风险复盘 · $dayKey';
  }

  @override
  String get financeAgentOptionsTitle => '期权收入风险复盘';

  @override
  String financeAgentOptionsSummary(
    Object elevatedCount,
    Object issueTitle,
    Object opportunityCount,
    Object scanId,
  ) {
    return '期权收入风险复盘：$scanId 中 $opportunityCount 个机会存在「$issueTitle」，其中 $elevatedCount 个为高风险合约。';
  }

  @override
  String get financeAgentOptionsIssueStaleScanTitle => '扫描数据已过期';

  @override
  String financeAgentOptionsIssueStaleScanBody(Object ageHours) {
    return '最新期权收入扫描已是 $ageHours 小时前；报价和 Greeks 可能不再反映市场。';
  }

  @override
  String get financeAgentOptionsIssueElevatedRiskTitle => '存在高风险合约';

  @override
  String financeAgentOptionsIssueElevatedRiskBody(Object count) {
    return '$count 个缓存机会在交易复核前已被标记为高风险。';
  }

  @override
  String get financeAgentOptionsIssueQuoteQualityTitle => '报价质量需要复核';

  @override
  String financeAgentOptionsIssueQuoteQualityBody(
    Object thinBookCount,
    Object wideSpreadCount,
  ) {
    return '$wideSpreadCount 个机会买卖价差高于 8%，$thinBookCount 个成交量或未平仓量偏薄。';
  }

  @override
  String get financeAgentOptionsIssueNarrowCushionTitle => '安全边际偏窄';

  @override
  String financeAgentOptionsIssueNarrowCushionBody(Object count) {
    return '$count 个机会距离盈亏平衡的安全边际小于 5%。';
  }

  @override
  String get financeAgentOptionsIssueMissingGreeksTitle => '风险输入不完整';

  @override
  String financeAgentOptionsIssueMissingGreeksBody(Object count) {
    return '$count 个机会缺少报价源中的 delta 或隐含波动率。';
  }

  @override
  String get financeAgentOptionsIssueConcentrationTitle => '标的集中度偏高';

  @override
  String financeAgentOptionsIssueConcentrationBody(
    Object count,
    Object opportunityCount,
    Object underlying,
  ) {
    return '$opportunityCount 个机会中有 $count 个绑定到 $underlying。';
  }

  @override
  String get financeAgentOptionsIssueModerateClusterTitle => '中等风险机会集中';

  @override
  String financeAgentOptionsIssueModerateClusterBody(
    Object moderateCount,
    Object opportunityCount,
  ) {
    return '$opportunityCount 个机会中有 $moderateCount 个为中等风险；使用扫描前请复核仓位大小。';
  }

  @override
  String get financeAgentOptionsInsightScanSnapshotTitle => '扫描快照';

  @override
  String financeAgentOptionsInsightScanSnapshotBody(
    Object opportunityCount,
    Object riskMix,
  ) {
    return '$opportunityCount 个缓存机会，风险结构 $riskMix。';
  }

  @override
  String financeAgentOptionsRiskMix(
    Object elevated,
    Object low,
    Object moderate,
  ) {
    return '$low 低 / $moderate 中 / $elevated 高';
  }

  @override
  String financeAgentOptionsEvidenceScanLabel(Object scanId) {
    return '期权收入扫描 $scanId';
  }

  @override
  String get financeAgentOptionsAction => '查看期权扫描';

  @override
  String get healthAgentMorningSkipNoHealth => '过去 24 小时没有健康信号';

  @override
  String get healthAgentMorningSkipNoUsable => '有健康事件但没有可用信号';

  @override
  String healthAgentMorningMemoryTitle(Object dayKey) {
    return '晨间简报 · $dayKey';
  }

  @override
  String get healthAgentMorningTitle => '晨间简报';

  @override
  String get healthAgentMorningSleepShortTag => '（偏短）';

  @override
  String get healthAgentMorningSleepLongTag => '（偏长）';

  @override
  String healthAgentMorningSleepLine(Object hours, Object tag) {
    return '睡眠 $hours 小时$tag';
  }

  @override
  String healthAgentMorningHrvLine(Object value) {
    return 'HRV $value ms';
  }

  @override
  String healthAgentMorningFinanceLine(Object items) {
    return '财务：$items';
  }

  @override
  String healthAgentMorningPromptSystem(Object language) {
    return '你是 HealthOS 晨间简报。根据过去 24 小时的结构化健康和财务信号，写一句符合用户语气的晨间简报（简短、平静、事实化）。只使用提供的数字。除非数字明显异常，否则不要添加建议。请用$language回复。';
  }

  @override
  String get healthAgentMorningPromptStructuredSignals =>
      '结构化信号（原样使用这些数字，不要改写）：';

  @override
  String get healthAgentMorningPromptInstruction =>
      '写一句平静、事实化的句子（不超过 30 个词或 45 个汉字），提到每个信号。不要列点。不要使用表情。';

  @override
  String get healthAgentMorningInsightSleepTitle => '睡眠';

  @override
  String get healthAgentMorningInsightHrvTitle => 'HRV';

  @override
  String get healthAgentMorningInsightFinanceTitle => '财务';

  @override
  String get healthAgentMorningAction => '查看简报';

  @override
  String healthAgentRecoverySkipInsufficient(Object count) {
    return 'HRV 数据不足（$count 个点）';
  }

  @override
  String get healthAgentRecoverySkipNoDecline => '未检测到持续 HRV 下降';

  @override
  String healthAgentRecoveryMemoryTitle(Object dayKey) {
    return '恢复提醒 · $dayKey';
  }

  @override
  String get healthAgentRecoveryTitle => '恢复提醒';

  @override
  String healthAgentRecoverySummary(
    Object baselineMs,
    Object days,
    Object declinePct,
    Object recentMs,
  ) {
    return 'HRV 已连续 $days 天低于基线（近期 $recentMs ms vs 平均 $baselineMs ms，下降 $declinePct%）。今天可考虑降低活动强度。';
  }

  @override
  String healthAgentRecoveryNotificationBody(Object days, Object declinePct) {
    return 'HRV 在 $days 天内下降 $declinePct%。今天可考虑降低活动强度。';
  }

  @override
  String get healthAgentRecoveryInsightDeclineTitle => 'HRV 下降';

  @override
  String healthAgentRecoveryInsightDeclineBody(Object days, Object declinePct) {
    return '连续 $days 天低于基线；比平时低 $declinePct%。';
  }

  @override
  String get healthAgentRecoveryInsightAdjustmentTitle => '调整建议';

  @override
  String get healthAgentRecoveryInsightAdjustmentBody =>
      '今天可考虑降低活动强度，并观察明天恢复情况。';

  @override
  String get healthAgentRecoveryEvidenceLabel => 'HRV 趋势';

  @override
  String get healthAgentRecoveryAction => '查看恢复提醒';

  @override
  String get healthAgentWeeklySkipNoData => '本周没有健康数据';

  @override
  String get healthAgentWeeklySkipNoActionable => '本周没有可行动信号';

  @override
  String healthAgentWeeklyMemoryTitle(Object dayKey) {
    return '每周健康总结 · $dayKey';
  }

  @override
  String get healthAgentWeeklyTitle => '每周健康总结';

  @override
  String healthAgentWeeklyPartRecovery(Object score, Object verdict) {
    return '恢复 $score/100（$verdict）';
  }

  @override
  String healthAgentWeeklyPartAvgSleep(Object hours) {
    return '平均睡眠 $hours 小时';
  }

  @override
  String healthAgentWeeklyPartSteps(Object steps) {
    return '$steps 步';
  }

  @override
  String healthAgentWeeklyPartWorkouts(Object count, Object minutes) {
    return '$count 次训练（$minutes 分钟）';
  }

  @override
  String healthAgentWeeklySummary(Object details) {
    return '本周：$details。';
  }

  @override
  String get healthAgentWeeklyInsightRecoveryTitle => '恢复';

  @override
  String healthAgentWeeklyInsightRecoveryBody(
    Object score,
    Object verdictSuffix,
  ) {
    return '$score/100$verdictSuffix';
  }

  @override
  String get healthAgentWeeklyInsightSleepTitle => '睡眠';

  @override
  String healthAgentWeeklyInsightSleepBody(Object hours) {
    return '平均每晚 $hours 小时。';
  }

  @override
  String get healthAgentWeeklyInsightActivityTitle => '活动';

  @override
  String healthAgentWeeklyInsightActivityBody(Object steps) {
    return '本周 $steps 步。';
  }

  @override
  String get healthAgentWeeklyInsightWorkoutsTitle => '训练';

  @override
  String healthAgentWeeklyInsightWorkoutsBody(Object count, Object minutes) {
    return '$count 次训练，共 $minutes 分钟。';
  }

  @override
  String get healthAgentWeeklyEvidenceLabel => '每周健康汇总';

  @override
  String get healthAgentWeeklyAction => '查看每周总结';

  @override
  String get executionAgentReviewSkipNoSignals => '暂无可复盘的执行信号';

  @override
  String executionAgentReviewMemoryTitle(Object dayKey) {
    return '执行复盘 · $dayKey';
  }

  @override
  String get executionAgentReviewTitle => '执行复盘';

  @override
  String executionAgentReviewSummary(Object details, Object sample) {
    return '执行复盘：$details。$sample';
  }

  @override
  String executionAgentReviewSummaryPartToday(Object count) {
    return '$count 个今日行动';
  }

  @override
  String executionAgentReviewSummaryPartOpen(Object count) {
    return '$count 个未完成行动';
  }

  @override
  String executionAgentReviewSummaryPartProjects(Object count) {
    return '$count 个活跃项目';
  }

  @override
  String executionAgentReviewSummaryPartCommitments(Object count) {
    return '$count 个活跃承诺';
  }

  @override
  String executionAgentReviewSummaryPartProgress(Object count) {
    return '本周 $count 条进展';
  }

  @override
  String executionAgentReviewSummaryPartBlocked(Object count) {
    return '$count 个阻塞';
  }

  @override
  String executionAgentReviewSummaryPartDue(Object count) {
    return '$count 个到期';
  }

  @override
  String executionAgentReviewSummaryFirst(Object title) {
    return '第一项：$title。';
  }

  @override
  String get executionAgentReviewInsightTodayTitle => '今日焦点';

  @override
  String executionAgentReviewInsightTodayBody(
    Object openCount,
    Object todayCount,
  ) {
    return '$openCount 个未完成行动中，有 $todayCount 个值得今天处理。';
  }

  @override
  String get executionAgentReviewInsightBlockedTitle => '阻塞事项';

  @override
  String executionAgentReviewInsightBlockedBody(Object count) {
    return '$count 个行动被阻塞。';
  }

  @override
  String get executionAgentReviewInsightDueTitle => '到期事项';

  @override
  String executionAgentReviewInsightDueBody(Object count) {
    return '$count 个行动已到期。';
  }

  @override
  String get executionAgentReviewInsightProgressTitle => '每周进展';

  @override
  String executionAgentReviewInsightProgressBody(
    Object commitmentCount,
    Object progressCount,
    Object projectCount,
  ) {
    return '$projectCount 个活跃项目和 $commitmentCount 个活跃承诺下有 $progressCount 条进展。';
  }

  @override
  String get executionAgentReviewAction => '查看执行复盘';

  @override
  String get knowledgeAgentReviewArtifactTitle => '每周知识复盘';

  @override
  String get knowledgeAgentReviewInsightDecisionsTitle => '到期决策';

  @override
  String knowledgeAgentReviewInsightDecisionsBody(Object count, Object plural) {
    return '$count 个决策复盘需要关注。';
  }

  @override
  String get knowledgeAgentReviewInsightAssumptionsTitle => '过期假设';

  @override
  String knowledgeAgentReviewInsightAssumptionsBody(
    Object count,
    Object days,
    Object plural,
  ) {
    return '$count 个假设已超过 $days 天验证窗口。';
  }

  @override
  String get knowledgeAgentReviewAction => '查看知识事项';

  @override
  String get knowledgeAgentAssumptionArtifactTitle => '假设复盘';

  @override
  String get knowledgeAgentAssumptionInsightTitle => '过期假设';

  @override
  String knowledgeAgentAssumptionInsightBody(
    Object count,
    Object days,
    Object plural,
  ) {
    return '$count 个假设已超过 $days 天验证窗口。';
  }

  @override
  String get knowledgeAgentAssumptionAction => '查看假设';

  @override
  String get knowledgeAgentContradictionArtifactTitle => '矛盾检查';

  @override
  String get knowledgeAgentContradictionInsightInvalidatedTitle => '已失效假设';

  @override
  String knowledgeAgentContradictionInsightInvalidatedBody(
    Object count,
    Object plural,
  ) {
    return '$count 个决策引用了不再开放的假设。';
  }

  @override
  String get knowledgeAgentContradictionInsightPrincipleTitle => '原则漂移';

  @override
  String knowledgeAgentContradictionInsightPrincipleBody(
    Object count,
    Object plural,
  ) {
    return '$count 个近期项目可能与活跃原则冲突。';
  }

  @override
  String get knowledgeAgentContradictionAction => '查看矛盾项';

  @override
  String get knowledgeAgentRoutineArtifactTitle => '例行事项到期';

  @override
  String get knowledgeAgentRoutineInsightOverdueTitle => '逾期例行事项';

  @override
  String knowledgeAgentRoutineInsightOverdueBody(Object count, Object plural) {
    return '$count 个例行事项已逾期。';
  }

  @override
  String get knowledgeAgentRoutineInsightUpcomingTitle => '即将到期例行事项';

  @override
  String knowledgeAgentRoutineInsightUpcomingBody(
    Object count,
    Object days,
    Object plural,
  ) {
    return '$count 个例行事项将在 $days 天内到期。';
  }

  @override
  String get knowledgeAgentRoutineAction => '查看例行事项';

  @override
  String get knowledgeAgentInboxSkipNoNotes => '没有待 triage 的 note';

  @override
  String knowledgeAgentInboxSummaryNoSuggestions(Object noteCount) {
    return '已查看 $noteCount 条 note，未找到值得提议的内容。';
  }

  @override
  String knowledgeAgentInboxSummarySuggestions(
    Object noteCount,
    Object proposalCount,
  ) {
    return '为 $noteCount 条 note 生成了 $proposalCount 条建议。';
  }

  @override
  String get knowledgeAgentInboxArtifactTitle => 'Inbox Triage';

  @override
  String get knowledgeAgentInboxInsightSuggestionsTitle => '新建议';

  @override
  String knowledgeAgentInboxInsightSuggestionsBody(
    Object noteCount,
    Object notePlural,
    Object proposalCount,
    Object proposalPlural,
  ) {
    return '$noteCount 条 note 中共有 $proposalCount 条建议。';
  }

  @override
  String knowledgeAgentInboxSuggestionKindBody(Object count, Object label) {
    return '$count 条建议。';
  }

  @override
  String get knowledgeAgentInboxUntitledNote => '未命名 note';

  @override
  String get knowledgeAgentInboxProposalClassification => '分类';

  @override
  String get knowledgeAgentInboxProposalTags => '标签';

  @override
  String get knowledgeAgentInboxProposalDecisionLinks => '关联决策';

  @override
  String get knowledgeAgentInboxProposalSuggestionSingular => '建议';

  @override
  String get knowledgeAgentInboxProposalSuggestionPlural => '建议';

  @override
  String get knowledgeAgentInboxAction => '查看 Inbox 建议';

  @override
  String get ingestKindExpense => '支出';

  @override
  String get ingestKindIncome => '收入';

  @override
  String get databaseUnlockLoading => '正在解锁本地数据…';

  @override
  String get databaseRecoveryTitle => '本地数据已锁定';

  @override
  String get databaseRecoveryMissingKeyMessage =>
      '此设备已没有加密本地数据库所需的密钥。现有数据未被覆盖。如果你有加密备份，可重置这份无法读取的本地数据，再从设置中恢复备份。';

  @override
  String get databaseRecoveryInvalidKeyMessage =>
      '设备中保存的数据库密钥已损坏。加密数据没有被修改。你可以重试，或重置无法读取的副本后恢复加密备份。';

  @override
  String get databaseRecoveryUnlockFailedMessage =>
      '设备密钥无法解锁本地数据库，数据没有被修改。你可以重试，或重置无法读取的副本后恢复加密备份。';

  @override
  String get databaseRecoveryMigrationTitle => '本地数据升级已暂停';

  @override
  String get databaseRecoveryMigrationMessage =>
      'NaviWealth 无法安全完成现有数据库的加密迁移，原始副本仍被保留。请检查可用存储空间后重试；没有已验证备份时不要重置。';

  @override
  String get databaseRecoveryUnavailableTitle => '本地数据暂不可用';

  @override
  String get databaseRecoveryUnavailableMessage =>
      '安全数据库无法打开。请先重试；如果问题持续，请保留应用数据并检查诊断日志，不要直接执行破坏性操作。';

  @override
  String get databaseRecoveryRetry => '重新解锁';

  @override
  String get databaseRecoveryResetAction => '重置无法读取的本地数据';

  @override
  String get databaseRecoveryResetting => '正在重置本地数据…';

  @override
  String get databaseRecoveryResetConfirmTitle => '重置无法读取的本地数据？';

  @override
  String get databaseRecoveryResetConfirmBody =>
      '这会永久删除此设备上的加密数据库，且无法找回已丢失的设备密钥。仅当本地副本确定无法恢复，或你已有可随后恢复的加密备份时继续。';

  @override
  String get databaseRecoveryResetConfirmAction => '重置本地数据';

  @override
  String get databaseRecoveryResetFailed => '无法重置本地数据，其他内容未被更改。';
}
