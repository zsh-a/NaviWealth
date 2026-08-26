import 'package:decimal/decimal.dart';

import '../../../../../core/logging/app_logger.dart';
import '../../../domain/fx/fx_rate.dart';
import '../../../market/domain/asset_market.dart';
import '../../../market/domain/historical_bar.dart';
import '../../../market/domain/market_data_service.dart';
import '../../repositories/fx_rate_repository.dart';
import '../http/clock.dart';

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
  /// Returns the number of rates successfully synced.
  Future<int> syncRates({
    required String baseCurrency,
    required Set<String> accountCurrencies,
    bool fullHistory = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final base = baseCurrency.trim().toUpperCase();
    final foreigns = accountCurrencies
        .map((c) => c.trim().toUpperCase())
        .where((c) => c.isNotEmpty && c != base)
        .toSet();

    if (foreigns.isEmpty) return 0;

    final end = _floorUtcDay(to ?? _clock.now());
    final explicitStart = from == null ? null : _floorUtcDay(from);
    if (explicitStart != null && explicitStart.isAfter(end)) {
      throw ArgumentError.value(from, 'from', 'must not be after to');
    }

    var synced = 0;
    for (final foreign in foreigns) {
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
        synced++;
      } catch (e) {
        AppLogger.instance.w('FX sync: failed to fetch $base→$foreign: $e');
      }
    }
    return synced;
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
    if (await _fetchHistoricalAndPersist(
      symbol: symbol,
      base: base,
      quote: quote,
      from: from,
      to: to,
    )) {
      return;
    }

    final inverseSymbol = '$quote$base=X';
    if (await _fetchHistoricalAndPersist(
      symbol: inverseSymbol,
      base: base,
      quote: quote,
      from: from,
      to: to,
      invert: true,
    )) {
      return;
    }

    // History is the source of truth for continuity, but retaining the old
    // quote fallback means a provider outage can still record today's mark.
    if (await _fetchQuoteAndPersist(symbol: symbol, base: base, quote: quote)) {
      return;
    }
    if (await _fetchQuoteAndPersist(
      symbol: inverseSymbol,
      base: base,
      quote: quote,
      invert: true,
    )) {
      return;
    }

    throw StateError('no FX data available for $base→$quote');
  }

  Future<bool> _fetchHistoricalAndPersist({
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
        AppLogger.instance.d('FX history: $symbol returned no usable bars');
        return false;
      }
      await _fxRepo.upsertDailyBatch(observations);
      return true;
    } catch (e) {
      AppLogger.instance.d('FX history: $symbol failed ($e)');
      return false;
    }
  }

  Future<bool> _fetchQuoteAndPersist({
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
      if (price <= Decimal.zero) return false;
      await _fxRepo.upsertDaily(
        baseCurrency: base,
        quoteCurrency: quote,
        rate: invert ? _invert(price) : price,
        asOf: response.data.asOf,
        fetchedAt: response.fetchedAt,
        source: response.source,
      );
      return true;
    } catch (e) {
      AppLogger.instance.d('FX quote: $symbol failed ($e)');
      return false;
    }
  }

  static Decimal _invert(Decimal value) =>
      (Decimal.one / value).toDecimal(scaleOnInfinitePrecision: 8);

  static DateTime _floorUtcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
