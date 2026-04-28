import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/entities/historical_bar.dart';
import '../../../domain/entities/quote.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../http/clock.dart';
import 'cache_policy.dart';

/// Read-through cache for quotes, history, and symbol search.
///
/// Layout:
///   * In-memory LRU for quotes (hot path) and search (cheap to recompute,
///     but TTL is long so memoisation pays).
///   * Drift-backed persistence for everything → survives app restart and
///     enables offline degradation. Access goes through the same API.
///
/// Tag semantics for `read*` results:
///   * `cachedFresh` — younger than `XxxFresh`.
///   * `stale`      — between `XxxFresh` and `XxxStaleWindow`. UI shows the
///                    "数据延迟" badge (FIR-26 离线降级).
///   * miss         — older than the stale window OR no row exists; returns
///                    null and the caller must hit a provider.
class MarketCache {
  MarketCache({
    required AppDatabase db,
    Clock clock = const SystemClock(),
    MarketCachePolicy policy = const MarketCachePolicy(),
  }) : _db = db,
       _clock = clock,
       _policy = policy,
       _quoteHot = _LruCache(capacity: policy.maxInMemoryQuotes);

  final AppDatabase _db;
  final Clock _clock;
  final MarketCachePolicy _policy;
  final _LruCache<String, CachedQuote> _quoteHot;

  // ─── quotes ────────────────────────────────────────────────────────────

  Future<CachedQuote?> readQuote(String symbol, {String? source}) async {
    final key = _quoteKey(symbol, source);
    final hot = _quoteHot.get(key);
    if (hot != null) return _withFreshness(hot);

    final query = _db.select(_db.marketQuotes)
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
    final fresh = _withFreshness(cached);
    if (fresh != null) _quoteHot.set(key, cached);
    return fresh;
  }

  Future<void> writeQuote(Quote quote, {required String source}) async {
    final now = _clock.now();
    await _db
        .into(_db.marketQuotes)
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
    _quoteHot.set(
      _quoteKey(quote.symbol, source),
      CachedQuote(quote: quote, fetchedAt: now, source: source),
    );
  }

  // ─── history ───────────────────────────────────────────────────────────

  Future<CachedHistory?> readHistory({
    required String symbol,
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    String? source,
  }) async {
    final query = _db.select(_db.marketHistoryBars)
      ..where(
        (t) =>
            t.symbol.equals(symbol.toUpperCase()) &
            t.interval.equals(_intervalKey(interval)) &
            t.asOf.isBetweenValues(from.toUtc(), to.toUtc()),
      );
    if (source != null) query.where((t) => t.source.equals(source));
    query.orderBy([(t) => OrderingTerm(expression: t.asOf)]);
    final rows = await query.get();
    if (rows.isEmpty) return null;
    final bars = rows
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
    final lastFetch = rows
        .map((r) => r.fetchedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final age = _clock.now().difference(lastFetch);
    final freshness = _classify(
      age,
      fresh: _policy.historyFresh,
      stale: _policy.historyStaleWindow,
    );
    if (freshness == null) return null;
    return CachedHistory(
      bars: bars,
      fetchedAt: lastFetch,
      freshness: freshness,
      source: rows.first.source,
    );
  }

  Future<void> writeHistory(
    List<HistoricalBar> bars, {
    required BarInterval interval,
    required String source,
  }) async {
    if (bars.isEmpty) return;
    final now = _clock.now();
    await _db.batch((b) {
      for (final bar in bars) {
        b.insert(
          _db.marketHistoryBars,
          MarketHistoryBarsCompanion.insert(
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

  // ─── search ────────────────────────────────────────────────────────────

  Future<CachedSearch?> readSearch(String query, {String? source}) async {
    final norm = query.trim().toLowerCase();
    if (norm.isEmpty) return null;
    final q = _db.select(_db.marketSymbolSearches)
      ..where((t) => t.query.equals(norm));
    if (source != null) q.where((t) => t.source.equals(source));
    q.orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]);
    q.limit(1);
    final row = await q.getSingleOrNull();
    if (row == null) return null;
    final age = _clock.now().difference(row.fetchedAt);
    final freshness = _classify(
      age,
      fresh: _policy.searchFresh,
      stale: _policy.searchStaleWindow,
    );
    if (freshness == null) return null;
    final decoded = (jsonDecode(row.results) as List)
        .cast<Map<String, dynamic>>()
        .map(_symbolInfoFromJson)
        .toList(growable: false);
    return CachedSearch(
      results: decoded,
      fetchedAt: row.fetchedAt,
      freshness: freshness,
      source: row.source,
    );
  }

  Future<void> writeSearch(
    String query,
    List<SymbolInfo> results, {
    required String source,
  }) async {
    final norm = query.trim().toLowerCase();
    if (norm.isEmpty) return;
    final now = _clock.now();
    await _db
        .into(_db.marketSymbolSearches)
        .insertOnConflictUpdate(
          MarketSymbolSearchesCompanion.insert(
            query: norm,
            source: source,
            results: jsonEncode(
              results.map(_symbolInfoToJson).toList(growable: false),
            ),
            fetchedAt: now,
          ),
        );
  }

  // ─── helpers ───────────────────────────────────────────────────────────

  String _quoteKey(String symbol, String? source) =>
      '${symbol.toUpperCase()}|${source ?? '*'}';

  CachedQuote? _withFreshness(CachedQuote cached) {
    final age = _clock.now().difference(cached.fetchedAt);
    final freshness = _classify(
      age,
      fresh: _policy.quoteFresh,
      stale: _policy.quoteStaleWindow,
    );
    if (freshness == null) return null;
    return cached.copyWithFreshness(freshness);
  }

  DataFreshness? _classify(
    Duration age, {
    required Duration fresh,
    required Duration stale,
  }) {
    if (age <= fresh) return DataFreshness.cachedFresh;
    if (age <= stale) return DataFreshness.stale;
    return null;
  }

  String _intervalKey(BarInterval interval) {
    switch (interval) {
      case BarInterval.day:
        return '1d';
      case BarInterval.week:
        return '1wk';
      case BarInterval.month:
        return '1mo';
    }
  }

  Map<String, dynamic> _symbolInfoToJson(SymbolInfo info) => {
    'symbol': info.symbol,
    'name': info.name,
    'market': info.market.name,
    if (info.currency != null) 'currency': info.currency,
    if (info.exchange != null) 'exchange': info.exchange,
    if (info.assetType != null) 'assetType': info.assetType,
  };

  SymbolInfo _symbolInfoFromJson(Map<String, dynamic> json) => SymbolInfo(
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    market: AssetMarket.values.firstWhere(
      (m) => m.name == (json['market'] as String? ?? 'unknown'),
      orElse: () => AssetMarket.unknown,
    ),
    currency: json['currency'] as String?,
    exchange: json['exchange'] as String?,
    assetType: json['assetType'] as String?,
  );
}

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
