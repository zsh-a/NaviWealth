import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/providers/yahoo_crumb_session.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';

import 'options_chain_provider.dart';

part 'yfinance_options_models.dart';
part 'yfinance_options_normalization.dart';
part 'yfinance_options_parsing.dart';
part 'yfinance_options_projection.dart';

/// Yahoo Finance options-chain adapter.
///
/// Uses the same `query1.finance.yahoo.com/v7/finance/options/<symbol>`
/// endpoint as the `yfinance` (Python) library. Yahoo TOS bars commercial
/// redistribution — see `docs/market-data-providers.md`; the data is
/// consumed locally and never written to a synced table.
class YFinanceOptionsProvider
    with
        YFinanceOptionsNormalizationMixin,
        YFinanceOptionsParsingMixin,
        YFinanceOptionsProjectionMixin
    implements OptionsChainProvider {
  YFinanceOptionsProvider({
    required MarketHttpClient http,
    required YahooCrumbSession session,
    Clock clock = const SystemClock(),
  }) : _http = http,
       _session = session,
       _clock = clock;

  final MarketHttpClient _http;
  final YahooCrumbSession _session;
  @override
  final Clock _clock;

  /// Per-symbol-per-expiration throttle. Maps "AAPL:2026-06-20" to its
  /// most recent successful response. The provider returns the cached
  /// payload (filtered to the requested DTE window) when called inside
  /// the [_perKeyTtl] window — design doc §4.1.
  final Map<String, _CachedChainPayload> _perKeyCache = {};
  static const Duration _perKeyTtl = Duration(minutes: 5);

  static const _base = 'https://query1.finance.yahoo.com/v7/finance/options';
  static const _requestTimeout = Duration(seconds: 10);
  static const _maxExpirationSlices = 2;

  @override
  String get name => 'yfinance_options';

  @override
  Future<OptionsChainSnapshot> fetchChain(OptionsChainRequest request) async {
    final upper = request.underlying.toUpperCase();
    final cached = _perKeyCache[upper];
    final now = _clock.now().toUtc();
    if (cached != null && now.difference(cached.fetchedAt) < _perKeyTtl) {
      return _projection(cached, request);
    }

    final firstResp = await _fetchOnce(upper, expirationEpoch: null);
    final expirations = firstResp.expirations;
    final picked = _pickExpirations(
      expirations: expirations,
      minDte: request.minDte,
      maxDte: request.maxDte,
      asOf: now,
    );

    final contracts = <OptionContract>[];
    final visited = <int>{};
    if (firstResp.firstExpirationEpoch != null) {
      visited.add(firstResp.firstExpirationEpoch!);
      contracts.addAll(firstResp.contracts);
    }
    for (final epoch in picked) {
      if (visited.contains(epoch)) continue;
      final extra = await _fetchOnce(upper, expirationEpoch: epoch);
      contracts.addAll(extra.contracts);
      visited.add(epoch);
    }

    final payload = _CachedChainPayload(
      currency: firstResp.currency,
      underlyingPriceRaw: firstResp.underlyingPriceRaw,
      fetchedAt: now,
      contracts: contracts,
    );
    _perKeyCache[upper] = payload;
    return _projection(payload, request);
  }

  /// Sends a chain request with the cached crumb + cookie attached. On
  /// 401 (Yahoo rotates crumbs aggressively) the session is invalidated
  /// and the call retried once with a fresh handshake.
  @override
  Future<Response<Map<String, dynamic>>> _sendAuthed(
    String symbol, {
    int? expirationEpoch,
  }) async {
    Future<Response<Map<String, dynamic>>> attempt() async {
      await _session.ensureReady();
      final headers = Map<String, String>.from(
        YahooCrumbSession.browserHeaders(),
      );
      final cookie = _session.cookieHeader;
      if (cookie != null) headers['Cookie'] = cookie;
      return _http.send<Map<String, dynamic>>(
        RequestOptions(
          path: '$_base/${Uri.encodeComponent(symbol)}',
          method: 'GET',
          responseType: ResponseType.json,
          connectTimeout: _requestTimeout,
          sendTimeout: _requestTimeout,
          receiveTimeout: _requestTimeout,
          queryParameters: {'date': ?expirationEpoch, 'crumb': ?_session.crumb},
          headers: headers,
        ),
        endpoint: 'getOptionsChain',
      );
    }

    try {
      return await attempt();
    } on ProviderUnavailableException catch (e) {
      if (e.statusCode != 401) rethrow;
      _session.invalidate();
      return attempt();
    }
  }
}
