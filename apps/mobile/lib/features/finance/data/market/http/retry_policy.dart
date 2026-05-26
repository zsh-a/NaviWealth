import 'dart:math';

import 'package:naviwealth/features/finance/data/market/exceptions.dart';

/// Decay schedule for retried requests.
///
/// Default values (base 500ms, max 30s, factor 2, jitter ±20%) are conservative
/// and match the FIR-25 selection note: "indexed backoff base 1s, max 60s,
/// jitter ±20%". Halved here because the mobile client is much more
/// latency-sensitive than a backend cron.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.factor = 2.0,
    this.jitter = 0.2,
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double factor;
  final double jitter;

  /// Backoff for the next retry given how many attempts have already failed.
  /// `attempts` is 1-indexed (1 → first retry, 2 → second, ...).
  Duration delayFor(int attempts, {Random? rng}) {
    final r = rng ?? Random();
    final exp = baseDelay.inMilliseconds * pow(factor, attempts - 1);
    final capped = exp.clamp(0.0, maxDelay.inMilliseconds.toDouble());
    final j = capped * jitter * (2 * r.nextDouble() - 1);
    final ms = (capped + j).clamp(0.0, maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: ms.round());
  }

  /// Whether [error] should be retried.
  ///
  /// Network blips and 5xx are retried. 429 with explicit retry-after is
  /// retried only if the suggested wait is below [maxDelay]. SymbolNotFound
  /// and ProviderResponse errors are NOT retried — they signal that more
  /// attempts will fail the same way.
  bool isRetryable(Object error) {
    if (error is NetworkException) return true;
    if (error is ProviderUnavailableException) {
      final code = error.statusCode;
      if (code == null) return true;
      return code >= 500 && code < 600;
    }
    if (error is RateLimitException) {
      final after = error.retryAfter;
      if (after == null) return true;
      return after <= maxDelay;
    }
    return false;
  }
}
