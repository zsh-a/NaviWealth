part of 'quote_cache.dart';

class CachedQuote {
  const CachedQuote({
    required this.quote,
    required this.fetchedAt,
    required this.source,
    this.freshness = DataFreshness.cachedFresh,
  });

  factory CachedQuote._fromRow(MarketQuoteRow row) {
    return CachedQuote(
      quote: Quote(
        symbol: row.symbol,
        currency: row.currency,
        price: Decimal.parse(row.price),
        asOf: row.asOf,
        previousClose: row.previousClose == null
            ? null
            : Decimal.parse(row.previousClose!),
        open: row.openPrice == null ? null : Decimal.parse(row.openPrice!),
        dayHigh: row.dayHigh == null ? null : Decimal.parse(row.dayHigh!),
        dayLow: row.dayLow == null ? null : Decimal.parse(row.dayLow!),
        volume: row.volume,
        exchange: row.exchange,
      ),
      fetchedAt: row.fetchedAt,
      source: row.source,
    );
  }

  final Quote quote;
  final DateTime fetchedAt;
  final String source;
  final DataFreshness freshness;

  CachedQuote copyWithFreshness(DataFreshness f) => CachedQuote(
    quote: quote,
    fetchedAt: fetchedAt,
    source: source,
    freshness: f,
  );
}

class CachedHistory {
  const CachedHistory({
    required this.bars,
    required this.fetchedAt,
    required this.freshness,
    required this.source,
  });

  final List<HistoricalBar> bars;
  final DateTime fetchedAt;
  final DataFreshness freshness;
  final String source;
}

class CachedSearch {
  const CachedSearch({
    required this.results,
    required this.fetchedAt,
    required this.freshness,
    required this.source,
  });

  final List<SymbolInfo> results;
  final DateTime fetchedAt;
  final DataFreshness freshness;
  final String source;
}

class _LruCache<K, V> {
  _LruCache({required this.capacity}) : assert(capacity > 0);

  final int capacity;
  final _entries = <K, V>{};

  V? get(K key) {
    final v = _entries.remove(key);
    if (v == null) return null;
    _entries[key] = v;
    return v;
  }

  void set(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}
