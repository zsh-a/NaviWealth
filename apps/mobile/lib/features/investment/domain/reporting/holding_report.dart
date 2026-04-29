import 'package:decimal/decimal.dart';

import '../../../../domain/services/currency_converter.dart';
import '../../../../domain/values/money.dart';
import '../fx_pnl/fx_pnl_breakdown.dart';
import '../fx_pnl/fx_pnl_calculator.dart';
import '../holding_price_source.dart';
import '../models/lot.dart';

/// Per-asset reporting row that splits the **本币口径** (asset-currency view)
/// from the **折算口径** (base-currency view), and inside the base view
/// distinguishes the market leg from the FX leg.
///
/// Storage layout mirrors the user-facing report:
///
/// - **Native columns** (`*InAsset`): cost, market value, P&L all in the
///   asset's own currency. These match what a single-currency broker
///   statement would show.
/// - **Base columns** (`*InBase` / [pnlBreakdown]): everything translated
///   into the user's base currency, with the FX revaluation of cost basis
///   pulled out as a separate line so the user can see how much of the
///   change is "the asset moved" vs "the currency moved".
///
/// Identity:
///
/// ```
/// totalPnLInBase
///   = pnlBreakdown.totalPnLInBase
///   = marketValueInBase - costBasisAtOpenFxInBase
/// ```
class AssetHoldingReport {
  const AssetHoldingReport({
    required this.assetId,
    required this.assetCurrency,
    required this.quantity,
    required this.costBasisInAsset,
    required this.marketValueInAsset,
    required this.unrealizedPnlInAsset,
    required this.costBasisAtOpenFxInBase,
    required this.marketValueInBase,
    required this.pnlBreakdown,
    required this.baseCurrency,
    required this.asOf,
  });

  final String assetId;
  final String assetCurrency;
  final Decimal quantity;

  /// Cost in asset currency: `Σ remainingQuantity * costPerUnit`.
  final Decimal costBasisInAsset;

  /// Market value in asset currency: `quantity * price` for asset-priced
  /// inputs. Zero when no price is available.
  final Decimal marketValueInAsset;

  /// `marketValueInAsset - costBasisInAsset`.
  final Decimal unrealizedPnlInAsset;

  /// Cost basis converted at the **open-day FX** for each lot, summed —
  /// i.e. what the user actually paid in base currency at the time. This
  /// is the anchor against which [pnlBreakdown] is decomposed.
  final Decimal costBasisAtOpenFxInBase;

  /// Market value translated at the as-of FX rate.
  final Decimal marketValueInBase;

  /// Total base-currency P&L, split into market and FX legs.
  final FxPnLBreakdown pnlBreakdown;

  final String baseCurrency;
  final DateTime asOf;

  /// Convenience: total base-currency P&L (market + FX).
  Decimal get totalPnlInBase => pnlBreakdown.totalPnLInBase;
}

/// Portfolio-level rollup of [AssetHoldingReport]s.
class PortfolioHoldingReport {
  const PortfolioHoldingReport({
    required this.assets,
    required this.totalCostBasisAtOpenFxInBase,
    required this.totalMarketValueInBase,
    required this.totalPnlBreakdown,
    required this.baseCurrency,
    required this.asOf,
  });

  /// Per-asset breakdowns keyed by `assetId`.
  final Map<String, AssetHoldingReport> assets;
  final Decimal totalCostBasisAtOpenFxInBase;
  final Decimal totalMarketValueInBase;
  final FxPnLBreakdown totalPnlBreakdown;
  final String baseCurrency;
  final DateTime asOf;
}

/// Builds a [PortfolioHoldingReport] from a flat list of lots.
///
/// Sits one layer above [HoldingComputer]: the computer answers "what does
/// the portfolio look like in base currency at as-of FX?", while this
/// service answers "what does the portfolio look like in *both* asset
/// currency and base currency, with FX explicitly split out?".
class HoldingReportService {
  HoldingReportService({
    required this.converter,
    required String baseCurrency,
    required this.prices,
  }) : baseCurrency = baseCurrency.trim().toUpperCase(),
       _fx = FxPnLCalculator(
         converter: converter,
         baseCurrency: baseCurrency,
       );

