import 'package:decimal/decimal.dart';

/// A point-in-time price snapshot for a symbol.
///
/// `price` and other monetary fields are kept in [Decimal] to avoid
/// accumulating float error when converting / aggregating downstream.
class Quote {
  Quote({
    required this.symbol,
    required this.currency,
    required this.price,
    required this.asOf,
    this.previousClose,
    this.open,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.exchange,
  });

  final String symbol;
  final String currency;
  final Decimal price;
  final DateTime asOf;
  final Decimal? previousClose;
  final Decimal? open;
  final Decimal? dayHigh;
  final Decimal? dayLow;
  final int? volume;
  final String? exchange;

  /// Net change vs. previous close.
  Decimal? get change => previousClose == null ? null : price - previousClose!;

  /// Percent change vs. previous close, in [0..1] convention.
  /// Returns null if previous close is missing or zero.
  Decimal? get changePercent {
    final prev = previousClose;
    if (prev == null || prev == Decimal.zero) return null;
    return ((price - prev) / prev).toDecimal(scaleOnInfinitePrecision: 6);
  }
}
