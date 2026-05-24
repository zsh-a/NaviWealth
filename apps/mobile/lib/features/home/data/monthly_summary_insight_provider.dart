/// §5.10.1 Layer 3 — first-week-of-month net-worth recap insight.
///
/// Once a calendar month rolls over, the dashboard surfaces a single
/// recap card for the seven days that follow: "March: net worth grew
/// ¥21,400". The card resolves to a deterministic delta computed off
/// the existing `dashboardTrendProvider` time series — no LLM call.
/// Outside that window the provider returns `null`.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dashboard_trend_builder.dart';
import 'dashboard_providers.dart';

class MonthlySummary {
  const MonthlySummary({
    required this.year,
    required this.month,
    required this.deltaMinor,
    required this.currency,
  });

  /// Year and 1-based month the recap covers — typically the prior
  /// calendar month.
  final int year;
  final int month;

  /// Net-worth change over the month in minor units (positive grew,
  /// negative shrank, zero flat).
  final int deltaMinor;
  final String currency;

  /// Stable hash for the dismissed-insights store so dismissing the
  /// March recap doesn't suppress April's.
  String get scopeHash =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';
}

/// Whole-day cutoff window after a month rolls over during which the
/// recap card is allowed to surface. Outside this window the user is
/// already deep into the new month — a "last month" card stops being
/// timely and becomes noise.
const int kMonthlySummaryWindowDays = 7;

final monthlySummaryInsightProvider = Provider<MonthlySummary?>((ref) {
  return summarizeMonthlyDelta(
    trend: ref.watch(dashboardTrendProvider).value,
    now: DateTime.now(),
  );
});

/// Pure helper exposed for testing. Returns `null` when:
///   * the window is closed (more than [kMonthlySummaryWindowDays]
///     into the new month),
///   * the trend lacks a point inside the previous month,
///   * the trend lacks a point inside the previous-of-previous month
///     (so we have no anchor to compute a delta).
MonthlySummary? summarizeMonthlyDelta({
  required DashboardTrend? trend,
  required DateTime now,
}) {
  if (trend == null || trend.points.isEmpty) return null;

  final nowUtc = now.toUtc();
  final monthStart = DateTime.utc(nowUtc.year, nowUtc.month);
  if (nowUtc.difference(monthStart).inDays >= kMonthlySummaryWindowDays) {
    return null;
  }

  // Window we're summarising = previous calendar month.
  final prevMonthStart = DateTime.utc(monthStart.year, monthStart.month - 1);
  final prevMonthEnd = monthStart;

  final endPoint = _lastPointInRange(
    trend.points,
    prevMonthStart,
    prevMonthEnd,
  );
  if (endPoint == null) return null;

  // Anchor = the latest point strictly before the previous month.
  final anchor = _lastPointBefore(trend.points, prevMonthStart);
  if (anchor == null) return null;

  final delta = endPoint.netWorth.amount - anchor.netWorth.amount;
  final minor = (delta * Decimal.fromInt(100)).floor().toBigInt();
  // Guard against absurdly large values; minor unit fits in 53-bit.
  if (minor.bitLength > 60) return null;

  return MonthlySummary(
    year: prevMonthStart.year,
    month: prevMonthStart.month,
    deltaMinor: minor.toInt(),
    currency: endPoint.netWorth.currency,
  );
}

TrendPoint? _lastPointInRange(
  List<TrendPoint> points,
  DateTime startInclusive,
  DateTime endExclusive,
) {
  TrendPoint? best;
  for (final p in points) {
    final asOf = p.asOf.toUtc();
    if (asOf.isBefore(startInclusive)) continue;
    if (!asOf.isBefore(endExclusive)) continue;
    if (best == null || asOf.isAfter(best.asOf.toUtc())) best = p;
  }
  return best;
}

TrendPoint? _lastPointBefore(List<TrendPoint> points, DateTime threshold) {
  TrendPoint? best;
  for (final p in points) {
    final asOf = p.asOf.toUtc();
    if (!asOf.isBefore(threshold)) continue;
    if (best == null || asOf.isAfter(best.asOf.toUtc())) best = p;
  }
  return best;
}
