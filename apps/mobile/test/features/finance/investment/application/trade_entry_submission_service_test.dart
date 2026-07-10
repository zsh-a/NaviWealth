import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_mutation_receipt.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/default_trade_entry_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late DriftOutboxStore outbox;
  late MutationStamper stamper;
  late SecuritiesAssetRepository securitiesRepo;
  late JournalEntryRepository journalEntryRepo;
  late PriceRepository priceRepo;
  late TradeEntrySubmissionService service;

  TradeEntrySubmissionService makeService({
    PriceRepository? prices,
    TradeEntryService? trades,
  }) {
    return TradeEntrySubmissionService(
      db: db,
      securitiesRepo: securitiesRepo,
      tradeService: trades ?? const _EchoTradeEntryService(),
      journalEntryRepo: journalEntryRepo,
      priceRepo: prices ?? priceRepo,
      currentUserId: () async => 'u-test',
    );
  }

  setUp(() {
    db = makeTestDatabase();
    outbox = DriftOutboxStore(db);
    stamper = makeStubStamper();
    securitiesRepo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    );
    priceRepo = PriceRepository(db: db, outbox: outbox, stamper: stamper);
    service = makeService();
  });

  tearDown(() async {
    await db.close();
  });

  test('success returns a versioned receipt for every committed row', () async {
    final receipt = await service.submit(_buyRequest());

    expect(receipt.transactionId, 'tx-test');
    expect(receipt.assetId, 'us_stock:AAPL');
    expect(receipt.journal.after.entry.id, 'tx-test');
    expect(receipt.journal.after.postings, hasLength(2));
    expect(receipt.price, isNotNull);
    expect(receipt.price!.after.id, 'tx-test');
    expect(receipt.price!.after.perUnit, Decimal.fromInt(150));
    expect(receipt.price!.after.source, 'trade');

    final assets = await db.select(db.assets).get();
    expect(assets.single.name, 'Apple Inc.');
    expect(await outbox.depth(), 5);
  });

  test(
    'price failure rolls security, journal, postings, price, and outbox back',
    () async {
      await securitiesRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
        name: 'Original Apple',
      );
      await db.customStatement('DELETE FROM op_outbox');
      final before = await _snapshot(db);
      final failingPriceRepo = _FailingPriceRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final failingService = makeService(prices: failingPriceRepo);

      await expectLater(
        failingService.submit(_buyRequest(assetName: 'Updated Apple')),
        throwsA(isA<StateError>()),
      );

      expect(failingPriceRepo.sawUpdatedAsset, isTrue);
      expect(failingPriceRepo.sawJournal, isTrue);
      expect(failingPriceRepo.sawPostings, isTrue);
      expect(failingPriceRepo.sawPrice, isTrue);
      expect(failingPriceRepo.sawOutbox, isTrue);
      expect(await _snapshot(db), before);
    },
  );

  test(
    'Undo restores an existing price observation exactly in content',
    () async {
      final seeded = await priceRepo.upsertWithReceipt(
        id: 'tx-test',
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: DateTime.utc(2026, 5, 1),
        perUnit: Decimal.fromInt(100),
        source: 'manual',
      );
      await db.customStatement('DELETE FROM op_outbox');

      final receipt = await service.submit(_buyRequest());
      expect(receipt.price!.before, seeded.after);
      expect(receipt.price!.after.perUnit, Decimal.fromInt(150));

      await service.undoMutation(receipt);

      final restored = (await priceRepo.findById('tx-test'))!;
      expect(restored.unit, seeded.after.unit);
      expect(restored.quoteCurrency, seeded.after.quoteCurrency);
      expect(restored.observedOn, seeded.after.observedOn);
      expect(restored.perUnit, Decimal.fromInt(100));
      expect(restored.source, 'manual');
      expect(restored.sync.deletedAt, isNull);
      expect(await journalEntryRepo.getById('tx-test'), isNull);
    },
  );

  test(
    'Undo tombstones new journal and price rows but preserves security metadata',
    () async {
      final receipt = await service.submit(_buyRequest());
      final assetBeforeUndo = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(receipt.assetId))).getSingle();

      await service.undoMutation(receipt);

      final entry = await (db.select(
        db.journalEntries,
      )..where((row) => row.id.equals(receipt.transactionId))).getSingle();
      expect(entry.deletedAt, isNotNull);
      final postings =
          await (db.select(db.postings)..where(
                (row) => row.journalEntryId.equals(receipt.transactionId),
              ))
              .get();
      expect(postings.every((posting) => posting.deletedAt != null), isTrue);
      final price = (await priceRepo.findById(receipt.transactionId))!;
      expect(price.sync.deletedAt, isNotNull);
      expect(
        await priceRepo.latestAt(
          unit: receipt.assetId,
          quoteCurrency: 'USD',
          asOf: DateTime.utc(2026, 5, 2),
        ),
        isNull,
      );
      expect(
        await (db.select(
          db.assets,
        )..where((row) => row.id.equals(receipt.assetId))).getSingle(),
        assetBeforeUndo,
      );
    },
  );

  test('later journal mutation makes Undo refuse atomically', () async {
    final receipt = await service.submit(_buyRequest());
    await db.customStatement('DELETE FROM op_outbox');
    await (db.update(
      db.journalEntries,
    )..where((row) => row.id.equals(receipt.transactionId))).write(
      JournalEntriesCompanion(
        narration: const Value('Later journal edit'),
        updatedAt: Value(DateTime.utc(2027)),
        updatedByDevice: const Value('remote'),
        hlc: const Value(Hlc(wallMillis: 20_001, counter: 0, nodeId: 'remote')),
      ),
    );
    await _expectUndoConflictPreservesState(service, receipt, db);
  });

  test('later posting mutation makes Undo refuse atomically', () async {
    final receipt = await service.submit(_buyRequest());
    await db.customStatement('DELETE FROM op_outbox');
    final postingId = receipt.journal.after.postings.first.id;
    await (db.update(
      db.postings,
    )..where((row) => row.id.equals(postingId))).write(
      PostingsCompanion(
        units: Value(Decimal.fromInt(11)),
        updatedAt: Value(DateTime.utc(2027)),
        updatedByDevice: const Value('remote'),
        hlc: const Value(Hlc(wallMillis: 20_002, counter: 0, nodeId: 'remote')),
      ),
    );
    await _expectUndoConflictPreservesState(service, receipt, db);
  });

  test('later price mutation makes Undo refuse atomically', () async {
    final receipt = await service.submit(_buyRequest());
    await db.customStatement('DELETE FROM op_outbox');
    await (db.update(
      db.prices,
    )..where((row) => row.id.equals(receipt.transactionId))).write(
      PricesCompanion(
        perUnit: Value(Decimal.fromInt(175)),
        updatedAt: Value(DateTime.utc(2027)),
        updatedByDevice: const Value('remote'),
        hlc: const Value(Hlc(wallMillis: 20_003, counter: 0, nodeId: 'remote')),
      ),
    );
    await _expectUndoConflictPreservesState(service, receipt, db);
  });

  test(
    'omitted price market lookup runs before any database transaction',
    () async {
      final trackingDb = _TrackingAppDatabase();
      addTearDown(trackingDb.close);
      final trackingOutbox = DriftOutboxStore(trackingDb);
      final trackingStamper = makeStubStamper();
      final market = _InspectingMarket(trackingDb);
      final trackingService = TradeEntrySubmissionService(
        db: trackingDb,
        securitiesRepo: SecuritiesAssetRepository(
          db: trackingDb,
          outbox: trackingOutbox,
          stamper: trackingStamper,
        ),
        tradeService: DefaultTradeEntryService(
          market: market,
          fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
          idGenerator: () => 'tx-market',
        ),
        journalEntryRepo: JournalEntryRepository(
          db: trackingDb,
          outbox: trackingOutbox,
          stamper: trackingStamper,
          fxRateSource: const IdentityFxRateSource(),
          baseCurrency: 'USD',
        ),
        priceRepo: PriceRepository(
          db: trackingDb,
          outbox: trackingOutbox,
          stamper: trackingStamper,
        ),
        currentUserId: () async => 'u-test',
      );

      final prepared = await trackingService.prepare(
        _buyRequest(omitPrice: true),
      );

      expect(market.calls, 1);
      expect(market.transactionDepthAtLookup, 0);
      expect(market.persistedRowsAtLookup, 0);
      expect(prepared.plan.trade.price, Decimal.fromInt(123));
      expect(await trackingDb.select(trackingDb.assets).get(), isEmpty);

      final receipt = await trackingService.commit(prepared);
      expect(receipt.price!.after.perUnit, Decimal.fromInt(123));
    },
  );
}

