import 'package:decimal/decimal.dart';

/// Decomposition of base-currency P&L into a "pure market" leg and a
/// "currency revaluation" leg.
///
/// Identity (per lot):
///
/// ```
/// totalPnLInBase = (mvAsset - costAsset) * fxAsOf
///                + costAsset           * (fxAsOf - fxOpened)
///                = mvAsset * fxAsOf - costAsset * fxOpened
/// ```
///
/// - [marketPnLInBase]: gain from price movement, valued at the as-of FX
///   rate. This is what the user "feels" in their base currency from the
///   asset's price moving — independent of the FX leg.
/// - [fxPnLInBase]: gain from currency revaluation of the cost basis.
///   Positive when the asset currency strengthened against base since the
///   lot was opened.
///
/// For realized records, the same identity holds with `fxAsOf` replaced
/// by the sell-day FX. Both legs are denominated in [baseCurrency].
class FxPnLBreakdown {
  const FxPnLBreakdown({
    required this.marketPnLInBase,
    required this.fxPnLInBase,
    required this.baseCurrency,
  });

  factory FxPnLBreakdown.zero(String baseCurrency) => FxPnLBreakdown(
    marketPnLInBase: Decimal.zero,
    fxPnLInBase: Decimal.zero,
    baseCurrency: baseCurrency.trim().toUpperCase(),
  );

  final Decimal marketPnLInBase;
  final Decimal fxPnLInBase;
  final String baseCurrency;

  Decimal get totalPnLInBase => marketPnLInBase + fxPnLInBase;

  FxPnLBreakdown operator +(FxPnLBreakdown other) {
    if (other.baseCurrency != baseCurrency) {
      throw ArgumentError(
        'Cannot sum FxPnLBreakdown across base currencies: '
        '$baseCurrency vs ${other.baseCurrency}',
      );
    }
    return FxPnLBreakdown(
      marketPnLInBase: marketPnLInBase + other.marketPnLInBase,
      fxPnLInBase: fxPnLInBase + other.fxPnLInBase,
      baseCurrency: baseCurrency,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FxPnLBreakdown &&
        other.marketPnLInBase == marketPnLInBase &&
        other.fxPnLInBase == fxPnLInBase &&
        other.baseCurrency == baseCurrency;
  }

  @override
  int get hashCode => Object.hash(marketPnLInBase, fxPnLInBase, baseCurrency);

  @override
  String toString() =>
      'FxPnLBreakdown(market: $marketPnLInBase, fx: $fxPnLInBase, '
      'total: $totalPnLInBase $baseCurrency)';
}
