import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';

/// The seven top-level "big bucket" categories surfaced by the dashboard pie
/// chart. The set is derived from scope: 股票 / ETF / 现金 / 加密 /
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

@immutable
class DashboardPhysicalValuation {
  const DashboardPhysicalValuation({required this.asOf, required this.value});

  final DateTime asOf;
  final Decimal value;
}

@immutable
class DashboardPhysicalAsset {
  const DashboardPhysicalAsset({
    required this.id,
    required this.name,
    required this.currency,
    required this.type,
    required this.currentValuation,
    required this.purchaseDate,
    required this.purchasePrice,
    this.lastValuationAt,
    this.address,
    this.autoDepreciation = false,
    this.annualResidualRate,
    this.valuationHistory = const [],
  });

  final String id;
  final String name;
  final String currency;
  final AssetType type;
  final Decimal currentValuation;
  final DateTime purchaseDate;
  final Decimal purchasePrice;
  final DateTime? lastValuationAt;
  final String? address;
  final bool autoDepreciation;
  final Decimal? annualResidualRate;

  /// Actual purchase/manual valuation points used by the historical trend.
  /// Keeping this dashboard-owned type avoids coupling the home read model
  /// to the physical-assets persistence implementation.
  final List<DashboardPhysicalValuation> valuationHistory;
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
    this.liabilityType,
    this.routeHint,
  });

  /// Stable id of the underlying asset / liability — used as the navigation
  /// target when the user taps the row in the drill-down list.
  final String id;
  final String name;

  /// Pre-rendered subtitle string. Use [liabilityType] instead when the
  /// row is a liability — the enum survives across locale switches and the
  /// UI resolves the localised label at render time.
  final String? subtitle;

  /// When non-null, the row represents a liability with this [LiabilityType].
  /// The UI looks up the localised label via `liabilityTypeLabel(...)` rather
  /// than relying on [subtitle], which keeps the aggregator framework- and
  /// locale-agnostic.
  final LiabilityType? liabilityType;

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

  /// Optional opaque hint the UI uses to deep-link the row (e.g. a
  /// `/portfolio/<id>` path or a tab name). Keeping it as a string lets
  /// the dashboard build above multiple feature routers.
  final String? routeHint;

  @override
  bool operator ==(Object other) =>
      other is CategoryItem &&
      other.id == id &&
      other.name == name &&
      other.subtitle == subtitle &&
      other.liabilityType == liabilityType &&
      other.valueInBase == valueInBase &&
      other.nativeAmount == nativeAmount &&
      other.nativeCurrency == nativeCurrency &&
      other.routeHint == routeHint;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    subtitle,
    liabilityType,
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
      other is CurrencyMismatch && other.id == id && other.currency == currency;

  @override
  int get hashCode => Object.hash(id, currency);
}

@immutable
class ManualAssetValuePoint {
  const ManualAssetValuePoint({required this.observedOn, required this.value});

  final DateTime observedOn;
  final Decimal value;

  @override
  bool operator ==(Object other) =>
      other is ManualAssetValuePoint &&
      other.observedOn == observedOn &&
      other.value == value;

  @override
  int get hashCode => Object.hash(observedOn, value);
}

/// Manual-valuation asset paired with its price/valuation observations.
///
/// Cash, deposits and wealth products no longer store current value on the
/// `assets` row. The authoritative values live in `prices`, so dashboard
/// consumers must carry both the asset metadata and its valuation history.
@immutable
class ManualAssetValuation {
  const ManualAssetValuation({required this.asset, required this.observations});

  final Asset asset;
  final List<ManualAssetValuePoint> observations;

  Decimal? valueAt(DateTime asOf) {
    if (observations.isEmpty) return null;
    for (var i = observations.length - 1; i >= 0; i--) {
      final point = observations[i];
      if (!point.observedOn.isAfter(asOf)) return point.value;
    }
    return null;
  }

  Decimal? currentValue() =>
      observations.isEmpty ? null : observations.last.value;

  @override
  bool operator ==(Object other) =>
      other is ManualAssetValuation &&
      other.asset == asset &&
      listEquals(other.observations, observations);

  @override
  int get hashCode => Object.hash(asset, Object.hashAll(observations));
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
    this.staleHoldingCount = 0,
    this.confidenceFloor,
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

  /// Number of securities holdings whose resolved price came back with
  /// [PriceConfidence.stale]. Drives the "N holdings have stale prices"
  /// banner. Zero when every contributing holding had a fresh price or
  /// when the dashboard has no securities holdings.
  final int staleHoldingCount;

  /// Worst (lowest-trust) [PriceConfidence] across every contributing
  /// holding. `null` when no security holding contributed a confidence
  /// (e.g. pure manual-asset portfolio, or empty snapshot).
  final PriceConfidence? confidenceFloor;

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