TradeEntrySubmissionRequest _buyRequest({
  Decimal? price,
  bool omitPrice = false,
  String assetName = 'Apple Inc.',
}) {
  return TradeEntrySubmissionRequest(
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    assetType: AssetType.stock,
    assetCurrency: 'USD',
    assetName: assetName,
    type: TradeType.buy,
    accountId: 'broker',
    cashAccountId: 'cash',
    quantity: Decimal.fromInt(10),
    price: omitPrice ? null : (price ?? Decimal.fromInt(150)),
    currency: 'USD',
    tradeDate: DateTime.utc(2026, 5, 1),
    defaultNarration: (asset) => 'Buy 10 ${asset.symbol} (${asset.name})',
  );
}

Future<void> _expectUndoConflictPreservesState(
  TradeEntrySubmissionService service,
  TradeMutationReceipt receipt,
  AppDatabase db,
) async {
  final before = await _snapshot(db);

  await expectLater(
    service.undoMutation(receipt),
    throwsA(
      anyOf(isA<JournalMutationConflict>(), isA<PriceMutationConflict>()),
    ),
  );

  expect(await _snapshot(db), before);
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
  const tables = <(String, String)>[
    ('assets', 'id'),
    ('journal_entries', 'id'),
    ('postings', 'id'),
    ('prices', 'id'),
    ('op_outbox', 'op_id'),
  ];
  final snapshot = <String, List<Map<String, Object?>>>{};
  for (final (table, orderBy) in tables) {
    final rows = await db
        .customSelect('SELECT * FROM $table ORDER BY $orderBy')
        .get();
    snapshot[table] = [
      for (final row in rows) Map<String, Object?>.from(row.data),
    ];
  }
  return snapshot;
}

