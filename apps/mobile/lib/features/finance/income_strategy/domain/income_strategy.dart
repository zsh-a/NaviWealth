import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

/// Stable, open identifier for an independently composable strategy sleeve.
///
/// This is deliberately a value object instead of an enum: a new module can
/// define its own identifier without changing the composition engine.
class IncomeStrategySleeveKind {
  const IncomeStrategySleeveKind(this.wire)
    : assert(wire != '', 'Sleeve wire id must not be empty.');

  static const dividends = IncomeStrategySleeveKind('dividends');
  static const wheel = IncomeStrategySleeveKind('wheel');
  static const leapsCall = IncomeStrategySleeveKind('leaps_call');

  final String wire;

  @override
  bool operator ==(Object other) =>
      other is IncomeStrategySleeveKind && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => wire;
}

IncomeStrategySleeveKind incomeStrategySleeveKindFromWire(String wire) =>
    IncomeStrategySleeveKind(wire.trim());

/// Stable, module-owned cash-flow identifier.
class IncomeStrategyCashFlowKind {
  const IncomeStrategyCashFlowKind(this.wire)
    : assert(wire != '', 'Cash-flow wire id must not be empty.');

  static const dividend = IncomeStrategyCashFlowKind('dividend');
  static const dividendWithholding = IncomeStrategyCashFlowKind(
    'dividend_withholding',
  );
  static const optionRealized = IncomeStrategyCashFlowKind('option_realized');
  static const leapsPurchase = IncomeStrategyCashFlowKind('leaps_purchase');
  static const leapsSale = IncomeStrategyCashFlowKind('leaps_sale');
  static const leapsExercise = IncomeStrategyCashFlowKind('leaps_exercise');

  final String wire;

  @override
  bool operator ==(Object other) =>
      other is IncomeStrategyCashFlowKind && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

enum IncomeStrategyCashFlowState { actual, declared, estimated, contingent }

enum IncomeStrategyMetricQuality { complete, partial, stale, unavailable }

IncomeStrategyMetricQuality combineIncomeStrategyMetricQuality(
  Iterable<IncomeStrategyMetricQuality> qualities,
) {
  var result = IncomeStrategyMetricQuality.complete;
  for (final quality in qualities) {
    if (quality.index > result.index) result = quality;
  }
  return result;
}

/// A base-currency monetary metric with explicit completeness.
///
/// Unknown FX or missing marks must degrade [quality]; callers never silently
/// add amounts from different currencies.
class IncomeStrategyMoneyMetric {
  const IncomeStrategyMoneyMetric({
    required this.value,
    this.quality = IncomeStrategyMetricQuality.complete,
  });

  factory IncomeStrategyMoneyMetric.zero(
    String currency, {
    IncomeStrategyMetricQuality quality = IncomeStrategyMetricQuality.complete,
  }) =>
      IncomeStrategyMoneyMetric(value: Money.zero(currency), quality: quality);

  final Money value;
  final IncomeStrategyMetricQuality quality;

  IncomeStrategyMoneyMetric operator +(IncomeStrategyMoneyMetric other) =>
      IncomeStrategyMoneyMetric(
        value: value + other.value,
        quality: combineIncomeStrategyMetricQuality([quality, other.quality]),
      );
}

enum IncomeStrategyRiskSeverity { info, warning, critical }

/// Stable, open identifier for a deterministic risk finding.
class IncomeStrategyRiskCode {
  const IncomeStrategyRiskCode(this.wire)
    : assert(wire != '', 'Risk wire id must not be empty.');

