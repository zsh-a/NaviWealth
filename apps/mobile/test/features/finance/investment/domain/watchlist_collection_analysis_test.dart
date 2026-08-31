import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_collection_analysis.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

void main() {
  test('projects coverage, direction, alerts, movers, and market slices', () {
    final analysis = WatchlistCollectionAnalysis.fromEntries([
      _entry(
        id: 'aapl',
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        price: '110',
        previousClose: '100',
        freshness: DataFreshness.live,
        alertConfigured: true,
        alertTriggered: true,
      ),
      _entry(
        id: 'msft',
        symbol: 'MSFT',
        market: AssetMarket.usStock,
        price: '90',
        previousClose: '100',
        freshness: DataFreshness.cachedFresh,
        alertConfigured: true,
      ),
      _entry(
        id: 'flat',
        symbol: 'FLAT',
        market: AssetMarket.usStock,
        price: '100',
        previousClose: '100',
        freshness: DataFreshness.stale,
      ),
      _entry(
        id: 'unknown',
        symbol: 'UNKNOWN',
        market: AssetMarket.usStock,
        price: '100',
        freshness: DataFreshness.live,
      ),
      _entry(id: '2800', symbol: '2800.HK', market: AssetMarket.hkStock),
    ]);

    final overall = analysis.overall;
    expect(overall.symbolCount, 5);
    expect(overall.availableQuoteCount, 4);
    expect(overall.unavailableQuoteCount, 1);
    expect(overall.quoteCoverageRatio, 0.8);
    expect(overall.liveQuoteCount, 2);
    expect(overall.cachedQuoteCount, 1);
    expect(overall.staleQuoteCount, 1);
    expect(overall.advancingCount, 1);
    expect(overall.decliningCount, 1);
    expect(overall.unchangedCount, 1);
    expect(overall.unknownPreviousCloseCount, 1);
    expect(overall.alertConfiguredCount, 2);
    expect(overall.triggeredAlertCount, 1);
    expect(overall.medianChangePercent, Decimal.zero);
    expect(overall.topGainer?.symbol, 'AAPL');
    expect(overall.topGainer?.changePercent, Decimal.parse('0.1'));
    expect(overall.topDecliner?.symbol, 'MSFT');
    expect(overall.topDecliner?.changePercent, Decimal.parse('-0.1'));

    expect(analysis.byMarket, hasLength(2));
    final us = analysis.byMarket.singleWhere(
      (slice) => slice.market == AssetMarket.usStock,
    );
    final hk = analysis.byMarket.singleWhere(
      (slice) => slice.market == AssetMarket.hkStock,
    );
    expect(us.symbolCount, 4);
    expect(us.availableQuoteCount, 4);
    expect(hk.symbolCount, 1);
    expect(hk.unavailableQuoteCount, 1);
  });

  test('averages the middle pair for an even-sized median', () {
    final analysis = WatchlistCollectionAnalysis.fromEntries([
      _entry(
        id: 'one',
        symbol: 'ONE',
        market: AssetMarket.usStock,
        price: '110',
        previousClose: '100',
        freshness: DataFreshness.live,
      ),
      _entry(
        id: 'two',
        symbol: 'TWO',
        market: AssetMarket.usStock,
        price: '120',
        previousClose: '100',
        freshness: DataFreshness.live,
      ),
    ]);

    expect(analysis.overall.medianChangePercent, Decimal.parse('0.15'));
  });

  test('treats a price without freshness metadata as unavailable', () {
    final analysis = WatchlistCollectionAnalysis.fromEntries([
      _entry(
        id: 'partial',
        symbol: 'PARTIAL',
        market: AssetMarket.usStock,
        price: '100',
        previousClose: '90',
      ),
    ]);

    expect(analysis.overall.availableQuoteCount, 0);
    expect(analysis.overall.unavailableQuoteCount, 1);
    expect(analysis.overall.advancingCount, 0);
  });
}

WatchlistAnalysisEntry _entry({
  required String id,
  required String symbol,
  required AssetMarket market,
  String? price,
  String? previousClose,
  DataFreshness? freshness,
  bool alertConfigured = false,
  bool alertTriggered = false,
}) {
  return WatchlistAnalysisEntry(
    id: id,
    symbol: symbol,
    market: market,
    price: price == null ? null : Decimal.parse(price),
    previousClose: previousClose == null ? null : Decimal.parse(previousClose),
    freshness: freshness,
    alertConfigured: alertConfigured,
    alertTriggered: alertTriggered,
  );
}
