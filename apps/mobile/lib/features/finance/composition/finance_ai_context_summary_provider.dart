/// FinanceOS implementation of [aiContextSummaryProvider]
/// (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// Watches Finance dashboard / anomaly / maturity providers and
/// returns a closure that turns the captured numbers into a list of
/// localised [AiContextFact]s. The closure runs at render time so the
/// l10n strings reflect the current locale without re-fetching data.
///
/// Registered as an override of [aiContextSummaryProvider] in
/// `bootstrap.dart`. HealthOS (D-2) ships an analogous provider; the
/// shell renderer iterates the union without knowing which domain
/// produced which fact.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../home/data/dashboard_providers.dart';

final financeAiContextSummaryProvider = Provider<AiContextSummaryBuilder>((
  ref,
) {
  final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
  final metrics = metricsAsync.value;
  final anomaly = ref.watch(expenseAnomalyInsightProvider);
  final maturity = ref.watch(depositMaturityInsightProvider);

  return (l10n) {
    final facts = <AiContextFact>[];

    final pct = metrics?.monthlyChangePct;
    if (pct != null && pct.isFinite) {
      final sign = pct >= 0 ? '+' : '−';
      final abs = (pct.abs() * 100).toStringAsFixed(1);
      facts.add(
        AiContextFact(
          id: 'fin:networth_pct',
          icon: pct >= 0
              ? FLucideIcons.trendingUp
              : FLucideIcons.trendingDown,
          tone: pct >= 0
              ? AiContextTone.positive
              : AiContextTone.attention,
          text: l10n.aiContextSummaryNetWorthLine('$sign$abs%'),
          suggestion: l10n.aiChatEmptyDynamicNetWorth,
        ),
      );
    }

    if (anomaly != null) {
      facts.add(
        AiContextFact(
          id: 'fin:expense_anomalies',
          icon: FLucideIcons.zap,
          tone: AiContextTone.attention,
          text: l10n.aiContextSummaryUnusualLine(1),
          suggestion: l10n.aiChatEmptyDynamicAnomaly(1),
        ),
      );
    }

    if (maturity != null && maturity.count > 0) {
      facts.add(
        AiContextFact(
          id: 'fin:upcoming_maturities',
          icon: FLucideIcons.calendarCheck,
          tone: AiContextTone.neutral,
          text: l10n.aiContextSummaryUpcomingLine(
            maturity.count,
            maturity.days,
          ),
          suggestion: l10n.aiChatEmptyDynamicMaturity(
            maturity.count,
            maturity.days,
          ),
        ),
      );
    }

    return AiContextSummary(facts: facts);
  };
});
