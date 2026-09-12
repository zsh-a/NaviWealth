import 'package:decimal/decimal.dart';

class WatchlistSimulationQuoteInput {
  const WatchlistSimulationQuoteInput({
    required this.watchlistItemId,
    required this.targetWeight,
    required this.changePercent,
  });

  final String watchlistItemId;
  final Decimal targetWeight;
  final Decimal? changePercent;
}

/// Point-in-time paper allocation projection.
///
/// Relative daily moves are currency-invariant, so this projection does not
/// fabricate FX conversions. Missing quotes reduce [pricedWeight]. It also
/// deliberately does not claim a historical NAV: that would require an
/// explicit FX series plus split/dividend adjustment policy.
class WatchlistSimulationProjection {
  const WatchlistSimulationProjection({
    required this.investedWeight,
    required this.cashWeight,
    required this.pricedWeight,
    required this.missingQuoteWeight,
    required this.weightedDailyChange,
  });

  final Decimal investedWeight;
  final Decimal cashWeight;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
  final Decimal weightedDailyChange;

  factory WatchlistSimulationProjection.calculate({
    required Iterable<WatchlistSimulationQuoteInput> positions,
    required Decimal cashWeight,
  }) {
    var investedWeight = Decimal.zero;
    var pricedWeight = Decimal.zero;
    var missingQuoteWeight = Decimal.zero;
    var weightedDailyChange = Decimal.zero;
    for (final position in positions) {
      investedWeight += position.targetWeight;
      final change = position.changePercent;
      if (change == null) {
        missingQuoteWeight += position.targetWeight;
      } else {
        pricedWeight += position.targetWeight;
        weightedDailyChange += position.targetWeight * change;
      }
    }
    return WatchlistSimulationProjection(
      investedWeight: investedWeight,
      cashWeight: cashWeight,
      pricedWeight: pricedWeight,
      missingQuoteWeight: missingQuoteWeight,
      weightedDailyChange: weightedDailyChange,
    );
  }

  Decimal dailyMoveAmount(Decimal startingCapital) =>
      startingCapital * weightedDailyChange;
}

/// One position's contribution to a day's weighted move.
///
/// A position without a usable quote contributes nothing and is reported as
/// `null` so the UI can mark it as unpriced instead of printing a fake `0.00%`.
Decimal? watchlistSimulationContribution({
  required Decimal targetWeight,
  required Decimal? changePercent,
}) {
  if (changePercent == null) return null;
  return targetWeight * changePercent;
}

/// Paper performance since the simulation baseline.
///
/// Derived purely from the observed value series, so it inherits the same
/// limits as [WatchlistSimulationProjection]: it is a chain of observed daily
/// moves, not a reconstructed historical NAV. It is the headline answer to
/// "how is this basket doing since I set it up", which the point-in-time
/// projection alone cannot express.
class WatchlistSimulationPerformance {
  const WatchlistSimulationPerformance({
    required this.latestValue,
    required this.cumulativeChange,
    required this.cumulativeReturn,
    required this.observationCount,
  });

  /// Most recent observed project value, in the simulation base currency.
  final Decimal latestValue;

  /// `latestValue - startingCapital`.
  final Decimal cumulativeChange;

  /// Ratio (not percentage points): `0.0321` means `+3.21%`.
  final Decimal cumulativeReturn;

  final int observationCount;

  /// Whether the series has moved beyond the creation baseline.
  bool get hasMoved => observationCount > 1;

  static WatchlistSimulationPerformance? fromSeries({
    required Iterable<Decimal> projectedValues,
    required Decimal startingCapital,
  }) {
    Decimal? latest;
    var count = 0;
    for (final value in projectedValues) {
      latest = value;
      count++;
    }
    if (latest == null || startingCapital <= Decimal.zero) return null;
    final change = latest - startingCapital;
    return WatchlistSimulationPerformance(
      latestValue: latest,
      cumulativeChange: change,
      cumulativeReturn: (change / startingCapital).toDecimal(
        scaleOnInfinitePrecision: 6,
      ),
      observationCount: count,
    );
  }
}

Map<String, Decimal> equalWatchlistSimulationWeights(
  Iterable<String> watchlistItemIds,
) {
  final ids = watchlistItemIds.toList(growable: false);
  if (ids.isEmpty) return const {};
  if (ids.toSet().length != ids.length) {
    throw ArgumentError('Watchlist simulation item ids must be unique.');
  }
  final ordinary = (Decimal.one / Decimal.fromInt(ids.length)).toDecimal(
    scaleOnInfinitePrecision: 8,
  );
  var remaining = Decimal.one;
  final result = <String, Decimal>{};
  for (var index = 0; index < ids.length; index++) {
    final weight = index == ids.length - 1 ? remaining : ordinary;
    result[ids[index]] = weight;
    remaining -= weight;
  }
  return Map<String, Decimal>.unmodifiable(result);
}