  static const unplannedSleeve = IncomeStrategyRiskCode('unplanned_sleeve');
  static const capitalBudgetExceeded = IncomeStrategyRiskCode(
    'capital_budget_exceeded',
  );
  static const assignmentBudgetExceeded = IncomeStrategyRiskCode(
    'assignment_budget_exceeded',
  );
  static const concentrationExceeded = IncomeStrategyRiskCode(
    'concentration_exceeded',
  );
  static const dividendInterruption = IncomeStrategyRiskCode(
    'dividend_interruption',
  );
  static const stackedDownside = IncomeStrategyRiskCode('stacked_downside');
  static const leapsBudgetExceeded = IncomeStrategyRiskCode(
    'leaps_budget_exceeded',
  );
  static const leapsCostNotCovered = IncomeStrategyRiskCode(
    'leaps_cost_not_covered',
  );
  static const missingMarketValue = IncomeStrategyRiskCode(
    'missing_market_value',
  );
  static const missingDelta = IncomeStrategyRiskCode('missing_delta');
  static const missingFxRate = IncomeStrategyRiskCode('missing_fx_rate');
  static const staleValuation = IncomeStrategyRiskCode('stale_valuation');
  static const expirationNear = IncomeStrategyRiskCode('expiration_near');
  static const incomeTargetAtRisk = IncomeStrategyRiskCode(
    'income_target_at_risk',
  );

  final String wire;

  @override
  bool operator ==(Object other) =>
      other is IncomeStrategyRiskCode && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
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

/// Domain-owned source reference. AI adapters convert this into EvidenceAnchor.
class IncomeStrategySourceRef {
  const IncomeStrategySourceRef({
    required this.table,
    required this.id,
    this.complete = true,
  });

  final String table;
  final String id;
  final bool complete;
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
    required this.baseAmount,
    required this.source,
  });

  final String id;
  final String assetId;
  final IncomeStrategySleeveKind sleeve;
  final IncomeStrategyCashFlowKind kind;
  final IncomeStrategyCashFlowState state;
  final DateTime date;

  /// Signed original-currency movement: received is positive, paid is negative.
  final Money amount;

  /// Same movement valued in the portfolio base currency. Null means the
  /// required historical FX rate is unavailable.
  final Money? baseAmount;
  final IncomeStrategySourceRef source;
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

/// Typed cross-sleeve capabilities consumed by coordination rules.
///
/// Module-specific lifecycle objects belong in [IncomeStrategySleeveDetails],
/// never in a string-keyed facts map.
class IncomeStrategyExposure {
  const IncomeStrategyExposure({
    required this.capitalAtRisk,
    this.marketValue,
    this.deltaEquivalentShares,
    this.assignmentObligation,
    this.holdingQuantity,
    this.holdingWeight,
    this.hasOpenShortPut = false,
    this.hasOpenCoveredCall = false,
  });

  final IncomeStrategyMoneyMetric capitalAtRisk;
  final IncomeStrategyMoneyMetric? marketValue;
  final Decimal? deltaEquivalentShares;
  final IncomeStrategyMoneyMetric? assignmentObligation;
  final Decimal? holdingQuantity;
  final Decimal? holdingWeight;
  final bool hasOpenShortPut;
  final bool hasOpenCoveredCall;
}

abstract interface class IncomeStrategySleeveDetails {
  const IncomeStrategySleeveDetails();
}

class IncomeStrategySleeveSnapshot {
  const IncomeStrategySleeveSnapshot({
    required this.kind,
    required this.status,
    required this.periodStart,
    required this.asOf,
    required this.realizedIncome,
    required this.realizedResult,
    required this.projectedCash,
    required this.exposure,
    required this.cashFlows,
    required this.risks,
    this.details,
  });

  final IncomeStrategySleeveKind kind;
  final String status;

  /// Realized-result reporting window. Current modules use calendar YTD.
  final DateTime periodStart;
  final DateTime asOf;
  final IncomeStrategyMoneyMetric realizedIncome;
  final IncomeStrategyMoneyMetric realizedResult;
  final IncomeStrategyMoneyMetric projectedCash;
  final IncomeStrategyExposure exposure;
  final List<IncomeStrategyCashFlow> cashFlows;
  final List<IncomeStrategyRisk> risks;
  final IncomeStrategySleeveDetails? details;

