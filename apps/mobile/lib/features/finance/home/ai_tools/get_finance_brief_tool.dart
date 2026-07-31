import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/application/planning_hub_status.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_inbox_providers.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';

/// Deterministic high-frequency brief over the same signals as Today + Plan.
class GetFinanceBriefTool implements DeviceTool {
  const GetFinanceBriefTool();

  @override
  String get name => 'get_finance_brief';

  @override
  String get description =>
      '读取当前资金续航、预算、再平衡、定投、待复核事项、Wheel 持仓和财务收件箱，'
      '用于回答“我今天该关注什么”。';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final planning = ctx.ref.read(planningHubStatusProvider);
    try {
      final inbox = await ctx.ref.read(financialInboxProvider.future);
      return buildFinanceBriefPayload(planning: planning, inbox: inbox);
    } on Object catch (error) {
      return buildFinanceBriefPayload(
        planning: planning,
        inbox: const [],
        inboxError: error.toString(),
      );
    }
  }
}

Map<String, Object?> buildFinanceBriefPayload({
  required PlanningHubStatus planning,
  required List<FinancialInboxItem> inbox,
  String? inboxError,
}) {
  final important = inbox
      .where((item) => item.priority == FinancialInboxPriority.important)
      .fold<int>(0, (sum, item) => sum + item.count);
  final attention = inbox
      .where((item) => item.priority == FinancialInboxPriority.attention)
      .fold<int>(0, (sum, item) => sum + item.count);
  final kindCounts = <String, int>{};
  for (final item in inbox) {
    kindCounts.update(
      item.kind.name,
      (count) => count + item.count,
      ifAbsent: () => item.count,
    );
  }
  final partial = planning.isLoading || planning.hasError || inboxError != null;
  return <String, Object?>{
    'status': partial ? 'partial' : 'complete',
    'planning_loading': planning.isLoading,
    'planning_error': planning.hasError,
    'inbox_error': ?inboxError,
    'runway': planning.runway?.name,
    'budget': <String, Object?>{
      'count': planning.budgetCount,
      'signal': planning.budgetSignal?.name,
      'progress': planning.budgetProgress,
    },
    'rebalance': <String, Object?>{
      'status': planning.rebalance?.name,
      'drift_pct': planning.rebalanceDriftPct,
    },
    'dca': <String, Object?>{
      'plan_count': planning.dcaPlanCount,
      'due': planning.dcaDue,
      'next_due_at': planning.dcaNextDueAt?.toUtc().toIso8601String(),
    },
    'pending_life_event_reviews': planning.pendingLifeEventReviews,
    'wheel': <String, Object?>{
      'cycle_count': planning.wheelCycleCount,
      'open_position_count': planning.wheelOpenPositionCount,
    },
    'inbox': <String, Object?>{
      'item_count': inbox.length,
      'important_count': important,
      'attention_count': attention,
      'kinds': kindCounts,
    },
  };
}
