import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/preferences/price_sync_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';

import 'fx_rate_sync_providers.dart';
import 'price_sync_coordinator.dart';

final priceSyncStatusBusProvider = Provider<PriceSyncStatusBus>((ref) {
  final bus = PriceSyncStatusBus();
  ref.onDispose(bus.close);
  return bus;
});

final priceSyncStatusEventStreamProvider = StreamProvider<PriceSyncStatusEvent>(
  (ref) async* {
    final bus = ref.watch(priceSyncStatusBusProvider);
    yield bus.current;
    yield* bus.stream;
  },
);

/// Coordinator instance. Lazily constructed; bootstrap reads
/// [priceSyncCoordinatorBootstrapProvider] which keeps a listener alive
/// and triggers [PriceSyncCoordinator.start] when the dependency chain
/// resolves.
final priceSyncCoordinatorProvider = FutureProvider<PriceSyncCoordinator>((
  ref,
) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final fxSync = await ref.watch(fxRateSyncServiceProvider.future);
  final prices = await ref.watch(priceRepositoryProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  final clock = ref.watch(clockProvider);
  final statusBus = ref.watch(priceSyncStatusBusProvider);

  final coordinator = PriceSyncCoordinator(
    market: market,
    fxSync: fxSync,
    prices: prices,
    // Read the toggle on each cycle so a settings change takes effect
    // without restarting the coordinator.
    writeDailySnapshots: () => ref.read(writeDailyPriceSnapshotsProvider),
    clock: clock,
    statusBus: statusBus,
    heldAssets: () => _readHeldAssets(db),
    fxInputs: () => _readFxInputs(db, ref),
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

/// Eager start hook. Bootstrap reads this once; the listener fires the
/// coordinator's `start()` whenever its dependency tree resolves.
final priceSyncCoordinatorBootstrapProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<PriceSyncCoordinator>>(priceSyncCoordinatorProvider, (
    _,
    next,
  ) {
    next.whenData((coordinator) => coordinator.start());
  }, fireImmediately: true);
});

Future<List<Asset>> _readHeldAssets(AppDatabase db) async {
  final query = db.select(db.assets)..where((t) => t.deletedAt.isNull());
  final rows = await query.get();
  return rows.map(_assetFromRow).toList(growable: false);
}

Future<FxSyncInputs?> _readFxInputs(AppDatabase db, Ref ref) async {
  final base = ref.read(baseCurrencyProvider);
  final rows = await db
      .customSelect(
        'SELECT currency FROM accounts '
        'WHERE deleted_at IS NULL AND archived = 0 '
        "AND id NOT LIKE 'system-account:%' "
        'UNION '
        'SELECT currency FROM assets WHERE deleted_at IS NULL',
      )
      .get();
  final currencies = rows
      .map((r) => r.read<String>('currency').trim().toUpperCase())
      .where((currency) => currency.isNotEmpty)
      .toSet();
  return FxSyncInputs(baseCurrency: base, currencies: currencies);
}

Asset _assetFromRow(AssetRow row) => Asset(
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
