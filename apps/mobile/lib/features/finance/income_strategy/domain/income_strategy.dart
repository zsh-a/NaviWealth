import 'package:decimal/decimal.dart';

/// Independently composable strategy sleeves for one underlying.
///
/// A sleeve is a source of exposure and cash-flow facts, not a shared trade
/// state machine. New sleeves can participate by contributing a snapshot to
/// [IncomeStrategyAssembler].
enum IncomeStrategySleeveKind { dividends, wheel, leapsCall }

extension IncomeStrategySleeveKindWire on IncomeStrategySleeveKind {
  String get wire => switch (this) {
    IncomeStrategySleeveKind.dividends => 'dividends',
    IncomeStrategySleeveKind.wheel => 'wheel',
    IncomeStrategySleeveKind.leapsCall => 'leaps_call',
  };
}

IncomeStrategySleeveKind? incomeStrategySleeveKindFromWire(String wire) =>
    switch (wire) {
      'dividends' => IncomeStrategySleeveKind.dividends,
      'wheel' => IncomeStrategySleeveKind.wheel,
      'leaps_call' => IncomeStrategySleeveKind.leapsCall,
      _ => null,
    };

enum IncomeStrategyCashFlowKind {
  dividend,
  dividendWithholding,
  optionRealized,
  leapsPurchase,
  leapsSale,
  leapsExercise,
}

enum IncomeStrategyCashFlowState { actual, declared, estimated, contingent }

enum IncomeStrategyRiskSeverity { info, warning, critical }

enum IncomeStrategyRiskCode {
  unplannedSleeve,
  capitalBudgetExceeded,
  assignmentBudgetExceeded,
  concentrationExceeded,
  dividendInterruption,
  stackedDownside,
  leapsBudgetExceeded,
  leapsCostNotCovered,
  missingMarketValue,
  missingDelta,
  expirationNear,
}

class IncomeStrategyAsset {
  const IncomeStrategyAsset({
    required this.assetId,
    required this.symbol,
    required this.market,
    required this.currency,
    this.label,
  });

  final String assetId;
  final String symbol;
  final String market;
  final String currency;
  final String? label;

  String get displayLabel {
    final value = label?.trim();
    return value == null || value.isEmpty ? symbol : value;
  }
}

class IncomeStrategyCashFlow {
  const IncomeStrategyCashFlow({
    required this.id,
    required this.assetId,
    required this.sleeve,
    required this.kind,
    required this.state,
    required this.date,
    required this.amount,
    required this.currency,
    required this.sourceTable,
    required this.sourceId,
    required this.hasCompleteEvidence,
  });

  final String id;
  final String assetId;
  final IncomeStrategySleeveKind sleeve;
  final IncomeStrategyCashFlowKind kind;
  final IncomeStrategyCashFlowState state;
  final DateTime date;

  /// Signed amount: cash received is positive and cash paid is negative.
  final Decimal amount;
  final String currency;
  final String sourceTable;
  final String sourceId;
  final bool hasCompleteEvidence;
}

class IncomeStrategyRisk {
  const IncomeStrategyRisk({
    required this.code,
    required this.severity,
    required this.assetId,
    required this.sleeves,
    this.evidence = const <String, Object?>{},
  });

  final IncomeStrategyRiskCode code;
  final IncomeStrategyRiskSeverity severity;
  final String assetId;
  final Set<IncomeStrategySleeveKind> sleeves;
  final Map<String, Object?> evidence;
}

class IncomeStrategySleeveSnapshot {
  const IncomeStrategySleeveSnapshot({
    required this.kind,
    required this.status,
    required this.realizedResult,
    required this.projectedCash,
    required this.capitalAtRisk,
    required this.marketValue,
    required this.deltaEquivalentShares,
    required this.cashFlows,
    required this.risks,
    this.facts = const <String, Object?>{},
  });

  final IncomeStrategySleeveKind kind;
  final String status;

  /// Realized economic result. This is deliberately separate from cash
  /// movement so buying a long call is not treated as an immediate loss.
  final Decimal realizedResult;
  final Decimal projectedCash;
  final Decimal capitalAtRisk;
  final Decimal? marketValue;
  final Decimal? deltaEquivalentShares;
  final List<IncomeStrategyCashFlow> cashFlows;
  final List<IncomeStrategyRisk> risks;

  /// Sleeve-specific read-only facts consumed by deterministic coordination
  /// rules and drill-down UI. Facts must never become persistence contracts.
  final Map<String, Object?> facts;
}

class IncomeStrategySleeveContribution {
  const IncomeStrategySleeveContribution({
    required this.asset,
    required this.snapshot,
  });

  final IncomeStrategyAsset asset;
  final IncomeStrategySleeveSnapshot snapshot;
}

class UnderlyingIncomeStrategySnapshot {
  const UnderlyingIncomeStrategySnapshot({
    required this.asset,
    required this.enabledSleeves,
    required this.sleeves,
    required this.risks,
    this.capitalBudget,
    this.annualIncomeTarget,
  });

  final IncomeStrategyAsset asset;
  final Set<IncomeStrategySleeveKind> enabledSleeves;
  final Map<IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot> sleeves;
  final List<IncomeStrategyRisk> risks;
  final Decimal? capitalBudget;
  final Decimal? annualIncomeTarget;

  Decimal get realizedResult =>
      _sum(sleeves.values.map((value) => value.realizedResult));

  Decimal get projectedCash =>
      _sum(sleeves.values.map((value) => value.projectedCash));

  Decimal get capitalAtRisk =>
      _sum(sleeves.values.map((value) => value.capitalAtRisk));

  Decimal get actualCashMovement => _sum(
    cashFlows
        .where((flow) => flow.state == IncomeStrategyCashFlowState.actual)
        .map((flow) => flow.amount),
  );

  Decimal? get deltaEquivalentShares {
    final values = sleeves.values
        .map((value) => value.deltaEquivalentShares)
        .toList(growable: false);
    if (values.isEmpty || values.any((value) => value == null)) return null;
    return _sum(values.cast<Decimal>());
  }

  List<IncomeStrategyCashFlow> get cashFlows {
    final values = [for (final sleeve in sleeves.values) ...sleeve.cashFlows]
      ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(values);
  }

  bool get hasActiveRisk =>
      risks.any((risk) => risk.severity != IncomeStrategyRiskSeverity.info);
}

class PortfolioIncomeStrategySnapshot {
  const PortfolioIncomeStrategySnapshot({
    required this.baseCurrency,
    required this.underlyings,
    required this.unassignedCashFlows,
  });

  final String baseCurrency;
  final List<UnderlyingIncomeStrategySnapshot> underlyings;
  final List<IncomeStrategyCashFlow> unassignedCashFlows;

  Decimal get realizedResult =>
      _sum(underlyings.map((value) => value.realizedResult));
  Decimal get projectedCash =>
      _sum(underlyings.map((value) => value.projectedCash)) +
      _sum(
        unassignedCashFlows
            .where(
              (flow) =>
                  flow.state == IncomeStrategyCashFlowState.declared ||
                  flow.state == IncomeStrategyCashFlowState.estimated,
            )
            .map((flow) => flow.amount),
      );
  Decimal get capitalAtRisk =>
      _sum(underlyings.map((value) => value.capitalAtRisk));
  int get activeRiskCount => underlyings
      .expand((value) => value.risks)
      .where((risk) => risk.severity != IncomeStrategyRiskSeverity.info)
      .length;

  List<IncomeStrategyCashFlow> get activity {
    final values = [
      for (final underlying in underlyings) ...underlying.cashFlows,
      ...unassignedCashFlows,
    ]..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(values);
  }
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}
