import 'package:decimal/decimal.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

import 'equity_classification.dart';

/// Asset types whose holdings are surfaced on the equity analytics page.
/// Cash, deposits, wealth products and physical assets are excluded —
/// "股票透视" is for tradeable securities only.
const Set<AssetType> kEquityAssetTypes = {
  AssetType.stock,
  AssetType.etf,
  AssetType.mutualFund,
};

/// Stable key for an allocation bucket. The key shape varies per dimension
/// so the UI can dispatch on `bucketKey` without losing type information.
sealed class BucketKey {
  const BucketKey();
}

class SectorBucketKey extends BucketKey {
  const SectorBucketKey(this.sector);
  final String sector;
  @override
  bool operator ==(Object other) =>
      other is SectorBucketKey && other.sector == sector;
  @override
  int get hashCode => Object.hash('sector', sector);
}

class RegionBucketKey extends BucketKey {
  const RegionBucketKey(this.region);
  final AssetMarket region;
  @override
  bool operator ==(Object other) =>
      other is RegionBucketKey && other.region == region;
  @override
  int get hashCode => Object.hash('region', region);
}

class MarketCapBucketKey extends BucketKey {
  const MarketCapBucketKey(this.bucket);
  final MarketCapBucket bucket;
  @override
  bool operator ==(Object other) =>
      other is MarketCapBucketKey && other.bucket == bucket;
  @override
  int get hashCode => Object.hash('marketCap', bucket);
}

class UnclassifiedBucketKey extends BucketKey {
  const UnclassifiedBucketKey();
  @override
  bool operator ==(Object other) => other is UnclassifiedBucketKey;
  @override
  int get hashCode => 'unclassified'.hashCode;
}

/// One holding inside an allocation bucket — the per-row record used to
/// populate the drill-down list.
class EquityHoldingRow {
  const EquityHoldingRow({
    required this.assetId,
    required this.symbol,
    required this.name,
    required this.assetType,
    required this.marketValueInBase,
    required this.weight,
    required this.classification,
  });

  final String assetId;
  final String symbol;
  final String? name;
  final AssetType assetType;
  final Decimal marketValueInBase;
  final Decimal weight;
  final EquityClassification classification;
}

/// One slice of the pie / one row of the bar chart.
class EquityAllocationBucket {
  const EquityAllocationBucket({
    required this.dimension,
    required this.key,
    required this.label,
    required this.totalValueInBase,
    required this.weight,
    required this.holdings,
    required this.isUnclassified,
  });

  final EquityAllocationDimension dimension;
  final BucketKey key;

  /// Stable, locale-neutral identifier for the bucket. The presentation
  /// layer maps known values (e.g. region enum names) to localized labels;
  /// free-form sector strings flow through verbatim.
  final String label;
  final Decimal totalValueInBase;
  final Decimal weight;
  final List<EquityHoldingRow> holdings;
  final bool isUnclassified;
}

/// Result of [EquityAllocationService.aggregate] — everything the
/// allocation view needs in a single immutable bundle.
class EquityAllocationView {
  const EquityAllocationView({
    required this.dimension,
    required this.baseCurrency,
    required this.totalValueInBase,
    required this.buckets,
    required this.unclassifiedCount,
    required this.asOf,
    required this.thresholds,
  });

  /// Empty view — used for the "no equity holdings yet" state. Avoids
  /// special-casing in the UI.
  factory EquityAllocationView.empty({
    required EquityAllocationDimension dimension,
    required String baseCurrency,
    required DateTime asOf,
    MarketCapThresholds? thresholds,
  }) {
    return EquityAllocationView(
      dimension: dimension,
      baseCurrency: baseCurrency,
      totalValueInBase: Decimal.zero,
      buckets: const <EquityAllocationBucket>[],
      unclassifiedCount: 0,
      asOf: asOf,
      thresholds: thresholds ?? MarketCapThresholds.defaults(),
    );
  }

  final EquityAllocationDimension dimension;
  final String baseCurrency;
  final Decimal totalValueInBase;
  final List<EquityAllocationBucket> buckets;

  /// Number of holdings whose classification was missing for [dimension].
  /// Drives the "请补全 N 个未分类持仓" hint.
  final int unclassifiedCount;
  final DateTime asOf;
  final MarketCapThresholds thresholds;

  bool get isEmpty => buckets.isEmpty;
}

/// Pure aggregator: take a snapshot of holdings, classify each, and roll
/// them up into [EquityAllocationBucket]s for one [EquityAllocationDimension].
///
/// This sits one layer above [HoldingService] — the holdings come in
/// already valued in the base currency, so the aggregator never has to
/// touch the FX layer or the price source again.
class EquityAllocationService {
  const EquityAllocationService();

