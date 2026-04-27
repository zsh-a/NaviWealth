import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../../../domain/entities/historical_bar.dart';
import '../../../domain/entities/quote.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/values/asset_market.dart';
import '../exceptions.dart';
import '../http/market_http_client.dart';
import 'market_provider.dart';

/// CoinGecko adapter (free, public Demo API).
///
/// CoinGecko keys data by *coin id* (e.g. `bitcoin`, `ethereum`), not by
/// ticker. Quote and historical methods accept either an id (preferred) or
/// a ticker — tickers are resolved through `searchSymbol` semantics.
class CoinGeckoProvider implements MarketProvider {
  CoinGeckoProvider({required MarketHttpClient http, String vsCurrency = 'usd'})
    : _http = http,
      _vs = vsCurrency.toLowerCase();

  final MarketHttpClient _http;
  final String _vs;

  static const _base = 'https://api.coingecko.com/api/v3';

  @override
  String get name => 'coingecko';

  @override
  Set<AssetMarket> get supportedMarkets => const {AssetMarket.crypto};

  @override
  Future<Quote> getQuote(String symbol) async {
    final id = await _resolveId(symbol);
    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_base/simple/price',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: {
          'ids': id,
          'vs_currencies': _vs,
          'include_last_updated_at': true,
        },
      ),
      endpoint: 'getQuote',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'price response not an object',
        provider: name,
      );
    }
    final entry = body[id];
    if (entry is! Map<String, dynamic>) {
      throw SymbolNotFoundException(
        'coingecko price missing for id=$id',
        provider: name,
      );
    }
    final priceRaw = entry[_vs];
    if (priceRaw is! num) {
      throw ProviderResponseException(
        'price for $_vs missing for id=$id',
        provider: name,
      );
    }
    final ts = (entry['last_updated_at'] as num?)?.toInt();
    return Quote(
      symbol: symbol.toUpperCase(),
      currency: _vs.toUpperCase(),
      price: _decimal(priceRaw),
      asOf: ts == null
          ? DateTime.now().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
    );
  }

  @override
  Future<List<HistoricalBar>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
  }) async {
    final id = await _resolveId(symbol);
    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_base/coins/$id/market_chart/range',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: {
          'vs_currency': _vs,
          'from': (from.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
          'to': (to.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
        },
      ),
      endpoint: 'getHistorical',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'market_chart response not an object',
        provider: name,
      );
    }
    final prices = (body['prices'] as List?)?.cast<List<dynamic>>() ?? const [];
    final volumes =
        (body['total_volumes'] as List?)?.cast<List<dynamic>>() ?? const [];
    // CoinGecko returns one price point per day for ranges spanning >1 day.
    // We collapse to a daily bar where O=H=L=C=price (no intraday detail in
    // free tier). Volume taken from the matching daily total. Weekly /
    // monthly aggregation is left to consumers — they can resample.
    final volumeByDay = <DateTime, num>{};
    for (final v in volumes) {
      if (v.length < 2) continue;
      final ts = DateTime.fromMillisecondsSinceEpoch(
        (v[0] as num).toInt(),
        isUtc: true,
      );
      final day = DateTime.utc(ts.year, ts.month, ts.day);
      volumeByDay[day] = (v[1] as num);
    }
    final bars = <HistoricalBar>[];
    for (final p in prices) {
      if (p.length < 2) continue;
      final ts = DateTime.fromMillisecondsSinceEpoch(
        (p[0] as num).toInt(),
        isUtc: true,
      );
      final day = DateTime.utc(ts.year, ts.month, ts.day);
      final price = _decimal(p[1] as num);
      bars.add(
        HistoricalBar(
          symbol: symbol.toUpperCase(),
          asOf: day,
          open: price,
          high: price,
          low: price,
          close: price,
          volume: volumeByDay[day]?.toInt(),
        ),
      );
    }
    return bars;
  }

  @override
  Future<List<SymbolInfo>> searchSymbol(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_base/search',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: {'query': query},
      ),
      endpoint: 'searchSymbol',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'search response not an object',
        provider: name,
      );
    }
    final coins = (body['coins'] as List?) ?? const [];
    return coins
        .whereType<Map<String, dynamic>>()
        .where((c) => c['symbol'] is String && c['id'] is String)
        .map(
          (c) => SymbolInfo(
            symbol: (c['symbol'] as String).toUpperCase(),
            name: c['name'] as String? ?? c['symbol'] as String,
            market: AssetMarket.crypto,
            currency: _vs.toUpperCase(),
            // We surface the CoinGecko id in `exchange` so callers can pass
            // it back into getQuote without re-searching. Slightly abusive
            // semantically but avoids inflating the SymbolInfo schema.
            exchange: c['id'] as String,
            assetType: 'CRYPTOCURRENCY',
          ),
        )
        .toList(growable: false);
  }

  /// Resolve a free-form symbol to a CoinGecko coin id.
  ///
  /// Treats any value that looks like a coin id (lower-case, contains a hyphen
  /// or is already lower-case word) as one. Otherwise issues a search. We
  /// don't cache the mapping here — that's the cache layer's job, since the
  /// resolution result is itself a SymbolInfo.
  Future<String> _resolveId(String input) async {
    final s = input.trim();
    if (s.isEmpty) {
      throw const SymbolNotFoundException(
        'empty symbol',
        provider: 'coingecko',
      );
    }
    if (s == s.toLowerCase() && !s.contains(RegExp(r'[\^/]'))) {
      return s;
    }
    final hits = await searchSymbol(s);
    if (hits.isEmpty) {
      throw SymbolNotFoundException('no match for $s', provider: name);
    }
    final first = hits.first;
    final id = first.exchange;
    if (id == null || id.isEmpty) {
      throw ProviderResponseException(
        'search hit missing id for $s',
        provider: name,
      );
    }
    return id;
  }

  Decimal _decimal(num value) => Decimal.parse(value.toString());
}
