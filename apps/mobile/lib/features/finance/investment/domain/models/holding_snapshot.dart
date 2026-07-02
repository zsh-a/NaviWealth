import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'lot.dart';

/// Per-asset position summary at a given point in time.
///
/// `cost_basis_in_base`, `market_value_in_base` and `unrealized_pnl_in_base`
/// are denominated in the user's selected base currency. The
/// asset-currency view ([costBasisInAssetCurrency], [marketValueInAssetCurrency])
/// is preserved alongside so reports that want to show "AAPL: $1,234 USD"
/// don't have to round-trip back through the FX converter.
///
/// [weight] is the fraction `marketValueInBase / totalPortfolioMarketValueInBase`
/// in `[0, 1]`; the [HoldingComputer] fills it in after the per-asset
/// snapshots are aggregated. Returned from a single asset path it is zero.
class HoldingSnapshot {
  const HoldingSnapshot({
    required this.assetId,
    required this.quantity,
    required this.costBasisInAssetCurrency,
    required this.marketValueInAssetCurrency,
    required this.assetCurrency,
    required this.costBasisInBase,
    required this.marketValueInBase,
    required this.unrealizedPnlInBase,
    required this.weight,
    required this.baseCurrency,
    required this.asOf,
    this.priceConfidence,
    this.priceSource,
    this.priceAsOf,
  });

  final String assetId;
  final Decimal quantity;

  final Decimal costBasisInAssetCurrency;
  final Decimal marketValueInAssetCurrency;
  final String assetCurrency;

  final Decimal costBasisInBase;
  final Decimal marketValueInBase;
  final Decimal unrealizedPnlInBase;

  /// Portfolio weight in `[0, 1]`.
  final Decimal weight;

  final String baseCurrency;
  final DateTime asOf;

  /// Trust level of the price used to derive [marketValueInAssetCurrency].
  /// Null when the snapshot was built without a resolver-sourced price
  /// (legacy tests, manual-valuation cost-basis fallback path).
  final PriceConfidence? priceConfidence;

  /// Provenance string of the price source — see [ResolvedPrice.source]
  /// for the convention.
  final String? priceSource;

  /// Observation timestamp of the price. Distinct from [asOf] (which is
  /// the snapshot computation moment); for forward-filled or daily-close
  /// prices this can be hours or days earlier.
  final DateTime? priceAsOf;

  HoldingSnapshot copyWith({
    Decimal? weight,
    Decimal? marketValueInAssetCurrency,
    Decimal? marketValueInBase,
    Decimal? unrealizedPnlInBase,
    DateTime? asOf,
    PriceConfidence? priceConfidence,
    String? priceSource,
    DateTime? priceAsOf,
  }) {
    return HoldingSnapshot(
      assetId: assetId,
      quantity: quantity,
      costBasisInAssetCurrency: costBasisInAssetCurrency,
      marketValueInAssetCurrency:
          marketValueInAssetCurrency ?? this.marketValueInAssetCurrency,
      assetCurrency: assetCurrency,
      costBasisInBase: costBasisInBase,
      marketValueInBase: marketValueInBase ?? this.marketValueInBase,
      unrealizedPnlInBase: unrealizedPnlInBase ?? this.unrealizedPnlInBase,
      weight: weight ?? this.weight,
      baseCurrency: baseCurrency,
      asOf: asOf ?? this.asOf,
      priceConfidence: priceConfidence ?? this.priceConfidence,
      priceSource: priceSource ?? this.priceSource,
      priceAsOf: priceAsOf ?? this.priceAsOf,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HoldingSnapshot &&
        other.assetId == assetId &&
        other.quantity == quantity &&
        other.costBasisInAssetCurrency == costBasisInAssetCurrency &&
        other.marketValueInAssetCurrency == marketValueInAssetCurrency &&
        other.assetCurrency == assetCurrency &&
        other.costBasisInBase == costBasisInBase &&
        other.marketValueInBase == marketValueInBase &&
        other.unrealizedPnlInBase == unrealizedPnlInBase &&
        other.weight == weight &&
        other.baseCurrency == baseCurrency &&
        other.asOf == asOf &&
        other.priceConfidence == priceConfidence &&
        other.priceSource == priceSource &&
        other.priceAsOf == priceAsOf;
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    quantity,
    costBasisInAssetCurrency,
    marketValueInAssetCurrency,
    assetCurrency,
    costBasisInBase,
    marketValueInBase,
    unrealizedPnlInBase,
    weight,
    baseCurrency,
    asOf,
    priceConfidence,
    priceSource,
    priceAsOf,
  );

  @override
  String toString() =>
      'HoldingSnapshot($assetId: qty=$quantity, mv=$marketValueInBase '
      '$baseCurrency, pnl=$unrealizedPnlInBase, w=$weight)';
}

/// Lot inventory at the close of a given day, used as the cache base for
/// incremental holding computation.
///
/// Keyed by `(ownerUserId, day)` in storage; in memory we just hand around a
/// `Map<String, LotInventorySnapshot>` keyed by ISO day string.
class LotInventorySnapshot {
  const LotInventorySnapshot({
    required this.ownerUserId,
    required this.day,
    required this.lots,
  });

  /// Owner partition for the snapshot. Mirrors [SyncableTable] so multi-user
  /// installs never bleed lots across boundaries.
  final String ownerUserId;

  /// UTC calendar day this snapshot represents the close of.
  final DateTime day;

  /// Lot inventory at the close of [day]. Closed lots (remainingQuantity == 0)
  /// are kept so that downstream reporting can still attribute realized P&L
  /// against their `id`.
  final List<Lot> lots;

  /// Open lots only — convenience for the hot path of [HoldingComputer.replay].
  Iterable<Lot> get openLots => lots.where((l) => !l.isClosed);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LotInventorySnapshot &&
        other.ownerUserId == ownerUserId &&
        other.day == day &&
        _listEquals(other.lots, lots);
  }

  @override
  int get hashCode => Object.hash(ownerUserId, day, Object.hashAll(lots));

  @override
  String toString() =>
      'LotInventorySnapshot($ownerUserId @ ${day.toIso8601String().substring(0, 10)} '
      'with ${lots.length} lots)';

  static bool _listEquals(List<Lot> a, List<Lot> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
