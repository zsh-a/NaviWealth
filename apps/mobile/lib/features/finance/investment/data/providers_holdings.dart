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

class _LedgerHoldingService implements SampledHoldingService {
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

  LedgerLotReader get _lotReader => LedgerLotReader(_db);

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async {
    final samples = await computeAtSamples([asOf]);
    return samples.isEmpty ? const {} : samples.single.snapshots;
  }

  @override
  Future<List<HoldingSample>> computeAtSamples(Iterable<DateTime> dates) async {
    final sorted = dates.map((date) => date.toUtc()).toSet().toList()..sort();
    if (sorted.isEmpty) return const [];
    final lotsByDate = await _lotReader.allLotsAtSamples(
      ownerUserId: ownerUserId,
      dates: sorted,
    );
    return [
      for (final date in sorted)
        _valueLots(date, lotsByDate[date] ?? const <Lot>[]),
    ];
  }

  HoldingSample _valueLots(DateTime asOf, List<Lot> lots) {
    final byAsset = <String, _HoldingAccumulator>{};
    for (final lot in lots.where((l) => !l.isClosed)) {
      final acc = byAsset.putIfAbsent(
        lot.assetId,
        () => _HoldingAccumulator(currency: lot.currency),
      );
      acc.add(lot);
    }

    final snapshots = <String, HoldingSnapshot>{};
    final issues = <HoldingValuationIssue>[];
    var totalMarketValue = Decimal.zero;
    for (final entry in byAsset.entries) {
      final acc = entry.value;
      if (acc.quantity == Decimal.zero) continue;

      final observedPrice = prices.priceFor(entry.key, asOf: asOf);
      final price =
          observedPrice ??
          HoldingPrice(
            price: acc.averageCostPerUnit,
            currency: acc.currency,
            confidence: PriceConfidence.estimated,
            source: 'cost_basis',
            asOf: asOf,
          );
      if (observedPrice == null) {
        issues.add(
          HoldingValuationIssue(
            assetId: entry.key,
            currency: acc.currency,
            cause: HoldingValuationIssueCause.missingPrice,
          ),
        );
      }
      final marketValue = acc.quantity * price.price;

      final Money costBase;
      try {
        costBase = converter.convert(
          Money(acc.costBasis, acc.currency),
          baseCurrency,
          on: asOf,
        );
      } on FxRateNotFoundError {
        issues.add(
          HoldingValuationIssue(
            assetId: entry.key,
            currency: acc.currency,
            cause: HoldingValuationIssueCause.missingFx,
          ),
        );
        continue;
      }
      final Money valueBase;
      try {
        valueBase = converter.convert(
          Money(marketValue, price.currency),
          baseCurrency,
          on: asOf,
        );
      } on FxRateNotFoundError {
        issues.add(
          HoldingValuationIssue(
            assetId: entry.key,
            currency: price.currency,
            cause: HoldingValuationIssueCause.missingFx,
          ),
        );
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

    final weighted = totalMarketValue == Decimal.zero
        ? snapshots
        : {
            for (final entry in snapshots.entries)
              entry.key: entry.value.copyWith(
                weight: (entry.value.marketValueInBase / totalMarketValue)
                    .toDecimal(scaleOnInfinitePrecision: 8),
              ),
          };
    return HoldingSample(
      asOf: asOf,
      snapshots: Map.unmodifiable(weighted),
      issues: List.unmodifiable(issues),
    );
  }

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) =>
      _lotReader.allLotsAt(ownerUserId: ownerUserId, asOf: asOf.toUtc());

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
