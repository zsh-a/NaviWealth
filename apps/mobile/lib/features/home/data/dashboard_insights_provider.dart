import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_paths.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../cashflow/data/cash_flow_providers.dart';
import '../../cashflow/domain/cash_flow_aggregator.dart';
import '../../cashflow/domain/home_cash_flow_metrics.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../fire/data/fire_providers.dart';
import '../../ingest/data/ingest_queue_insight_provider.dart';
import '../../rebalance/data/rebalance_drift_insight_provider.dart';
import '../domain/insight_models.dart';
import 'dismissed_insights_store.dart';
import 'duplicate_charge_insight_provider.dart';
import 'monthly_summary_insight_provider.dart';

/// Computes actionable insights for the dashboard [InsightStrip].
///
/// Each insight is derived from an existing provider and is only shown
/// when the underlying data is available and non-empty. Dismissed
/// kinds (§5.10.1 Layer 3 三动作) are filtered out before the list
/// reaches the UI so the same card doesn't bounce back when its
/// underlying signal recomputes.
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
          route: AppRoutes.accountsFire,
        ),
      );
    } else if (months == 0) {
      insights.add(
        const InsightItem(
          icon: Icons.celebration_outlined,
          kind: InsightKind.fireReached,
          iconColor: Colors.green,
          route: AppRoutes.accountsFire,
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
        route: AppRoutes.accountsRebalance,
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

  final duplicate = ref.watch(duplicateChargeInsightProvider);
  if (duplicate != null && !duplicate.isEmpty) {
    insights.add(
      InsightItem(
        icon: Icons.copy_all_outlined,
        kind: InsightKind.duplicateCharge,
        iconColor: Colors.deepOrange,
        duplicateChargeCount: duplicate.matches.length,
        duplicateChargeAmountMinor: duplicate.totalAbsAmountMinor,
        duplicateChargeCurrency: duplicate.currency,
        route: AppRoutes.activityExpenses,
      ),
    );
  }

  final summary = ref.watch(monthlySummaryInsightProvider);
  if (summary != null) {
    insights.add(
      InsightItem(
        icon: Icons.calendar_month_outlined,
        kind: InsightKind.monthlySummary,
        iconColor: summary.deltaMinor >= 0 ? Colors.teal : Colors.redAccent,
        summaryYear: summary.year,
        summaryMonth: summary.month,
        summaryDeltaMinor: summary.deltaMinor,
        summaryCurrency: summary.currency,
        route: AppRoutes.accountsAnalytics,
      ),
    );
  }

  final cashFlowSummary = ref.watch(
    cashFlowSummaryProvider(
      const CashFlowSummaryRequest(period: CashFlowPeriod.month),
    ),
  );
  cashFlowSummary.whenData((summary) {
    final metrics = monthlyCashFlowHomeMetrics(summary);
    if (metrics.hasData && metrics.net.isNegative) {
      insights.add(
        InsightItem(
          icon: Icons.account_balance_wallet_outlined,
          kind: InsightKind.cashFlowDeficit,
          iconColor: Colors.redAccent,
          cashFlowMonthKey: metrics.monthKey,
          cashFlowNetMinor: _moneyToMinor(metrics.net.amount),
          cashFlowCurrency: metrics.net.currency,
          route: kCashflowPath,
        ),
      );
    }
  });

  // §5.10.10 / S5a.1 — Layer 4 queue surfaces as a calm ambient card;
  // row tap deep-links to the review page (AppRoutes.activityIngest).
  final ingest = ref.watch(ingestQueueInsightProvider);
  if (ingest != null && !ingest.isEmpty) {
    insights.add(
      InsightItem(
        icon: Icons.move_to_inbox_outlined,
        kind: InsightKind.ingestQueue,
        ingestPendingCount: ingest.pendingCount,
        ingestFreshCount: ingest.freshCount,
        route: AppRoutes.activityIngest,
      ),
    );
  }

  final dismissed =
      ref.watch(dismissedInsightKeysProvider).value ??
      const <DismissedInsightKey>{};
  if (dismissed.isEmpty) return insights;
  return insights
      .where(
        (item) => !dismissed.contains(
          DismissedInsightKey(
            kind: item.kind,
            scopeHash: insightScopeHash(item),
          ),
        ),
      )
      .toList(growable: false);
});

/// Stable hash from an [InsightItem]'s identifying fields. Mirrors the
/// scope-hash semantics on `DuplicateChargeSummary` / `MonthlySummary`
/// so dismissal records can be reconstructed from the rendered card.
String insightScopeHash(InsightItem item) {
  switch (item.kind) {
    case InsightKind.fireProgress:
    case InsightKind.fireReached:
    case InsightKind.portfolioDrift:
    case InsightKind.maturity:
    case InsightKind.anomaly:
      // Single-instance kinds — one hash is enough to dismiss them.
      return '';
    case InsightKind.duplicateCharge:
      // The provider encodes the full match cluster into its
      // scopeHash; the InsightItem lost that detail when it was
      // flattened, so collapse to the count + amount + currency
      // signature. Two separate clusters with the same shape will
      // collide — acceptable for a "don't show me this" preference.
      return [
        item.duplicateChargeCount ?? 0,
        item.duplicateChargeAmountMinor ?? 0,
        item.duplicateChargeCurrency ?? '',
      ].join(':');
    case InsightKind.monthlySummary:
      return '${item.summaryYear ?? 0}-${item.summaryMonth ?? 0}';
    case InsightKind.ingestQueue:
      return '${item.ingestPendingCount ?? 0}:${item.ingestFreshCount ?? 0}';
    case InsightKind.cashFlowDeficit:
      return '${item.cashFlowMonthKey ?? ''}:'
          '${item.cashFlowNetMinor ?? 0}:'
          '${item.cashFlowCurrency ?? ''}';
  }
}

int _moneyToMinor(Decimal amount) =>
    (amount * Decimal.fromInt(100)).round().toBigInt().toInt();
