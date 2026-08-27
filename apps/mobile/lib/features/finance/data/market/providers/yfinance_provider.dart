import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import 'market_provider.dart';
import 'yahoo_crumb_session.dart';

/// Yahoo Finance adapter using the public `query1`/`query2` chart and search
/// endpoints. These are the same endpoints `yfinance` (Python) wraps.
///
/// Caveats — see selection notes:
/// * Yahoo's TOS prohibits commercial redistribution. Acceptable for personal,
///   non-commercial use only. The composite service must not surface this
///   data in any commercial product without a license.
/// * Endpoints are not officially versioned. Adapter parses defensively and
///   surfaces `ProviderResponseException` on schema drift.
class YFinanceProvider implements MarketProvider {
  YFinanceProvider({required MarketHttpClient http, YahooCrumbSession? session})
    : _http = http,
      _session = session;

  final MarketHttpClient _http;
  final YahooCrumbSession? _session;

  static const _chartBase = 'https://query1.finance.yahoo.com/v8/finance/chart';
  static const _searchBase =
      'https://query2.finance.yahoo.com/v1/finance/search';

  @override
  String get name => 'yfinance';

  @override
  Set<AssetMarket> get supportedMarkets => const {
    AssetMarket.usStock,
    AssetMarket.hkStock,
    AssetMarket.fx,
  };

  @override
  Future<Quote> getQuote(String symbol) async {
    final response = await _send(
      path: '$_chartBase/${Uri.encodeComponent(symbol)}',
      queryParameters: const {'interval': '1d', 'range': '5d'},
      endpoint: 'getQuote',
    );
    final result = _firstChartResult(response.data, symbol);
    final meta = _expectMap(result['meta'], 'meta');
    final priceRaw = meta['regularMarketPrice'];
    if (priceRaw is! num) {
      throw ProviderResponseException(
        'meta.regularMarketPrice missing for $symbol',
        provider: name,
      );
    }
    final ts = (meta['regularMarketTime'] as num?)?.toInt();
    return Quote(
      symbol: symbol.toUpperCase(),
      currency: (meta['currency'] as String?)?.toUpperCase() ?? 'USD',
      price: _decimal(priceRaw),
      asOf: ts == null
          ? DateTime.now().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
      previousClose: _optionalDecimal(meta['chartPreviousClose']),
      exchange: meta['exchangeName'] as String?,
    );
  }