  EquityAllocationView aggregate({
    required Iterable<HoldingSnapshot> snapshots,
    required Asset? Function(String assetId) assetLookup,
    required EquityClassifier classifier,
    required EquityAllocationDimension dimension,
    required String baseCurrency,
    required DateTime asOf,
    MarketCapThresholds? thresholds,
  }) {
    final effectiveThresholds = thresholds ?? MarketCapThresholds.defaults();
    final byKey = <BucketKey, _BucketAggregate>{};
    var portfolioTotal = Decimal.zero;
    var unclassifiedCount = 0;

    for (final snapshot in snapshots) {
      final asset = assetLookup(snapshot.assetId);
      if (asset == null) continue;
      if (!kEquityAssetTypes.contains(asset.type)) continue;
      if (snapshot.marketValueInBase.sign <= 0) continue;

      final classification = classifier.classify(asset);
      portfolioTotal += snapshot.marketValueInBase;

      final BucketKey key;
      final String label;
      final bool isUnclassified;
      if (classification.isMissingFor(dimension)) {
        key = const UnclassifiedBucketKey();
        label = _kUnclassifiedLabel;
        isUnclassified = true;
        unclassifiedCount += 1;
      } else {
        switch (dimension) {
          case EquityAllocationDimension.sector:
            final sector = classification.sector.value!;
            key = SectorBucketKey(sector);
            label = sector;
          case EquityAllocationDimension.region:
            final region = classification.region.value!;
            key = RegionBucketKey(region);
            label = region.name;
          case EquityAllocationDimension.marketCap:
            final bucket = classification.marketCapBucket.value!;
            key = MarketCapBucketKey(bucket);
            label = bucket.name;
        }
        isUnclassified = false;
      }

      final agg = byKey.putIfAbsent(
        key,
        () => _BucketAggregate(
          key: key,
          label: label,
          isUnclassified: isUnclassified,
        ),
      );
      agg.add(snapshot, asset, classification);
    }

    final buckets =
        byKey.values
            .map(
              (a) => EquityAllocationBucket(
                dimension: dimension,
                key: a.key,
                label: a.label,
                totalValueInBase: a.total,
                weight: portfolioTotal.sign == 0
                    ? Decimal.zero
                    : (a.total / portfolioTotal).toDecimal(
                        scaleOnInfinitePrecision: 12,
                      ),
                holdings: a.buildHoldings(portfolioTotal),
                isUnclassified: a.isUnclassified,
              ),
            )
            .toList()
          ..sort(_compareBuckets);

    return EquityAllocationView(
      dimension: dimension,
      baseCurrency: baseCurrency,
      totalValueInBase: portfolioTotal,
      buckets: List.unmodifiable(buckets),
      unclassifiedCount: unclassifiedCount,
      asOf: asOf,
      thresholds: effectiveThresholds,
    );
  }

  static int _compareBuckets(
    EquityAllocationBucket a,
    EquityAllocationBucket b,
  ) {
    // Unclassified always last — keeps the eye on the data buckets first.
    if (a.isUnclassified != b.isUnclassified) {
      return a.isUnclassified ? 1 : -1;
    }
    final cmp = b.totalValueInBase.compareTo(a.totalValueInBase);
    if (cmp != 0) return cmp;
    return a.label.compareTo(b.label);
  }
}

/// Stable token for the unclassified bucket. The UI looks for this exact
/// value to decide whether to show the "complete metadata" hint inside
/// the bucket row.
const String _kUnclassifiedLabel = '__unclassified__';

/// Public accessor for [_kUnclassifiedLabel] so widgets / tests can
/// pattern-match without re-declaring the constant.
const String kUnclassifiedBucketLabel = _kUnclassifiedLabel;

class _BucketAggregate {
  _BucketAggregate({
    required this.key,
    required this.label,
    required this.isUnclassified,
  });

  final BucketKey key;
  final String label;
  final bool isUnclassified;
  Decimal total = Decimal.zero;
  final List<_HoldingPart> _parts = [];

  void add(
    HoldingSnapshot snapshot,
    Asset asset,
    EquityClassification classification,
  ) {
    total += snapshot.marketValueInBase;
    _parts.add(
      _HoldingPart(
        snapshot: snapshot,
        asset: asset,
        classification: classification,
      ),
    );
  }

  List<EquityHoldingRow> buildHoldings(Decimal portfolioTotal) {
    final rows =
        _parts.map((p) {
            final weight = portfolioTotal.sign == 0
                ? Decimal.zero
                : (p.snapshot.marketValueInBase / portfolioTotal).toDecimal(
                    scaleOnInfinitePrecision: 12,
                  );
            return EquityHoldingRow(
              assetId: p.asset.id,
              symbol: p.asset.symbol,
              name: p.asset.name,
              assetType: p.asset.type,
              marketValueInBase: p.snapshot.marketValueInBase,
              weight: weight,
              classification: p.classification,
            );
          }).toList()
          ..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));
    return List.unmodifiable(rows);
  }
}

class _HoldingPart {
  _HoldingPart({
    required this.snapshot,
    required this.asset,
    required this.classification,
  });

  final HoldingSnapshot snapshot;
  final Asset asset;
  final EquityClassification classification;
}
