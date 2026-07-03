import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';

/// `propose_fire_plan_update` — propose changes to the FIRE plan.
///
/// Returns a `ProposalEnvelope`-shaped JSON the front-end's
/// confirm-and-apply pipeline consumes. Never mutates state directly —
/// the user must tap confirm. The applier writes through
/// [saveFirePlanWithRef]; that path validates and persists atomically.
class ProposeFirePlanUpdateTool implements DeviceTool {
  const ProposeFirePlanUpdateTool();

  @override
  String get name => 'propose_fire_plan_update';

  @override
  String get description =>
      '提议更新 FIRE 计划中的一项或多项字段。'
      '可改字段:target_net_worth / monthly_expenses / monthly_surplus / inflation_rate / '
      'safe_withdrawal_rate / target_cash_bucket_months / lifestyle_mode。'
      '本工具不会立即写入,而是返回 plan,前端会展示 diff 并请用户确认。'
      '请在 summary_zh 中只描述准备修改的字段,不要顺手做出未确认的其他承诺。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'target_net_worth': <String, Object?>{'type': 'number', 'minimum': 0},
      'monthly_expenses': <String, Object?>{'type': 'number', 'minimum': 0},
      'monthly_surplus': <String, Object?>{'type': 'number'},
      'inflation_rate': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 0.20,
      },
      'safe_withdrawal_rate': <String, Object?>{
        'type': 'number',
        'minimum': 0.005,
        'maximum': 0.10,
      },
      'target_cash_bucket_months': <String, Object?>{
        'type': 'integer',
        'minimum': 0,
        'maximum': 60,
      },
      'lifestyle_mode': <String, Object?>{
        'type': 'string',
        'enum': <String>['lean', 'standard', 'fat', 'coast', 'barista'],
      },
      'note': <String, Object?>{'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final updates = <String, Object?>{};
    const knownFields = <String>{
      'target_net_worth',
      'monthly_expenses',
      'monthly_surplus',
      'inflation_rate',
      'safe_withdrawal_rate',
      'target_cash_bucket_months',
      'lifestyle_mode',
    };
    for (final field in knownFields) {
      if (input.containsKey(field) && input[field] != null) {
        updates[field] = input[field];
      }
    }
    if (updates.isEmpty) {
      return proposalBadRequest(
        'propose_fire_plan_update: at least one field must be supplied',
      );
    }

    final currentPlan = ctx.ref.read(firePlanProvider);
    final before = <String, Object?>{
      'target_net_worth': currentPlan.targetNetWorth.toString(),
      'monthly_expenses': currentPlan.monthlyExpenses.toString(),
      'monthly_surplus': currentPlan.monthlySurplus.toString(),
      'inflation_rate': currentPlan.inflationRate,
      'safe_withdrawal_rate': currentPlan.safeWithdrawalRate,
      'target_cash_bucket_months': currentPlan.targetCashBucketMonths,
      'lifestyle_mode': currentPlan.lifestyleMode.name,
    };

    final summary = _summary(updates);
    return readyPlan(
      kind: 'fire_plan_update',
      summaryZh: summary,
      payload: <String, Object?>{
        'before': before,
        'after': updates,
        if (input['note'] != null) 'note': input['note'],
      },
    );
  }
}

String _summary(Map<String, Object?> updates) {
  final parts = <String>[];
  if (updates.containsKey('target_net_worth')) {
    parts.add('目标净值 → ${updates['target_net_worth']}');
  }
  if (updates.containsKey('monthly_expenses')) {
    parts.add('月度支出 → ${updates['monthly_expenses']}');
  }
  if (updates.containsKey('monthly_surplus')) {
    parts.add('月度结余 → ${updates['monthly_surplus']}');
  }
  if (updates.containsKey('inflation_rate')) {
    parts.add('通胀率 → ${updates['inflation_rate']}');
  }
  if (updates.containsKey('safe_withdrawal_rate')) {
    parts.add('安全提取率 → ${updates['safe_withdrawal_rate']}');
  }
  if (updates.containsKey('target_cash_bucket_months')) {
    parts.add('现金桶目标 → ${updates['target_cash_bucket_months']} 个月');
  }
  if (updates.containsKey('lifestyle_mode')) {
    parts.add('生活方式 → ${updates['lifestyle_mode']}');
  }
  return '更新 FIRE 计划:${parts.join('、')}';
}
