import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/mutation_context.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/ai/contracts/task_context.dart' show AnalyticalUpload;
import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/providers.dart';
import '../../../domain/entities/fx_rate.dart' as dom;
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../../features/finance/data/market/market_data_providers.dart';
import '../../settings/data/base_currency_preference.dart';
import '../domain/cost_basis/fifo_strategy.dart';
import '../domain/cost_basis_engine.dart';
import '../domain/fx_pnl/fx_pnl_breakdown.dart';
import '../domain/holding_price_source.dart';
import '../domain/holding_service.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/models/realized_pnl.dart';
import '../domain/models/trade_events.dart';
import '../domain/reporting/holding_report.dart';
import '../domain/returns/portfolio_return.dart';
import '../domain/trade_entry/default_trade_entry_service.dart';
import '../domain/trade_entry/trade_entry_service.dart';
import 'portfolio_return_service.dart';

final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
});

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((
  ref,
) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  return DefaultTradeEntryService(market: market, fx: fx);
});

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

final _ledgerRevisionProvider = StreamProvider.autoDispose<int>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query =
      db.select(db.postings).join([
          innerJoin(
            db.journalEntries,
            db.journalEntries.id.equalsExp(db.postings.journalEntryId),
          ),
          leftOuterJoin(
            db.accounts,
            db.accounts.id.equalsExp(db.postings.accountId),
          ),
        ])
        ..where(db.postings.deletedAt.isNull())
        ..where(db.journalEntries.deletedAt.isNull());
  var revision = 0;
  // Debounce by 300ms: during rapid sync writes, only the last emission
  // in a burst triggers the expensive holdings recomputation cascade.
  Timer? timer;
  final controller = StreamController<int>();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  query.watch().listen(
    (_) {
      timer?.cancel();
      timer = Timer(
        const Duration(milliseconds: 300),
        () => controller.add(revision++),
      );
    },
    onError: controller.addError,
    onDone: controller.close,
  );
  yield* controller.stream;
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
  final rows = ref.watch(_priceRowsStreamProvider).value ?? const <PriceRow>[];
  final ledgerSource = InMemoryHoldingPriceSource([
    for (final row in rows)
      HoldingPriceObservation(
        assetId: row.unit,
        asOf: _floorToDay(row.observedOn),
        price: row.perUnit,
        currency: row.quoteCurrency,
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

final _currentOwnerUserIdProvider = FutureProvider<String>((ref) async {
  final stamper = await ref.watch(mutationStamperProvider.future);
  return stamper.currentUserId();
});

final holdingBaseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(baseCurrencyProvider);
});

final holdingServiceProvider = FutureProvider<HoldingService>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final prices = await ref.watch(holdingPriceSourceProvider.future);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final base = ref.watch(holdingBaseCurrencyProvider);
  return _LedgerHoldingService(
    db: db,
    ownerUserId: ownerUserId,
    baseCurrency: base,
    prices: prices,
    converter: converter,
  );
});

final holdingsSnapshotProvider =
    FutureProvider.autoDispose<Map<String, HoldingSnapshot>>((ref) async {
      ref.watch(_ledgerRevisionProvider);
      final service = await ref.watch(holdingServiceProvider.future);
      return service.computeAt(DateTime.now().toUtc());
    });

final portfolioHoldingReportProvider =
    FutureProvider.autoDispose<PortfolioHoldingReport>((ref) async {
      ref.watch(_ledgerRevisionProvider);
      final now = DateTime.now().toUtc();
      final service = await ref.watch(holdingServiceProvider.future);
      final prices = await ref.watch(holdingPriceSourceProvider.future);
      final converter = ref.watch(returnsCurrencyConverterProvider);
      final base = ref.watch(holdingBaseCurrencyProvider);
      final lots = await service.lotsAt(now);
      return HoldingReportService(
        converter: converter,
        baseCurrency: base,
        prices: prices,
      ).build(lots: lots, asOf: now);
    });

final assetHoldingReportProvider = FutureProvider.autoDispose
    .family<AssetHoldingReport?, String>((ref, assetId) async {
      final report = await ref.watch(portfolioHoldingReportProvider.future);
      return report.assets[assetId];
    });

final portfolioFxPnlProvider = Provider.autoDispose<FxPnLBreakdown>((ref) {
  final report = ref.watch(portfolioHoldingReportProvider).value;
  return report?.totalPnlBreakdown ??
      FxPnLBreakdown.zero(ref.watch(holdingBaseCurrencyProvider));
});

