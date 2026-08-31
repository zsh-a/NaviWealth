import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_simulation_projection.dart';

void main() {
  test('weights available daily moves and reports missing quote weight', () {
    final projection = WatchlistSimulationProjection.calculate(
      positions: [
        WatchlistSimulationQuoteInput(
          watchlistItemId: 'aapl',
          targetWeight: Decimal.parse('0.5'),
          changePercent: Decimal.parse('0.02'),
        ),
        WatchlistSimulationQuoteInput(
          watchlistItemId: 'msft',
          targetWeight: Decimal.parse('0.3'),
          changePercent: Decimal.parse('-0.01'),
        ),
        WatchlistSimulationQuoteInput(
          watchlistItemId: 'missing',
          targetWeight: Decimal.parse('0.1'),
          changePercent: null,
        ),
      ],
      cashWeight: Decimal.parse('0.1'),
    );

    expect(projection.investedWeight, Decimal.parse('0.9'));
    expect(projection.pricedWeight, Decimal.parse('0.8'));
    expect(projection.missingQuoteWeight, Decimal.parse('0.1'));
    expect(projection.weightedDailyChange, Decimal.parse('0.007'));
    expect(
      projection.dailyMoveAmount(Decimal.parse('100000')),
      Decimal.parse('700'),
    );
  });

  test('equal weights sum exactly to one for repeating fractions', () {
    final weights = equalWatchlistSimulationWeights(['a', 'b', 'c']);

    expect(weights, hasLength(3));
    expect(
      weights.values.fold(Decimal.zero, (sum, weight) => sum + weight),
      Decimal.one,
    );
    expect(weights['a'], Decimal.parse('0.33333333'));
    expect(weights['c'], Decimal.parse('0.33333334'));
  });
}
