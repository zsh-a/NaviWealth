import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

enum MoneyRunwayStatus { healthy, watch, shortfall }

enum MoneyRunwayConfidence { low, medium, high }

enum MoneyRunwayAssumptionSource { observedHistory, firePlan, defaultPolicy }

enum MoneyRunwayScenarioKind { largePurchase, delayedIncome, reducedIncome }

enum RunwayFlowCertainty { known, estimated }

enum RunwayFlowKind { recurring, liability, dividend }

MoneyRunwayConfidence calibrateMoneyRunwayConfidence({
  required MoneyRunwayConfidence calculated,
  required bool hasEstimatedDividend,
  double? dividendForecastError,
}) {
  if (!hasEstimatedDividend) return calculated;
  if (dividendForecastError != null && dividendForecastError > 0.25) {
    return MoneyRunwayConfidence.low;
  }
  return calculated == MoneyRunwayConfidence.high
      ? MoneyRunwayConfidence.medium
      : calculated;
}

@immutable
class MoneyRunwayScenario {
  MoneyRunwayScenario.largePurchase(this.amount)
    : kind = MoneyRunwayScenarioKind.largePurchase,
      delayDays = 0,
      reduction = Decimal.zero,
      durationDays = 0;

  MoneyRunwayScenario.delayedIncome(this.delayDays)
    : kind = MoneyRunwayScenarioKind.delayedIncome,
      amount = Decimal.zero,
      reduction = Decimal.zero,
      durationDays = 0;

  MoneyRunwayScenario.reducedIncome({
    required this.reduction,
    this.durationDays = 90,
  }) : kind = MoneyRunwayScenarioKind.reducedIncome,
       amount = Decimal.zero,
       delayDays = 0;

  final MoneyRunwayScenarioKind kind;
  final Decimal amount;
  final int delayDays;
  final Decimal reduction;
  final int durationDays;
}

@immutable
class RunwayScheduledFlow {
  const RunwayScheduledFlow({
    required this.id,
    required this.date,
    required this.amount,
    required this.label,
    this.certainty = RunwayFlowCertainty.known,
    this.kind = RunwayFlowKind.recurring,
  });

  final String id;
  final DateTime date;
  final Decimal amount;
  final String label;
  final RunwayFlowCertainty certainty;
  final RunwayFlowKind kind;
}

@immutable
class MoneyRunwayPoint {
  const MoneyRunwayPoint({
    required this.date,
    required this.knownBalance,
    required this.expectedBalance,
  });

  final DateTime date;
  final Decimal knownBalance;
  final Decimal expectedBalance;
}

@immutable
class MoneyRunwaySnapshot {
  const MoneyRunwaySnapshot({
    required this.asOf,
    required this.currency,
    required this.startingBalance,
    required this.reserveTarget,
    required this.averageMonthlyExpense,
    required this.estimatedDailyVariableOutflow,
    required this.scheduledFlows,
    required this.points,
    required this.status,
    required this.confidence,
    required this.dataCompleteness,
    required this.historicalForecastError,
    required this.missingCurrencies,
    required this.hasData,
    this.monthlyExpenseSource = MoneyRunwayAssumptionSource.observedHistory,
    this.reserveSource = MoneyRunwayAssumptionSource.defaultPolicy,
  });

  final DateTime asOf;
  final String currency;
  final Decimal startingBalance;
  final Decimal reserveTarget;
  final Decimal averageMonthlyExpense;
  final Decimal estimatedDailyVariableOutflow;
  final List<RunwayScheduledFlow> scheduledFlows;
  final List<MoneyRunwayPoint> points;
  final MoneyRunwayStatus status;
  final MoneyRunwayConfidence confidence;
  final double dataCompleteness;
  final double? historicalForecastError;
  final Set<String> missingCurrencies;
  final bool hasData;
  final MoneyRunwayAssumptionSource monthlyExpenseSource;
  final MoneyRunwayAssumptionSource reserveSource;

