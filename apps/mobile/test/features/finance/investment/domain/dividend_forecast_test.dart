import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/cash_dividend.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

void main() {
  group('TrailingTwelveMonthsStrategy', () {
    test('projects the trailing 12-month actual gross dividend schedule', () {
      const strategy = TrailingTwelveMonthsStrategy();
      final horizonEnd = DateTime.utc(2027, 5, 17);
      final result = strategy.forecast(
        holdings: [_holding('asset-a', quantity: '100')],
        history: [
          _dividend('asset-a', DateTime.utc(2026, 1, 10), gross: '10'),
          _dividend('asset-a', DateTime.utc(2026, 4, 10), gross: '12'),
          _dividend('asset-a', DateTime.utc(2025, 1, 10), gross: '99'),
          _dividend('asset-b', DateTime.utc(2026, 1, 10), gross: '50'),
        ],
        declared: const [],
        horizonEnd: horizonEnd,
      );

      expect(result.strategy, 'ttm');
      expect(result.confidence, DividendForecastConfidence.low);
      expect(result.total, d('22'));
      expect(result.perAsset[DateTime.utc(2027, 1, 10)], d('10'));
      expect(result.perAsset[DateTime.utc(2027, 4, 10)], d('12'));
    });
  });

  group('DeclaredActionsStrategy', () {
    test('uses future cash dividend and DRIP declarations', () {
      const strategy = DeclaredActionsStrategy();
      final result = strategy.forecast(
        holdings: [_holding('asset-a', quantity: '100')],
        history: const [],
        declared: [
          CashDividendAction(
            id: 'declared-a',
            assetId: 'asset-a',
            effectiveDate: DateTime.utc(2026, 6, 1),
            transactionId: 'tx-a',
            accountId: 'brokerage',
            currency: 'USD',
            amountPerShare: d('0.20'),
            withholdingTax: Decimal.zero,
          ),
          DripAction(
            id: 'drip-a',
            assetId: 'asset-a',
            effectiveDate: DateTime.utc(2026, 9, 1),
            transactionId: 'tx-b',
            accountId: 'brokerage',
            currency: 'USD',
            amountPerShare: d('0.30'),
            pricePerUnit: d('10'),
            withholdingTax: Decimal.zero,
            fee: Decimal.zero,
          ),
          CashDividendAction(
            id: 'past-a',
            assetId: 'asset-a',
            effectiveDate: DateTime.utc(2026, 5, 1),
            transactionId: 'tx-past',
            accountId: 'brokerage',
            currency: 'USD',
            amountPerShare: d('10'),
            withholdingTax: Decimal.zero,
          ),
        ],
        horizonEnd: DateTime.utc(2027, 5, 17),
      );

      expect(result.strategy, 'declared');
      expect(result.confidence, DividendForecastConfidence.high);
      expect(result.total, d('50'));
      expect(result.perAsset[DateTime.utc(2026, 6, 1)], d('20'));
      expect(result.perAsset[DateTime.utc(2026, 9, 1)], d('30'));
    });
  });

  group('DpsExtrapolationStrategy', () {
    test('estimates annual DPS frequency and multiplies current holdings', () {
      const strategy = DpsExtrapolationStrategy();
      final result = strategy.forecast(
        holdings: [_holding('asset-a', quantity: '100')],
        history: [
          for (var month = 12; month >= 7; month--)
            _dividend(
              'asset-a',
              DateTime.utc(2025, month, 5),
              gross: '10',
              amountPerShare: '0.10',
            ),
        ],
        declared: const [],
        horizonEnd: DateTime.utc(2027, 5, 17),
      );

      expect(result.strategy, 'dps');
      expect(result.confidence, DividendForecastConfidence.medium);
      expect(result.total, d('120.00000000'));
      expect(result.amountInMonth(DateTime.utc(2026, 6)), d('10.00000000'));
    });
  });

  group('DividendForecastService', () {
    test('ignores declared amounts that cannot be converted to base', () {
      const service = DividendForecastService();
      final result = service.forecast(
        holdings: [_holding('asset-a', quantity: '100')],
        history: [
          _dividend(
            'asset-a',
            DateTime.utc(2026, 2, 1),
            gross: '25',
            amountPerShare: '0',
          ),
        ],
        declared: [
          CashDividendAction(
            id: 'foreign-declaration',
            assetId: 'asset-a',
            effectiveDate: DateTime.utc(2026, 8, 1),
            transactionId: 'tx-foreign',
            accountId: 'brokerage',
            currency: 'CNY',
            amountPerShare: d('10'),
            withholdingTax: Decimal.zero,
          ),
        ],
        horizonEnd: DateTime.utc(2027, 5, 17),
      );

      expect(result.total, d('25'));
      expect(result.assetStrategies, {'asset-a': 'ttm'});
    });

    test(
      'fills gaps by declared, then DPS, then TTM with source breakdown',
      () {
        const service = DividendForecastService();
        final result = service.forecast(
          holdings: [
            _holding('declared-asset', quantity: '100'),
            _holding('dps-asset', quantity: '10'),
            _holding('ttm-asset', quantity: '1'),
          ],
          history: [
            _dividend(
              'dps-asset',
              DateTime.utc(2025, 6, 1),
              gross: '10',
              amountPerShare: '1',
            ),
            _dividend(
              'dps-asset',
              DateTime.utc(2025, 9, 1),
              gross: '10',
              amountPerShare: '1',
            ),
            _dividend(
              'ttm-asset',
              DateTime.utc(2026, 2, 1),
              gross: '30',
              amountPerShare: '0',
            ),
          ],
          declared: [
            CashDividendAction(
              id: 'declared',
              assetId: 'declared-asset',
              effectiveDate: DateTime.utc(2026, 6, 1),
              transactionId: 'tx',
              accountId: 'brokerage',
              currency: 'USD',
              amountPerShare: d('0.30'),
              withholdingTax: Decimal.zero,
            ),
          ],
          horizonEnd: DateTime.utc(2027, 5, 17),
        );

        expect(result.strategy, 'composite');
        expect(result.total, d('100.00000000'));
        expect(result.strategyBreakdown['declared'], d('30.0'));
        expect(result.strategyBreakdown['dps'], d('40.00000000'));
        expect(result.strategyBreakdown['ttm'], d('30'));
        expect(result.assetStrategies, {
          'declared-asset': 'declared',
          'dps-asset': 'dps',
          'ttm-asset': 'ttm',
        });
      },
    );

    test('forecasts 50 holdings with 24 months of history under 50ms', () {
      const service = DividendForecastService();
      final holdings = [
        for (var i = 0; i < 50; i++) _holding('asset-$i', quantity: '100'),
      ];
      final history = [
        for (var i = 0; i < 50; i++)
          for (var month = 0; month < 24; month++)
            _dividend(
              'asset-$i',
              DateTime.utc(2026, 5, 1).subtract(Duration(days: month * 30)),
              gross: '5',
              amountPerShare: '0.05',
            ),
      ];

      final sw = Stopwatch()..start();
      final result = service.forecast(
        holdings: holdings,
        history: history,
        declared: const [],
        horizonEnd: DateTime.utc(2027, 5, 17),
      );
      sw.stop();

      expect(result.total > Decimal.zero, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}

HoldingSnapshot _holding(String assetId, {required String quantity}) {
  final qty = d(quantity);
  return HoldingSnapshot(
    assetId: assetId,
    quantity: qty,
    costBasisInAssetCurrency: qty,
    marketValueInAssetCurrency: qty,
    assetCurrency: 'USD',
    costBasisInBase: qty,
    marketValueInBase: qty,
    unrealizedPnlInBase: Decimal.zero,
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 5, 17),
  );
}

CashDividend _dividend(
  String assetId,
  DateTime date, {
  required String gross,
  String? amountPerShare,
}) {
  final grossAmount = d(gross);
  final perShare = amountPerShare == null ? grossAmount : d(amountPerShare);
  return CashDividend(
    id: '$assetId-${date.toIso8601String()}',
    transactionId: 'tx-$assetId-${date.millisecondsSinceEpoch}',
    accountId: 'brokerage',
    assetId: assetId,
    currency: 'USD',
    effectiveDate: date,
    shareCount: Decimal.one,
    amountPerShare: perShare,
    grossAmount: grossAmount,
    withholdingTax: Decimal.zero,
    netAmount: grossAmount,
    reinvested: false,
  );
}

Decimal d(String value) => Decimal.parse(value);
