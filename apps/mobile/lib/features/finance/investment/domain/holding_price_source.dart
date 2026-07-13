import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'package:naviwealth/features/finance/market/domain/resolved_price.dart';

/// Per-asset price observation used by the holding pipeline.
///
/// Carries its own [currency] because a multi-market portfolio routinely
/// holds USD, CNY and HKD assets side by side; collapsing to base currency
/// at the source of truth would discard the native-currency view that
/// [HoldingSnapshot.marketValueInAssetCurrency] needs.
///
/// [confidence], [source] and [asOf] are populated when the price came
/// from the layered resolver. They are nullable so legacy in-memory test
/// fakes (which only carry the raw decimal) still construct.
class HoldingPrice {
  const HoldingPrice({
    required this.price,
    required this.currency,
    this.confidence,
    this.source,
    this.asOf,
  });

  final Decimal price;
  final String currency;
  final PriceConfidence? confidence;
  final String? source;
  final DateTime? asOf;

  @override
  bool operator ==(Object other) =>
      other is HoldingPrice &&
      other.price == price &&
      other.currency == currency &&
      other.confidence == confidence &&
      other.source == source &&
      other.asOf == asOf;

  @override
  int get hashCode => Object.hash(price, currency, confidence, source, asOf);

  @override
  String toString() => '$price $currency';
}

/// Domain-side contract for "give me a price for this asset on this date".
///
/// Decoupled from [MarketDataService] so the pure [HoldingComputer] can be
/// driven from any source — a fake map in tests, an Asset.lastPrice fallback,
/// the live market service, or a historical bar lookup.
abstract class HoldingPriceSource {
  /// Returns the price observed at or before [asOf] for [assetId], or null
  /// when no price is available. Implementations decide whether to fall back
  /// to an older quote or refuse — the computer treats null as "skip the
  /// market-value calculation for this asset."
  HoldingPrice? priceFor(String assetId, {required DateTime asOf});
}

/// In-memory [HoldingPriceSource] backed by a flat list of observations.
///
/// Behaves like [InMemoryFxRateLookup]: pick the most recent observation
/// whose `asOf` is `<= asOf` (forward-fill — markets close, holidays happen,
/// and refusing to value a portfolio because Christmas Day has no quote is
/// not the right behaviour).
class InMemoryHoldingPriceSource implements HoldingPriceSource {
  InMemoryHoldingPriceSource(Iterable<HoldingPriceObservation> observations)
    : _byAsset = _index(observations);

  final Map<String, List<HoldingPriceObservation>> _byAsset;

  @override
  HoldingPrice? priceFor(String assetId, {required DateTime asOf}) {
    final observations = _byAsset[assetId];
    if (observations == null || observations.isEmpty) return null;
    // observations sorted ascending by asOf — walk backwards for nearest <= asOf.
    for (var i = observations.length - 1; i >= 0; i--) {
      final obs = observations[i];
      if (!obs.asOf.isAfter(asOf)) {
        return HoldingPrice(
          price: obs.price,
          currency: obs.currency,
          confidence: obs.confidence,
          source: obs.source,
          asOf: obs.asOf,
        );
      }
    }
    return null;
  }

  static Map<String, List<HoldingPriceObservation>> _index(
    Iterable<HoldingPriceObservation> observations,
  ) {
    final map = <String, List<HoldingPriceObservation>>{};
    for (final o in observations) {
      map.putIfAbsent(o.assetId, () => []).add(o);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.asOf.compareTo(b.asOf));
    }
    return map;
  }
}

/// Single price observation row for [InMemoryHoldingPriceSource].
class HoldingPriceObservation {
  const HoldingPriceObservation({
    required this.assetId,
    required this.price,
    required this.currency,
    required this.asOf,
    this.confidence,
    this.source,
  });

  final String assetId;
  final Decimal price;
  final String currency;
  final DateTime asOf;
  final PriceConfidence? confidence;
  final String? source;
}

/// [HoldingPriceSource] composed of two layers:
///
///   - [resolved]: a pre-computed map of [ResolvedPrice]s from the
///     [PriceResolver], captured at [resolvedAt]. Used when the caller's
///     `asOf` is within [resolvedFreshness] of [resolvedAt] — typically
///     "now-ish" lookups for the live dashboard.
///   - [fallback]: a `HoldingPriceSource` over the `prices` ledger.
///     Used for historical lookups and as a safety net when the resolver
///     returned `null` for an asset.
///
/// This composition lets Phase B switch the live valuation path to the
/// resolver without breaking historical valuation, which still depends
/// on the synced observation history.
class ResolvedPriceHoldingSource implements HoldingPriceSource {
  ResolvedPriceHoldingSource({
    required Map<String, ResolvedPrice?> resolved,
    required this.resolvedAt,
    required this.fallback,
    this.resolvedFreshness = const Duration(days: 1),
  }) : _resolved = resolved;

  final Map<String, ResolvedPrice?> _resolved;
  final DateTime resolvedAt;
  final HoldingPriceSource fallback;
  final Duration resolvedFreshness;

  @override
  HoldingPrice? priceFor(String assetId, {required DateTime asOf}) {
    final lookback = resolvedAt.difference(asOf).abs();
    if (lookback <= resolvedFreshness) {
      final r = _resolved[assetId];
      // A now-ish resolver result is only valid for this sample when the
      // observation itself is not in the future. Without this guard, a quote
      // fetched today could leak into yesterday's end-of-day trend point.
      if (r != null && !r.asOf.isAfter(asOf)) {
        return HoldingPrice(
          price: r.value,
          currency: r.currency,
          confidence: r.confidence,
          source: r.source,
          asOf: r.asOf,
        );
      }
    }
    return fallback.priceFor(assetId, asOf: asOf);
  }
}
