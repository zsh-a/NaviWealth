import 'package:flutter/material.dart';

import 'dashboard_models.dart';

/// Discrete insight types shown on the dashboard's AI Insight Feed.
///
/// Adding a new kind requires:
///  - a producer in `dashboard_insights_provider.dart`
///  - label / value strings in `insight_feed_strings.dart`
enum InsightKind {
  fireProgress,
  fireReached,
  portfolioDrift,
  maturity,
  anomaly,
  // §5.10.1 — duplicate charge: same merchant + same amount within ±2
  // days, after refund + recurring exclusion.
  duplicateCharge,
  // §5.10.1 — first-week-of-month recap of the prior month's net
  // worth delta.
  monthlySummary,
  // §5.10.10 / S5a.1 — Layer 4 ingest queue has parsed-but-unconfirmed
  // drafts waiting for the user to confirm / skip.
  ingestQueue,
  // FIR-142 — current-month operating cashflow is below zero.
  cashFlowDeficit,
  // FIRE OS Phase 1 — trailing-12-month withdrawal rate is above the
  // plan's safe withdrawal rate.
  fireOsHighWithdrawalRate,
  // FIRE OS Phase 1 — cash bucket coverage has slipped below the plan's
  // target.
  fireOsLowCashBucket,
  // FIRE OS Phase 2 — assets exist that no bucket rule covers and the
  // default classifier can't claim (real estate, vehicles).
  fireOsUnmappedHoldings,
}

/// One actionable insight surfaced on the dashboard. The view layer
/// resolves [kind] into headline + detail strings via the localized
/// labels in `insight_feed_strings.dart`, and routes the user to
/// [route] when they tap the card's primary action.
class InsightItem {
  const InsightItem({
    required this.icon,
    required this.kind,
    this.iconColor,
    this.onTap,
    this.route,
    this.monthsToTarget,
    this.category,
    this.driftPct,
    this.maturityCount,
    this.maturityDays,
    this.anomalyPct,
    this.duplicateChargeCount,
    this.duplicateChargeAmountMinor,
    this.duplicateChargeCurrency,
    this.summaryYear,
    this.summaryMonth,
    this.summaryDeltaMinor,
    this.summaryCurrency,
    this.ingestPendingCount,
    this.ingestFreshCount,
    this.cashFlowMonthKey,
    this.cashFlowNetMinor,
    this.cashFlowCurrency,
    this.fireOsWithdrawalRate,
    this.fireOsSafeWithdrawalRate,
    this.fireOsCashBucketMonths,
    this.fireOsTargetCashBucketMonths,
    this.fireOsUnmappedCount,
  });

  final IconData icon;
  final InsightKind kind;
  final Color? iconColor;
  final VoidCallback? onTap;
  final String? route;
  final int? monthsToTarget;
  final AssetCategory? category;
  final double? driftPct;
  final int? maturityCount;
  final int? maturityDays;
  final double? anomalyPct;

  // ── duplicateCharge fields ──────────────────────────────────────
  /// Total number of suspected duplicate-charge pairs found.
  final int? duplicateChargeCount;

  /// Sum of the absolute pair amounts in minor units (worst-case
  /// over-charge if the user actually got billed twice for every
  /// pair). Drives the "you may have been overcharged ¥X" summary.
  final int? duplicateChargeAmountMinor;
  final String? duplicateChargeCurrency;

  // ── monthlySummary fields ───────────────────────────────────────
  /// Year and month (1–12) the summary covers — typically the prior
  /// calendar month.
  final int? summaryYear;
  final int? summaryMonth;

  /// Net-worth delta over the summarised month, in minor units.
  /// Positive = grew, negative = shrank.
  final int? summaryDeltaMinor;
  final String? summaryCurrency;

  // ── ingestQueue fields ──────────────────────────────────────────
  /// Total parsed-but-unconfirmed drafts in the Layer 4 queue.
  final int? ingestPendingCount;

  /// Subset flagged as new (no dedup match) — safe to bulk-confirm.
  final int? ingestFreshCount;

  // ── cashFlowDeficit fields ─────────────────────────────────────
  final String? cashFlowMonthKey;
  final int? cashFlowNetMinor;
  final String? cashFlowCurrency;

  // ── FIRE OS fields ──────────────────────────────────────────────
  /// Current withdrawal rate as a decimal (`0.046` = 4.6%). Used by
  /// the high-WR insight; null on other kinds.
  final double? fireOsWithdrawalRate;

  /// The plan's safe-withdrawal-rate baseline the WR was compared to.
  final double? fireOsSafeWithdrawalRate;

  /// Months of expenses currently covered by the cash bucket.
  final double? fireOsCashBucketMonths;

  /// Plan's target cash-bucket month count.
  final int? fireOsTargetCashBucketMonths;

  /// Number of holdings the bucket allocator could not classify.
  final int? fireOsUnmappedCount;
}
