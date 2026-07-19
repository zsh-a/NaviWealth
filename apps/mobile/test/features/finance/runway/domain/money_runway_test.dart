import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

void main() {
  test('projects known and estimated balances independently', () {
    final now = DateTime.utc(2026, 7, 1);
    final runway = buildMoneyRunway(
      asOf: now,
      currency: 'CNY',
      startingBalance: Decimal.fromInt(10000),
      reserveTarget: Decimal.fromInt(3000),
      averageMonthlyExpense: Decimal.fromInt(3000),
      estimatedDailyVariableOutflow: Decimal.fromInt(100),
      scheduledFlows: <RunwayScheduledFlow>[
        RunwayScheduledFlow(
          id: 'rent',
          date: DateTime.utc(2026, 7, 5),
          amount: Decimal.fromInt(-2000),
          label: 'Rent',
        ),
        RunwayScheduledFlow(
          id: 'salary',
          date: DateTime.utc(2026, 7, 10),
          amount: Decimal.fromInt(5000),
          label: 'Salary',
        ),
      ],
      confidence: MoneyRunwayConfidence.high,
      horizonDays: 30,
    );

    expect(
      runway.balanceAt(30, includeEstimates: false),
      Decimal.fromInt(13000),
    );
    expect(runway.balanceAt(30), Decimal.fromInt(10000));
    expect(runway.status, MoneyRunwayStatus.healthy);
    expect(runway.firstShortfallDate, isNull);
  });

  test('detects first expected shortfall', () {
    final runway = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'CNY',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.fromInt(500),
      averageMonthlyExpense: Decimal.fromInt(3000),
      estimatedDailyVariableOutflow: Decimal.fromInt(100),
      scheduledFlows: const <RunwayScheduledFlow>[],
      confidence: MoneyRunwayConfidence.medium,
      horizonDays: 30,
    );

    expect(runway.status, MoneyRunwayStatus.shortfall);
    expect(runway.firstShortfallDate, DateTime.utc(2026, 7, 12));
    expect(runway.minimumExpectedBalance, Decimal.fromInt(-2000));
  });
}
