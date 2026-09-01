import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/providers/yfinance_corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';

import '../canned_adapter.dart';

({YFinanceCorporateActionProvider provider, CannedAdapter adapter}) _build() {
  final adapter = CannedAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  final http = MarketHttpClient(
    providerName: 'yfinance',
    rateLimiter: RateLimiter(
      maxRequests: 100,
      window: const Duration(minutes: 1),
      clock: const SystemClock(),
    ),
    dio: dio,
    retryPolicy: const RetryPolicy(maxAttempts: 1),
    clock: const SystemClock(),
  );
  return (
    provider: YFinanceCorporateActionProvider(
      http: http,
      now: () => DateTime.utc(2026, 8, 20),
    ),
    adapter: adapter,
  );
}

CorporateActionFetchRequest _request() => CorporateActionFetchRequest(
  symbol: 'AAPL',
  market: AssetMarket.usStock,
  from: DateTime.utc(2024),
  to: DateTime.utc(2027),
);

Map<String, Object?> _body(Object? events) => <String, Object?>{
  'chart': <String, Object?>{
    'result': <Object?>[
      <String, Object?>{
        'meta': <String, Object?>{'currency': 'USD'},
        'events': events,
      },
    ],
    'error': null,
  },
};

void main() {
  group('YFinanceCorporateActionProvider', () {
    test('returns partial when valid and malformed rows are mixed', () async {
      final harness = _build();
      harness.adapter.enqueue(
        '/AAPL',
        _body(<String, Object?>{
          'dividends': <String, Object?>{
            'good': <String, Object?>{'date': 1_714_521_600, 'amount': 0.22},
            'bad': <String, Object?>{'date': 1_714_521_600},
          },
        }),
      );

      final result = await harness.provider.fetch(_request());
      expect(result.disposition, CorporateActionFetchDisposition.partial);
      expect(result.actions, hasLength(1));
      expect(result.warning, contains('1 malformed'));
    });

    test('rejects malformed envelopes instead of reporting empty', () async {
      final harness = _build();
      harness.adapter.enqueue('/AAPL', <String, Object?>{'chart': 'broken'});

      await expectLater(
        harness.provider.fetch(_request()),
        throwsA(isA<ProviderResponseException>()),
      );
    });

    test('rejects all-malformed event blocks', () async {
      final harness = _build();
      harness.adapter.enqueue(
        '/AAPL',
        _body(<String, Object?>{
          'dividends': <String, Object?>{
            'bad': <String, Object?>{'date': 1_714_521_600},
          },
        }),
      );

      await expectLater(
        harness.provider.fetch(_request()),
        throwsA(isA<ProviderResponseException>()),
      );
    });
  });
}
