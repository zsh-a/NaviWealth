import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';
import '../domain/income_strategy_rule.dart';

const kBuiltInIncomeStrategyCoordinationRules = <IncomeStrategyRule>[
  StackedDownsideRule(),
  DividendInterruptionRule(),
  LeapsFundingRule(),
  LeapsBudgetRule(),
  AssignmentBudgetRule(),
];

class StackedDownsideRule implements IncomeStrategyRule {
  const StackedDownsideRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.stackedDownside;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final wheel = context.sleeves[IncomeStrategySleeveKind.wheel];
    final leaps = context.sleeves[IncomeStrategySleeveKind.leapsCall];
    if (wheel?.exposure.hasOpenShortPut == true && leaps != null) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: {
          IncomeStrategySleeveKind.wheel,
          IncomeStrategySleeveKind.leapsCall,
        },
      );
    }
  }
}

class DividendInterruptionRule implements IncomeStrategyRule {
  const DividendInterruptionRule();

  @override
  IncomeStrategyRiskCode get code =>
      IncomeStrategyRiskCode.dividendInterruption;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final dividendIntent = context.plan?.intent(
      IncomeStrategySleeveKind.dividends,
    );
    final wheelIntent = context.plan?.intent(IncomeStrategySleeveKind.wheel);
    final preserve =
        dividendIntent?.boolValue(
          DividendIncomeStrategySettings.preservePosition,
          fallback: true,
        ) ??
        false;
    final allowCalledAway =
        wheelIntent?.boolValue(
          WheelIncomeStrategySettings.allowSharesCalledAway,
          fallback: false,
        ) ??
        false;
    final wheel = context.sleeves[IncomeStrategySleeveKind.wheel];
    if (preserve &&
        !allowCalledAway &&
        wheel?.exposure.hasOpenCoveredCall == true) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: {
          IncomeStrategySleeveKind.dividends,
          IncomeStrategySleeveKind.wheel,
        },
      );
    }
  }
}

class LeapsFundingRule implements IncomeStrategyRule {
  const LeapsFundingRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.leapsCostNotCovered;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final leaps = context.sleeves[IncomeStrategySleeveKind.leapsCall];
    if (leaps == null || leaps.capitalAtRisk.value.amount <= Decimal.zero) {
      return;
    }
    var funding = Money.zero(context.baseCurrency);
    for (final kind in const [
      IncomeStrategySleeveKind.dividends,
      IncomeStrategySleeveKind.wheel,
    ]) {
      final sleeve = context.sleeves[kind];
      if (sleeve != null) funding += sleeve.realizedIncome.value;
    }
    if (funding < leaps.capitalAtRisk.value) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: {
          IncomeStrategySleeveKind.dividends,
          IncomeStrategySleeveKind.wheel,
          IncomeStrategySleeveKind.leapsCall,
        },
        evidence: {
          'realized_income_ytd': funding.amount.toString(),
          'open_leaps_cost': leaps.capitalAtRisk.value.amount.toString(),
          'currency': context.baseCurrency,
        },
      );
    }
  }
}

class LeapsBudgetRule implements IncomeStrategyRule {
  const LeapsBudgetRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.leapsBudgetExceeded;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final plan = context.plan;
    final maxCost = plan
        ?.intent(IncomeStrategySleeveKind.leapsCall)
        ?.decimalValue(LeapsIncomeStrategySettings.maxCost);
    final leaps = context.sleeves[IncomeStrategySleeveKind.leapsCall];
    if (plan == null || maxCost == null || leaps == null) return;
    final limit = context.tryConvertToBase(Money(maxCost, plan.currency));
    if (limit != null && leaps.capitalAtRisk.value > limit) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.critical,
        assetId: context.asset.assetId,
        sleeves: {IncomeStrategySleeveKind.leapsCall},
        evidence: {
          'capital_at_risk': leaps.capitalAtRisk.value.amount.toString(),
          'limit': limit.amount.toString(),
          'currency': context.baseCurrency,
        },
      );
    }
  }
}

class AssignmentBudgetRule implements IncomeStrategyRule {
  const AssignmentBudgetRule();

  @override
  IncomeStrategyRiskCode get code =>
      IncomeStrategyRiskCode.assignmentBudgetExceeded;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final plan = context.plan;
    final maxAssignment = plan
        ?.intent(IncomeStrategySleeveKind.wheel)
        ?.decimalValue(WheelIncomeStrategySettings.maxAssignmentValue);
    final obligation = context
        .sleeves[IncomeStrategySleeveKind.wheel]
        ?.exposure
        .assignmentObligation;
    if (plan == null || maxAssignment == null || obligation == null) return;
    final limit = context.tryConvertToBase(Money(maxAssignment, plan.currency));
    if (limit != null && obligation.value > limit) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.critical,
        assetId: context.asset.assetId,
        sleeves: {IncomeStrategySleeveKind.wheel},
        evidence: {
          'assignment_value': obligation.value.amount.toString(),
          'limit': limit.amount.toString(),
          'currency': context.baseCurrency,
        },
      );
    }
  }
}
