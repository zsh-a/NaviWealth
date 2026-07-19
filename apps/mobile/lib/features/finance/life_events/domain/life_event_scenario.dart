import 'package:decimal/decimal.dart';

enum LifeEventTemplate { largePurchase, careerBreak, homePurchase }

final class LifeEventBaseline {
  const LifeEventBaseline({
    required this.liquidBalance,
    required this.monthlyIncome,
    required this.monthlyOutflow,
    required this.currency,
    this.fireMonthsToTarget,
  });

  final Decimal liquidBalance;
  final Decimal monthlyIncome;
  final Decimal monthlyOutflow;
  final String currency;
  final int? fireMonthsToTarget;
}

final class LifeEventAssumptions {
  const LifeEventAssumptions({
    required this.upfrontCost,
    required this.monthlyIncomeDelta,
    required this.monthlyOutflowDelta,
    required this.durationMonths,
  });

  final Decimal upfrontCost;
  final Decimal monthlyIncomeDelta;
  final Decimal monthlyOutflowDelta;
  final int durationMonths;

  Map<String, Object> toJson() => {
    'upfrontCost': upfrontCost.toString(),
    'monthlyIncomeDelta': monthlyIncomeDelta.toString(),
    'monthlyOutflowDelta': monthlyOutflowDelta.toString(),
    'durationMonths': durationMonths,
  };

  factory LifeEventAssumptions.fromJson(
    Map<String, Object?> json,
  ) => LifeEventAssumptions(
    upfrontCost: Decimal.parse(json['upfrontCost']! as String),
    monthlyIncomeDelta: Decimal.parse(json['monthlyIncomeDelta']! as String),
    monthlyOutflowDelta: Decimal.parse(json['monthlyOutflowDelta']! as String),
    durationMonths: json['durationMonths']! as int,
  );
}

final class LifeEventOutcome {
  const LifeEventOutcome({
    required this.liquidAfter90Days,
    required this.liquidAfter12Months,
    required this.monthlySurplus,
    required this.coverageMonths,
    required this.estimatedFireDelayMonths,
  });

  final Decimal liquidAfter90Days;
  final Decimal liquidAfter12Months;
  final Decimal monthlySurplus;
  final double? coverageMonths;
  final int? estimatedFireDelayMonths;

  Map<String, Object?> toJson() => {
    'liquidAfter90Days': liquidAfter90Days.toString(),
    'liquidAfter12Months': liquidAfter12Months.toString(),
    'monthlySurplus': monthlySurplus.toString(),
    'coverageMonths': coverageMonths,
    'estimatedFireDelayMonths': estimatedFireDelayMonths,
  };

  factory LifeEventOutcome.fromJson(Map<String, Object?> json) =>
      LifeEventOutcome(
        liquidAfter90Days: Decimal.parse(json['liquidAfter90Days']! as String),
        liquidAfter12Months: Decimal.parse(
          json['liquidAfter12Months']! as String,
        ),
        monthlySurplus: Decimal.parse(json['monthlySurplus']! as String),
        coverageMonths: (json['coverageMonths'] as num?)?.toDouble(),
        estimatedFireDelayMonths: (json['estimatedFireDelayMonths'] as num?)
            ?.toInt(),
      );
}

final class LifeEventScenarioEngine {
  const LifeEventScenarioEngine();

  LifeEventOutcome simulate(
    LifeEventBaseline baseline,
    LifeEventAssumptions assumptions,
  ) {
    final monthlySurplus =
        baseline.monthlyIncome +
        assumptions.monthlyIncomeDelta -
        baseline.monthlyOutflow -
        assumptions.monthlyOutflowDelta;
    Decimal atMonth(int month) {
      final affectedMonths = month.clamp(0, assumptions.durationMonths);
      final normalMonths = month - affectedMonths;
      final normalSurplus = baseline.monthlyIncome - baseline.monthlyOutflow;
      return baseline.liquidBalance -
          assumptions.upfrontCost +
          monthlySurplus * Decimal.fromInt(affectedMonths) +
          normalSurplus * Decimal.fromInt(normalMonths);
    }

    final outflow = baseline.monthlyOutflow + assumptions.monthlyOutflowDelta;
    final baselineSurplus = baseline.monthlyIncome - baseline.monthlyOutflow;
    final twelveMonthLoss =
        baseline.liquidBalance +
        baselineSurplus * Decimal.fromInt(12) -
        atMonth(12);
    return LifeEventOutcome(
      liquidAfter90Days: atMonth(3),
      liquidAfter12Months: atMonth(12),
      monthlySurplus: monthlySurplus,
      coverageMonths: outflow <= Decimal.zero
          ? null
          : (baseline.liquidBalance - assumptions.upfrontCost).toDouble() /
                outflow.toDouble(),
      estimatedFireDelayMonths:
          baseline.fireMonthsToTarget == null ||
              baselineSurplus <= Decimal.zero ||
              twelveMonthLoss <= Decimal.zero
          ? null
          : (twelveMonthLoss.toDouble() / baselineSurplus.toDouble()).ceil(),
    );
  }

  /// Captures the currently observed baseline for a later comparison. This
  /// intentionally makes no claim that the selected decision caused it.
  LifeEventOutcome observe(LifeEventBaseline baseline) {
    final surplus = baseline.monthlyIncome - baseline.monthlyOutflow;
    return LifeEventOutcome(
      liquidAfter90Days: baseline.liquidBalance,
      liquidAfter12Months: baseline.liquidBalance,
      monthlySurplus: surplus,
      coverageMonths: baseline.monthlyOutflow <= Decimal.zero
          ? null
          : baseline.liquidBalance.toDouble() /
                baseline.monthlyOutflow.toDouble(),
      estimatedFireDelayMonths: null,
    );
  }

  LifeEventAssumptions preset(
    LifeEventTemplate template,
    LifeEventBaseline baseline,
  ) => switch (template) {
    LifeEventTemplate.largePurchase => LifeEventAssumptions(
      upfrontCost: baseline.liquidBalance * Decimal.parse('0.20'),
      monthlyIncomeDelta: Decimal.zero,
      monthlyOutflowDelta: Decimal.zero,
      durationMonths: 1,
    ),
    LifeEventTemplate.careerBreak => LifeEventAssumptions(
      upfrontCost: Decimal.zero,
      monthlyIncomeDelta: -baseline.monthlyIncome,
      monthlyOutflowDelta: Decimal.zero,
      durationMonths: 6,
    ),
    LifeEventTemplate.homePurchase => LifeEventAssumptions(
      upfrontCost: baseline.liquidBalance * Decimal.parse('0.30'),
      monthlyIncomeDelta: Decimal.zero,
      monthlyOutflowDelta: baseline.monthlyOutflow * Decimal.parse('0.10'),
      durationMonths: 12,
    ),
  };
}
