import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'cache/quote_cache.dart';
import 'exceptions.dart';
import 'http/clock.dart';
import 'metrics/market_metrics.dart';
import 'providers/market_provider.dart';

/// Default [MarketDataService] implementation.
///
/// Pipeline per request:
///   1. Cache hit (fresh) → return immediately.
///   2. Provider chain (in order, filtered by `supportedMarkets`):
///      a. On success: write to cache, return as `live`.
///      b. On `SymbolNotFoundException`: try next provider (data is just
///         not on this source).
///      c. On any other [MarketDataException]: log + record fallback,
///         try next provider.
///   3. Provider chain exhausted → look up *stale* cache; return as `stale`
///      to trigger the UI badge.
///   4. Still nothing → throw [NoMarketDataAvailableException].
class CompositeMarketDataService implements MarketDataService {
  CompositeMarketDataService({
    required List<MarketProvider> providers,
    required MarketCache cache,
    Clock clock = const SystemClock(),
    MarketMetrics? metrics,
  }) : _providers = List.unmodifiable(providers),
       _cache = cache,
       _clock = clock,
       _metrics = metrics;

  final List<MarketProvider> _providers;
  final MarketCache _cache;
  final Clock _clock;
  final MarketMetrics? _metrics;

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    final cached = await _cache.readQuote(symbol);
    if (cached != null && cached.freshness == DataFreshness.cachedFresh) {
      _metrics?.recordCache(
        endpoint: 'getQuote',
        outcome: CacheOutcome.hitFresh,
      );
      return MarketResponse(
        data: cached.quote,
        freshness: DataFreshness.cachedFresh,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    _metrics?.recordCache(endpoint: 'getQuote', outcome: CacheOutcome.miss);

    final candidates = _providersFor(market);
    Object? lastError;
    String? lastProvider;
    for (final provider in candidates) {
      try {
        final quote = await provider.getQuote(symbol);
        await _cache.writeQuote(quote, source: provider.name);
        if (lastProvider != null) {
          _metrics?.recordFallback(
            fromProvider: lastProvider,
            toProvider: provider.name,
          );
        }
        return MarketResponse(
          data: quote,
          freshness: DataFreshness.live,
          source: provider.name,
          fetchedAt: _clock.now(),
        );
      } on SymbolNotFoundException catch (e) {
        // Not on this source — try next without escalating.
        AppLogger.instance.d('${provider.name} no symbol for $symbol: $e');
        lastError = e;
        lastProvider = provider.name;
      } on MarketDataException catch (e) {
        AppLogger.instance.w(
          '${provider.name} failed for $symbol: $e; falling back',
        );
        lastError = e;
        lastProvider = provider.name;
      }
    }

    return _serveStaleQuote(symbol, lastError);
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    final cached = await _cache.readHistory(
      symbol: symbol,
      from: from,
      to: to,
      interval: interval,
    );
    final cacheCoversRange =
        cached != null && _coversRange(cached.bars, from, to);
    if (cacheCoversRange && cached.freshness == DataFreshness.cachedFresh) {
      _metrics?.recordCache(
        endpoint: 'getHistorical',
        outcome: CacheOutcome.hitFresh,
      );
      return MarketResponse(
        data: cached.bars,
        freshness: DataFreshness.cachedFresh,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    _metrics?.recordCache(
      endpoint: 'getHistorical',
      outcome: CacheOutcome.miss,
    );

    final candidates = _providersFor(market);
    Object? lastError;
    String? lastProvider;
    for (final provider in candidates) {
      try {
        final bars = await provider.getHistorical(
          symbol,
          from: from,
          to: to,
          interval: interval,
        );
        await _cache.writeHistory(
          bars,
          interval: interval,
          source: provider.name,
        );
        if (lastProvider != null) {
          _metrics?.recordFallback(
            fromProvider: lastProvider,
            toProvider: provider.name,
          );
        }
        return MarketResponse(
          data: bars,
          freshness: DataFreshness.live,
          source: provider.name,
          fetchedAt: _clock.now(),
        );
      } on UnsupportedError catch (e) {
        // E.g. SinaProvider does not expose historical bars; skip silently.
        AppLogger.instance.d('${provider.name} no historical for $symbol: $e');
        lastError = e;
        lastProvider = provider.name;
      } on SymbolNotFoundException catch (e) {
        lastError = e;
        lastProvider = provider.name;
      } on MarketDataException catch (e) {
        AppLogger.instance.w(
          '${provider.name} history failed for $symbol: $e; falling back',
        );
        lastError = e;
        lastProvider = provider.name;
      }
    }

    if (cached != null) {
      _metrics?.recordCache(
        endpoint: 'getHistorical',
        outcome: CacheOutcome.hitStale,
      );
      return MarketResponse(
        data: cached.bars,
        freshness: DataFreshness.stale,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    throw NoMarketDataAvailableException(
      'no provider produced history for $symbol',
      cause: lastError,
    );
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async {
    if (query.trim().isEmpty) {
      return MarketResponse(
        data: const [],
        freshness: DataFreshness.live,
        source: 'noop',
        fetchedAt: _clock.now(),
      );
    }
    final cached = await _cache.readSearch(query);
    if (cached != null && cached.freshness == DataFreshness.cachedFresh) {
      _metrics?.recordCache(
        endpoint: 'searchSymbol',
        outcome: CacheOutcome.hitFresh,
      );
      return MarketResponse(
        data: cached.results,
        freshness: DataFreshness.cachedFresh,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    _metrics?.recordCache(endpoint: 'searchSymbol', outcome: CacheOutcome.miss);

    final candidates = _providersFor(market);
    Object? lastError;
    final aggregated = <String, SymbolInfo>{};
    String? sourceTag;
    for (final provider in candidates) {
      try {
        final hits = await provider.searchSymbol(query);
        for (final hit in hits) {
          aggregated.putIfAbsent(_searchKey(hit), () => hit);
        }
        sourceTag = sourceTag == null
            ? provider.name
            : '$sourceTag+${provider.name}';
      } on UnsupportedError catch (e) {
        AppLogger.instance.d('${provider.name} no search: $e');
      } on MarketDataException catch (e) {
        AppLogger.instance.w('${provider.name} search failed: $e');
        lastError = e;
      }
    }

    if (aggregated.isNotEmpty) {
      final results = aggregated.values.toList(growable: false);
      await _cache.writeSearch(
        query,
        results,
        source: sourceTag ?? 'composite',
      );
      return MarketResponse(
        data: results,
        freshness: DataFreshness.live,
        source: sourceTag ?? 'composite',
        fetchedAt: _clock.now(),
      );
    }
    if (cached != null) {
      _metrics?.recordCache(
        endpoint: 'searchSymbol',
        outcome: CacheOutcome.hitStale,
      );
      return MarketResponse(
        data: cached.results,
        freshness: DataFreshness.stale,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    throw NoMarketDataAvailableException(
      'no provider returned search results for "$query"',
      cause: lastError,
    );
  }

  Future<MarketResponse<Quote>> _serveStaleQuote(
    String symbol,
    Object? lastError,
  ) async {
    final cached = await _cache.readQuote(symbol);
    if (cached != null) {
      _metrics?.recordCache(
        endpoint: 'getQuote',
        outcome: CacheOutcome.hitStale,
      );
      return MarketResponse(
        data: cached.quote,
        freshness: DataFreshness.stale,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
    }
    throw NoMarketDataAvailableException(
      'no provider returned a quote for $symbol and no cached fallback exists',
      cause: lastError,
    );
  }

  List<MarketProvider> _providersFor(AssetMarket? market) {
    if (market == null || market == AssetMarket.unknown) return _providers;
    final routed = _providers
        .where((p) => p.supportedMarkets.contains(market))
        .toList(growable: false);
    return routed.isEmpty ? _providers : routed;
  }

  bool _coversRange(List<HistoricalBar> bars, DateTime from, DateTime to) {
    if (bars.isEmpty) return false;
    final first = bars.first.asOf;
    final last = bars.last.asOf;
    // Permit a 3-day grace at each edge for non-trading days at boundaries.
    return first.isBefore(from.add(const Duration(days: 3))) &&
        last.isAfter(to.subtract(const Duration(days: 3)));
  }

  String _searchKey(SymbolInfo info) =>
      '${info.market.name}:${info.symbol.toUpperCase()}';
}
