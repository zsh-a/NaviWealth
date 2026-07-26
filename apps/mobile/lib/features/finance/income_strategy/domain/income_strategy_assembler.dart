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
    Iterable<IncomeStrategyGroupRule> groupRules = const [],
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

    // Pass 1 — per-asset contexts and per-asset rule findings.
    final contexts = <String, IncomeStrategyRuleContext>{};
    final assetRisks = <String, List<IncomeStrategyRisk>>{};
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
      contexts[entry.key] = context;
      assetRisks[entry.key] = <IncomeStrategyRisk>[
        for (final sleeve in byKind.values) ...sleeve.risks,
        for (final rule in rules) ...rule.evaluate(context),
      ];
    }

    // Pass 2 — strategy groups. Every asset lands in exactly one group:
    // its plan's explicit groupId, or an implicit singleton keyed by
    // assetId. Group rules run once per group; singleton findings merge
    // back into the member so ungrouped assets behave exactly as before.
    final groupMembers = <String, List<String>>{};
    final explicitGroups = <String>{};
    for (final assetId in assets.keys) {
      final plan = planByAsset[assetId];
      final groupId = plan?.groupId;
      final key = groupId == null || groupId.isEmpty ? assetId : groupId;
      if (key != assetId) explicitGroups.add(key);
      groupMembers.putIfAbsent(key, () => <String>[]).add(assetId);
    }

    final groupRisksById = <String, List<IncomeStrategyRisk>>{};
    final groupLabels = <String, String>{};
    for (final entry in groupMembers.entries) {
      final isExplicit = explicitGroups.contains(entry.key);
      final memberContexts = [
        for (final assetId in entry.value) contexts[assetId]!,
      ];
      String label;
      if (isExplicit) {
        final named = entry.value
            .map((assetId) => planByAsset[assetId]?.groupLabel?.trim())
            .where((value) => value != null && value.isNotEmpty)
            .firstOrNull;
        label =
            named ??
            memberContexts.map((context) => context.asset.symbol).join(' + ');
      } else {
        label = memberContexts.first.asset.symbol;
      }
      groupLabels[entry.key] = label;
      final groupContext = IncomeStrategyGroupRuleContext(
        groupId: entry.key,
        groupLabel: label,
        isExplicit: isExplicit,
        baseCurrency: normalizedBase,
        asOf: clock,
        converter: converter,
        members: memberContexts,
      );
      final findings = <IncomeStrategyRisk>[
        for (final rule in groupRules) ...rule.evaluate(groupContext),
      ];
      if (isExplicit) {
        groupRisksById[entry.key] = findings;
      } else {
        // Singleton: keep the finding on the underlying, same as the old
        // per-asset coordination rules.
        assetRisks[entry.value.single]!.addAll(findings);
      }
    }

    final underlyingById = <String, UnderlyingIncomeStrategySnapshot>{};
    final underlyings = <UnderlyingIncomeStrategySnapshot>[];
    for (final entry in assets.entries) {
      final context = contexts[entry.key]!;
      final plan = planByAsset[entry.key];
      final underlying = UnderlyingIncomeStrategySnapshot(
        asset: entry.value,
        baseCurrency: normalizedBase,
        periodStart: periodStart,
        asOf: clock,
        enabledSleeves: Set.unmodifiable(context.enabledSleeves),
        sleeves: Map.unmodifiable(context.sleeves),
        risks: List.unmodifiable(assetRisks[entry.key]!),
        capitalBudget: context.tryConvertToBase(plan?.capitalBudgetMoney),
        annualIncomeTarget: context.tryConvertToBase(
          plan?.annualIncomeTargetMoney,
        ),
      );
      underlyingById[entry.key] = underlying;
      underlyings.add(underlying);
    }

    underlyings.sort((a, b) {
      if (a.hasActiveRisk != b.hasActiveRisk) return a.hasActiveRisk ? -1 : 1;
      final aActive = a.sleeves.isNotEmpty;
      final bActive = b.sleeves.isNotEmpty;
      if (aActive != bActive) return aActive ? -1 : 1;
      return a.asset.symbol.compareTo(b.asset.symbol);
    });

    final groups =
        <IncomeStrategyGroupSnapshot>[
          for (final entry in groupMembers.entries)
            IncomeStrategyGroupSnapshot(
              id: entry.key,
              label: groupLabels[entry.key]!,
              isExplicit: explicitGroups.contains(entry.key),
              baseCurrency: normalizedBase,
              members: List.unmodifiable([
                for (final assetId in entry.value) underlyingById[assetId]!,
              ]),
              risks: List.unmodifiable(
                groupRisksById[entry.key] ?? const <IncomeStrategyRisk>[],
              ),
            ),
        ]..sort((a, b) {
          if (a.hasActiveRisk != b.hasActiveRisk) {
            return a.hasActiveRisk ? -1 : 1;
          }
          return a.label.compareTo(b.label);
        });

    return PortfolioIncomeStrategySnapshot(
      baseCurrency: normalizedBase,
      periodStart: periodStart,
      asOf: clock,
      underlyings: List.unmodifiable(underlyings),
      unassignedCashFlows: List.unmodifiable(unassignedCashFlows),
      groups: List.unmodifiable(groups),
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
