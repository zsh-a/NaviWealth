part of 'dashboard_providers.dart';

/// Header-strip metrics that complement the hero net-worth number with
/// signed deltas: today's change in base currency, MTD change as a ratio,
/// and YTD return as an annualized rate.
///
/// `dailyChange` is `nw(today) − nw(yesterday)` in base currency.
///
/// `monthlyChangePct` is `(nw(today) − nw(monthStart)) / nw(monthStart)`
/// — a simple percent change suitable for short windows where path-
/// dependent flows are noise. `null` when `nw(monthStart)` is zero.
///
/// `ytdChangePct` is the postings-derived money-weighted return. It uses
/// XIRR when the ledger has a solvable set of cash flows, and falls back to
/// cumulative absolute return for degenerate windows.
@immutable
class DashboardHeaderMetrics {
  const DashboardHeaderMetrics({
    required this.baseCurrency,
    required this.dailyChange,
    required this.monthlyChange,
    required this.monthlyChangePct,
    required this.ytdChange,
    required this.ytdChangePct,
  });

  final String baseCurrency;
  final Money? dailyChange;
  final Money? monthlyChange;
  final double? monthlyChangePct;
  final Money? ytdChange;
  final double? ytdChangePct;
}

final dashboardHeaderMetricsProvider = FutureProvider<DashboardHeaderMetrics>((
  ref,
) async {
  final base = ref.watch(dashboardBaseCurrencyProvider);
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final monthStart = DateTime.utc(today.year, today.month, 1);
  final yearStart = DateTime.utc(today.year, 1, 1);
  final rangeFrom = yesterday.isBefore(yearStart) ? yesterday : yearStart;

  final range = DashboardTimeRange(
    preset: DashboardRangePreset.custom,
    from: rangeFrom,
    to: today,
    granularity: NetWorthGranularity.day,
  );
  final trend = await ref.watch(dashboardTrendProvider(range).future);
  final byDate = {for (final point in trend.points) point.asOf: point};
  final todayPoint = byDate[today];
  final yesterdayPoint = byDate[yesterday];
  final monthStartPoint = byDate[monthStart];
  final yearStartPoint = byDate[yearStart];

  bool reliable(TrendPoint? point) =>
      point?.quality == TrendPointQuality.complete;

  Money? change(TrendPoint? current, TrendPoint? baseline) {
    if (!reliable(current) || !reliable(baseline)) return null;
    return current!.netWorth - baseline!.netWorth;
  }

  double? pctChange(TrendPoint? current, TrendPoint? baseline) {
    if (!reliable(current) || !reliable(baseline)) return null;
    final currentMoney = current!.netWorth;
    final baselineMoney = baseline!.netWorth;
    if (baselineMoney.amount.sign == 0) {
      return currentMoney.amount.sign == 0 ? null : double.infinity;
    }
    final ratio =
        (currentMoney.amount - baselineMoney.amount) / baselineMoney.amount;
    return ratio.toDecimal(scaleOnInfinitePrecision: 8).toDouble();
  }

  final ytdReliable = reliable(todayPoint) && reliable(yearStartPoint);
  final ytdRatio = ytdReliable
      ? await _ytdRatio(ref, from: yearStart, to: today)
      : null;

  return DashboardHeaderMetrics(
    baseCurrency: base,
    dailyChange: change(todayPoint, yesterdayPoint),
    monthlyChange: change(todayPoint, monthStartPoint),
    monthlyChangePct: pctChange(todayPoint, monthStartPoint),
    ytdChange: change(todayPoint, yearStartPoint),
    ytdChangePct: ytdRatio,
  );
});

Future<double?> _ytdRatio(
  Ref ref, {
  required DateTime from,
  required DateTime to,
}) async {
  final service = await ref.watch(portfolioReturnServiceProvider.future);
  final result = await service.compute(from: from, to: to);
  return result.displayReturn;
}
