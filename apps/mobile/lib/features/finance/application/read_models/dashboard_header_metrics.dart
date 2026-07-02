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
  final Money dailyChange;
  final Money monthlyChange;
  final double? monthlyChangePct;
  final Money ytdChange;
  final double? ytdChangePct;
}

final dashboardHeaderMetricsProvider = FutureProvider<DashboardHeaderMetrics>((
  ref,
) async {
  // Establish the same postings-derived invalidation edge as the dashboard
  // snapshot. The return service does the historical XIRR query below.
  final manualList = await _manualAssetValuationsForHeader(ref);
  final physicalList = await ref.watch(physicalAssetsListProvider.future);
  final liabList = await ref.watch(liabilitiesStreamProvider.future);
  final assetList = await ref.watch(allAssetsStreamProvider.future);
  final holdingsByAsset = await ref.watch(holdingsSnapshotProvider.future);
  final priceRows = await ref.watch(dashboardPriceRowsProvider.future);
  final fxRows = await ref.watch(fxRatesStreamProvider.future);
  final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(fxRows));
  final base = ref.watch(dashboardBaseCurrencyProvider);
  final schedules = await _liabilitySchedulesForTrend(ref, liabList);
  final securities = _buildSecurityHoldings(
    holdingsByAsset: holdingsByAsset,
    assets: assetList,
  );
  final securityPrices = _buildSecurityPriceHistory(
    assets: assetList,
    priceRows: priceRows,
  );

  final builder = DashboardTrendBuilder(
    converter: converter,
    baseCurrency: base,
  );

  Money nwAt(DateTime date) {
    final range = DashboardTimeRange(
      preset: DashboardRangePreset.custom,
      from: date,
      to: date,
      granularity: NetWorthGranularity.day,
    );
    final trend = builder.build(
      range: range,
      manualAssets: manualList,
      physicalAssets: dashboardPhysicalAssetsFrom(physicalList),
      liabilities: liabList,
      liabilitySchedules: schedules,
      securitiesHoldings: securities,
      securityPrices: securityPrices,
    );
    return trend.points.isEmpty
        ? Money.zero(base)
        : trend.points.first.netWorth;
  }

  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final monthStart = DateTime.utc(today.year, today.month, 1);
  final yearStart = DateTime.utc(today.year, 1, 1);

  final nwToday = nwAt(today);
  final nwYesterday = nwAt(yesterday);
  final nwMonthStart = nwAt(monthStart);
  final nwYearStart = nwAt(yearStart);

  double? pctChange(Money current, Money baseline) {
    if (baseline.amount.sign == 0) {
      return current.amount.sign == 0 ? null : double.infinity;
    }
    final ratio = (current.amount - baseline.amount) / baseline.amount;
    return ratio.toDecimal(scaleOnInfinitePrecision: 8).toDouble();
  }

  final ytdRatio = await _ytdRatio(ref, from: yearStart, to: today);

  return DashboardHeaderMetrics(
    baseCurrency: base,
    dailyChange: nwToday - nwYesterday,
    monthlyChange: nwToday - nwMonthStart,
    monthlyChangePct: pctChange(nwToday, nwMonthStart),
    ytdChange: nwToday - nwYearStart,
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
