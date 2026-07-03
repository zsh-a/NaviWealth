part of 'quote_cache.dart';

String _quoteKey(String symbol, String? source) =>
    '${symbol.toUpperCase()}|${source ?? '*'}';

CachedQuote? _withFreshness(MarketCache cache, CachedQuote cached) {
  final age = cache._clock.now().difference(cached.fetchedAt);
  final freshness = _classify(
    age,
    fresh: cache._policy.quoteFresh,
    stale: cache._policy.quoteStaleWindow,
  );
  if (freshness == null) return null;
  return cached.copyWithFreshness(freshness);
}

DataFreshness? _classify(
  Duration age, {
  required Duration fresh,
  required Duration stale,
}) {
  if (age <= fresh) return DataFreshness.cachedFresh;
  if (age <= stale) return DataFreshness.stale;
  return null;
}

String _intervalKey(BarInterval interval) {
  switch (interval) {
    case BarInterval.day:
      return '1d';
    case BarInterval.week:
      return '1wk';
    case BarInterval.month:
      return '1mo';
  }
}

Map<String, dynamic> _symbolInfoToJson(SymbolInfo info) => {
  'symbol': info.symbol,
  'name': info.name,
  'market': info.market.name,
  if (info.currency != null) 'currency': info.currency,
  if (info.exchange != null) 'exchange': info.exchange,
  if (info.assetType != null) 'assetType': info.assetType,
};

SymbolInfo _symbolInfoFromJson(Map<String, dynamic> json) => SymbolInfo(
  symbol: json['symbol'] as String,
  name: json['name'] as String,
  market: AssetMarket.values.firstWhere(
    (m) => m.name == (json['market'] as String? ?? 'unknown'),
    orElse: () => AssetMarket.unknown,
  ),
  currency: json['currency'] as String?,
  exchange: json['exchange'] as String?,
  assetType: json['assetType'] as String?,
);
