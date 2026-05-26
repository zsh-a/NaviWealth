/// TTL knobs for the market-data cache layer.
///
/// Default quote freshness is one day. NaviWealth uses market data for
/// portfolio valuation and FX conversion rather than intraday trading, so the
/// automatic refresh path should not burn free-tier provider quota every few
/// minutes.
/// `quoteStaleWindow` is the additional grace window during which we still
/// serve a cached quote — labelled `stale` for the UI badge — when every
/// provider in the chain is unreachable. Beyond that window we throw rather
/// than mislead the user with a price that may be days old.
class MarketCachePolicy {
  const MarketCachePolicy({
    this.quoteFresh = const Duration(days: 1),
    this.quoteStaleWindow = const Duration(days: 7),
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
