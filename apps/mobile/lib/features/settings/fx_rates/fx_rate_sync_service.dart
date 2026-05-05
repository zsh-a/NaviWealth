import 'package:decimal/decimal.dart';

import '../../../core/logging/app_logger.dart';

import '../../../data/repositories/fx_rate_repository.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';

/// Fetches today's FX rates from Yahoo Finance and persists them to the
/// local `fx_rates` table.
///
/// The service derives which currency pairs to fetch from the user's
/// account currencies and base currency. It fetches one rate per
/// foreign currency (base↔foreign) via [MarketDataService.getQuote]
/// using Yahoo Finance symbols (`{BASE}{QUOTE}=X`).
class FxRateSyncService {
  FxRateSyncService({
    required MarketDataService marketData,
    required FxRateRepository fxRepo,
  })  : _marketData = marketData,
        _fxRepo = fxRepo;

  final MarketDataService _marketData;
  final FxRateRepository _fxRepo;

  /// Fetch and persist today's FX rates for all needed pairs.
  ///
  /// [baseCurrency] is the user's preferred display currency (e.g. "CNY").
  /// [accountCurrencies] is the set of currencies used across all accounts
  /// (e.g. {"USD", "HKD", "CNY"}).
  ///
  /// Returns the number of rates successfully synced.
  Future<int> syncRates({
    required String baseCurrency,
    required Set<String> accountCurrencies,
  }) async {
    final base = baseCurrency.trim().toUpperCase();
    final foreigns = accountCurrencies
        .map((c) => c.trim().toUpperCase())
        .where((c) => c != base)
        .toSet();

    if (foreigns.isEmpty) return 0;

    var synced = 0;
    for (final foreign in foreigns) {
      try {
        await _fetchAndPersist(base, foreign);
        synced++;
      } catch (e) {
        AppLogger.instance.w('FX sync: failed to fetch $base→$foreign: $e');
      }
    }
    return synced;
  }

  /// Fetch a single pair from Yahoo Finance and upsert into the local table.
  ///
  /// Yahoo symbol format: `{base}{quote}=X` (e.g. `USDCNY=X`).
  /// If the direct symbol fails, tries the inverse (`{quote}{base}=X`).
  Future<void> _fetchAndPersist(String base, String quote) async {
    final symbol = '$base$quote=X';
    try {
      final resp = await _marketData.getQuote(symbol, market: AssetMarket.fx);
      await _fxRepo.upsertDaily(
        baseCurrency: base,
        quoteCurrency: quote,
        rate: resp.data.price,
        asOf: resp.data.asOf,
        source: 'yfinance',
      );
    } catch (e) {
      AppLogger.instance.d('FX sync: $symbol failed ($e), trying inverse');
      // Try inverse: quoteBase=X and invert the rate.
      final inverseSymbol = '$quote$base=X';
      final resp =
          await _marketData.getQuote(inverseSymbol, market: AssetMarket.fx);
      final inverseRate = resp.data.price;
      if (inverseRate == Decimal.zero) rethrow;
      final rate =
          (Decimal.one / inverseRate).toDecimal(scaleOnInfinitePrecision: 8);
      await _fxRepo.upsertDaily(
        baseCurrency: base,
        quoteCurrency: quote,
        rate: rate,
        asOf: resp.data.asOf,
        source: 'yfinance',
      );
    }
  }
}
