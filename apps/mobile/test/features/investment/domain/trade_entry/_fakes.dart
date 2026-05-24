import 'package:decimal/decimal.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

/// Stub [MarketDataService] that returns canned historical bars per symbol.
class FakeMarketDataService implements MarketDataService {
  FakeMarketDataService({
    Map<String, List<HistoricalBar>>? historical,
    this.source = 'fake',
    this.errorOnHistorical,
  }) : _historical = historical ?? {};

  final Map<String, List<HistoricalBar>> _historical;
  final String source;

  /// When set, [getHistorical] throws this. Lets tests exercise the
  /// "provider failed → priceUnavailable" path.
  final Object? errorOnHistorical;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    if (errorOnHistorical != null) {
      throw errorOnHistorical!;
    }
    final bars = _historical[symbol] ?? const <HistoricalBar>[];
    final filtered = bars
        .where((b) => !b.asOf.isBefore(from) && !b.asOf.isAfter(to))
        .toList(growable: false);
    return MarketResponse(
      data: filtered,
      freshness: DataFreshness.live,
      source: source,
      fetchedAt: DateTime.utc(2026, 4, 28),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}

HistoricalBar bar(String symbol, DateTime date, String close) {
  final c = Decimal.parse(close);
  return HistoricalBar(
    symbol: symbol,
    asOf: date,
    open: c,
    high: c,
    low: c,
    close: c,
  );
}

/// Build a test [Asset] with sensible defaults.
Asset asset({
  String id = 'asset-1',
  AssetType type = AssetType.stock,
  String symbol = 'AAPL',
  String currency = 'USD',
  String? market,
}) => Asset(
  id: id,
  type: type,
  symbol: symbol,
  currency: currency,
  market: market,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: DateTime.utc(2026, 4, 28),
    updatedByDevice: 'dev',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
  ),
);

/// Counter-based [Hlc] supplier so tests can assert on emitted HLCs.
class CountingHlcStamper {
  CountingHlcStamper({this.nodeId = 'dev'});
  final String nodeId;
  int _n = 0;

  Future<Hlc> call() async {
    _n++;
    return Hlc(wallMillis: _n, counter: 0, nodeId: nodeId);
  }
}

/// Build a [CurrencyConverter] seeded with a single rate for tests.
CurrencyConverter fxConverter({
  required String base,
  required String quote,
  required String rate,
  required DateTime on,
  String source = 'test',
}) {
  return FxRateCurrencyConverter(
    InMemoryFxRateLookup([
      FxRate(
        base: base,
        quote: quote,
        date: on,
        rate: Decimal.parse(rate),
        source: source,
      ),
    ]),
  );
}
