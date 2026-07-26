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

/// Group-scope evaluation context: the member contexts of one strategy
/// group. For implicit singleton groups this degenerates to exactly one
/// member, so group rules subsume the old per-asset behaviour without a
/// second code path.
class IncomeStrategyGroupRuleContext {
  const IncomeStrategyGroupRuleContext({
    required this.groupId,
    required this.groupLabel,
    required this.isExplicit,
    required this.baseCurrency,
    required this.asOf,
    required this.converter,
    required this.members,
  });

  final String groupId;
  final String groupLabel;
  final bool isExplicit;
  final String baseCurrency;
  final DateTime asOf;
  final CurrencyConverter converter;
  final List<IncomeStrategyRuleContext> members;

  /// Every member sleeve of [kind] across the group, paired with the
  /// member context that owns it.
  Iterable<(IncomeStrategyRuleContext, IncomeStrategySleeveSnapshot)> sleevesOf(
    IncomeStrategySleeveKind kind,
  ) sync* {
    for (final member in members) {
      final sleeve = member.sleeves[kind];
      if (sleeve != null) yield (member, sleeve);
    }
  }

  Money? tryConvertToBase(Money? value, {DateTime? on}) {
    if (value == null) return null;
    try {
      return converter.convert(value, baseCurrency, on: on ?? asOf);
    } on FxRateNotFoundError {
      return null;
    }
  }
}

/// A coordination rule that reasons across every member of a strategy
/// group. Wheel-funds-LEAPS and stacked-downside belong here: the legs
/// may sit on different underlyings (TQQQ wheel + QQQ LEAPS).
abstract interface class IncomeStrategyGroupRule {
  IncomeStrategyRiskCode get code;

  Iterable<IncomeStrategyRisk> evaluate(IncomeStrategyGroupRuleContext context);
}
