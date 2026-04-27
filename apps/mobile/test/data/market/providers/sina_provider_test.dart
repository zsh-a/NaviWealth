import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/exceptions.dart';
import 'package:naviwealth/data/market/http/market_http_client.dart';
import 'package:naviwealth/data/market/http/rate_limiter.dart';
import 'package:naviwealth/data/market/http/retry_policy.dart';
import 'package:naviwealth/data/market/providers/sina_provider.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';

import '../canned_adapter.dart';
import '../fake_clock.dart';

SinaProvider _make(CannedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return SinaProvider(
    http: MarketHttpClient(
      providerName: 'sina',
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
  group('SinaProvider', () {
    test('parses a typical hq response into a Quote', () async {
      // 32 fields, ASCII-safe; Chinese name field (#0) is bytes we replace
      // with `STOCK` to keep this test pure-ASCII.
      const fields = [
        'STOCK', // 0 name
        '1500.00', // 1 open
        '1499.00', // 2 prev close
        '1510.00', // 3 current price
        '1520.00', // 4 day high
        '1490.00', // 5 day low
        '0', // 6
        '0', // 7
        '12345', // 8 volume
        ...['0', '0', '0', '0', '0', '0', '0', '0'], // 9..16
        ...['0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0'],
        // 17..29
        '2026-04-28', // 30 date
        '14:30:00', // 31 time
      ];
      final payload = 'var hq_str_sh600519="${fields.join(',')}";';
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'hq.sinajs.cn',
          CannedResponse(
            Uint8List.fromList(payload.codeUnits),
            headers: const {
              'content-type': ['application/javascript'],
            },
          ),
        );

      final quote = await _make(adapter).getQuote('sh600519');

      expect(quote.symbol, 'SH600519');
      expect(quote.currency, 'CNY');
      expect(quote.price, Decimal.parse('1510.00'));
      expect(quote.previousClose, Decimal.parse('1499.00'));
      expect(quote.exchange, 'SSE');
      expect(quote.volume, 12345);
    });

    test('treats empty payload as SymbolNotFound', () async {
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'hq.sinajs.cn',
          CannedResponse(
            Uint8List.fromList('var hq_str_sh000000="";'.codeUnits),
          ),
        );
      expect(
        () => _make(adapter).getQuote('sh000000'),
        throwsA(isA<SymbolNotFoundException>()),
      );
    });

    test('historical / search are unsupported', () async {
      final p = _make(CannedAdapter());
      expect(
        () => p.getHistorical(
          'sh600519',
          from: DateTime.utc(2026, 1, 1),
          to: DateTime.utc(2026, 4, 28),
          interval: BarInterval.day,
        ),
        throwsUnsupportedError,
      );
      expect(() => p.searchSymbol('apple'), throwsUnsupportedError);
    });

    test('routes 6-digit code to sh / sz prefix automatically', () async {
      final fields = <String>[
        'X',
        '10',
        '11',
        '12',
        '13',
        '9',
        '0',
        '0',
        '100',
        ...List.filled(21, '0'),
        '2026-04-28',
        '14:30:00',
      ];
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'hq.sinajs.cn',
          CannedResponse(
            Uint8List.fromList(
              'var hq_str_sh600519="${fields.join(',')}";'.codeUnits,
            ),
          ),
        );

      final quote = await _make(adapter).getQuote('600519');
      expect(quote.symbol, 'SH600519');
    });
  });
}
