import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/data/market/cache/corporate_action_candidate_cache.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart'
    as market_clock;
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/providers/eastmoney_corporate_action_provider.dart';
import 'package:naviwealth/features/finance/data/market/providers/yfinance_corporate_action_provider.dart';
import 'package:naviwealth/features/finance/data/market/services/corporate_actions_service.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../domain/reporting/event_timeline.dart';

/// Unified public corporate-action fetcher. Market routing remains inside the
/// service so timelines, paper simulations, and future confirmation flows can
/// reuse the same provider contract.
final corporateActionsServiceProvider = FutureProvider<CorporateActionsService>(
  (ref) async {
    MarketHttpClient http(
      String providerName, {
      required int requestsPerMinute,
    }) {
      return MarketHttpClient(
        providerName: providerName,
        rateLimiter: RateLimiter(
          maxRequests: requestsPerMinute,
          window: const Duration(minutes: 1),
          clock: const market_clock.SystemClock(),
        ),
        dio: Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        ),
        clock: const market_clock.SystemClock(),
        metrics: ref.watch(marketMetricsProvider),
      );
    }

    final db = await ref.watch(appDatabaseProvider.future);
    return CorporateActionsService(
      providers: [
        EastmoneyCorporateActionProvider(
          http: http('eastmoney', requestsPerMinute: 20),
          available: !kIsWeb,
        ),
        YFinanceCorporateActionProvider(
          http: http('yfinance', requestsPerMinute: 60),
        ),
      ],
      logger: ref.watch(loggerProvider),
      cache: CorporateActionCandidateCache(db: db),
    );
  },
);

/// Per-symbol timeline projection of provider-neutral corporate actions.
/// Provider failures remain errors; unsupported markets degrade to an empty
/// timeline without attempting an unrelated provider.
final corporateActionEventsProvider = FutureProvider.autoDispose
    .family<List<CorporateActionEvent>, String>((ref, symbol) async {
      final service = await ref.watch(corporateActionsServiceProvider.future);
      final actions = await service.getForSymbol(symbol);
      return _timelineEvents(actions);
    });

final upcomingEventsForSymbolProvider = Provider.autoDispose
    .family<AsyncValue<List<CorporateActionEvent>>, String>((ref, symbol) {
      final eventsAsync = ref.watch(corporateActionEventsProvider(symbol));
      return eventsAsync.whenData(
        (raw) =>
            buildEventTimeline(events: raw, watchedSymbols: <String>{symbol}),
      );
    });

List<CorporateActionEvent> _timelineEvents(
  Iterable<MarketCorporateAction> actions,
) {
  final events = <CorporateActionEvent>[];
  for (final action in actions) {
    if (action.status == MarketCorporateActionStatus.cancelled) continue;
    final date = action.timelineDate;
    if (date == null) continue;
    if (action.kind == MarketCorporateActionKind.distribution &&
        action.hasCashDistribution &&
        action.currency != null) {
      events.add(
        CorporateActionEvent(
          id: '${action.id}:cash',
          symbol: action.symbol,
          kind: CorporateActionKind.cashDividend,
          scheduledFor: date,
          cashAmount: action.cashPerShare!,
          currency: action.currency!,
          note: action.note,
        ),
      );
    }
    if (action.kind == MarketCorporateActionKind.split && action.hasSplit) {
      events.add(
        CorporateActionEvent(
          id: '${action.id}:split',
          symbol: action.symbol,
          kind: CorporateActionKind.split,
          scheduledFor: date,
          cashAmount: Decimal.zero,
          currency: action.currency ?? '',
          ratio: SplitRatio(action.splitNumerator!, action.splitDenominator!),
          note: action.note,
        ),
      );
    }
  }
  return List<CorporateActionEvent>.unmodifiable(events);
}