  Decimal balanceAt(int days, {bool includeEstimates = true}) {
    if (points.isEmpty) return startingBalance;
    final index = days.clamp(0, points.length - 1);
    final point = points[index];
    return includeEstimates ? point.expectedBalance : point.knownBalance;
  }

  DateTime? get firstShortfallDate {
    for (final point in points) {
      if (point.expectedBalance < Decimal.zero) return point.date;
    }
    return null;
  }

  Decimal get minimumExpectedBalance {
    var minimum = startingBalance;
    for (final point in points) {
      if (point.expectedBalance < minimum) minimum = point.expectedBalance;
    }
    return minimum;
  }

  double? get emergencyCoverageMonths {
    if (averageMonthlyExpense <= Decimal.zero) return null;
    return (startingBalance / averageMonthlyExpense).toDouble();
  }

  Map<String, Object?> toEvidenceJson() => <String, Object?>{
    'as_of': asOf.toIso8601String(),
    'currency': currency,
    'starting_balance': startingBalance.toString(),
    'reserve_target': reserveTarget.toString(),
    'average_monthly_expense': averageMonthlyExpense.toString(),
    'estimated_daily_variable_outflow': estimatedDailyVariableOutflow
        .toString(),
    'balance_30d': balanceAt(30).toString(),
    'balance_60d': balanceAt(60).toString(),
    'balance_90d': balanceAt(90).toString(),
    'minimum_expected_balance': minimumExpectedBalance.toString(),
    'first_shortfall_date': firstShortfallDate?.toIso8601String(),
    'status': status.name,
    'confidence': confidence.name,
    'data_completeness': dataCompleteness,
    'historical_forecast_error': historicalForecastError,
    'scheduled_flow_count': scheduledFlows.length,
    'estimated_flow_count': scheduledFlows
        .where((flow) => flow.certainty == RunwayFlowCertainty.estimated)
        .length,
    'missing_currencies': missingCurrencies.toList()..sort(),
    'monthly_expense_source': monthlyExpenseSource.name,
    'reserve_source': reserveSource.name,
  };
}

MoneyRunwaySnapshot buildMoneyRunway({
  required DateTime asOf,
  required String currency,
  required Decimal startingBalance,
  required Decimal reserveTarget,
  required Decimal averageMonthlyExpense,
  required Decimal estimatedDailyVariableOutflow,
  required Iterable<RunwayScheduledFlow> scheduledFlows,
  required MoneyRunwayConfidence confidence,
  double dataCompleteness = 0,
  double? historicalForecastError,
  Set<String> missingCurrencies = const <String>{},
  int horizonDays = 90,
  bool hasData = true,
  MoneyRunwayAssumptionSource monthlyExpenseSource =
      MoneyRunwayAssumptionSource.observedHistory,
  MoneyRunwayAssumptionSource reserveSource =
      MoneyRunwayAssumptionSource.defaultPolicy,
}) {
  final start = _day(asOf);
  final flows = scheduledFlows.toList(growable: false)
    ..sort((a, b) => a.date.compareTo(b.date));
  final flowsByDay = <DateTime, Decimal>{};
  final knownFlowsByDay = <DateTime, Decimal>{};
  for (final flow in flows) {
    final day = _day(flow.date);
    if (day.isBefore(start) ||
        day.isAfter(start.add(Duration(days: horizonDays)))) {
      continue;
    }
    flowsByDay[day] = (flowsByDay[day] ?? Decimal.zero) + flow.amount;
    if (flow.certainty == RunwayFlowCertainty.known) {
      knownFlowsByDay[day] =
          (knownFlowsByDay[day] ?? Decimal.zero) + flow.amount;
    }
  }

  var known = startingBalance;
  var expected = startingBalance;
  final points = <MoneyRunwayPoint>[];
  for (var offset = 0; offset <= horizonDays; offset++) {
    final date = start.add(Duration(days: offset));
    final expectedFlow = flowsByDay[date] ?? Decimal.zero;
    final knownFlow = knownFlowsByDay[date] ?? Decimal.zero;
    known += knownFlow;
    expected += expectedFlow;
    if (offset > 0) expected -= estimatedDailyVariableOutflow;
    points.add(
      MoneyRunwayPoint(
        date: date,
        knownBalance: known,
        expectedBalance: expected,
      ),
    );
  }

  var minimum = startingBalance;
  for (final point in points) {
    if (point.expectedBalance < minimum) minimum = point.expectedBalance;
  }
  final status = !hasData
      ? MoneyRunwayStatus.watch
      : minimum < Decimal.zero
      ? MoneyRunwayStatus.shortfall
      : minimum < reserveTarget
      ? MoneyRunwayStatus.watch
      : MoneyRunwayStatus.healthy;

  return MoneyRunwaySnapshot(
    asOf: start,
    currency: currency,
    startingBalance: startingBalance,
    reserveTarget: reserveTarget,
    averageMonthlyExpense: averageMonthlyExpense,
    estimatedDailyVariableOutflow: estimatedDailyVariableOutflow,
    scheduledFlows: List<RunwayScheduledFlow>.unmodifiable(flows),
    points: List<MoneyRunwayPoint>.unmodifiable(points),
    status: status,
    confidence: confidence,
    dataCompleteness: dataCompleteness,
    historicalForecastError: historicalForecastError,
    missingCurrencies: Set<String>.unmodifiable(missingCurrencies),
    hasData: hasData,
    monthlyExpenseSource: monthlyExpenseSource,
    reserveSource: reserveSource,
  );
}

