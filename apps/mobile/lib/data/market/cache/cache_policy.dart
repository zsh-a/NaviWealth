/// TTL knobs for the market-data cache layer.
///
/// FIR-26 calls for "行情 60s / 历史 1d TTL". `quoteFresh` matches that.
/// `quoteStaleWindow` is the additional grace window during which we still
/// serve a cached quote — labelled `stale` for the UI badge — when every
/// provider in the chain is unreachable. Beyond that window we throw rather
/// than mislead the user with a price that may be days old.
class MarketCachePolicy {
  const MarketCachePolicy({
    this.quoteFresh = const Duration(seconds: 60),
    this.quoteStaleWindow = const Duration(hours: 24),
    this.historyFresh = const Duration(days: 1),
    this.historyStaleWindow = const Duration(days: 30),
    this.searchFresh = const Duration(days: 7),
    this.searchStaleWindow = const Duration(days: 30),
    this.maxInMemoryQuotes = 256,
  });

  final Duration quoteFresh;
  final Duration quoteStaleWindow;
  final Duration historyFresh;
  final Duration historyStaleWindow;
  final Duration searchFresh;
  final Duration searchStaleWindow;
  final int maxInMemoryQuotes;
}
