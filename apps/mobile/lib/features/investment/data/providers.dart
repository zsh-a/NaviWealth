import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/entities/fx_rate.dart' as dom;
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../settings/data/base_currency_preference.dart';
import '../domain/holding_price_source.dart';
import '../domain/holding_service.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/trade_entry/default_trade_entry_service.dart';
import '../domain/trade_entry/trade_entry_service.dart';

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
  final prices = ref.watch(holdingPriceSourceProvider);
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
      final service = await ref.watch(holdingServiceProvider.future);
      return service.computeAt(DateTime.now().toUtc());
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
