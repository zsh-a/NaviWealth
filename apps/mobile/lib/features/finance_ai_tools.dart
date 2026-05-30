/// FinanceOS device-tool aggregator (`docs/lifeos-shell.md` §7.1, D-1.2).
///
/// Each Finance feature owns its `ai_tools/` subdir; this barrel
/// collects them so `bootstrap.dart` can register the full list with
/// the cross-domain `deviceToolsProvider`. HealthOS D-2 will land an
/// analogous `health_ai_tools.dart` alongside.
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainFinance;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import 'accounts/ai_tools/list_payment_accounts_tool.dart';
import 'accounts/ai_tools/propose_account_create_tool.dart';
import 'accounts/ai_tools/read_account_window_tool.dart';
import 'cashflow/ai_tools/get_cashflow_buckets_tool.dart';
import 'cashflow/ai_tools/get_refund_links_tool.dart';
import 'cashflow/ai_tools/get_transfer_links_tool.dart';
import 'expense/ai_tools/get_anomaly_flags_tool.dart';
import 'expense/ai_tools/get_recurring_patterns_tool.dart';
import 'expense/ai_tools/get_subscription_changes_tool.dart';
import 'expense/ai_tools/propose_expense_tool.dart';
import 'expense/ai_tools/read_category_window_tool.dart';
import 'fire/ai_tools/get_fire_buckets_tool.dart';
import 'fire/ai_tools/get_fire_plan_tool.dart';
import 'fire/ai_tools/get_fire_review_tool.dart';
import 'fire/ai_tools/get_fire_state_tool.dart';
import 'fire/ai_tools/get_fire_stress_tests_tool.dart';
import 'fire/ai_tools/propose_fire_bucket_rule_tool.dart';
import 'fire/ai_tools/propose_fire_plan_update_tool.dart';
import 'fire/ai_tools/simulate_fire_plan_tool.dart';
import 'home/ai_tools/get_net_worth_summary_tool.dart';
import 'investment/ai_tools/breakdown_tools.dart';
import 'investment/ai_tools/get_asset_allocation_tool.dart';
import 'investment/ai_tools/get_holdings_tool.dart';
import 'investment/ai_tools/get_investment_performance_tool.dart';
import 'investment/ai_tools/propose_asset_valuation_tool.dart';
import 'investment/ai_tools/propose_trade_tool.dart';
import 'investment/ai_tools/read_asset_window_tool.dart';
import 'liabilities/ai_tools/propose_liability_payment_tool.dart';
import 'options_income/ai_tools/get_options_income_opportunities_tool.dart';
import 'options_income/ai_tools/get_options_strategy_profile_tool.dart';
import 'options_income/ai_tools/get_wheel_lifecycle_tool.dart';
import 'options_income/ai_tools/propose_options_journal_entry_tool.dart';
import 'options_income/ai_tools/propose_options_profile_update_tool.dart';

/// All FinanceOS device tools.
const List<DeviceTool> kFinanceDeviceTools = <DeviceTool>[
  // Accounts
  ListPaymentAccountsTool(),
  ProposeAccountCreateTool(),
  ReadAccountWindowTool(),
  // Cashflow
  GetCashflowBucketsTool(),
  GetRefundLinksTool(),
  GetTransferLinksTool(),
  // Expense
  GetAnomalyFlagsTool(),
  GetRecurringPatternsTool(),
  GetSubscriptionChangesTool(),
  ProposeExpenseTool(),
  ReadCategoryWindowTool(),
  // FIRE OS Phase 5 tools.
  GetFireStateTool(),
  GetFirePlanTool(),
  GetFireBucketsTool(),
  GetFireStressTestsTool(),
  GetFireReviewTool(),
  SimulateFirePlanTool(),
  ProposeFirePlanUpdateTool(),
  ProposeFireBucketRuleTool(),
  // Home / net worth
  GetNetWorthSummaryTool(),
  // Investment
  GetHoldingsTool(),
  GetAssetAllocationTool(),
  GetInvestmentPerformanceTool(),
  GetIndustryBreakdownTool(),
  GetGeoBreakdownTool(),
  GetMarketCapBreakdownTool(),
  ProposeAssetValuationTool(),
  ProposeTradeTool(),
  ReadAssetWindowTool(),
  // Liabilities
  ProposeLiabilityPaymentTool(),
  // Options Income (`docs/options-income.md` §8 + Wheel lifecycle).
  GetOptionsIncomeOpportunitiesTool(),
  GetOptionsStrategyProfileTool(),
  ProposeOptionsProfileUpdateTool(),
  ProposeOptionsJournalEntryTool(),
  GetWheelLifecycleTool(),
];

