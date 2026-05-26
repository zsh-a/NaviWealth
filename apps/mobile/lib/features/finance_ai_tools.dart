/// FinanceOS device-tool aggregator (`docs/lifeos-shell.md` §7.1, D-1.2).
///
/// Each Finance feature owns its `ai_tools/` subdir; this barrel
/// collects them so `bootstrap.dart` can register the full list with
/// the cross-domain `deviceToolsProvider`. HealthOS D-2 will land an
/// analogous `health_ai_tools.dart` alongside.
library;

import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart'
    show DeviceToolRegistry, kShellDeviceToolsCore;
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

/// Shell-only tools — re-exported here so `bootstrap.dart` has a
/// single import surface.
const List<DeviceTool> kShellDeviceTools = kShellDeviceToolsCore;

/// Back-compat surface for tests that pre-date D-1.2's composition
/// root. Production code reads `deviceToolsProvider` instead so each
/// domain's contribution is observable; this list is the same union
/// `bootstrap.dart` builds.
const List<DeviceTool> kDeviceTools = <DeviceTool>[
  ...kShellDeviceToolsCore,
  ...kFinanceDeviceTools,
];

/// Back-compat factory matching the pre-D-1.2 surface.
DeviceToolRegistry defaultDeviceToolRegistry() =>
    DeviceToolRegistry(kDeviceTools);
