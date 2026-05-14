import 'package:decimal/decimal.dart';

import 'price_confidence.dart';

/// A single resolved valuation for an asset, regardless of where the value
/// came from (live provider, cached quote, synced `prices` ledger row,
/// historical bar close, or a manual entry).
///
/// Callers should never check the [source] string in business logic —
/// branch on [confidence] instead. The string is for diagnostics and the
/// AI caveat path only.
class ResolvedPrice {
  const ResolvedPrice({
    required this.value,
    required this.currency,
    required this.confidence,
    required this.source,
    required this.asOf,
    required this.fetchedAt,
    this.note,
  });

  /// Price per unit, in [currency]. Positive.
  final Decimal value;

  /// ISO-4217 code of [value]'s currency (e.g. `'USD'`, `'CNY'`).
  final String currency;

  /// Trust level. See [PriceConfidence] for the ordering.
  final PriceConfidence confidence;

  /// Free-form provenance string. Conventions:
  ///   - `'yfinance' | 'coingecko' | 'sina'` — live provider tag
  ///   - `'manual' | 'manual:adjust'`        — user-entered observation
  ///   - `'auto:<provider>'`                  — coordinator-written daily snapshot
  ///   - `'import:<broker>'`                  — broker import
  ///   - `'historical-bar'`                   — derived from a daily bar close
  final String source;

  /// Timestamp the price refers to (provider quote `asOf` or observation
  /// `observed_on`). Distinct from [fetchedAt].
  final DateTime asOf;

  /// When we learned about [value]. For provider hits this is "now"; for
  /// cache or ledger reads this is the cache write or observation insert.
  final DateTime fetchedAt;

  /// Optional human-readable note ("forward-filled 3d", "inverted from
  /// CNYUSD=X", ...). Surfaced only in diagnostics.
  final String? note;

  bool get isStale => confidence == PriceConfidence.stale;

  @override
  bool operator ==(Object other) =>
      other is ResolvedPrice &&
      other.value == value &&
      other.currency == currency &&
      other.confidence == confidence &&
      other.source == source &&
      other.asOf == asOf &&
      other.fetchedAt == fetchedAt &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    value,
    currency,
    confidence,
    source,
    asOf,
    fetchedAt,
    note,
  );

  @override
  String toString() =>
      'ResolvedPrice($value $currency, ${confidence.name}, $source @ $asOf)';
}
