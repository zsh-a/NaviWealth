import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/domain/dca/dca_simulator.dart';

Decimal d(String value) => Decimal.parse(value);

void main() {
  const engine = DcaSimulator();

  test('computes cumulative return, average cost, and zero drawdown', () {
    final result = engine.simulate(
      DcaSimulationInput(
        allocations: [DcaAllocation(symbol: 'VOO', weight: Decimal.one)],
        amountPerContribution: d('100'),
        currency: 'USD',
        from: DateTime.utc(2026, 1),
        to: DateTime.utc(2026, 2),
        frequency: DcaFrequency.monthly,
        priceSeries: {
          'VOO': [
            DcaPricePoint(asOf: DateTime.utc(2026, 1), close: d('10')),
            DcaPricePoint(asOf: DateTime.utc(2026, 2), close: d('20')),
          ],
        },
      ),
    );

    expect(result.totalInvested, d('200'));
    expect(result.endingValue, d('300'));
    expect(result.cumulativeReturn, d('0.5'));
    expect(result.positions.single.averageCost, d('13.3333333333333333'));
    expect(result.maxDrawdown, Decimal.zero);
  });

  test('reports drawdown and loss when prices fall', () {
    final result = engine.simulate(
      DcaSimulationInput(
        allocations: [DcaAllocation(symbol: 'VOO', weight: Decimal.one)],
        amountPerContribution: d('100'),
        currency: 'USD',
        from: DateTime.utc(2026, 1),
        to: DateTime.utc(2026, 3),
        frequency: DcaFrequency.monthly,
        priceSeries: {
          'VOO': [
            DcaPricePoint(asOf: DateTime.utc(2026, 1), close: d('20')),
            DcaPricePoint(asOf: DateTime.utc(2026, 2), close: d('30')),
            DcaPricePoint(asOf: DateTime.utc(2026, 3), close: d('10')),
          ],
        },
      ),
    );

    expect(result.totalInvested, d('300'));
    expect(result.cumulativeReturn < Decimal.zero, isTrue);
    expect(result.maxDrawdown > Decimal.zero, isTrue);
  });

  test('supports equal-weight baskets', () {
    final result = engine.simulate(
      DcaSimulationInput(
        allocations: [
          DcaAllocation(symbol: 'VOO', weight: d('0.5')),
          DcaAllocation(symbol: 'QQQ', weight: d('0.5')),
        ],
        amountPerContribution: d('200'),
        currency: 'USD',
        from: DateTime.utc(2026, 1),
        to: DateTime.utc(2026, 2),
        frequency: DcaFrequency.monthly,
        priceSeries: {
          'VOO': [
            DcaPricePoint(asOf: DateTime.utc(2026, 1), close: d('10')),
            DcaPricePoint(asOf: DateTime.utc(2026, 2), close: d('20')),
          ],
          'QQQ': [
            DcaPricePoint(asOf: DateTime.utc(2026, 1), close: d('20')),
            DcaPricePoint(asOf: DateTime.utc(2026, 2), close: d('20')),
          ],
        },
      ),
    );

    expect(result.positions, hasLength(2));
    expect(result.totalInvested, d('400'));
    expect(result.endingValue, d('500'));
    expect(result.cumulativeReturn, d('0.25'));
  });

  test(
    'returns empty metrics for zero amount, single missing series, or window',
    () {
      final noAmount = engine.simulate(
        DcaSimulationInput(
          allocations: [DcaAllocation(symbol: 'VOO', weight: Decimal.one)],
          amountPerContribution: Decimal.zero,
          currency: 'USD',
          from: DateTime.utc(2026, 1),
          to: DateTime.utc(2026, 2),
          frequency: DcaFrequency.monthly,
          priceSeries: const {},
        ),
      );
      final emptyWindow = engine.simulate(
        DcaSimulationInput(
          allocations: [DcaAllocation(symbol: 'VOO', weight: Decimal.one)],
          amountPerContribution: d('100'),
          currency: 'USD',
          from: DateTime.utc(2026, 2),
          to: DateTime.utc(2026, 1),
          frequency: DcaFrequency.monthly,
          priceSeries: const {},
        ),
      );

      expect(noAmount.isEmpty, isTrue);
      expect(noAmount.cumulativeReturn, Decimal.zero);
      expect(emptyWindow.isEmpty, isTrue);
    },
  );

  test('single period has zero max drawdown', () {
    final result = engine.simulate(
      DcaSimulationInput(
        allocations: [DcaAllocation(symbol: 'VOO', weight: Decimal.one)],
        amountPerContribution: d('100'),
        currency: 'USD',
        from: DateTime.utc(2026, 1),
        to: DateTime.utc(2026, 1, 28),
        frequency: DcaFrequency.monthly,
        priceSeries: {
          'VOO': [DcaPricePoint(asOf: DateTime.utc(2026, 1), close: d('10'))],
        },
      ),
    );

    expect(result.totalInvested, d('100'));
    expect(result.maxDrawdown, Decimal.zero);
  });
}
