import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/fx_pnl/fx_pnl_calculator.dart';
import 'package:naviwealth/features/investment/domain/models/realized_pnl.dart';

import '../_helpers.dart';

void main() {
  // Build a converter where 1 USD costs `rate` CNY on the requested day.
  CurrencyConverter cny(List<MapEntry<DateTime, String>> usdToCnyRates) {
    final rates = [
      for (final e in usdToCnyRates)
        FxRate(
          base: 'USD',
          quote: 'CNY',
          date: e.key,
          rate: Decimal.parse(e.value),
          source: 'test',
        ),
    ];
    return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
  }

  group('FxPnLCalculator.unrealized', () {
    final openedAt = DateTime.utc(2026, 1, 1);
    final asOf = DateTime.utc(2026, 4, 1);

    test('USD lot with no FX move: only the market leg contributes', () {
      final converter = cny([
        MapEntry(openedAt, '7.00'),
        MapEntry(asOf, '7.00'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: d('170'), // up $20/share
        asOf: asOf,
      );
      // marketPnL_asset = 100 * (170 - 150) = 2000 USD; * 7 = 14000 CNY
      expect(breakdown.marketPnLInBase, d('14000.00'));
      // No FX move
      expect(breakdown.fxPnLInBase, Decimal.zero);
      expect(breakdown.totalPnLInBase, d('14000.00'));
    });

    test('USD lot with FX appreciation: separate FX and market legs', () {
      final converter = cny([
        MapEntry(openedAt, '7.00'),
        MapEntry(asOf, '7.50'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: d('170'),
        asOf: asOf,
      );
      // marketPnL_base = 100 * (170 - 150) * 7.5 = 15000
      expect(breakdown.marketPnLInBase, d('15000.00'));
      // fxPnL_base = (100 * 150) * (7.5 - 7.0) = 7500
      expect(breakdown.fxPnLInBase, d('7500.00'));
      // identity check: mv * fx_now - cost * fx_open
      // 100 * 170 * 7.5 - 100 * 150 * 7.0 = 127500 - 105000 = 22500
      expect(breakdown.totalPnLInBase, d('22500.00'));
    });

    test('FX depreciation produces a negative FX leg', () {
      final converter = cny([
        MapEntry(openedAt, '7.50'),
        MapEntry(asOf, '7.00'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: d('150'), // unchanged
        asOf: asOf,
      );
      expect(breakdown.marketPnLInBase, Decimal.zero);
      // (100 * 150) * (7.0 - 7.5) = -7500
      expect(breakdown.fxPnLInBase, d('-7500.00'));
      expect(breakdown.totalPnLInBase, d('-7500.00'));
    });

    test('lot in base currency yields zero FX leg', () {
      final converter = cny([MapEntry(openedAt, '7.00')]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'CNY',
        originalQuantity: d('100'),
        costPerUnit: d('10'),
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: d('15'),
        asOf: asOf,
      );
      expect(breakdown.fxPnLInBase, Decimal.zero);
      expect(breakdown.marketPnLInBase, d('500'));
      expect(breakdown.totalPnLInBase, d('500'));
    });

    test('null price means no market leg, but FX leg still revalues cost', () {
      final converter = cny([
        MapEntry(openedAt, '7.00'),
        MapEntry(asOf, '7.20'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: null,
        asOf: asOf,
      );
      // mv = 0 → marketPnL_asset = -cost = -15000; * 7.2 = -108000
      expect(breakdown.marketPnLInBase, d('-108000.0'));
      // fx leg: 15000 * 0.2 = 3000
      expect(breakdown.fxPnLInBase, d('3000.00'));
    });

    test('closed lot returns zero', () {
      final converter = cny([MapEntry(openedAt, '7.00')]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot = makeLot(
        currency: 'USD',
        originalQuantity: d('100'),
        remainingQuantity: Decimal.zero,
      );
      final breakdown = calc.unrealized(
        lot: lot,
        marketPricePerUnit: d('999'),
        asOf: asOf,
      );
      expect(breakdown.marketPnLInBase, Decimal.zero);
      expect(breakdown.fxPnLInBase, Decimal.zero);
    });
  });

  group('FxPnLCalculator.realized', () {
    final openedAt = DateTime.utc(2026, 1, 1);
    final realizedAt = DateTime.utc(2026, 6, 1);

    test('cross-currency realized P&L splits market and FX legs', () {
      final converter = cny([
        MapEntry(openedAt, '7.00'),
        MapEntry(realizedAt, '7.50'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final r = RealizedPnL(
        id: 'r-1',
        sellTransactionId: 'tx-sell',
        lotId: 'l-1',
        accountId: 'a',
        assetId: 'AAPL',
        currency: 'USD',
        quantity: d('50'),
        costBasis: d('5000'), // 50 * 100
        proceeds: d('6000'), // 50 * 120
        fees: d('10'),
        realizedAt: realizedAt,
        lotOpenedAt: openedAt,
      );
      final breakdown = calc.realized(r);
      // market: gain_asset = (6000 - 10 - 5000) = 990; * 7.5 = 7425
      expect(breakdown.marketPnLInBase, d('7425.00'));
      // fx leg: cost * (sell_fx - open_fx) = 5000 * 0.5 = 2500
      expect(breakdown.fxPnLInBase, d('2500.00'));
      // identity: proceeds_at_sell - fees_at_sell - cost_at_open
      // (6000 - 10) * 7.5 - 5000 * 7 = 44925 - 35000 = 9925
      expect(breakdown.totalPnLInBase, d('9925.00'));
    });
  });

  group('FxPnLCalculator.sum', () {
    test('sums multiple breakdowns into a total in the same base currency', () {
      final converter = cny([
        MapEntry(DateTime.utc(2026, 1, 1), '7.00'),
        MapEntry(DateTime.utc(2026, 4, 1), '7.20'),
      ]);
      final calc = FxPnLCalculator(converter: converter, baseCurrency: 'CNY');
      final lot1 = makeLot(
        id: 'l-1',
        day: 0,
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final lot2 = makeLot(
        id: 'l-2',
        day: 0,
        currency: 'USD',
        originalQuantity: d('50'),
        costPerUnit: d('100'),
      );
      final asOf = DateTime.utc(2026, 4, 1);
      final parts = [
        calc.unrealized(lot: lot1, marketPricePerUnit: d('160'), asOf: asOf),
        calc.unrealized(lot: lot2, marketPricePerUnit: d('110'), asOf: asOf),
      ];
      final total = calc.sum(parts);
      expect(
        total.totalPnLInBase,
        parts[0].totalPnLInBase + parts[1].totalPnLInBase,
      );
      expect(total.baseCurrency, 'CNY');
    });
  });
}
