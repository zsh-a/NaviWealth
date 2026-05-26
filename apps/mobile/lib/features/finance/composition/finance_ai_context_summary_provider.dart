/// FinanceOS implementation of [aiContextSummaryProvider]
/// (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// Composes the AI page header chip from Finance dashboard providers
/// (header metrics, expense anomaly, deposit maturity). Registered as
/// an override of [aiContextSummaryProvider] in `bootstrap.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../home/data/dashboard_providers.dart';

final financeAiContextSummaryProvider = Provider<AiContextSummary>((ref) {
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