/// FinanceOS device-tool descriptors. Co-located with the tool list
/// above — adding a Finance tool means one new file under
/// `features/<feature>/ai_tools/`, one new line in
/// [kFinanceDeviceTools], and one new entry here. Merged into
/// [allToolDescriptors] by the cross-domain catalog.
const kFinanceToolDescriptors = <String, ToolDescriptor>{
  // Accounts
  'list_payment_accounts': ToolDescriptor(
    name: 'list_payment_accounts',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'propose_account_create': ToolDescriptor(
    name: 'propose_account_create',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'read_account_window': ToolDescriptor(
    name: 'read_account_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  // Cashflow
  'get_cashflow_buckets': ToolDescriptor(
    name: 'get_cashflow_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_refund_links': ToolDescriptor(
    name: 'get_refund_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_transfer_links': ToolDescriptor(
    name: 'get_transfer_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  // Expense
  'get_anomaly_flags': ToolDescriptor(
    name: 'get_anomaly_flags',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_recurring_patterns': ToolDescriptor(
    name: 'get_recurring_patterns',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_subscription_changes': ToolDescriptor(
    name: 'get_subscription_changes',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'propose_expense': ToolDescriptor(
    name: 'propose_expense',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.small,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'read_category_window': ToolDescriptor(
    name: 'read_category_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  // FIRE OS Phase 5 — `docs/roadmap-fire-os.md` §5.
  'get_fire_state': ToolDescriptor(
    name: 'get_fire_state',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_fire_plan': ToolDescriptor(
    name: 'get_fire_plan',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_fire_buckets': ToolDescriptor(
    name: 'get_fire_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_fire_stress_tests': ToolDescriptor(
    name: 'get_fire_stress_tests',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_fire_review': ToolDescriptor(
    name: 'get_fire_review',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'simulate_fire_plan': ToolDescriptor(
    name: 'simulate_fire_plan',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'propose_fire_plan_update': ToolDescriptor(
    name: 'propose_fire_plan_update',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'propose_fire_bucket_rule': ToolDescriptor(
    name: 'propose_fire_bucket_rule',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  // Home / net worth
  'get_net_worth_summary': ToolDescriptor(
    name: 'get_net_worth_summary',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  // Investment
  'get_holdings': ToolDescriptor(
    name: 'get_holdings',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_asset_allocation': ToolDescriptor(
    name: 'get_asset_allocation',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_investment_performance': ToolDescriptor(
    name: 'get_investment_performance',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'get_industry_breakdown': ToolDescriptor(
    name: 'get_industry_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_geo_breakdown': ToolDescriptor(
    name: 'get_geo_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_market_cap_breakdown': ToolDescriptor(
    name: 'get_market_cap_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'propose_asset_valuation': ToolDescriptor(
    name: 'propose_asset_valuation',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'propose_trade': ToolDescriptor(
    name: 'propose_trade',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'read_asset_window': ToolDescriptor(
    name: 'read_asset_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  // Liabilities
  'propose_liability_payment': ToolDescriptor(
    name: 'propose_liability_payment',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  // Options Income — `docs/options-income.md` §8.2 + Wheel lifecycle.
  'get_options_income_opportunities': ToolDescriptor(
    name: 'get_options_income_opportunities',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
  'get_options_strategy_profile': ToolDescriptor(
    name: 'get_options_strategy_profile',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainFinance,
  ),
  'propose_options_profile_update': ToolDescriptor(
    name: 'propose_options_profile_update',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'propose_options_journal_entry': ToolDescriptor(
    name: 'propose_options_journal_entry',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainFinance,
  ),
  'get_wheel_lifecycle': ToolDescriptor(
    name: 'get_wheel_lifecycle',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainFinance,
  ),
};

/// FinanceOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` when FinanceOS is active (always on
/// today). Keeps domain-specific tool guidance out of the shell prompt.
const String kFinanceSystemPromptBlock =
    '[FinanceOS 域]\n'
    '- 录入财务数据时调用 propose_* 工具，工具返回「待确认计划」，由前端确认页落库：\n'
    '  • propose_trade（证券、加密买卖 / 转入转出）\n'
    '  • propose_expense（日常消费 / 支出）\n'
    '  • propose_liability_payment（房贷 / 信用卡 / 消费贷还款）\n'
    '  • propose_account_create（新建账户）\n'
    '  • propose_asset_valuation（房产 / 车 / 存款等手工估值资产更新）\n'
    '  • propose_fire_plan_update / propose_fire_bucket_rule（FIRE 计划与桶规则调整）\n'
    '  • propose_options_journal_entry / propose_options_profile_update（期权 wheel 流水与策略画像）\n'
    '- 记录支出时，若用户没有指定支付账户，先调用 list_payment_accounts 看候选；只有工具返回空时才提示「没有可用支付账户，是否新建」。\n'
    '- 期权 / 投资类问题优先用 get_holdings / get_asset_allocation / get_investment_performance，不要凭印象推断仓位与收益。';
