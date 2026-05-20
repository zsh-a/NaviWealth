import '../../../../../features/fire/data/fire_providers.dart';
import '../../../../../features/fire/domain/fire_plan.dart';
import 'device_tool.dart';

/// `get_fire_plan` — return the user-supplied FIRE plan inputs.
///
/// Read-only mirror of [FirePlan]. Used as a precursor to
/// `propose_fire_plan_update`: the AI inspects the current target /
/// SWR / cash-bucket months before suggesting an edit.
class GetFirePlanTool implements DeviceTool {
  const GetFirePlanTool();

  @override
  String get name => 'get_fire_plan';

  @override
  String get description =>
      '返回当前 FIRE 计划(目标净值 / 年度支出 / 月度结余 / SWR / 现金桶目标 / 生活方式 / 预留 / 风险参数)。'
      '`is_configured = false` 表示用户尚未填写计划——请先邀请用户配置,不要凭空建议数字。'
      '修改建议必须通过 `propose_fire_plan_update`,从不直接断言"我已修改"。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final plan = ctx.ref.read(firePlanProvider);
    return _toJson(plan);
  }
}

Map<String, Object?> _toJson(FirePlan plan) {
  return <String, Object?>{
    'id': plan.id,
    'base_currency': plan.baseCurrency,
    'is_configured': plan.isConfigured,
    'monthly_expenses': plan.monthlyExpenses.toString(),
    'monthly_surplus': plan.monthlySurplus.toString(),
    'annual_expense': plan.annualExpense.amount.toString(),
    'inflation_rate': plan.inflationRate,
    'target_net_worth': plan.targetNetWorth.toString(),
    'safe_withdrawal_rate': plan.safeWithdrawalRate,
    'target_cash_bucket_months': plan.targetCashBucketMonths,
    'lifestyle_mode': plan.lifestyleMode.name,
    'reserves': [
      for (final r in plan.reserves)
        <String, Object?>{
          'id': r.id,
          'label': r.label,
          'amount': r.amount.amount.toString(),
          'currency': r.amount.currency,
          'kind': r.kind.name,
        },
    ],
    'risk_settings': plan.riskSettings.toJson(),
  };
}
