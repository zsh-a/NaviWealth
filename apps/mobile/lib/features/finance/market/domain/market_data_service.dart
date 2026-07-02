import 'asset_market.dart';
import 'historical_bar.dart';
import 'quote.dart';
import 'symbol_info.dart';

/// Freshness label attached to every market-data response.
///
/// `live` — fetched from a provider just now.
/// `cachedFresh` — served from cache within its TTL; equivalent to live for UI.
/// `stale` — served from cache past its TTL because the provider is unreachable
/// or we are offline. UI must surface this with a badge.
enum DataFreshness { live, cachedFresh, stale }

/// Wrapper attaching freshness + source metadata to any market-data payload.
class MarketResponse<T> {
  const MarketResponse({
    required this.data,
    required this.freshness,
    required this.source,
    required this.fetchedAt,
  });

  final T data;
  final DataFreshness freshness;
  final String source;
  final DateTime fetchedAt;

  bool get isStale => freshness == DataFreshness.stale;
}

/// Unified market-data abstraction.
///
/// The single entry point used by features (assets, analytics, FIRE, etc.).
/// Implementations route to provider adapters and apply the cache + offline
/// degradation policy. Features must NOT talk to providers directly.
abstract class MarketDataService {
  /// Latest quote for [symbol]. Pass [market] when known to skip routing
  /// heuristics and reduce provider fan-out.
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market});

  /// Daily / weekly / monthly bars in `[from, to]` (inclusive, UTC dates).
  /// Bars are returned in ascending order. Empty list = no data in range.
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  });

  /// Search by ticker / company name. Results are best-effort and may include
  /// fuzzy matches. Limit is provider-dependent (typically <= 25).
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  });
}
