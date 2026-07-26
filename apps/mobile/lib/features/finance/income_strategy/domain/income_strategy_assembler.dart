import 'package:decimal/decimal.dart';

import 'income_strategy.dart';
import 'income_strategy_plan.dart';

/// Pure composition boundary for every current and future income sleeve.
class IncomeStrategyAssembler {
  const IncomeStrategyAssembler();

  PortfolioIncomeStrategySnapshot assemble({
    required String baseCurrency,
    required Iterable<IncomeStrategyPlan> plans,
    required Iterable<IncomeStrategySleeveContribution> contributions,
    Iterable<IncomeStrategyCashFlow> unassignedCashFlows = const [],
  }) {
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
      final risks = <IncomeStrategyRisk>[
        for (final sleeve in byKind.values) ...sleeve.risks,
        ..._coordinationRisks(
          assetId: entry.key,
          enabled: enabled,
          sleeves: byKind,
          plan: plan,
        ),
      ];
      underlyings.add(
        UnderlyingIncomeStrategySnapshot(
          asset: entry.value,
          enabledSleeves: Set.unmodifiable(enabled),
          sleeves: Map.unmodifiable(byKind),
          risks: List.unmodifiable(risks),
          capitalBudget: plan?.capitalBudget,
          annualIncomeTarget: plan?.annualIncomeTarget,
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
      baseCurrency: baseCurrency,
      underlyings: List.unmodifiable(underlyings),
      unassignedCashFlows: List.unmodifiable(unassignedCashFlows),
    );
  }

  List<IncomeStrategyRisk> _coordinationRisks({
    required String assetId,
    required Set<IncomeStrategySleeveKind> enabled,
    required Map<IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot>
    sleeves,
    required IncomeStrategyPlan? plan,
  }) {
    final risks = <IncomeStrategyRisk>[];
    for (final kind in sleeves.keys.where((kind) => !enabled.contains(kind))) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.unplannedSleeve,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: assetId,
          sleeves: {kind},
        ),
      );
    }

    final wheel = sleeves[IncomeStrategySleeveKind.wheel];
    final leaps = sleeves[IncomeStrategySleeveKind.leapsCall];
    final capitalBudget = plan?.capitalBudget;
    final totalCapital = sleeves.values.fold(
      Decimal.zero,
      (sum, sleeve) => sum + sleeve.capitalAtRisk,
    );
    if (capitalBudget != null && totalCapital > capitalBudget) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.capitalBudgetExceeded,
          severity: IncomeStrategyRiskSeverity.critical,
          assetId: assetId,
          sleeves: Set.unmodifiable(sleeves.keys),
          evidence: {
            'capital_at_risk': totalCapital.toString(),
            'limit': capitalBudget.toString(),
          },
        ),
      );
    }
    if (wheel?.facts['has_open_short_put'] == true && leaps != null) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.stackedDownside,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: assetId,
          sleeves: const {
            IncomeStrategySleeveKind.wheel,
            IncomeStrategySleeveKind.leapsCall,
          },
        ),
      );
    }
    if (leaps != null && leaps.capitalAtRisk > Decimal.zero) {
      final fundingResult =
          (sleeves[IncomeStrategySleeveKind.dividends]?.realizedResult ??
              Decimal.zero) +
          (wheel?.realizedResult ?? Decimal.zero);
      if (fundingResult < leaps.capitalAtRisk) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.leapsCostNotCovered,
            severity: IncomeStrategyRiskSeverity.warning,
            assetId: assetId,
            sleeves: const {
              IncomeStrategySleeveKind.dividends,
              IncomeStrategySleeveKind.wheel,
              IncomeStrategySleeveKind.leapsCall,
            },
            evidence: {
              'realized_income': fundingResult.toString(),
              'open_leaps_cost': leaps.capitalAtRisk.toString(),
            },
          ),
        );
      }
    }
    if (plan?.preserveDividend == true &&
        plan?.allowSharesCalledAway == false &&
        wheel?.facts['has_open_covered_call'] == true) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.dividendInterruption,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: assetId,
          sleeves: const {
            IncomeStrategySleeveKind.dividends,
            IncomeStrategySleeveKind.wheel,
          },
        ),
      );
    }

    final maxLeapsCost = plan?.maxLeapsCost;
    if (maxLeapsCost != null &&
        (leaps?.capitalAtRisk ?? Decimal.zero) > maxLeapsCost) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.leapsBudgetExceeded,
          severity: IncomeStrategyRiskSeverity.critical,
          assetId: assetId,
          sleeves: const {IncomeStrategySleeveKind.leapsCall},
          evidence: {
            'capital_at_risk': leaps!.capitalAtRisk.toString(),
            'limit': maxLeapsCost.toString(),
          },
        ),
      );
    }
    final maxAssignment = plan?.maxAssignmentValue;
    final assignmentValue = wheel?.facts['assignment_value'];
    if (maxAssignment != null &&
        assignmentValue is Decimal &&
        assignmentValue > maxAssignment) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.assignmentBudgetExceeded,
          severity: IncomeStrategyRiskSeverity.critical,
          assetId: assetId,
          sleeves: const {IncomeStrategySleeveKind.wheel},
          evidence: {
            'assignment_value': assignmentValue.toString(),
            'limit': maxAssignment.toString(),
          },
        ),
      );
    }
    final maxWeight = plan?.maxPositionWeight;
    final holdingWeight =
        sleeves[IncomeStrategySleeveKind.dividends]?.facts['holding_weight'];
    if (maxWeight != null &&
        holdingWeight is Decimal &&
        holdingWeight > maxWeight) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.concentrationExceeded,
          severity: IncomeStrategyRiskSeverity.critical,
          assetId: assetId,
          sleeves: const {IncomeStrategySleeveKind.dividends},
          evidence: {
            'weight': holdingWeight.toString(),
            'limit': maxWeight.toString(),
          },
        ),
      );
    }
    return risks;
  }
}
