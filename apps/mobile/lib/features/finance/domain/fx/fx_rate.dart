import 'package:decimal/decimal.dart';

/// A single observed exchange rate: 1 [base] = [rate] [quote] on [date].
///
/// [date] is normalized to a UTC calendar day — FX is quoted per trading
/// day, and storing wall-clock instants makes "the rate on 2026-04-28"
/// queries ambiguous across time zones.
class FxRate {
  FxRate({
    required String base,
    required String quote,
    required DateTime date,
    required this.rate,
    required this.source,
    DateTime? fetchedAt,
  }) : base = _normalizeCurrency(base, 'base'),
       quote = _normalizeCurrency(quote, 'quote'),
       date = _normalizeDay(date),
       fetchedAt = _normalizeFetchedAt(fetchedAt, date) {
    if (rate <= Decimal.zero) {
      throw ArgumentError.value(rate, 'rate', 'must be positive');
    }
    if (this.base == this.quote) {
      throw ArgumentError(
        'base and quote must differ; got both = ${this.base}',
      );
    }
  }

  final String base;
  final String quote;
  final DateTime date;
  final Decimal rate;
  final String source;

  /// Instant when this observation was fetched or manually recorded. It is
  /// intentionally separate from [date], which is the provider's market day.
  final DateTime fetchedAt;

  /// The inverse quote: 1 [quote] = `1 / rate` [base], same date and source.
  FxRate inverse() => FxRate(
    base: quote,
    quote: base,
    date: date,
    rate: (Decimal.one / rate).toDecimal(scaleOnInfinitePrecision: 20),
    source: source,
    fetchedAt: fetchedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is FxRate &&
      other.base == base &&
      other.quote == quote &&
      other.date == date &&
      other.rate == rate &&
      other.source == source &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(base, quote, date, rate, source, fetchedAt);

  @override
  String toString() =>
      'FxRate($base→$quote @ ${date.toIso8601String().substring(0, 10)} '
      '= $rate, src=$source)';

  static String _normalizeCurrency(String code, String field) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, field, 'must not be empty');
    }
    return trimmed.toUpperCase();
  }

  static DateTime _normalizeDay(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  static DateTime _normalizeFetchedAt(DateTime? value, DateTime fallback) =>
      (value ?? DateTime.utc(fallback.year, fallback.month, fallback.day))
          .toUtc();
}
