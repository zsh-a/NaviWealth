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
}