MoneyRunwaySnapshot applyMoneyRunwayScenario(
  MoneyRunwaySnapshot base,
  MoneyRunwayScenario scenario,
) {
  final horizonEnd = base.asOf.add(const Duration(days: 90));
  final flows = <RunwayScheduledFlow>[];
  for (final flow in base.scheduledFlows) {
    switch (scenario.kind) {
      case MoneyRunwayScenarioKind.largePurchase:
        flows.add(flow);
      case MoneyRunwayScenarioKind.delayedIncome:
        final shifted = flow.amount > Decimal.zero
            ? flow.date.add(Duration(days: scenario.delayDays))
            : flow.date;
        if (!shifted.isAfter(horizonEnd)) {
          flows.add(
            RunwayScheduledFlow(
              id: '${flow.id}:scenario-delay',
              date: shifted,
              amount: flow.amount,
              label: flow.label,
              certainty: flow.certainty,
              kind: flow.kind,
            ),
          );
        }
      case MoneyRunwayScenarioKind.reducedIncome:
        final insideWindow = !flow.date.isAfter(
          base.asOf.add(Duration(days: scenario.durationDays)),
        );
        flows.add(
          RunwayScheduledFlow(
            id: '${flow.id}:scenario-reduction',
            date: flow.date,
            amount: flow.amount > Decimal.zero && insideWindow
                ? flow.amount * (Decimal.one - scenario.reduction)
                : flow.amount,
            label: flow.label,
            certainty: flow.certainty,
            kind: flow.kind,
          ),
        );
    }
  }
  if (scenario.kind == MoneyRunwayScenarioKind.largePurchase) {
    flows.add(
      RunwayScheduledFlow(
        id: 'scenario:large-purchase',
        date: base.asOf,
        amount: -scenario.amount.abs(),
        label: 'Scenario purchase',
      ),
    );
  }
  return buildMoneyRunway(
    asOf: base.asOf,
    currency: base.currency,
    startingBalance: base.startingBalance,
    reserveTarget: base.reserveTarget,
    averageMonthlyExpense: base.averageMonthlyExpense,
    estimatedDailyVariableOutflow: base.estimatedDailyVariableOutflow,
    scheduledFlows: flows,
    confidence: base.confidence,
    dataCompleteness: base.dataCompleteness,
    historicalForecastError: base.historicalForecastError,
    missingCurrencies: base.missingCurrencies,
    hasData: base.hasData,
    monthlyExpenseSource: base.monthlyExpenseSource,
    reserveSource: base.reserveSource,
  );
}

DateTime _day(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
