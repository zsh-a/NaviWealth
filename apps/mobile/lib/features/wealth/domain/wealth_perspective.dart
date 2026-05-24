import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/values/money.dart';
import '../../home/domain/dashboard_models.dart';

/// Dimensions the Wealth tab can group net-worth holdings under.
///
/// IA migration §A-2: revives the original P1-D "multi-perspective"
/// allocation breakdown on the Wealth tab. The third dimension —
/// **by account** — is handled by [AccountsGroupedSections] further
/// down the same page; surfacing it here would duplicate that view, so
/// this contract intentionally limits itself to the two perspectives
/// that aren't otherwise reachable inline.
enum WealthPerspective {
  /// Big-bucket asset categories (stocks / cash / crypto / …) — the
  /// existing pie chart dimension.
  byCategory,

  /// Native currency of each holding (USD / CNY / BTC / …).
  byCurrency,
}

/// One bar in the breakdown — a label, an amount in the base currency,
/// and the count of underlying items so the UI can show "5 holdings".
@immutable
class WealthBucket {
  const WealthBucket({
    required this.key,
    required this.label,
    required this.valueInBase,
    required this.itemCount,
  });

  /// Stable machine key (e.g. asset category name, currency code).
  final String key;

  /// Display label — usually the same as [key] for currency, the
  /// localized category name for category buckets (the localizer runs
  /// at the call site; this contract stays locale-agnostic).
  final String label;

  final Money valueInBase;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is WealthBucket &&
      other.key == key &&
      other.label == label &&
      other.valueInBase == valueInBase &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(key, label, valueInBase, itemCount);
}

/// Pure result of slicing a [DashboardSnapshot] along one perspective.
///
/// Buckets are returned in descending order by [WealthBucket.valueInBase]
/// so the UI can render the most concentrated bucket first without a
/// secondary sort pass.
@immutable
class WealthAggregation {
  const WealthAggregation({
    required this.perspective,
    required this.buckets,
    required this.total,
  });

  final WealthPerspective perspective;
  final List<WealthBucket> buckets;
  final Money total;
}

/// Build a [WealthAggregation] off a dashboard snapshot.
///
/// Reads asset rows from [DashboardSnapshot.allocations]. Liability
/// categories (where [CategoryAllocation.category] is
/// [AssetCategory.liability]) are excluded — they have their own
/// surface on the Wealth tab — and the [WealthAggregation.total] reports
/// the gross asset side, not net worth.
WealthAggregation buildWealthAggregation({
  required DashboardSnapshot snapshot,
  required WealthPerspective perspective,
  String Function(AssetCategory category)? categoryLabel,
}) {
  switch (perspective) {
    case WealthPerspective.byCategory:
      return _byCategory(snapshot, categoryLabel ?? _defaultCategoryLabel);
    case WealthPerspective.byCurrency:
      return _byCurrency(snapshot);
  }
}

WealthAggregation _byCategory(
  DashboardSnapshot snapshot,
  String Function(AssetCategory category) labelFn,
) {
  final base = snapshot.baseCurrency;
  final buckets = <WealthBucket>[];
  Decimal total = Decimal.zero;
  for (final allocation in snapshot.allocations) {
    if (allocation.category == AssetCategory.liability) continue;
    final amount = allocation.totalInBase.amount;
    if (amount == Decimal.zero) continue;
    total += amount;
    buckets.add(
      WealthBucket(
        key: allocation.category.name,
        label: labelFn(allocation.category),
        valueInBase: allocation.totalInBase,
        itemCount: allocation.items.length,
      ),
    );
  }
  buckets.sort((a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount));
  return WealthAggregation(
    perspective: WealthPerspective.byCategory,
    buckets: List.unmodifiable(buckets),
    total: Money(total, base),
  );
}

WealthAggregation _byCurrency(DashboardSnapshot snapshot) {
  final base = snapshot.baseCurrency;
  final bucketTotals = <String, Decimal>{};
  final bucketCounts = <String, int>{};
  Decimal total = Decimal.zero;
  for (final allocation in snapshot.allocations) {
    if (allocation.category == AssetCategory.liability) continue;
    for (final item in allocation.items) {
      // Liability rows can appear inside non-liability allocations only
      // via data corruption; the [_byCategory] aggregator already
      // skipped the liability bucket above so anything here is an asset.
      final currency = item.nativeCurrency.toUpperCase();
      bucketTotals[currency] =
          (bucketTotals[currency] ?? Decimal.zero) + item.valueInBase.amount;
      bucketCounts[currency] = (bucketCounts[currency] ?? 0) + 1;
      total += item.valueInBase.amount;
    }
  }
  final buckets =
      bucketTotals.entries
          .where((entry) => entry.value != Decimal.zero)
          .map(
            (entry) => WealthBucket(
              key: entry.key,
              label: entry.key,
              valueInBase: Money(entry.value, base),
              itemCount: bucketCounts[entry.key] ?? 0,
            ),
          )
          .toList()
        ..sort((a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount));
  return WealthAggregation(
    perspective: WealthPerspective.byCurrency,
    buckets: List.unmodifiable(buckets),
    total: Money(total, base),
  );
}

String _defaultCategoryLabel(AssetCategory category) => category.name;