final realizedPnlProvider = FutureProvider.autoDispose<List<RealizedPnL>>((
  ref,
) async {
  ref.watch(_ledgerRevisionProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final rows = await _postingRowsThrough(
    db,
    ownerUserId,
    DateTime.now().toUtc(),
  );
  return _realizedPnlFromRows(rows);
});

final portfolioReturnServiceProvider = FutureProvider<PortfolioReturnService>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final holdings = await ref.watch(holdingServiceProvider.future);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final base = ref.watch(holdingBaseCurrencyProvider);
  return LedgerPortfolioReturnService(
    db: db,
    ownerUserId: ownerUserId,
    baseCurrency: base,
    holdings: holdings,
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

class _LedgerHoldingService implements HoldingService {
  _LedgerHoldingService({
    required AppDatabase db,
    required this.ownerUserId,
    required this.baseCurrency,
    required this.prices,
    required this.converter,
  }) : _db = db;

  final AppDatabase _db;
  final String ownerUserId;
  final String baseCurrency;
  final HoldingPriceSource prices;
  final CurrencyConverter converter;

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async {
    final lots = await lotsAt(asOf);
    final byAsset = <String, _HoldingAccumulator>{};
    for (final lot in lots.where((l) => !l.isClosed)) {
      final acc = byAsset.putIfAbsent(
        lot.assetId,
        () => _HoldingAccumulator(currency: lot.currency),
      );
      acc.add(lot);
    }

    final snapshots = <String, HoldingSnapshot>{};
    var totalMarketValue = Decimal.zero;
    for (final entry in byAsset.entries) {
      final acc = entry.value;
      if (acc.quantity == Decimal.zero) continue;

      final price =
          prices.priceFor(entry.key, asOf: asOf) ??
          HoldingPrice(price: acc.averageCostPerUnit, currency: acc.currency);
      final marketValue = acc.quantity * price.price;

      Money costBase;
      Money valueBase;
      try {
        costBase = converter.convert(
          Money(acc.costBasis, acc.currency),
          baseCurrency,
          on: asOf,
        );
        valueBase = converter.convert(
          Money(marketValue, price.currency),
          baseCurrency,
          on: asOf,
        );
      } on FxRateNotFoundError {
        continue;
      }

      totalMarketValue += valueBase.amount;
      snapshots[entry.key] = HoldingSnapshot(
        assetId: entry.key,
        quantity: acc.quantity,
        costBasisInAssetCurrency: acc.costBasis,
        marketValueInAssetCurrency: marketValue,
        assetCurrency: price.currency,
        costBasisInBase: costBase.amount,
        marketValueInBase: valueBase.amount,
        unrealizedPnlInBase: valueBase.amount - costBase.amount,
        weight: Decimal.zero,
        baseCurrency: baseCurrency,
        asOf: asOf,
        priceConfidence: price.confidence,
        priceSource: price.source,
        priceAsOf: price.asOf,
      );
    }

    if (totalMarketValue == Decimal.zero) return snapshots;
    return {
      for (final entry in snapshots.entries)
        entry.key: entry.value.copyWith(
          weight: (entry.value.marketValueInBase / totalMarketValue).toDecimal(
            scaleOnInfinitePrecision: 8,
          ),
        ),
    };
  }

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async {
    final rows = await _postingRowsThrough(asOf);
    final lots = <Lot>[];
    for (final row in rows) {
      final posting = row.posting;
      final cost = posting.costPerUnit;
      final costCurrency = posting.costCurrency;
      if (cost == null || costCurrency == null) continue;
      if (posting.units > Decimal.zero) {
        lots.add(
          Lot(
            id: posting.costLotId ?? posting.id,
            openingTransactionId: posting.journalEntryId,
            accountId: posting.accountId,
            assetId: posting.unit,
            currency: costCurrency,
            originalQuantity: posting.units,
            remainingQuantity: posting.units,
            costPerUnit: cost,
            openedAt: posting.costAcquiredOn ?? row.date,
          ),
        );
      } else if (posting.units < Decimal.zero) {
        _reduceLots(
          lots,
          accountId: posting.accountId,
          assetId: posting.unit,
          lotId: posting.costLotId,
          quantity: -posting.units,
        );
      }
    }
    return lots;
  }

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async {
    final boundary = _endOfDay(day);
    return LotInventorySnapshot(
      ownerUserId: ownerUserId,
      day: _utcDay(day),
      lots: await lotsAt(boundary),
    );
  }

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  Future<List<_LedgerPostingRow>> _postingRowsThrough(DateTime asOf) async {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
            innerJoin(_db.assets, _db.assets.id.equalsExp(_db.postings.unit)),
          ])
          ..where(_db.postings.ownerUserId.equals(ownerUserId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull())
          ..where(_db.journalEntries.date.isSmallerOrEqualValue(asOf))
          ..orderBy([
            OrderingTerm.asc(_db.journalEntries.date),
            OrderingTerm.asc(_db.postings.position),
            OrderingTerm.asc(_db.postings.id),
          ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        _LedgerPostingRow(
          posting: row.readTable(_db.postings),
          date: row.readTable(_db.journalEntries).date,
        ),
    ];
  }

  void _reduceLots(
    List<Lot> lots, {
    required String accountId,
    required String assetId,
    required String? lotId,
    required Decimal quantity,
  }) {
    var remaining = quantity;
    final candidates =
        lots
            .where(
              (lot) =>
                  !lot.isClosed &&
                  lot.accountId == accountId &&
                  lot.assetId == assetId &&
                  (lotId == null || lot.id == lotId),
            )
            .toList()
          ..sort((a, b) => a.openedAt.compareTo(b.openedAt));

    for (final lot in candidates) {
      if (remaining <= Decimal.zero) break;
      final closeQty = lot.remainingQuantity < remaining
          ? lot.remainingQuantity
          : remaining;
      final index = lots.indexOf(lot);
      lots[index] = lot.copyWith(
        remainingQuantity: lot.remainingQuantity - closeQty,
      );
      remaining -= closeQty;
    }
  }

  static DateTime _utcDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  static DateTime _endOfDay(DateTime d) {
    final day = _utcDay(d);
    return day
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
  }
}

Future<List<_LedgerPostingRow>> _postingRowsThrough(
  AppDatabase db,
  String ownerUserId,
  DateTime asOf,
) async {
  final query =
      db.select(db.postings).join([
          innerJoin(
            db.journalEntries,
            db.journalEntries.id.equalsExp(db.postings.journalEntryId),
          ),
          innerJoin(db.assets, db.assets.id.equalsExp(db.postings.unit)),
        ])
        ..where(db.postings.ownerUserId.equals(ownerUserId))
        ..where(db.postings.deletedAt.isNull())
        ..where(db.journalEntries.deletedAt.isNull())
        ..where(db.journalEntries.date.isSmallerOrEqualValue(asOf))
        ..orderBy([
          OrderingTerm.asc(db.journalEntries.date),
          OrderingTerm.asc(db.postings.position),
          OrderingTerm.asc(db.postings.id),
        ]);
  final rows = await query.get();
  return [
    for (final row in rows)
      _LedgerPostingRow(
        posting: row.readTable(db.postings),
        date: row.readTable(db.journalEntries).date,
      ),
  ];
}

List<RealizedPnL> _realizedPnlFromRows(List<_LedgerPostingRow> rows) {
  var id = 0;
  final engine = CostBasisEngine(
    strategy: const FifoStrategy(),
    idGenerator: () => 'realized-${++id}',
  );
  var lots = <Lot>[];
  final realized = <RealizedPnL>[];

  for (final row in rows) {
    final posting = row.posting;
    final cost = posting.costPerUnit;
    final costCurrency = posting.costCurrency;
    if (cost == null || costCurrency == null) continue;

    if (posting.units > Decimal.zero) {
      lots = [
        ...lots,
        Lot(
          id: posting.costLotId ?? posting.id,
          openingTransactionId: posting.journalEntryId,
          accountId: posting.accountId,
          assetId: posting.unit,
          currency: costCurrency,
          originalQuantity: posting.units,
          remainingQuantity: posting.units,
          costPerUnit: cost,
          openedAt: posting.costAcquiredOn ?? row.date,
        ),
      ];
      continue;
    }

    final price = posting.pricePerUnit;
    final priceCurrency = posting.priceCurrency;
    if (posting.units < Decimal.zero &&
        price != null &&
        priceCurrency != null) {
      final result = engine.applySell(
        SellEvent(
          transactionId: posting.journalEntryId,
          accountId: posting.accountId,
          assetId: posting.unit,
          currency: priceCurrency,
          quantity: -posting.units,
          pricePerUnit: price,
          fee: Decimal.zero,
          tradeDate: row.date,
        ),
        lots,
      );
      lots = result.updatedLots;
      realized.addAll(result.realizedPnL);
    }
  }

  realized.sort((a, b) => b.realizedAt.compareTo(a.realizedAt));
  return List.unmodifiable(realized);
}

class _LedgerPostingRow {
  const _LedgerPostingRow({required this.posting, required this.date});

  final PostingRow posting;
  final DateTime date;
}

class _HoldingAccumulator {
  _HoldingAccumulator({required this.currency});

  final String currency;
  Decimal quantity = Decimal.zero;
  Decimal costBasis = Decimal.zero;

  Decimal get averageCostPerUnit {
    if (quantity == Decimal.zero) return Decimal.zero;
    return (costBasis / quantity).toDecimal(scaleOnInfinitePrecision: 16);
  }

  void add(Lot lot) {
    quantity += lot.remainingQuantity;
    costBasis += lot.remainingCost;
  }
}

/// Device-side portfolio snapshot — the canonical holdings picture
/// (holdings engine + FX + multi-lot). Uploaded on the cloud chat path
/// (`portfolio_snapshot`) and read directly by the device `get_holdings`
/// tool (§4.6.3 W-D4.2), so both paths share one builder. Returns
/// `null` when the user has no holdings.
final devicePortfolioSnapshotProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>(
      (ref) => buildDevicePortfolioSnapshot(ref),
    );

Future<Map<String, Object?>?> buildDevicePortfolioSnapshot(Ref ref) async {
  final holdings = await ref.read(holdingsSnapshotProvider.future);
  if (holdings.isEmpty) return null;
  final assets = await ref.read(allAssetsStreamProvider.future);
  final byId = {for (final asset in assets) asset.id: asset};
  final asOf = holdings.values.first.asOf.toUtc().toIso8601String();
  final baseCurrency = holdings.values.first.baseCurrency;
  return <String, Object?>{
    'as_of': asOf,
    'base_currency': baseCurrency,
    'holdings': <String, Object?>{
      for (final entry in holdings.entries)
        entry.key: holdingSnapshotJson(entry.value, byId[entry.key]),
    },
  };
}

Map<String, Object?> holdingSnapshotJson(HoldingSnapshot snap, Asset? asset) {
  return <String, Object?>{
    'asset_id': snap.assetId,
    'symbol': asset?.symbol,
    'name': asset?.name,
    'type': asset?.type.name,
    'net_quantity': snap.quantity.toString(),
    'asset_currency': snap.assetCurrency,
    'market_value_asset_currency': snap.marketValueInAssetCurrency.toString(),
    'cost_basis_asset_currency': snap.costBasisInAssetCurrency.toString(),
    'base_currency': snap.baseCurrency,
    'market_value_base': snap.marketValueInBase.toString(),
    'cost_basis_base': snap.costBasisInBase.toString(),
    'unrealized_pnl_base': snap.unrealizedPnlInBase.toString(),
    'weight': snap.weight.toString(),
    'as_of': snap.asOf.toUtc().toIso8601String(),
    'price_confidence': snap.priceConfidence?.name,
    'price_source': snap.priceSource,
    'price_as_of': snap.priceAsOf?.toUtc().toIso8601String(),
  };
}

/// The canonical [HoldingSnapshot] → [AnalyticalUpload] conversion
/// (§4.3.3). Single source shared by the cloud
/// `ContextPack.analytical_uploads` path and the device
/// `get_investment_performance` tool (W-D4.3b) so the device tool's
/// output is exactly what the backend `investment_performance` read
/// model mirrors (§10). Decimals are stringified to avoid float drift.
AnalyticalUpload holdingSnapshotToUpload(HoldingSnapshot snap) {
  return AnalyticalUpload(
    kind: 'investment_performance',
    id: snap.assetId,
    payload: <String, Object?>{
      'asset_id': snap.assetId,
      'asset_currency': snap.assetCurrency,
      'base_currency': snap.baseCurrency,
      'as_of': snap.asOf.toUtc().toIso8601String(),
      'quantity': snap.quantity.toString(),
      'cost_basis_in_asset_currency': snap.costBasisInAssetCurrency.toString(),
      'market_value_in_asset_currency': snap.marketValueInAssetCurrency
          .toString(),
      'cost_basis_in_base': snap.costBasisInBase.toString(),
      'market_value_in_base': snap.marketValueInBase.toString(),
      'unrealized_pnl_in_base': snap.unrealizedPnlInBase.toString(),
      'weight': snap.weight.toString(),
    },
  );
}
