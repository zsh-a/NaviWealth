import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

/// Market-cap bucket used by the equity allocation view.
///
/// Defaults match the wireframe in `docs/design/06-analytics.md`:
/// large ≥ 200B, small ≤ 2B, mid in between. Both thresholds live in
/// [MarketCapThresholds] so a settings screen can later expose them.
enum MarketCapBucket { large, mid, small }

/// Configurable boundaries for [MarketCapBucket]. Values are in the user's
/// base currency at the point the metadata was captured — we don't try to
/// re-convert them on the fly because changing the user's base currency
/// already invalidates downstream comparisons against the same threshold.
class MarketCapThresholds {
  const MarketCapThresholds({required this.largeMin, required this.smallMax})
    : assert(true, 'caller validates ordering');

  /// Construct the default 200B / 2B split.
  factory MarketCapThresholds.defaults() => MarketCapThresholds(
    largeMin: Decimal.parse('200000000000'),
    smallMax: Decimal.parse('2000000000'),
  );

  /// Minimum market cap (inclusive) to be classified as [MarketCapBucket.large].
  final Decimal largeMin;

  /// Maximum market cap (inclusive) to be classified as [MarketCapBucket.small].
  final Decimal smallMax;

  /// Returns the bucket [cap] falls into, or null when [cap] is null.
  MarketCapBucket? bucket(Decimal? cap) {
    if (cap == null) return null;
    if (cap >= largeMin) return MarketCapBucket.large;
    if (cap <= smallMax) return MarketCapBucket.small;
    return MarketCapBucket.mid;
  }
}

/// Where a single classification field came from.
///
/// `auto` — populated by MarketDataService into the asset row.
/// `manual` — explicit user override stored in [EquityClassificationOverrideStore].
/// `missing` — neither source had a value; the field is treated as
/// "未分类" in the UI and counts toward the unclassified prompt.
enum ClassificationSource { auto, manual, missing }

/// One typed dimension of an [EquityClassification], paired with the
/// provenance of its value.
class ClassifiedField<T> {
  const ClassifiedField({required this.value, required this.source});

  /// Convenience constructor for an absent field.
  const ClassifiedField.missing()
    : value = null,
      source = ClassificationSource.missing;

  final T? value;
  final ClassificationSource source;

  /// True when no usable value was resolved.
  bool get isMissing => value == null;

  @override
  bool operator ==(Object other) =>
      other is ClassifiedField<T> &&
      other.value == value &&
      other.source == source;

  @override
  int get hashCode => Object.hash(value, source);

  @override
  String toString() => 'ClassifiedField($value, $source)';
}

/// All four dimensions an equity instrument is bucketed by, with each
/// dimension carrying its own [ClassificationSource]. The [marketCapBucket]
/// is derived from [marketCap] via [MarketCapThresholds]; it is materialized
/// here so the allocation view doesn't need the thresholds to do bucketing
/// a second time.
class EquityClassification {
  const EquityClassification({
    required this.assetId,
    required this.sector,
    required this.region,
    required this.marketCap,
    required this.marketCapBucket,
  });

  final String assetId;
  final ClassifiedField<String> sector;
  final ClassifiedField<AssetMarket> region;
  final ClassifiedField<Decimal> marketCap;
  final ClassifiedField<MarketCapBucket> marketCapBucket;

  /// True when no value was resolved for [dim].
  bool isMissingFor(EquityAllocationDimension dim) => switch (dim) {
    EquityAllocationDimension.sector => sector.isMissing,
    EquityAllocationDimension.region => region.isMissing,
    EquityAllocationDimension.marketCap => marketCapBucket.isMissing,
  };
}

/// User override for one or more classification dimensions of a single
/// asset. Override values always win over the auto-populated asset fields.
class EquityClassificationOverride {
  const EquityClassificationOverride({
    this.sector,
    this.region,
    this.marketCap,
  });

  final String? sector;
  final AssetMarket? region;
  final Decimal? marketCap;

  bool get isEmpty => sector == null && region == null && marketCap == null;
}

/// Storage for per-asset overrides. The current production binding is
/// [InMemoryEquityClassificationOverrideStore]; persistent storage will be
/// layered on top in a follow-up so users keep their corrections across
/// launches.
abstract class EquityClassificationOverrideStore {
  EquityClassificationOverride? findFor(String assetId);
}

/// Allocation dimensions surfaced on the analytics page.
enum EquityAllocationDimension { sector, region, marketCap }

