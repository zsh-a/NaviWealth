import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_paths.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../fire/data/fire_providers.dart';
import '../../rebalance/data/rebalance_drift_insight_provider.dart';
import '../domain/insight_models.dart';

/// Computes actionable insights for the dashboard [InsightStrip].
///
/// Each insight is derived from an existing provider and is only shown
/// when the underlying data is available and non-empty.
final dashboardInsightsProvider = Provider<List<InsightItem>>((ref) {
  final insights = <InsightItem>[];

  // FIRE progress insight
  final fireAsync = ref.watch(fireDashboardViewProvider);
  fireAsync.whenData((view) {
    // Use the baseline scenario's monthsToTarget
    final baseline = view.scenarios.isNotEmpty ? view.scenarios.first : null;
    final months = baseline?.monthsToTarget;
    if (months != null && months > 0) {
      insights.add(
        InsightItem(
          icon: Icons.flag_outlined,
          kind: InsightKind.fireProgress,
          monthsToTarget: months,
          route: AppRoutes.aiInsightsFire,
        ),
      );
    } else if (months == 0) {
      insights.add(
        const InsightItem(
          icon: Icons.celebration_outlined,
          kind: InsightKind.fireReached,
          iconColor: Colors.green,
          route: AppRoutes.aiInsightsFire,
        ),
      );
    }
  });

  final drift = ref.watch(rebalanceDriftInsightProvider);
  if (drift != null) {
    insights.add(
      InsightItem(
        icon: Icons.tune_outlined,
        kind: InsightKind.portfolioDrift,
        category: drift.category,
        driftPct: drift.deviation,
        iconColor: Colors.amber,
        route: AppRoutes.aiInsightsRebalance,
      ),
    );
  }

  final maturity = ref.watch(depositMaturityInsightProvider);
  if (maturity != null) {
    insights.add(
      InsightItem(
        icon: Icons.event_available_outlined,
        kind: InsightKind.maturity,
        maturityCount: maturity.count,
        maturityDays: maturity.days,
        route: AppRoutes.accounts,
      ),
    );
  }

  final anomaly = ref.watch(expenseAnomalyInsightProvider);
  if (anomaly != null) {
    insights.add(
      InsightItem(
        icon: Icons.trending_up_outlined,
        kind: InsightKind.anomaly,
        anomalyPct: anomaly.deltaRatio,
        iconColor: anomaly.deltaRatio > 0 ? Colors.orange : null,
        route: AppRoutes.expenseReport,
      ),
    );
  }

  return insights;
});
