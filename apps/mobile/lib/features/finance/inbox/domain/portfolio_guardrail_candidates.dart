import '../../analytics/domain/concentration_risk.dart';
import '../../cashflow/domain/dividend_policy_monitor.dart';
import '../../composition/finance_route_paths.dart';
import '../../rebalance/domain/rebalance_models.dart';
import 'financial_inbox.dart';

/// Pure mappers: concentration / rebalance / dividend policy → inbox candidates.
///
/// Kept free of Riverpod so unit tests can assert sourceKey stability, priority,
/// route, and presence/absence without a full provider graph.
class PortfolioGuardrailCandidates {
  const PortfolioGuardrailCandidates();

  /// One open signal per concentration breach (stable [sourceKey] per
  /// dimension + label so repository upsert / revalidation stay idempotent).
  List<FinancialSignalCandidate> fromConcentrationAlerts(
    Iterable<ConcentrationAlert> alerts, {
    String route = FinanceRoutes.wealthPortfolio,
  }) {
    final items = <FinancialSignalCandidate>[];
    for (final alert in alerts) {
      items.add(
        FinancialSignalCandidate(
          sourceKey: concentrationSourceKey(alert.dimension, alert.label),
          kind: FinancialInboxKind.concentrationRisk,
          priority: alert.severity == RiskSeverity.critical
              ? FinancialInboxPriority.important
              : FinancialInboxPriority.attention,
          count: 1,
          route: route,
          evidence: <String, Object?>{
            'dimension': alert.dimension.name,
            'label': alert.label,
            'weight': alert.weight,
            'threshold': alert.threshold,
            'severity': alert.severity.name,
            'asset_ids': List<String>.unmodifiable(alert.assetIds),
          },
        ),
      );
    }
    return List.unmodifiable(items);
  }

  /// Emits a single rebalance-drift signal when the user has configured at
  /// least one security-level asset target and any asset or residual category
  /// drift exceeds the engine warning threshold.
  List<FinancialSignalCandidate> fromRebalancePlan(
    RebalancePlan? plan, {
    String route = FinanceRoutes.planRebalance,
  }) {
    if (plan == null) return const <FinancialSignalCandidate>[];
    if (plan.target.assetTargets.isEmpty) {
      return const <FinancialSignalCandidate>[];
    }

    final breached = plan.drifts
        .where((drift) => drift.severity != DriftSeverity.ok)
        .toList(growable: false);
    if (breached.isEmpty) return const <FinancialSignalCandidate>[];

    final hasCritical = breached.any(
      (drift) => drift.severity == DriftSeverity.critical,
    );
    var maxAbsDeviation = 0.0;
    for (final drift in breached) {
      if (drift.absDeviation > maxAbsDeviation) {
        maxAbsDeviation = drift.absDeviation;
      }
    }
    final assetBreachCount = breached.where((d) => d.isAssetTarget).length;
    final categoryBreachCount = breached.length - assetBreachCount;

    return List.unmodifiable([
      FinancialSignalCandidate(
        sourceKey: rebalanceDriftSourceKey,
        kind: FinancialInboxKind.rebalanceDrift,
        priority: hasCritical
            ? FinancialInboxPriority.important
            : FinancialInboxPriority.attention,
        count: breached.length,
        route: route,
        evidence: <String, Object?>{
          'breach_count': breached.length,
          'asset_breach_count': assetBreachCount,
          'category_breach_count': categoryBreachCount,
          'max_abs_deviation': maxAbsDeviation,
          'drift_before_pct': plan.driftBeforePct,
        },
      ),
    ]);
  }

  /// One signal per held asset with TTM dividend deterioration.
  List<FinancialSignalCandidate> fromDividendDeteriorations(
    Iterable<DividendDeterioration> rows, {
    String route = FinanceRoutes.cashflowDividends,
  }) {
    final items = <FinancialSignalCandidate>[];
    for (final row in rows) {
      items.add(
        FinancialSignalCandidate(
          sourceKey: dividendDeteriorationSourceKey(row.assetId),
          kind: FinancialInboxKind.dividendDeterioration,
          priority: row.severity == DividendDeteriorationSeverity.critical
              ? FinancialInboxPriority.important
              : FinancialInboxPriority.attention,
          count: 1,
          route: route,
          evidence: <String, Object?>{
            'asset_id': row.assetId,
            'label': row.assetLabel,
            'ttm_gross': row.ttmGrossInBase.toString(),
            'prior_ttm_gross': row.priorTtmGrossInBase.toString(),
            'drop_ratio': row.dropRatio,
            'severity': row.severity.name,
          },
        ),
      );
    }
    return List.unmodifiable(items);
  }

  /// Stable per logical breach family: `concentration:<dimension>:<label>`.
  static String concentrationSourceKey(RiskDimension dimension, String label) {
    final slug = label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    return 'concentration:${dimension.name}:$slug';
  }

  static String dividendDeteriorationSourceKey(String assetId) =>
      'dividend-deterioration:$assetId';

  static const rebalanceDriftSourceKey = 'rebalance-drift';
}
