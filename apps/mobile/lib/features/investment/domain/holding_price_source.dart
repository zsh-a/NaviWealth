import 'package:decimal/decimal.dart';

/// Per-asset price observation used by the holding pipeline.
///
/// Carries its own [currency] because a multi-market portfolio routinely
/// holds USD, CNY and HKD assets side by side; collapsing to base currency
/// at the source of truth would discard the native-currency view that
/// [HoldingSnapshot.marketValueInAssetCurrency] needs.
class HoldingPrice {
  const HoldingPrice({required this.price, required this.currency});

  final Decimal price;
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is HoldingPrice &&
      other.price == price &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(price, currency);

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
        return HoldingPrice(price: obs.price, currency: obs.currency);
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
  });

  final String assetId;
  final Decimal price;
  final String currency;
  final DateTime asOf;
}
