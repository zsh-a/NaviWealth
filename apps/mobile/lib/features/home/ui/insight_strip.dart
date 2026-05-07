import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';
import 'insight_chip.dart';

enum InsightKind {
  fireProgress,
  fireReached,
  portfolioDrift,
  maturity,
  anomaly,
}

/// A data model for a single insight item.
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

/// Horizontal scrollable row of [InsightChip] widgets.
/// Shows actionable insights on the dashboard (rebalancing alerts,
/// goal progress, upcoming maturities, expense anomalies).
class InsightStrip extends StatelessWidget {
  const InsightStrip({super.key, required this.insights});

  final List<InsightItem> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: insights.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.s8),
        itemBuilder: (context, i) {
          final item = insights[i];
          final l10n = AppLocalizations.of(context);
          final route = item.route;
          return InsightChip(
            icon: item.icon,
            label: _labelFor(l10n, item),
            value: _valueFor(l10n, item),
            iconColor: item.iconColor,
            onTap:
                item.onTap ??
                (route == null ? null : () => context.push(route)),
          );
        },
      ),
    );
  }

  String _labelFor(AppLocalizations l10n, InsightItem item) {
    return switch (item.kind) {
      InsightKind.fireProgress ||
      InsightKind.fireReached => l10n.dashboardInsightFireLabel,
      InsightKind.portfolioDrift => l10n.dashboardInsightDriftLabel,
      InsightKind.maturity => l10n.dashboardInsightMaturityLabel,
      InsightKind.anomaly => l10n.dashboardInsightAnomalyLabel,
    };
  }

  String _valueFor(AppLocalizations l10n, InsightItem item) {
    return switch (item.kind) {
      InsightKind.fireProgress => _fireProgressValue(l10n, item),
      InsightKind.fireReached => l10n.dashboardInsightFireReached,
      InsightKind.portfolioDrift => _driftValue(l10n, item),
      InsightKind.maturity => l10n.dashboardInsightMaturityValue(
        item.maturityCount ?? 0,
        item.maturityDays ?? 0,
      ),
      InsightKind.anomaly => l10n.dashboardInsightAnomalyValue(
        _signedPercent(item.anomalyPct ?? 0),
      ),
    };
  }

  String _fireProgressValue(AppLocalizations l10n, InsightItem item) {
    final months = item.monthsToTarget ?? 0;
    final years = months ~/ 12;
    final remainingMonths = months % 12;
    if (years > 0) {
      return l10n.dashboardInsightFireToGoYears(years, remainingMonths);
    }
    return l10n.dashboardInsightFireToGoMonths(remainingMonths);
  }

  String _driftValue(AppLocalizations l10n, InsightItem item) {
    final category = item.category;
    final pp = ((item.driftPct ?? 0).abs() * 100).round();
    final direction = (item.driftPct ?? 0) >= 0
        ? l10n.dashboardInsightDriftOver
        : l10n.dashboardInsightDriftUnder;
    final label = category == null
        ? l10n.dashboardCategoryStock
        : AssetCategoryVisuals.label(l10n, category);
    return l10n.dashboardInsightDriftValue(label, direction, pp);
  }

  String _signedPercent(double ratio) {
    final pct = (ratio.abs() * 100).round();
    if (ratio > 0) return '+$pct%';
    if (ratio < 0) return '-$pct%';
    return '0%';
  }
}
