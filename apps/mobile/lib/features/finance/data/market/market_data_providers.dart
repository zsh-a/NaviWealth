import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/services/price_resolver.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

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
import 'providers/options/options_chain_provider.dart';
import 'providers/options/yfinance_options_provider.dart';
import 'providers/sina_provider.dart';
import 'providers/yahoo_crumb_session.dart';
import 'providers/yfinance_provider.dart';
import 'resolver/layered_price_resolver.dart';

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

TalkerDioLogger _marketDioLogger(Ref ref) => TalkerDioLogger(
  talker: ref.read(talkerProvider),
  settings: const TalkerDioLoggerSettings(printResponseData: false),
);

/// Shared cookie + crumb session for Yahoo Finance. Yahoo started
/// gating `query1`/`query2` endpoints behind a per-session crumb token
/// in 2023; without it the API returns `401 Invalid Crumb`. The session
/// caches the handshake for the app lifetime and refreshes on 401.
final yahooCrumbSessionProvider = Provider<YahooCrumbSession>((ref) {
  return YahooCrumbSession();
});

/// Options chain provider. Reuses the same [MarketHttpClient]/[RateLimiter]
/// as [yfinanceProviderProvider] so quote + chain calls share one budget
/// (`docs/options-income.md` §4.1). Built lazily because the Income Planner
/// is mobile-only; pure-quote consumers don't pay the construction cost.
final yfinanceOptionsProviderProvider = Provider<OptionsChainProvider>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_marketDioLogger(ref));
  final http = MarketHttpClient(
    providerName: 'yfinance_options',
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: dio,
    retryPolicy: const RetryPolicy(),
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return YFinanceOptionsProvider(
    http: http,
    session: ref.watch(yahooCrumbSessionProvider),
    clock: ref.watch(clockProvider),
  );
});

final yfinanceProviderProvider = Provider<MarketProvider>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_marketDioLogger(ref));
  final http = MarketHttpClient(
    providerName: 'yfinance',
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: dio,
    retryPolicy: const RetryPolicy(),
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return YFinanceProvider(http: http);
});

final coingeckoProviderProvider = Provider<MarketProvider>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_marketDioLogger(ref));
  final http = MarketHttpClient(
    providerName: 'coingecko',
    // CoinGecko Demo API free tier ≈ 30 calls / minute.
    rateLimiter: RateLimiter(
      maxRequests: 30,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: dio,
    clock: ref.watch(clockProvider),
    metrics: ref.watch(marketMetricsProvider),
  );
  return CoinGeckoProvider(http: http);
});

final sinaProviderProvider = Provider<MarketProvider>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_marketDioLogger(ref));
  final http = MarketHttpClient(
    providerName: 'sina',
    // Sina hq has no published quota; rate-limit conservatively.
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: ref.watch(clockProvider),
    ),
    dio: dio,
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

/// Default tier-window policy for [LayeredPriceResolver]. Overrideable by
/// tests (shrink windows to seconds) or settings (future Phase E toggle).
final priceResolverPolicyProvider = Provider<PriceResolverPolicy>(
  (ref) => const PriceResolverPolicy(),
);

/// The unified valuation entry point. Composes the live market service +
/// synced `prices` ledger + the layered tier policy. Features that need
/// "price for asset" must consume this, not [marketDataServiceProvider]
/// directly.
final priceResolverProvider = FutureProvider<PriceResolver>((ref) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final prices = await ref.watch(priceRepositoryProvider.future);
  return LayeredPriceResolver(
    market: market,
    prices: prices,
    clock: ref.watch(clockProvider),
    policy: ref.watch(priceResolverPolicyProvider),
  );
});
