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
