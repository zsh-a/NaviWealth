import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/runway/data/runway_forecast_repository.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  test(
    'mature forecast is evaluated against observed liquid balance',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = RunwayForecastRepository(
        db: db,
        ownerUserId: 'owner-1',
      );
      final first = buildMoneyRunway(
        asOf: DateTime.utc(2026, 1, 1),
        currency: 'CNY',
        startingBalance: Decimal.fromInt(1000),
        reserveTarget: Decimal.zero,
        averageMonthlyExpense: Decimal.zero,
        estimatedDailyVariableOutflow: Decimal.zero,
        scheduledFlows: const [],
        confidence: MoneyRunwayConfidence.high,
        dataCompleteness: 1,
      );
      await repository.recordAndEvaluate(first);

      final observed = buildMoneyRunway(
        asOf: DateTime.utc(2026, 2, 1),
        currency: 'CNY',
        startingBalance: Decimal.fromInt(900),
        reserveTarget: Decimal.zero,
        averageMonthlyExpense: Decimal.zero,
        estimatedDailyVariableOutflow: Decimal.zero,
        scheduledFlows: const [],
        confidence: MoneyRunwayConfidence.high,
        dataCompleteness: 1,
      );
      await repository.recordAndEvaluate(observed);
      final quality = await repository.quality();

      expect(quality.evaluatedCount, 1);
      expect(quality.meanRelativeError, closeTo(0.1, 0.0001));
    },
  );
}
