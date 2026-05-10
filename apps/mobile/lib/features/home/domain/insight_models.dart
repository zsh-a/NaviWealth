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
}
