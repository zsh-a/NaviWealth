import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/metrics/market_metrics.dart';
import 'clock.dart';
import 'rate_limiter.dart';
import 'retry_policy.dart';

/// Thin wrapper around [Dio] that:
///   - applies a per-provider [RateLimiter] before each request,
///   - retries on transient errors with [RetryPolicy] backoff,
///   - normalises Dio errors into the typed market-data exception hierarchy,
///   - emits per-attempt metrics (success / error / fallback).
///
/// Each provider holds its own instance so rate-limit state is isolated. Dio
/// itself is configurable from the outside for testing — pass a Dio with a
/// [DioAdapter] to inject canned responses.
class MarketHttpClient {
  MarketHttpClient({
    required this.providerName,
    required this.rateLimiter,
    Dio? dio,
    this.retryPolicy = const RetryPolicy(),
    Clock clock = const SystemClock(),
    Random? random,
    MarketMetrics? metrics,
  }) : _dio = dio ?? Dio(),
       _clock = clock,
       _random = random ?? Random(),
       _metrics = metrics;

  final String providerName;
  final RateLimiter rateLimiter;
  final RetryPolicy retryPolicy;
  final Dio _dio;
  final Clock _clock;
  final Random _random;
  final MarketMetrics? _metrics;

  /// Issue [request], honouring the rate limiter and retry policy.
  ///
  /// Throws a [MarketDataException] subclass on failure. Caller decides
  /// whether to fall back to another provider.
  Future<Response<T>> send<T>(
    RequestOptions request, {
    String endpoint = 'unknown',
  }) async {
    Object? lastError;
    final maxAttempts = retryPolicy.maxAttempts;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      await rateLimiter.acquire();
      final stopwatch = Stopwatch()..start();
      try {
        final response = await _dio.fetch<T>(request);
        stopwatch.stop();
        _metrics?.recordRequest(
          provider: providerName,
          endpoint: endpoint,
          ok: true,
          latency: stopwatch.elapsed,
        );
        return response;
      } catch (err, st) {
        stopwatch.stop();
        final mapped = _mapError(err);
        _metrics?.recordRequest(
          provider: providerName,
          endpoint: endpoint,
          ok: false,
          latency: stopwatch.elapsed,
          errorType: mapped.runtimeType.toString(),
        );
        lastError = mapped;
        if (attempt >= maxAttempts || !retryPolicy.isRetryable(mapped)) {
          AppLogger.instance.w(
            'market.http $providerName.$endpoint failed after '
            '$attempt/$maxAttempts: $mapped',
            error: err,
            stackTrace: st,
          );
          throw mapped;
        }
        final delay = _delayFor(attempt, mapped);
        AppLogger.instance.d(
          'market.http $providerName.$endpoint attempt $attempt failed '
          '(${mapped.runtimeType}); backing off ${delay.inMilliseconds}ms',
        );
        await _clock.sleep(delay);
      }
    }
    // Unreachable: loop either returns or throws. Keeps the analyzer happy.
    throw lastError ??
        ProviderUnavailableException(
          'Exhausted retries with no error',
          provider: providerName,
        );
  }

  Duration _delayFor(int attempt, MarketDataException error) {
    if (error is RateLimitException && error.retryAfter != null) {
      return error.retryAfter!;
    }
    return retryPolicy.delayFor(attempt, rng: _random);
  }

  MarketDataException _mapError(Object err) {
    if (err is MarketDataException) return err;
    if (err is DioException) {
      final response = err.response;
      switch (err.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return NetworkException(
            err.message ?? 'connection error',
            provider: providerName,
            cause: err,
          );
        case DioExceptionType.cancel:
          return NetworkException(
            'request cancelled',
            provider: providerName,
            cause: err,
          );
        case DioExceptionType.badCertificate:
          return NetworkException(
            'bad certificate',
            provider: providerName,
            cause: err,
          );
        case DioExceptionType.unknown:
          return NetworkException(
            err.message ?? 'unknown network error',
            provider: providerName,
            cause: err,
          );
        case DioExceptionType.badResponse:
          break;
      }
      if (response == null) {
        return NetworkException(
          'no response',
          provider: providerName,
          cause: err,
        );
      }
      final status = response.statusCode ?? 0;
      if (status == 429) {
        return RateLimitException(
          'rate limited',
          provider: providerName,
          cause: err,
          retryAfter: _parseRetryAfter(response.headers.value('retry-after')),
        );
      }
      if (status == 404) {
        return SymbolNotFoundException(
          'not found',
          provider: providerName,
          cause: err,
        );
      }
      return ProviderUnavailableException(
        'http $status',
        provider: providerName,
        statusCode: status,
        cause: err,
      );
    }
    return ProviderResponseException(
      err.toString(),
      provider: providerName,
      cause: err,
    );
  }

  Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final secs = int.tryParse(header.trim());
    if (secs != null) return Duration(seconds: secs);
    final at = DateTime.tryParse(header);
    if (at != null) {
      final diff = at.toUtc().difference(_clock.now());
      return diff.isNegative ? Duration.zero : diff;
    }
    return null;
  }
}
