import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

/// The five buckets every FIRE plan is sliced into. They are an
/// *interpretation* layer over accounts and assets — not a new account
/// schema. A holding can belong to exactly one bucket at a time; mappings
/// live in [FireBucketRule] (see `fire_bucket_allocator.dart`).
enum FireBucketRole {
  /// Cash, demand deposits — money you can spend this week without
  /// touching the portfolio.
  cash,

  /// Short-duration fixed income, money-market funds, ultra-short bond
  /// ETFs — capital preservation with mild yield.
  defensive,

  /// Equities and equity-flavoured holdings — the engine that drags the
  /// plan toward FIRE on a long horizon.
  growth,

  /// Earmarked one-off reserves: medical buffer, family-support pile,
  /// long-tail risk. Bigger than emergency cash, smaller than the growth
  /// bucket.
  riskReserve,

  /// Dream / discretionary — a future trip, a major purchase. Carved out
  /// so the rest of the plan doesn't drift sideways covering it.
  dream,
}

/// What is the bucket currently doing relative to its target?
enum FireBucketStatus {
  /// Healthy — within ±10% of target (or no target).
  onTrack,

  /// Below 90% of target — the user should consider a top-up.
  underTarget,

  /// Over 110% of target — capital is "trapped" here and could fund
  /// better-yielding sleeves. Surfaced as info, not a warning.
  overTarget,

  /// No assets mapped to this bucket yet — onboarding signal.
  empty,
}

/// One mapping: "this account / asset funds this bucket, optionally at
/// this allocation percentage". Persisted in local prefs in Phase 2; a
/// candidate Drift table when sync lands (roadmap §7.2).
@immutable
class FireBucketRule {
  const FireBucketRule({
    required this.id,
    required this.role,
    required this.targetTable,
    required this.targetId,
    this.allocationPct,
    this.note,
  });

  final String id;
  final FireBucketRole role;

  /// `'accounts'` or `'assets'` — which Drift table [targetId] points at.
  final String targetTable;

  /// Stable id of the account / asset row.
  final String targetId;

  /// `0.0–1.0`; when `null` the rule means "100% of this target counts".
  final double? allocationPct;

  /// Optional user-supplied note ("emergency fund", "kids' education").
  final String? note;

  FireBucketRule copyWith({
    FireBucketRole? role,
    String? targetTable,
    String? targetId,
    double? allocationPct,
    String? note,
  }) {
    return FireBucketRule(
      id: id,
      role: role ?? this.role,
      targetTable: targetTable ?? this.targetTable,
      targetId: targetId ?? this.targetId,
      allocationPct: allocationPct ?? this.allocationPct,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'role': role.name,
    'target_table': targetTable,
    'target_id': targetId,
    if (allocationPct != null) 'allocation_pct': allocationPct,
    if (note != null) 'note': note,
  };

  factory FireBucketRule.fromJson(Map<String, Object?> json) {
    return FireBucketRule(
      id: (json['id'] as String?) ?? '',
      role: FireBucketRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => FireBucketRole.cash,
      ),
      targetTable: (json['target_table'] as String?) ?? 'accounts',
      targetId: (json['target_id'] as String?) ?? '',
      allocationPct: (json['allocation_pct'] as num?)?.toDouble(),
      note: json['note'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FireBucketRule &&
      other.id == id &&
      other.role == role &&
      other.targetTable == targetTable &&
      other.targetId == targetId &&
      other.allocationPct == allocationPct &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(id, role, targetTable, targetId, allocationPct, note);
}

/// Computed value of a single bucket at a point in time. Produced by the
/// allocator (Phase 2) and surfaced by [FireState.buckets].
@immutable
class FireBucketState {
  const FireBucketState({
    required this.role,
    required this.currentValue,
    required this.targetValue,
    required this.status,
    required this.coverageRatio,
    this.assetIds = const <String>[],
    this.note,
  });

  final FireBucketRole role;

  /// Sum of mapped holdings / accounts in base currency.
  final Money currentValue;

  /// Target value for the bucket — for `cash` this is
  /// `monthlyExpense × targetCashBucketMonths`; for others it is the
  /// planner's intent or `Money.zero` (no formal target yet).
  final Money targetValue;

  /// `currentValue / targetValue` as a double; clamped to `[0, 5]` to
  /// avoid divide-by-zero blowups. `null` when target is zero (no formal
  /// target) so the UI can render the "no target" affordance.
  final double? coverageRatio;

  final FireBucketStatus status;

  /// Ids of the assets / accounts that contributed to [currentValue].
  /// Used by the AI inspector and the bucket-detail UI.
  final List<String> assetIds;

  /// Optional human note (e.g. "no rules yet — using defaults").
  final String? note;

  /// Money "still to add" to hit the target. Zero when at or above target.
  Money get shortfall {
    final diff = targetValue.amount - currentValue.amount;
    return diff > Decimal.zero
        ? Money(diff, targetValue.currency)
        : Money.zero(targetValue.currency);
  }

  @override
  bool operator ==(Object other) =>
      other is FireBucketState &&
      other.role == role &&
      other.currentValue == currentValue &&
      other.targetValue == targetValue &&
      other.coverageRatio == coverageRatio &&
      other.status == status &&
      listEquals(other.assetIds, assetIds) &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    role,
    currentValue,
    targetValue,
    coverageRatio,
    status,
    Object.hashAll(assetIds),
    note,
  );
}
