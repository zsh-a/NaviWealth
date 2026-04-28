import 'package:decimal/decimal.dart';

enum BarInterval { day, week, month }

/// A single OHLCV bar.
///
/// `asOf` represents the bar's logical date (UTC, midnight) for daily / weekly
/// / monthly bars, not a wall-clock timestamp. Providers that return market
/// timezones must normalise before constructing.
class HistoricalBar {
  HistoricalBar({
    required this.symbol,
    required this.asOf,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
    this.adjustedClose,
  });

  final String symbol;
  final DateTime asOf;
  final Decimal open;
  final Decimal high;
  final Decimal low;
  final Decimal close;
  final int? volume;
  final Decimal? adjustedClose;
}
