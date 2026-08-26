import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';

/// Adds provider-backed daily bars to a live/ledger holding price source.
///
/// Current valuation intentionally resolves from live quotes and the synced
/// `prices` ledger. Historical charts additionally need an on-demand price
/// window so days without a persisted snapshot do not fall back to cost basis
/// and render as a misleading flat line.
Future<HoldingPriceSource> buildHistoricalHoldingPriceSource({
  required MarketDataService market,
  required HoldingPriceSource current,
  required Iterable<Asset> assets,
  required DateTime from,
  required DateTime to,
  Duration lookback = const Duration(days: 14),
  int concurrency = 4,
}) async {
  final assetList = assets.toList(growable: false);
  if (assetList.isEmpty) return current;

  final observations = <HoldingPriceObservation>[];
  final historyFrom = from.toUtc().subtract(lookback);
  final historyTo = to.toUtc();
  final batchSize = concurrency < 1 ? 1 : concurrency;
  for (var start = 0; start < assetList.length; start += batchSize) {
    final end = (start + batchSize).clamp(0, assetList.length);
    final resolved = await Future.wait(
      assetList
          .sublist(start, end)
          .map(
            (asset) => _historicalObservationsForAsset(
              market: market,
              asset: asset,
              from: historyFrom,
              to: historyTo,
            ),
          ),
    );
    for (final rows in resolved) {
      observations.addAll(rows);
    }
  }
  if (observations.isEmpty) return current;
  return _HistoricalHoldingPriceSource(
    current: current,
    historical: InMemoryHoldingPriceSource(observations),
  );
}

Future<List<HoldingPriceObservation>> _historicalObservationsForAsset({
  required MarketDataService market,
  required Asset asset,
  required DateTime from,
  required DateTime to,
}) async {
  if (asset.symbol.trim().isEmpty) return const [];
  try {
    final response = await market.getHistorical(
      asset.symbol,
      from: from,
      to: to,
      market: assetMarketFromWire(asset.market),
    );
    final confidence = response.isStale
        ? PriceConfidence.stale
        : PriceConfidence.dailyClose;
    return [
      for (final bar in response.data)
        HoldingPriceObservation(
          assetId: asset.id,
          // Holdings are valued at the tradable close. Adjusted close is a
          // total-return series and would count dividends again when the
          // ledger already contains dividend/corporate-action postings.
          price: bar.close,
          currency: asset.currency,
          asOf: bar.asOf.toUtc(),
          confidence: confidence,
          source: 'historical-bar:${response.source}',
        ),
    ];
  } on Object {
    // History enhances the existing live/ledger path. Offline or unsupported
    // providers retain the current source and its explicit estimated quality.
    return const [];
  }
}

class _HistoricalHoldingPriceSource implements HoldingPriceSource {
  const _HistoricalHoldingPriceSource({
    required this.current,
    required this.historical,
  });

  final HoldingPriceSource current;
  final HoldingPriceSource historical;

  @override
  HoldingPrice? priceFor(String assetId, {required DateTime asOf}) {
    final currentPrice = current.priceFor(assetId, asOf: asOf);
    final historicalPrice = historical.priceFor(assetId, asOf: asOf);
    if (currentPrice == null) return historicalPrice;
    if (historicalPrice == null || _isManualPrice(currentPrice)) {
      return currentPrice;
    }
    final currentAt = currentPrice.asOf;
    final historicalAt = historicalPrice.asOf;
    if (currentAt == null || currentAt.isAfter(asOf)) return historicalPrice;
    if (historicalAt == null || currentAt.isAfter(historicalAt)) {
      return currentPrice;
    }
    return historicalPrice;
  }

  bool _isManualPrice(HoldingPrice price) {
    if (price.confidence == PriceConfidence.manual) return true;
    final source = price.source?.toLowerCase();
    return source == 'manual' || source?.startsWith('manual:') == true;
  }
}
