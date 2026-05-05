import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fire/data/fire_providers.dart';
import '../ui/insight_strip.dart';

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
      final years = months ~/ 12;
      final remainingMonths = months % 12;
      final label =
          years > 0 ? '${years}y ${remainingMonths}m' : '${remainingMonths}m';
      insights.add(InsightItem(
        icon: Icons.flag_outlined,
        label: 'FIRE',
        value: '$label to go',
      ));

    } else if (months == 0) {
      insights.add(const InsightItem(
        icon: Icons.celebration_outlined,
        label: 'FIRE',
        value: 'Goal reached!',
        iconColor: Colors.green,
      ));
    }
  });

  // TODO: Add more insights when providers are available:
  // - Portfolio drift (from rebalance engine)
  // - Upcoming deposit maturities
  // - Expense trend anomalies

  return insights;
});
