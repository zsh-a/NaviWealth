import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'income_strategy.dart';
import 'income_strategy_plan.dart';

class IncomeStrategyRuleContext {
  const IncomeStrategyRuleContext({
    required this.baseCurrency,
    required this.asOf,
    required this.asset,
    required this.plan,
    required this.enabledSleeves,
    required this.sleeves,
    required this.converter,
  });

  final String baseCurrency;
  final DateTime asOf;
  final IncomeStrategyAsset asset;
  final IncomeStrategyPlan? plan;
  final Set<IncomeStrategySleeveKind> enabledSleeves;
  final Map<IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot> sleeves;
  final CurrencyConverter converter;

  Money? tryConvertToBase(Money? value, {DateTime? on}) {
    if (value == null) return null;
    try {
      return converter.convert(value, baseCurrency, on: on ?? asOf);
    } on FxRateNotFoundError {
      return null;
    }
  }
}

abstract interface class IncomeStrategyRule {
  IncomeStrategyRiskCode get code;

  Iterable<IncomeStrategyRisk> evaluate(IncomeStrategyRuleContext context);
}
