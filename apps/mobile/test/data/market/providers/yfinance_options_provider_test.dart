import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/http/market_http_client.dart';
import 'package:naviwealth/data/market/http/rate_limiter.dart';
import 'package:naviwealth/data/market/http/retry_policy.dart';
import 'package:naviwealth/data/market/providers/options/options_chain_provider.dart';
import 'package:naviwealth/data/market/providers/options/yfinance_options_provider.dart';
import 'package:naviwealth/data/market/providers/yahoo_crumb_session.dart';

import '../canned_adapter.dart';
import '../fake_clock.dart';

const _aaplChain = {
  'optionChain': {
    'result': [
      {
        'quote': {'currency': 'USD', 'regularMarketPrice': 200.0},
        'expirationDates': <int>[],
        'options': <Object>[],
      },
    ],
    'error': null,
  },
};

CannedResponse _json(Object body, {int status = 200}) =>
    CannedResponse(body, status: status, headers: const {
      Headers.contentTypeHeader: ['application/json;charset=utf-8'],
    });

CannedResponse _setCookie(String value) => CannedResponse(
      '',
      status: 404,
      headers: {
        'set-cookie': [value],
        Headers.contentTypeHeader: ['text/html'],
      },
    );

CannedResponse _crumb(String token) => CannedResponse(
      token,
      status: 200,
      headers: const {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );

(YFinanceOptionsProvider, CannedAdapter) _makeProvider(FakeClock clock) {
  final adapter = CannedAdapter();
  final sessionDio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  final providerDio = Dio()..httpClientAdapter = adapter;
  final session = YahooCrumbSession(dio: sessionDio);
  final provider = YFinanceOptionsProvider(
    http: MarketHttpClient(
      providerName: 'yfinance_options',
      rateLimiter: RateLimiter(
        maxRequests: 60,
        window: const Duration(minutes: 1),
        clock: clock,
      ),
      dio: providerDio,
      // maxAttempts=1 keeps MarketHttpClient from masking the 401 with its
      // own retry loop — the test wants to observe the provider-level
      // crumb-refresh retry, not the HTTP-level retry.
      retryPolicy: const RetryPolicy(maxAttempts: 1),
      clock: clock,
    ),
    session: session,
  );
  return (provider, adapter);
}

void main() {
  group('YFinanceOptionsProvider', () {
    test('attaches crumb + Cookie to the options request on first call',
        () async {
      final clock = FakeClock();
      final (provider, adapter) = _makeProvider(clock);
      adapter
        ..enqueueRaw('fc.yahoo.com', _setCookie('A1=tok1'))
        ..enqueueRaw('getcrumb', _crumb('XCRUMB1'))
        ..enqueueRaw('finance/options/AAPL', _json(_aaplChain));

      await provider.fetchChain(
        const OptionsChainRequest(
          underlying: 'AAPL',
          minDte: 0,
          maxDte: 60,
        ),
      );

      final chainCall =
          adapter.calls.firstWhere((c) => c.uri.path.contains('options/AAPL'));
      expect(chainCall.queryParameters['crumb'], 'XCRUMB1');
      expect(chainCall.headers['Cookie'], 'A1=tok1');
    });

    test('refreshes crumb + retries once when chain endpoint returns 401',
        () async {
      final clock = FakeClock();
      final (provider, adapter) = _makeProvider(clock);
      adapter
        // First handshake.
        ..enqueueRaw('fc.yahoo.com', _setCookie('A1=stale'))
        ..enqueueRaw('getcrumb', _crumb('STALE'))
        // Stale crumb → 401.
        ..enqueueRaw(
          'finance/options/AAPL',
          _json(
            {
              'finance': {
                'result': null,
                'error': {
                  'code': 'Unauthorized',
                  'description': 'Invalid Crumb',
                },
              },
            },
            status: 401,
          ),
        )
        // Second handshake after invalidate.
        ..enqueueRaw('fc.yahoo.com', _setCookie('A1=fresh'))
        ..enqueueRaw('getcrumb', _crumb('FRESH'))
        // Retry succeeds.
        ..enqueueRaw('finance/options/AAPL', _json(_aaplChain));

      await provider.fetchChain(
        const OptionsChainRequest(
          underlying: 'AAPL',
          minDte: 0,
          maxDte: 60,
        ),
      );

      final chainCalls = adapter.calls
          .where((c) => c.uri.path.contains('options/AAPL'))
          .toList();
      expect(chainCalls, hasLength(2));
      expect(chainCalls.first.queryParameters['crumb'], 'STALE');
      expect(chainCalls.last.queryParameters['crumb'], 'FRESH');
      expect(chainCalls.last.headers['Cookie'], 'A1=fresh');
    });
  });
}
