import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

class WatchlistAnalysisEntry {
  const WatchlistAnalysisEntry({
    required this.id,
    required this.symbol,
    required this.market,
    required this.price,
    required this.previousClose,
    required this.freshness,
    required this.alertConfigured,
    required this.alertTriggered,
  });

  final String id;
  final String symbol;
  final AssetMarket market;
  final Decimal? price;
  final Decimal? previousClose;
  final DataFreshness? freshness;
  final bool alertConfigured;
  final bool alertTriggered;

  Decimal? get changePercent {
    final current = price;
    final previous = previousClose;
    if (current == null || previous == null || previous == Decimal.zero) {
      return null;
    }
    return ((current - previous) / previous).toDecimal(
      scaleOnInfinitePrecision: 6,
    );
  }
}

class WatchlistMover {
  const WatchlistMover({
    required this.id,
    required this.symbol,
    required this.market,
    required this.changePercent,
  });

  final String id;
  final String symbol;
  final AssetMarket market;
  final Decimal changePercent;
}

class WatchlistAnalysisSlice {
  const WatchlistAnalysisSlice({
    required this.market,
    required this.symbolCount,
    required this.availableQuoteCount,
    required this.liveQuoteCount,
    required this.cachedQuoteCount,
    required this.staleQuoteCount,
    required this.unavailableQuoteCount,
    required this.advancingCount,
    required this.decliningCount,
    required this.unchangedCount,
    required this.unknownPreviousCloseCount,
    required this.alertConfiguredCount,
    required this.triggeredAlertCount,
    required this.medianChangePercent,
    required this.topGainer,
    required this.topDecliner,
  });

  final AssetMarket? market;
  final int symbolCount;
  final int availableQuoteCount;
  final int liveQuoteCount;
  final int cachedQuoteCount;
  final int staleQuoteCount;
  final int unavailableQuoteCount;
  final int advancingCount;
  final int decliningCount;
  final int unchangedCount;
  final int unknownPreviousCloseCount;
  final int alertConfiguredCount;
  final int triggeredAlertCount;
  final Decimal? medianChangePercent;
  final WatchlistMover? topGainer;
  final WatchlistMover? topDecliner;

  double get quoteCoverageRatio =>
      symbolCount == 0 ? 0 : availableQuoteCount / symbolCount;
}

class WatchlistCollectionAnalysis {
  const WatchlistCollectionAnalysis({
    required this.overall,
    required this.byMarket,
  });

  factory WatchlistCollectionAnalysis.fromEntries(
    Iterable<WatchlistAnalysisEntry> entries,
  ) {
    final allEntries = List<WatchlistAnalysisEntry>.unmodifiable(entries);
    final byMarket = <AssetMarket, List<WatchlistAnalysisEntry>>{};
    for (final entry in allEntries) {
      byMarket.putIfAbsent(entry.market, () => []).add(entry);
    }
    final markets = byMarket.keys.toList()
      ..sort((left, right) => left.wire.compareTo(right.wire));
    return WatchlistCollectionAnalysis(
      overall: _analyzeSlice(allEntries),
      byMarket: List<WatchlistAnalysisSlice>.unmodifiable([
        for (final market in markets)
          _analyzeSlice(byMarket[market]!, market: market),
      ]),
    );
  }

  final WatchlistAnalysisSlice overall;
  final List<WatchlistAnalysisSlice> byMarket;
}

WatchlistAnalysisSlice _analyzeSlice(
  List<WatchlistAnalysisEntry> entries, {
  AssetMarket? market,
}) {
  var availableQuoteCount = 0;
  var liveQuoteCount = 0;
  var cachedQuoteCount = 0;
  var staleQuoteCount = 0;
  var unavailableQuoteCount = 0;
  var advancingCount = 0;
  var decliningCount = 0;
  var unchangedCount = 0;
  var unknownPreviousCloseCount = 0;
  var alertConfiguredCount = 0;
  var triggeredAlertCount = 0;
  final changes = <Decimal>[];
  WatchlistMover? topGainer;
  WatchlistMover? topDecliner;

  for (final entry in entries) {
    if (entry.alertConfigured) alertConfiguredCount++;
    if (entry.alertConfigured && entry.alertTriggered) triggeredAlertCount++;
    if (entry.price == null || entry.freshness == null) {
      unavailableQuoteCount++;
      continue;
    }

    availableQuoteCount++;
    switch (entry.freshness) {
      case DataFreshness.live:
        liveQuoteCount++;
      case DataFreshness.cachedFresh:
        cachedQuoteCount++;
      case DataFreshness.stale:
        staleQuoteCount++;
      case null:
        break;
    }

    final change = entry.changePercent;
    if (change == null) {
      unknownPreviousCloseCount++;
      continue;
    }
    changes.add(change);
    if (change > Decimal.zero) {
      advancingCount++;
      if (topGainer == null || change > topGainer.changePercent) {
        topGainer = _mover(entry, change);
      }
    } else if (change < Decimal.zero) {
      decliningCount++;
      if (topDecliner == null || change < topDecliner.changePercent) {
        topDecliner = _mover(entry, change);
      }
    } else {
      unchangedCount++;
    }
  }

  changes.sort();
  final median = switch (changes.length) {
    0 => null,
    final length when length.isOdd => changes[length ~/ 2],
    final length =>
      ((changes[(length ~/ 2) - 1] + changes[length ~/ 2]) / Decimal.fromInt(2))
          .toDecimal(scaleOnInfinitePrecision: 6),
  };

  return WatchlistAnalysisSlice(
    market: market,
    symbolCount: entries.length,
    availableQuoteCount: availableQuoteCount,
    liveQuoteCount: liveQuoteCount,
    cachedQuoteCount: cachedQuoteCount,
    staleQuoteCount: staleQuoteCount,
    unavailableQuoteCount: unavailableQuoteCount,
    advancingCount: advancingCount,
    decliningCount: decliningCount,
    unchangedCount: unchangedCount,
    unknownPreviousCloseCount: unknownPreviousCloseCount,
    alertConfiguredCount: alertConfiguredCount,
    triggeredAlertCount: triggeredAlertCount,
    medianChangePercent: median,
    topGainer: topGainer,
    topDecliner: topDecliner,
  );
}

WatchlistMover _mover(WatchlistAnalysisEntry entry, Decimal change) {
  return WatchlistMover(
    id: entry.id,
    symbol: entry.symbol,
    market: entry.market,
    changePercent: change,
  );
}
