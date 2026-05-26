import 'package:naviwealth/features/options_income/domain/option_contract.dart';

/// Abstract chain provider. Distinct from `MarketProvider` because:
///   * options requests are user-initiated, never on a render path;
///   * each provider has its own per-symbol throttle (the doc's
///     "low-frequency third path");
///   * the result is denominated in normalized contracts ready for the
///     scorer, not raw provider DTOs.
///
/// See `docs/options-income.md` §4 for the rollout / TOS notes.
abstract class OptionsChainProvider {
  String get name;

  /// Fetch the option chain for [underlying] limited to a DTE window. The
  /// implementation must:
  ///   * apply its own rate-limiter via [MarketHttpClient],
  ///   * enforce per-symbol-per-expiration throttling (5 minutes per the
  ///     design doc) — repeated calls inside the window may return the
  ///     last successful payload from in-memory cache.
  Future<OptionsChainSnapshot> fetchChain(OptionsChainRequest request);
}

class OptionsChainRequest {
  const OptionsChainRequest({
    required this.underlying,
    required this.minDte,
    required this.maxDte,
  });

  final String underlying;
  final int minDte;
  final int maxDte;
}

class OptionsChainSnapshot {
  const OptionsChainSnapshot({
    required this.underlying,
    required this.underlyingPriceRaw,
    required this.currency,
    required this.contracts,
    required this.fetchedAt,
  });

  final String underlying;
  final String currency;

  /// Plain spot price string captured at chain fetch time. Decimal-parsed
  /// downstream so the provider doesn't need a Money dep here.
  final String underlyingPriceRaw;

  final List<OptionContract> contracts;
  final DateTime fetchedAt;
}
