import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import 'cache_policy.dart';

part 'quote_cache_helpers.dart';
part 'quote_cache_history.dart';
part 'quote_cache_models.dart';
part 'quote_cache_quotes.dart';
part 'quote_cache_search.dart';

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
///                    "数据延迟" badge (离线降级).
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

  Future<CachedQuote?> readQuote(
    String symbol, {
    AssetMarket? market,
    String? source,
  }) => _readQuote(this, symbol, market: market, source: source);

  Future<void> writeQuote(
    Quote quote, {
    AssetMarket? market,
    required String source,
  }) => _writeQuote(this, quote, market: market, source: source);

  // ─── history ───────────────────────────────────────────────────────────

  Future<CachedHistory?> readHistory({
    required String symbol,
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
    String? source,
  }) => _readHistory(
    this,
    symbol: symbol,
    from: from,
    to: to,
    interval: interval,
    market: market,
    source: source,
  );

  Future<void> writeHistory(
    List<HistoricalBar> bars, {
    required BarInterval interval,
    AssetMarket? market,
    required String source,
  }) => _writeHistory(
    this,
    bars,
    interval: interval,
    market: market,
    source: source,
  );

  // ─── search ────────────────────────────────────────────────────────────

  Future<CachedSearch?> readSearch(
    String query, {
    AssetMarket? market,
    String? source,
  }) => _readSearch(this, query, market: market, source: source);

  Future<void> writeSearch(
    String query,
    List<SymbolInfo> results, {
    AssetMarket? market,
    required String source,
  }) => _writeSearch(this, query, results, market: market, source: source);
}
