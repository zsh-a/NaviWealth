import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/providers/yahoo_crumb_session.dart';
import 'package:naviwealth/features/finance/data/market/providers/yfinance_provider.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';

import '../canned_adapter.dart';
import '../fake_clock.dart';

YFinanceProvider _makeProvider(
  CannedAdapter adapter,
  FakeClock clock, {
  YahooCrumbSession? session,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return YFinanceProvider(
    http: MarketHttpClient(
      providerName: 'yfinance',
      rateLimiter: RateLimiter(
        maxRequests: 60,
        window: const Duration(minutes: 1),
        clock: clock,
      ),
      dio: dio,
      retryPolicy: const RetryPolicy(maxAttempts: 1),
      clock: clock,
    ),
    session: session,
  );
}

void main() {
  group('YFinanceProvider.getQuote', () {
    test('parses meta block from chart endpoint', () async {
      final adapter = CannedAdapter()
        ..enqueue('finance/chart/AAPL', {
          'chart': {
            'result': [
              {
                'meta': {
                  'currency': 'USD',
                  'symbol': 'AAPL',
                  'exchangeName': 'NMS',
                  'regularMarketPrice': 250.10,
                  'chartPreviousClose': 249.00,
                  'regularMarketTime': 1714291200,
                },
              },
            ],
            'error': null,
          },
        });
      final p = _makeProvider(adapter, FakeClock());

      final quote = await p.getQuote('AAPL');

      expect(quote.symbol, 'AAPL');
      expect(quote.currency, 'USD');
      expect(quote.price, Decimal.parse('250.1'));
      expect(quote.previousClose, Decimal.parse('249.0'));
      expect(quote.exchange, 'NMS');
    });

    test('attaches the shared Yahoo crumb session to chart requests', () async {
      final marketAdapter = CannedAdapter()
        ..enqueue('finance/chart/USDCNY', {
          'chart': {
            'result': [
              {
                'meta': {'currency': 'CNY', 'regularMarketPrice': 7.2},
              },
            ],
            'error': null,
          },
        });
      final sessionAdapter = CannedAdapter()
        ..enqueueRaw(
          'fc.yahoo.com',
          CannedResponse(
            '',
            status: 404,
            headers: {
              'set-cookie': ['A1=chart-session'],
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
        )
        ..enqueueRaw(
          'getcrumb',
          CannedResponse(
            'CHART_CRUMB',
            headers: const {
              Headers.contentTypeHeader: ['text/plain'],
            },
          ),
        );
      final sessionDio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = sessionAdapter;
      final provider = _makeProvider(
        marketAdapter,
        FakeClock(),
        session: YahooCrumbSession(dio: sessionDio),
      );

      await provider.getQuote('USDCNY=X');

      final request = marketAdapter.calls.single;
      expect(request.queryParameters['crumb'], 'CHART_CRUMB');
      expect(request.headers['Cookie'], 'A1=chart-session');
      expect(request.headers['User-Agent'], contains('Safari'));
    });

    test(
      'maps chart.error code containing "not found" to SymbolNotFound',
      () async {
        final adapter = CannedAdapter()
          ..enqueue('finance/chart/ZZZ', {
            'chart': {
              'result': null,
              'error': {
                'code': 'Not Found',
                'description': 'No data found, symbol may be delisted',
              },
            },
          });
        final p = _makeProvider(adapter, FakeClock());

        expect(
          () => p.getQuote('ZZZ'),
          throwsA(isA<SymbolNotFoundException>()),
        );
      },
    );
  });

  group('YFinanceProvider.getHistorical', () {
    test('emits one bar per non-null timestamp slot', () async {
      final adapter = CannedAdapter()
        ..enqueue('finance/chart/AAPL', {
          'chart': {
            'result': [
              {
                'meta': {'currency': 'USD'},
                'timestamp': [1714291200, 1714377600, 1714464000],
                'indicators': {
                  'quote': [
                    {
                      'open': [100.0, 101.0, null],
                      'high': [102.0, 103.0, null],
                      'low': [99.0, 100.0, null],
                      'close': [101.5, 102.5, null],
                      'volume': [10000, 20000, null],
                    },
                  ],
                  'adjclose': [
                    {
                      'adjclose': [101.5, 102.5, null],
                    },
                  ],
                },
              },
            ],
            'error': null,
          },
        });
      final p = _makeProvider(adapter, FakeClock());

      final bars = await p.getHistorical(
        'AAPL',
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 4, 30),
        interval: BarInterval.day,
      );

      expect(bars, hasLength(2));
      expect(bars.first.close, Decimal.parse('101.5'));
      expect(bars.first.adjustedClose, Decimal.parse('101.5'));
      expect(bars.last.volume, 20000);
    });
  });

  group('YFinanceProvider.searchSymbol', () {
    test('infers market from quoteType / exchange', () async {
      final adapter = CannedAdapter()
        ..enqueue('finance/search', {
          'quotes': [
            {
              'symbol': 'AAPL',
              'shortname': 'Apple Inc.',
              'exchange': 'NMS',
              'quoteType': 'EQUITY',
            },
            {
              'symbol': 'BTC-USD',
              'longname': 'Bitcoin USD',
              'exchange': 'CCC',
              'quoteType': 'CRYPTOCURRENCY',
            },
          ],
        });
      final p = _makeProvider(adapter, FakeClock());

      final results = await p.searchSymbol('apple');
      expect(results, hasLength(2));
      expect(results.first.market, AssetMarket.usStock);
      expect(results.last.market, AssetMarket.crypto);
    });
  });
}
