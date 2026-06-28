/// FinanceOS device-tool aggregator (`docs/architecture/lifeos-shell.md` §7.1, D-1.2).
///
/// Each Finance feature owns its `ai_tools/` subdir; this barrel
/// collects them so `domain_packs.dart` can register the full list with
/// the cross-domain `deviceToolsProvider`.
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainFinance;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/registered_device_tool.dart';
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

/// FinanceOS device tools and policy metadata. Adding a Finance tool means
/// adding one registration here; the runtime tool list and descriptor map
/// are derived below.
const DeviceToolRegistrationBuilder _financeTool =
    DeviceToolRegistrationBuilder(kDomainFinance);

final List<RegisteredDeviceTool>
kFinanceToolRegistrations = <RegisteredDeviceTool>[
  // Accounts
  _financeTool.read(const ListPaymentAccountsTool(), tier: BudgetTier.standard),
  _financeTool.propose(
    const ProposeAccountCreateTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.read(const ReadAccountWindowTool(), tier: BudgetTier.standard),
  // Cashflow
  _financeTool.read(const GetCashflowBucketsTool()),
  _financeTool.read(const GetRefundLinksTool()),
  _financeTool.read(const GetTransferLinksTool()),
  // Expense
  _financeTool.read(const GetAnomalyFlagsTool(), risk: RiskLevel.suggest),
  _financeTool.read(const GetRecurringPatternsTool()),
  _financeTool.read(
    const GetSubscriptionChangesTool(),
    risk: RiskLevel.suggest,
  ),
  _financeTool.propose(const ProposeExpenseTool()),
  _financeTool.read(const ReadCategoryWindowTool(), tier: BudgetTier.standard),
  // FIRE OS Phase 5 tools.
  _financeTool.read(const GetFireStateTool(), tier: BudgetTier.standard),
  _financeTool.read(const GetFirePlanTool()),
  _financeTool.read(const GetFireBucketsTool(), tier: BudgetTier.standard),
  _financeTool.read(
    const GetFireStressTestsTool(),
    risk: RiskLevel.suggest,
    tier: BudgetTier.standard,
  ),
  _financeTool.read(
    const GetFireReviewTool(),
    risk: RiskLevel.suggest,
    tier: BudgetTier.standard,
  ),
  _financeTool.read(
    const SimulateFirePlanTool(),
    risk: RiskLevel.suggest,
    tier: BudgetTier.standard,
  ),
  _financeTool.propose(
    const ProposeFirePlanUpdateTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.propose(
    const ProposeFireBucketRuleTool(),
    tier: BudgetTier.standard,
  ),
  // Home / net worth
  _financeTool.read(const GetNetWorthSummaryTool()),
  // Investment
  _financeTool.read(const GetHoldingsTool()),
  _financeTool.read(const GetAssetAllocationTool()),
  _financeTool.read(const GetInvestmentPerformanceTool()),
  _financeTool.read(
    const GetIndustryBreakdownTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.read(const GetGeoBreakdownTool(), tier: BudgetTier.standard),
  _financeTool.read(
    const GetMarketCapBreakdownTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.propose(
    const ProposeAssetValuationTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.propose(const ProposeTradeTool(), tier: BudgetTier.standard),
  _financeTool.read(const ReadAssetWindowTool(), tier: BudgetTier.standard),
  // Liabilities
  _financeTool.propose(
    const ProposeLiabilityPaymentTool(),
    tier: BudgetTier.standard,
  ),
  // Options Income (`docs/domains/options-income.md` §8 + Wheel lifecycle).
  _financeTool.read(
    const GetOptionsIncomeOpportunitiesTool(),
    risk: RiskLevel.suggest,
    tier: BudgetTier.standard,
  ),
  _financeTool.read(const GetOptionsStrategyProfileTool()),
  _financeTool.propose(
    const ProposeOptionsProfileUpdateTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.propose(
    const ProposeOptionsJournalEntryTool(),
    tier: BudgetTier.standard,
  ),
  _financeTool.read(const GetWheelLifecycleTool(), tier: BudgetTier.standard),
];

final List<DeviceTool> kFinanceDeviceTools = registeredDeviceTools(
  kFinanceToolRegistrations,
);

final Map<String, ToolDescriptor> kFinanceToolDescriptors =
    registeredToolDescriptors(kFinanceToolRegistrations);

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
