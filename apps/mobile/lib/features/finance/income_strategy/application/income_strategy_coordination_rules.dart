import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';
import '../domain/income_strategy_rule.dart';

const kBuiltInIncomeStrategyCoordinationRules = <IncomeStrategyRule>[
  DividendInterruptionRule(),
  LeapsBudgetRule(),
  AssignmentBudgetRule(),
];

/// Group-scope coordination rules. For an implicit singleton group these
/// behave exactly like the old per-asset checks; for an explicit group the
/// legs may live on different underlyings (TQQQ wheel + QQQ LEAPS).
const kBuiltInIncomeStrategyGroupRules = <IncomeStrategyGroupRule>[
  StackedDownsideRule(),
  LeapsFundingRule(),
];

class StackedDownsideRule implements IncomeStrategyGroupRule {
  const StackedDownsideRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.stackedDownside;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyGroupRuleContext context,
  ) sync* {
    final shortPut = context
        .sleevesOf(IncomeStrategySleeveKind.wheel)
        .where((entry) => entry.$2.exposure.hasOpenShortPut)
        .firstOrNull;
    final leaps = context
        .sleevesOf(IncomeStrategySleeveKind.leapsCall)
        .firstOrNull;
    if (shortPut != null && leaps != null) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: leaps.$1.asset.assetId,
        groupId: context.isExplicit ? context.groupId : null,
        sleeves: {
          IncomeStrategySleeveKind.wheel,
          IncomeStrategySleeveKind.leapsCall,
        },
        evidence: {
          if (context.isExplicit) ...{
            'group': context.groupLabel,
            'short_put_asset': shortPut.$1.asset.symbol,
            'leaps_asset': leaps.$1.asset.symbol,
          },
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

class LeapsFundingRule implements IncomeStrategyGroupRule {
  const LeapsFundingRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.leapsCostNotCovered;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyGroupRuleContext context,
  ) sync* {
    final leapsSleeves = context
        .sleevesOf(IncomeStrategySleeveKind.leapsCall)
        .toList(growable: false);
    if (leapsSleeves.isEmpty) return;
    var openLeapsCost = Money.zero(context.baseCurrency);
    for (final (_, sleeve) in leapsSleeves) {
      openLeapsCost += sleeve.capitalAtRisk.value;
    }
    if (openLeapsCost.amount <= Decimal.zero) return;

    // Funding pools across the whole group: a TQQQ wheel or an SCHD
    // dividend sleeve can both pay for a QQQ LEAPS call.
    var funding = Money.zero(context.baseCurrency);
    for (final kind in const [
      IncomeStrategySleeveKind.dividends,
      IncomeStrategySleeveKind.wheel,
    ]) {
      for (final (_, sleeve) in context.sleevesOf(kind)) {
        funding += sleeve.realizedIncome.value;
      }
    }
    if (funding < openLeapsCost) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: leapsSleeves.first.$1.asset.assetId,
        groupId: context.isExplicit ? context.groupId : null,
        sleeves: {
          IncomeStrategySleeveKind.dividends,
          IncomeStrategySleeveKind.wheel,
          IncomeStrategySleeveKind.leapsCall,
        },
        evidence: {
          'realized_income_ytd': funding.amount.toString(),
          'open_leaps_cost': openLeapsCost.amount.toString(),
          'currency': context.baseCurrency,
          if (context.isExplicit) 'group': context.groupLabel,
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
