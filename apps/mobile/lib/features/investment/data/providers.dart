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
import 'transaction_repository.dart';

final transactionRepositoryProvider =
    FutureProvider<TransactionRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return TransactionRepository(db: db, outbox: outbox, stamper: stamper);
});

/// Currency converter for trade-entry FX backfill.
/// Uses the same stub as the dashboard until a persistent FX rate repo ships.
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

/// Live stream of every non-deleted [Asset] in the local database. The
/// holding pipeline needs to look up prices and currency for any asset id
/// it sees in a transaction, regardless of whether it's a manual cash row
/// or a securities row — so this is a single read over the full table
/// rather than the type-filtered streams the analytics or assets tabs use.
/// Also consumed by the dashboard to pair securities holdings with their
/// asset metadata (type → category bucket, name, currency).
final allAssetsStreamProvider =
    StreamProvider.autoDispose<List<Asset>>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.assets)..where((t) => t.deletedAt.isNull());
  yield* query.watch().map((rows) => rows.map(_assetFromRow).toList());
});

/// Live stream of every non-deleted transaction. The holding and returns
/// adapters consume this synchronously, so a new trade flows through to
/// the dashboard and analytics snapshots without manual invalidation.
final transactionsStreamProvider =
    StreamProvider.autoDispose<List<Transaction>>((ref) async* {
  final repo = await ref.watch(transactionRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Per-asset price source for the holding pipeline. Forward-fills from
/// `Asset.lastPrice` — the most recent observed close. Granular price
/// history (intraday / per-day bars) is a follow-up; for "value the
/// portfolio at noon today" the current `lastPrice` is the right answer
/// in single-currency simulations and good enough for the dashboard's
/// XIRR bookend valuations.
///
/// Returns `null` when no price has ever been observed (asset row exists
/// but `lastPrice` is null) or when the requested `asOf` predates
/// `lastPriceAt` — refusing to forward-fill from "tomorrow's close" into
/// "yesterday's value" prevents look-ahead bias in historical XIRR runs.
final holdingPriceSourceProvider = Provider<HoldingPriceSource>((ref) {
  final assets = ref.watch(allAssetsStreamProvider).value ?? const <Asset>[];
  return _AssetLastPriceHoldingPriceSource(assets);
});

/// Currency converter wired through to the live fx_rates stream — same
/// fallback as the dashboard converter so XIRR sees the same FX state.
final returnsCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const <dom.FxRate>[];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

/// Cost-basis method used by the holding pipeline. Default to FIFO until
/// settings exposes a preference. (LIFO / average will require a Riverpod
/// override or a settings-backed provider.)
final holdingCostBasisMethodProvider = Provider<CostBasisMethod>(
  (ref) => CostBasisMethod.fifo,
);

/// In-memory daily snapshot store — first-launch warm cache. The Drift-
/// backed implementation lands alongside the post-close snapshot job.
final holdingDailySnapshotStoreProvider =
    Provider<HoldingDailySnapshotStore>((ref) {
  return InMemoryHoldingDailySnapshotStore();
});

/// Adapter exposing [transactionsStreamProvider] as a
/// [HoldingTransactionsRepository]. Filters in memory by owner / date —
/// fine for personal-portfolio sizes; a Drift-side range query is the
/// natural follow-up for large-history users. Rebuilds whenever the
/// transactions stream emits, which is what makes new trades surface in
/// the dashboard / holdings views without explicit invalidation.
final holdingTransactionsRepositoryProvider =
    Provider<HoldingTransactionsRepository>((ref) {
  final txns =
      ref.watch(transactionsStreamProvider).value ?? const <Transaction>[];
  return _TransactionListHoldingAdapter(txns);
});

/// Adapter exposing [transactionsStreamProvider] as a
/// [ReturnsTransactionsRepository]. Same shape as the holding adapter.
final returnsTransactionsRepositoryProvider =
    Provider<ReturnsTransactionsRepository>((ref) {
  final txns =
      ref.watch(transactionsStreamProvider).value ?? const <Transaction>[];
  return _TransactionListReturnsAdapter(txns);
});

/// Owner user id resolver — same MutationStamper-backed resolver every
/// other repo uses, surfaced as a Riverpod-friendly Future for the
/// holding / returns service constructors.
final _currentOwnerUserIdProvider = FutureProvider<String>((ref) async {
  final stamper = await ref.watch(mutationStamperProvider.future);
  return stamper.currentUserId();
});

/// Default base currency for the holding service. The analytics layer
/// keeps its own [analyticsBaseCurrencyProvider]; the dashboard uses
/// [dashboardBaseCurrencyProvider]. Both eventually read the same
/// settings preference, so we follow the dashboard's wiring here.
final holdingBaseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(baseCurrencyProvider);
});

/// Production [HoldingService] — composes the transaction adapter, the
/// in-memory snapshot store, the asset-driven price source, and the
/// dashboard FX converter.
///
/// Tests override this directly with a fake (see analytics_page_test.dart)
/// rather than overriding every dependency individually.
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

/// Per-asset portfolio snapshot at "now". Single seam consumed by both
/// the dashboard (rolls market value into `总资产`) and the analytics
/// page (allocation / concentration views). Re-fires whenever the
/// underlying transactions stream, asset prices, or FX rates change, so
/// recording a trade reactively updates every downstream chart.
final holdingsSnapshotProvider =
    FutureProvider.autoDispose<Map<String, HoldingSnapshot>>((ref) async {
  final service = await ref.watch(holdingServiceProvider.future);
  return service.computeAt(DateTime.now().toUtc());
});

/// Adapter exposing [HoldingService.lotsAt] as a [ReturnsLotsSource].
final returnsLotsSourceProvider =
    FutureProvider<ReturnsLotsSource>((ref) async {
  final service = await ref.watch(holdingServiceProvider.future);
  return _HoldingServiceReturnsLotsSource(service);
});

/// FIR-89: composes [ReturnsService] for portfolio / asset / bucket XIRR.
/// Reuses the holding-service adapter for lot bookends, the same
/// transaction repository for in-window flows, and the dashboard's FX
/// converter so cross-currency cash flows roll up consistently.
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
    lastPrice: row.lastPrice,
    lastPriceAt: row.lastPriceAt,
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

class _AssetLastPriceHoldingPriceSource implements HoldingPriceSource {
  _AssetLastPriceHoldingPriceSource(Iterable<Asset> assets)
      : _byId = {
          for (final a in assets)
            if (a.lastPrice != null) a.id: a,
        };

  final Map<String, Asset> _byId;

  @override
  HoldingPrice? priceFor(String assetId, {required DateTime asOf}) {
    final a = _byId[assetId];
    if (a == null || a.lastPrice == null) return null;
    final ts = a.lastPriceAt;
    if (ts != null && ts.isAfter(asOf)) return null;
    return HoldingPrice(price: a.lastPrice!, currency: a.currency);
  }
}

List<Transaction> _filter(
  List<Transaction> all,
  String ownerUserId,
  DateTime from,
  DateTime to,
) {
  return all
      .where(
        (t) =>
            t.sync.ownerUserId == ownerUserId &&
            t.sync.deletedAt == null &&
            !t.tradeDate.isBefore(from) &&
            !t.tradeDate.isAfter(to),
      )
      .toList();
}

class _TransactionListHoldingAdapter implements HoldingTransactionsRepository {
  _TransactionListHoldingAdapter(this._txns);
  final List<Transaction> _txns;

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      _filter(_txns, ownerUserId, from, to);

  @override
  Future<List<CorporateAction>> corporateActionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      const <CorporateAction>[];
}

class _TransactionListReturnsAdapter implements ReturnsTransactionsRepository {
  _TransactionListReturnsAdapter(this._txns);
  final List<Transaction> _txns;

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async =>
      _filter(_txns, ownerUserId, from, to);
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
