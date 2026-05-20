import 'package:intl/intl.dart';

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
    InsightKind.duplicateCharge => l10n.dashboardInsightDuplicateChargeLabel,
    InsightKind.monthlySummary => l10n.dashboardInsightMonthlySummaryLabel,
    InsightKind.ingestQueue => l10n.dashboardInsightIngestQueueLabel,
    InsightKind.cashFlowDeficit => l10n.dashboardInsightCashFlowDeficitLabel,
    InsightKind.fireOsHighWithdrawalRate =>
      l10n.fireOsInsightHighWithdrawalRate,
    InsightKind.fireOsLowCashBucket => l10n.fireOsInsightLowCashBucket,
    InsightKind.fireOsUnmappedHoldings => l10n.fireOsInsightUnmappedHoldings,
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
    InsightKind.duplicateCharge => _duplicateCharge(l10n, item),
    InsightKind.monthlySummary => _monthlySummary(l10n, item),
    InsightKind.ingestQueue => l10n.dashboardInsightIngestQueueValue(
      item.ingestPendingCount ?? 0,
      item.ingestFreshCount ?? 0,
    ),
    InsightKind.cashFlowDeficit => _cashFlowDeficit(l10n, item),
    InsightKind.fireOsHighWithdrawalRate =>
      l10n.fireOsInsightHighWithdrawalRateValue(
        ((item.fireOsWithdrawalRate ?? 0) * 100).toStringAsFixed(1),
        ((item.fireOsSafeWithdrawalRate ?? 0) * 100).toStringAsFixed(1),
      ),
    InsightKind.fireOsLowCashBucket =>
      l10n.fireOsInsightLowCashBucketValue(
        (item.fireOsCashBucketMonths ?? 0).toStringAsFixed(1),
        item.fireOsTargetCashBucketMonths ?? 0,
      ),
    InsightKind.fireOsUnmappedHoldings =>
      l10n.fireOsInsightUnmappedHoldingsValue(
        item.fireOsUnmappedCount ?? 0,
      ),
  };
}

String _cashFlowDeficit(AppLocalizations l10n, InsightItem item) {
  final delta = item.cashFlowNetMinor ?? 0;
  final currency = item.cashFlowCurrency ?? 'USD';
  return l10n.dashboardInsightCashFlowDeficitValue(
    _formatMoney(delta.abs(), currency),
  );
}

String _duplicateCharge(AppLocalizations l10n, InsightItem item) {
  final count = item.duplicateChargeCount ?? 0;
  final amountMinor = item.duplicateChargeAmountMinor ?? 0;
  final currency = item.duplicateChargeCurrency ?? 'USD';
  return l10n.dashboardInsightDuplicateChargeValue(
    count,
    _formatMoney(amountMinor, currency),
  );
}

String _monthlySummary(AppLocalizations l10n, InsightItem item) {
  final delta = item.summaryDeltaMinor ?? 0;
  final currency = item.summaryCurrency ?? 'USD';
  if (delta == 0) return l10n.dashboardInsightMonthlySummaryFlat;
  final amount = _formatMoney(delta.abs(), currency);
  return delta > 0
      ? l10n.dashboardInsightMonthlySummaryUp(amount)
      : l10n.dashboardInsightMonthlySummaryDown(amount);
}

/// Format a minor-unit amount as a thin "currency + grouped digits"
/// string. Distinct from [MoneyText] because this string is consumed
/// by the ARB-templated detail line, not a widget.
String _formatMoney(int amountMinor, String currency) {
  final value = amountMinor.abs() / 100.0;
  final formatted = NumberFormat.currency(
    name: currency,
    symbol: _glyphFor(currency),
    decimalDigits: 2,
  ).format(value);
  return formatted;
}

String _glyphFor(String code) {
  switch (code.toUpperCase()) {
    case 'CNY':
    case 'JPY':
      return '¥';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'HKD':
      return r'HK$';
    default:
      return '$code ';
  }
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
