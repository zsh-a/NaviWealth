import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/investment/domain/reporting/holding_report.dart';

import '../_helpers.dart';

void main() {
  CurrencyConverter usdCnyAt(String openRate, String asOfRate) {
    return FxRateCurrencyConverter(
      InMemoryFxRateLookup([
        FxRate(
          base: 'USD',
          quote: 'CNY',
          date: DateTime.utc(2026, 1, 1),
          rate: Decimal.parse(openRate),
          source: 'test',
        ),
        FxRate(
          base: 'USD',
          quote: 'CNY',
          date: DateTime.utc(2026, 4, 1),
          rate: Decimal.parse(asOfRate),
          source: 'test',
        ),
      ]),
    );
  }

  group('HoldingReportService.build', () {
    test('USD lot in a CNY portfolio surfaces native AND base columns plus '
        'FX-split P&L', () {
      final converter = usdCnyAt('7.00', '7.50');
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('170'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final service = HoldingReportService(
        converter: converter,
        baseCurrency: 'CNY',
        prices: prices,
      );

      final lot = makeLot(
        assetId: 'AAPL',
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
        // openedAt = 2026-01-01 via day=0 default
      );
      final report = service.build(
        lots: [lot],
        asOf: DateTime.utc(2026, 4, 1),
      );

      expect(report.assets, hasLength(1));
      final aapl = report.assets['AAPL']!;

      // Native (USD) view
      expect(aapl.assetCurrency, 'USD');
      expect(aapl.costBasisInAsset, d('15000'));
      expect(aapl.marketValueInAsset, d('17000'));
      expect(aapl.unrealizedPnlInAsset, d('2000'));

      // Base (CNY) view
      expect(aapl.baseCurrency, 'CNY');
      // mvBase = 17000 * 7.5 = 127500
      expect(aapl.marketValueInBase, d('127500.00'));
      // costBasisAtOpenFxInBase = 15000 * 7 = 105000
      expect(aapl.costBasisAtOpenFxInBase, d('105000.00'));

      // P&L breakdown
      // marketPnL_base = 2000 * 7.5 = 15000
      expect(aapl.pnlBreakdown.marketPnLInBase, d('15000.00'));
      // fxPnL_base = 15000 * 0.5 = 7500
      expect(aapl.pnlBreakdown.fxPnLInBase, d('7500.00'));
      // total = 22500 = mvBase - costAtOpen
      expect(aapl.totalPnlInBase, d('22500.00'));

      // Portfolio rollup matches
      expect(report.totalMarketValueInBase, aapl.marketValueInBase);
      expect(report.totalCostBasisAtOpenFxInBase, aapl.costBasisAtOpenFxInBase);
      expect(
        report.totalPnlBreakdown.totalPnLInBase,
        aapl.totalPnlInBase,
      );
    });

    test('aggregates lots from multiple accounts under one asset row', () {
      final converter = usdCnyAt('7.00', '7.00');
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('160'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final service = HoldingReportService(
        converter: converter,
        baseCurrency: 'CNY',
        prices: prices,
      );

      final l1 = makeLot(
        id: 'l-1',
        accountId: 'broker-A',
        assetId: 'AAPL',
        currency: 'USD',
        originalQuantity: d('100'),
        costPerUnit: d('150'),
      );
      final l2 = makeLot(
        id: 'l-2',
        accountId: 'broker-B',
        assetId: 'AAPL',
        currency: 'USD',
        originalQuantity: d('50'),
        costPerUnit: d('140'),
      );
      final report = service.build(
        lots: [l1, l2],
        asOf: DateTime.utc(2026, 4, 1),
      );

      final aapl = report.assets['AAPL']!;
      expect(aapl.quantity, d('150'));
      // costAsset = 100*150 + 50*140 = 22000
      expect(aapl.costBasisInAsset, d('22000'));
      // mvAsset = 150 * 160 = 24000
      expect(aapl.marketValueInAsset, d('24000'));
    });

    test('rejects mixed-currency lots for one asset', () {
      final converter = usdCnyAt('7.00', '7.00');
      final prices = InMemoryHoldingPriceSource(const []);
      final service = HoldingReportService(
        converter: converter,
        baseCurrency: 'CNY',
        prices: prices,
      );

      final lots = [
        makeLot(id: 'l-usd', currency: 'USD'),
        makeLot(id: 'l-cny', currency: 'CNY'),
      ];

      expect(
        () => service.build(lots: lots, asOf: DateTime.utc(2026, 4, 1)),
        throwsA(isA<StateError>()),
      );
    });

    test('closed lots are excluded', () {
      final converter = usdCnyAt('7.00', '7.50');
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'asset-1',
          price: d('170'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final service = HoldingReportService(
        converter: converter,
        baseCurrency: 'CNY',
        prices: prices,
      );
      final closed = makeLot(remainingQuantity: Decimal.zero, currency: 'USD');
      final report = service.build(
        lots: [closed],
        asOf: DateTime.utc(2026, 4, 1),
      );
      expect(report.assets, isEmpty);
    });

    test('lot in base currency contributes only the market leg', () {
      final converter = usdCnyAt('7.00', '7.50');
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: '600519',
          price: d('1800'),
          currency: 'CNY',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final service = HoldingReportService(
        converter: converter,
        baseCurrency: 'CNY',
        prices: prices,
      );
      final lot = makeLot(
        assetId: '600519',
        currency: 'CNY',
        originalQuantity: d('100'),
        costPerUnit: d('1500'),
      );
      final report = service.build(
        lots: [lot],
        asOf: DateTime.utc(2026, 4, 1),
      );
      final row = report.assets['600519']!;
      expect(row.pnlBreakdown.fxPnLInBase, Decimal.zero);
      expect(row.pnlBreakdown.marketPnLInBase, d('30000'));
    });
  });
}
