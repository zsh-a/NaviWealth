import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart'
    as market_clock;
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/services/corporate_actions_service.dart';
import '../domain/reporting/event_timeline.dart';

/// Underlying corporate-actions fetcher. One instance per app — the
/// service owns an in-memory TTL cache, so a singleton avoids fan-out
/// fetches when multiple watchers ask for the same symbol.
///
/// Tests override [corporateActionEventsProvider] directly (single seam)
/// so they don't need a fake service.
final corporateActionsServiceProvider = Provider<CorporateActionsService>((
  ref,
) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  final http = MarketHttpClient(
    providerName: 'yfinance',
    rateLimiter: RateLimiter(
      maxRequests: 60,
      window: const Duration(minutes: 1),
      clock: const market_clock.SystemClock(),
    ),
    dio: dio,
    clock: const market_clock.SystemClock(),
    metrics: ref.watch(marketMetricsProvider),
  );
  return CorporateActionsService(http: http, logger: ref.watch(loggerProvider));
});

/// Per-symbol corporate-action events for the Finance investment timeline.
/// UI surfaces (holding detail "事件" tab) subscribe to this; the
/// [CorporateActionsService] supplies events via the yfinance chart
/// endpoint with a 12-hour TTL cache.
///
/// Returns `[]` while loading and on any network error — the service
/// caches errors briefly to avoid hammering Yahoo on transient outages.
///
/// Tests override this provider directly to inject canned events.
final corporateActionEventsProvider = FutureProvider.autoDispose
    .family<List<CorporateActionEvent>, String>((ref, symbol) {
      final service = ref.watch(corporateActionsServiceProvider);
      return service.getForSymbol(symbol);
    });

/// Filtered timeline projection for [symbol] over the next 90 days.
/// Centralises the `buildEventTimeline` call so callers don't thread
/// the symbol set / window themselves.
///
/// Returns an [AsyncValue]: the upstream fetcher is async, so this
/// provider mirrors the same lifecycle (loading → data → error). The
/// widget consumer renders loading, empty, and retryable error states
/// separately so "nothing scheduled" is never confused with a failed
/// corporate-action fetch.
final upcomingEventsForSymbolProvider = Provider.autoDispose
    .family<AsyncValue<List<CorporateActionEvent>>, String>((ref, symbol) {
      final eventsAsync = ref.watch(corporateActionEventsProvider(symbol));
      return eventsAsync.whenData(
        (raw) =>
            buildEventTimeline(events: raw, watchedSymbols: <String>{symbol}),
      );
    });
