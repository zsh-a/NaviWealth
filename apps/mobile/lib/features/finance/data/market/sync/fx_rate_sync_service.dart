import 'package:decimal/decimal.dart';

import '../../../../../core/logging/app_logger.dart';
import '../../../domain/fx/fx_rate.dart';
import '../../../market/domain/asset_market.dart';
import '../../../market/domain/historical_bar.dart';
import '../../../market/domain/market_data_service.dart';
import '../../repositories/fx_rate_repository.dart';
import '../exceptions.dart';
import '../http/clock.dart';

/// Outcome of one FX sync pass.
///
/// FX is derived market data, so one unavailable pair should not discard
/// rates that were fetched successfully for the other pairs. The old integer
/// return value made that partial failure invisible to callers; this report
/// keeps the compatibility wrapper below while giving UI and coordinator
/// callers enough information to explain what happened.
class FxRateSyncResult {
  FxRateSyncResult({
    required Set<String> requestedPairs,
    required Set<String> syncedPairs,
    required Map<String, String> failures,
  }) : requestedPairs = Set.unmodifiable(requestedPairs),
       syncedPairs = Set.unmodifiable(syncedPairs),
       failures = Map.unmodifiable(failures);

  final Set<String> requestedPairs;
  final Set<String> syncedPairs;
  final Map<String, String> failures;

  int get syncedCount => syncedPairs.length;
  int get failedCount => failures.length;
  bool get hasFailures => failures.isNotEmpty;

  String? get failureSummary {
    if (failures.isEmpty) return null;
    final summary = failures.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(' · ');
    // Keep a provider response from turning a small toast into a full-screen
    // diagnostic dump. The complete exception remains in the application log.
    return summary.length <= 280 ? summary : '${summary.substring(0, 279)}…';
  }
}

class _FxFetchAttempt {
  const _FxFetchAttempt.success() : succeeded = true, error = null;
  const _FxFetchAttempt.failure(Object value)
    : succeeded = false,
      error = value;

  final bool succeeded;
  final Object? error;
}

/// Fetches daily FX history and persists it to the local `fx_rates` table.
///
/// The service derives which currency pairs to fetch from the user's
/// account currencies and base currency. It fetches one rate per
/// foreign currency (base↔foreign) via [MarketDataService.getQuote]
/// using Yahoo Finance symbols (`{BASE}{QUOTE}=X`) as a fallback. The primary
/// path uses [MarketDataService.getHistorical] so missed app launches can be
/// backfilled instead of leaving holes in the local series.
class FxRateSyncService {
  FxRateSyncService({
    required MarketDataService marketData,
    required FxRateRepository fxRepo,
    Clock clock = const SystemClock(),
    Duration historyLookback = const Duration(days: 365 * 5),
    Duration incrementalOverlap = const Duration(days: 7),
  }) : _marketData = marketData,
       _fxRepo = fxRepo,
       _clock = clock,
       _historyLookback = historyLookback,
       _incrementalOverlap = incrementalOverlap {
    if (historyLookback.inDays < 1) {
      throw ArgumentError.value(
        historyLookback,
        'historyLookback',
        'must be at least one day',
      );
    }
    if (incrementalOverlap.inDays < 0) {
      throw ArgumentError.value(
        incrementalOverlap,
        'incrementalOverlap',
        'must not be negative',
      );
    }
  }

  final MarketDataService _marketData;
  final FxRateRepository _fxRepo;
  final Clock _clock;
  final Duration _historyLookback;
  final Duration _incrementalOverlap;

