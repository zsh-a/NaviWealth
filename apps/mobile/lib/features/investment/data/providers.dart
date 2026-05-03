import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/providers.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/domain/transaction.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/entities/fx_rate.dart' as dom;
import '../../../domain/services/currency_converter.dart';
import '../../settings/data/base_currency_preference.dart';
import '../domain/cost_basis/cost_basis_method.dart';
import '../domain/holding_price_source.dart';
import '../domain/holding_service.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/returns/returns_service.dart';
import '../domain/trade_entry/default_trade_entry_service.dart';
import '../domain/trade_entry/trade_entry_service.dart';

final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
});

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((ref) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  final engine = await ref.watch(syncEngineProvider.future);
  final deviceId = ref.watch(deviceIdProviderProvider);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return DefaultTradeEntryService(
    market: market,
    fx: fx,
    stampHlc: engine.stampHlc,
    ownerUserId: await stamper.currentUserId(),
    deviceId: await deviceId.getOrCreate(),
  );
});

final allAssetsStreamProvider =
    StreamProvider.autoDispose<List<Asset>>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.assets)..where((t) => t.deletedAt.isNull());
  yield* query.watch().map((rows) => rows.map(_assetFromRow).toList());
});

final _priceRowsStreamProvider =
    StreamProvider.autoDispose<List<PriceRow>>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.prices)..where((t) => t.deletedAt.isNull());
  yield* query.watch();
});

final holdingPriceSourceProvider = Provider<HoldingPriceSource>((ref) {
  final rows = ref.watch(_priceRowsStreamProvider).value ?? const <PriceRow>[];
  return InMemoryHoldingPriceSource([
    for (final row in rows)
      HoldingPriceObservation(
        assetId: row.unit,
        asOf: row.observedOn,
        price: row.perUnit,
        currency: row.quoteCurrency,
      ),
  ]);
});

final returnsCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const <dom.FxRate>[];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

final holdingCostBasisMethodProvider = Provider<CostBasisMethod>(
  (ref) => CostBasisMethod.fifo,
);

final holdingDailySnapshotStoreProvider =
    Provider<HoldingDailySnapshotStore>((ref) {
  return InMemoryHoldingDailySnapshotStore();
});

final holdingTransactionsRepositoryProvider =
    Provider<HoldingTransactionsRepository>((ref) {
  return const _EmptyHoldingTransactionsAdapter();
});

final returnsTransactionsRepositoryProvider =
    Provider<ReturnsTransactionsRepository>((ref) {
  return const _EmptyReturnsTransactionsAdapter();
});

final _currentOwnerUserIdProvider = FutureProvider<String>((ref) async {
  final stamper = await ref.watch(mutationStamperProvider.future);
  return stamper.currentUserId();
});

final holdingBaseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(baseCurrencyProvider);
});

final holdingServiceProvider =
    FutureProvider<HoldingService>((ref) async {
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final transactions = ref.watch(holdingTransactionsRepositoryProvider);
  final snapshots = ref.watch(holdingDailySnapshotStoreProvider);
  final prices = ref.watch(holdingPriceSourceProvider);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final base = ref.watch(holdingBaseCurrencyProvider);
  final method = ref.watch(holdingCostBasisMethodProvider);
  return DefaultHoldingService(
    ownerUserId: ownerUserId,
    baseCurrency: base,
    costBasisMethod: method,
    transactions: transactions,
    snapshots: snapshots,
    prices: prices,
    converter: converter,
  );
});

final holdingsSnapshotProvider =
    FutureProvider.autoDispose<Map<String, HoldingSnapshot>>((ref) async {
  final service = await ref.watch(holdingServiceProvider.future);
  return service.computeAt(DateTime.now().toUtc());
});

final returnsLotsSourceProvider =
    FutureProvider<ReturnsLotsSource>((ref) async {
  final service = await ref.watch(holdingServiceProvider.future);
  return _HoldingServiceReturnsLotsSource(service);
});

final returnsServiceProvider =
    FutureProvider<ReturnsService>((ref) async {
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final transactions = ref.watch(returnsTransactionsRepositoryProvider);
  final lots = await ref.watch(returnsLotsSourceProvider.future);
  final prices = ref.watch(holdingPriceSourceProvider);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final base = ref.watch(holdingBaseCurrencyProvider);
  return ReturnsService(
    ownerUserId: ownerUserId,
    baseCurrency: base,
    transactions: transactions,
    lots: lots,
    prices: prices,
    converter: converter,
  );
});

Asset _assetFromRow(AssetRow row) {
  return Asset(
    id: row.id,
    type: row.type,
    symbol: row.symbol,
    currency: row.currency,
    name: row.name,
    market: row.market,
    industry: row.industry,
    region: row.region,
    isin: row.isin,
    logoUrl: row.logoUrl,
    metadataJson: row.metadataJson,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}

class _EmptyHoldingTransactionsAdapter
    implements HoldingTransactionsRepository {
  const _EmptyHoldingTransactionsAdapter();

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      const <Transaction>[];

  @override
  Future<List<CorporateAction>> corporateActionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      const <CorporateAction>[];
}

class _EmptyReturnsTransactionsAdapter
    implements ReturnsTransactionsRepository {
  const _EmptyReturnsTransactionsAdapter();

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      const <Transaction>[];
}

class _HoldingServiceReturnsLotsSource implements ReturnsLotsSource {
  _HoldingServiceReturnsLotsSource(this._service);
  final HoldingService _service;

  @override
  Future<List<Lot>> lotsAt({
    required String ownerUserId,
    required DateTime asOf,
  }) {
    return _service.lotsAt(asOf);
  }
}
