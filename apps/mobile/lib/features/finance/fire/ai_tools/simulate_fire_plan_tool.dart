import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state_service.dart';

/// `simulate_fire_plan` — run a hypothetical FIRE state with the given
/// overrides, *without* persisting any change. Useful for "what if I
/// spend 20% more / save 30% more / cut expenses in half" style
/// follow-ups. Returns the same shape as `get_fire_state`.
class SimulateFirePlanTool implements DeviceTool {
  const SimulateFirePlanTool();

  @override
  String get name => 'simulate_fire_plan';

  @override
  String get description =>
      '在不写入任何更改的前提下,模拟一组 FIRE 计划假设的结果(返回与 get_fire_state 完全相同的 JSON 形状)。'
      '可选输入(任意组合):monthly_expenses / monthly_surplus / safe_withdrawal_rate / target_cash_bucket_months / '
      'investable_assets / liquid_assets / annual_spend。所有未指定的项目沿用当前真实值。'
      '请明确告知用户这是模拟结果,本工具不会修改实际计划;真要落地请用 propose_fire_plan_update。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'monthly_expenses': <String, Object?>{'type': 'number', 'minimum': 0},
      'monthly_surplus': <String, Object?>{'type': 'number'},
      'safe_withdrawal_rate': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 0.20,
      },
      'target_cash_bucket_months': <String, Object?>{
        'type': 'integer',
        'minimum': 0,
        'maximum': 60,
      },
      'target_net_worth': <String, Object?>{'type': 'number', 'minimum': 0},
      'investable_assets': <String, Object?>{'type': 'number'},
      'liquid_assets': <String, Object?>{'type': 'number'},
      'annual_spend': <String, Object?>{'type': 'number'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final stateAsync = ctx.ref.read(fireStateProvider);
    final base = stateAsync.whenOrNull(data: (s) => s);
    if (base == null) {
      return <String, Object?>{
        'error': 'base_state_unavailable',
        'code': 'unavailable',
      };
    }

    Decimal? dec(String key) {
      final raw = input[key];
      if (raw is num) return DecimalX.fromDouble(raw.toDouble());
      return null;
    }

    final plan = base.plan.copyWith(
      monthlyExpenses: dec('monthly_expenses') ?? base.plan.monthlyExpenses,
      monthlySurplus: dec('monthly_surplus') ?? base.plan.monthlySurplus,
      safeWithdrawalRate:
          (input['safe_withdrawal_rate'] is num
              ? (input['safe_withdrawal_rate'] as num).toDouble()
              : null) ??
          base.plan.safeWithdrawalRate,
      targetCashBucketMonths:
          (input['target_cash_bucket_months'] is num
              ? (input['target_cash_bucket_months'] as num).toInt()
              : null) ??
          base.plan.targetCashBucketMonths,
      targetNetWorth: dec('target_net_worth') ?? base.plan.targetNetWorth,
    );

    final investable = Money(
      dec('investable_assets') ?? base.investableAssets.amount,
      base.baseCurrency,
    );
    final liquid = Money(
      dec('liquid_assets') ?? base.liquidAssets.amount,
      base.baseCurrency,
    );
    final annualSpend = dec('annual_spend');
    final trailing = annualSpend != null
        ? Money(annualSpend, base.baseCurrency)
        : (base.annualSpendSource == FireAnnualSpendSource.trailing12m
              ? base.annualSpend
              : null);

    final netWorth = Money(
      investable.amount + (base.netWorth.amount - base.investableAssets.amount),
      base.baseCurrency,
    );

    final simulated = computeFireState(
      plan: plan,
      netWorth: netWorth,
      investableAssets: investable,
      liquidAssets: liquid,
      trailingAnnualSpend: trailing,
      fireEtaMonths: null,
      currencyMismatchCount: base.currencyMismatchCount,
      computedAt: base.computedAt,
    );
    return <String, Object?>{
      'simulation': simulated.toJson(),
      'note': 'Simulation only — no plan changes were persisted. Use propose_fire_plan_update to apply.',
    };
  }
}
