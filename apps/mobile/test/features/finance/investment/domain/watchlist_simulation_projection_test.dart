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

  test('contribution reports an unpriced position as unknown, not zero', () {
    expect(
      watchlistSimulationContribution(
        targetWeight: Decimal.parse('0.25'),
        changePercent: Decimal.parse('0.04'),
      ),
      Decimal.parse('0.01'),
    );
    expect(
      watchlistSimulationContribution(
        targetWeight: Decimal.parse('0.25'),
        changePercent: null,
      ),
      isNull,
    );
  });

  test('performance measures the observed series against starting capital', () {
    final performance = WatchlistSimulationPerformance.fromSeries(
      projectedValues: [
        Decimal.parse('100000'),
        Decimal.parse('101000'),
        Decimal.parse('103030'),
      ],
      startingCapital: Decimal.parse('100000'),
    );

    expect(performance, isNotNull);
    expect(performance!.latestValue, Decimal.parse('103030'));
    expect(performance.cumulativeChange, Decimal.parse('3030'));
    expect(performance.cumulativeReturn, Decimal.parse('0.0303'));
    expect(performance.observationCount, 3);
    expect(performance.hasMoved, isTrue);
  });

  test('performance reports a baseline-only series as unmoved', () {
    final performance = WatchlistSimulationPerformance.fromSeries(
      projectedValues: [Decimal.parse('100000')],
      startingCapital: Decimal.parse('100000'),
    );

    expect(performance!.observationCount, 1);
    expect(performance.cumulativeReturn, Decimal.zero);
    expect(performance.hasMoved, isFalse);
  });

  test('performance is unavailable without observations or capital', () {
    expect(
      WatchlistSimulationPerformance.fromSeries(
        projectedValues: const [],
        startingCapital: Decimal.parse('100000'),
      ),
      isNull,
    );
    expect(
      WatchlistSimulationPerformance.fromSeries(
        projectedValues: [Decimal.parse('100')],
        startingCapital: Decimal.zero,
      ),
      isNull,
    );
  });
}
