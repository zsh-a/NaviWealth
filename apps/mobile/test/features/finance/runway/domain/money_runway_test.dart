import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

void main() {
  test('calibrates confidence from estimated dividend forecast quality', () {
    expect(
      calibrateMoneyRunwayConfidence(
        calculated: MoneyRunwayConfidence.high,
        hasEstimatedDividend: true,
      ),
      MoneyRunwayConfidence.medium,
    );
    expect(
      calibrateMoneyRunwayConfidence(
        calculated: MoneyRunwayConfidence.high,
        hasEstimatedDividend: true,
        dividendForecastError: 0.3,
      ),
      MoneyRunwayConfidence.low,
    );
    expect(
      calibrateMoneyRunwayConfidence(
        calculated: MoneyRunwayConfidence.high,
        hasEstimatedDividend: false,
        dividendForecastError: 0.3,
      ),
      MoneyRunwayConfidence.high,
    );
  });

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
    expect(runway.firstReserveBreachDate, isNull);
  });

  test('keeps status dates aligned with the initial balance', () {
    final runway = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'USD',
      startingBalance: Decimal.fromInt(100),
      reserveTarget: Decimal.fromInt(500),
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'salary',
          date: DateTime.utc(2026, 7, 1, 18),
          amount: Decimal.fromInt(1000),
          label: 'Salary',
        ),
      ],
      confidence: MoneyRunwayConfidence.high,
    );

    expect(runway.status, MoneyRunwayStatus.watch);
    expect(runway.firstReserveBreachDate, runway.asOf);
    expect(runway.minimumExpectedBalanceDate, runway.asOf);
  });

  test('keeps only flows inside the forecast window', () {
    final runway = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 10),
      currency: 'USD',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.zero,
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'past',
          date: DateTime.utc(2026, 7, 9),
          amount: Decimal.fromInt(100),
          label: 'Past',
        ),
        RunwayScheduledFlow(
          id: 'inside',
          date: DateTime.utc(2026, 7, 11),
          amount: Decimal.fromInt(100),
          label: 'Inside',
        ),
        RunwayScheduledFlow(
          id: 'future',
          date: DateTime.utc(2026, 7, 12),
          amount: Decimal.fromInt(100),
          label: 'Future',
        ),
      ],
      confidence: MoneyRunwayConfidence.high,
      horizonDays: 1,
    );

    expect(runway.scheduledFlows.map((flow) => flow.id), ['inside']);
    expect(runway.balanceAt(1), Decimal.fromInt(1100));
  });

  test('resolves event-day balances and risk dates from the forecast', () {
    final runway = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'USD',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.fromInt(900),
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'bill',
          date: DateTime.utc(2026, 7, 10, 18),
          amount: Decimal.fromInt(-200),
          label: 'Bill',
        ),
      ],
      confidence: MoneyRunwayConfidence.high,
      horizonDays: 30,
    );

    expect(
      runway.pointOn(DateTime.utc(2026, 7, 10, 8))?.expectedBalance,
      Decimal.fromInt(800),
    );
    expect(
      runway.expectedBalanceAfter(DateTime.utc(2026, 7, 10, 8)),
      Decimal.fromInt(800),
    );
    expect(runway.firstReserveBreachDate, DateTime.utc(2026, 7, 10));
    expect(runway.minimumExpectedBalance, Decimal.fromInt(800));
    expect(runway.minimumExpectedBalanceDate, DateTime.utc(2026, 7, 10));
    expect(
      runway.toEvidenceJson()['first_reserve_breach_date'],
      '2026-07-10T00:00:00.000Z',
    );
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

  test('estimated dividends affect expected but not known balance', () {
    final runway = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'USD',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.zero,
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'estimated-dividend',
          date: DateTime.utc(2026, 7, 10),
          amount: Decimal.fromInt(100),
          label: 'Dividend',
          certainty: RunwayFlowCertainty.estimated,
          kind: RunwayFlowKind.dividend,
        ),
      ],
      confidence: MoneyRunwayConfidence.medium,
      horizonDays: 30,
    );

    expect(
      runway.balanceAt(30, includeEstimates: false),
      Decimal.fromInt(1000),
    );
    expect(runway.balanceAt(30), Decimal.fromInt(1100));
    expect(runway.toEvidenceJson()['estimated_flow_count'], 1);
  });

  test('stress scenarios transform only the intended cash flows', () {
    final base = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'CNY',
      startingBalance: Decimal.fromInt(10000),
      reserveTarget: Decimal.fromInt(3000),
      averageMonthlyExpense: Decimal.fromInt(3000),
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: <RunwayScheduledFlow>[
        RunwayScheduledFlow(
          id: 'salary',
          date: DateTime.utc(2026, 7, 10),
          amount: Decimal.fromInt(5000),
          label: 'Salary',
        ),
        RunwayScheduledFlow(
          id: 'rent',
          date: DateTime.utc(2026, 7, 12),
          amount: Decimal.fromInt(-2000),
          label: 'Rent',
        ),
      ],
      confidence: MoneyRunwayConfidence.high,
    );

    final purchase = applyMoneyRunwayScenario(
      base,
      MoneyRunwayScenario.largePurchase(Decimal.fromInt(3000)),
    );
    final delayed = applyMoneyRunwayScenario(
      base,
      MoneyRunwayScenario.delayedIncome(14),
    );
    final reduced = applyMoneyRunwayScenario(
      base,
      MoneyRunwayScenario.reducedIncome(reduction: Decimal.parse('0.3')),
    );

    expect(purchase.balanceAt(90), base.balanceAt(90) - Decimal.fromInt(3000));
    expect(delayed.balanceAt(15), Decimal.fromInt(8000));
    expect(delayed.balanceAt(30), base.balanceAt(30));
    expect(reduced.balanceAt(90), base.balanceAt(90) - Decimal.fromInt(1500));
  });

  test('stress scenarios preserve dividend kind and certainty', () {
    final base = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'USD',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.zero,
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'estimated-dividend',
          date: DateTime.utc(2026, 7, 10),
          amount: Decimal.fromInt(100),
          label: 'Dividend',
          certainty: RunwayFlowCertainty.estimated,
          kind: RunwayFlowKind.dividend,
        ),
      ],
      confidence: MoneyRunwayConfidence.medium,
    );

    final delayed = applyMoneyRunwayScenario(
      base,
      MoneyRunwayScenario.delayedIncome(14),
    );
    final reduced = applyMoneyRunwayScenario(
      base,
      MoneyRunwayScenario.reducedIncome(reduction: Decimal.parse('0.3')),
    );

    for (final scenario in [delayed, reduced]) {
      expect(
        scenario.scheduledFlows.single.certainty,
        RunwayFlowCertainty.estimated,
      );
      expect(scenario.scheduledFlows.single.kind, RunwayFlowKind.dividend);
    }
  });
}
