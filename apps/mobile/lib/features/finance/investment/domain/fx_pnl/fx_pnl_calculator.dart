import 'package:decimal/decimal.dart';

import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';
import '../models/lot.dart';
import '../models/realized_pnl.dart';
import 'fx_pnl_breakdown.dart';

/// Pure calculator that splits base-currency P&L into market and FX legs
/// for both unrealized lots and realized sells.
///
/// All FX lookups go through a single injected [CurrencyConverter] so we
/// can swap the rate source (in-memory cache, Drift table, remote provider)
/// without touching the math.
///
/// The calculator does not aggregate: it returns one [FxPnLBreakdown] per
/// input. Callers that want per-asset / per-portfolio rollups sum the
/// results with [FxPnLBreakdown.+].
class FxPnLCalculator {
  FxPnLCalculator({required this.converter, required String baseCurrency})
    : baseCurrency = baseCurrency.trim().toUpperCase();

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Unrealized P&L decomposition for one open [lot] valued at [asOf]
  /// against [marketPricePerUnit] in [lot]'s asset currency.
  ///
  /// Closed lots (`remainingQuantity == 0`) return a zero breakdown — the
  /// realized leg is what the caller wants for those.
  ///
  /// Pass [marketPricePerUnit] = `null` when no quote is available; the
  /// market leg is then zero (the position contributes only its FX leg
  /// against cost basis), matching how [HoldingComputer] handles missing
  /// prices.
  FxPnLBreakdown unrealized({
    required Lot lot,
    required Decimal? marketPricePerUnit,
    required DateTime asOf,
  }) {
    if (lot.isClosed) return FxPnLBreakdown.zero(baseCurrency);

    final assetCurrency = lot.currency;
    final qty = lot.remainingQuantity;
    final costAsset = qty * lot.costPerUnit;
    final mvAsset = marketPricePerUnit == null
        ? Decimal.zero
        : qty * marketPricePerUnit;

    final fxAsOf = _rateAssetToBase(assetCurrency, on: asOf);
    final fxOpened = _rateAssetToBase(assetCurrency, on: lot.openedAt);

    // Market leg: (mv - cost) in asset, revalued at as-of FX.
    final marketPnLAsset = mvAsset - costAsset;
    final marketPnLInBase = marketPnLAsset * fxAsOf;

    // FX leg: cost basis revalued from open-day FX to as-of FX.
    final fxPnLInBase = costAsset * (fxAsOf - fxOpened);

    return FxPnLBreakdown(
      marketPnLInBase: marketPnLInBase,
      fxPnLInBase: fxPnLInBase,
      baseCurrency: baseCurrency,
    );
  }

  /// Realized P&L decomposition for one [RealizedPnL] record.
  ///
  /// The market leg is `(proceeds - fees - cost)` (all in asset currency)
  /// converted at the sell-day FX. The FX leg revalues the cost basis from
  /// the lot's open day to the sell day. Together they sum to
  /// `proceeds_at_sell_fx - cost_at_open_fx - fees_at_sell_fx` in base.
  FxPnLBreakdown realized(RealizedPnL r) {
    final fxOpened = _rateAssetToBase(r.currency, on: r.lotOpenedAt);
    final fxRealized = _rateAssetToBase(r.currency, on: r.realizedAt);
    final marketGainAsset = r.gain; // proceeds - fees - cost
    final marketPnLInBase = marketGainAsset * fxRealized;
    final fxPnLInBase = r.costBasis * (fxRealized - fxOpened);
    return FxPnLBreakdown(
      marketPnLInBase: marketPnLInBase,
      fxPnLInBase: fxPnLInBase,
      baseCurrency: baseCurrency,
    );
  }

  /// Sum a sequence of unrealized breakdowns. Convenience for portfolio-
  /// level rollups; semantically the same as folding `+` over the list.
  FxPnLBreakdown sum(Iterable<FxPnLBreakdown> parts) {
    var total = FxPnLBreakdown.zero(baseCurrency);
    for (final p in parts) {
      total = total + p;
    }
    return total;
  }

  /// Rate at which 1 unit of [assetCurrency] becomes [baseCurrency] at [on].
  /// Same-currency calls short-circuit at 1.
  Decimal _rateAssetToBase(String assetCurrency, {required DateTime on}) {
    if (assetCurrency.toUpperCase() == baseCurrency) return Decimal.one;
    final probe = Money(Decimal.one, assetCurrency);
    return converter.convert(probe, baseCurrency, on: on).amount;
  }
}
