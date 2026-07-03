part of 'quote_cache.dart';

Future<CachedQuote?> _readQuote(
  MarketCache cache,
  String symbol, {
  String? source,
}) async {
  final key = _quoteKey(symbol, source);
  final hot = cache._quoteHot.get(key);
  if (hot != null) return _withFreshness(cache, hot);

  final query = cache._db.select(cache._db.marketQuotes)
    ..where((t) => t.symbol.equals(symbol.toUpperCase()));
  if (source != null) {
    query.where((t) => t.source.equals(source));
  } else {
    query.orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]);
    query.limit(1);
  }
  final row = await query.getSingleOrNull();
  if (row == null) return null;
  final cached = CachedQuote._fromRow(row);
  final fresh = _withFreshness(cache, cached);
  if (fresh != null) cache._quoteHot.set(key, cached);
  return fresh;
}

Future<void> _writeQuote(
  MarketCache cache,
  Quote quote, {
  required String source,
}) async {
  final now = cache._clock.now();
  await cache._db
      .into(cache._db.marketQuotes)
      .insertOnConflictUpdate(
        MarketQuotesCompanion.insert(
          symbol: quote.symbol.toUpperCase(),
          source: source,
          currency: quote.currency,
          price: quote.price.toString(),
          previousClose: Value(quote.previousClose?.toString()),
          openPrice: Value(quote.open?.toString()),
          dayHigh: Value(quote.dayHigh?.toString()),
          dayLow: Value(quote.dayLow?.toString()),
          volume: Value(quote.volume),
          exchange: Value(quote.exchange),
          asOf: quote.asOf,
          fetchedAt: now,
        ),
      );
  cache._quoteHot.set(
    _quoteKey(quote.symbol, source),
    CachedQuote(quote: quote, fetchedAt: now, source: source),
  );
}
