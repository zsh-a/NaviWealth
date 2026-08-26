part of 'providers.dart';

final allAssetsStreamProvider = StreamProvider.autoDispose<List<Asset>>((
  ref,
) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.assets)..where((t) => t.deletedAt.isNull());
  yield* query.watch().map((rows) => rows.map(_assetFromRow).toList());
});

final _priceRowsStreamProvider = StreamProvider.autoDispose<List<PriceRow>>((
  ref,
) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.prices)..where((t) => t.deletedAt.isNull());
  yield* query.watch();
});

DateTime _floorToDay(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

/// Composed price source for the holdings pipeline:
///   1. Pre-resolved live prices from [priceResolverProvider] for "now-ish"
///      asOf lookups (drives the live dashboard / FIRE / AI snapshot).
///   2. Synced `prices` ledger observations for historical asOf (drives
///      portfolio-return curves, time-machine views, anything pre-today).
///
/// Switching from the prior ledger-only `Provider<HoldingPriceSource>` to
/// this `FutureProvider` means consumers (`holdingServiceProvider`,
/// `portfolioReturnServiceProvider`) need to await it — they already lived
/// in `FutureProvider` scopes, so the change is local.
final holdingPriceSourceProvider = FutureProvider<HoldingPriceSource>((
  ref,
) async {
  // Re-resolve live prices after each successful market sync. Selecting only
  // lastSuccessAt avoids rebuilding for the intermediate syncing event.
  ref.watch(
    priceSyncStatusEventStreamProvider.select(
      (event) => event.value?.lastSuccessAt,
    ),
  );
  final rows = ref.watch(_priceRowsStreamProvider).value ?? const <PriceRow>[];
  final ledgerSource = InMemoryHoldingPriceSource([
    for (final row in rows)
      HoldingPriceObservation(
        assetId: row.unit,
        asOf: _floorToDay(row.observedOn),
        price: row.perUnit,
        currency: row.quoteCurrency,
        confidence: row.source == 'manual' || row.source.startsWith('manual:')
            ? PriceConfidence.manual
            : PriceConfidence.dailyClose,
        source: row.source,
      ),
  ]);
  final assets = ref.watch(allAssetsStreamProvider).value ?? const <Asset>[];
  final resolver = await ref.watch(priceResolverProvider.future);
  final clock = ref.watch(clockProvider);
  final resolvedAt = clock.now();
  final resolved = await resolver.resolveMany(assets, asOf: resolvedAt);
  return ResolvedPriceHoldingSource(
    resolved: resolved,
    resolvedAt: resolvedAt,
    fallback: ledgerSource,
  );
});

final returnsCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const <dom.FxRate>[];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

final holdingBaseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(baseCurrencyProvider);
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
