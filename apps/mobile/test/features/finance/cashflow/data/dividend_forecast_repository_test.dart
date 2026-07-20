import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_repository.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_cash_projection.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  test(
    'evaluates matured after-tax forecast against ledger dividends',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = DividendForecastRepository(
        db: db,
        ownerUserId: 'owner-1',
      );

      await repository.recordAndEvaluate(
        asOf: DateTime.utc(2026, 1, 1),
        currency: 'USD',
        projections: [
          DividendCashProjection(
            date: DateTime.utc(2026, 1, 2),
            netAmount: Decimal.fromInt(100),
            certainty: DividendCashCertainty.inferred,
            hasTaxEvidence: true,
          ),
        ],
        actualEvents: const [],
        strategy: 'ttm',
        confidence: DividendForecastConfidence.medium,
        horizonDays: 2,
      );

      await repository.recordAndEvaluate(
        asOf: DateTime.utc(2026, 1, 4),
        currency: 'USD',
        projections: const [],
        actualEvents: [_event(date: DateTime.utc(2026, 1, 2), net: 80)],
        strategy: 'ttm',
        confidence: DividendForecastConfidence.medium,
        horizonDays: 2,
      );

      final quality = await repository.quality();
      expect(quality.evaluatedCount, 1);
      expect(quality.meanRelativeError, closeTo(0.2, 0.0001));
    },
  );

  test('keeps the first snapshot for the same as-of day and horizon', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = DividendForecastRepository(
      db: db,
      ownerUserId: 'owner-1',
    );

    for (final amount in [100, 200]) {
      await repository.recordAndEvaluate(
        asOf: DateTime.utc(2026, 1, 1, 12),
        currency: 'USD',
        projections: [
          DividendCashProjection(
            date: DateTime.utc(2026, 1, 2),
            netAmount: Decimal.fromInt(amount),
            certainty: DividendCashCertainty.inferred,
            hasTaxEvidence: false,
          ),
        ],
        actualEvents: const [],
        strategy: 'ttm',
        confidence: DividendForecastConfidence.low,
        horizonDays: 2,
      );
    }

    final row = await db
        .customSelect('SELECT predicted_net FROM dividend_forecast_snapshots')
        .getSingle();
    expect(row.read<String>('predicted_net'), '100');
  });
}

DividendCenterEvent _event({required DateTime date, required int net}) {
  return DividendCenterEvent(
    event: CashFlowEvent(
      journalEntryId: 'dividend-${date.toIso8601String()}',
      date: date,
      kind: CashFlowKind.dividend,
      signedAmount: Decimal.fromInt(net),
      originalAmount: Decimal.fromInt(net),
      currency: 'USD',
      accountId: 'cash',
      counterAccountSide: AccountSide.income,
    ),
    assetId: 'us:AAPL',
    assetLabel: 'AAPL',
    withholdingInBase: Decimal.zero,
    withholdingOriginal: Decimal.zero,
    withholdingCurrency: 'USD',
  );
}
