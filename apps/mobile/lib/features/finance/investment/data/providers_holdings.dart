part of 'providers.dart';

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
  late final StreamSubscription<List<TypedResult>> subscription;
  ref.onDispose(() {
    timer?.cancel();
    unawaited(subscription.cancel());
    controller.close();
  });
  subscription = query.watch().listen(
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
    final rows = await _postingRowsThrough(_db, ownerUserId, asOf);
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