class _EchoTradeEntryService implements TradeEntryService {
  const _EchoTradeEntryService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId ?? 'tx-test',
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: draft.price ?? Decimal.one,
        currency: draft.currency,
        tradeDate: draft.tradeDate,
        fee: draft.fee,
        tax: draft.tax,
        note: draft.note,
      ),
      pricing: PriceProvenance.userSupplied,
    );
  }
}

class _FailingPriceRepository extends PriceRepository {
  _FailingPriceRepository({
    required this.db,
    required super.outbox,
    required super.stamper,
  }) : super(db: db);

  final AppDatabase db;
  bool sawUpdatedAsset = false;
  bool sawJournal = false;
  bool sawPostings = false;
  bool sawPrice = false;
  bool sawOutbox = false;

  @override
  Future<PriceMutationReceipt> upsertWithReceipt({
    required String id,
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
    bool allowZero = false,
  }) async {
    final asset = await (db.select(
      db.assets,
    )..where((row) => row.id.equals('us_stock:AAPL'))).getSingle();
    sawUpdatedAsset = asset.name == 'Updated Apple';
    sawJournal = (await db.select(db.journalEntries).get()).isNotEmpty;
    sawPostings = (await db.select(db.postings).get()).isNotEmpty;
    await super.upsertWithReceipt(
      id: id,
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: observedOn,
      perUnit: perUnit,
      source: source,
      allowZero: allowZero,
    );
    sawPrice = (await db.select(db.prices).get()).isNotEmpty;
    sawOutbox =
        (await db.customSelect('SELECT * FROM op_outbox').get()).isNotEmpty;
    throw StateError('price write failed');
  }
}

class _TrackingAppDatabase extends AppDatabase {
  _TrackingAppDatabase()
    : super(DatabaseConnection(NativeDatabase.memory(logStatements: false)));

  int transactionDepth = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    transactionDepth += 1;
    try {
      return await super.transaction(action, requireNew: requireNew);
    } finally {
      transactionDepth -= 1;
    }
  }
}

class _InspectingMarket implements MarketDataService {
  _InspectingMarket(this.db);

  final _TrackingAppDatabase db;
  int calls = 0;
  int? transactionDepthAtLookup;
  int? persistedRowsAtLookup;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    calls += 1;
    transactionDepthAtLookup = db.transactionDepth;
    persistedRowsAtLookup =
        (await db.select(db.assets).get()).length +
        (await db.select(db.journalEntries).get()).length +
        (await db.select(db.postings).get()).length +
        (await db.select(db.prices).get()).length;
    final price = Decimal.fromInt(123);
    return MarketResponse(
      data: [
        HistoricalBar(
          symbol: symbol,
          asOf: DateTime.utc(2026, 5, 1),
          open: price,
          high: price,
          low: price,
          close: price,
        ),
      ],
      freshness: DataFreshness.live,
      source: 'test-market',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}
