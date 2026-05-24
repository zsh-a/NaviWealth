import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../../../features/investment/domain/reporting/event_timeline.dart';
import '../exceptions.dart';
import '../http/market_http_client.dart';
import '../providers/yfinance_corporate_actions.dart';

/// Fetch + cache for per-symbol corporate-action events
/// (`docs/roadmap-next.md` §3.5).
///
/// Wraps the yfinance chart endpoint (already used for historical bars)
/// with `events=div,splits` and the [parseYahooCorporateActions] parser.
/// The cache is in-memory only — corporate actions are derived public
/// data, so losing the cache on restart costs at most one extra fetch
/// per watched symbol. No Drift table, no sync.
///
/// **Failure mode**: network errors are swallowed and surface as an
/// empty event list. The error is cached for [_errorTtl] so a fan-out
/// fetch (e.g. user opens the watchlist) doesn't immediately retry
/// every symbol after a transient outage. Live errors still flow into
/// the app logger.
class CorporateActionsService {
  CorporateActionsService({
    required MarketHttpClient http,
    required AppLogger logger,
    Duration successTtl = const Duration(hours: 12),
    Duration errorTtl = const Duration(minutes: 15),
    DateTime Function()? now,
  })  : _http = http,
        _logger = logger,
        _successTtl = successTtl,
        _errorTtl = errorTtl,
        _now = now ?? (() => DateTime.now().toUtc());

  final MarketHttpClient _http;
  final AppLogger _logger;
  final Duration _successTtl;
  final Duration _errorTtl;
  final DateTime Function() _now;

  static const String _chartBase =
      'https://query1.finance.yahoo.com/v8/finance/chart';
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  final Map<String, Future<List<CorporateActionEvent>>> _inflight =
      <String, Future<List<CorporateActionEvent>>>{};

  /// Return events for [symbol]. Hits the cache when available + fresh,
  /// dedupes concurrent calls for the same symbol, fetches from the
  /// provider when the cache is cold or stale.
  Future<List<CorporateActionEvent>> getForSymbol(String symbol) {
    final key = symbol.trim().toUpperCase();
    if (key.isEmpty) return Future.value(const <CorporateActionEvent>[]);

    final cached = _cache[key];
    if (cached != null && !cached.expired(_now())) {
      return Future.value(cached.events);
    }
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final fut = _fetchAndStore(key);
    _inflight[key] = fut;
    fut.whenComplete(() => _inflight.remove(key));
    return fut;
  }

  /// Drop the cached entry (and any in-flight fetch) for [symbol]. A
  /// subsequent [getForSymbol] will hit the network. Useful when the
  /// UI surfaces an explicit "Refresh events" action.
  void invalidate(String symbol) {
    _cache.remove(symbol.trim().toUpperCase());
  }

  Future<List<CorporateActionEvent>> _fetchAndStore(String symbol) async {
    try {
      final events = await _fetch(symbol);
      _cache[symbol] = _CacheEntry(
        events: events,
        fetchedAt: _now(),
        ttl: _successTtl,
      );
      return events;
    } catch (err, st) {
      _logger.w(
        'corporate_actions_service: $symbol fetch failed',
        error: err,
        stackTrace: st,
      );
      _cache[symbol] = _CacheEntry(
        events: const <CorporateActionEvent>[],
        fetchedAt: _now(),
        ttl: _errorTtl,
      );
      return const <CorporateActionEvent>[];
    }
  }

  Future<List<CorporateActionEvent>> _fetch(String symbol) async {
    // Pull a window straddling now so we catch upcoming events (Yahoo
    // surfaces announced dividends/splits with future ex-dates) plus
    // any very recently passed ones the UI may want to display under
    // a "last announced" affordance.
    final now = _now();
    final from = now.subtract(const Duration(days: 30));
    final to = now.add(const Duration(days: 365));

    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_chartBase/${Uri.encodeComponent(symbol)}',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: <String, Object?>{
          'interval': '1d',
          'period1': (from.millisecondsSinceEpoch ~/ 1000).toString(),
          'period2': (to.millisecondsSinceEpoch ~/ 1000).toString(),
          'events': 'div,splits',
        },
        headers: const <String, Object?>{'User-Agent': _userAgent},
      ),
      endpoint: 'corporateActions',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const ProviderResponseException(
        'chart response not an object',
        provider: 'yfinance',
      );
    }
    final currency = _currencyOf(body) ?? _defaultCurrencyFor(symbol);
    return parseYahooCorporateActions(
      responseBody: body,
      symbol: symbol,
      currency: currency,
    );
  }

  /// Best-effort extraction of `chart.result[0].meta.currency`. Returns
  /// `null` on any schema drift — the caller falls back.
  String? _currencyOf(Map<String, dynamic> body) {
    final chart = body['chart'];
    if (chart is! Map) return null;
    final results = chart['result'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    final meta = first['meta'];
    if (meta is! Map) return null;
    final currency = meta['currency'];
    return currency is String ? currency.toUpperCase() : null;
  }

  /// Coarse fallback when yfinance omits the currency tag. We pick USD
  /// for US tickers and HKD for `.HK` suffixed ones; everything else
  /// defaults to USD which Money treats as a documentable
  /// "needs FX" rather than silently mixing currencies.
  String _defaultCurrencyFor(String symbol) {
    if (symbol.toUpperCase().endsWith('.HK')) return 'HKD';
    return 'USD';
  }
}

class _CacheEntry {
  _CacheEntry({
    required this.events,
    required this.fetchedAt,
    required this.ttl,
  });

  final List<CorporateActionEvent> events;
  final DateTime fetchedAt;
  final Duration ttl;

  bool expired(DateTime now) => now.difference(fetchedAt) >= ttl;
}
