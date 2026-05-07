import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/domain/dashboard_models.dart';
import '../domain/rebalance_models.dart';
import 'rebalance_providers.dart';

class DriftSummary {
  const DriftSummary({required this.category, required this.deviation});

  final AssetCategory category;

  /// Signed drift as a ratio. Positive means overweight.
  final double deviation;
}

DriftSummary? summarizeRebalanceDrift(
  RebalancePlan? plan, {
  required double threshold,
}) {
  if (plan == null) return null;
  Drift? top;
  for (final drift in plan.drifts) {
    if (drift.absDeviation < threshold) continue;
    if (top == null || drift.absDeviation > top.absDeviation) {
      top = drift;
    }
  }
  if (top == null) return null;
  return DriftSummary(category: top.category, deviation: top.deviation);
}

final rebalanceDriftInsightProvider = Provider<DriftSummary?>((ref) {
  final plan = ref.watch(rebalancePlanProvider);
  final threshold = ref.watch(warningThresholdProvider);
  return summarizeRebalanceDrift(plan, threshold: threshold);
});