  @override
  Future<List<HistoricalBar>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
  }) async {
    final fromDay = _floorUtcDay(from);
    // Yahoo's period2 is exclusive, while MarketDataService's contract is
    // inclusive on both calendar-day endpoints.
    final toExclusive = _floorUtcDay(to).add(const Duration(days: 1));
    final response = await _send(
      path: '$_chartBase/${Uri.encodeComponent(symbol)}',
      queryParameters: {
        'interval': _intervalParam(interval),
        'period1': (fromDay.millisecondsSinceEpoch ~/ 1000).toString(),
        'period2': (toExclusive.millisecondsSinceEpoch ~/ 1000).toString(),
        'events': 'div,splits',
      },
      endpoint: 'getHistorical',
    );
    final result = _firstChartResult(response.data, symbol);
    final timestamps = (result['timestamp'] as List?)?.cast<num>() ?? const [];
    if (timestamps.isEmpty) return const [];
    final indicators = _expectMap(result['indicators'], 'indicators');
    final quoteList = (indicators['quote'] as List?)?.cast<dynamic>();
    if (quoteList == null || quoteList.isEmpty) {
      throw ProviderResponseException(
        'indicators.quote missing for $symbol',
        provider: name,
      );
    }
    final q = _expectMap(quoteList.first, 'indicators.quote[0]');
    final adjList = (indicators['adjclose'] as List?)?.cast<dynamic>();
    final adj = adjList == null || adjList.isEmpty
        ? null
        : (_expectMap(adjList.first, 'adjclose')['adjclose'] as List?)
              ?.cast<num?>();
    final opens = (q['open'] as List?)?.cast<num?>() ?? const [];
    final highs = (q['high'] as List?)?.cast<num?>() ?? const [];
    final lows = (q['low'] as List?)?.cast<num?>() ?? const [];
    final closes = (q['close'] as List?)?.cast<num?>() ?? const [];
    final volumes = (q['volume'] as List?)?.cast<num?>() ?? const [];

    final bars = <HistoricalBar>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = i < closes.length ? closes[i] : null;
      final open = i < opens.length ? opens[i] : null;
      final high = i < highs.length ? highs[i] : null;
      final low = i < lows.length ? lows[i] : null;
      // Yahoo emits null cells for non-trading days inside the range.
      if (close == null || open == null || high == null || low == null) {
        continue;
      }
      final ts = DateTime.fromMillisecondsSinceEpoch(
        timestamps[i].toInt() * 1000,
        isUtc: true,
      );
      bars.add(
        HistoricalBar(
          symbol: symbol.toUpperCase(),
          asOf: DateTime.utc(ts.year, ts.month, ts.day),
          open: _decimal(open),
          high: _decimal(high),
          low: _decimal(low),
          close: _decimal(close),
          volume: i < volumes.length ? volumes[i]?.toInt() : null,
          adjustedClose: (adj != null && i < adj.length && adj[i] != null)
              ? _decimal(adj[i]!)
              : null,
        ),
      );
    }
    return bars;
  }

  @override
  Future<List<SymbolInfo>> searchSymbol(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _send(
      path: _searchBase,
      queryParameters: {
        'q': query,
        'quotesCount': 20,
        'newsCount': 0,
        'enableFuzzyQuery': true,
      },
      endpoint: 'searchSymbol',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'search response not an object',
        provider: name,
      );
    }
    final quotes = (body['quotes'] as List?) ?? const [];
    return quotes
        .whereType<Map<String, dynamic>>()
        .where((q) => q['symbol'] is String)
        .map((q) {
          final exch = q['exchange'] as String?;
          return SymbolInfo(
            symbol: q['symbol'] as String,
            name:
                (q['shortname'] as String?) ??
                (q['longname'] as String?) ??
                q['symbol'] as String,
            market: _inferMarket(exch, q['quoteType'] as String?),
            exchange: exch,
            assetType: q['quoteType'] as String?,
          );
        })
        .toList(growable: false);
  }

  /// Sends a Yahoo request with the shared browser session when one is
  /// configured. The optional session keeps the provider easy to unit-test
  /// with a plain canned HTTP adapter; production wiring always supplies the
  /// app-wide [YahooCrumbSession].
  Future<Response<Map<String, dynamic>>> _send({
    required String path,
    required Map<String, dynamic> queryParameters,
    required String endpoint,
  }) async {
    Future<Response<Map<String, dynamic>>> attempt() async {
      final query = Map<String, dynamic>.from(queryParameters);
      final headers = Map<String, String>.from(
        YahooCrumbSession.browserHeaders(),
      );
      final session = _session;
      if (session != null) {
        await session.ensureReady();
        final crumb = session.crumb;
        if (crumb != null && crumb.isNotEmpty) query['crumb'] = crumb;
        final cookie = session.cookieHeader;
        if (cookie != null) headers['Cookie'] = cookie;
      }
      return _http.send<Map<String, dynamic>>(
        RequestOptions(
          path: path,
          method: 'GET',
          responseType: ResponseType.json,
          connectTimeout: _requestTimeout,
          sendTimeout: _requestTimeout,
          receiveTimeout: _requestTimeout,
          queryParameters: query,
          headers: headers,
        ),
        endpoint: endpoint,
      );
    }

    try {
      return await attempt();
    } on ProviderUnavailableException catch (e) {
      // Yahoo can rotate the crumb while the app is running. Retry the
      // request once after a complete handshake rather than falling through
      // to a provider that cannot serve FX at all.
      if (_session == null || e.statusCode != 401) rethrow;
      _session.invalidate();
      return attempt();
    }
  }

  Map<String, dynamic> _firstChartResult(dynamic body, String symbol) {
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'chart response not an object',
        provider: name,
      );
    }
    final chart = body['chart'];
    if (chart is! Map<String, dynamic>) {
      throw ProviderResponseException('chart envelope missing', provider: name);
    }
    final err = chart['error'];
    if (err is Map<String, dynamic>) {
      final code = err['code'] as String? ?? 'unknown';
      final desc = err['description'] as String? ?? '';
      if (code.toLowerCase().contains('not') &&
          code.toLowerCase().contains('found')) {
        throw SymbolNotFoundException('$symbol: $desc', provider: name);
      }
      throw ProviderResponseException('$code: $desc', provider: name);
    }
    final results = (chart['result'] as List?) ?? const [];
    if (results.isEmpty) {
      throw SymbolNotFoundException(
        '$symbol returned no chart result',
        provider: name,
      );
    }
    return _expectMap(results.first, 'chart.result[0]');
  }

  Map<String, dynamic> _expectMap(dynamic value, String path) {
    if (value is Map<String, dynamic>) return value;
    throw ProviderResponseException(
      '$path expected object, got ${value.runtimeType}',
      provider: name,
    );
  }

  Decimal _decimal(num value) => Decimal.parse(value.toString());

  Decimal? _optionalDecimal(dynamic value) =>
      value is num ? _decimal(value) : null;

  String _intervalParam(BarInterval interval) {
    switch (interval) {
      case BarInterval.day:
        return '1d';
      case BarInterval.week:
        return '1wk';
      case BarInterval.month:
        return '1mo';
    }
  }

  DateTime _floorUtcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  AssetMarket _inferMarket(String? exchange, String? type) {
    if (type == 'CRYPTOCURRENCY') return AssetMarket.crypto;
    if (type == 'CURRENCY') return AssetMarket.fx;
    final ex = exchange?.toUpperCase() ?? '';
    if (ex == 'HKG') return AssetMarket.hkStock;
    if (ex == 'SHH' || ex == 'SHZ') return AssetMarket.cnA;
    if (ex == 'NMS' ||
        ex == 'NYQ' ||
        ex == 'NYM' ||
        ex == 'NGM' ||
        ex == 'PCX') {
      return AssetMarket.usStock;
    }
    return AssetMarket.unknown;
  }

  static const _requestTimeout = Duration(seconds: 10);
}
