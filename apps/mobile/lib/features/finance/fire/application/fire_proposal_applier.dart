import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/features/finance/fire/data/fire_bucket_rules_preferences.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_bucket.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';

/// FIRE proposal writer owned by the FIRE slice.
///
/// Finance proposal composition delegates confirmed FIRE plans here so the
/// FIRE storage and payload parsing rules stay with their owning subdomain.
class FireProposalApplier {
  const FireProposalApplier({
    required this.planWriter,
    required this.bucketRuleWriter,
  });

  final Future<void> Function(Map<String, Object?> after) planWriter;
  final Future<String> Function(Map<String, Object?> payload) bucketRuleWriter;

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
    await planWriter(Map<String, Object?>.from(after));
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'default',
      appliedTable: 'fire_plans',
      appliedAt: at,
      shortLabel: 'Updated ${plan.summaryZh}',
    );
  }

  Future<ProposalApplyState> applyBucketRule(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final payload = <String, Object?>{
      'role': plan.payload['role'],
      'target_table': plan.payload['target_table'],
      'target_id': plan.payload['target_id'],
      'allocation_pct': plan.payload['allocation_pct'],
      'note': plan.payload['note'],
    };
    final id = await bucketRuleWriter(payload);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: id,
      appliedTable: 'fire_bucket_rules',
      appliedAt: at,
      shortLabel: 'Bound ${plan.summaryZh}',
    );
  }
}

final fireProposalApplierProvider = Provider<FireProposalApplier>((ref) {
  return FireProposalApplier(
    planWriter: (after) => _applyFirePlanUpdateProposal(ref: ref, after: after),
    bucketRuleWriter: (payload) =>
        _applyFireBucketRuleProposal(ref: ref, payload: payload),
  );
});

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

Future<String> _applyFireBucketRuleProposal({
  required Ref ref,
  required Map<String, Object?> payload,
}) async {
  final roleRaw = payload['role'] as String? ?? '';
  final role = FireBucketRole.values.firstWhere(
    (r) => _wireForRole(r) == roleRaw,
    orElse: () => FireBucketRole.cash,
  );
  final targetId = payload['target_id'] as String? ?? '';
  if (targetId.isEmpty) {
    throw StateError('fire_bucket_rule payload missing target_id');
  }
  final pct = (payload['allocation_pct'] is num)
      ? (payload['allocation_pct'] as num).toDouble()
      : null;
  final note = payload['note'] as String?;
  final rule = FireBucketRule(
    id: targetId,
    role: role,
    targetTable: (payload['target_table'] as String?) ?? 'assets',
    targetId: targetId,
    allocationPct: pct,
    note: note,
  );
  await ref.read(fireBucketRulesProvider.notifier).upsert(rule);
  return targetId;
}

String _wireForRole(FireBucketRole role) {
  switch (role) {
    case FireBucketRole.cash:
      return 'cash';
    case FireBucketRole.defensive:
      return 'defensive';
    case FireBucketRole.growth:
      return 'growth';
    case FireBucketRole.riskReserve:
      return 'risk_reserve';
    case FireBucketRole.dream:
      return 'dream';
  }
}