/// Default empty override store — useful as a stand-in until users have
/// expressed any overrides.
class InMemoryEquityClassificationOverrideStore
    implements EquityClassificationOverrideStore {
  InMemoryEquityClassificationOverrideStore([
    Map<String, EquityClassificationOverride>? seed,
  ]) : _store = {...?seed};

  final Map<String, EquityClassificationOverride> _store;

  @override
  EquityClassificationOverride? findFor(String assetId) => _store[assetId];

  void set(String assetId, EquityClassificationOverride override) {
    if (override.isEmpty) {
      _store.remove(assetId);
      return;
    }
    _store[assetId] = override;
  }

  void clear(String assetId) => _store.remove(assetId);
}

/// Maps an asset to its [EquityClassification].
abstract class EquityClassifier {
  EquityClassification classify(Asset asset);
}

/// Resolves classification by combining the auto-populated columns on the
/// [Asset] row (`industry`, `region`, `market`) with a manual override
/// looked up via [EquityClassificationOverrideStore]. Override values win
/// per-field, so a user can correct just `sector` without losing the
/// auto-resolved region.
class DefaultEquityClassifier implements EquityClassifier {
  DefaultEquityClassifier({
    MarketCapThresholds? thresholds,
    EquityClassificationOverrideStore? overrides,
  }) : thresholds = thresholds ?? MarketCapThresholds.defaults(),
       _overrides = overrides ?? InMemoryEquityClassificationOverrideStore();

  final MarketCapThresholds thresholds;
  final EquityClassificationOverrideStore _overrides;

  @override
  EquityClassification classify(Asset asset) {
    final override = _overrides.findFor(asset.id);

    final sector = _resolve(override?.sector, _normalizeSector(asset.industry));
    final region = _resolveRegion(override?.region, asset.region, asset.market);
    final cap = _resolve(override?.marketCap, _autoMarketCap(asset));

    final ClassifiedField<MarketCapBucket> bucket;
    final bucketValue = thresholds.bucket(cap.value);
    if (bucketValue == null) {
      bucket = const ClassifiedField<MarketCapBucket>.missing();
    } else {
      bucket = ClassifiedField(value: bucketValue, source: cap.source);
    }

    return EquityClassification(
      assetId: asset.id,
      sector: sector,
      region: region,
      marketCap: cap,
      marketCapBucket: bucket,
    );
  }

  ClassifiedField<T> _resolve<T>(T? overrideValue, T? autoValue) {
    if (overrideValue != null) {
      return ClassifiedField(
        value: overrideValue,
        source: ClassificationSource.manual,
      );
    }
    if (autoValue != null) {
      return ClassifiedField(
        value: autoValue,
        source: ClassificationSource.auto,
      );
    }
    return const ClassifiedField.missing();
  }

  ClassifiedField<AssetMarket> _resolveRegion(
    AssetMarket? overrideValue,
    String? regionHint,
    String? marketHint,
  ) {
    if (overrideValue != null) {
      return ClassifiedField(
        value: overrideValue,
        source: ClassificationSource.manual,
      );
    }
    final auto =
        assetMarketFromHint(regionHint) ?? assetMarketFromHint(marketHint);
    if (auto != null && auto != AssetMarket.unknown) {
      return ClassifiedField(value: auto, source: ClassificationSource.auto);
    }
    return const ClassifiedField.missing();
  }

  String? _normalizeSector(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Auto market cap is not yet populated by the current MarketDataService;
  /// returning null lets [_resolve] fall through to "missing". When
  /// market-cap support lands, point this at the appropriate Asset field
  /// (or a sidecar metadata column) without having to revisit the rest of
  /// the analytics pipeline.
  Decimal? _autoMarketCap(Asset asset) => null;
}

/// Maps a free-form market / region hint string (as stored on the `Asset`
/// row) to an [AssetMarket]. Intentionally permissive — every
/// canonical broker name we have seen so far flows through here.
AssetMarket? assetMarketFromHint(String? raw) {
  if (raw == null) return null;
  switch (raw.trim().toLowerCase()) {
    case 'cn':
    case 'cn-a':
    case 'cna':
    case 'cn_a':
    case 'a':
    case 'a-share':
    case 'a-shares':
    case 'sse':
    case 'szse':
    case 'shanghai':
    case 'shenzhen':
      return AssetMarket.cnA;
    case 'hk':
    case 'hkex':
    case 'hong kong':
    case 'hk-stock':
      return AssetMarket.hkStock;
    case 'us':
    case 'usa':
    case 'nyse':
    case 'nasdaq':
    case 'amex':
    case 'us-stock':
    case 'us_stock':
      return AssetMarket.usStock;
    case 'crypto':
    case 'cryptocurrency':
      return AssetMarket.crypto;
    case 'fx':
    case 'forex':
      return AssetMarket.fx;
    case '':
    case 'unknown':
      return null;
    default:
      return null;
  }
}
