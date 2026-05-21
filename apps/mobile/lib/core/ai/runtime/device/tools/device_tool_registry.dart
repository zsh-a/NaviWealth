/// Device tool registry + Drift-backed dispatcher (§4.6 W-D4).
///
/// The canonical id→tool map, a `schemas()` feed for the agent loop,
/// a per-tool timeout, and stable error envelopes (`policy_denied` /
/// `tool_timeout`) consumed by the model.
///
/// **Allow-list decision** (see §11): registry *membership* is the
/// device allow-list. `ToolDescriptor` is metadata for registered
/// tools; dispatch authority still comes from this list because a
/// missing implementation is the strongest possible deny.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contracts/tool_descriptor.dart';
import '../anthropic/anthropic_wire.dart';
import '../device_session.dart';
import '../device_tool_dispatcher.dart';
import 'breakdown_tools.dart';
import 'device_tool.dart';
import 'get_anomaly_flags_tool.dart';
import 'get_asset_allocation_tool.dart';
import 'get_cashflow_buckets_tool.dart';
import 'get_fire_buckets_tool.dart';
import 'get_fire_plan_tool.dart';
import 'get_fire_review_tool.dart';
import 'get_fire_state_tool.dart';
import 'get_fire_stress_tests_tool.dart';
import 'get_holdings_tool.dart';
import 'get_investment_performance_tool.dart';
import 'get_net_worth_summary_tool.dart';
import 'get_options_income_opportunities_tool.dart';
import 'get_options_strategy_profile_tool.dart';
import 'get_recurring_patterns_tool.dart';
import 'get_refund_links_tool.dart';
import 'get_subscription_changes_tool.dart';
import 'get_transfer_links_tool.dart';
import 'list_payment_accounts_tool.dart';
import 'propose_account_create_tool.dart';
import 'propose_asset_valuation_tool.dart';
import 'propose_expense_tool.dart';
import 'propose_fire_bucket_rule_tool.dart';
import 'propose_fire_plan_update_tool.dart';
import 'propose_liability_payment_tool.dart';
import 'propose_options_journal_entry_tool.dart';
import 'propose_options_profile_update_tool.dart';
import 'propose_trade_tool.dart';
import 'read_account_window_tool.dart';
import 'read_asset_window_tool.dart';
import 'read_category_window_tool.dart';
import 'simulate_fire_plan_tool.dart';

/// Mirrors backend `PER_TOOL_TIMEOUT_MS`.
const Duration kPerToolTimeout = Duration(seconds: 15);

/// Canonical device-dispatchable tool set. Registry membership *is* the
/// device allow-list (§11): a tool runs on device iff a Drift-backed
/// port is registered here. Single source for the provider and the
/// W-D6 static-contract test (every name must resolve in the shared
/// `tool_descriptor.dart` mirror).
const List<DeviceTool> kDeviceTools = <DeviceTool>[
  ListPaymentAccountsTool(),
  GetHoldingsTool(),
  GetAssetAllocationTool(),
  GetCashflowBucketsTool(),
  GetAnomalyFlagsTool(),
  GetRecurringPatternsTool(),
  GetRefundLinksTool(),
  GetTransferLinksTool(),
  GetInvestmentPerformanceTool(),
  GetNetWorthSummaryTool(),
  GetSubscriptionChangesTool(),
  ProposeExpenseTool(),
  ProposeAccountCreateTool(),
  ProposeAssetValuationTool(),
  ProposeLiabilityPaymentTool(),
  ProposeTradeTool(),
  ReadAccountWindowTool(),
  ReadAssetWindowTool(),
  ReadCategoryWindowTool(),
  GetIndustryBreakdownTool(),
  GetGeoBreakdownTool(),
  GetMarketCapBreakdownTool(),
  // FIRE OS Phase 5 tools — explain / simulate / confirm-to-apply.
  GetFireStateTool(),
  GetFirePlanTool(),
  GetFireBucketsTool(),
  GetFireStressTestsTool(),
  GetFireReviewTool(),
  SimulateFirePlanTool(),
  ProposeFirePlanUpdateTool(),
  ProposeFireBucketRuleTool(),
  // Income Planner (`docs/options-income.md` §8).
  GetOptionsIncomeOpportunitiesTool(),
  GetOptionsStrategyProfileTool(),
  ProposeOptionsProfileUpdateTool(),
  ProposeOptionsJournalEntryTool(),
];

DeviceToolRegistry defaultDeviceToolRegistry() =>
    DeviceToolRegistry(kDeviceTools);

class DeviceToolRegistry {
  DeviceToolRegistry(Iterable<DeviceTool> tools)
    : _tools = {for (final t in tools) t.name: t};

  final Map<String, DeviceTool> _tools;

  DeviceTool? lookup(String name) => _tools[name];

  Iterable<String> get names => _tools.keys;

  /// Tool schemas fed to [AnthropicRequest.tools]. Sorted by name for
  /// stable prompts / golden tests, like the backend `schemas()`.
  List<AnthropicToolSchema> schemas() {
    final out = [
      for (final t in _tools.values)
        AnthropicToolSchema(
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema,
        ),
    ];
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

/// [DeviceToolDispatcher] backed by the device registry + Riverpod.
class DriftDeviceToolDispatcher implements DeviceToolDispatcher {
  DriftDeviceToolDispatcher({
    required Ref ref,
    required DeviceToolRegistry registry,
    Duration perToolTimeout = kPerToolTimeout,
  }) : _ref = ref,
       _registry = registry,
       _timeout = perToolTimeout;

  final Ref _ref;
  final DeviceToolRegistry _registry;
  final Duration _timeout;

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    final tool = _registry.lookup(name);
    if (tool == null) {
      return _policyDenied(name, 'unknown_tool', '未注册的端侧工具：$name');
    }
    // §4.5 — external side effects are never auto-dispatched.
    if (lookupToolDescriptor(name)?.sideEffect == SideEffect.externalCall) {
      return _policyDenied(name, 'runtime_not_allowed', '该工具有外部副作用，端侧不自动执行。');
    }

    final args = input is Map
        ? input.map((k, v) => MapEntry(k.toString(), v))
        : <String, Object?>{};
    try {
      return await tool
          .invoke(DeviceToolContext(ref: _ref, session: session), args)
          .timeout(
            _timeout,
            onTimeout: () => <String, Object?>{
              'error':
                  "tool '$name' timed out after ${_timeout.inMilliseconds}ms",
              'code': 'tool_timeout',
              'tool': name,
            },
          );
    } catch (e) {
      return <String, Object?>{'error': '$e', 'code': 'tool_error'};
    }
  }

  /// Stable `policy_denied` envelope retained from the retired backend
  /// contract so older UI/debug expectations keep the same shape.
  Map<String, Object?> _policyDenied(
    String tool,
    String policy,
    String message,
  ) => <String, Object?>{
    'error': {
      'code': 'policy_denied',
      'policy': policy,
      'tool': tool,
      'message': message,
    },
    'policy_denied': true,
  };
}
