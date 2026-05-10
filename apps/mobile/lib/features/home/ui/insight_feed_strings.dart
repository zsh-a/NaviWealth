import '../../../l10n/gen/app_localizations.dart';
import '../domain/insight_models.dart';
import 'asset_category_visuals.dart';

/// Stateless string resolver for [InsightItem] → headline + detail copy.
/// Pulled out of the strip widget so the new vertical [AiInsightFeed] can
/// reuse the exact same labels.
String insightHeadline(AppLocalizations l10n, InsightItem item) {
  return switch (item.kind) {
    InsightKind.fireProgress ||
    InsightKind.fireReached => l10n.dashboardInsightFireLabel,
    InsightKind.portfolioDrift => l10n.dashboardInsightDriftLabel,
    InsightKind.maturity => l10n.dashboardInsightMaturityLabel,
    InsightKind.anomaly => l10n.dashboardInsightAnomalyLabel,
  };
}

String insightDetail(AppLocalizations l10n, InsightItem item) {
  return switch (item.kind) {
    InsightKind.fireProgress => _fireProgress(l10n, item),
    InsightKind.fireReached => l10n.dashboardInsightFireReached,
    InsightKind.portfolioDrift => _drift(l10n, item),
    InsightKind.maturity => l10n.dashboardInsightMaturityValue(
      item.maturityCount ?? 0,
      item.maturityDays ?? 0,
    ),
    InsightKind.anomaly => l10n.dashboardInsightAnomalyValue(
      _signedPercent(item.anomalyPct ?? 0),
    ),
  };
}

String _fireProgress(AppLocalizations l10n, InsightItem item) {
  final months = item.monthsToTarget ?? 0;
  final years = months ~/ 12;
  final remaining = months % 12;
  if (years > 0) {
    return l10n.dashboardInsightFireToGoYears(years, remaining);
  }
  return l10n.dashboardInsightFireToGoMonths(remaining);
}

String _drift(AppLocalizations l10n, InsightItem item) {
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
