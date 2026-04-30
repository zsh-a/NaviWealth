import 'package:flutter/foundation.dart';

import '../../../../domain/values/asset_market.dart';

/// Catalogue of mainstream broad-base indices the user can pin against
/// their portfolio. Kept as a closed enum (rather than an open list driven
/// from settings) so the comparison card can hard-code curated metadata
/// — display name resource keys, native currency, provider symbol — while
/// the rest of the app still flows through [MarketDataService].
///
/// Order matters: it doubles as the default chip ordering shown in the UI.
enum BenchmarkIndex {
  hs300,
  sp500,
  nasdaq,
  hsi,
}

/// Static metadata for a [BenchmarkIndex]. Symbol values are the ones that
/// resolve through the production provider chain (yfinance + sina), so the
/// composite [MarketDataService] does not need any new routing rules.
@immutable
class BenchmarkIndexInfo {
  const BenchmarkIndexInfo({
    required this.index,
    required this.symbol,
    required this.currency,
    required this.market,
  });

  final BenchmarkIndex index;

  /// Provider-facing ticker. yfinance accepts `^GSPC` / `^IXIC` / `^HSI`
  /// directly; A-share index history is served via the same `<code>.SS`
  /// listing yfinance exposes (`000300.SS` for the CSI 300 / 沪深 300).
  final String symbol;

  /// Native currency the index price is quoted in. Used to label tooltips
  /// — the comparison itself runs on normalized (unitless) ratios so we
  /// never FX-convert benchmark prices.
  final String currency;

  final AssetMarket market;
}

/// Lookup catalogue. The map is keyed by [BenchmarkIndex] so the lookup
/// stays type-safe; no string-based registry to drift out of sync.
const Map<BenchmarkIndex, BenchmarkIndexInfo> kBenchmarkIndexCatalogue = {
  BenchmarkIndex.hs300: BenchmarkIndexInfo(
    index: BenchmarkIndex.hs300,
    symbol: '000300.SS',
    currency: 'CNY',
    market: AssetMarket.cnA,
  ),
  BenchmarkIndex.sp500: BenchmarkIndexInfo(
    index: BenchmarkIndex.sp500,
    symbol: '^GSPC',
    currency: 'USD',
    market: AssetMarket.usStock,
  ),
  BenchmarkIndex.nasdaq: BenchmarkIndexInfo(
    index: BenchmarkIndex.nasdaq,
    symbol: '^IXIC',
    currency: 'USD',
    market: AssetMarket.usStock,
  ),
  BenchmarkIndex.hsi: BenchmarkIndexInfo(
    index: BenchmarkIndex.hsi,
    symbol: '^HSI',
    currency: 'HKD',
    market: AssetMarket.hkStock,
  ),
};

/// Convenience accessor — throws if the catalogue is mistakenly out of sync
/// with the enum (caught by an `enumValuesAreCatalogued` test).
BenchmarkIndexInfo benchmarkInfoFor(BenchmarkIndex index) {
  final info = kBenchmarkIndexCatalogue[index];
  if (info == null) {
    throw StateError('Benchmark catalogue missing entry for $index');
  }
  return info;
}
