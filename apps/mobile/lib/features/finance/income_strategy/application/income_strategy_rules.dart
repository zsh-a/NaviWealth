import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_rule.dart';

const kCoreIncomeStrategyRules = <IncomeStrategyRule>[
  UnplannedSleeveRule(),
  CapitalBudgetRule(),
  ConcentrationRule(),
  IncomeTargetPaceRule(),
];

class UnplannedSleeveRule implements IncomeStrategyRule {
  const UnplannedSleeveRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.unplannedSleeve;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    for (final kind in context.sleeves.keys.where(
      (kind) => !context.enabledSleeves.contains(kind),
    )) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: {kind},
      );
    }
  }
}

class CapitalBudgetRule implements IncomeStrategyRule {
  const CapitalBudgetRule();

  @override
  IncomeStrategyRiskCode get code =>
      IncomeStrategyRiskCode.capitalBudgetExceeded;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final nativeBudget = context.plan?.capitalBudgetMoney;
    if (nativeBudget == null) return;
    final budget = context.tryConvertToBase(nativeBudget);
    if (budget == null) {
      yield IncomeStrategyRisk(
        code: IncomeStrategyRiskCode.missingFxRate,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: Set.unmodifiable(context.sleeves.keys),
        evidence: {
          'from_currency': nativeBudget.currency,
          'to_currency': context.baseCurrency,
        },
      );
      return;
    }
    final total = _sumCapital(context);
    if (total.value > budget) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.critical,
        assetId: context.asset.assetId,
        sleeves: Set.unmodifiable(context.sleeves.keys),
        evidence: {
          'capital_at_risk': total.value.amount.toString(),
          'limit': budget.amount.toString(),
          'currency': context.baseCurrency,
        },
      );
    }
  }
}

class ConcentrationRule implements IncomeStrategyRule {
  const ConcentrationRule();

  @override
  IncomeStrategyRiskCode get code =>
      IncomeStrategyRiskCode.concentrationExceeded;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final limit = context.plan?.maxPositionWeight;
    if (limit == null) return;
    final weights = context.sleeves.values
        .map((sleeve) => sleeve.exposure.holdingWeight)
        .whereType<Decimal>();
    final weight = weights.fold(Decimal.zero, (max, value) {
      return value > max ? value : max;
    });
    if (weight > limit) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.critical,
        assetId: context.asset.assetId,
        sleeves: Set.unmodifiable(context.sleeves.keys),
        evidence: {'weight': weight.toString(), 'limit': limit.toString()},
      );
    }
  }
}

class IncomeTargetPaceRule implements IncomeStrategyRule {
  const IncomeTargetPaceRule();

  @override
  IncomeStrategyRiskCode get code => IncomeStrategyRiskCode.incomeTargetAtRisk;

  @override
  Iterable<IncomeStrategyRisk> evaluate(
    IncomeStrategyRuleContext context,
  ) sync* {
    final nativeTarget = context.plan?.annualIncomeTargetMoney;
    if (nativeTarget == null || nativeTarget.amount <= Decimal.zero) return;
    final target = context.tryConvertToBase(nativeTarget);
    if (target == null) return;
    final yearStart = DateTime.utc(context.asOf.year);
    final yearEnd = DateTime.utc(context.asOf.year + 1);
    final elapsedDays = context.asOf.difference(yearStart).inDays + 1;
    final daysInYear = yearEnd.difference(yearStart).inDays;
    final expectedToDate =
        target.amount *
        Decimal.fromInt(elapsedDays) /
        Decimal.fromInt(daysInYear);
    final expected = expectedToDate.toDecimal(scaleOnInfinitePrecision: 8);
    var actual = Money.zero(context.baseCurrency);
    for (final sleeve in context.sleeves.values) {
      actual += sleeve.realizedIncome.value;
    }
    if (actual.amount < expected * Decimal.parse('0.75')) {
      yield IncomeStrategyRisk(
        code: code,
        severity: IncomeStrategyRiskSeverity.warning,
        assetId: context.asset.assetId,
        sleeves: Set.unmodifiable(context.enabledSleeves),
        evidence: {
          'realized_income_ytd': actual.amount.toString(),
          'expected_income_ytd': expected.toString(),
          'annual_target': target.amount.toString(),
          'currency': context.baseCurrency,
        },
      );
    }
  }
}

IncomeStrategyMoneyMetric _sumCapital(IncomeStrategyRuleContext context) {
  var result = IncomeStrategyMoneyMetric.zero(context.baseCurrency);
  for (final sleeve in context.sleeves.values) {
    result += sleeve.capitalAtRisk;
  }
  return result;
}
