import 'asset_market.dart';
import 'market_data_service.dart';

/// How much to trust a resolved price.
///
/// The layered resolver attaches one of these to every [ResolvedPrice] so
/// downstream consumers (dashboard, AI prompt, freshness badges) can caveat
/// without re-deriving heuristics from raw timestamps. The ordering of the
/// enum reflects descending trust — [realTime] is best, [stale] is worst.
enum PriceConfidence {
  /// Live quote, real-time-eligible market, observed within [realTimeMaxAge].
  realTime,

  /// Live quote but the provider bar is older than [realTimeMaxAge] (most
  /// free feeds run a 15-minute delay even when they answer 'live').
  delayed,

  /// Cache-fresh quote or the most recent daily close — accurate enough to
  /// value a portfolio, not accurate enough to trade on.
  dailyClose,

  /// User entered the price by hand (manual asset valuation or trade fill).
  manual,

  /// No price source produced a value; downstream computed an approximate
  /// figure (typically cost-basis carry-forward).
  estimated,

  /// Any tier returned a value past its freshness window. Surfacing as
  /// [stale] is the contract — UI badge, AI caveat, sync coordinator
  /// scheduling a refresh.
  stale,
}

/// Threshold below which a live quote is treated as [PriceConfidence.realTime].
/// Above this and up to [delayedMaxAge] we tag [PriceConfidence.delayed].
const Duration realTimeMaxAge = Duration(minutes: 5);

/// Hard ceiling for the [delayed] tag — beyond this, even a 'live' provider
/// response is downgraded to [dailyClose] because the bar is stale enough
/// to be functionally a daily close.
const Duration delayedMaxAge = Duration(minutes: 30);

extension PriceConfidenceMapping on PriceConfidence {
  /// Map a [MarketDataService] freshness response into a [PriceConfidence].
  ///
  /// - [DataFreshness.live] inspects [age]:
  ///     ≤ [realTimeMaxAge]  → [realTime]
  ///     ≤ [delayedMaxAge]   → [delayed]
  ///     otherwise           → [dailyClose]
  /// - [DataFreshness.cachedFresh] → [dailyClose] (the cache TTL guarantees
  ///   the value is recent enough for valuation but not for trading).
  /// - [DataFreshness.stale] → [stale].
  ///
  /// FX is always [dailyClose] when live — the FX feed is a once-per-day
  /// reference rate, not a tradeable quote.
  static PriceConfidence fromFreshness(
    DataFreshness freshness, {
    required Duration age,
    AssetMarket? market,
  }) {
    switch (freshness) {
      case DataFreshness.stale:
        return PriceConfidence.stale;
      case DataFreshness.cachedFresh:
        return PriceConfidence.dailyClose;
      case DataFreshness.live:
        if (market == AssetMarket.fx) return PriceConfidence.dailyClose;
        if (age <= realTimeMaxAge) return PriceConfidence.realTime;
        if (age <= delayedMaxAge) return PriceConfidence.delayed;
        return PriceConfidence.dailyClose;
    }
  }
}
