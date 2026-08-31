import 'dart:async';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

/// Provider-neutral fetch, routing, single-flight, and TTL cache for public
/// corporate-action reference data.
///
/// This service never writes FinanceOS business rows. Consumers decide whether
/// actions are timeline-only, paper-simulation candidates, or user-confirmed
/// real corporate actions.
class CorporateActionsService {
  CorporateActionsService({
    required List<CorporateActionProvider> providers,
    required AppLogger logger,
    Duration successTtl = const Duration(hours: 12),
    Duration errorTtl = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _providers = List<CorporateActionProvider>.unmodifiable(providers),
       _logger = logger,
       _successTtl = successTtl,
       _errorTtl = errorTtl,
       _now = now ?? (() => DateTime.now().toUtc());

  final List<CorporateActionProvider> _providers;
  final AppLogger _logger;
  final Duration _successTtl;
  final Duration _errorTtl;
  final DateTime Function() _now;

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  final Map<String, Future<CorporateActionFetchResult>> _inflight =
      <String, Future<CorporateActionFetchResult>>{};

  Future<List<MarketCorporateAction>> getForSymbol(
    String symbol, {
    AssetMarket? market,
  }) async {
    final result = await fetchForSymbol(symbol, market: market);
    return switch (result.disposition) {
      CorporateActionFetchDisposition.success ||
      CorporateActionFetchDisposition.authoritativeEmpty ||
      CorporateActionFetchDisposition.partial => result.actions,
      CorporateActionFetchDisposition.unsupported => const [],
      CorporateActionFetchDisposition.failure =>
        throw result.error ??
            NoMarketDataAvailableException(
              'Corporate actions unavailable for $symbol',
            ),
    };
  }

  Future<CorporateActionFetchResult> fetchForSymbol(
    String symbol, {
    AssetMarket? market,
  }) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final resolvedMarket = market ?? inferAssetMarket(normalizedSymbol);
    if (normalizedSymbol.isEmpty) {
      return Future.value(
        CorporateActionFetchResult(
          provider: 'none',
          disposition: CorporateActionFetchDisposition.authoritativeEmpty,
          actions: const [],
          fetchedAt: _now(),
        ),
      );
    }

    final key = '${resolvedMarket.wire}:$normalizedSymbol';
    final cached = _cache[key];
    if (cached != null && !cached.expired(_now())) {
      return Future.value(cached.result);
    }
    final running = _inflight[key];
    if (running != null) return running;

    final future = _fetch(normalizedSymbol, resolvedMarket);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  void invalidate(String symbol, {AssetMarket? market}) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final resolvedMarket = market ?? inferAssetMarket(normalizedSymbol);
    _cache.remove('${resolvedMarket.wire}:$normalizedSymbol');
  }

  Future<CorporateActionFetchResult> _fetch(
    String symbol,
    AssetMarket market,
  ) async {
    final providers = _providers
        .where(
          (provider) => provider.capabilities.supportedMarkets.contains(market),
        )
        .toList(growable: false);
    if (providers.isEmpty) {
      final result = CorporateActionFetchResult(
        provider: 'none',
        disposition: CorporateActionFetchDisposition.unsupported,
        actions: const [],
        fetchedAt: _now(),
        warning: 'No corporate-action provider supports ${market.wire}.',
      );
      _store(symbol, market, result);
      return result;
    }

    final now = _now();
    final request = CorporateActionFetchRequest(
      symbol: symbol,
      market: market,
      from: now.subtract(const Duration(days: 30)),
      to: now.add(const Duration(days: 365)),
    );
    final failures = <Object>[];
    var unsupportedCount = 0;
    for (final provider in providers) {
      try {
        final result = await provider.fetch(request);
        if (result.hasUsableData) {
          _store(symbol, market, result);
          return result;
        }
        if (result.disposition == CorporateActionFetchDisposition.unsupported) {
          unsupportedCount++;
          continue;
        }
        if (result.disposition == CorporateActionFetchDisposition.failure) {
          failures.add(
            result.error ??
                ProviderUnavailableException(
                  '${provider.name} returned a failed result',
                  provider: provider.name,
                ),
          );
        }
      } catch (error, stackTrace) {
        failures.add(error);
        _logger.w(
          'corporate_actions_service: ${provider.name} $symbol fetch failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (unsupportedCount == providers.length) {
      final result = CorporateActionFetchResult(
        provider: providers.map((provider) => provider.name).join(','),
        disposition: CorporateActionFetchDisposition.unsupported,
        actions: const [],
        fetchedAt: _now(),
        warning: 'Corporate actions are unavailable on this platform.',
      );
      _store(symbol, market, result);
      return result;
    }

    final error = NoMarketDataAvailableException(
      'Every corporate-action provider failed for $symbol',
      cause: failures,
    );
    final result = CorporateActionFetchResult(
      provider: providers.map((provider) => provider.name).join(','),
      disposition: CorporateActionFetchDisposition.failure,
      actions: const [],
      fetchedAt: _now(),
      error: error,
    );
    _store(symbol, market, result);
    return result;
  }

  void _store(
    String symbol,
    AssetMarket market,
    CorporateActionFetchResult result,
  ) {
    final ttl = result.disposition == CorporateActionFetchDisposition.failure
        ? _errorTtl
        : _successTtl;
    _cache['${market.wire}:$symbol'] = _CacheEntry(
      result: result,
      fetchedAt: _now(),
      ttl: ttl,
    );
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.result,
    required this.fetchedAt,
    required this.ttl,
  });

  final CorporateActionFetchResult result;
  final DateTime fetchedAt;
  final Duration ttl;

  bool expired(DateTime now) => now.difference(fetchedAt) >= ttl;
}
