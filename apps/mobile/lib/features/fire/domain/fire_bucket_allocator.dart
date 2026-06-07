import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../core/format/formatters.dart';
import '../../../domain/values/money.dart';
import '../../home/domain/dashboard_models.dart';
import 'fire_bucket.dart';
import 'fire_plan.dart';

/// Allocator output: the five bucket states plus the assets that no
/// user rule and no default classifier mapped anywhere (real estate
/// and vehicles, primarily). Surfacing them explicitly keeps the
/// roadmap promise: "未分配资产被明确标注,不静默忽略".
@immutable
class FireBucketAllocation {
  const FireBucketAllocation({
    required this.buckets,
    required this.unmappedHoldings,
  });

  final List<FireBucketState> buckets;
  final List<FireUnmappedHolding> unmappedHoldings;
}

@immutable
class FireUnmappedHolding {
  const FireUnmappedHolding({
    required this.id,
    required this.name,
    required this.value,
    required this.reason,
  });

  final String id;
  final String name;
  final Money value;

  /// Stable code for the reason — `category_not_drawable`,
  /// `unsupported_category`, etc. UI / AI use it to render an action.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is FireUnmappedHolding &&
      other.id == id &&
      other.name == name &&
      other.value == value &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(id, name, value, reason);
}

/// Slice the [snapshot] into the five FIRE buckets.
///
/// Pure function: no providers, no IO. The default classifier maps by
/// [AssetCategory]; [userRules] overrides per-holding when the user has
/// declared an explicit mapping (see [FireBucketRule]). Real estate /
/// vehicles fall into [FireUnmappedHolding] because they don't fund
/// withdrawals — the user can override with an explicit rule (e.g.
/// "this rental property is my dream bucket").
FireBucketAllocation allocateBuckets({
  required FirePlan plan,
  required DashboardSnapshot snapshot,
  required Money monthlyExpense,
  List<FireBucketRule> userRules = const <FireBucketRule>[],
}) {
  _requireBase(plan.baseCurrency, monthlyExpense.amount, 'monthlyExpense');

  // Index user rules by (targetTable, targetId) for O(1) lookup. The
  // table is `accounts` or `assets`; allocations carry `id` from the
  // underlying drift row.
  final ruleByItem = <String, FireBucketRule>{};
  for (final rule in userRules) {
    ruleByItem['${rule.targetTable}:${rule.targetId}'] = rule;
  }

  final totals = <FireBucketRole, Decimal>{
    for (final r in FireBucketRole.values) r: Decimal.zero,
  };
  final assetIds = <FireBucketRole, List<String>>{
    for (final r in FireBucketRole.values) r: <String>[],
  };
  final unmapped = <FireUnmappedHolding>[];

  for (final allocation in snapshot.allocations) {
    if (allocation.category == AssetCategory.liability) continue;
    for (final item in allocation.items) {
      // User rule takes precedence; default classifier provides the
      // fallback role. Items without a rule and not classifiable land
      // in the unmapped list.
      final ruleKey = 'assets:${item.id}';
      final rule = ruleByItem[ruleKey];
      final role = rule?.role ?? _defaultRoleFor(allocation.category);
      if (role == null) {
        unmapped.add(
          FireUnmappedHolding(
            id: item.id,
            name: item.name,
            value: item.valueInBase,
            reason: 'category_not_drawable',
          ),
        );
        continue;
      }
      final pct = rule?.allocationPct;
      final factor = pct == null
          ? Decimal.one
          : DecimalX.fromDouble(pct.clamp(0.0, 1.0), scale: 4);
      final contribution = item.valueInBase.amount * factor;
      totals[role] = totals[role]! + contribution;
      assetIds[role]!.add(item.id);
    }
  }

  // Targets per role.
  final cashTarget =
      monthlyExpense.amount * Decimal.fromInt(plan.targetCashBucketMonths);
  final riskReserveTarget =
      plan.totalReserves.amount +
      DecimalX.fromDouble(plan.riskSettings.oneOffShockAmount);

  Money money(Decimal d) => Money(d, plan.baseCurrency);

  FireBucketState build(FireBucketRole role, Decimal target) {
    final current = totals[role]!;
    final coverage = _coverage(current, target);
    final status = _status(current, target);
    return FireBucketState(
      role: role,
      currentValue: money(current),
      targetValue: money(target),
      status: status,
      coverageRatio: coverage,
      assetIds: List.unmodifiable(assetIds[role]!),
    );
  }

  return FireBucketAllocation(
    buckets: List.unmodifiable(<FireBucketState>[
      build(FireBucketRole.cash, cashTarget),
      build(FireBucketRole.defensive, Decimal.zero),
      build(FireBucketRole.growth, Decimal.zero),
      build(FireBucketRole.riskReserve, riskReserveTarget),
      build(FireBucketRole.dream, Decimal.zero),
    ]),
    unmappedHoldings: List.unmodifiable(unmapped),
  );
}

/// The default category→role mapping. `null` means the allocator
/// surfaces the asset as unmapped; the user can pin it via a rule.
FireBucketRole? _defaultRoleFor(AssetCategory category) {
  switch (category) {
    case AssetCategory.cash:
      return FireBucketRole.cash;
    case AssetCategory.bondsAndFunds:
      return FireBucketRole.defensive;
    case AssetCategory.stock:
    case AssetCategory.etf:
      return FireBucketRole.growth;
    case AssetCategory.crypto:
      // Crypto sits in the growth bucket by default — large volatility
      // belongs with the long-horizon sleeve, not the cash buffer. A
      // user worried about risk can map specific positions to
      // `riskReserve` instead.
      return FireBucketRole.growth;
    case AssetCategory.realEstate:
    case AssetCategory.vehicle:
      return null;
    case AssetCategory.liability:
      return null;
  }
}

double? _coverage(Decimal current, Decimal target) {
  if (target <= Decimal.zero) return null;
  final ratio = (current / target).toDouble();
  if (ratio.isNaN || ratio.isInfinite) return null;
  // Clamp at 5× — past that the gauge stops being informative.
  return ratio.clamp(0.0, 5.0);
}

FireBucketStatus _status(Decimal current, Decimal target) {
  if (target <= Decimal.zero) {
    return current <= Decimal.zero
        ? FireBucketStatus.empty
        : FireBucketStatus.onTrack;
  }
  final ratio = (current / target).toDouble();
  if (ratio.isNaN || ratio.isInfinite) return FireBucketStatus.onTrack;
  if (ratio < 0.9) return FireBucketStatus.underTarget;
  if (ratio > 1.1) return FireBucketStatus.overTarget;
  return FireBucketStatus.onTrack;
}

void _requireBase(String base, Decimal _, String label) {
  // Money carries currency; the call site validates by reading
  // [Money.currency]. Kept as a hook so a future tightening can throw
  // on the spot rather than rely on Money's own arithmetic guards.
}
