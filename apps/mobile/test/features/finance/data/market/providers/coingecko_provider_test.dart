import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/providers/coingecko_provider.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';

import '../canned_adapter.dart';
import '../fake_clock.dart';

CoinGeckoProvider _make(CannedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return CoinGeckoProvider(
    http: MarketHttpClient(
      providerName: 'coingecko',
      rateLimiter: RateLimiter(
        maxRequests: 60,
        window: const Duration(minutes: 1),
        clock: FakeClock(),
      ),
      dio: dio,
      retryPolicy: const RetryPolicy(maxAttempts: 1),
      clock: FakeClock(),
    ),
  );
}

void main() {
  group('CoinGeckoProvider', () {
    test('getQuote with id-shaped input hits simple/price directly', () async {
      final adapter = CannedAdapter()
        ..enqueue('simple/price', {
          'bitcoin': {'usd': 65000.5, 'last_updated_at': 1714291200},
        });

      final p = _make(adapter);
      final quote = await p.getQuote('bitcoin');

      expect(quote.price, Decimal.parse('65000.5'));
      expect(quote.currency, 'USD');
      expect(adapter.calls, hasLength(1));
    });

    test(
      'getQuote with ticker-shaped input resolves via search first',
      () async {
        final adapter = CannedAdapter()
          ..enqueue('search', {
            'coins': [
              {'id': 'bitcoin', 'symbol': 'btc', 'name': 'Bitcoin'},
            ],
          })
          ..enqueue('simple/price', {
            'bitcoin': {'usd': 65000.5, 'last_updated_at': 1714291200},
          });

        final p = _make(adapter);
        final quote = await p.getQuote('BTC');

        expect(quote.price, Decimal.parse('65000.5'));
        expect(adapter.calls, hasLength(2));
        expect(adapter.calls.first.uri.path, contains('search'));
      },
    );

    test('throws SymbolNotFound when search yields nothing', () async {
      final adapter = CannedAdapter()
        ..enqueue('search', {'coins': <Map<String, dynamic>>[]});
      final p = _make(adapter);
      expect(() => p.getQuote('ZZZ'), throwsA(isA<SymbolNotFoundException>()));
    });

    test('getHistorical collapses prices to one bar per day', () async {
      final adapter = CannedAdapter()
        ..enqueue('market_chart/range', {
          'prices': [
            [1714291200000, 60000.0],
            [1714377600000, 61000.0],
          ],
          'total_volumes': [
            [1714291200000, 1000.0],
            [1714377600000, 2000.0],
          ],
        });

      final p = _make(adapter);
      final bars = await p.getHistorical(
        'bitcoin',
        from: DateTime.utc(2026, 4, 28),
        to: DateTime.utc(2026, 4, 30),
        interval: BarInterval.day,
      );

      expect(bars, hasLength(2));
      expect(bars.first.close, Decimal.parse('60000.0'));
      expect(bars.last.volume, 2000);
    });

    test(
      'searchSymbol tags results as crypto and surfaces id in exchange',
      () async {
        final adapter = CannedAdapter()
          ..enqueue('search', {
            'coins': [
              {'id': 'ethereum', 'symbol': 'eth', 'name': 'Ethereum'},
            ],
          });

        final p = _make(adapter);
        final hits = await p.searchSymbol('eth');

        expect(hits, hasLength(1));
        expect(hits.single.market, AssetMarket.crypto);
        expect(hits.single.exchange, 'ethereum');
      },
    );
  });
}
