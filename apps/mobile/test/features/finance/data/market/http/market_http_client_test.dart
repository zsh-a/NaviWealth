import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/metrics/market_metrics.dart';

import '../canned_adapter.dart';
import '../fake_clock.dart';

void main() {
  group('MarketHttpClient', () {
    test('retries 5xx then succeeds on the second attempt', () async {
      final adapter = CannedAdapter()
        ..enqueue('/probe', 'oops', status: 503)
        ..enqueue('/probe', {'ok': true});
      final dio = Dio()..httpClientAdapter = adapter;
      final clock = FakeClock();
      final client = MarketHttpClient(
        providerName: 'fake',
        rateLimiter: RateLimiter(
          maxRequests: 60,
          window: const Duration(minutes: 1),
          clock: clock,
        ),
        dio: dio,
        retryPolicy: const RetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 10),
        ),
        clock: clock,
        random: Random(0),
      );

      final response = await client.send<Map<String, dynamic>>(
        RequestOptions(
          path: 'https://api.example.com/probe',
          method: 'GET',
          responseType: ResponseType.json,
        ),
        endpoint: 'probe',
      );

      expect(response.data, {'ok': true});
      expect(adapter.calls, hasLength(2));
    });

    test('does not retry SymbolNotFound', () async {
      final adapter = CannedAdapter()..enqueue('/probe', 'gone', status: 404);
      final dio = Dio()..httpClientAdapter = adapter;
      final clock = FakeClock();
      final client = MarketHttpClient(
        providerName: 'fake',
        rateLimiter: RateLimiter(
          maxRequests: 60,
          window: const Duration(minutes: 1),
          clock: clock,
        ),
        dio: dio,
        retryPolicy: const RetryPolicy(maxAttempts: 5),
        clock: clock,
      );

      await expectLater(
        () => client.send<dynamic>(
          RequestOptions(path: 'https://api.example.com/probe', method: 'GET'),
        ),
        throwsA(isA<SymbolNotFoundException>()),
      );
      // Single attempt only — 404 short-circuits retry.
      expect(adapter.calls, hasLength(1));
    });

    test('records request metrics on success and failure', () async {
      final adapter = CannedAdapter()
        ..enqueue('/p', 'down', status: 500)
        ..enqueue('/p', 'down', status: 500)
        ..enqueue('/p', {'ok': 1});
      final dio = Dio()..httpClientAdapter = adapter;
      final clock = FakeClock();
      final metrics = MarketMetrics();
      addTearDown(metrics.dispose);
      final client = MarketHttpClient(
        providerName: 'fake',
        rateLimiter: RateLimiter(
          maxRequests: 60,
          window: const Duration(minutes: 1),
          clock: clock,
        ),
        dio: dio,
        retryPolicy: const RetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 5),
        ),
        clock: clock,
        metrics: metrics,
        random: Random(0),
      );

      await client.send<dynamic>(
        RequestOptions(path: 'https://api.example.com/p', method: 'GET'),
        endpoint: 'p',
      );

      final c = metrics.snapshot().requests['fake|p']!;
      expect(c.total, 3);
      expect(c.ok, 1);
      expect(c.errors, 2);
    });
  });
}
