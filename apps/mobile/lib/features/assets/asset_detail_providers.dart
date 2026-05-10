import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/market/market_data_providers.dart';
import '../../domain/entities/historical_bar.dart';
import '../../domain/services/market_data_service.dart';
import '../../domain/values/asset_market.dart';
import '../investment/data/providers.dart';
import '../investment/domain/models/holding_snapshot.dart';

/// Snapshot of [assetId] from the portfolio's holding pipeline at "now".
///
/// Returns null when the user has never held the asset (no lots ever
/// opened) — distinct from "currently flat" (snapshot present, quantity
/// zero), so the card can pick a sensible empty state.
final assetHoldingSnapshotProvider = FutureProvider.autoDispose
    .family<HoldingSnapshot?, String>((ref, assetId) async {
      final service = await ref.watch(holdingServiceProvider.future);
      final asOf = DateTime.now().toUtc();
      final all = await service.computeAt(asOf);
      return all[assetId];
    });

/// Family key for [assetPriceHistoryProvider]. Value-equal so two cards on
/// the same asset and lookback share a single cache entry.
class PriceHistoryKey {
  const PriceHistoryKey({
    required this.symbol,
    required this.market,
    required this.days,
  });

  final String symbol;
  final AssetMarket? market;
  final int days;

  @override
  bool operator ==(Object other) =>
      other is PriceHistoryKey &&
      other.symbol == symbol &&
      other.market == market &&
      other.days == days;

  @override
  int get hashCode => Object.hash(symbol, market, days);
}

/// Last [PriceHistoryKey.days] of close-price bars for the asset (FIR-26).
///
/// The market service is responsible for caching + offline degradation;
/// this provider just turns its returned [MarketResponse] into a Riverpod
/// future so the chart can read freshness alongside the data.
final assetPriceHistoryProvider = FutureProvider.autoDispose
    .family<MarketResponse<List<HistoricalBar>>, PriceHistoryKey>((
      ref,
      key,
    ) async {
      final service = await ref.watch(marketDataServiceProvider.future);
      final to = DateTime.now().toUtc();
      final from = to.subtract(Duration(days: key.days));
      return service.getHistorical(
        key.symbol,
        from: from,
        to: to,
        market: key.market,
      );
    });
