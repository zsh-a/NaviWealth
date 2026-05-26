import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

/// Adapter contract implemented by every external market-data source.
///
/// Composition rule: a provider returns raw [Quote] / [HistoricalBar] /
/// [SymbolInfo] without freshness wrappers — the cache layer sits above and
/// is responsible for tagging each response with [DataFreshness]. Providers
/// must throw a [MarketDataException] subclass on failure; the composite
/// service uses the type to decide retry-vs-fallback.
abstract class MarketProvider {
  String get name;

  /// Markets this provider can serve. Used to short-circuit fan-out.
  Set<AssetMarket> get supportedMarkets;

  Future<Quote> getQuote(String symbol);

  Future<List<HistoricalBar>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
  });

  Future<List<SymbolInfo>> searchSymbol(String query);
}
