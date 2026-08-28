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
  String get navActivity => '记录';

  @override
  String get navAccounts => '账户';

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
  String get planRebalanceSectionTitle => '再平衡';

  @override
  String get planIncomeSectionSubtitle => '股息、Wheel 与 LEAPS';

  @override
  String get planBudgetSectionTitle => '预算';

  @override
  String get planAttentionTitle => '需要关注';

  @override
  String planAttentionShowAll(int count) {
    return '再查看 $count 项';
  }

  @override
  String get planAttentionCollapse => '收起';

  @override
  String planAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String get planCashSafetyTitle => '现金安全';

  @override
  String get planLongTermGoalsTitle => '目标与场景';

  @override
  String get planInvestmentPlanTitle => '投资';

  @override
  String get planIncomeStrategiesTitle => '收益策略';

  @override
  String planExploreActiveOptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个期权持仓',
    );
    return '$_temp0';
  }

  @override
  String get planDcaPlanTitle => '定投计划';

  @override
  String get planFireGoalTitle => '财务自由';

  @override
  String get planFireGoalNotConfigured => '需要时再设定长期目标';

  @override
  String get planStatusNeedsSetup => '待设置';

  @override
  String get planStatusLoading => '正在读取状态…';

  @override
  String get planStatusUnavailable => '状态暂不可用';

  @override
  String get planStatusPartiallyUnavailable => '部分规划状态暂不可用。';

  @override
  String get planStatusView => '查看';

  @override
  String get planStatusInProgress => '进行中';

  @override
  String get planStatusOnTrack => '正常';

  @override
  String get planStatusNeedsAttention => '待复盘';

  @override
  String get planStatusActionRequired => '需处理';

  @override
  String get planStatusNoPendingReviews => '暂无待复盘项';

  @override
  String planStatusPendingReviews(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项待复盘',
    );
    return '$_temp0';
  }

  @override
  String get planStatusRebalanceBalanced => '配置达标';

  @override
  String planStatusRebalanceAttention(String percent) {
    return '偏离 $percent%';
  }

  @override
  String get planStatusRebalanceActive => '执行中';

  @override
  String planStatusBudgetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个类别上限',
    );
    return '$_temp0';
  }

  @override
  String get planStatusBudgetComfortable => '本月支出在计划内';

  @override
  String planStatusBudgetUsed(String percent) {
    return '本月已使用 $percent%';
  }

  @override
  String get planStatusBudgetStrained => '本月预算接近上限';

  @override
  String get planStatusBudgetOver => '本月预算已超支';

  @override
  String planStatusFireProgress(String percent) {
    return '已完成目标的 $percent%';
  }

  @override
  String get planStatusDcaDue => '本期定投待执行';

  @override
  String planStatusDcaNext(String date) {
    return '下次 $date';
  }

  @override
  String get planStatusDcaPaused => '计划均已暂停';

  @override
  String get planBudgetTitle => '预算';

  @override
  String get planBudgetEmptyTitle => '暂无预算';

  @override
  String get planBudgetEmptyBody => '为任意类别设定月度上限，本页会显示实际花销与上限的对比。';

  @override
  String get planBudgetEmptyCta => '设置第一笔预算';

  @override
  String get planBudgetAddAction => '新增预算';

  @override
  String get planBudgetCreateTitle => '新建预算';

  @override
  String get planBudgetCategoryLabel => '支出类别';

  @override
  String get planBudgetCategoryHelper => '选择需要按月跟踪支出上限的类别。';

  @override
  String get planBudgetCategoryRequired => '请选择支出类别。';

  @override
  String get planBudgetNoAvailableCategories => '本月所有支出类别都已设置预算。';

  @override
  String get planBudgetPreviousMonth => '上个月';

  @override
  String get planBudgetCopyPreviousAction => '复制上月预算';

  @override
  String planBudgetCopied(int count) {
    return '已从上月复制 $count 项预算';
  }

  @override
  String planBudgetCurrencyMismatch(int count) {
    return '有 $count 项预算使用其他币种，未计入当前汇总。';
  }

  @override
  String get planBudgetNextMonth => '下个月';

  @override
  String planBudgetPeriodCurrency(String month, String currency) {
    return '$month · $currency';
  }

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
  String get planBudgetDeleteAction => '删除预算';

  @override
  String get planBudgetDeleteTitle => '删除这笔预算？';

  @override
  String get planBudgetDeleteBody => '这会移除所选月份的类别上限，不会影响已经记录的支出。';

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
  String get planWheelTitle => 'Wheel 周期';

  @override
  String get planWheelEmptyTitle => '暂无进行中的周期';

  @override
  String get planWheelEmptyBody => '录入一次卖 put 或备兑 call 交易后，周期会显示在这里。';

  @override
  String get planWheelHistoryTitle => '周期记录';

  @override
  String get planWheelStageBetween => '周期间歇';

  @override
  String get planWheelStageCashWaiting => '现金待命';

  @override
  String get planWheelStageShortPut => '卖出 Put（持仓中）';

  @override
  String get planWheelStagePutExpired => 'Put 已到期';

  @override
  String get planWheelStagePutAssigned => 'Put 已行权';

  @override
  String get planWheelStageSharesHeld => '持有正股';

  @override
  String get planWheelStageShortCall => '备兑 Call（持仓中）';

  @override
  String get planWheelStageCallExpired => 'Call 已到期';

  @override
  String get planWheelStageCallCalled => '正股已被行权卖出';

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
  String get wealthObjectsTitle => '资产项目';

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
  String get cashFlowShowOriginalCurrencies => '显示原币金额';

  @override
  String get cashFlowShowBaseCurrency => '显示本位币金额';

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
  String get cashFlowKpiOutflow => '现金支出';

  @override
  String get cashFlowKpiNet => '经营净额';

  @override
  String get cashFlowIncomeExpenseTitle => '收入 vs 支出';

  @override
  String get cashFlowNetTrendTitle => '净现金流趋势';

  @override
  String get cashFlowCategoryTitle => '类目分布';

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
  String get recurringDeleteTitle => '删除规则？';

  @override
  String get recurringDeleteBody => '该周期规则将被删除，删除后可在提示中撤销。';

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
  String get dividendCenterMetricTtmNet => '近 12 月税后';

  @override
  String dividendCenterMetricTtmNetCaption(String ratio) {
    return '预扣税后保留 $ratio';
  }

  @override
  String get dividendCenterMetricYoy => '同比同期';

  @override
  String get dividendCenterMetricWithholding => '预扣税';

  @override
  String get dividendCenterPolicyTitle => '股息收入关注';

  @override
  String dividendCenterPolicyBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 只持仓的已记录股息现金较前一年下滑',
    );
    return '$_temp0';
  }

  @override
  String get dividendCenterPolicySeverityWarning => '预警';

  @override
  String get dividendCenterPolicySeverityCritical => '严重';

  @override
  String dividendCenterPolicyDropLine(String percent) {
    return '下滑 $percent%';
  }

  @override
  String get dividendResilienceTitle => '历史股息韧性';

  @override
  String dividendResilienceConfidence(String confidence) {
    return '$confidence置信度';
  }

  @override
  String get dividendResilienceConfidenceHigh => '高';

  @override
  String get dividendResilienceConfidenceMedium => '中';

  @override
  String get dividendResilienceConfidenceLow => '低';

  @override
  String get dividendResilienceNoCoverage => '暂无可用的已记录历史。';

  @override
  String dividendResilienceCoverage(
    String start,
    String end,
    int months,
    int recordedMonths,
  ) {
    return '$start–$end · 覆盖 $months 个月 · 已记录 $recordedMonths 个派息月';
  }

  @override
  String dividendResilienceCadenceCoverage(
    int expected,
    int missing,
    int irregular,
  ) {
    return '节奏检查：预计 $expected 次 · 疑似缺失 $missing 次 · $irregular 个不规则资产';
  }

  @override
  String get dividendResilienceNetSeries => '税后';

  @override
  String get dividendResilienceChartLabel => '滚动十二个月税前与税后股息收入';

  @override
  String get dividendResilienceIncomeCagr => '税后收入复合增速';

  @override
  String get dividendResilienceMaxDrawdown => '最大收入跌幅';

  @override
  String get dividendResilienceLargestSource => '最大收入来源';

  @override
  String get dividendResilienceRetention => '税后留存率';

  @override
  String get dividendResilienceNotRecovered => '尚未恢复';

  @override
  String dividendResilienceRecoveredIn(int months) {
    return '$months 个月后恢复';
  }

  @override
  String get dividendResilienceAttributionTitle => '较前 12 个月的变化来源';

  @override
  String get dividendResilienceAttributionHint => '仅在账本包含足够的每股分红和汇率证据时拆分影响。';

  @override
  String dividendResilienceAttributionSplit(
    String holding,
    String unit,
    String fx,
  ) {
    return '持仓 $holding · 每股 $unit · 汇率 $fx';
  }

  @override
  String dividendResilienceAttributionCombined(String local, String fx) {
    return '持仓/每股 $local · 汇率 $fx';
  }

  @override
  String get dividendResilienceDriverHolding => '主要来源：持仓数量';

  @override
  String get dividendResilienceDriverUnitDividend => '主要来源：每股分红';

  @override
  String get dividendResilienceDriverFx => '主要来源：汇率';

  @override
  String get dividendResilienceDriverCombined => '持仓与每股分红影响未拆分';

  @override
  String dividendResilienceMethodology(int matchedPercent, int excludedCount) {
    return '基于你的已记录账本，不是组合回测。$matchedPercent% 的已归属记录具有每股分红证据；另有 $excludedCount 笔因缺少汇率未计入。';
  }

  @override
  String get financialInboxEvidencePrimaryDriver => '主要变化来源';

  @override
  String get financialInboxEvidenceUnitDividend => '具有每股分红证据';

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
  String get dividendCenterRankingNetYieldOnCost => '税后成本收益率';

  @override
  String get dividendCenterRankingWithholding => '税额';

  @override
  String get dividendCenterForecastTitle => '未来 12 个月';

  @override
  String get dividendCenterForecastUnavailable => '历史记录或已宣告派息不足，暂无法预测。';

  @override
  String dividendCenterForecastHistoricalError(String error, int count) {
    return '90 天历史误差 $error，基于 $count 次评估';
  }

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
    return '确定删除 $asset 的股息记录？删除后可在提示中撤销。';
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
  String get portfolioAllHoldings => '全部持仓';

  @override
  String get portfolioUnassigned => '未分类';

  @override
  String get portfolioManageTitle => '组合设置';

  @override
  String get portfolioCreateTitle => '新建组合';

  @override
  String get portfolioEditTitle => '编辑组合';

  @override
  String get portfolioNameLabel => '组合名称';

  @override
  String get portfolioNameRequired => '请输入组合名称。';

  @override
  String get portfolioStrategyLabel => '策略';

  @override
  String get portfolioCreateApproachTitle => '选择投资方式';

  @override
  String get portfolioCreateApproachHint => '先使用清晰的默认方案，之后仍可调整配置。';

  @override
  String get portfolioCreateRecommendedHint => '推荐作为长期分散投资的核心配置';

  @override
  String get portfolioCreateCustomizableHint => '聚焦特定目标，之后可以继续调整';

  @override
  String get portfolioStrategyIndexCore => '指数核心';

  @override
  String get portfolioStrategyDividendIncome => '股息组合';

  @override
  String get portfolioStrategyOptionsIncome => '期权收益';

  @override
  String get portfolioStrategyIncome => '股息收入';

  @override
  String get portfolioStrategyGrowth => '成长';

  @override
  String get portfolioStrategyPreservation => '资本保全';

  @override
  String get portfolioStrategyGoalLinked => '关联目标';

  @override
  String get portfolioStrategyCustom => '自定义';

  @override
  String get portfolioStrategyCustomCreateAction => '创建策略类型';

  @override
  String get portfolioStrategyCustomNameLabel => '策略类型名称';

  @override
  String get portfolioStrategyCapitalRoleLabel => '资本角色';

  @override
  String get portfolioStrategyCapitalOwner => '拥有独立资金占比';

  @override
  String get portfolioStrategyCapitalOverlay => '叠加策略（不占资金比例）';

  @override
  String get portfolioStrategyDefaultAssetLabel => '默认资产类别';

  @override
  String get portfolioAnnualIncomeTargetLabel => '年度收入目标（可选）';

  @override
  String get portfolioNoPortfolios => '创建组合，按投资目的分类持仓。';

  @override
  String get portfolioAssignLotsTitle => '纳入持仓';

  @override
  String get portfolioAssignLotsSubtitle => '选择要纳入组合策略仓的买入批次。';

  @override
  String get portfolioAssignCashTitle => '纳入现金';

  @override
  String get portfolioAssignCashSubtitle => '从资产账户中划分现金，纳入一个策略仓。';

  @override
  String get portfolioAssignCashAction => '纳入现金';

  @override
  String get portfolioCashAssignmentsTitle => '已纳入现金';

  @override
  String get portfolioCashAccountLabel => '资产账户';

  @override
  String get portfolioCashAmountLabel => '分配金额';

  @override
  String get portfolioCashAmountInvalid => '请输入大于零的金额。';

  @override
  String get portfolioCashNoAccounts => '请先创建资产账户，再分配现金。';

  @override
  String portfolioCashAssignmentSummary(
    String amount,
    String currency,
    String group,
  ) {
    return '$amount $currency · $group';
  }

  @override
  String get portfolioAssignmentSaved => '纳入资产已保存。';

  @override
  String get portfolioStudioTitle => '组合工作台';

  @override
  String get portfolioStudioNotFound => '该组合不存在或已删除。';

  @override
  String get portfolioStudioPlanTitle => '投资计划';

  @override
  String get portfolioStudioPlanHint => '目标与实际偏离会在这里汇总；进入组合可调整策略仓、资产和规则。';

  @override
  String get portfolioStudioPlanEmptyHint => '创建第一个组合，开始定义资金用途与再平衡目标。';

  @override
  String get portfolioStudioPlanTargetLabel => '计划目标';

  @override
  String portfolioStudioTargetSummary(String target, int count) {
    return '计划目标 $target% · $count 个策略仓';
  }

  @override
  String get portfolioStudioConfiguredStatus => '已配置';

  @override
  String get portfolioStudioSleevesMetric => '策略仓';

  @override
  String get portfolioStudioAssetsMetric => '纳入资产';

  @override
  String get portfolioStudioRulesMetric => '规则';

  @override
  String get portfolioStudioRebalanceAction => '检查再平衡';

  @override
  String get portfolioStudioOverviewTab => '概览';

  @override
  String get portfolioStudioStructureTab => '结构';

  @override
  String get portfolioStudioAssetsTab => '资产';

  @override
  String get portfolioStudioRulesTab => '规则';

  @override
  String get portfolioStudioConfigurationTitle => '组合设置';

  @override
  String get portfolioStudioConfigurationHint => '只进入当前需要调整的部分。';

  @override
  String portfolioStudioSleeveCount(int count) {
    return '$count 个策略';
  }

  @override
  String portfolioStudioIncludedAssetCount(int count) {
    return '已纳入 $count 项资产';
  }

  @override
  String portfolioStudioRuleCount(int count) {
    return '$count 条可选规则';
  }

  @override
  String get portfolioStudioAllocationTitle => '资金路径';

  @override
  String get portfolioStudioAllocationHint => '计划 → 组合 → 策略仓 → 资产目标，一条路径完成配置。';

  @override
  String get portfolioStudioNextActionTitle => '下一步';

  @override
  String get portfolioStudioNextActionHint => '统一调整策略仓比例，合计始终保持 100%。';

  @override
  String get portfolioStudioStructureTitle => '策略仓';

  @override
  String get portfolioStudioStructureHint => '每个策略仓拥有独立资金目标与仓内资产配置。';

  @override
  String portfolioStudioSleeveSummary(String target, int count, String policy) {
    return '目标 $target% · $count 项资产目标 · $policy';
  }

  @override
  String get portfolioStudioIncludedAssetsTitle => '纳入资产';

  @override
  String get portfolioStudioIncludedAssetsHint => '在当前组合中选择持仓与现金，并明确归属的策略仓。';

  @override
  String get portfolioStudioAssetTargetsHint => '每个策略仓计划配置的资产类别与具体标的。';

  @override
  String get portfolioStudioNoIncludedAssets => '尚未纳入持仓或现金。';

  @override
  String get portfolioStudioIncludedPositionLabel => '持仓批次';

  @override
  String get portfolioStudioIncludePositionAction => '纳入持仓';

  @override
  String get portfolioStudioIncludeCashAction => '纳入现金';

  @override
  String get portfolioStudioAddAssetsAction => '添加资产';

  @override
  String get portfolioStudioAddAssetsHint => '选择要纳入的持仓或现金余额。';

  @override
  String get portfolioStudioRulesTitle => '规则与增强';

  @override
  String get portfolioStudioRulesHint => '规则附着在策略仓上，不单独占用资金比例。';

  @override
  String get portfolioStudioNoRules => '暂无额外规则；策略仓仍按自身目标运行。';

  @override
  String portfolioStudioAssetTargetCount(int count) {
    return '$count 项资产目标';
  }

  @override
  String get portfolioTrendTitle => '组合趋势';

  @override
  String get portfolioTrendHint => '区分市值变化与资金进出，并可切换查看现金流调整后的组合表现。';

  @override
  String get portfolioTrendMarketValue => '市值';

  @override
  String get portfolioTrendPerformance => '收益';

  @override
  String get portfolioTrendCurrentValue => '当前市值';

  @override
  String get portfolioTrendPeriodPerformance => '期间收益';

  @override
  String get portfolioTrendNetFlow => '净资金流';

  @override
  String get portfolioTrendAwaitingData => '纳入资产或现金后，将在这里生成趋势。';

  @override
  String get portfolioTrendEstimatedDisclosure => '部分时点使用了估算价格或不完整的汇率历史。';

  @override
  String get portfolioTrendChartSemantics => '组合市值与收益趋势';

  @override
  String get portfolioTrendMonthSemantics => '组合近一个月收益趋势';

  @override
  String get portfolioTrendRangeYtd => '年初';

  @override
  String get rebalancePortfoliosTitle => '组合资金配置';

  @override
  String get rebalanceCapitalTreeHint => '组合间资金调拨 → 组合内策略配置 → 策略内资产配置';

  @override
  String rebalancePortfolioWeightPair(String actual, String target) {
    return '当前 $actual · 目标 $target';
  }

  @override
  String get rebalancePortfolioTransfersTitle => '组合间资金调拨';

  @override
  String get rebalanceGroupsTitle => '再平衡分组';

  @override
  String rebalanceGroupWeight(String percent) {
    return '目标 $percent';
  }

  @override
  String get rebalanceGroupTransfersTitle => '组间资金调拨';

  @override
  String rebalanceGroupTransfer(String from, String to, String amount) {
    return '$from → $to：$amount';
  }

  @override
  String get portfolioGroupsSectionTitle => '策略仓';

  @override
  String get portfolioAllocationSectionTitle => '组合资金占比';

  @override
  String portfolioAllocationWeightSummary(String weight) {
    return '全局目标 $weight%';
  }

  @override
  String get portfolioAllocationEditTitle => '编辑组合资金配置';

  @override
  String get portfolioAllocationPlanSubtitle => '统一设置所有组合的比例，合计必须为 100%。';

  @override
  String get portfolioAllocationTargetWeightLabel => '全局目标占比（%）';

  @override
  String get portfolioAllocationSingleTargetHint =>
      '只有一个组合时必须保持 100%。请先添加另一个组合，再调整目标占比。';

  @override
  String get portfolioGroupAddAction => '添加策略仓';

  @override
  String get portfolioStrategyAllocationEditTitle => '编辑策略仓比例';

  @override
  String get portfolioStrategyAllocationPlanSubtitle =>
      '统一设置所有策略仓的比例，合计必须为 100%。';

  @override
  String get portfolioOverlayAddAction => '添加规则';

  @override
  String get portfolioOverlayNoTemplates => '请先创建规则类型，再将其附加到策略仓。';

  @override
  String get portfolioOverlayHostGroupLabel => '应用到策略仓';

  @override
  String get portfolioOverlaySectionTitle => '规则与增强';

  @override
  String get portfolioOverlayDeleteAction => '删除规则';

  @override
  String get portfolioOverlayDeleteConfirmation =>
      '该规则将从当前策略仓移除，不会影响纳入资产和会计账本。';

  @override
  String get portfolioGroupEditTitle => '编辑策略仓';

  @override
  String get portfolioGroupNameLabel => '策略仓名称';

  @override
  String get portfolioStrategyDeleteAction => '删除策略仓';

  @override
  String get portfolioStrategyDeleteLastBlocked =>
      '组合至少需要保留一个资金策略；若不再需要，请删除整个组合。';

  @override
  String get portfolioStrategyDeleteFailed => '策略删除失败，请重试。';

  @override
  String portfolioStrategyDeleteTransferDescription(
    String weight,
    int assignmentCount,
    int overlayCount,
  ) {
    return '当前 $weight% 目标比例和 $assignmentCount 项资产或现金归属将转移到所选策略；$overlayCount 个叠加策略会一并删除。';
  }

  @override
  String get portfolioGroupTargetWeightLabel => '组合目标占比（%）';

  @override
  String get portfolioGroupSingleTargetHint =>
      '只有一个策略时必须保持 100%。请先添加另一个策略，再调整目标占比。';

  @override
  String get portfolioGroupDriftBandLabel => '允许偏差（%）';

  @override
  String get portfolioGroupTransferPolicyLabel => '资金调拨规则';

  @override
  String get portfolioGroupTransferBidirectional => '自由调拨';

  @override
  String get portfolioGroupTransferInflowsOnly => '只接收资金';

  @override
  String get portfolioGroupTransferIsolated => '独立管理';

  @override
  String get capitalAllocationTotalLabel => '配置合计';

  @override
  String get capitalAllocationEditAction => '编辑';

  @override
  String capitalAllocationTotalHint(String total) {
    return '当前合计 $total%。请调整所有项目，使合计为 100%。';
  }

  @override
  String get capitalAllocationAdvancedAction => '资金规则与允许偏差';

  @override
  String get capitalAllocationBalanceEvenlyAction => '平均分配';

  @override
  String get capitalAllocationFillRemainderAction => '自动补足';

  @override
  String get capitalAllocationToleranceLabel => '允许偏差（%）';

  @override
  String get capitalAllocationRuleLabel => '资金规则';

  @override
  String get capitalAllocationRuleBidirectional => '自由调拨';

  @override
  String get capitalAllocationRuleBidirectionalDescription =>
      '资金可以流入，也可以从这里调出。';

  @override
  String get capitalAllocationRuleInflowsOnly => '只接收资金';

  @override
  String get capitalAllocationRuleInflowsOnlyDescription =>
      '允许补充资金，但不会自动调出现有资金。';

  @override
  String get capitalAllocationRuleIsolated => '独立管理';

  @override
  String get capitalAllocationRuleIsolatedDescription => '不参与任何方向的自动资金调拨。';

  @override
  String get capitalAllocationSaveFailed => '无法保存配置计划，请重试。';

  @override
  String portfolioGroupWeightSummary(String weight, String policy) {
    return '目标 $weight% · $policy';
  }

  @override
  String get portfolioGroupNoTemplates => '暂无可用的资金策略类型。';

  @override
  String get portfolioSaveFailed => '组合保存失败，请重试。';

  @override
  String get portfolioDeleteFailed => '组合删除失败，请重试。';

  @override
  String get portfolioDeleteAction => '删除组合';

  @override
  String get portfolioDeleteConfirmation =>
      '该组合中的资产与现金归属将被清除，策略配置也会一并删除；会计账本不会改变。';

  @override
  String portfolioDeleteTransferDescription(
    String weight,
    int assignmentCount,
  ) {
    return '当前 $weight% 目标比例和 $assignmentCount 项资产或现金归属将转移到所选策略，原组合及其策略配置会一并删除。';
  }

  @override
  String get portfolioRemovalTransferHint => '目标比例和资产归属会在同一事务中转移，不会改变会计账本。';

  @override
  String get portfolioRemovalTransferTargetLabel => '转移至';

  @override
  String get portfolioRemovalTransferAction => '转移并删除';

  @override
  String portfolioStrategyCountSummary(String strategy, int count) {
    return '$strategy · $count 个资金策略';
  }

  @override
  String portfolioLotsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个批次',
      one: '1 个批次',
    );
    return '$_temp0';
  }

  @override
  String get portfolioScopedReturnUnavailable => '记录组合归属历史后才能计算组合收益率。';

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
  String get portfolioHubConcentrationTitle => '集中度风险';

  @override
  String portfolioHubConcentrationSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 项超过你设定的阈值',
    );
    return '$_temp0';
  }

  @override
  String get portfolioHubConcentrationDimensionAsset => '单标的';

  @override
  String get portfolioHubConcentrationDimensionSector => '行业';

  @override
  String get portfolioHubConcentrationDimensionRegion => '地区';

  @override
  String get portfolioHubConcentrationDimensionCurrency => '币种';

  @override
  String get portfolioHubConcentrationSeverityWarning => '预警';

  @override
  String get portfolioHubConcentrationSeverityCritical => '严重';

  @override
  String portfolioHubConcentrationWeightLine(String weight, String threshold) {
    return '$weight% · 上限 $threshold%';
  }

  @override
  String get portfolioHubConcentrationRebalanceCta => '查看再平衡计划';

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
  String get dcaSimulatorSymbolHint => 'VOO 或 VOO:60, QQQ:40';

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
  String get dcaSimulatorDraftAction => '保存周期计划';

  @override
  String get dcaPlanSectionTitle => '周期定投计划';

  @override
  String get dcaPlanEmpty => '完成一次模拟后，可将结果保存为周期定投计划。';

  @override
  String get dcaPlanSaved => '周期定投计划已保存';

  @override
  String get dcaPlanActive => '进行中';

  @override
  String get dcaPlanPaused => '已暂停';

  @override
  String dcaPlanNextDue(String date, String amount, String currency) {
    return '下次 $date · $amount $currency';
  }

  @override
  String get dcaPlanExecuteNow => '记录本期定投';

  @override
  String get dcaPlanPause => '暂停';

  @override
  String get dcaPlanResume => '恢复';

  @override
  String get dcaPlanDeleteTitle => '删除周期计划？';

  @override
  String get dcaPlanDeleteBody => '将删除后续计划与提醒，已记录的交易会保留。';

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
  String get homeTodayBriefSubtitle => '今日财务概览';

  @override
  String get lifeBriefSubtitle => '集中查看今天值得关注的动态';

  @override
  String get lifeStageTitle => 'LifeOS';

  @override
  String get lifeHeroMetricAttention => '待处理';

  @override
  String get lifeHeroMetricSignals => '新动态';

  @override
  String get lifeHeroMetricClear => '今日状态';

  @override
  String get lifeHeroHeadlineCalm => '今天暂无待处理事项';

  @override
  String get lifeHeroHeadlineSignals => '今天有新的跨领域动态';

  @override
  String get lifeHeroHeadlineAttention => '有事项需要优先处理';

  @override
  String lifeHeroBody(int count) {
    return '汇总 $count 个功能领域的重要变化';
  }

  @override
  String lifeStickyAttention(int count) {
    return '$count 项待处理';
  }

  @override
  String lifeStickySignals(int count) {
    return '$count 条新动态';
  }

  @override
  String get lifeStickyCalm => '暂无待处理事项';

  @override
  String get lifeReviewTitle => '复盘';

  @override
  String get lifeReviewHeadline => '完成闭环';

  @override
  String get lifeReviewSubtitle => '集中回看决策、假设与后续行动。';

  @override
  String get lifeReviewPickerSubtitle => '选择本次要复盘的领域。';

  @override
  String get lifeTimelineTitle => '最新动态';

  @override
  String get lifeTimelinePriorityTitle => '优先处理';

  @override
  String get lifeTimelineEmptyTitle => '今天很安静';

  @override
  String get lifeTimelineEmpty => '你仍可以进入各功能领域查看详情。';

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
  String get lifeNavLabel => '总览';

  @override
  String lifeSignalFinanceDayTitle(String count) {
    return '今日收支 $count 笔';
  }

  @override
  String lifeSignalFinanceDaySubtitle(String expense, String income) {
    return '支出 $expense · 收入 $income';
  }

  @override
  String get lifeSignalFinanceBudgetStrainedTitle => '本月预算需要关注';

  @override
  String get lifeSignalFinanceBudgetOverTitle => '本月预算已超支';

  @override
  String lifeSignalFinanceBudgetSubtitle(String periodMonth) {
    return '$periodMonth 预算使用情况';
  }

  @override
  String get lifeSignalRecoveryTitle => '恢复状态需要关注';

  @override
  String get lifeSignalRecoverySubtitle => '恢复状态出现需要关注的变化';

  @override
  String lifeSignalExecBlockedTitle(String count) {
    return '$count 个受阻行动';
  }

  @override
  String get lifeSignalExecBlockedSubtitle => '部分行动尚未取得进展';

  @override
  String lifeSignalExecDueTitle(String count) {
    return '$count 个到期行动';
  }

  @override
  String get lifeSignalExecDueSubtitle => '这些行动计划今天完成';

  @override
  String lifeSignalKnowledgeTitle(String count) {
    return '收件箱 $count 条笔记';
  }

  @override
  String get lifeSignalKnowledgeSubtitle => '有笔记等待整理或复盘';

  @override
  String get lifeSignalAgentTitle => '有新的财务洞察';

  @override
  String get lifeSignalAgentSubtitle => '财务简报已生成最新分析';

  @override
  String get agentArtifactDetailTitle => '洞察详情';

  @override
  String get agentArtifactMissingTitle => '洞察暂不可用';

  @override
  String get agentArtifactMissingBody => '这条结果可能已过期、已被隐藏，或来自当前未启用的功能领域。';

  @override
  String get lifeSignalDetailTitle => '动态详情';

  @override
  String get lifeSignalEvidenceTitle => '判断依据';

  @override
  String lifeSignalRecoveryScoreEvidence(String score) {
    return '恢复分数：$score';
  }

  @override
  String get lifeSignalCreateAction => '创建行动';

  @override
  String lifeSignalCreateActionFor(String update) {
    return '为「$update」创建行动';
  }

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
  String get lifeSignalActionCreated => '行动已创建，并保留来源信息。';

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
  String get lifeSignalActionReviewFinance => '查看今日财务记录';

  @override
  String get lifeSignalActionReviewBudget => '查看本月预算';

  @override
  String get lifeSignalActionProtectRecovery => '今天优先保护恢复';

  @override
  String get lifeSignalActionReviewKnowledge => '整理知识收件箱';

  @override
  String get lifeSignalActionReviewAgent => '查看最新财务洞察';

  @override
  String lifeSignalActionNote(String source, String detail) {
    return '来自「$source」：$detail';
  }

  @override
  String get financeAgentResultsLoading => '正在加载财务洞察';

  @override
  String get financeAgentResultsLoadingBody => '正在加载近期财务复盘。';

  @override
  String get financeAgentResultsEmptyTitle => '暂无财务洞察';

  @override
  String get financeAgentResultsEmptyBody => '有新的计划复盘结果时，会显示在这里。';

  @override
  String get financeAgentResultsErrorTitle => '无法加载财务洞察';

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
  String get activityActionIncomeHint => '记一笔工资、股息或其它收入';

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
  String get wealthActionPanelAssetHint => '现金、存款、理财或实物资产';

  @override
  String get wealthActionPanelAssetSubtitle => '选择最符合这项资产的类型。';

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
  String get superFabIncome => '收入';

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
  String get homeQuickImport => '导入账单';

  @override
  String get financePrivacyHideAmountsTooltip => '隐藏金额';

  @override
  String get financePrivacyShowAmountsTooltip => '显示金额';

  @override
  String homeNetWorthSubtitle(String currency) {
    return '添加账户或导入数据后，将以 $currency 显示净资产';
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
  String get assetsAddCashTitle => '现金与多币种余额';

  @override
  String get assetsAddCashSubtitle => '登记银行活期或现金账户中的可用余额';

  @override
  String get assetsAddDepositTitle => '存款（定期或活期）';

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
  String get corpActionTypeStockDividend => '送股或红股';

  @override
  String get corpActionTypeSplit => '拆股或合股';

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
  String liabilityPaymentSheetTitle(int period) {
    return '记录第 $period 期还款';
  }

  @override
  String liabilityPaymentSheetAmount(String amount) {
    return '还款金额 · $amount';
  }

  @override
  String get liabilityPaymentSheetDate => '还款日期';

  @override
  String get liabilityPaymentSheetDateHint => '请选择资金从还款账户扣除的实际日期。';

  @override
  String get liabilityPaymentSheetSubmit => '记录还款';

  @override
  String get liabilityScheduleMarkPaidNoAccount => '标记还款前请先指定还款账户。';

  @override
  String liabilityScheduleUndoConfirmTitle(int period) {
    return '撤销第 $period 期还款？';
  }

  @override
  String get liabilityScheduleUndoConfirmBody => '这将移除关联的账本交易，并把该期恢复为待还状态。';

  @override
  String get liabilityNotFound => '未找到该负债';

  @override
  String get liabilityRevolvingNoSchedule => '信用卡和循环授信没有固定还款计划。';

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
  String get physicalAssetDeleteConfirmBody =>
      '估值历史将标记为已删除；此前已完成同步的设备仍可能保留可恢复的记录。';

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
  String get fxRatesSyncCompleted => '汇率已更新';

  @override
  String fxRatesSyncFailed(String error) {
    return '无法同步汇率：$error';
  }

  @override
  String fxRatesSyncPartial(int synced, int total, String error) {
    return '已更新 $synced/$total 个币对。$error';
  }

  @override
  String get fxRatesOverviewTitle => '币种行情';

  @override
  String get fxRatesOverviewSubtitle => '集中查看财富历史中正在使用的汇率。';

  @override
  String get fxRatesStatusSyncing => '同步中';

  @override
  String get fxRatesStatusFailed => '离线';

  @override
  String get fxRatesStatusReady => '已更新';

  @override
  String get fxRatesStatusLocal => '本地历史';

  @override
  String get fxRatesTrackedPairsLabel => '跟踪币对';

  @override
  String get fxRatesBaseCurrencyLabel => '基础货币';

  @override
  String get fxRatesLastUpdatedLabel => '最近更新';

  @override
  String get fxRatesLatestObservation => '最新观测';

  @override
  String get fxRatesHistoryTitle => '历史走势';

  @override
  String get fxRatesRange7D => '7天';

  @override
  String get fxRatesRange30D => '30天';

  @override
  String get fxRatesRange90D => '90天';

  @override
  String get fxRatesRangeAll => '全部';

  @override
  String get fxRatesHistoryEntries => '历史记录';

  @override
  String get fxRatesViewDetails => '查看明细';

  @override
  String get fxRatesNotEnoughHistory => '积累更多记录后即可看到趋势。';

  @override
  String get fxRatesRangeHint => '当前显示所选时间范围，切换“全部”可查看完整历史。';

  @override
  String fxRatesAsOfValue(String date) {
    return '截至 $date';
  }

  @override
  String fxRatesPairsTracked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已跟踪 $count 个币对',
      one: '已跟踪 1 个币对',
      zero: '暂无币对',
    );
    return '$_temp0';
  }

  @override
  String fxRatesEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条记录',
      one: '1 条记录',
    );
    return '$_temp0';
  }

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
  String dashboardValuationTrustMissingFx(int count, String currency) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 项资产因缺少到 $currency 的汇率而未计入',
    );
    return '$_temp0';
  }

  @override
  String dashboardValuationTrustWarning(
    int staleCount,
    String quality,
    String asOf,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      staleCount,
      locale: localeName,
      other: '有 $staleCount 项价格陈旧 · $quality · 截至 $asOf',
      zero: '$quality估值 · 截至 $asOf',
    );
    return '$_temp0';
  }

  @override
  String dashboardValuationTrustReady(String quality, String asOf) {
    return '$quality估值 · 截至 $asOf';
  }

  @override
  String get dashboardValuationTrustAction => '详情';

  @override
  String get dashboardValuationTrustSheetTitle => '估值可信度';

  @override
  String dashboardValuationTrustQuality(String quality) {
    return '质量：$quality';
  }

  @override
  String dashboardValuationTrustAsOf(String asOf) {
    return '截至 $asOf';
  }

  @override
  String dashboardValuationTrustStale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 项资产价格已陈旧',
    );
    return '$_temp0';
  }

  @override
  String get dashboardValuationQualityRealTime => '实时';

  @override
  String get dashboardValuationQualityDelayed => '延迟';

  @override
  String get dashboardValuationQualityDailyClose => '日收盘';

  @override
  String get dashboardValuationQualityManual => '手工';

  @override
  String get dashboardValuationQualityEstimated => '估算';

  @override
  String get dashboardValuationQualityStale => '陈旧';

  @override
  String get settingsAboutTitle => '关于 NaviWealth';

  @override
  String settingsAboutSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsAccentSeedTitle => '强调色';

  @override
  String get accentSeedCyan => '青蓝';

  @override
  String get accentSeedViolet => '紫罗兰';

  @override
  String get accentSeedIndigo => '靛蓝';

  @override
  String get settingsSurfaceStyleTitle => '界面风格';

  @override
  String get surfaceStyleStandard => '标准';

  @override
  String get surfaceStyleOled => 'OLED 纯黑';

  @override
  String get surfaceStyleHighContrast => '高对比';

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
  String get commonRequiredField => '请输入内容。';

  @override
  String get commonInvalidNumber => '请输入有效数字。';

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
  String get shortcutToggleSidebar => '收起或展开侧边栏';

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
  String get askAiResultNoLocalMatch => '命令栏暂时无法回答这个问题。你可以在 AI 助手中继续询问。';

  @override
  String get askAiResultContinueInChat => '在 AI 助手中继续';

  @override
  String get askAiResultIrreversibleBlocked => '命令栏不执行转账、下单或删除账户等操作。请前往对应页面完成。';

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
  String get commandPaletteToggleTheme => '切换主题（亮色或暗色）';

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
  String get nativeUpdateCheck => '检查更新';

  @override
  String get nativeUpdateChecking => '检查中…';

  @override
  String get nativeUpdateUpToDate => '当前已是最新版本。';

  @override
  String get nativeUpdateCheckFailed => '检查更新失败，请稍后重试。';

  @override
  String get nativeUpdateUnavailable => '当前版本不支持更新检查。';

  @override
  String get nativeUpdateNotificationTitle => 'NaviWealth 有新版本';

  @override
  String nativeUpdateNotificationBody(String version) {
    return '版本 $version 可以更新。';
  }

  @override
  String get nativeUpdateApply => '更新';

  @override
  String get nativeUpdateDismiss => '稍后';

  @override
  String nativeUpdateDownloading(int percent) {
    return '正在下载更新（$percent%）';
  }

  @override
  String get nativeUpdateInstallPermission =>
      '请在 Android 设置中允许 NaviWealth 安装更新，然后再次点击更新。';

  @override
  String get nativeUpdateVerificationFailed => '下载的更新完整性校验失败。';

  @override
  String get nativeUpdatePackageMismatch => '下载的文件不是有效的 NaviWealth 安装包。';

  @override
  String get nativeUpdateInstallFailed => 'Android 无法启动更新安装器。';

  @override
  String get nativeUpdateDownloadFailed => '更新下载失败，请稍后重试。';

  @override
  String get nativeUpdateInstallStarted => '更新已下载，请在 Android 中确认安装。';

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
  String get settingsSwitchToLocalTitle => '切换到本地模式';

  @override
  String get settingsSwitchToLocalSubtitle => '关闭云同步，但保留本机数据';

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
  String get analyticsEquitySubtitle => '按行业、地区或市值查看股票和 ETF 持仓。';

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
  String get fireDepthTitle => '财务韧性检查';

  @override
  String get fireDepthSubtitle => '自动检查真正影响目标的风险';

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
    return '$rate% · 安全提取率 $swr%';
  }

  @override
  String get fireOsHeroWithdrawalRateInfinite => '有支出但缺可投资资产';

  @override
  String get fireOsHeroCashBucketLabel => '现金桶';

  @override
  String fireOsHeroCashBucketValue(String months, int target) {
    return '$months 个月 · 目标 $target 个月';
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
  String get fireOsActionConfigurePlanDetail => '填写目标净值、月度支出与结余后，系统才能判断安全程度。';

  @override
  String get fireOsActionHoldSteadyTitle => '状态健康——继续保持';

  @override
  String get fireOsActionHoldSteadyDetail => '当前提取率低于安全提取率，现金储备充足。';

  @override
  String get fireOsActionTopUpCashBucketTitle => '补足现金桶';

  @override
  String fireOsActionTopUpCashBucketDetail(String amount, int months) {
    return '还需增加 $amount，才能覆盖 $months 个月的支出。';
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
  String get fireOsActionDelayDiscretionaryDetail => '暂缓旅行、升级或大额采购，待提取率回落后再恢复。';

  @override
  String get fireOsActionRebalanceTitle => '再平衡至目标权重';

  @override
  String get fireOsActionRebalanceDetail => '配置已偏离目标——调整各桶比例。';

  @override
  String get fireOsActionBuildRiskReserveTitle => '建立风险储备';

  @override
  String get fireOsActionBuildRiskReserveDetail => '净资产为负或安全垫较薄，请先准备应急和医疗资金。';

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
  String get fireOsBucketsSubtitle => '将资产归入现金、防御、增长、风险储备或梦想目标。';

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
  String get fireOsUnmappedSubtitle => '这些资产尚未归入任何类别。如需纳入计划，请配置分类规则。';

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
  String get fireOsReviewSubtitle => '按月、季度和年度生成复盘快照。指标由规则计算，AI 仅用于解读结果。';

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
  String get fireOsReviewDiffWrUnavailable => '提取率包含无穷值，无法计算差值';

  @override
  String fireOsReviewDiffNetWorth(String sign, String amount) {
    return '净资产 $sign$amount';
  }

  @override
  String get fireOsReviewDiffNetWorthCurrencyChanged => '净资产币种已更改，无法比较差值。';

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
  String get targetAllocationEditorAddCategory => '添加资产类别';

  @override
  String get targetAllocationEditorNoCategoriesAvailable => '所有资产类别均已添加';

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
  String get settingsRiskRegionSubtitle => '单一市场或地区的占比超过此值时发出提醒。';

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
  String get settingsStressTestLumpSumSubtitle => '医疗、家庭支援等突发开销（基础币种）';

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
  String get expenseFormDeleteDialogBody => '确认删除此支出？删除后可在提示中撤销，该操作也会同步给其他设备。';

  @override
  String get expenseFormNoAccountsTitle => '先创建一个账户';

  @override
  String get expenseFormNoAccountsBody => '支出需要选择资金账户。前往「账户」新建后再来录入。';

  @override
  String get expenseFormNoAccountsCta => '去创建';

  @override
  String get incomeFormCreateTitle => '记录收入';

  @override
  String get incomeFormAmountLabel => '金额';

  @override
  String get incomeFormAmountInvalid => '金额必须大于 0';

  @override
  String get incomeFormKindLabel => '收入类型';

  @override
  String get incomeFormAccountLabel => '入账账户';

  @override
  String get incomeFormAccountRequired => '请选择入账账户和币种';

  @override
  String get incomeFormAdvancedTitle => '日期与备注';

  @override
  String get incomeFormDateLabel => '日期时间';

  @override
  String get incomeFormDefaultNarration => '收入';

  @override
  String get incomeFormNoAccountsTitle => '先创建一个账户';

  @override
  String get incomeFormNoAccountsBody => '收入需要选择入账账户。前往「账户」新建后再来录入。';

  @override
  String get incomeFormNoAccountsCta => '去创建';

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
  String get aiChatEmptyTitle => '你的 LifeOS 助手';

  @override
  String get aiChatEmptyBody =>
      '你可以一起询问财务、知识、健康和计划。回答会优先参考本机数据和已启用的功能；信息不足时，助手会先向你确认。';

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
  String get speechInputContinuousStartTooltip => '开启连续对话';

  @override
  String get speechInputContinuousStopTooltip => '结束连续对话';

  @override
  String get speechInputStartingTooltip => '正在准备端侧语音识别…';

  @override
  String get speechInputPreparingStatus => '正在准备麦克风…';

  @override
  String get speechInputPermissionStatus => '正在等待麦克风权限…';

  @override
  String get speechInputReadyStatus => '识别已就绪，正在开启麦克风…';

  @override
  String get speechInputListeningStatus => '正在聆听…';

  @override
  String get speechInputContinuousStatus => '连续聆听中…';

  @override
  String get speechInputEndpointingStatus => '正在收尾识别…';

  @override
  String get speechInputThinkingStatus => '正在思考…';

  @override
  String get speechInputSpeakingStatus => '正在播报 · 点击麦克风可打断';

  @override
  String get speechInputDuplexSpeakingStatus => '正在播报 · 直接说话即可打断';

  @override
  String get speechInputDuplexPausedStatus => '播报已暂停 · 继续说话即可打断';

  @override
  String get speechInputSwitchToTextTooltip => '切换为文字输入';

  @override
  String get speechInputCancelTooltip => '取消语音输入';

  @override
  String get speechOutputStopTooltip => '停止朗读';

  @override
  String get speechInputModelMissing => '请先下载中文实时语音模型';

  @override
  String get speechInputUnsupported => '当前平台暂不支持端侧语音输入';

  @override
  String get speechInputPermissionDenied => '需要麦克风权限才能使用语音输入';

  @override
  String get speechInputRecorderUnavailable => '麦克风或录音设备不可用';

  @override
  String get speechInputRuntimeUnavailable => '端侧语音识别服务不可用';

  @override
  String get speechInputSessionBusy => '上一语音会话仍在关闭，请稍后重试';

  @override
  String get speechInputFailed => '语音识别启动失败，请稍后重试';

  @override
  String get speechInputRetry => '重试';

  @override
  String get speechOutputEngineUnavailable => '当前设备无法使用文字转语音';

  @override
  String get speechOutputSynthesisFailed => '这段回答暂时无法朗读';

  @override
  String get speechOutputSessionBusy => '已有另一段回答正在朗读';

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
  String get aiChatProposalKindTransfer => '转账';

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
  String get aiChatFieldDestinationAmount => '到账金额';

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
  String get aiChatRowFromAccount => '转出账户';

  @override
  String get aiChatRowToAccount => '转入账户';

  @override
  String get aiChatRowDestinationAmount => '到账金额';

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
  String get aiChatToolShowRawJson => '查看原始数据';

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
  String get accountDetailAddBalanceAction => '录入余额';

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
  String get accountCategoryLiabilityHint => '信用卡和贷款以外的其他负债';

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
  String get accountFormInstitutionHelper => '银行、券商或平台名称（可选）';

  @override
  String get accountFormAccountNumberLabel => '账号或末位号（可选）';

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
  String get cashFormNeedAccountHint => '请先创建一个银行或现金账户。';

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
  String get activitySelectEntry => '选择一条流水，在不离开时间线的情况下查看详情';

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
  String get activityFeedSummaryNet => '净收支';

  @override
  String activityFeedSummaryShown(int count) {
    return '已显示 $count 笔';
  }

  @override
  String activityFeedSummaryCountValue(int count) {
    return '共 $count 笔';
  }

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
  String get activityFeedSearchHint => '搜索商户、备注或账户';

  @override
  String activityFeedSearchTag(String query) {
    return '“$query”';
  }

  @override
  String get activityEntryDeleteTitle => '删除这笔流水？';

  @override
  String get activityEntryDeleteBody => '将从账本中移除该日记账分录及其明细，删除后可在提示中撤销。';

  @override
  String get activityEntryDeleted => '已删除流水';

  @override
  String get activityEntryDeleteFailed => '删除流水失败，请重试。';

  @override
  String get accountsTransferAction => '转账';

  @override
  String get accountsJournalAction => '日记账';

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
  String get settingsAiSection => 'AI';

  @override
  String get settingsAiHubTitle => 'AI 与设备智能';

  @override
  String get settingsAiHubSubtitle => '服务、设备模型、智能体、隐私与活动记录';

  @override
  String get settingsAiHubRuntimeSection => '运行环境';

  @override
  String get settingsAiHubTrustSection => '隐私与透明度';

  @override
  String get settingsAiHistoryTitle => 'AI 历史会话';

  @override
  String get settingsAiHistorySubtitle => '查看已保存的 AI 对话';

  @override
  String get personalMemoryTitle => '个人记忆';

  @override
  String get personalMemorySubtitle => '管理 AI 使用的目标、偏好、约束与规则';

  @override
  String get personalMemorySection => '已确认个人资料';

  @override
  String get personalMemoryEmpty => '暂无已确认的个人资料事实。';

  @override
  String get personalMemoryAdd => '添加个人资料事实';

  @override
  String get personalMemoryCreateTitle => '添加个人资料事实';

  @override
  String get personalMemoryEditTitle => '编辑个人资料事实';

  @override
  String get personalMemoryKind => '类型';

  @override
  String get personalMemoryKindGoal => '目标';

  @override
  String get personalMemoryKindPreference => '偏好';

  @override
  String get personalMemoryKindConstraint => '约束';

  @override
  String get personalMemoryKindRule => '规则';

  @override
  String get personalMemoryKey => '键';

  @override
  String get personalMemoryKeyHint => '例如：cash_buffer_months';

  @override
  String get personalMemoryValue => '值';

  @override
  String get personalMemoryValueHint => '文本或 JSON 值';

  @override
  String get personalMemorySummary => '摘要';

  @override
  String get personalMemorySummaryHint => '一条可供 Agent 作为证据使用的清晰事实';

  @override
  String get personalMemoryDomain => '领域（可选）';

  @override
  String get personalMemoryDomainHint => 'finance、health、knowledge 或 execution';

  @override
  String get personalMemoryRequired => '键和摘要为必填项';

  @override
  String get personalMemoryDeleteTitle => '忘记这条个人资料事实？';

  @override
  String get personalMemoryDeleteBody => '它将不再进入后续 AI 上下文。此页面无法撤销该操作。';

  @override
  String get personalMemoryInactiveDomain => '已保留在本地；该领域关闭时不会进入 AI 上下文';

  @override
  String personalMemoryLoadFailed(String error) {
    return '无法加载个人记忆：$error';
  }

  @override
  String get settingsAdvancedHubTitle => '高级诊断';

  @override
  String get settingsAdvancedHubSubtitle => '日志与性能工具';

  @override
  String get settingsAboutDiagnosticsSection => '关于与诊断';

  @override
  String get settingsDataSection => '数据与同步';

  @override
  String get settingsNotificationsPrivacySection => '通知与隐私';

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
      '将删除本机上该领域的数据和历史记录。若已开启云同步，云端数据可能在下次同步时重新下载。';

  @override
  String dataManagementResetEverywhereConfirmTitle(String domain) {
    return '永久删除 $domain？';
  }

  @override
  String get dataManagementResetEverywhereConfirmBody =>
      '将从云端和所有已连接设备永久删除该领域的数据。离线设备重新联网后也无法恢复。此操作不可撤销。';

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
  String get settingsDomainsSection => '功能领域';

  @override
  String get settingsDomainsDeepLinkBlockedNotice => '该链接属于尚未开通的领域,在下方开通后即可访问。';

  @override
  String get settingsDomainsTitle => '功能领域';

  @override
  String get settingsDomainsSubtitle =>
      '管理 FinanceOS、HealthOS、KnowledgeOS 和 ExecutionOS';

  @override
  String get settingsDomainsFinanceSubtitle =>
      '始终启用的财务功能：货币、汇率、风险偏好、资产配置和 FIRE 规划';

  @override
  String get settingsDomainsFinanceAlwaysOnBadge => '常开';

  @override
  String settingsDomainsDisabledToast(String domain) {
    return '$domain 已关闭。你可以随时在这里重新启用。';
  }

  @override
  String settingsDomainsEnableSuccessTitle(String domain) {
    return '$domain 已就绪';
  }

  @override
  String settingsDomainsEnableSuccessBody(String domain) {
    return '立即打开 $domain 并创建第一个有用对象，也可以稍后再开始。';
  }

  @override
  String get settingsDomainsOpenNow => '立即打开';

  @override
  String get settingsDomainsOpenLater => '稍后';

  @override
  String settingsDomainsDisableConfirmTitle(String domain) {
    return '关闭 $domain？';
  }

  @override
  String settingsDomainsDisableConfirmBody(String domain) {
    return '$domain 数据仍会保留在本机和同步端，但导航、工具、后台 Agent 和通知会暂停，重新启用后即可恢复。';
  }

  @override
  String get settingsDomainsDisableConfirmAction => '关闭';

  @override
  String settingsDomainsConfigure(String domain) {
    return '配置 $domain';
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
  String agentSettingsNextRunAt(String date) {
    return '下次 $date';
  }

  @override
  String get agentSettingsNextRunOnOpen => '下次打开 App 时检查';

  @override
  String get agentSettingsExecutionTitle => '运行方式';

  @override
  String get agentSettingsExecutionForeground => '打开或回到 App 前台时检查并补跑';

  @override
  String get agentSettingsRunNowHint => '只运行一次，不会改变自动计划';

  @override
  String agentSettingsAroundTime(String time) {
    return '约 $time';
  }

  @override
  String agentSettingsEveryHours(int hours) {
    return '每 $hours 小时';
  }

  @override
  String agentSettingsEveryMinutes(int minutes) {
    return '每 $minutes 分钟';
  }

  @override
  String agentSettingsEveryHoursMinutes(int hours, int minutes) {
    return '每 $hours 小时 $minutes 分钟';
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
  String get settingsAdvancedSection => '诊断工具';

  @override
  String get settingsAiModelsTitle => 'AI 模型';

  @override
  String get settingsAiModelsSubtitle => '下载与管理本地 AI 和语音模型';

  @override
  String get aiLlmRuntimeCheckTitle => 'AI 服务检查';

  @override
  String get aiLlmRuntimeCheckReady => '使用当前模型配置发送一条测试请求，检查 AI 服务是否可用。';

  @override
  String get aiLlmRuntimeCheckNoProfile => '请先保存并启用一个模型服务商配置，再检查 AI 服务。';

  @override
  String get aiLlmRuntimeCheckAction => '开始检查';

  @override
  String get aiLlmRuntimeCheckRunning => '检查中…';

  @override
  String get aiLlmRuntimeCheckPrompt => '请用一句简短的话确认 NaviWealth 可以访问当前 AI 服务。';

  @override
  String aiLlmRuntimeCheckSucceeded(String status) {
    return 'AI 服务检查完成：$status';
  }

  @override
  String aiLlmRuntimeCheckFailed(String error) {
    return 'AI 服务检查失败：$error';
  }

  @override
  String aiLlmRuntimeCheckStatus(String status) {
    return '本机检查：$status';
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
    return '$summary\n\n确认后，将使用与 AI 助手相同的方式保存这项更改。';
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
  String get settingsAiPrivacySubtitle => '控制发送给模型服务商的数据范围';

  @override
  String get aiPrivacyTitle => 'AI 隐私';

  @override
  String get aiPrivacyIntro => '选择使用云端模型时可以发送多少数据。你可以随时更改。';

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
  String get aiPrivacyMaskAccountsLabel => '隐藏账户和机构名称';

  @override
  String get aiPrivacyMaskAccountsDescription => '发送前，将银行、券商等机构名称替换为匿名标识。';

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
  String get settingsLogsCopyAction => '复制全部日志';

  @override
  String get settingsLogsShareAction => '分享全部日志';

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
  String get settingsPerfCopyEvidence => '复制性能证据';

  @override
  String get settingsPerfEvidenceCopied => '已复制性能证据';

  @override
  String get settingsDomainsHealthEnabledSubtitle => 'AI 工具和本地记忆索引已启用';

  @override
  String get settingsDomainsHealthDisabledSubtitle => '启用 AI 工具和本地记忆索引';

  @override
  String get settingsDomainsHealthTodaySubtitle => '查看今日恢复、指标与健康趋势';

  @override
  String get settingsDomainsKnowledgeEnabledSubtitle =>
      '收件箱、资料库、复盘、AI 工具和本地记忆索引已启用';

  @override
  String get settingsDomainsKnowledgeDisabledSubtitle => '个人决策与认知演化记忆库';

  @override
  String get settingsDomainsKnowledgeInboxSubtitle => '捕获笔记、写决策、查看资料库与复盘';

  @override
  String get settingsDomainsKnowledgeLibrarySubtitle => '浏览决策、假设、例行事项、概念和笔记';

  @override
  String get settingsDomainsKnowledgeReviewSubtitle => '复盘到期决策、过期假设和到期例行事项';

  @override
  String get settingsDomainsKnowledgeMemoryTitle => 'KnowledgeOS 本地记忆';

  @override
  String get settingsDomainsKnowledgeMemorySubtitle => '管理用于召回、查重与语义搜索的本地模型';

  @override
  String get settingsDomainsHealthPermissionDenied => '权限被拒绝，请前往系统健康设置后重试';

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
    return '上次同步：新增或更新 $upserted 项 · 无变化 $unchanged 项 · 共拉取 $total 项';
  }

  @override
  String get settingsDomainsHealthSyncTitle => '同步健康数据';

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
  String get settingsAiModelsOrtMissing => '缺少 ONNX Runtime 动态库';

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
  String get settingsAiModelsSpeechEngineTitle => '语音识别引擎';

  @override
  String get settingsAiModelsSpeechEngineSubtitle =>
      '系统端侧识别是安全默认值；Zipformer 全程本地运行，需要先下载语音模型。';

  @override
  String get settingsAiModelsSpeechEngineLocalOnlySubtitle =>
      '当前平台使用本地 Zipformer 识别，需要先下载语音模型。';

  @override
  String get settingsAiModelsSpeechEngineSystem => '系统端侧识别';

  @override
  String get settingsAiModelsSpeechEngineZipformer => '本地 Zipformer';

  @override
  String get settingsAiModelsSpeechEngineZipformerMissing =>
      '使用本地识别前，请先下载下方 Zipformer 模型。';

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
  String get settingsAiModelsActiveRuntimeNative => '本机运行';

  @override
  String get settingsAiModelsActiveRuntimeStub => '模拟运行';

  @override
  String get settingsAiModelsActiveRuntimeUnknown => '不可用';

  @override
  String get settingsAiModelsFingerprintLabel => '模型指纹';

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
    return '$count 条后台整理建议，应用前由你确认。';
  }

  @override
  String get knowledgeAiSuggestionsEmpty => '当前没有待处理的整理建议。';

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
  String get knowledgeAiSuggestionViewAction => '查看';

  @override
  String get knowledgeAiSuggestionDismissedToast => '已忽略建议。';

  @override
  String get knowledgeAiSuggestionFeedbackLabel => '这条建议有帮助吗？';

  @override
  String get knowledgeAiSuggestionFeedbackGood => '有帮助';

  @override
  String get knowledgeAiSuggestionFeedbackBad => '没帮助';

  @override
  String get knowledgeAiSuggestionFeedbackToast => '反馈已保存。';

  @override
  String get knowledgeAiSuggestionMoreActions => '更多操作';

  @override
  String knowledgeAiSuggestionClassificationSummary(String kind) {
    return '建议整理为$kind';
  }

  @override
  String knowledgeAiSuggestionTagsSummary(String tags) {
    return '建议添加标签：$tags';
  }

  @override
  String knowledgeAiSuggestionDecisionLinksSummary(int count) {
    return '建议关联 $count 条相关决策';
  }

  @override
  String get knowledgeAiSuggestionFieldTags => '标签';

  @override
  String get knowledgeAiSuggestionFieldDecisions => '相关决策';

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
  String get knowledgeAgentContradictionTitle => '检测到 Decision 冲突';

  @override
  String get knowledgeAgentContradictionNone => '过去 90 天未检测到冲突。';

  @override
  String knowledgeAgentContradictionInvalidatedAssumption(Object assumptionId) {
    return '该决策仍引用假设 $assumptionId，但这项假设已被证伪或停用。';
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
  String get knowledgeMarkdownBold => '加粗';

  @override
  String get knowledgeMarkdownLink => '链接';

  @override
  String get knowledgeMarkdownBulletedList => '项目列表';

  @override
  String get knowledgeMarkdownQuote => '引用';

  @override
  String get knowledgeMarkdownInlineCode => '行内代码';

  @override
  String knowledgeMarkdownTableLabel(int rows, int columns) {
    return '表格，共 $rows 行、$columns 列';
  }

  @override
  String knowledgeMarkdownImageLabel(String description) {
    return '图片：$description';
  }

  @override
  String get knowledgeDecisionNotFound => 'Decision 不存在或已删除';

  @override
  String get knowledgeDecisionDetailTitle => '决策详情';

  @override
  String get knowledgeDecisionActionPrompt => '将这个决策转化为一个具体的下一步。';

  @override
  String get knowledgeActionLinked => '已关联一个后续行动。';

  @override
  String get knowledgeActionCreate => '创建行动';

  @override
  String get knowledgeActionOpen => '打开行动';

  @override
  String get knowledgeActionCreated => '已创建后续行动';

  @override
  String get knowledgeActionUnavailable => '启用 ExecutionOS 后可创建后续行动。';

  @override
  String knowledgeActionFailed(String error) {
    return '无法创建行动：$error';
  }

  @override
  String get knowledgeNoteActionPrompt => '将这条笔记转化为一个具体后续行动。';

  @override
  String knowledgeNoteActionDraftTitle(String note) {
    return '跟进：$note';
  }

  @override
  String get knowledgeExperimentActionPrompt => '将这个实验转化为一个具体下一步。';

  @override
  String knowledgeExperimentActionDraftTitle(String experiment) {
    return '推进实验：$experiment';
  }

  @override
  String knowledgeDecisionActionDraftTitle(String decision) {
    return '跟进：$decision';
  }

  @override
  String knowledgeDecisionActionDraftNote(String choice) {
    return '决策选择：$choice';
  }

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
  String get knowledgeSourceOpenConfirmTitle => '打开来源链接？';

  @override
  String get knowledgeSourceOpenConfirmBody =>
      '即将离开 NaviWealth 打开外部来源，请确认目标地址。';

  @override
  String get knowledgeSourceOpenAction => '打开';

  @override
  String get knowledgeSourceOpenFailed => '无法打开来源链接。';

  @override
  String get knowledgeSourceCopyAction => '复制来源链接';

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
  String knowledgeLibraryDeleteImpactBody(
    Object attachmentCount,
    Object referenceCount,
    Object relationCount,
    Object title,
  ) {
    return '“$title”关联了 $relationCount 条关系、$referenceCount 处内联引用和 $attachmentCount 个附件。关系会解除，引用对象与附件文件会保留；删除后可撤销。';
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
  String get spendingTitle => '支出分析';

  @override
  String get expenseReportRangeThisMonth => '本月';

  @override
  String get expenseReportRangeThisMonthCompact => '本月';

  @override
  String get expenseReportRangeLast3Months => '近 3 月';

  @override
  String get expenseReportRange3mCompact => '3月';

  @override
  String get expenseReportRangeLast6Months => '近 6 月';

  @override
  String get expenseReportRange6mCompact => '6月';

  @override
  String get expenseReportRangeLast12Months => '近 12 月';

  @override
  String get expenseReportRange12mCompact => '12月';

  @override
  String get expenseReportRangeCustom => '自定义';

  @override
  String get expenseReportRangeCustomCompact => '自定';

  @override
  String get expenseReportTotalExpenses => '总支出';

  @override
  String get expenseReportDailyAverage => '日均';

  @override
  String get expenseReportEntryCount => '记账数';

  @override
  String get expenseReportCategoryCount => '类目数';

  @override
  String expenseReportSkippedFx(int count) {
    return '$count 笔支出因汇率缺失未计入合计。';
  }

  @override
  String expenseReportBaseCurrency(String currency, int days) {
    return '基础货币 $currency · 共 $days 个自然日';
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
  String get wealthProductNoAccountHint => '请先创建银行或券商账户。';

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
      '数据保存在本机。点击“从网络导入”，可选择使用 Yahoo 或 CoinGecko 的数据补全字段。';

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
  String get activityFeedFilterApply => '应用筛选';

  @override
  String get activityFeedFilterAllDates => '全部日期';

  @override
  String get activityFeedFilterAllKinds => '全部类型';

  @override
  String activityFeedFilterKindCount(int count) {
    return '$count 种类型';
  }

  @override
  String activityFeedFilterAccountCount(int count) {
    return '$count 个账户';
  }

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
  String get ingestCopyDiagnostics => '复制隐私安全的导入诊断';

  @override
  String get ingestDiagnosticsCopied => '导入诊断已复制';

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
  String ingestSummaryTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已记录 $count 笔',
    );
    return '$_temp0';
  }

  @override
  String ingestSummaryFailures(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 笔待复核',
    );
    return '$_temp0';
  }

  @override
  String get ingestSummaryBody => '条目已进入活动流,余额已同步更新。';

  @override
  String get ingestSummaryViewActivity => '查看活动';

  @override
  String get agentResultsLoadingTitle => '助手正在整理';

  @override
  String get agentResultsLoadingBody => '正在获取最新的 Agent 结果…';

  @override
  String get agentResultsErrorTitle => 'Agent 结果暂不可用';

  @override
  String get agentResultsEmptyTitle => '还没有 Agent 结果';

  @override
  String get agentResultsEmptyBody => '运行一次 Agent,获取该领域的最新解读。';

  @override
  String get agentResultsGenerateAction => '生成';

  @override
  String get knowledgeStatusActive => '生效中';

  @override
  String get knowledgeStatusPaused => '已暂停';

  @override
  String get knowledgeStatusRetired => '已退役';

  @override
  String get knowledgeStatusWeakened => '已削弱';

  @override
  String get knowledgeStatusFalsified => '已证伪';

  @override
  String get knowledgeStatusPlanned => '已计划';

  @override
  String get knowledgeStatusRunning => '进行中';

  @override
  String get knowledgeStatusDone => '已完成';

  @override
  String get knowledgeStatusAbandoned => '已放弃';

  @override
  String get knowledgeStatusArchived => '已归档';

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
      '粘贴支付宝、微信或银行 CSV 账单文本\n例如：2026-05-10,星巴克,-38.00,CNY';

  @override
  String get ingestPasteRequired => '请先粘贴账单文本再解析。';

  @override
  String get ingestEmptyPasteCta => '粘贴';

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
  String get ingestEditDraft => '修正字段';

  @override
  String get ingestEditDescription => '描述';

  @override
  String get ingestEditAmount => '金额';

  @override
  String get ingestEditCurrency => '币种';

  @override
  String get ingestEditDate => '交易日期';

  @override
  String get ingestEditCategory => '分类提示（选填）';

  @override
  String get ingestEditInvalid => '请填写描述、正数金额和币种。';

  @override
  String get ingestEditConflict => '编辑期间该草稿已发生变化，请检查最新内容后重试。';

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
      '可定期导入支付宝、微信或银行的 CSV 和文本账单。\n系统会先标记重叠账期中的重复记录，再由你确认入账。';

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
  String get settingsAiLlmTitle => 'AI 服务 · 自带 API Key';

  @override
  String get settingsAiLlmSubtitle => '管理多个模型服务商，并切换本机直连配置';

  @override
  String get aiLlmMissingApiKey => '请先填入 API Key';

  @override
  String get aiLlmSaved => '已保存到设备安全存储';

  @override
  String get aiLlmSwitched => '已切换';

  @override
  String get aiLlmRemoved => '已从设备移除';

  @override
  String get aiLlmDeleteTitle => '删除模型服务商？';

  @override
  String aiLlmDeleteBody(String name) {
    return '这会从此设备移除 $name 及其已保存的 API Key。';
  }

  @override
  String get aiLlmEmpty => '尚未配置模型服务商。添加 API Key 后，即可由本机直接连接并使用 AI 服务。';

  @override
  String get aiLlmAddProvider => '添加模型服务商';

  @override
  String get aiLlmEditProvider => '编辑模型服务商';

  @override
  String get aiLlmActiveTag => '使用中';

  @override
  String get aiLlmTapToSwitch => '点按切换';

  @override
  String get aiLlmNameLabel => '名称（可选）';

  @override
  String get aiLlmNameHint => '例如 Anthropic 官方或公司网关';

  @override
  String get aiLlmProviderLabel => '提供商';

  @override
  String get aiLlmStoredKeyHint => '已配置 · 留空则保持不变';

  @override
  String get aiLlmBaseUrlLabel => '自定义服务地址（Base URL，可选）';

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
      '使用你自己的 LLM API Key，由本机直接连接模型服务商。你可以保存多个服务商配置并随时切换。API Key 仅保存在本设备的安全存储中，不会上传、同步或备份。费用和调用限制由你的模型服务商账户承担。';

  @override
  String get aiLlmUnsupportedTitle => '当前平台不支持 AI 服务直连';

  @override
  String get aiLlmUnsupportedBody =>
      '自带 API Key 的 AI 服务可在 iOS、Android、macOS、Windows 和 Linux 上使用，并需要系统级安全存储。Web 端暂不支持。';

  @override
  String aiLlmStatusActive(String name) {
    return '使用中：$name · 本机直连运行';
  }

  @override
  String get aiLlmStatusSavedNoActive => '已保存模型服务商，但尚未选择使用项';

  @override
  String get aiLlmStatusReadFailed => '读取安全存储失败';

  @override
  String get aiLlmStatusNotConfigured => '未配置 · 当前无可用 AI 服务';

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
  String get watchlistSelectItem => '选择标的，查看行情与提醒规则';

  @override
  String get watchlistAccountsEntrySubtitle => '跟踪标的并设置本地价格告警';

  @override
  String get watchlistAddAction => '添加标的';

  @override
  String watchlistRowActionsTitle(String symbol) {
    return '$symbol 操作';
  }

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
  String get incomePlannerTitle => '期权工作台';

  @override
  String get incomePlannerAccountsEntrySubtitle => '扫描卖出看跌和备兑看涨的现金流机会';

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
      '卖出现金担保看跌期权和备兑看涨期权均可能造成损失。若被行权，现金担保看跌期权可能要求你按行权价买入 100 股；备兑看涨期权会限制行权价以上的潜在收益。期权收入规划仅筛选符合你风险偏好的机会，不预测价格，也不会代你下单。请在使用前阅读 OCC《标准化期权的特征与风险》。';

  @override
  String get incomePlannerOccAccept => '我已了解风险，继续';

  @override
  String get incomePlannerOccCancel => '暂不';

  @override
  String get incomePlannerOccLearnMore => '打开 OCC ODD';

  @override
  String get incomePlannerStartTitle => '设置你的策略偏好';

  @override
  String get incomePlannerStartBody => '设置你愿意采用的策略和风险水平，然后选择可持有或卖出的标的。';

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
  String get incomePlannerProfilePercentHelper => '输入百分数，例如输入 12 表示 12%。';

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
      '没有可扫描的标的。请至少添加一个允许卖出看跌或看涨期权的标的，或确认备兑看涨标的的持仓不少于 100 股。';

  @override
  String get incomePlannerLastScanLabel => '上次扫描';

  @override
  String get incomePlannerLastScanStale => '缓存数据已超过 24 小时 —— 刷新以获取最新数据。';

  @override
  String get incomePlannerOpportunitiesAllRejected =>
      '本次没有候选通过你的风险边界。请先查看下方原因；保持当前限制并稍后再看也是合理结果。';

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
  String get incomePlannerChipLeaps => 'LEAPS 看涨';

  @override
  String get incomePlannerLaneSellSection => '卖方收入（Put / Call）';

  @override
  String get incomePlannerLaneLeapsSection => 'LEAPS 看涨';

  @override
  String get incomePlannerAdjustLeapsBudget => '调整 LEAPS 预算';

  @override
  String get incomePlannerScanLeapsCta => '扫描机会';

  @override
  String get incomePlannerMetricLeapsCost => '成本（最大亏损）';

  @override
  String get incomePlannerMetricLeverage => '杠杆';

  @override
  String get incomePlannerMetricAnnualCost => '年化时间价值成本';

  @override
  String get incomePlannerMetricFundingCoverage => '收入覆盖';

  @override
  String get incomePlannerRiskLow => '相对较低';

  @override
  String get incomePlannerRiskModerate => '相对中等';

  @override
  String get incomePlannerRiskElevated => '相对偏高';

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
  String get incomePlannerDetailContractSection => '合约信息';

  @override
  String get incomePlannerDetailLiquiditySection => '流动性';

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
  String get incomePlannerJournalDeleteTitle => '删除交易日记？';

  @override
  String get incomePlannerJournalDeleteBody => '该记录将从统计、Wheel 历史及对应账本镜像中移除。';

  @override
  String get incomePlannerJournalCreditLabel => '收取权利金（每张合约）';

  @override
  String incomePlannerJournalTotalCredit(String amount) {
    return '权利金总额：$amount';
  }

  @override
  String get incomePlannerAssignmentNeedsAccount =>
      '记录行权指派前请先选择券商账户，否则股票腿无法记入账本。';

  @override
  String get incomePlannerJournalDebitLabel => '平仓支付（每张合约）';

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
  String get incomePlannerJournalStatusAssigned => '被指派';

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
  String get incomePlannerStatsPremiumChartTitle => '各标的权利金';

  @override
  String optionsExplainYieldStrength(String yieldPct, String score) {
    return '年化收益 $yieldPct（评分 $score）';
  }

  @override
  String optionsExplainLiquidityStrength(
    String spread,
    int openInterest,
    String score,
  ) {
    return '流动性良好：买卖价差 $spread，未平仓量 $openInterest（评分 $score）';
  }

  @override
  String optionsExplainSafetyStrength(String margin, String score) {
    return '距盈亏平衡有 $margin 安全边际（评分 $score）';
  }

  @override
  String optionsExplainIvStrength(String iv, String score) {
    return '隐含波动率 $iv 处于稳健区间（评分 $score）';
  }

  @override
  String get optionsExplainIvUnknown => '未知';

  @override
  String optionsExplainFitStrength(String score) {
    return '与当前持仓契合（评分 $score）';
  }

  @override
  String optionsExplainEventStrength(String score) {
    return '未来 7 天无财报或宏观事件（评分 $score）';
  }

  @override
  String get optionsExplainEventUnavailable => '事件日历不可用；未对事件风险评分';

  @override
  String optionsExplainGenericScore(String dimension, String score) {
    return '$dimension 评分 $score';
  }

  @override
  String optionsExplainYieldWeak(String yieldPct, String score) {
    return '年化收益偏低：$yieldPct（评分 $score）';
  }

  @override
  String optionsExplainLiquidityWeak(String spread, String score) {
    return '流动性一般：买卖价差 $spread（评分 $score）';
  }

  @override
  String optionsExplainSafetyWeak(String margin, String score) {
    return '安全边际有限：$margin（评分 $score）';
  }

  @override
  String optionsExplainIvWeak(String score) {
    return '隐含波动率超出正常区间（评分 $score）';
  }

  @override
  String optionsExplainFitWeak(String score) {
    return '与当前持仓契合度一般（评分 $score）';
  }

  @override
  String optionsExplainEventWeak(String score) {
    return '处于事件窗口内，执行需谨慎（评分 $score）';
  }

  @override
  String get optionsExplainEventCheck => '下单前请先核对财报与宏观事件日期';

  @override
  String optionsExplainSummaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) {
    return '$symbol ${dte}DTE 卖出看跌 @ $strike — 年化 $yieldPct，安全边际 $margin';
  }

  @override
  String optionsExplainSummaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) {
    return '$symbol ${dte}DTE 备兑看涨 @ $strike — 年化 $yieldPct，安全边际 $margin';
  }

  @override
  String get optionsExplainBestForPutConservative =>
      '适合保守现金流偏好：优先考虑更高的安全边际与流动性。';

  @override
  String get optionsExplainBestForPutBalanced => '适合均衡现金流偏好：在收益与下行风险之间取得平衡。';

  @override
  String get optionsExplainBestForPutAggressive => '适合愿意承担更高被指派概率以换取年化收益的场景。';

  @override
  String get optionsExplainBestForCallConservative =>
      '适合保守增强：卖出更虚值的看涨期权，被行权概率更低。';

  @override
  String get optionsExplainBestForCallBalanced => '适合均衡增强：增加收入而不明显影响持仓。';

  @override
  String get optionsExplainBestForCallAggressive => '适合愿意接受被行权以兑现收益的场景。';

  @override
  String get optionsExplainAvoidPut => '如果你不愿在被指派时按行权价买入 100 股，请回避。';

  @override
  String get optionsExplainAvoidCall => '如果你不愿按行权价卖出 100 股，请回避。';

  @override
  String optionsExplainWorstPut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  ) {
    return '如果 $symbol 跌破 $strike，你将以 $breakeven 的有效成本买入 100 股，占用现金 $cash。';
  }

  @override
  String optionsExplainWorstCall(String symbol, String strike, String cap) {
    return '如果 $symbol 上涨至 $strike，你将按 $strike 卖出 100 股并放弃其上方涨幅；总收入上限为 $cap。';
  }

  @override
  String optionsExplainLeapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  ) {
    return '$symbol ${dte}DTE LEAPS 看涨 @ $strike — 成本 $cost，delta $delta';
  }

  @override
  String optionsExplainLeapsWorstCase(
    String symbol,
    String strike,
    String cost,
  ) {
    return '如果到期时 $symbol 收于 $strike 之下，$cost 权利金将全部归零。最大亏损为全部已付成本。';
  }

  @override
  String get optionsExplainLeapsBestFor =>
      '适合作为有收入资助的股票替代：由 Wheel 或股息收入支付的长期深实值敞口。';

  @override
  String get optionsExplainLeapsAvoid => '如果无法持有穿越完整回撤，请回避——时间价值会衰减，仓位可能到期归零。';

  @override
  String optionsExplainLeapsCostBullet(String costPct) {
    return '每单位股票敞口的年化时间价值成本 $costPct';
  }

  @override
  String optionsExplainLeapsLeverageBullet(String leverage, String delta) {
    return '每单位资金控制 $leverage 倍股票敞口（delta $delta）';
  }

  @override
  String optionsExplainLeapsIntrinsicBullet(String intrinsicPct) {
    return '权利金中 $intrinsicPct 为内在价值';
  }

  @override
  String optionsExplainLeapsSpreadBullet(String spread) {
    return '买卖价差较宽 $spread——LEAPS 流动性偏薄，请使用限价单';
  }

  @override
  String get optionsExplainLeapsDeltaEstimated => 'delta 由隐含波动率推算——数据源未提供希腊值';

  @override
  String optionsExplainLeapsThetaBullet(String extrinsic) {
    return '$extrinsic 的时间价值将在到期前衰减殆尽';
  }

  @override
  String optionsExplainLeapsFundingBullet(String coverage) {
    return '组内收入已覆盖此成本的 $coverage';
  }

  @override
  String optionsLedgerPremium(String symbol) {
    return '期权权利金 $symbol';
  }

  @override
  String optionsLedgerCloseDebit(String symbol) {
    return '期权平仓支出 $symbol';
  }

  @override
  String optionsLedgerPutAssigned(String symbol) {
    return '看跌期权被指派 $symbol';
  }

  @override
  String optionsLedgerCallAssigned(String symbol) {
    return '备兑看涨被行权 $symbol';
  }

  @override
  String optionsLedgerLeapsOpen(String symbol) {
    return 'LEAPS 开仓 $symbol';
  }

  @override
  String optionsLedgerLeapsClose(String symbol) {
    return 'LEAPS 平仓 $symbol';
  }

  @override
  String optionsLedgerLeapsExercise(String symbol) {
    return 'LEAPS 行权 $symbol';
  }

  @override
  String optionsLedgerLeapsExpired(String symbol) {
    return 'LEAPS 到期 $symbol';
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
  String get incomePlannerOccConfirmation =>
      '我理解每张合约被行权时可能需要买入或卖出 100 股，且本规划器不会下单，也不保证收益。';

  @override
  String get incomePlannerUnderlyingStrategyRequired => '请至少为该标的启用一种策略。';

  @override
  String get incomePlannerUnderlyingDeleteTitle => '移除已批准标的？';

  @override
  String incomePlannerUnderlyingDeleteBody(String symbol) {
    return '$symbol 将不再参与期权扫描。';
  }

  @override
  String get incomePlannerSupportedMarketHelper => '当前扫描支持美国上市股票和 ETF。';

  @override
  String get incomePlannerMaxBuyPriceLabel => '可接受的最高接货价';

  @override
  String get incomePlannerMaxBuyPriceHelper =>
      '高于该价格的 Put 行权价会被过滤；留空表示不增加价格上限。';

  @override
  String get incomePlannerMinSellPriceLabel => '可接受的最低卖出价';

  @override
  String get incomePlannerMinSellPriceHelper =>
      '低于该价格的 Call 行权价会被过滤；留空表示不增加价格下限。';

  @override
  String get incomePlannerUnderlyingNotesLabel => '投资立场';

  @override
  String get incomePlannerUnderlyingNotesHelper => '记录你愿意持有或卖出该标的的理由。';

  @override
  String get incomePlannerPositiveNumberValidation => '请输入大于零的数字。';

  @override
  String get incomePlannerProfileStrategyRequired => '请至少启用一种期权策略。';

  @override
  String incomePlannerProfileAdvancedSummary(
    int minDte,
    int maxDte,
    String capital,
  ) {
    return '$minDte–$maxDte DTE · 单笔最多 $capital%';
  }

  @override
  String get incomePlannerProfileMaxUnderlyingExposure => '行权后单一标的最大占比';

  @override
  String get incomePlannerProfilePutDeltaRange => 'Put 绝对 Delta 范围';

  @override
  String get incomePlannerProfileLeapsSection => 'LEAPS 扫描';

  @override
  String get incomePlannerProfileSellFilters => '卖方筛选';

  @override
  String incomePlannerProfileLeapsSummary(
    int minDte,
    int maxDte,
    String low,
    String high,
  ) {
    return '$minDte–$maxDte DTE · delta $low–$high';
  }

  @override
  String get incomePlannerProfileLeapsMinDte => 'LEAPS 最小 DTE';

  @override
  String get incomePlannerProfileLeapsMaxDte => 'LEAPS 最大 DTE';

  @override
  String get incomePlannerProfileLeapsDeltaRange => 'LEAPS 看涨 delta 区间';

  @override
  String get incomePlannerProfileLeapsMaxSpread => 'LEAPS 最大价差 (%)';

  @override
  String get incomePlannerProfileCallDeltaRange => 'Call Delta 范围';

  @override
  String get incomePlannerProfileDeltaLow => '下限';

  @override
  String get incomePlannerProfileDeltaHigh => '上限';

  @override
  String get incomePlannerProfileDeltaValidation => '请输入大于 0 且不超过 1 的小数。';

  @override
  String get incomePlannerProfileDeltaOrderValidation => '上限必须大于或等于下限。';

  @override
  String get incomePlannerWorkspaceOpportunities => '机会';

  @override
  String get incomePlannerWorkspaceJournal => '日志';

  @override
  String get incomePlannerWorkspaceCandidates => '候选';

  @override
  String get incomePlannerWorkspaceOpenPositions => '未平仓';

  @override
  String get incomePlannerWorkspaceApproved => '批准标的';

  @override
  String get incomePlannerWorkspaceNeverScanned => '尚未扫描';

  @override
  String get incomePlannerWorkspaceScanStale => '扫描已过期';

  @override
  String get incomePlannerWorkspaceScanFresh => '扫描较新';

  @override
  String incomePlannerWorkspaceProfileSummary(
    int minDte,
    int maxDte,
    String capital,
    String scanState,
  ) {
    return '$minDte–$maxDte DTE · 单笔最多 $capital · $scanState';
  }

  @override
  String get incomePlannerManageApprovedAction => '管理标的';

  @override
  String incomePlannerApprovedSummary(int count) {
    return '$count 个已批准标的';
  }

  @override
  String get incomePlannerScanProgressHint => '检查最新期权链时会保留旧结果，扫描最长可能需要 45 秒。';

  @override
  String incomePlannerScanCompletedToast(int count) {
    return '扫描完成 · $count 个候选';
  }

  @override
  String get incomePlannerOpportunityFilterAll => '全部';

  @override
  String incomePlannerOpportunityCountSummary(int visible, int total) {
    return '显示 $visible/$total，按适配评分排序';
  }

  @override
  String get incomePlannerOpportunityFilterEmpty => '当前策略筛选下没有机会。';

  @override
  String incomePlannerOpportunityExpirySummary(String date, int dte) {
    return '$date 到期 · $dte DTE';
  }

  @override
  String get incomePlannerMetricPremiumTotal => '总权利金';

  @override
  String get incomePlannerMetricUnderlyingPrice => '标的现价';

  @override
  String get incomePlannerMetricExpiration => '到期日';

  @override
  String get incomePlannerMetricDelta => 'Delta';

  @override
  String get incomePlannerMetricIv => '隐含波动率';

  @override
  String get incomePlannerMetricOpenInterest => '未平仓量';

  @override
  String get incomePlannerMetricVolume => '成交量';

  @override
  String get incomePlannerMetricSpread => '买卖价差';

  @override
  String get incomePlannerScoreYield => '收益';

  @override
  String get incomePlannerScoreLiquidity => '流动性';

  @override
  String get incomePlannerScoreSafetyMargin => '安全边际';

  @override
  String get incomePlannerScoreIv => '波动率适配';

  @override
  String get incomePlannerScorePortfolioFit => '组合适配';

  @override
  String get incomePlannerScoreEventSafety => '事件安全';

  @override
  String get incomePlannerRejectionReasonsTitle => '主要拒绝原因';

  @override
  String incomePlannerRejectionReasonSummary(String reason, int count) {
    return '$reason · $count 张合约';
  }

  @override
  String get incomePlannerRejectCapitalLimit => '超过资金上限';

  @override
  String get incomePlannerRejectLiquidity => '流动性不足';

  @override
  String get incomePlannerRejectSpread => '价差过大';

  @override
  String get incomePlannerRejectDte => '不在 DTE 范围';

  @override
  String get incomePlannerRejectDelta => '不在 Delta 范围';

  @override
  String get incomePlannerRejectDeltaUnavailable => '数据源未提供希腊值（delta）';

  @override
  String get incomePlannerRejectLeapsBudget => '超出 LEAPS 预算';

  @override
  String get incomePlannerRejectQuote => '无可用报价';

  @override
  String get incomePlannerRejectPriceIntent => '不符合你的价格意愿';

  @override
  String get incomePlannerRejectEventRisk => '事件风险保护';

  @override
  String get incomePlannerRejectOther => '其他硬性条件';

  @override
  String get incomePlannerApprovedPutNoLimit => '允许 Put';

  @override
  String incomePlannerApprovedPutLimit(String price) {
    return 'Put ≤ $price';
  }

  @override
  String get incomePlannerApprovedCallNoLimit => '允许 Call';

  @override
  String incomePlannerApprovedCallLimit(String price) {
    return 'Call ≥ $price';
  }

  @override
  String get incomePlannerJournalOpenedAtLabel => '开仓日期';

  @override
  String get incomePlannerJournalExpirationLabel => '到期日';

  @override
  String get incomePlannerJournalClosedAtLabel => '结算日期';

  @override
  String get incomePlannerJournalContractQuantityLabel => '合约数量';

  @override
  String get incomePlannerJournalFeesLabel => '总费用';

  @override
  String get incomePlannerJournalFilterAll => '全部';

  @override
  String get incomePlannerJournalFilterOpen => '未平仓';

  @override
  String get incomePlannerJournalFilterResolved => '已结算';

  @override
  String get incomePlannerJournalFilterEmpty => '当前筛选下没有交易日志。';

  @override
  String incomePlannerJournalExpiresIn(int days) {
    return '$days 天后到期';
  }

  @override
  String incomePlannerJournalQuantitySummary(int quantity, int size) {
    return '$quantity 张 · 每张 $size 股';
  }

  @override
  String get incomePlannerJournalPremiumLabel => '权利金';

  @override
  String get incomePlannerJournalNetPnlLabel => '净盈亏';

  @override
  String get planWheelStageMixedOpen => '多个混合未平仓头寸';

  @override
  String incomePlannerWheelOpenCount(int count) {
    return '$count 个未平仓头寸';
  }

  @override
  String incomePlannerWheelDueSummary(String position, int days) {
    return '$position · 剩余 $days 天';
  }

  @override
  String incomePlannerWheelExpiredSummary(String position, int days) {
    return '$position · 已到期 $days 天，请记录结果';
  }

  @override
  String get incomePlannerWheelRealizedIncome => '已实现净收入';

  @override
  String get incomePlannerWheelOpenPositionsTitle => '未平仓头寸';

  @override
  String get incomePlannerWheelExpirationMissing => '缺少到期日 · 请更新该日志';

  @override
  String get incomePlannerWheelNextReviewOpen => '检查重叠的未平仓头寸，并核对总风险暴露。';

  @override
  String get incomePlannerWheelNextWaitPut => '关注未平仓 Put，并在到期或平仓时记录结果。';

  @override
  String get incomePlannerWheelNextRecordPut => '先记录 Put 结果，再进入下一阶段。';

  @override
  String get incomePlannerWheelNextScanCall => '当前持有正股；仅在愿意卖出时扫描备兑 Call。';

  @override
  String get incomePlannerWheelNextWaitCall => '关注备兑 Call，并记录到期、平仓或行权结果。';

  @override
  String get incomePlannerWheelNextRecordCall => '记录正股被行权卖出的结果，并核对持仓与现金。';

  @override
  String get incomePlannerWheelNextStartPut => '现金待命；仅对已批准且愿意持有的标的开始新 Put。';

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
  String get healthTodayBriefSubtitle => '今日健康概览';

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
  String get healthSourceChecking => '正在检查连接…';

  @override
  String get healthSourceReady => '已就绪';

  @override
  String get healthSourcePermissionRequired => '需要权限';

  @override
  String get healthSourceUnavailable => '不可用';

  @override
  String get healthSourceSyncFailed => '同步失败';

  @override
  String healthSourceLastSync(String time) {
    return '同步于 $time';
  }

  @override
  String healthSourceLastAttempt(String time) {
    return '最近尝试于 $time';
  }

  @override
  String healthSourceLastSuccess(String time) {
    return '上次成功于 $time';
  }

  @override
  String healthSourceDataAt(String time) {
    return '数据于 $time';
  }

  @override
  String get healthSourceNoData => '还没有导入数据';

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
  String agentResultUpdated(String time) {
    return '更新于 $time';
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
  String get healthPlanEnableHint => '请在“设置 → 功能领域”中启用 HealthOS，才能查看恢复建议。';

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
  String get knowledgeInboxTitle => '收件箱';

  @override
  String knowledgeInboxSuggestionsPending(int count) {
    return '有 $count 条 AI 建议待确认';
  }

  @override
  String get knowledgeInboxSuggestionsLoading => '正在检查异步 AI 建议…';

  @override
  String get knowledgeInboxSuggestionsLoadFailed => '整理状态加载失败，点击重试';

  @override
  String get knowledgeInboxAiUnavailable => '笔记仍会正常保存；配置设备端 LLM 后可获得异步分类与标签建议。';

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
  String get knowledgeInboxEmptyBody => '先记下想法，KnowledgeOS 会在后台整理；任何升级都由你确认。';

  @override
  String get knowledgeInboxLoadFailedTitle => '收件箱加载失败';

  @override
  String get knowledgeCaptureAction => '新建捕获';

  @override
  String get knowledgeCreateEntry => '新建条目';

  @override
  String get knowledgeCaptureTitle => '写一条想法';

  @override
  String get knowledgeCaptureDraftRecovered => '已恢复这台设备上未完成的录入。';

  @override
  String get knowledgeCaptureDraftDiscard => '丢弃草稿';

  @override
  String get knowledgeCaptureDraftCleared => '草稿已清除';

  @override
  String get knowledgeCaptureTitleField => '标题（可选）';

  @override
  String get knowledgeCaptureBodyField => '内容';

  @override
  String get knowledgeCaptureTitleHint => '\"港卡需要定期活跃\"';

  @override
  String get knowledgeCaptureBodyHint => '\"港卡每 6 个月做一次活跃交易，否则会休眠\"';

  @override
  String get knowledgeCaptureSavedClassifyingTitle => '已保存 · AI 正在分析';

  @override
  String get knowledgeCaptureSavedPreviewTitle => '已保存的捕获';

  @override
  String get knowledgeCaptureSuggestionTitle => 'AI 建议';

  @override
  String get knowledgeCaptureComposeSubtitle =>
      '自然写下内容；保存前可由 AI 完整整理标题与 Markdown。';

  @override
  String get knowledgeCaptureClassifyingSubtitle =>
      '笔记已保存。AI 正在判断是否适合整理为例行事项、决策或其他知识内容。';

  @override
  String get knowledgeCaptureSuggestionSubtitle => '应用前先确认 AI 抽取的类型和字段。';

  @override
  String get knowledgeCaptureTypeLabel => '保存为';

  @override
  String get knowledgeCaptureKindAuto => '自动';

  @override
  String get knowledgeCaptureKindAutoDescription => '保存后由 KnowledgeOS 判断知识类型';

  @override
  String get knowledgeCaptureKindNote => '笔记';

  @override
  String get knowledgeCaptureKindRoutine => '例行事项';

  @override
  String get knowledgeCaptureKindDecision => '决策';

  @override
  String get knowledgeCaptureKindAssumption => '假设';

  @override
  String get knowledgeCaptureKindPrinciple => '原则';

  @override
  String get knowledgeCaptureKindConcept => '概念';

  @override
  String get knowledgeCaptureKindExperiment => '实验';

  @override
  String get knowledgeCaptureSave => '保存';

  @override
  String get knowledgeCaptureSavedToast => '已保存到收件箱，分类与关联建议将在后台生成。';

  @override
  String get knowledgeCaptureOrganizeAction => '整理并预览';

  @override
  String get knowledgeCaptureOrganizing => '正在整理…';

  @override
  String get knowledgeCaptureOrganizingSubtitle =>
      'AI 正在保持原意的前提下整理标题、层级与 Markdown。';

  @override
  String get knowledgeCaptureOrganizingBody => '正在生成完整、易读的内容草稿；确认前不会改动原文。';

  @override
  String get knowledgeCaptureOrganizedSubtitle => '先查看阅读效果，也可切换到编辑模式微调后再保存。';

  @override
  String get knowledgeCaptureAiOrganizationHint =>
      'AI 会优化标题、内容结构与阅读节奏，不补充原文没有的事实。';

  @override
  String get knowledgeCaptureSaveWithoutAi => '保存原文';

  @override
  String get knowledgeCaptureSaveOrganized => '保存整理稿';

  @override
  String get knowledgeCaptureReviewDraftTitle => '整理后的草稿';

  @override
  String get knowledgeCaptureReviewDraftSubtitle => '默认先预览，标题和正文仍可编辑。';

  @override
  String get knowledgeCaptureOriginalVersion => '原始内容';

  @override
  String get knowledgeCaptureOrganizedVersion => 'AI 整理稿';

  @override
  String get knowledgeCaptureShowOriginal => '查看原文';

  @override
  String get knowledgeCaptureShowOrganized => '查看整理稿';

  @override
  String get knowledgeCaptureUntitledOriginal => '无标题原文';

  @override
  String get knowledgeCaptureOrganizeFailed => 'AI 未能生成安全、完整的整理稿，原文没有变化。';

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
    return 'AI 判断这是一条笔记，将仅优化文字而不转换类型。原因：$reason';
  }

  @override
  String get knowledgeCapturePolishedVersionTitle => '确认整理稿';

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
  String get knowledgeCaptureKindNoteDescription => '保留为笔记';

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
  String get knowledgeAiPromptHint => '提问或搜索知识…';

  @override
  String get knowledgeAiAskAction => '询问 KnowledgeOS';

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
  String get knowledgeLibraryTitle => '资料库';

  @override
  String get knowledgeLibrarySelectItem => '选择一项，在阅读时继续浏览';

  @override
  String get knowledgeLibraryEmptyAllTitle => '资料库还没有内容';

  @override
  String get knowledgeLibraryEmptyAllBody => '先快速记录一条笔记，或直接创建决策和假设。';

  @override
  String get knowledgeLibraryEmptyDecisionsTitle => '还没有 Decision';

  @override
  String get knowledgeLibraryEmptyDecisionsBody => '新建 Decision，记录第一条值得复盘的判断。';

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
  String get knowledgeLibraryEmptyNotesBody =>
      '记录一条笔记，之后可由 KnowledgeOS 建议标签、关联或升级。';

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
  String get knowledgeLibraryTypeTitle => '知识类型';

  @override
  String get knowledgeLibraryTypePickerSubtitle => '选择资料库的浏览范围。';

  @override
  String knowledgeLibraryTypeScope(String type, int count) {
    return '$type · $count 条';
  }

  @override
  String get knowledgeLibraryTypeGroupCore => '核心';

  @override
  String get knowledgeLibraryTypeGroupSources => '素材';

  @override
  String get knowledgeLibraryTypeGroupThinking => '认知';

  @override
  String get knowledgeLibraryTypeGroupAction => '行动';

  @override
  String get knowledgeLibraryTypeAllDescription => '浏览全部知识对象';

  @override
  String get knowledgeLibraryTypeDecisionsDescription => '记录选择、理由与结果';

  @override
  String get knowledgeLibraryTypePrinciplesDescription => '长期稳定的判断规则';

  @override
  String get knowledgeLibraryTypeAssumptionsDescription => '仍需验证的判断';

  @override
  String get knowledgeLibraryTypeNotesDescription => '保留原始记录与来源';

  @override
  String get knowledgeLibraryTypeConceptsDescription => '归纳主题、别名与关联';

  @override
  String get knowledgeLibraryTypeExperimentsDescription => '用行动验证假设';

  @override
  String get knowledgeLibraryTypeRoutinesDescription => '需要周期执行的事项';

  @override
  String get knowledgeLibraryFilterAll => '全部';

  @override
  String get knowledgeLibraryFilterTitle => '筛选';

  @override
  String get knowledgeLibrarySearchClear => '清除搜索';

  @override
  String get knowledgeLibraryItemActions => '知识条目操作';

  @override
  String get knowledgeItemOrganize => 'AI 整理';

  @override
  String get knowledgeItemLink => '建立关联';

  @override
  String get knowledgeRelationSheetTitle => '关联知识';

  @override
  String get knowledgeRelationSearchHint => '搜索知识';

  @override
  String get knowledgeRelationNoTargets => '可用内容均已关联';

  @override
  String knowledgeRelationLinkedToast(Object title) {
    return '已关联至“$title”';
  }

  @override
  String get knowledgeRelationLinkedTitle => '已关联';

  @override
  String get knowledgeRelationAvailableTitle => '可关联知识';

  @override
  String knowledgeRelationRemoveLink(Object kind) {
    return '$kind · 解除关联';
  }

  @override
  String knowledgeRelationUnlinkedToast(Object title) {
    return '已解除与“$title”的关联';
  }

  @override
  String get knowledgeItemReview => '复盘';

  @override
  String get knowledgeItemPause => '暂停';

  @override
  String get knowledgeItemResume => '恢复';

  @override
  String get knowledgeItemCopySummary => '复制摘要';

  @override
  String get knowledgeItemStartExperiment => '开始';

  @override
  String get knowledgeItemRecordResult => '记录结果';

  @override
  String get knowledgeItemCopyResult => '复制结果';

  @override
  String get knowledgeItemRestartExperiment => '重新开始';

  @override
  String get knowledgeItemUpdatedToast => '知识已更新';

  @override
  String get knowledgeItemCopiedToast => '已复制';

  @override
  String get knowledgeLibrarySearchRecent => '最近';

  @override
  String get knowledgeLibrarySearchSuggestions => '建议';

  @override
  String get knowledgeLibrarySearchEmptyTitle => '没有匹配的知识';

  @override
  String get knowledgeLibrarySearchEmptyBody => '换个关键词，或切换到其他分段。';

  @override
  String knowledgeLibrarySearchEmptyScopedBody(String segment) {
    return '“$segment”中没有匹配结果。可搜索全部知识或换个关键词。';
  }

  @override
  String get knowledgeLibrarySearchAllAction => '搜索全部知识';

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
  String get knowledgeReviewOverviewTitle => '复盘状态';

  @override
  String get knowledgeReviewAllClearBadge => '全部正常';

  @override
  String get knowledgeReviewAllClearBody =>
      '当前没有到期复盘或待确认建议。即使未配置 AI，确定性复盘仍然可用。';

  @override
  String get knowledgeReviewBrowseLibrary => '浏览知识库';

  @override
  String get knowledgeReviewReorder => '拖动调整顺序';

  @override
  String knowledgeReviewAttentionSummary(
    int routines,
    int decisions,
    int assumptions,
    int suggestions,
    int findings,
  ) {
    return '$routines 个 Routine · $decisions 个 Decision · $assumptions 个 Assumption · $suggestions 条 AI 建议 · $findings 条冲突';
  }

  @override
  String get knowledgeReviewAgentNotRun => 'Knowledge Review Agent 尚未运行。';

  @override
  String knowledgeReviewLastRun(String date) {
    return '最近一次 Agent 复盘：$date';
  }

  @override
  String get knowledgeReviewAiUnavailable =>
      '尚未配置可用的设备端 LLM，AI 建议不可用；到期复盘仍可正常使用。';

  @override
  String get knowledgeReviewRunNow => '运行 Knowledge Review';

  @override
  String get knowledgeReviewRoutinesTitle => '本周到期的例行事项';

  @override
  String get knowledgeReviewRoutinesEmpty => '未来 7 天内没有到期的 Routine。';

  @override
  String get knowledgeReviewDecisionsTitle => '待复盘的决策';

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
  String get knowledgeReviewAssumptionsTitle => '待验证的假设';

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
    return '· $statement（$days 天，置信度 $confidence）';
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
  String get knowledgeReviewAssumptionConfirmTitle => '确认这条 Assumption';

  @override
  String knowledgeReviewAssumptionConfirmBody(String statement) {
    return '仅当当前证据仍支持以下假设时确认：\n“$statement”';
  }

  @override
  String get knowledgeReviewAssumptionStillValid => '仍然成立';

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
  String get knowledgeNewDecision => '新建决策';

  @override
  String get knowledgeNewPrinciple => '新建原则';

  @override
  String get knowledgeNewAssumption => '新建假设';

  @override
  String get knowledgeNewNote => '新建笔记';

  @override
  String get knowledgeNewConcept => '新建概念';

  @override
  String get knowledgeNewExperiment => '新建实验';

  @override
  String get knowledgeNewRoutine => '新建例行事项';

  @override
  String get knowledgeNewMoreTypes => '更多类型';

  @override
  String get knowledgeNewChooserTitle => '新建…';

  @override
  String get knowledgeNewChooserSubtitle => '选择要创建的结构化知识。临时想法可以先记入收件箱。';

  @override
  String get knowledgeNewDecisionHint => '主要内容：问题、选项和理由';

  @override
  String get knowledgeNewPrincipleHint => '世界观原语，例如 \"edge-first\"';

  @override
  String get knowledgeNewAssumptionHint => '可证伪的信念 + 置信度';

  @override
  String get knowledgeDecisionWriterTitle => '新建决策';

  @override
  String get knowledgeDecisionWriterSubtitle => '记录决策的问题、选项、理由和复盘';

  @override
  String get knowledgeDecisionEditTitle => '编辑决策';

  @override
  String get knowledgeDecisionEditSubtitle => '更新选项、理由、预期结果和复盘计划';

  @override
  String get knowledgeDecisionAddOption => '添加选项';

  @override
  String get knowledgeDecisionClear => '清除';

  @override
  String get knowledgeDecisionExpectedOutcomeLabel => '预期结果（可选）';

  @override
  String get knowledgeDecisionRevisitConditionsLabel => '满足这些条件时复盘（可选）';

  @override
  String get knowledgeDecisionRevisitConditionsHint => '每行一个条件，例如：现金缓冲低于 12 个月';

  @override
  String get knowledgeDecisionRevisitConditionsTitle => '复盘条件';

  @override
  String get knowledgeAssumptionWriterSubtitle2 => '可证伪的信念，设置置信度以便后续复盘';

  @override
  String get knowledgeConceptWriterSubtitle2 => '用于 soft links 和 AI 交叉引用的锚点';

  @override
  String get knowledgeExperimentWriterSubtitle2 => '用明确方法验证一条假设';

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
  String get knowledgeDecisionOptionsRequirement => '至少填写两个不同的选项。';

  @override
  String get knowledgeDecisionSelectionRequirement => '请选择最终决定采用的选项。';

  @override
  String knowledgeDecisionOptionLabelHint(Object index) {
    return '选项 $index';
  }

  @override
  String get knowledgeDecisionOptionRationaleHint => '为什么选这个选项（可选）';

  @override
  String get knowledgeDecisionNoReferenceCandidates =>
      '尚未声明原则或假设。你可以先保存决策，之后再添加引用。';

  @override
  String get knowledgeDecisionRationaleLabel => '理由（Markdown）';

  @override
  String get knowledgeDecisionRationaleHint => '为什么选这个选项 — 限制条件、当时的判断';

  @override
  String get knowledgeDecisionExpectedOutcomeHint => '如何判断成功，例如使用哪些指标或信号';

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
  String get knowledgeDecisionLifecycleSubtitle => '状态、实际结果和认知变化';

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
  String get knowledgePrincipleWriterTitle => '新建原则';

  @override
  String get knowledgePrincipleWriterSubtitle => '长期世界观原语，不可证伪';

  @override
  String get knowledgePrincipleStatementHint =>
      '\"默认 edge-first\" / \"避免高维护成本系统\"';

  @override
  String get knowledgePrincipleRationaleHint => '为什么把这个世界观定为原则';

  @override
  String get knowledgeAssumptionWriterTitle => '新建假设';

  @override
  String get knowledgeAssumptionEditTitle => '编辑假设';

  @override
  String get knowledgeAssumptionEditSubtitle => '更新陈述、置信度和适用范围';

  @override
  String get knowledgeAssumptionWriterSubtitle => '可证伪的信念 + 置信度';

  @override
  String get knowledgeAssumptionStatementHint => '\"长期指数增长高于通胀\"';

  @override
  String get knowledgeConceptWriterTitle => '新建概念';

  @override
  String get knowledgeConceptWriterSubtitle => '用于搜索和内容关联的命名节点';

  @override
  String get knowledgeConceptNameHint => '概念名称（例如 \"edge-first\"）';

  @override
  String get knowledgeConceptAliasesHint => '逗号分隔的同义词';

  @override
  String get knowledgeConceptSummaryHint => '用 1–2 句话说明这个概念';

  @override
  String get knowledgeExperimentWriterTitle => '新建实验';

  @override
  String get knowledgeExperimentWriterSubtitle => '用方法和指标验证一条假设';

  @override
  String get knowledgeExperimentHypothesisHint =>
      '\"covered call 60 DTE on QQQ 优于 30 DTE\"';

  @override
  String get knowledgeExperimentMethodHint => '怎么做、跑多久、用什么数据';

  @override
  String get knowledgeExperimentMetricsHint =>
      '逗号分隔（例如 \"yield, drawdown, sharpe\"）';

  @override
  String get knowledgeExperimentNoActiveAssumptions => '目前没有可关联的活跃假设，也可以暂时留空';

  @override
  String get knowledgeExperimentTargetAssumptionLabel => '关联假设（可选）';

  @override
  String get knowledgeRoutineWriterTitle => '新建例行事项';

  @override
  String get knowledgeRoutineWriterSubtitle => '设置定期提醒，临近到期时会主动提示';

  @override
  String get knowledgeRoutineStatementHint => '例如“港卡做一次活跃交易”或“每月对账”';

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
  String get knowledgeConfidenceLow => '较低';

  @override
  String get knowledgeConfidenceMedium => '中等';

  @override
  String get knowledgeConfidenceHigh => '较高';

  @override
  String get knowledgeWriterScopeHint => '可选，例如投资、健康或工作';

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
  String get knowledgeWriterContextSectionTitle => '补充信息';

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
  String get knowledgeNotesHintTitle => '在收件箱快速记录';

  @override
  String get knowledgeNotesHintBody => '资料库用于浏览已保存的笔记。临时想法请先记入收件箱，再在复盘中整理。';

  @override
  String get knowledgeNoteTagsLabel => '标签（用逗号分隔）';

  @override
  String get amountHidden => '金额已隐藏';

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
  String get healthGarminRememberPassword => '安全保存密码';

  @override
  String get healthGarminRememberPasswordHint =>
      '仅加密保存在本机 Keychain 或 Keystore，不会同步。';

  @override
  String get healthGarminAutoRenewEnabled => '会话自动续期已开启';

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
  String get healthGarminErrorCredentialsInvalid =>
      '已保存的 Garmin 密码已失效，请重新输入密码连接。';

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
  String get settingsDomainsExecutionEnabledSubtitle => '今日行动、承诺、进展和个人待办事项';

  @override
  String get settingsDomainsExecutionDisabledSubtitle => '把决策与计划转成可追踪的行动';

  @override
  String get settingsDomainsExecutionTodaySubtitle => '查看今天的行动、阻塞与进展';

  @override
  String get executionTabToday => '今天';

  @override
  String get executionTabCommitments => '计划';

  @override
  String get executionTabReview => '复盘';

  @override
  String get executionCommandToday => 'ExecutionOS 今天';

  @override
  String get executionCommandCommitments => 'ExecutionOS 计划';

  @override
  String get executionCommandReview => 'ExecutionOS 复盘';

  @override
  String get executionTodayTitle => '今天';

  @override
  String get executionTodayBriefSubtitle => '今日执行概览';

  @override
  String get executionCommitmentsTitle => '计划';

  @override
  String get executionPlansSelectItem => '选择一个计划，在此处查看详情';

  @override
  String get executionReviewTitle => '复盘';

  @override
  String get executionReviewNeedsAttentionTitle => '需要关注';

  @override
  String get executionReviewWeekResultsTitle => '本周结果';

  @override
  String executionReviewRecentActivity(int count) {
    return '近期活动 · $count';
  }

  @override
  String get executionReviewDetailsTitle => '复盘详情';

  @override
  String get executionReviewDetailsSubtitle => '数据新鲜度与技术运行详情';

  @override
  String get executionCreateActionTitle => '新建行动';

  @override
  String get executionCreatePlanTitle => '添加';

  @override
  String get executionCreateProjectTitle => '新建计划';

  @override
  String get executionCreateCommitmentTitle => '新建承诺';

  @override
  String get executionCreateProgressTitle => '新建进展';

  @override
  String get executionEditProgressTitle => '编辑进展';

  @override
  String get executionEditActionTitle => '编辑行动';

  @override
  String get executionEditProjectTitle => '编辑计划';

  @override
  String get executionEditCommitmentTitle => '编辑承诺';

  @override
  String get executionActionField => '行动';

  @override
  String get executionProjectField => '计划';

  @override
  String get executionCommitmentField => '承诺';

  @override
  String get executionRelationField => '归属';

  @override
  String get executionNoRelation => '收件箱 · 不归属计划';

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
  String get executionProjectTitleHint => '哪件事需要多个步骤完成？';

  @override
  String get executionProjectDescriptionHint => '可选结果、范围或完成标准';

  @override
  String get executionCommitmentTitleHint => '你承诺推进什么？';

  @override
  String get executionCommitmentDescriptionHint => '可选范围、原因或目标结果';

  @override
  String get executionOverviewFocus => '今日';

  @override
  String get executionOverviewBlocked => '阻塞';

  @override
  String get executionOverviewHigh => '高优先';

  @override
  String get executionOverviewDue => '到期';

  @override
  String get executionOverviewProjects => '计划';

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
  String get executionTodayFilteredEmptyBody => '切换筛选；有需要跟进的事情再捕获为行动。';

  @override
  String executionDeleteConfirmTitle(Object item) {
    return '删除「$item」？';
  }

  @override
  String get executionDeleteConfirmBody => '这会从 ExecutionOS 移除该条目，并同步删除记录。';

  @override
  String get executionCommitmentsEmptyTitle => '没有进行中事项';

  @override
  String get executionCommitmentsEmptyBody => '先记录一个具体行动；需要多个步骤时再建立计划。';

  @override
  String get executionCommitmentsClosedEmptyTitle => '没有已关闭事项';

  @override
  String get executionCommitmentsClosedEmptyBody => '已完成或已归档的计划会出现在这里。';

  @override
  String get executionReviewEmptyTitle => '还没有进展记录';

  @override
  String get executionReviewEmptyBody => '完成与阻塞记录会出现在这里，方便复盘。';

  @override
  String get executionClosedActionsSection => '最近已关闭行动';

  @override
  String get executionProjectsSection => '计划';

  @override
  String get executionCommitmentsSection => '持续事项';

  @override
  String get executionInboxSection => '收集箱';

  @override
  String get executionActionsSection => '行动';

  @override
  String get executionRelatedActionsSection => '关联行动';

  @override
  String get executionTimelineSection => '时间线';

  @override
  String get executionDetailMissingTitle => '未找到条目';

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
  String executionDueBadge(String date) {
    return '截止 $date';
  }

  @override
  String executionScheduledBadge(String date) {
    return '计划 $date';
  }

  @override
  String executionOverdueBadge(String date) {
    return '逾期 $date';
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
  String get executionLifecycleArchive => '归档';

  @override
  String get executionLifecycleActiveView => '进行中';

  @override
  String get executionLifecycleClosedView => '已关闭';

  @override
  String get executionClosedWorkEntry => '已关闭事项';

  @override
  String get executionActiveWorkEntry => '返回进行中事项';

  @override
  String get executionProjectStatusUpdateFailed => '更新项目状态失败。';

  @override
  String get executionCommitmentStatusUpdateFailed => '更新承诺状态失败。';

  @override
  String get executionProgressDoneDefault => '已标记为完成。';

  @override
  String get executionProgressDroppedDefault => '已标记为放弃。';

  @override
  String get executionProgressStartedDefault => '已开始推进。';

  @override
  String get executionProgressResumedDefault => '已恢复推进。';

  @override
  String get executionProjectPausedDefault => '项目已暂停。';

  @override
  String get executionProjectResumedDefault => '项目已恢复。';

  @override
  String get executionProjectCompletedDefault => '项目已完成。';

  @override
  String get executionProjectArchivedDefault => '项目已归档。';

  @override
  String get executionCommitmentPausedDefault => '承诺已暂停。';

  @override
  String get executionCommitmentResumedDefault => '承诺已恢复。';

  @override
  String get executionCommitmentCompletedDefault => '承诺已完成。';

  @override
  String get executionCommitmentArchivedDefault => '承诺已归档。';

  @override
  String get executionLifecycleCompleteConfirmTitle => '仍有未完成行动，确认完成？';

  @override
  String executionLifecycleCompleteConfirmBody(int count) {
    return '完成后仍会保留 $count 条开放行动，并移入收集箱。';
  }

  @override
  String get executionLifecycleArchiveConfirmTitle => '仍有未完成行动，确认归档？';

  @override
  String executionLifecycleArchiveConfirmBody(int count) {
    return '归档后仍会保留 $count 条开放行动，并移入收集箱。';
  }

  @override
  String executionLifecycleStatusUpdated(Object status) {
    return '状态已更新为「$status」';
  }

  @override
  String executionDeleteWithOpenActionsBody(int count) {
    return '删除后，该条目下的 $count 条开放行动会移入收集箱。';
  }

  @override
  String get executionProgressKindField => '进展类型';

  @override
  String get executionProgressNoteField => '进展记录';

  @override
  String get executionProgressNoteHint => '记录变化或备注；如需改变行动状态，请使用行动操作。';

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
  String get executionOpenActionsSection => '开放行动';

  @override
  String get executionStandaloneActionsSection => '独立行动';

  @override
  String get executionUnplacedActionsSection => '待安置行动';

  @override
  String get executionProjectCommitmentsSection => '项目承诺';

  @override
  String get executionReviewWindow7d => '7 天';

  @override
  String get executionReviewWindow30d => '30 天';

  @override
  String get executionReviewWindowAll => '全部';

  @override
  String get executionReviewCompletedMetric => '已完成';

  @override
  String get executionReviewBlockedMetric => '阻塞';

  @override
  String get executionReviewProgressMetric => '进展';

  @override
  String get executionReviewGenerateTitle => '执行复盘';

  @override
  String get executionReviewGenerateBody => '在本地生成焦点、阻塞、到期事项和近期进展摘要。';

  @override
  String get executionReviewGenerateAction => '生成复盘';

  @override
  String get executionProposalActionLabel => '行动';

  @override
  String get executionProposalActionStatusLabel => '行动状态';

  @override
  String get executionProposalProjectLabel => '项目';

  @override
  String get executionProposalCommitmentLabel => '承诺';

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
    return '提取率 $withdrawalRate，安全提取率 $safeRate；现金储备可覆盖 $cashBucketMonths 个月，目标为 $targetCashBucketMonths 个月。';
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
    return '低风险 $low · 中风险 $moderate · 高风险 $elevated';
  }

  @override
  String financeAgentOptionsEvidenceScanLabel(Object scanId) {
    return '期权收入扫描 $scanId';
  }

  @override
  String get financeAgentOptionsAction => '查看期权扫描';

  @override
  String healthAgentRecoverySkipInsufficient(Object count) {
    return 'HRV 数据不足（$count 个点）';
  }

  @override
  String get healthAgentRecoverySkipNoDecline => '未检测到持续 HRV 下降';

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
  String get executionAgentReviewInsightStalledTitle => '停滞事项';

  @override
  String executionAgentReviewInsightStalledBody(Object count) {
    return '$count 个进行中行动至少 7 天没有变化。';
  }

  @override
  String get executionAgentReviewInsightNoNextActionTitle => '缺少下一步';

  @override
  String executionAgentReviewInsightNoNextActionBody(
    Object commitmentCount,
    Object projectCount,
  ) {
    return '$projectCount 个活跃项目和 $commitmentCount 个活跃承诺没有未完成的下一步行动。';
  }

  @override
  String get executionAgentReviewInsightOverdueTargetsTitle => '目标日期已过';

  @override
  String executionAgentReviewInsightOverdueTargetsBody(
    Object commitmentCount,
    Object projectCount,
  ) {
    return '$projectCount 个项目和 $commitmentCount 个承诺已超过目标日期。';
  }

  @override
  String get executionAgentReviewInsightRepeatedBlockerTitle => '重复阻塞';

  @override
  String executionAgentReviewInsightRepeatedBlockerBody(Object count) {
    return '本周有 $count 个行动多次记录阻塞。';
  }

  @override
  String get executionAgentReviewInsightOverloadTitle => '今日负载过高';

  @override
  String executionAgentReviewInsightOverloadBody(Object count, Object limit) {
    return '今天有 $count 个行动争夺注意力，建议聚焦约 $limit 个。';
  }

  @override
  String get executionAgentReviewInsightThroughputTitle => '每周吞吐';

  @override
  String executionAgentReviewInsightThroughputBody(
    Object completedCount,
    Object droppedCount,
  ) {
    return '本周完成 $completedCount 个行动，放弃 $droppedCount 个。';
  }

  @override
  String get executionAgentReviewInsightOutcomeTitle => '行动关闭后的来源信号';

  @override
  String executionAgentReviewInsightOutcomeBody(
    Object activeCount,
    Object clearedCount,
  ) {
    return '行动关闭后，有 $clearedCount 个来源信号已未检测到，$activeCount 个仍被检测到。';
  }

  @override
  String get executionAgentReviewPlanAction => '生成恢复计划';

  @override
  String get executionAgentReviewPlanActionBody =>
      '复盘停滞和缺少归属的工作，并为用户确认生成具体下一步或状态更新。';

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
  String get ingestKindTransfer => '转账';

  @override
  String get ingestKindTrade => '证券交易';

  @override
  String get ingestRecordTransfer => '进入转账表单';

  @override
  String get ingestRecordTrade => '进入交易表单';

  @override
  String get ingestTransferRecorded => '转账已记录，草稿已完成。';

  @override
  String get ingestTradeRecorded => '交易已记录，草稿已完成。';

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

  @override
  String get financialInboxTitle => '财务收件箱';

  @override
  String get financialInboxPriorityImportant => '重要';

  @override
  String get financialInboxPriorityAttention => '待复核';

  @override
  String financialInboxLastCheckedCompact(String date) {
    return '检查于 $date';
  }

  @override
  String get monthlyCloseTitle => '月度关账';

  @override
  String get monthlyCloseStart => '开始月度关账';

  @override
  String get monthlyCloseStartBody => '复核本月证据、核对账户余额，并保留清晰的关账记录。';

  @override
  String monthlyClosePeriod(String period) {
    return '关账 $period';
  }

  @override
  String get monthlyCloseIntro => '完成所有依据核对后再关闭本月。';

  @override
  String get monthlyCloseImport => '复核导入交易';

  @override
  String get monthlyCloseInbox => '清空财务收件箱';

  @override
  String get monthlyCloseAccounts => '核对账户余额';

  @override
  String get monthlyCloseRunway => '检查未来 90 天';

  @override
  String get monthlyCloseActions => '检查后续行动';

  @override
  String get monthlyCloseMarkDone => '完成';

  @override
  String get monthlyCloseUndo => '撤销';

  @override
  String get monthlyCloseComplete => '关闭本月';

  @override
  String get monthlyCloseCompleted => '本月已关闭';

  @override
  String get monthlyCloseReconciliationTitle => '账户对账';

  @override
  String get monthlyCloseLedgerBalance => '本期末账本余额';

  @override
  String monthlyCloseDifference(String amount, String unit) {
    return '差额：$amount $unit';
  }

  @override
  String get monthlyCloseEnterStatementBalance => '录入账单余额';

  @override
  String monthlyCloseStatementBalanceTitle(String account) {
    return '$account 的账单余额';
  }

  @override
  String get monthlyCloseAcceptDifference => '接受差额';

  @override
  String get monthlyCloseDifferenceReasonTitle => '为什么接受这笔差额？';

  @override
  String get monthlyCloseDifferenceReasonHint => '记录尚未解决的原因';

  @override
  String get monthlyCloseWithException => '带例外关账';

  @override
  String get monthlyCloseExceptionTitle => '说明关账例外';

  @override
  String get monthlyCloseExceptionHint => '记录为什么接受剩余未验证项';

  @override
  String get monthlyCloseStateBlocked => '受阻';

  @override
  String get monthlyCloseStateReady => '待核对';

  @override
  String get monthlyCloseStateVerified => '已验证';

  @override
  String get monthlyCloseStateOverridden => '已接受';

  @override
  String get monthlyCloseVerifiedBody => '关闭本月时，所有依据均已验证。';

  @override
  String monthlyCloseOverriddenBody(String reason) {
    return '带例外关闭：$reason';
  }

  @override
  String financialInboxCount(int count) {
    return '有 $count 项需要处理';
  }

  @override
  String get financialInboxEmptyTitle => '已全部处理';

  @override
  String get financialInboxEmptyBody => '新的导入记录和已确认的资金风险会出现在这里。';

  @override
  String get financialInboxResolve => '解决';

  @override
  String get financialInboxSnooze => '稍后处理';

  @override
  String get financialInboxChooseSnooze => '稍后提醒时间';

  @override
  String get financialInboxSnoozeTomorrow => '明天';

  @override
  String get financialInboxSnoozeWeek => '7 天后';

  @override
  String get financialInboxSnoozeMonth => '30 天后';

  @override
  String get financialInboxResolveGroup => '批量完成';

  @override
  String financialInboxResolveGroupBody(int count) {
    return '确认完成该优先级分组中的全部 $count 项？';
  }

  @override
  String financialInboxResolvedCount(int count) {
    return '已完成 $count 项';
  }

  @override
  String financialInboxImportTitle(int count) {
    return '复核 $count 条导入记录';
  }

  @override
  String get financialInboxImportBody => '确认后再写入正式账本。';

  @override
  String get financialInboxRunwayTitle => '检查资金续航';

  @override
  String get financialInboxRunwayBody => '预测余额低于你的安全储备。';

  @override
  String financialInboxFxTitle(int count) {
    return '补充 $count 个缺失汇率';
  }

  @override
  String get financialInboxFxBody => '缺失汇率会降低预测可信度。';

  @override
  String financialInboxBalanceTitle(int count) {
    return '处理 $count 个余额差异';
  }

  @override
  String get financialInboxBalanceBody => '账单余额与账本余额不一致。';

  @override
  String get financialInboxAnomalyTitle => '复核异常支出';

  @override
  String get financialInboxAnomalyBody => '预计支出与最近月份存在明显差异。';

  @override
  String financialInboxSubscriptionTitle(int count) {
    return '复核 $count 个订阅变化';
  }

  @override
  String get financialInboxSubscriptionBody => '周期付款的变化超过了本地检测阈值。';

  @override
  String financialInboxValuationTitle(int count) {
    return '刷新 $count 个过期估值';
  }

  @override
  String get financialInboxValuationBody => '过期价格会降低当前资产状况的可信度。';

  @override
  String get financialInboxDecisionTitle => '复盘财务决策';

  @override
  String get financialInboxDecisionBody => '该决策已经到达计划复盘日期。';

  @override
  String financialInboxConcentrationTitle(int count) {
    return '复核 $count 项集中度风险';
  }

  @override
  String get financialInboxConcentrationBody => '单只持仓或行业权重超过你设定的集中度阈值。';

  @override
  String financialInboxRebalanceTitle(int count) {
    return '再平衡 $count 项配置偏离';
  }

  @override
  String get financialInboxRebalanceBody => '单票目标权重偏离已超过再平衡预警阈值。';

  @override
  String financialInboxDividendTitle(int count) {
    return '复核 $count 项分红下滑';
  }

  @override
  String get financialInboxDividendBody => '持仓的滚动分红较前一年明显下降。';

  @override
  String get financialInboxEvidenceDimension => '维度';

  @override
  String get financialInboxEvidenceLabel => '名称';

  @override
  String get financialInboxEvidenceWeight => '权重';

  @override
  String get financialInboxEvidenceThreshold => '阈值';

  @override
  String get financialInboxEvidenceSeverity => '严重程度';

  @override
  String get financialInboxEvidenceBreachCount => '偏离项数';

  @override
  String get financialInboxEvidenceMaxDeviation => '最大偏离';

  @override
  String get financialInboxEvidenceDropRatio => '下滑比例';

  @override
  String get financialInboxEvidenceTtmGross => '近12月毛分红';

  @override
  String get financialInboxEvidencePriorTtmGross => '前12月毛分红';

  @override
  String get financialInboxEvidenceAssetId => '资产';

  @override
  String get settingsProductMetricsTitle => '本地产品指标';

  @override
  String get settingsProductMetricsSubtitle =>
      '自愿开启仅存于设备的漏斗计数；不记录或上传财务数值与身份标识。';

  @override
  String get settingsProductMetricsCopy => '复制产品验证数据';

  @override
  String get settingsProductMetricsCopySubtitle => '导出本设备上隐私安全的每日与累计指标。';

  @override
  String get settingsProductMetricsCopied => '已复制产品验证数据';

  @override
  String get lifeEventScenariosTitle => '人生事件推演';

  @override
  String get lifeEventScenariosIntro => '做决定前先比较确定性计算结果；假设、选择和后续复盘会保存在一起。';

  @override
  String get lifeEventOptimistic => '乐观';

  @override
  String get lifeEventBaseline => '基准';

  @override
  String get lifeEventConservative => '保守';

  @override
  String get lifeEventScenariosEmptyTitle => '请先建立财务基线';

  @override
  String get lifeEventScenariosEmptyBody => '添加账户和支出记录后，推演会使用你的真实流动资金和月支出。';

  @override
  String get lifeEventLargePurchase => '大额消费';

  @override
  String get lifeEventCareerBreak => '职业空档';

  @override
  String get lifeEventHomePurchase => '购房';

  @override
  String get lifeEventLargePurchaseAssumption => '预设：一次性支出当前流动资金的 20%。';

  @override
  String lifeEventCareerBreakAssumption(int months) {
    return '预设：$months 个月无收入。';
  }

  @override
  String get lifeEventHomePurchaseAssumption => '预设：首付为流动资金的 30%，一年内月支出增加 10%。';

  @override
  String get lifeEventAfter90Days => '90 天后流动资金';

  @override
  String get lifeEventAfter12Months => '12 个月后流动资金';

  @override
  String get lifeEventMonthlySurplus => '事件期间月结余';

  @override
  String get lifeEventEditAssumptions => '编辑假设';

  @override
  String get lifeEventUpfrontCost => '一次性成本';

  @override
  String get lifeEventIncomeDelta => '月收入变化';

  @override
  String get lifeEventOutflowDelta => '月支出变化';

  @override
  String get lifeEventDurationMonths => '持续月数';

  @override
  String get lifeEventFireImpact => '预计 FIRE 影响';

  @override
  String lifeEventFireDelay(int months) {
    return '约推迟 $months 个月';
  }

  @override
  String get lifeEventFireNoDelay => '无明显推迟';

  @override
  String get lifeEventAskAi => '让助手解读';

  @override
  String get lifeEventChooseScenario => '保存决策';

  @override
  String get lifeEventOpenAction => '打开后续行动';

  @override
  String get lifeEventAdjustPlan => '调整预算';

  @override
  String get lifeEventDecisionSaved => '已保存决策和假设';

  @override
  String lifeEventReviewActionTitle(String decision) {
    return '复盘决策：$decision';
  }

  @override
  String get lifeEventReviewActionBody => '将确定性预测与实际财务数据对比，不推断因果关系。';

  @override
  String get lifeEventDecisionHistory => '待复盘决策';

  @override
  String get lifeEventPendingReview => '待复盘';

  @override
  String get lifeEventReviewed => '已复盘';

  @override
  String lifeEventReviewOn(String date) {
    return '计划于 $date 复盘';
  }

  @override
  String get lifeEventChooseReviewDate => '选择复盘时间';

  @override
  String get lifeEventReviewIn30Days => '30 天后';

  @override
  String get lifeEventReviewIn90Days => '90 天后';

  @override
  String get lifeEventReviewIn180Days => '180 天后';

  @override
  String get lifeEventCaptureActual => '记录当前结果';

  @override
  String lifeEventObservedDifference(String amount) {
    return '观察到的 90 天余额差异：$amount。这只是对比，不代表因果关系。';
  }

  @override
  String get moneyRunwayCreateAction => '将风险转为行动';

  @override
  String get moneyRunwayActionConfirmTitle => '创建 Execution 行动？';

  @override
  String get moneyRunwayActionConfirmBody => '当前现金安全依据会附在行动中，确认前不会创建任何内容。';

  @override
  String get moneyRunwayActionTitle => '改善近期现金安全';

  @override
  String get moneyRunwayActionCreated => '已创建 Execution 行动';

  @override
  String get moneyRunwayTitle => '现金安全';

  @override
  String get moneyRunwayNinetyDayBalance => '90 天后预计余额';

  @override
  String get moneyRunwayEmptyTitle => '建立现金安全基线';

  @override
  String get moneyRunwayEmptyBody => '导入账单或添加账户，即可查看未来 90 天。';

  @override
  String get moneyRunwayHorizonsTitle => '未来余额';

  @override
  String moneyRunwayMinimumBalance(String amount) {
    return '未来最低余额：$amount';
  }

  @override
  String moneyRunwayMinimumBalanceDate(String date) {
    return '最低点日期：$date';
  }

  @override
  String moneyRunwayRiskDate(String date) {
    return '预计 $date 出现现金缺口';
  }

  @override
  String moneyRunwayReserveBreachDate(String date) {
    return '预计 $date 低于储备目标';
  }

  @override
  String moneyRunwayDays(Object days) {
    return '$days 天';
  }

  @override
  String get moneyRunwayStatusHealthy => '稳健';

  @override
  String get moneyRunwayStatusHealthyBody => '预计现金始终高于你的储备目标。';

  @override
  String get moneyRunwayStatusWatch => '需关注';

  @override
  String get moneyRunwayStatusWatchBody => '预计现金仍为正，但会低于储备目标。';

  @override
  String get moneyRunwayStatusShortfall => '存在缺口';

  @override
  String get moneyRunwayStatusShortfallBody => '预计现金会在当前窗口内降至零以下。';

  @override
  String moneyRunwayConfidence(Object confidence) {
    return '可信度：$confidence';
  }

  @override
  String get moneyRunwayConfidenceLow => '低';

  @override
  String get moneyRunwayConfidenceMedium => '中';

  @override
  String get moneyRunwayConfidenceHigh => '高';

  @override
  String get moneyRunwayAssumptionsTitle => '计算假设';

  @override
  String get moneyRunwayStartingCash => '流动资金';

  @override
  String get moneyRunwayReserveTarget => '储备目标';

  @override
  String get moneyRunwayVariableEstimate => '每月可变支出估计';

  @override
  String get moneyRunwaySourceObservedHistory => '近 90 天实际记录';

  @override
  String get moneyRunwaySourceFirePlan => 'FIRE 计划';

  @override
  String get moneyRunwaySourceDefaultPolicy => '默认 3 个月储备';

  @override
  String get moneyRunwayCoverage => '应急覆盖';

  @override
  String get moneyRunwayCompleteness => '数据完整度';

  @override
  String get moneyRunwayHistoricalError => '近期预测误差';

  @override
  String get moneyRunwayScenariosTitle => '压力测试';

  @override
  String get moneyRunwayScenarioPurchase => '立即支出一个月生活费';

  @override
  String get moneyRunwayScenarioDelayedIncome => '预计收入延迟 14 天';

  @override
  String get moneyRunwayScenarioReducedIncome => '预计收入减少 30%';

  @override
  String get moneyRunwayCustomScenarioAction => '自定义压力测试';

  @override
  String get moneyRunwayCustomScenarioTitle => '自定义现金续航场景';

  @override
  String moneyRunwayCustomPurchase(String currency) {
    return '一次性支出（$currency）';
  }

  @override
  String get moneyRunwayCustomDelayDays => '收入延迟（天）';

  @override
  String get moneyRunwayCustomReductionPercent => '收入减少（%）';

  @override
  String get moneyRunwayCustomDurationDays => '减少持续时间（天）';

  @override
  String get moneyRunwayCustomInvalid => '请输入非负数、0 至 100% 的收入降幅，并至少设置一个压力因素。';

  @override
  String get moneyRunwayCustomRun => '运行场景';

  @override
  String get moneyRunwayCustomResult => '自定义场景最低余额';

  @override
  String get moneyRunwayCustomReset => '清除自定义场景';

  @override
  String moneyRunwayCoverageMonths(Object months) {
    return '$months 个月';
  }

  @override
  String get moneyRunwayScheduledTitle => '已知未来收支';

  @override
  String get moneyRunwayScheduledEmpty => '尚未配置周期收入或账单。';

  @override
  String moneyRunwayScheduledCount(int count) {
    return '已计入 $count 项未来收支';
  }

  @override
  String get moneyRunwayTimelineTitle => '未来现金时间线';

  @override
  String moneyRunwayTimelineMore(int count) {
    return '查看全部 $count 项';
  }

  @override
  String get moneyRunwayTimelineLess => '收起时间线';

  @override
  String moneyRunwayTimelineBalanceAfter(String amount) {
    return '当日预计余额：$amount';
  }

  @override
  String get moneyRunwayTimelineEmpty => '未来 90 天没有已排期收支，可添加周期收入或账单。';

  @override
  String get moneyRunwayManageScheduled => '管理未来收支';

  @override
  String get moneyRunwayDeclaredDividend => '已宣告税后股息';

  @override
  String get moneyRunwayEstimatedDividend => '推算税后股息';

  @override
  String get moneyRunwayEstimatedFlow => '估算';

  @override
  String moneyRunwayMissingFx(Object currencies) {
    return '因缺少汇率而未计入：$currencies';
  }

  @override
  String get financeActivationTitle => '获得第一个有效结果';

  @override
  String get financeActivationDismiss => '隐藏设置引导';

  @override
  String financeActivationProgress(int completed, int total) {
    return '$completed/$total';
  }

  @override
  String get financeActivationDataTitle => '从真实流水开始';

  @override
  String get financeActivationDataBody => '手工记一笔或导入账单，让结果建立在你自己的数据上。';

  @override
  String get financeActivationDataAction => '添加财务数据';

  @override
  String get financeActivationReviewTitle => '只处理例外项';

  @override
  String financeActivationReviewBody(int count) {
    return '还有 $count 项需要确认或恢复。';
  }

  @override
  String get financeActivationReviewAction => '继续复核';

  @override
  String get financeActivationRunwayTitle => '检查未来 90 天';

  @override
  String get financeActivationRunwayBody => '流水已就绪，请确认资金续航结果及其缺失数据。';

  @override
  String get financeActivationRunwayAction => '查看资金续航';

  @override
  String get financialInboxEvidenceTitle => '判断依据';

  @override
  String get financialInboxFirstDetected => '首次发现';

  @override
  String get financialInboxLastChecked => '最近检查';

  @override
  String get financialInboxLinkedAction => '关联行动';

  @override
  String get financialInboxFixSource => '修复来源数据';

  @override
  String get financialInboxCreateAction => '创建行动';

  @override
  String get financialInboxViewAction => '查看行动';

  @override
  String get financialInboxActionUnavailable => '启用 ExecutionOS 后才能创建行动。';

  @override
  String get financialInboxEvidencePeriod => '期间';

  @override
  String get financialInboxEvidenceMismatchCount => '余额差异';

  @override
  String get financialInboxEvidenceChangeRatio => '变化比例';

  @override
  String get financialInboxEvidenceExpenseCount => '本月支出笔数';

  @override
  String get financialInboxExpenseDetailsTitle => '具体支出';

  @override
  String get financialInboxExpenseUntitled => '支出';

  @override
  String get financialInboxEvidenceChangeCount => '变化数量';

  @override
  String get financialInboxEvidenceStaleCount => '过期估值';

  @override
  String get financialInboxEvidenceReviewDate => '复盘日期';

  @override
  String get financialInboxEvidenceCurrencies => '币种';

  @override
  String get financialInboxEvidenceCompleteness => '数据完整度';

  @override
  String get financialInboxActionTodo => '待处理';

  @override
  String get financialInboxActionDoing => '进行中';

  @override
  String get financialInboxActionBlocked => '受阻';

  @override
  String get financialInboxActionDone => '已完成';

  @override
  String get financialInboxActionDropped => '已放弃';

  @override
  String get financialInboxActionUnknown => '不可用';

  @override
  String get financialInboxRevalidation => '来源复核';

  @override
  String get financialInboxRevalidationCleared => '后续完整检查中已消失';

  @override
  String get financialInboxRevalidationStillDetected => '行动完成后仍被检测到';

  @override
  String get financialInboxRevalidationInconclusive => '未能完成来源检查';

  @override
  String get financialInboxRevalidationActionDropped => '行动已放弃，信号保持打开';

  @override
  String get financialInboxRevalidatedAt => '复核时间';

  @override
  String get monthlyCloseCoverageTitle => '账户覆盖率';

  @override
  String monthlyCloseCoverageValue(int accepted, int total) {
    return '$accepted/$total';
  }

  @override
  String monthlyCloseSincePrevious(int newCount, int clearedCount) {
    return '相比上次关账：新增 $newCount 个信号，清除 $clearedCount 个。';
  }

  @override
  String monthlyClosePreviousDuration(int minutes) {
    return '上次关账耗时 $minutes 分钟。';
  }

  @override
  String monthlyCloseCarriedForward(int signals, int reconciliations) {
    return '上次月结遗留：$signals 个信号，$reconciliations 个对账异常。';
  }

  @override
  String get monthlyCloseHistoryTitle => '月结历史';

  @override
  String monthlyCloseHistoryCount(int count) {
    return '$count 次历史关账';
  }

  @override
  String monthlyCloseHistoryExceptions(int count) {
    return '$count 个异常';
  }

  @override
  String monthlyCloseHistoryDuration(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get expenseCategoriesManageTitle => '支出类别';

  @override
  String get expenseCategoriesAdd => '新增类别';

  @override
  String get expenseCategoriesEdit => '编辑类别';

  @override
  String get expenseCategoriesEmpty => '暂无支出类别';

  @override
  String get expenseCategoriesArchived => '已归档';

  @override
  String get expenseCategoriesBuiltIn => '内置类别';

  @override
  String get expenseCategoriesCustom => '自定义类别';

  @override
  String get expenseCategoriesMoveUp => '上移';

  @override
  String get expenseCategoriesMoveDown => '下移';

  @override
  String get expenseCategoriesArchive => '归档类别';

  @override
  String get expenseCategoriesRestore => '恢复类别';

  @override
  String get expenseCategoriesNameLabel => '名称';

  @override
  String get expenseCategoriesNameRequired => '请输入类别名称';

  @override
  String get expenseCategoriesParentLabel => '上级类别';

  @override
  String get expenseCategoriesParentHelper => '可选；留空表示一级类别。';

  @override
  String get expenseCategoriesMakeTopLevel => '移为一级类别';

  @override
  String get expenseCategoriesIconLabel => '图标标识';

  @override
  String get expenseCategoriesColorLabel => '强调色';

  @override
  String get expenseCategoriesColorHelper => '选择用于列表与报表的类别颜色。';

  @override
  String get leapsOverlayTitle => 'LEAPS 上涨敞口';

  @override
  String get leapsOverlaySubtitle => '独立于 Wheel 记录的长期看涨期权';

  @override
  String get leapsOverlayAdd => '添加 LEAPS Call';

  @override
  String get leapsOverlayEdit => '编辑 LEAPS Call';

  @override
  String get leapsOverlayEmpty => '尚未记录长期看涨期权';

  @override
  String leapsOverlayOpenCount(int count) {
    return '$count 个未平仓 LEAPS';
  }

  @override
  String get leapsOverlayCost => '未平仓权利金风险';

  @override
  String get leapsOverlayCoverage => 'Wheel 收益覆盖率';

  @override
  String get leapsOverlayDeltaShares => 'Delta 等效股数';

  @override
  String get leapsOverlayCombinedRealized => '组合已实现损益';

  @override
  String get leapsOverlayUnknown => '未记录';

  @override
  String leapsOverlayCoverageValue(String percent) {
    return '已覆盖 $percent%';
  }

  @override
  String get leapsOverlayOptionSymbol => 'Call 合约';

  @override
  String get leapsOverlayOpenedAt => '开仓日期';

  @override
  String get leapsOverlayExpiration => '到期日';

  @override
  String get leapsOverlayStrike => '行权价';

  @override
  String get leapsOverlayEntryDebit => '每张开仓支出';

  @override
  String get leapsOverlayExitCredit => '每张平仓收入';

  @override
  String get leapsOverlayCurrentMark => '每张当前市值';

  @override
  String get leapsOverlayCurrentDelta => '当前 Delta（0–1）';

  @override
  String get leapsOverlayMarkedAt => '估值日期';

  @override
  String get leapsOverlayStatus => '持仓状态';

  @override
  String get leapsOverlayStatusOpen => '持仓中';

  @override
  String get leapsOverlayStatusClosed => '已平仓';

  @override
  String get leapsOverlayStatusExercised => '已行权';

  @override
  String get leapsOverlayStatusExpired => '已到期';

  @override
  String get leapsOverlayDeleteTitle => '删除 LEAPS 持仓？';

  @override
  String get leapsOverlayDeleteBody => '该持仓会从已同步的策略记录中移除。';

  @override
  String get leapsOverlayDurationHint =>
      'LEAPS 在挂牌时属于长期合约；即使当前剩余不足一年，也应记录真实到期日。';

  @override
  String get leapsOverlayDeltaHint => '可选的手工快照。未知时请留空，NaviWealth 不会虚构数值。';

  @override
  String get leapsOverlayDateInvalid => '到期日必须晚于开仓日期。';

  @override
  String get leapsOverlayDeltaInvalid => '请输入 0 到 1 之间的 Delta。';

  @override
  String get aiChatProposalKindLeapsCall => 'LEAPS Call 持仓';

  @override
  String get incomeStrategyTitle => '收益策略';

  @override
  String get incomeStrategyTabOverview => '总览';

  @override
  String get incomeStrategyTabUnderlyings => '标的';

  @override
  String get incomeStrategyTabActivity => '动态';

  @override
  String get incomeStrategyEmptyTitle => '尚未形成收益策略';

  @override
  String get incomeStrategyEmptyBody =>
      '围绕同一标的自由组合股息、Wheel 和 LEAPS。即使某个实际仓位不在计划中，也会继续显示其风险。';

  @override
  String get incomeStrategyRealizedResult => '已实现结果';

  @override
  String get incomeStrategyProjectedCash => '预计现金';

  @override
  String get incomeStrategyCapitalAtRisk => '风险资本';

  @override
  String get incomeStrategyRiskCount => '待复核风险';

  @override
  String get incomeStrategyRisksTitle => '组合协调风险';

  @override
  String get incomeStrategyUnderlyingsTitle => '标的策略轨道';

  @override
  String incomeStrategyRiskSummary(int count) {
    return '$count 项风险';
  }

  @override
  String get incomeStrategyPlanAligned => '符合计划';

  @override
  String get incomeStrategyEnabled => '已启用';

  @override
  String get incomeStrategyDisabled => '未启用';

  @override
  String get incomeStrategyNoPosition => '暂无实际仓位';

  @override
  String get incomeStrategyActivityEmpty => '暂无策略动态';

  @override
  String get incomeStrategyOpenDividendCenter => '股息中心';

  @override
  String get incomeStrategyOpenOptionsPlanner => '期权工作台';

  @override
  String get incomeStrategySleeveDividends => '股息';

  @override
  String get incomeStrategySleeveWheel => 'Wheel';

  @override
  String get incomeStrategySleeveLeaps => 'LEAPS Call';

  @override
  String get incomeStrategyStatusHolding => '持有中';

  @override
  String get incomeStrategyStatusPlanned => '已规划';

  @override
  String get incomeStrategyStatusOpen => '持仓中';

  @override
  String get incomeStrategyStatusResolved => '已结束';

  @override
  String get incomeStrategyMetricPartial => '估值不完整';

  @override
  String get incomeStrategyCashFlowDividend => '股息税前收入';

  @override
  String get incomeStrategyCashFlowWithholding => '股息预扣税';

  @override
  String get incomeStrategyCashFlowWheel => 'Wheel 已实现结果';

  @override
  String get incomeStrategyCashFlowLeapsPurchase => '买入 LEAPS';

  @override
  String get incomeStrategyCashFlowLeapsSale => '卖出 LEAPS';

  @override
  String get incomeStrategyCashFlowLeapsExercise => 'LEAPS 行权现金';

  @override
  String get incomeStrategyRiskUnplanned => '存在不在当前策略计划内的实际仓位；应复核该敞口，而不是将它隐藏。';

  @override
  String get incomeStrategyRiskCapitalBudget => '组合策略资金占用已超过计划预算。';

  @override
  String get incomeStrategyRiskAssignment => '开放 Put 的潜在行权金额超过设定上限。';

  @override
  String get incomeStrategyRiskConcentration => '该标的仓位超过设定的组合权重上限。';

  @override
  String get incomeStrategyRiskDividend =>
      '当前存在 Covered Call，但计划要求保留股息收入；股票可能在未来被行权卖出。';

  @override
  String get incomeStrategyRiskStacked =>
      'Wheel Short Put 与 LEAPS Call 在同一标的上叠加了对下跌敏感的资本。';

  @override
  String get incomeStrategyRiskLeapsBudget => '未平仓 LEAPS 成本超过设定预算。';

  @override
  String get incomeStrategyRiskLeapsCoverage => '已实现收入尚未覆盖未平仓 LEAPS 成本。';

  @override
  String get incomeStrategyRiskMissingMark => 'LEAPS 缺少当前市值，组合估值不完整。';

  @override
  String get incomeStrategyRiskMissingDelta => 'LEAPS 缺少 Delta，等效股数敞口不完整。';

  @override
  String get incomeStrategyRiskMissingFx => '缺少汇率，一个或多个金额汇总不完整。';

  @override
  String get incomeStrategyRiskStaleValuation => '持仓估值已过期，需要刷新。';

  @override
  String get incomeStrategyRiskIncomeTarget => '年初至今已实现收入明显落后于年度目标。';

  @override
  String get incomeStrategyRiskExpiration => '有期权临近到期，需要复核。';

  @override
  String get incomeStrategyPlanAdd => '添加策略计划';

  @override
  String get incomeStrategyPlanEdit => '编辑策略计划';

  @override
  String get incomeStrategyPlanSubtitle => '自由选择策略组合，并统一设置风险边界。';

  @override
  String get incomeStrategyPlanAsset => '标的';

  @override
  String get incomeStrategyPlanSleeves => '启用的策略模块';

  @override
  String get incomeStrategyPlanGroup => '策略组';

  @override
  String get incomeStrategyPlanGroupHint =>
      '跨标的协同 wheel 与 LEAPS——例如用 TQQQ Wheel 收入资助 QQQ LEAPS。';

  @override
  String get incomeStrategyPlanGroupNone => '无（独立标的）';

  @override
  String get incomeStrategyPlanGroupNew => '新建组…';

  @override
  String get incomeStrategyPlanGroupNameLabel => '组名称';

  @override
  String get incomeStrategyPlanGroupNameRequired => '请输入新组的名称。';

  @override
  String get incomeStrategyPlanPreserveDividend => '优先保留股息收入';

  @override
  String get incomeStrategyPlanAllowCalledAway => '允许股票被行权卖出';

  @override
  String get incomeStrategyPlanLimits => '统一限制';

  @override
  String get incomeStrategyPlanLimitsHint => '可选的组合与策略边界';

  @override
  String get incomeStrategyPlanCapitalBudget => '总资本预算';

  @override
  String get incomeStrategyPlanAnnualTarget => '年度收入目标';

  @override
  String get incomeStrategyPlanMaxWeight => '最大组合权重（%）';

  @override
  String get incomeStrategyPlanMaxLeapsCost => 'LEAPS 最大未平仓成本';

  @override
  String get incomeStrategyPlanMaxAssignment => 'Put 最大潜在行权金额';

  @override
  String get incomeStrategyPlanAssetRequired => '请选择标的。';

  @override
  String get incomeStrategyPlanSleeveRequired => '请至少启用一个策略模块。';

  @override
  String get incomeStrategyPlanNumberInvalid => '限制必须为非负数，组合权重必须在 0 到 100 之间。';

  @override
  String get incomeStrategyPlanDeleteTitle => '删除策略计划？';

  @override
  String get incomeStrategyPlanDeleteBody => '实际持仓和交易仍会显示，但该标的的组合设置与限制将被移除。';

  @override
  String get rebalanceStagePortfolioTitle => '1 · 组合间资金调拨';

  @override
  String get rebalanceStageStrategyTitle => '2 · 组合内策略仓配置';

  @override
  String get rebalanceStageAssetTitle => '3 · 策略仓内资产配置';

  @override
  String rebalanceDecisionPolicyBlocked(String name) {
    return '$name 已超出允许偏差，但当前调拨规则阻止了所需资金移动。';
  }

  @override
  String rebalanceDecisionNoCounterparty(String name) {
    return '$name 已超出允许偏差，但目前没有符合条件的资金来源或去向。';
  }

  @override
  String get rebalanceCapitalBlockedTitle => '需要处理';

  @override
  String get rebalanceConfigurePlanAction => '修改配置方案';

  @override
  String get portfolioCapitalAssignmentTitle => '资产归属';

  @override
  String get portfolioCapitalAssignmentSubtitle => '将持仓与现金唯一归属到一个组合和策略。';

  @override
  String get portfolioCapitalAssignmentLotsAction => '分配持仓';

  @override
  String get portfolioCapitalAssignmentLotsHint => '按整笔或部分批次将持仓归属到策略。';

  @override
  String get portfolioCapitalAssignmentCashAction => '分配现金';

  @override
  String get portfolioCapitalAssignmentCashHint => '将账户现金预留给指定策略。';

  @override
  String get portfolioStrategyLibraryTitle => '策略类型库';

  @override
  String get portfolioStrategyLibrarySubtitle => '集中管理添加策略时可用的内置与自定义类型。';

  @override
  String get portfolioStrategyBuiltInBadge => '内置';

  @override
  String get portfolioStrategyCustomBadge => '自定义';

  @override
  String get portfolioStrategyEditAction => '编辑';

  @override
  String get portfolioStrategyArchiveAction => '归档';

  @override
  String get portfolioStrategyArchiveTitle => '归档此策略类型？';

  @override
  String get portfolioStrategyArchiveBody => '已有策略保留当前配置，但以后添加策略时将不再显示此类型。';

  @override
  String get portfolioStrategyArchiveFailed => '无法归档此策略类型。';

  @override
  String get rebalanceCapitalFirstHint =>
      '请先通过资产归属完成上方资金调拨；组合与策略进入允许偏差后，才可执行策略内资产交易。';

  @override
  String get rebalanceCapitalBlockedHint =>
      '当前资金配置无法自动完成。请调整调拨规则、目标比例或补充可用资金；解决后系统会重新计算下一阶段。';

  @override
  String get rebalanceTransferTaskTitle => '当前调拨任务';

  @override
  String rebalanceTransferTaskSummary(String from, String to, String amount) {
    return '$from → $to · $amount';
  }

  @override
  String get rebalanceTransferTaskHint =>
      '优先移动现金；不足时再调整持仓归属。完成后返回再平衡，系统会用最新资产归属重新计算下一阶段。';

  @override
  String get rebalanceTransferTaskRecalculateAction => '完成并重新计算';

  @override
  String get rebalanceCapitalFirstAction => '请先处理资金调拨';

  @override
  String get rebalanceResolveTransferAction => '处理调拨';

  @override
  String get healthActivationTitle => '连接健康数据';

  @override
  String get healthActivationBody =>
      '选择你已经在用的数据源。所有连接均为只读，也可以仅靠手动记录使用 HealthOS。';

  @override
  String get healthActivationAction => '连接系统健康';

  @override
  String get healthActivationGarminAction => '连接 Garmin';

  @override
  String get healthActivationManualAction => '手动记录';

  @override
  String healthRefreshFresh(String time) {
    return '健康数据更新于$time';
  }

  @override
  String healthRefreshStale(String time) {
    return '健康数据可能已过期 · 更新于$time';
  }

  @override
  String healthRefreshPartialFailure(int count) {
    return '$count 个数据源刷新失败';
  }

  @override
  String get healthRefreshPullHint => '下拉即可同步所有已连接数据源';

  @override
  String healthRecoveryConfidence(String confidence, int coverage) {
    return '$confidence可信度 · $coverage% 覆盖';
  }

  @override
  String get healthRecoveryConfidenceHigh => '高';

  @override
  String get healthRecoveryConfidenceMedium => '中';

  @override
  String get healthRecoveryConfidenceLow => '低';

  @override
  String get healthRecoveryConfidenceInsufficient => '不足';

  @override
  String healthRecoveryFreshness(String time) {
    return '最新输入于$time';
  }

  @override
  String get healthRecoveryWhyTitle => '为什么是这个分数';

  @override
  String get healthRecoveryWhyLess => '收起评分依据';

  @override
  String healthRecoveryEvidence(String metric, String recent, String delta) {
    return '$metric：当前 $recent · 较基线$delta';
  }

  @override
  String healthRecoveryEvidenceNoBaseline(String metric, String recent) {
    return '$metric：当前 $recent · 正在建立个人基线';
  }

  @override
  String healthRecoveryEvidenceBaseline(
    String baseline,
    int recentSamples,
    int baselineSamples,
  ) {
    return '基线 $baseline · 近期 $recentSamples 条 / 基线 $baselineSamples 条';
  }

  @override
  String healthRecoveryEvidenceNoBaselineSamples(int recentSamples) {
    return '近期 $recentSamples 条 · 正在建立个人基线';
  }

  @override
  String healthRecoveryDeltaUp(String value) {
    return '高 $value%';
  }

  @override
  String healthRecoveryDeltaDown(String value) {
    return '低 $value%';
  }

  @override
  String get healthRecoveryMetricHrv => 'HRV';

  @override
  String get healthRecoveryMetricRhr => '静息心率';

  @override
  String get healthRecoveryMetricSleep => '睡眠';

  @override
  String get healthRecoveryMetricVo2 => '最大摄氧量';

  @override
  String get healthRecoveryMetricBodyBattery => '身体电量';

  @override
  String get healthRecoveryMetricStress => '压力';

  @override
  String get healthSettingsSourcesTitle => '已连接的数据源';

  @override
  String get healthSettingsSourcesHelp => '集中管理连接、Garmin 安全会话和数据新鲜度。';

  @override
  String get executionDailyFocusTitle => '今日 Top 3';

  @override
  String get executionDailyFocusEmpty => '选择今天真正值得投入注意力的最多三个行动。';

  @override
  String get executionTodayNextActions => '接下来的行动';

  @override
  String executionDailyFocusSuggestion(String titles) {
    return '最近复盘建议：$titles';
  }

  @override
  String get executionDailyFocusUseSuggestion => '采用建议';

  @override
  String executionActionStatusUpdated(String status) {
    return '行动已移至「$status」';
  }

  @override
  String get executionQuickWhenField => '何时处理';

  @override
  String get executionQuickWhenInbox => '收集箱';

  @override
  String get executionQuickWhenToday => '今天';

  @override
  String get executionQuickWhenTomorrow => '明天';

  @override
  String get executionShowDetails => '更多选项';

  @override
  String get executionHideDetails => '收起选项';

  @override
  String get executionScheduleAfterDue => '计划日期不能晚于截止日期。';

  @override
  String get executionBlockReasonTitle => '是什么阻塞了这个行动？';

  @override
  String get executionBlockReasonHint => '记录依赖、待决事项或缺失信息';

  @override
  String get executionDailyFocusToggle => 'Top 3';

  @override
  String executionDailyFocusCount(int count) {
    return '$count/3';
  }

  @override
  String get executionDailyFocusReplaceTitle => '替换 Top 3 行动';

  @override
  String executionDailyFocusReplaceBody(String title) {
    return '今日 Top 3 已满，请选择一项替换为“$title”。';
  }

  @override
  String get executionDailyFocusReplaceAction => '替换此行动';

  @override
  String get executionDailyFocusMoveUp => '上移';

  @override
  String get executionDailyFocusMoveDown => '下移';

  @override
  String get executionDailyFocusRemove => '移出 Top 3';

  @override
  String get executionDueAgentTitle => '即将到期的行动';

  @override
  String get executionDueAgentDescription => '每天检查明天前到期的未完成行动，并可发送本地提醒。';

  @override
  String get executionDueAgentNothingDue => '未来一天内没有行动到期。';

  @override
  String executionDueAgentSummary(int count, String title) {
    return '明天前有 $count 个行动到期，首项：$title';
  }

  @override
  String executionReviewCreateNextActions(int count) {
    return '创建 $count 个下一步行动';
  }

  @override
  String get executionReviewCreateNextActionsBody =>
      '是否为仍缺少下一步行动的每个项目或承诺创建一个高优先级行动？';

  @override
  String executionReviewCreatedNextActions(int count) {
    return '已创建 $count 条下一步行动';
  }

  @override
  String executionReviewDraftNextActions(int count) {
    return '检查 $count 个缺失的下一步';
  }

  @override
  String get executionReviewAgentNotRun => '每周 Execution Review 尚未运行。';

  @override
  String get executionReviewAgentRunning => 'Execution Review 正在运行。';

  @override
  String get executionReviewAgentFailed =>
      '最近一次 Execution Review 失败，活动摘要仍可正常使用。';

  @override
  String executionReviewAgentLastRun(String date) {
    return '最近一次 Execution Review：$date';
  }

  @override
  String get executionReviewRunNow => '运行复盘';

  @override
  String executionReviewNextActionFor(String title) {
    return '明确「$title」的下一步';
  }

  @override
  String get agentSettingsTriggerEvent => '数据变更';

  @override
  String get executionSearchTitle => '搜索 ExecutionOS';

  @override
  String get executionSearchFilterTitle => '结果类型';

  @override
  String get executionSearchFilterAll => '全部';

  @override
  String get executionSearchHint => '搜索行动和计划';

  @override
  String get executionSearchEmptyTitle => '搜索全部执行事项';

  @override
  String get executionSearchEmptyBody => '结果包含进行中和已关闭的行动与计划。';

  @override
  String get executionSearchStartAction => '开始搜索';

  @override
  String get executionSearchNoResults => '没有匹配事项';

  @override
  String get executionSearchTryAgain => '可尝试标题、备注或描述。';

  @override
  String get executionSearchClearAction => '清除搜索';

  @override
  String get executionSearchKindAction => '行动';

  @override
  String get executionSearchKindProject => '计划';

  @override
  String get executionSearchKindProgress => '进展';

  @override
  String get knowledgeSettingsReviewCadence => '复盘频率';

  @override
  String get knowledgeSettingsStaleThreshold => '假设过期阈值';

  @override
  String knowledgeSettingsEveryDays(int days) {
    return '每 $days 天';
  }

  @override
  String knowledgeSettingsAfterDays(int days) {
    return '连续 $days 天未验证后';
  }

  @override
  String knowledgeCaptureNeedsStructure(String kind) {
    return '创建 $kind 前需要补齐结构化字段：决策选项、假设置信度，或实验方法与指标。';
  }

  @override
  String get knowledgeMarkdownInsertImage => '插入图片';

  @override
  String get knowledgeImageSourceCamera => '拍照';

  @override
  String get knowledgeImageSourceGallery => '相册';

  @override
  String get knowledgeImageSourceFile => '选择文件';

  @override
  String get knowledgeImageImportFailed => '图片导入失败';

  @override
  String get knowledgeImageLocalOnlyToast => '图片已插入，目前仅保存在此设备。';

  @override
  String get developerIssuesTitle => '报告产品问题';

  @override
  String get developerIssuesSubtitle =>
      '保存一份带有限诊断信息的本地 dogfood 报告。只有你明确导出后，数据才会离开设备。';

  @override
  String get developerIssuesDescriptionLabel => '哪里需要改进？';

  @override
  String get developerIssuesDescriptionHint => '例如：FIRE 卡片的信息层级让建议操作不容易被发现。';

  @override
  String get developerIssuesDescriptionHelp => '请说明观察到的问题与预期结果，不要填写密钥等敏感信息。';

  @override
  String get developerIssuesDescriptionRequired => '请先描述产品问题再保存。';

  @override
  String get developerIssuesCaptureAction => '保存本地报告';

  @override
  String get developerIssuesCapturingAction => '正在保存…';

  @override
  String get developerIssuesSavedToast => '报告已保存在此设备';

  @override
  String get developerIssuesSaveFailedToast => '报告保存失败，请检查描述后重试。';

  @override
  String get developerIssuesContextSection => '自动附加的上下文';

  @override
  String get developerIssuesRouteLabel => '来源页面';

  @override
  String get developerIssuesDomainLabel => '领域';

  @override
  String get developerIssuesShellDomain => 'LifeOS 外壳';

  @override
  String get developerIssuesHistorySection => '本地报告';

  @override
  String get developerIssuesEmpty => '此设备尚未保存报告。';

  @override
  String get developerIssuesExportAction => '导出';

  @override
  String get developerIssuesExportedLabel => '已导出';

  @override
  String get developerIssuesLocalLabel => '仅本地';

  @override
  String get developerIssuesTraceAttached => '已附 Trace';

  @override
  String developerIssuesToolErrorsAttached(int count) {
    return '$count 个工具错误码';
  }

  @override
  String get developerIssuesExportFailedToast => '无法打开导出面板，请重试。';

  @override
  String get developerIssuesAdvancedTitle => '产品问题报告';

  @override
  String get developerIssuesAdvancedSubtitle =>
      '在本地捕获页面、构建版本、最新 Trace 与有限工具错误码';
}
