import 'package:decimal/decimal.dart';

/// Per-asset valuation lookup used by [NetWorthService] to price holdings on
/// historical sample dates.
///
/// Implementations may be backed by:
/// - A market-data feed cache (stocks / ETFs / crypto), keyed by symbol with
///   one bar per trading day.
/// - User-entered valuation snapshots for non-market assets such as real
///   estate or vehicles. These are typically fed from a sequence of
///   `valuationAdjust` transactions where each adjustment becomes a new
///   `(date, price)` pair with quantity treated as 1.
///
/// All methods are pure: they observe the price book without mutating it.
abstract class AssetPriceSource {
  /// Returns the per-unit price of [assetId] on [on], in the asset's native
  /// currency. The lookup falls back to the most recent observation **on
  /// or before** [on] (FX-style backfill — no future-leak).
  ///
  /// Returns `null` when no observation exists on or before [on]. Callers
  /// treat this as "the asset contributes 0 to net worth at that date" so
  /// recently-purchased assets do not retroactively appear before they were
  /// owned.
  Decimal? priceOn(String assetId, DateTime on);

  /// The currency [priceOn] is quoted in for [assetId]. Returns `null` for
  /// unknown assets — callers should skip such positions.
  String? currencyOf(String assetId);
}

/// In-memory [AssetPriceSource] backed by a per-asset list of observations.
///
/// Suitable for tests and for the warm in-memory cache that sits in front of
/// the persistent market-data store. Observations may be inserted in any
/// order; the ctor sorts them by date for binary-search lookup.
class InMemoryAssetPriceSource implements AssetPriceSource {
  InMemoryAssetPriceSource(Iterable<AssetPriceObservation> observations) {
    for (final obs in observations) {
      _byAsset.putIfAbsent(obs.assetId, () => []).add(obs);
      final existingCcy = _currency[obs.assetId];
      if (existingCcy != null && existingCcy != obs.currency) {
        throw ArgumentError(
          'Asset ${obs.assetId} has mixed currencies: '
          '$existingCcy vs ${obs.currency}.',
        );
      }
      _currency[obs.assetId] = obs.currency;
    }
    for (final list in _byAsset.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
  }

  final Map<String, List<AssetPriceObservation>> _byAsset = {};
  final Map<String, String> _currency = {};

  @override
  Decimal? priceOn(String assetId, DateTime on) {
    final list = _byAsset[assetId];
    if (list == null || list.isEmpty) return null;
    final cutoff = DateTime.utc(on.year, on.month, on.day);
    // List is sorted ascending; binary search for the rightmost entry
    // with date <= cutoff.
    var lo = 0;
    var hi = list.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!list[mid].date.isAfter(cutoff)) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return null;
    return list[found].price;
  }

  @override
  String? currencyOf(String assetId) => _currency[assetId];
}

/// One price observation: [assetId] traded at [price] [currency] on [date].
class AssetPriceObservation {
  AssetPriceObservation({
    required String assetId,
    required this.price,
    required String currency,
    required DateTime date,
  }) : assetId = assetId.trim(),
       currency = _normalizeCurrency(currency),
       date = DateTime.utc(date.year, date.month, date.day) {
    if (this.assetId.isEmpty) {
      throw ArgumentError.value(assetId, 'assetId', 'must not be empty');
    }
    if (price < Decimal.zero) {
      throw ArgumentError.value(price, 'price', 'must be non-negative');
    }
  }

  final String assetId;
  final Decimal price;
  final String currency;
  final DateTime date;

  static String _normalizeCurrency(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'currency', 'must not be empty');
    }
    return trimmed.toUpperCase();
  }
}