  final CurrencyConverter converter;
  final HoldingPriceSource prices;
  final String baseCurrency;
  final FxPnLCalculator _fx;

  /// Build a per-asset / portfolio report from [lots] valued at [asOf].
  PortfolioHoldingReport build({
    required Iterable<Lot> lots,
    required DateTime asOf,
  }) {
    // Accumulate by asset; lots may belong to multiple accounts but the
    // user-facing report aggregates at the asset level.
    final byAsset = <String, _AssetAggregate>{};
    final byAssetFxParts = <String, List<FxPnLBreakdown>>{};

    for (final l in lots) {
      if (l.isClosed) continue;
      final agg = byAsset.putIfAbsent(
        l.assetId,
        () => _AssetAggregate(currency: l.currency),
      );
      if (agg.currency != l.currency) {
        throw StateError(
          'Asset ${l.assetId} has lots in mixed currencies '
          '(${agg.currency} vs ${l.currency}); the holding report requires '
          'an asset to be denominated in a single currency.',
        );
      }
      agg.quantity += l.remainingQuantity;
      agg.costBasisInAsset += l.remainingQuantity * l.costPerUnit;

      final priceObs = prices.priceFor(l.assetId, asOf: asOf);
      final perLotFx = _fx.unrealized(
        lot: l,
        marketPricePerUnit: priceObs?.price,
        asOf: asOf,
      );
      byAssetFxParts.putIfAbsent(l.assetId, () => []).add(perLotFx);
    }

    final assets = <String, AssetHoldingReport>{};
    var totalCostBase = Decimal.zero;
    var totalMvBase = Decimal.zero;
    var totalPnl = FxPnLBreakdown.zero(baseCurrency);

    for (final entry in byAsset.entries) {
      final assetId = entry.key;
      final agg = entry.value;

      final priceObs = prices.priceFor(assetId, asOf: asOf);
      final mvAsset = priceObs == null
          ? Decimal.zero
          : agg.quantity * priceObs.price;
      final unrealAsset = mvAsset - agg.costBasisInAsset;

      final assetPnl = _fx.sum(byAssetFxParts[assetId] ?? const []);

      // Translate market value at as-of FX.
      final mvBase = priceObs == null
          ? Decimal.zero
          : converter
                .convert(Money(mvAsset, agg.currency), baseCurrency, on: asOf)
                .amount;
      // costBasisAtOpenFxInBase derived from the breakdown identity:
      // mvBase - assetPnl.totalPnLInBase = Σ_lot cost_asset * fxOpen.
      final costAtOpenFxBase = mvBase - assetPnl.totalPnLInBase;

      assets[assetId] = AssetHoldingReport(
        assetId: assetId,
        assetCurrency: agg.currency,
        quantity: agg.quantity,
        costBasisInAsset: agg.costBasisInAsset,
        marketValueInAsset: mvAsset,
        unrealizedPnlInAsset: unrealAsset,
        costBasisAtOpenFxInBase: costAtOpenFxBase,
        marketValueInBase: mvBase,
        pnlBreakdown: assetPnl,
        baseCurrency: baseCurrency,
        asOf: asOf,
      );

      totalCostBase += costAtOpenFxBase;
      totalMvBase += mvBase;
      totalPnl = totalPnl + assetPnl;
    }

    return PortfolioHoldingReport(
      assets: assets,
      totalCostBasisAtOpenFxInBase: totalCostBase,
      totalMarketValueInBase: totalMvBase,
      totalPnlBreakdown: totalPnl,
      baseCurrency: baseCurrency,
      asOf: asOf,
    );
  }
}

class _AssetAggregate {
  _AssetAggregate({required this.currency});
  final String currency;
  Decimal quantity = Decimal.zero;
  Decimal costBasisInAsset = Decimal.zero;
}