  /// Fetch and persist FX rates for all needed pairs.
  ///
  /// [baseCurrency] is the user's preferred display currency (e.g. "CNY").
  /// [accountCurrencies] is the set of currencies used across all accounts
  /// (e.g. {"USD", "HKD", "CNY"}).
  ///
  /// The first sync for a pair fetches [_historyLookback] calendar days.
  /// Later automatic syncs start [_incrementalOverlap] days before the newest
  /// stored observation, so a device that was offline can fill the missing
  /// tail without downloading the entire series again. Set [fullHistory] for
  /// an explicit repair/backfill action. [from] and [to] are inclusive UTC
  /// calendar-day overrides intended for repair tools and tests.
  ///
  /// Returns a per-pair report. A failed pair is recorded in [failures] and
  /// does not prevent the remaining pairs from being attempted.
  Future<FxRateSyncResult> syncRatesDetailed({
    required String baseCurrency,
    required Set<String> accountCurrencies,
    bool fullHistory = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final base = baseCurrency.trim().toUpperCase();
    if (base.isEmpty) {
      throw ArgumentError.value(
        baseCurrency,
        'baseCurrency',
        'must not be empty',
      );
    }
    final foreigns =
        accountCurrencies
            .map((c) => c.trim().toUpperCase())
            .where((c) => c.isNotEmpty && c != base)
            .toSet()
            .toList()
          ..sort();

    if (foreigns.isEmpty) {
      return FxRateSyncResult(
        requestedPairs: const {},
        syncedPairs: const {},
        failures: const {},
      );
    }

    final end = _floorUtcDay(to ?? _clock.now());
    final explicitStart = from == null ? null : _floorUtcDay(from);
    if (explicitStart != null && explicitStart.isAfter(end)) {
      throw ArgumentError.value(from, 'from', 'must not be after to');
    }

    final requestedPairs = <String>{};
    final syncedPairs = <String>{};
    final failures = <String, String>{};
    for (final foreign in foreigns) {
      final pair = '$base/$foreign';
      requestedPairs.add(pair);
      try {
        final start =
            explicitStart ??
            await _startForPair(
              base: base,
              quote: foreign,
              end: end,
              fullHistory: fullHistory,
            );
        await _fetchAndPersist(base, foreign, from: start, to: end);
        syncedPairs.add(pair);
      } catch (e, st) {
        final message = _describeError(e);
        failures[pair] = message;
        AppLogger.instance.w(
          'FX sync: failed to fetch $base→$foreign: $message',
          error: e,
          stackTrace: st,
        );
      }
    }
    return FxRateSyncResult(
      requestedPairs: requestedPairs,
      syncedPairs: syncedPairs,
      failures: failures,
    );
  }

  /// Backwards-compatible count-only API for non-UI callers.
  Future<int> syncRates({
    required String baseCurrency,
    required Set<String> accountCurrencies,
    bool fullHistory = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await syncRatesDetailed(
      baseCurrency: baseCurrency,
      accountCurrencies: accountCurrencies,
      fullHistory: fullHistory,
      from: from,
      to: to,
    );
    return result.syncedCount;
  }

  Future<DateTime> _startForPair({
    required String base,
    required String quote,
    required DateTime end,
    required bool fullHistory,
  }) async {
    final earliestAllowed = end.subtract(
      Duration(days: _historyLookback.inDays - 1),
    );
    if (fullHistory) return earliestAllowed;

    final latest = await _fxRepo.latestDateForPair(base: base, quote: quote);
    if (latest == null) return earliestAllowed;

    final overlapStart = latest.subtract(
      Duration(days: _incrementalOverlap.inDays),
    );
    return overlapStart.isBefore(earliestAllowed)
        ? earliestAllowed
        : overlapStart.isAfter(end)
        ? end
        : overlapStart;
  }

  /// Fetch a single pair from historical market data and upsert every
  /// returned trading-day close into the local table. If history is
  /// unavailable, falls back to the latest quote path for resilience.
  ///
  /// Yahoo symbol format: `{base}{quote}=X` (e.g. `USDCNY=X`).
  /// If the direct symbol fails, tries the inverse (`{quote}{base}=X`) and
  /// inverts every returned close.
  Future<void> _fetchAndPersist(
    String base,
    String quote, {
    required DateTime from,
    required DateTime to,
  }) async {
    final symbol = '$base$quote=X';
    final failures = <Object>[];
    final directHistory = await _fetchHistoricalAndPersist(
      symbol: symbol,
      base: base,
      quote: quote,
      from: from,
      to: to,
    );
    if (directHistory.succeeded) {
      return;
    }
    if (directHistory.error != null) failures.add(directHistory.error!);
    // The direct and inverse symbols still hit the same Yahoo IP quota. Once
    // the provider has explicitly rate-limited us, trying all four fallbacks
    // only turns one failed refresh into a larger burst of 429s.
    if (_isRateLimited(directHistory.error)) {
      throw _noDataError(base: base, quote: quote, failures: failures);
    }

    final inverseSymbol = '$quote$base=X';
    final inverseHistory = await _fetchHistoricalAndPersist(
      symbol: inverseSymbol,
      base: base,
      quote: quote,
      from: from,
      to: to,
      invert: true,
    );
    if (inverseHistory.succeeded) {
      return;
    }
    if (inverseHistory.error != null) failures.add(inverseHistory.error!);

    // History is the source of truth for continuity, but retaining the old
    // quote fallback means a provider outage can still record today's mark.
    final directQuote = await _fetchQuoteAndPersist(
      symbol: symbol,
      base: base,
      quote: quote,
    );
    if (directQuote.succeeded) {
      return;
    }
    if (directQuote.error != null) failures.add(directQuote.error!);

    final inverseQuote = await _fetchQuoteAndPersist(
      symbol: inverseSymbol,
      base: base,
      quote: quote,
      invert: true,
    );
    if (inverseQuote.succeeded) {
      return;
    }
    if (inverseQuote.error != null) failures.add(inverseQuote.error!);

    throw _noDataError(base: base, quote: quote, failures: failures);
  }

  Future<_FxFetchAttempt> _fetchHistoricalAndPersist({
    required String symbol,
    required String base,
    required String quote,
    required DateTime from,
    required DateTime to,
    bool invert = false,
  }) async {
    try {
      final response = await _marketData.getHistorical(
        symbol,
        from: from,
        to: to,
        interval: BarInterval.day,
        market: AssetMarket.fx,
      );
      final observations = <FxRate>[];
      for (final bar in response.data) {
        if (bar.close <= Decimal.zero) continue;
        final rate = invert ? _invert(bar.close) : bar.close;
        observations.add(
          FxRate(
            base: base,
            quote: quote,
            date: bar.asOf,
            rate: rate,
            source: response.source,
            fetchedAt: response.fetchedAt,
          ),
        );
      }
      if (observations.isEmpty) {
        final error = StateError('$symbol returned no usable bars');
        AppLogger.instance.d('FX history: $error');
        return _FxFetchAttempt.failure(error);
      }
      await _fxRepo.upsertDailyBatch(observations);
      return const _FxFetchAttempt.success();
    } catch (e) {
      AppLogger.instance.d('FX history: $symbol failed ($e)');
      return _FxFetchAttempt.failure(e);
    }
  }

  Future<_FxFetchAttempt> _fetchQuoteAndPersist({
    required String symbol,
    required String base,
    required String quote,
    bool invert = false,
  }) async {
    try {
      final response = await _marketData.getQuote(
        symbol,
        market: AssetMarket.fx,
      );
      final price = response.data.price;
      if (price <= Decimal.zero) {
        return _FxFetchAttempt.failure(
          StateError('$symbol returned a non-positive quote'),
        );
      }
      await _fxRepo.upsertDaily(
        baseCurrency: base,
        quoteCurrency: quote,
        rate: invert ? _invert(price) : price,
        asOf: response.data.asOf,
        fetchedAt: response.fetchedAt,
        source: response.source,
      );
      return const _FxFetchAttempt.success();
    } catch (e) {
      AppLogger.instance.d('FX quote: $symbol failed ($e)');
      return _FxFetchAttempt.failure(e);
    }
  }

  String _describeError(Object error) {
    if (error is MarketDataException) {
      final cause = error.cause;
      final causeText = cause == null ? '' : ' (${_describeError(cause)})';
      final provider = error.provider == null ? '' : ' [${error.provider}]';
      return '${error.runtimeType}$provider: ${error.message}$causeText';
    }
    return error.toString();
  }

  NoMarketDataAvailableException _noDataError({
    required String base,
    required String quote,
    required List<Object> failures,
  }) {
    final details = failures.map(_describeError).take(2).join('; ');
    return NoMarketDataAvailableException(
      'no FX data available for $base→$quote'
      '${details.isEmpty ? '' : ' ($details)'}',
      cause: failures.isEmpty ? null : failures.last,
    );
  }

  bool _isRateLimited(Object? error) {
    if (error is RateLimitException) return true;
    if (error is MarketDataException) return _isRateLimited(error.cause);
    return false;
  }

  static Decimal _invert(Decimal value) =>
      (Decimal.one / value).toDecimal(scaleOnInfinitePrecision: 8);

  static DateTime _floorUtcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
