import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_cash_projection.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

void main() {
  test('keeps declared tax evidence separate from inferred net cash', () {
    final declaredDate = DateTime.utc(2026, 8, 1);
    final inferredDate = DateTime.utc(2026, 9, 1);
    final forecast = ProjectedDividend(
      assetId: 'portfolio',
      perAsset: {
        declaredDate: Decimal.fromInt(100),
        inferredDate: Decimal.fromInt(200),
      },
      total: Decimal.fromInt(300),
      currency: 'USD',
      strategy: 'composite',
      confidence: DividendForecastConfidence.medium,
    );

    final rows = buildDividendCashProjections(
      forecast: forecast,
      declaredActions: [
        CashDividendAction(
          id: 'declared',
          assetId: 'a',
          effectiveDate: declaredDate,
          transactionId: 'declared',
          accountId: 'broker',
          currency: 'USD',
          amountPerShare: Decimal.one,
          withholdingTax: Decimal.fromInt(15),
        ),
      ],
      holdings: [_holding(quantity: 100)],
      from: DateTime.utc(2026, 7, 1),
      to: DateTime.utc(2026, 10, 1),
      observedNetRetentionRatio: 0.8,
    );

    expect(rows, hasLength(2));
    expect(rows.first.certainty, DividendCashCertainty.declared);
    expect(rows.first.netAmount, Decimal.fromInt(85));
    expect(rows.first.hasTaxEvidence, isTrue);
    expect(rows.last.certainty, DividendCashCertainty.inferred);
    expect(rows.last.netAmount, Decimal.fromInt(160));
    expect(rows.last.hasTaxEvidence, isTrue);
  });

  test(
    'marks inferred gross as lacking tax evidence when retention is unknown',
    () {
      final date = DateTime.utc(2026, 8, 1);
      final rows = buildDividendCashProjections(
        forecast: ProjectedDividend(
          assetId: 'portfolio',
          perAsset: {date: Decimal.fromInt(100)},
          total: Decimal.fromInt(100),
          currency: 'USD',
          strategy: 'ttm',
          confidence: DividendForecastConfidence.low,
        ),
        declaredActions: const [],
        holdings: [_holding(quantity: 100)],
        from: DateTime.utc(2026, 7, 1),
        to: DateTime.utc(2026, 10, 1),
      );

      expect(rows.single.netAmount, Decimal.fromInt(100));
      expect(rows.single.certainty, DividendCashCertainty.inferred);
      expect(rows.single.hasTaxEvidence, isFalse);
    },
  );
}

HoldingSnapshot _holding({required int quantity}) => HoldingSnapshot(
  assetId: 'a',
  quantity: Decimal.fromInt(quantity),
  costBasisInAssetCurrency: Decimal.fromInt(1000),
  marketValueInAssetCurrency: Decimal.fromInt(1000),
  assetCurrency: 'USD',
  costBasisInBase: Decimal.fromInt(1000),
  marketValueInBase: Decimal.fromInt(1000),
  unrealizedPnlInBase: Decimal.zero,
  weight: Decimal.one,
  baseCurrency: 'USD',
  asOf: DateTime.utc(2026, 7, 1),
);
