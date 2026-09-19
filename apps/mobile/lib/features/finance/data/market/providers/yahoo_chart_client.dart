import 'package:dio/dio.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';

import 'yahoo_crumb_session.dart';

/// Shared Yahoo chart transport for quotes, history, and corporate actions.
///
/// Yahoo's chart endpoint is used by several market adapters, so session
/// cookies, crumb refresh, browser headers, and 401 recovery live here rather
/// than drifting between feature-specific providers.
class YahooChartClient {
  YahooChartClient({required MarketHttpClient http, YahooCrumbSession? session})
    : _http = http,
      _session = session;

  static const String chartBase =
      'https://query1.finance.yahoo.com/v8/finance/chart';
  static const Duration requestTimeout = Duration(seconds: 10);

  final MarketHttpClient _http;
  final YahooCrumbSession? _session;

  Future<Response<Map<String, dynamic>>> get({
    required String path,
    required Map<String, Object?> queryParameters,
    required String endpoint,
  }) async {
    Future<Response<Map<String, dynamic>>> attempt() async {
      final query = Map<String, Object?>.from(queryParameters);
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
          connectTimeout: requestTimeout,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
          queryParameters: query,
          headers: headers,
        ),
        endpoint: endpoint,
      );
    }

    try {
      return await attempt();
    } on ProviderUnavailableException catch (error) {
      if (_session == null || error.statusCode != 401) rethrow;
      _session.invalidate();
      return attempt();
    }
  }

  Future<Response<Map<String, dynamic>>> getChart({
    required String symbol,
    required Map<String, Object?> queryParameters,
    required String endpoint,
  }) => get(
    path: '$chartBase/${Uri.encodeComponent(symbol)}',
    queryParameters: queryParameters,
    endpoint: endpoint,
  );
}
