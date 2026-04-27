import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/providers.dart';
import '../../domain/services/market_data_service.dart';
import 'cache/cache_policy.dart';
import 'cache/quote_cache.dart';
import 'composite_market_data_service.dart';
import 'http/clock.dart';
import 'http/market_http_client.dart';
import 'http/rate_limiter.dart';
import 'http/retry_policy.dart';
import 'metrics/market_metrics.dart';
import 'providers/coingecko_provider.dart';
import 'providers/market_provider.dart';
import 'providers/sina_provider.dart';
import 'providers/yfinance_provider.dart';

/// Per-app singleton clock — overrideable in tests.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Single [MarketMetrics] sink shared across providers and the composite
/// service so cache + HTTP counters aggregate.
final marketMetricsProvider = Provider<MarketMetrics>((ref) {
  final m = MarketMetrics();
  ref.onDispose(m.dispose);
  return m;
});

/// Cache policy override hook — features (e.g. background refresh task)
/// can override to use a more aggressive policy.
final marketCachePolicyProvider = Provider<MarketCachePolicy>(
  (ref) => const MarketCachePolicy(),
);

final marketCacheProvider = FutureProvider<MarketCache>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return MarketCache(
    db: db,
    clock: ref.watch(clockProvider),
    policy: ref.watch(marketCachePolicyProvider),
  );
});

final yfinanceProviderProvider = Provider<MarketProvider>((ref) {
  final http = MarketHttpClient(
    providerName: 'yfinance',
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
    retryPolicy: const RetryPolicy(),
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return YFinanceProvider(http: http);
});

final coingeckoProviderProvider = Provider<MarketProvider>((ref) {
  final http = MarketHttpClient(
    providerName: 'coingecko',
    // CoinGecko Demo API free tier ≈ 30 calls / minute.
    rateLimiter: RateLimiter(
      maxRequests: 30,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return CoinGeckoProvider(http: http);
});

final sinaProviderProvider = Provider<MarketProvider>((ref) {
  final http = MarketHttpClient(
    providerName: 'sina',
    // Sina hq has no published quota; rate-limit conservatively.
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return SinaProvider(http: http);
});

/// Routing chain. Order matters — the composite service walks the list and
/// the first provider that supports the requested market is tried first.
final marketProviderChainProvider = Provider<List<MarketProvider>>((ref) {
  return [
    ref.watch(sinaProviderProvider),
    ref.watch(yfinanceProviderProvider),
    ref.watch(coingeckoProviderProvider),
  ];
});

final marketDataServiceProvider = FutureProvider<MarketDataService>((
  ref,
) async {
  final cache = await ref.watch(marketCacheProvider.future);
  return CompositeMarketDataService(
    providers: ref.watch(marketProviderChainProvider),
    cache: cache,
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
});
