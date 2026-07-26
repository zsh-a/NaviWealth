import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'income_strategy.dart';
import 'income_strategy_plan.dart';
import 'income_strategy_rule.dart';

/// Pure composition boundary for every current and future strategy module.
///
/// The assembler knows no concrete sleeve ids and no strategy-specific rule.
/// Modules contribute snapshots; registered [rules] coordinate them.
class IncomeStrategyAssembler {
  const IncomeStrategyAssembler();

  PortfolioIncomeStrategySnapshot assemble({
    required String baseCurrency,
    required DateTime asOf,
    required CurrencyConverter converter,
    required Iterable<IncomeStrategyPlan> plans,
    required Iterable<IncomeStrategySleeveContribution> contributions,
    required Iterable<IncomeStrategyRule> rules,
    Iterable<IncomeStrategyCashFlow> unassignedCashFlows = const [],
  }) {
    final normalizedBase = baseCurrency.trim().toUpperCase();
    final clock = asOf.toUtc();
    final periodStart = DateTime.utc(clock.year);
    final planByAsset = {for (final plan in plans) plan.assetId: plan};
    final assets = <String, IncomeStrategyAsset>{};
    final sleeves =
        <String, Map<IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot>>{};

    for (final plan in plans) {
      assets[plan.assetId] = IncomeStrategyAsset(
        assetId: plan.assetId,
        symbol: plan.symbol,
        market: plan.market,
        currency: plan.currency,
      );
    }
    for (final contribution in contributions) {
      _validateBaseCurrency(contribution.snapshot, normalizedBase);
      final assetId = contribution.asset.assetId;
      assets[assetId] = contribution.asset;
      final byKind = sleeves.putIfAbsent(
        assetId,
        () => <IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot>{},
      );
      if (byKind.containsKey(contribution.snapshot.kind)) {
        throw StateError(
          'Duplicate ${contribution.snapshot.kind.wire} sleeve for $assetId',
        );
      }
      byKind[contribution.snapshot.kind] = contribution.snapshot;
    }

    final underlyings = <UnderlyingIncomeStrategySnapshot>[];
    for (final entry in assets.entries) {
      final plan = planByAsset[entry.key];
      final byKind =
          sleeves[entry.key] ??
          const <IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot>{};
      final enabled =
          plan?.enabledSleeves ?? Set<IncomeStrategySleeveKind>.of(byKind.keys);
      final context = IncomeStrategyRuleContext(
        baseCurrency: normalizedBase,
        asOf: clock,
        asset: entry.value,
        plan: plan,
        enabledSleeves: enabled,
        sleeves: byKind,
        converter: converter,
      );
      final risks = <IncomeStrategyRisk>[
        for (final sleeve in byKind.values) ...sleeve.risks,
        for (final rule in rules) ...rule.evaluate(context),
      ];
      underlyings.add(
        UnderlyingIncomeStrategySnapshot(
          asset: entry.value,
          baseCurrency: normalizedBase,
          periodStart: periodStart,
          asOf: clock,
          enabledSleeves: Set.unmodifiable(enabled),
          sleeves: Map.unmodifiable(byKind),
          risks: List.unmodifiable(risks),
          capitalBudget: context.tryConvertToBase(plan?.capitalBudgetMoney),
          annualIncomeTarget: context.tryConvertToBase(
            plan?.annualIncomeTargetMoney,
          ),
        ),
      );
    }

    underlyings.sort((a, b) {
      if (a.hasActiveRisk != b.hasActiveRisk) return a.hasActiveRisk ? -1 : 1;
      final aActive = a.sleeves.isNotEmpty;
      final bActive = b.sleeves.isNotEmpty;
      if (aActive != bActive) return aActive ? -1 : 1;
      return a.asset.symbol.compareTo(b.asset.symbol);
    });
    return PortfolioIncomeStrategySnapshot(
      baseCurrency: normalizedBase,
      periodStart: periodStart,
      asOf: clock,
      underlyings: List.unmodifiable(underlyings),
      unassignedCashFlows: List.unmodifiable(unassignedCashFlows),
    );
  }

  void _validateBaseCurrency(
    IncomeStrategySleeveSnapshot snapshot,
    String baseCurrency,
  ) {
    final metrics = <IncomeStrategyMoneyMetric>[
      snapshot.realizedIncome,
      snapshot.realizedResult,
      snapshot.projectedCash,
      snapshot.capitalAtRisk,
      ?snapshot.marketValue,
      ?snapshot.exposure.assignmentObligation,
    ];
    for (final metric in metrics) {
      if (metric.value.currency != baseCurrency) {
        throw StateError(
          '${snapshot.kind.wire} contributed ${metric.value.currency} '
          'metric to $baseCurrency portfolio.',
        );
      }
    }
    for (final flow in snapshot.cashFlows) {
      final base = flow.baseAmount;
      if (base != null && base.currency != baseCurrency) {
        throw StateError(
          '${snapshot.kind.wire} cash flow ${flow.id} has '
          '${base.currency} base amount in $baseCurrency portfolio.',
        );
      }
    }
  }
}
