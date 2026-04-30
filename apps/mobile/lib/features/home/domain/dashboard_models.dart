import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../data/domain/enums.dart';
import '../../../domain/values/money.dart';

/// The seven top-level "big bucket" categories surfaced by the dashboard pie
/// chart. The set is derived from FIR-52's scope: 股票 / ETF / 现金 / 加密 /
/// 房产 / 车辆 / 负债. We add `bondsAndFunds` as a catch-all for fixed-income
/// holdings (mutual funds, bonds, deposits, wealth products) so they don't
/// silently roll up into "cash" — users keep separate mental buckets for
/// these and conflating them hides risk concentration.
enum AssetCategory {
  stock,
  etf,
  bondsAndFunds,
  cash,
  crypto,
  realEstate,
  vehicle,
  liability,
}

/// One row in a category breakdown drill-down.
@immutable
class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.valueInBase,
    required this.nativeAmount,
    required this.nativeCurrency,
    this.routeHint,
  });

  /// Stable id of the underlying asset / liability — used as the navigation
  /// target when the user taps the row in the drill-down list.
  final String id;
  final String name;
  final String? subtitle;

  /// Value of this row in the dashboard's base currency. Always positive for
  /// asset rows; positive (i.e. unsigned outstanding balance) for liability
  /// rows — the negative sign is applied at the [CategoryAllocation] level
  /// so the pie chart can decide whether to show liabilities as a negative
  /// slice or in a separate "deductions" panel.
  final Money valueInBase;

  /// Native-currency amount, before FX conversion. Useful for the row
  /// subtitle ("$1,234 USD · ¥9,012 CNY").
  final Decimal nativeAmount;
  final String nativeCurrency;

  /// Optional opaque hint the UI uses to deep-link the row (e.g. an
  /// `/assets/<id>` path or a tab name). Keeping it as a string lets
  /// the dashboard build above multiple feature routers.
  final String? routeHint;

  @override
  bool operator ==(Object other) =>
      other is CategoryItem &&
      other.id == id &&
      other.name == name &&
      other.subtitle == subtitle &&
      other.valueInBase == valueInBase &&
      other.nativeAmount == nativeAmount &&
      other.nativeCurrency == nativeCurrency &&
      other.routeHint == routeHint;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        subtitle,
        valueInBase,
        nativeAmount,
        nativeCurrency,
        routeHint,
      );
}

/// One slice of the allocation pie. Aggregates the per-asset items in a
/// single category along with the category-level total.
@immutable
class CategoryAllocation {
  const CategoryAllocation({
    required this.category,
    required this.totalInBase,
    required this.items,
  });

  final AssetCategory category;

  /// Sum of [items]' values in base currency. For [AssetCategory.liability]
  /// this is the unsigned outstanding principal — consumers that need a
  /// signed number (e.g. computing net worth) negate liabilities themselves.
  final Money totalInBase;

  final List<CategoryItem> items;

  bool get isLiability => category == AssetCategory.liability;

  @override
  bool operator ==(Object other) =>
      other is CategoryAllocation &&
      other.category == category &&
      other.totalInBase == totalInBase &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(category, totalInBase, Object.hashAll(items));
}

/// One asset / liability whose conversion to the dashboard's base currency
/// failed. Surfaced so the UI can warn the user that the displayed total
/// excludes these holdings instead of silently dropping them.
@immutable
class CurrencyMismatch {
  const CurrencyMismatch({required this.id, required this.currency});

  final String id;
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is CurrencyMismatch &&
      other.id == id &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(id, currency);
}

/// Snapshot of the user's current asset distribution, ready to be rendered
/// by the dashboard pie chart and net-worth header.
@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.asOf,
    required this.baseCurrency,
    required this.allocations,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netWorth,
    this.currencyMismatches = const [],
  });

  /// Empty snapshot — used as the initial state while async data is still
  /// loading or when the user has not yet entered any assets.
  factory DashboardSnapshot.empty({
    required DateTime asOf,
    required String baseCurrency,
  }) {
    return DashboardSnapshot(
      asOf: asOf,
      baseCurrency: baseCurrency,
      allocations: const [],
      totalAssets: Money.zero(baseCurrency),
      totalLiabilities: Money.zero(baseCurrency),
      netWorth: Money.zero(baseCurrency),
    );
  }

  final DateTime asOf;
  final String baseCurrency;
  final List<CategoryAllocation> allocations;
  final Money totalAssets;
  final Money totalLiabilities;
  final Money netWorth;

  /// Holdings excluded from the totals because no FX rate could convert
  /// them to [baseCurrency]. Empty when every asset / liability could be
  /// folded into the snapshot. Caller surfaces these in a warning banner.
  final List<CurrencyMismatch> currencyMismatches;

  bool get isEmpty => allocations.isEmpty;
}

/// Mapping from asset-type → big-bucket category. Centralised here so both
/// the snapshot aggregator and the trend builder agree on the bucketing
/// rules.
AssetCategory categoryForAssetType(AssetType type) {
  switch (type) {
    case AssetType.stock:
      return AssetCategory.stock;
    case AssetType.etf:
      return AssetCategory.etf;
    case AssetType.crypto:
      return AssetCategory.crypto;
    case AssetType.realEstate:
      return AssetCategory.realEstate;
    case AssetType.vehicle:
      return AssetCategory.vehicle;
    case AssetType.cash:
      return AssetCategory.cash;
    case AssetType.bond:
    case AssetType.mutualFund:
    case AssetType.bankDepositTerm:
    case AssetType.bankDepositDemand:
    case AssetType.wealthProduct:
      return AssetCategory.bondsAndFunds;
    case AssetType.commodity:
    case AssetType.custom:
      return AssetCategory.stock; // best-effort fallback
  }
}
