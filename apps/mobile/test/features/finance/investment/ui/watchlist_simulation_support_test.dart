import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_simulation_projection.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_simulation_support.dart';

Decimal _sumOf(Iterable<String> texts) => texts.fold(
  Decimal.zero,
  (sum, text) => sum + Decimal.parse(text),
);

void main() {
  test('equal split prints two decimals that still total the budget', () {
    final texts = watchlistSimulationSplitPercentTexts(
      ids: const ['a', 'b', 'c'],
      totalPercent: Decimal.fromInt(100),
    );

    expect(texts.values, ['33.33', '33.33', '33.34']);
    expect(_sumOf(texts.values), Decimal.fromInt(100));
  });

  test('equal split respects virtual cash', () {
    final texts = watchlistSimulationSplitPercentTexts(
      ids: const ['a', 'b', 'c'],
      totalPercent: Decimal.fromInt(90),
    );

    expect(texts.values, ['30.00', '30.00', '30.00']);
    expect(
      _sumOf(texts.values) + Decimal.fromInt(10),
      Decimal.fromInt(100),
    );
  });

  test('equal split is empty without ids', () {
    expect(
      watchlistSimulationSplitPercentTexts(
        ids: const [],
        totalPercent: Decimal.fromInt(100),
      ),
      isEmpty,
    );
  });

  test('snapping stored ratios yields a valid 100% starting state', () {
    final ratios = equalWatchlistSimulationWeights([
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
    ]);

    final texts = watchlistSimulationSnapPercentTexts(
      ids: ratios.keys.toList(growable: false),
      ratiosById: ratios,
      cashPercentText: '0',
    );

    expect(texts, hasLength(6));
    expect(_sumOf(texts.values), Decimal.fromInt(100));
  });

  test('snapping keeps the cash allocation out of the position budget', () {
    final ratios = <String, Decimal>{
      'a': Decimal.parse('0.33333333'),
      'b': Decimal.parse('0.33333333'),
      'c': Decimal.parse('0.33333334'),
    };

    final texts = watchlistSimulationSnapPercentTexts(
      ids: ratios.keys.toList(growable: false),
      ratiosById: ratios,
      cashPercentText: '10',
    );

    expect(texts.values, ['30.00', '30.00', '30.00']);
    expect(_sumOf(texts.values), Decimal.fromInt(90));
  });

  test('snapping falls back to an equal split when nothing is stored yet', () {
    final texts = watchlistSimulationSnapPercentTexts(
      ids: const ['a', 'b'],
      ratiosById: const {},
      cashPercentText: '20',
    );

    expect(texts.values, ['40.00', '40.00']);
    expect(_sumOf(texts.values), Decimal.fromInt(80));
  });

  test('percent text and ratio conversion round-trip at two decimals', () {
    expect(
      watchlistSimulationPercentText(Decimal.parse('0.16666667')),
      '16.67',
    );
    expect(watchlistSimulationPercentText(Decimal.zero), '0');
    expect(
      watchlistSimulationPercentToRatio(Decimal.parse('16.66')),
      Decimal.parse('0.1666'),
    );
  });

  test('symbol labels fall back to the encoded watchlist item id', () {
    expect(watchlistSimulationSymbolFromId('us_stock:AAPL'), 'AAPL');
    expect(watchlistSimulationSymbolFromId('AAPL'), 'AAPL');
    expect(
      watchlistSimulationSymbolLabel(null, fallbackId: 'hk_stock:0700'),
      '0700',
    );
  });
}
