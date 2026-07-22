import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';

/// FIRE proposal writer owned by the FIRE slice.
class FireProposalApplier {
  const FireProposalApplier({
    required this.planWriter,
    required this.planReader,
  });

  final Future<void> Function(Map<String, Object?> after) planWriter;
  final FirePlan Function() planReader;

  Future<ProposalApplyState> applyPlanUpdate(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final after = plan.payload['after'];
    if (after is! Map) {
      throw ProposalApplyException(
        'fire_plan_update payload missing `after` field',
      );
    }
    final before = _firePlanPayload(planReader());
    await planWriter(Map<String, Object?>.from(after));
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'default',
      appliedTable: 'fire_plans',
      appliedAt: at,
      undoData: <String, Object?>{'before': before},
      shortLabel: 'Updated ${plan.summaryZh}',
    );
  }

  Future<void> undoPlanUpdate(ProposalApplyState state) async {
    final before = state.undoData?['before'];
    if (before is! Map) {
      throw ProposalApplyException('FIRE plan undo snapshot is missing');
    }
    await planWriter(Map<String, Object?>.from(before));
  }
}

final fireProposalApplierProvider = Provider<FireProposalApplier>((ref) {
  return FireProposalApplier(
    planWriter: (after) => _applyFirePlanUpdateProposal(ref: ref, after: after),
    planReader: () => ref.read(firePlanProvider),
  );
});

Map<String, Object?> _firePlanPayload(FirePlan plan) => <String, Object?>{
  'target_net_worth': plan.targetNetWorth.toString(),
  'monthly_expenses': plan.monthlyExpenses.toString(),
  'monthly_surplus': plan.monthlySurplus.toString(),
  'inflation_rate': plan.inflationRate,
  'safe_withdrawal_rate': plan.safeWithdrawalRate,
  'target_cash_bucket_months': plan.targetCashBucketMonths,
  'lifestyle_mode': plan.lifestyleMode.name,
};

Future<void> _applyFirePlanUpdateProposal({
  required Ref ref,
  required Map<String, Object?> after,
}) async {
  final plan = ref.read(firePlanProvider);
  Decimal? d(String key) {
    final raw = after[key];
    if (raw is num) return DecimalX.fromDouble(raw.toDouble());
    if (raw is String) return Decimal.tryParse(raw);
    return null;
  }

  final updated = plan.copyWith(
    targetNetWorth: d('target_net_worth') ?? plan.targetNetWorth,
    monthlyExpenses: d('monthly_expenses') ?? plan.monthlyExpenses,
    monthlySurplus: d('monthly_surplus') ?? plan.monthlySurplus,
    inflationRate:
        (after['inflation_rate'] is num
            ? (after['inflation_rate'] as num).toDouble()
            : null) ??
        plan.inflationRate,
    safeWithdrawalRate:
        (after['safe_withdrawal_rate'] is num
            ? (after['safe_withdrawal_rate'] as num).toDouble()
            : null) ??
        plan.safeWithdrawalRate,
    targetCashBucketMonths:
        (after['target_cash_bucket_months'] is num
            ? (after['target_cash_bucket_months'] as num).toInt()
            : null) ??
        plan.targetCashBucketMonths,
    lifestyleMode:
        _parseLifestyle(after['lifestyle_mode']) ?? plan.lifestyleMode,
  );
  await saveFirePlanWithRef(ref, updated);
}

FireLifestyleMode? _parseLifestyle(Object? raw) {
  if (raw is! String) return null;
  for (final m in FireLifestyleMode.values) {
    if (m.name == raw) return m;
  }
  return null;
}