  IncomeStrategyMoneyMetric get capitalAtRisk => exposure.capitalAtRisk;
  IncomeStrategyMoneyMetric? get marketValue => exposure.marketValue;
  Decimal? get deltaEquivalentShares => exposure.deltaEquivalentShares;
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
    required this.baseCurrency,
    required this.periodStart,
    required this.asOf,
    required this.enabledSleeves,
    required this.sleeves,
    required this.risks,
    this.capitalBudget,
    this.annualIncomeTarget,
  });

  final IncomeStrategyAsset asset;
  final String baseCurrency;
  final DateTime periodStart;
  final DateTime asOf;
  final Set<IncomeStrategySleeveKind> enabledSleeves;
  final Map<IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot> sleeves;
  final List<IncomeStrategyRisk> risks;
  final Money? capitalBudget;
  final Money? annualIncomeTarget;

  IncomeStrategyMoneyMetric get realizedResult => _sumMetrics(
    baseCurrency,
    sleeves.values.map((value) => value.realizedResult),
  );

  IncomeStrategyMoneyMetric get realizedIncome => _sumMetrics(
    baseCurrency,
    sleeves.values.map((value) => value.realizedIncome),
  );

  IncomeStrategyMoneyMetric get projectedCash => _sumMetrics(
    baseCurrency,
    sleeves.values.map((value) => value.projectedCash),
  );

  IncomeStrategyMoneyMetric get capitalAtRisk => _sumMetrics(
    baseCurrency,
    sleeves.values.map((value) => value.capitalAtRisk),
  );

  IncomeStrategyMoneyMetric get actualCashMovement {
    var value = Money.zero(baseCurrency);
    var quality = IncomeStrategyMetricQuality.complete;
    for (final flow in cashFlows.where(
      (flow) =>
          flow.state == IncomeStrategyCashFlowState.actual &&
          !flow.date.isBefore(periodStart) &&
          !flow.date.isAfter(asOf),
    )) {
      final base = flow.baseAmount;
      if (base == null) {
        quality = IncomeStrategyMetricQuality.partial;
      } else {
        value += base;
      }
    }
    return IncomeStrategyMoneyMetric(value: value, quality: quality);
  }

  Decimal? get deltaEquivalentShares {
    final values = sleeves.values
        .map((value) => value.deltaEquivalentShares)
        .whereType<Decimal>()
        .toList(growable: false);
    return values.isEmpty ? null : _sumDecimal(values);
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
    required this.periodStart,
    required this.asOf,
    required this.underlyings,
    required this.unassignedCashFlows,
  });

  final String baseCurrency;
  final DateTime periodStart;
  final DateTime asOf;
  final List<UnderlyingIncomeStrategySnapshot> underlyings;
  final List<IncomeStrategyCashFlow> unassignedCashFlows;

  IncomeStrategyMoneyMetric get realizedResult => _sumMetrics(
    baseCurrency,
    underlyings.map((value) => value.realizedResult),
  );

  IncomeStrategyMoneyMetric get realizedIncome => _sumMetrics(
    baseCurrency,
    underlyings.map((value) => value.realizedIncome),
  );

  IncomeStrategyMoneyMetric get projectedCash {
    final assigned = _sumMetrics(
      baseCurrency,
      underlyings.map((value) => value.projectedCash),
    );
    var unassigned = Money.zero(baseCurrency);
    var quality = IncomeStrategyMetricQuality.complete;
    for (final flow in unassignedCashFlows.where(
      (flow) =>
          flow.state == IncomeStrategyCashFlowState.declared ||
          flow.state == IncomeStrategyCashFlowState.estimated,
    )) {
      final base = flow.baseAmount;
      if (base == null) {
        quality = IncomeStrategyMetricQuality.partial;
      } else {
        unassigned += base;
      }
    }
    return assigned +
        IncomeStrategyMoneyMetric(value: unassigned, quality: quality);
  }

  IncomeStrategyMoneyMetric get capitalAtRisk => _sumMetrics(
    baseCurrency,
    underlyings.map((value) => value.capitalAtRisk),
  );

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

IncomeStrategyMoneyMetric _sumMetrics(
  String currency,
  Iterable<IncomeStrategyMoneyMetric> values,
) {
  var result = IncomeStrategyMoneyMetric.zero(currency);
  for (final value in values) {
    result += value;
  }
  return result;
}

Decimal _sumDecimal(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}
