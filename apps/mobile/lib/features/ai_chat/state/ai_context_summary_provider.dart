import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../home/data/dashboard_providers.dart';

/// Compact financial state summary shown in the AI assistant page header.
///
/// Composed entirely from existing dashboard providers — no new
/// computation. The four cells render the rolling pulse the user wants
/// the assistant to be aware of: net-worth direction, recent expense
/// anomalies, upcoming deposit maturities, and base currency.
///
/// **Relationship to `core/ai/local/skills/context_compressor.dart`**:
/// the new [ContextCompressor] reads the same upstream providers
/// (header metrics, expense anomaly, deposit maturity) and produces
/// a wire-format [ContextPack]. This UI summary is intentionally a
/// different shape — it carries display-only fields (todaysChange,
/// upcomingMaturitiesDays) that the cloud planner doesn't need. The
/// two surfaces are kept aligned by sharing the same providers as
/// inputs; do not derive one from the other.
@immutable
class AiContextSummary {
  const AiContextSummary({
    required this.baseCurrency,
    required this.monthlyChangePct,
    required this.todaysChange,
    required this.unusualExpensesCount,
    required this.upcomingMaturitiesCount,
    required this.upcomingMaturitiesDays,
  });

  final String baseCurrency;

  /// Month-to-date net-worth change as a fraction (e.g. 0.034 = +3.4%).
  /// `null` when no metrics are available yet (cold-start, no data).
  final double? monthlyChangePct;

  /// Today's net-worth change in base currency. May be zero.
  final double todaysChange;

  /// Number of expense anomalies detected this period (0 if none).
  final int unusualExpensesCount;

  /// Number of deposit maturities upcoming inside [upcomingMaturitiesDays]
  /// days. Both fields are zero when no maturities are imminent.
  final int upcomingMaturitiesCount;
  final int upcomingMaturitiesDays;

  bool get isEmpty =>
      monthlyChangePct == null &&
      todaysChange == 0 &&
      unusualExpensesCount == 0 &&
      upcomingMaturitiesCount == 0;
}

final aiContextSummaryProvider = Provider<AiContextSummary>((ref) {
  final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
  final m = metricsAsync.value;
  final anomaly = ref.watch(expenseAnomalyInsightProvider);
  final maturity = ref.watch(depositMaturityInsightProvider);

  return AiContextSummary(
    baseCurrency: m?.baseCurrency ?? 'USD',
    monthlyChangePct: m?.monthlyChangePct,
    todaysChange: m?.dailyChange.amount.toDouble() ?? 0,
    unusualExpensesCount: anomaly == null ? 0 : 1,
    upcomingMaturitiesCount: maturity?.count ?? 0,
    upcomingMaturitiesDays: maturity?.days ?? 0,
  );
});
