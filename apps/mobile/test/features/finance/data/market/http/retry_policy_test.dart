import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    const policy = RetryPolicy();

    test('retries network and 5xx errors', () {
      expect(policy.isRetryable(const NetworkException('boom')), isTrue);
      expect(
        policy.isRetryable(
          const ProviderUnavailableException('500', statusCode: 503),
        ),
        isTrue,
      );
    });

    test('does not retry 404 / 4xx surfaced as not-found or non-retriable', () {
      expect(
        policy.isRetryable(const SymbolNotFoundException('nope')),
        isFalse,
      );
      expect(
        policy.isRetryable(
          const ProviderUnavailableException('400', statusCode: 400),
        ),
        isFalse,
      );
    });

    test('rate limit retried only when retry-after fits inside maxDelay', () {
      expect(policy.isRetryable(const RateLimitException('slow down')), isTrue);
      expect(
        policy.isRetryable(
          const RateLimitException(
            'slow down',
            retryAfter: Duration(seconds: 5),
          ),
        ),
        isTrue,
      );
      expect(
        policy.isRetryable(
          const RateLimitException(
            'slow down',
            retryAfter: Duration(minutes: 5),
          ),
        ),
        isFalse,
      );
    });

    test('delayFor stays inside maxDelay with jitter applied', () {
      const tight = RetryPolicy(
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 1),
        factor: 4,
        jitter: 0.5,
      );
      final rng = Random(42);
      for (var attempt = 1; attempt <= 8; attempt++) {
        final d = tight.delayFor(attempt, rng: rng);
        expect(d, lessThanOrEqualTo(tight.maxDelay));
      }
    });
  });
}
