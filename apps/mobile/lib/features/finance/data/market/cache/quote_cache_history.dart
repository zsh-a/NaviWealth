part of 'quote_cache.dart';

Future<CachedHistory?> _readHistory(
  MarketCache cache, {
  required String symbol,
  required DateTime from,
  required DateTime to,
  BarInterval interval = BarInterval.day,
  AssetMarket? market,
  String? source,
}) async {
  final query = cache._db.select(cache._db.marketHistoryBars)
    ..where(
      (t) =>
          t.market.equals(_marketKey(market)) &
          t.symbol.equals(symbol.toUpperCase()) &
          t.interval.equals(_intervalKey(interval)) &
          t.asOf.isBetweenValues(from.toUtc(), to.toUtc()),
    );
  if (source != null) query.where((t) => t.source.equals(source));
  query.orderBy([(t) => OrderingTerm(expression: t.asOf)]);
  final rows = await query.get();
  if (rows.isEmpty) return null;

  // Never combine bars from different providers. Their trading calendars,
  // corporate-action adjustments and coverage can differ, so a mixed series
  // is not a coherent cache entry even when every row is individually valid.
  final bySource = <String, List<MarketHistoryRow>>{};
  for (final row in rows) {
    (bySource[row.source] ??= <MarketHistoryRow>[]).add(row);
  }

  CachedHistory? best;
  for (final entry in bySource.entries) {
    final sourceRows = entry.value;
    final bars = sourceRows
        .map(
          (r) => HistoricalBar(
            symbol: r.symbol,
            asOf: r.asOf,
            open: Decimal.parse(r.openPrice),
            high: Decimal.parse(r.high),
            low: Decimal.parse(r.low),
            close: Decimal.parse(r.closePrice),
            volume: r.volume,
            adjustedClose: r.adjustedClose == null
                ? null
                : Decimal.parse(r.adjustedClose!),
          ),
        )
        .toList(growable: false);
    final lastFetch = sourceRows
        .map((r) => r.fetchedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final age = cache._clock.now().difference(lastFetch);
    final freshness = _classify(
      age,
      fresh: cache._policy.historyFresh,
      stale: cache._policy.historyStaleWindow,
    );
    if (freshness == null) continue;
    final candidate = CachedHistory(
      bars: bars,
      fetchedAt: lastFetch,
      freshness: freshness,
      source: entry.key,
    );
    if (best == null || candidate.fetchedAt.isAfter(best.fetchedAt)) {
      best = candidate;
    }
  }
  return best;
}

Future<void> _writeHistory(
  MarketCache cache,
  List<HistoricalBar> bars, {
  required BarInterval interval,
  AssetMarket? market,
  required String source,
}) async {
  if (bars.isEmpty) return;
  final now = cache._clock.now();
  await cache._db.batch((b) {
    for (final bar in bars) {
      b.insert(
        cache._db.marketHistoryBars,
        MarketHistoryBarsCompanion.insert(
          market: _marketKey(market),
          symbol: bar.symbol.toUpperCase(),
          interval: _intervalKey(interval),
          asOf: bar.asOf,
          source: source,
          openPrice: bar.open.toString(),
          high: bar.high.toString(),
          low: bar.low.toString(),
          closePrice: bar.close.toString(),
          volume: Value(bar.volume),
          adjustedClose: Value(bar.adjustedClose?.toString()),
          fetchedAt: now,
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  });
}
