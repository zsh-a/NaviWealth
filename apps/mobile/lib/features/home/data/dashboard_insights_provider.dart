import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../app/route_paths.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../cashflow/data/cash_flow_providers.dart';
import '../../cashflow/domain/cash_flow_aggregator.dart';
import '../../cashflow/domain/home_cash_flow_metrics.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_bucket.dart';
import '../../ingest/data/ingest_queue_insight_provider.dart';
import '../../rebalance/data/rebalance_drift_insight_provider.dart';
import '../domain/dashboard_models.dart';
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
          icon: FLucideIcons.flag,
          kind: InsightKind.fireProgress,
          monthsToTarget: months,
          route: AppRoutes.planFire,
        ),
      );
    } else if (months == 0) {
      insights.add(
        const InsightItem(
          icon: FLucideIcons.partyPopper,
          kind: InsightKind.fireReached,
          tone: InsightTone.success,
          route: AppRoutes.planFire,
        ),
      );
    }
  });

  // FIRE OS Phase 1: high withdrawal rate / low cash bucket signals. The
  // hero card on the FIRE page shows the same data in detail; the home
  // surface is the calm prompt before the user opens the dashboard.
  final fireStateAsync = ref.watch(fireStateProvider);
  fireStateAsync.whenData((state) {
    if (!state.isConfigured) return;
    if (state.withdrawalRate.isFinite &&
        state.withdrawalRate > state.plan.safeWithdrawalRate) {
      insights.add(
        InsightItem(
          icon: FLucideIcons.trendingUp,
          kind: InsightKind.fireOsHighWithdrawalRate,
          tone: InsightTone.warning,
          route: AppRoutes.planFire,
          fireOsWithdrawalRate: state.withdrawalRate,
          fireOsSafeWithdrawalRate: state.plan.safeWithdrawalRate,
        ),
      );
    }
    if (state.cashBucketMonths.isFinite &&
        state.cashBucketMonths < state.plan.targetCashBucketMonths) {
      insights.add(
        InsightItem(
          icon: FLucideIcons.landmark,
          kind: InsightKind.fireOsLowCashBucket,
          tone: InsightTone.warning,
          route: AppRoutes.planFire,
          fireOsCashBucketMonths: state.cashBucketMonths,
          fireOsTargetCashBucketMonths: state.plan.targetCashBucketMonths,
        ),
      );
    }
    if (state.unmappedHoldings.isNotEmpty) {
      insights.add(
        InsightItem(
          icon: FLucideIcons.circleHelp,
          kind: InsightKind.fireOsUnmappedHoldings,
          tone: InsightTone.warning,
          route: AppRoutes.planFire,
          fireOsUnmappedCount: state.unmappedHoldings.length,
        ),
      );
    }

    // Non-cash bucket deviation. Cash already has its own dedicated
    // insight; pick the single worst other bucket so the home strip
    // doesn't show 4 bucket cards at once.
    final worst = _worstNonCashBucket(state.buckets);
    if (worst != null) {
      final fmt = NumberFormat.simpleCurrency(
        name: worst.currentValue.currency,
        decimalDigits: 0,
      );
      insights.add(
        InsightItem(
          icon: worst.status == FireBucketStatus.overTarget
              ? FLucideIcons.foldVertical
              : FLucideIcons.unfoldVertical,
          kind: InsightKind.fireOsBucketDeviation,
          tone: InsightTone.warning,
          route: AppRoutes.planFire,
          fireOsBucketRoleLabel: _bucketRoleWire(worst.role),
          fireOsBucketCurrentLabel: fmt
              .format(worst.currentValue.amount.toDouble())
              .trim(),
          fireOsBucketTargetLabel: fmt
              .format(worst.targetValue.amount.toDouble())
              .trim(),
        ),
      );
    }
  });

  final drift = ref.watch(rebalanceDriftInsightProvider);
  if (drift != null) {
    insights.add(
      InsightItem(
        icon: FLucideIcons.slidersHorizontal,
        kind: InsightKind.portfolioDrift,
        category: drift.category,
        driftPct: drift.deviation,
        tone: InsightTone.warning,
        route: AppRoutes.planRebalance,
      ),
    );
  }

  final maturity = ref.watch(depositMaturityInsightProvider);
  if (maturity != null) {
    insights.add(
      InsightItem(
        icon: FLucideIcons.calendarCheck,
        kind: InsightKind.maturity,
        maturityCount: maturity.count,
        maturityDays: maturity.days,
        route: AppRoutes.wealth,
      ),
    );
  }

  final anomaly = ref.watch(expenseAnomalyInsightProvider);
  if (anomaly != null) {
    insights.add(
      InsightItem(
        icon: FLucideIcons.trendingUp,
        kind: InsightKind.anomaly,
        anomalyPct: anomaly.deltaRatio,
        tone: anomaly.deltaRatio > 0 ? InsightTone.warning : null,
        route: AppRoutes.expenseReport,
      ),
    );
  }

  final duplicate = ref.watch(duplicateChargeInsightProvider);
  if (duplicate != null && !duplicate.isEmpty) {
    insights.add(
      InsightItem(
        icon: FLucideIcons.copy,
        kind: InsightKind.duplicateCharge,
        tone: InsightTone.danger,
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
        icon: FLucideIcons.calendar,
        kind: InsightKind.monthlySummary,
        tone: summary.deltaMinor >= 0
            ? InsightTone.success
            : InsightTone.danger,
        summaryYear: summary.year,
        summaryMonth: summary.month,
        summaryDeltaMinor: summary.deltaMinor,
        summaryCurrency: summary.currency,
        route: AppRoutes.cashflow,
      ),
    );
  }

  final cashFlowSummary = ref.watch(
    cashFlowSummaryProvider(
      const CashFlowSummaryRequest(period: CashFlowPeriod.month),
    ),
  );
  cashFlowSummary.whenData((summary) {
    final metrics = monthlyCashFlowHomeMetrics(
      summary,
      now: ref.watch(cashFlowNowProvider),
    );
    if (metrics.hasData && metrics.net.isNegative) {
      insights.add(
        InsightItem(
          icon: FLucideIcons.wallet,
          kind: InsightKind.cashFlowDeficit,
          tone: InsightTone.danger,
          cashFlowMonthKey: metrics.monthKey,
          cashFlowNetMinor: _moneyToMinor(metrics.net.amount),
          cashFlowCurrency: metrics.net.currency,
          route: AppRoutes.cashflow,
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
        icon: FLucideIcons.inbox,
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
    case InsightKind.fireOsHighWithdrawalRate:
    case InsightKind.fireOsLowCashBucket:
    case InsightKind.fireOsUnmappedHoldings:
      // Single-instance kinds — one hash is enough to dismiss them.
      return '';
    case InsightKind.currencyMismatch:
      return [
        item.currencyMismatchCount ?? 0,
        item.currencyMismatchBaseCurrency ?? '',
      ].join(':');
    case InsightKind.fireOsBucketDeviation:
      // Dismissable per role — if the user silences the "growth bucket
      // off-target" prompt that shouldn't also silence "risk reserve
      // off-target" the next month.
      return item.fireOsBucketRoleLabel ?? '';
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

/// Convert dashboard FX coverage gaps into a home insight.
///
/// The dashboard still renders a dedicated warning banner with per-holding
/// details. This insight makes the same data visible in the user's action
/// queue and deep-links to the FX rate manager.
InsightItem? summarizeCurrencyMismatchInsight({
  required List<CurrencyMismatch> mismatches,
  required String baseCurrency,
}) {
  if (mismatches.isEmpty) return null;
  return InsightItem(
    icon: FLucideIcons.arrowLeftRight,
    kind: InsightKind.currencyMismatch,
    tone: InsightTone.warning,
    route: AppRoutes.settingsFxRates,
    currencyMismatchCount: mismatches.length,
    currencyMismatchBaseCurrency: baseCurrency,
  );
}

int _moneyToMinor(Decimal amount) =>
    (amount * Decimal.fromInt(100)).round().toBigInt().toInt();

/// Pick the non-cash bucket that is furthest from its target (worst
/// under-target wins; otherwise furthest over-target). Returns null
/// when no non-cash bucket has a formal target or every such bucket
/// is on-track.
FireBucketState? _worstNonCashBucket(List<FireBucketState> buckets) {
  FireBucketState? worst;
  double? worstSeverity;
  for (final b in buckets) {
    if (b.role == FireBucketRole.cash) continue;
    // Only buckets with a target can deviate.
    if (b.targetValue.amount <= Decimal.zero) continue;
    if (b.status == FireBucketStatus.onTrack) continue;
    final coverage = b.coverageRatio ?? 1.0;
    // Severity = distance from 1.0 (the on-track centre). Under-
    // target rolls onto the same metric symmetrically — both are
    // signals worth surfacing.
    final severity = (coverage - 1.0).abs();
    if (worstSeverity == null || severity > worstSeverity) {
      worst = b;
      worstSeverity = severity;
    }
  }
  return worst;
}

/// Wire-name a bucket role for telemetry / dismissal keys. Matches the
/// AI tool surface (snake_case) so dismissal records can survive a
/// later UI label change.
String _bucketRoleWire(FireBucketRole role) {
  switch (role) {
    case FireBucketRole.cash:
      return 'cash';
    case FireBucketRole.defensive:
      return 'defensive';
    case FireBucketRole.growth:
      return 'growth';
    case FireBucketRole.riskReserve:
      return 'risk_reserve';
    case FireBucketRole.dream:
      return 'dream';
  }
}
