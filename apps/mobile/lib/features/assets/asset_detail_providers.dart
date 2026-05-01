import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/domain/transaction.dart';
import '../../data/market/market_data_providers.dart';
import '../../domain/entities/historical_bar.dart';
import '../../domain/services/market_data_service.dart';
import '../../domain/values/asset_market.dart';
import '../investment/data/providers.dart';
import '../investment/domain/cost_basis_engine.dart';
import '../investment/domain/holding_computer.dart';
import '../investment/domain/models/holding_snapshot.dart';

/// Live stream of every non-deleted transaction for [assetId], newest first.
///
/// Wraps [TransactionRepository.watchByAssetId] as an autoDispose family so
/// the asset-detail card subscribes only while the page is mounted.
final assetTransactionsStreamProvider = StreamProvider.autoDispose
    .family<List<Transaction>, String>((ref, assetId) async* {
  final repo = await ref.watch(transactionRepositoryProvider.future);
  yield* repo.watchByAssetId(assetId);
});

/// Replays [assetId]'s transactions through the active cost-basis engine.
///
/// We re-derive realized P&L locally rather than reading it off
/// [holdingServiceProvider] because that service only surfaces unrealized
/// snapshots. The replay scope is limited to a single asset's transactions,
/// so the result is independent of cross-asset corporate actions — which
/// is what the asset-detail card needs.
final assetReplayProvider = FutureProvider.autoDispose
    .family<HoldingReplayResult, String>((ref, assetId) async {
  final txs = await ref.watch(
    assetTransactionsStreamProvider(assetId).future,
  );
  final method = ref.watch(holdingCostBasisMethodProvider);
  final computer = HoldingComputer(
    engine: CostBasisEngine.forMethod(method),
  );
  return computer.replay(initialLots: const [], transactions: txs);
});

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
    .family<MarketResponse<List<HistoricalBar>>, PriceHistoryKey>(
  (ref, key) async {
    final service = await ref.watch(marketDataServiceProvider.future);
    final to = DateTime.now().toUtc();
    final from = to.subtract(Duration(days: key.days));
    return service.getHistorical(
      key.symbol,
      from: from,
      to: to,
      market: key.market,
    );
  },
);

/// Aggregate realized P&L for [assetId] in asset currency.
///
/// Sums `RealizedPnL.gain` (proceeds − fees − cost) across every closed lot
/// the replay produced. Asset-currency rather than base-currency: the card
/// renders this next to native cost / market value, so keeping the units
/// consistent avoids an FX conversion that would otherwise need a per-sell
/// historical rate.
final assetRealizedPnlProvider = FutureProvider.autoDispose
    .family<Decimal, String>((ref, assetId) async {
  final result = await ref.watch(assetReplayProvider(assetId).future);
  var total = Decimal.zero;
  for (final r in result.realizedPnL) {
    total += r.gain;
  }
  return total;
});
