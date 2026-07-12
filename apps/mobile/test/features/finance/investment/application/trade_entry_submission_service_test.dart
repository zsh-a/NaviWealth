import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_mutation_receipt.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/data/ledger_lot_reader.dart';
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

  setUp(() async {
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
    await _seedTradeAccounts(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('contract errors expose stable diagnostic codes', () {
    const error = TradeSubmissionContractError(
      TradeSubmissionContractErrorCode.accountInvalid,
      'private detail',
    );

    expect(diagnosticErrorCode(error), 'trade_account_invalid');
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
    'USD buy commits under a CNY base without a historical FX rate',
    () async {
      final cnyJournal = JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );
      final cnyService = TradeEntrySubmissionService(
        db: db,
        securitiesRepo: securitiesRepo,
        tradeService: const _EchoTradeEntryService(),
        journalEntryRepo: cnyJournal,
        priceRepo: priceRepo,
        currentUserId: () async => 'u-test',
      );

      final receipt = await cnyService.submit(
        _buyRequest(
          transactionId: 'usd-buy-cny-base',
          tradeDate: DateTime.utc(2026, 7, 9),
        ),
      );

      expect(receipt.transactionId, 'usd-buy-cny-base');
      expect(receipt.journal.after.postings, hasLength(2));
      expect(await cnyJournal.getById('usd-buy-cny-base'), isNotNull);
    },
  );

  test('cross-database repository binding fails before any write', () async {
    final other = makeTestDatabase();
    addTearDown(other.close);
    final otherOutbox = DriftOutboxStore(other);
    final otherPrice = PriceRepository(
      db: other,
      outbox: otherOutbox,
      stamper: stamper,
    );

    expect(
      () => TradeEntrySubmissionService(
        db: db,
        securitiesRepo: securitiesRepo,
        tradeService: const _EchoTradeEntryService(),
        journalEntryRepo: journalEntryRepo,
        priceRepo: otherPrice,
        currentUserId: () async => 'u-test',
      ),
      throwsA(
        isA<TradeSubmissionContractError>().having(
          (error) => error.code,
          'code',
          TradeSubmissionContractErrorCode.databaseMismatch,
        ),
      ),
    );
    expect(await db.select(db.assets).get(), isEmpty);
    expect(await other.select(other.assets).get(), isEmpty);
  });

  test('non-Drift outboxes fail binding before any write', () async {
    final candidates = <OutboxStore>[InMemoryOutboxStore(), _RecordingOutbox()];
    for (final candidate in candidates) {
      final before = await _snapshot(db);
      expect(
        () => TradeEntrySubmissionService(
          db: db,
          securitiesRepo: SecuritiesAssetRepository(
            db: db,
            outbox: candidate,
            stamper: stamper,
          ),
          tradeService: const _EchoTradeEntryService(),
          journalEntryRepo: JournalEntryRepository(
            db: db,
            outbox: candidate,
            stamper: stamper,
            fxRateSource: const IdentityFxRateSource(),
            baseCurrency: 'USD',
          ),
          priceRepo: PriceRepository(
            db: db,
            outbox: candidate,
            stamper: stamper,
          ),
          currentUserId: () async => 'u-test',
        ),
        throwsA(
          isA<TradeSubmissionContractError>().having(
            (error) => error.code,
            'code',
            TradeSubmissionContractErrorCode.databaseMismatch,
          ),
        ),
      );
      expect(await candidate.depth(), 0);
      expect(await _snapshot(db), before);
    }
  });

  test('buy fee is capitalized once and drives the later sell gain', () async {
    var generatedId = 0;
    final strict = makeService(
      trades: DefaultTradeEntryService(
        market: _CountingMarket(),
        fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
        idGenerator: () => 'fee-generated-${generatedId++}',
      ),
    );
    final buy = await strict.submit(
      _buyRequest(
        transactionId: 'fee-buy',
        quantity: Decimal.fromInt(10),
        price: Decimal.fromInt(100),
        fee: Decimal.fromInt(10),
      ),
    );
    final buyAsset = buy.journal.after.postings.singleWhere(
      (posting) => posting.unit == 'us_stock:AAPL',
    );
    expect(buy.journal.after.postings, hasLength(2));
    expect(buyAsset.cost!.perUnit, Decimal.fromInt(101));
    expect(
      buy.journal.after.postings
          .singleWhere((posting) => posting.accountId == 'cash')
          .units,
      Decimal.fromInt(-1010),
    );

    final reader = LedgerLotReader(db);
    var lots = await reader.lotsAt(
      ownerUserId: 'u-test',
      accountId: 'broker',
      assetId: 'us_stock:AAPL',
      asOf: DateTime.utc(2026, 5, 1),
    );
    expect(lots.single.costPerUnit, Decimal.fromInt(101));
    expect(lots.single.remainingQuantity, Decimal.fromInt(10));

    final sell = await strict.submit(
      _buyRequest(
        transactionId: 'fee-sell',
        type: TradeType.sell,
        quantity: Decimal.fromInt(4),
        price: Decimal.fromInt(150),
        tradeDate: DateTime.utc(2026, 5, 2),
      ),
    );
    expect(
      sell.journal.after.postings
          .singleWhere((posting) => posting.units == Decimal.fromInt(-196))
          .units,
      Decimal.fromInt(-196),
    );

    await strict.undoMutation(sell);
    lots = await reader.lotsAt(
      ownerUserId: 'u-test',
      accountId: 'broker',
      assetId: 'us_stock:AAPL',
      asOf: DateTime.utc(2026, 5, 2),
    );
    expect(lots.single.remainingQuantity, Decimal.fromInt(10));
    await strict.undoMutation(buy);
    expect(
      await reader.lotsAt(
        ownerUserId: 'u-test',
        accountId: 'broker',
        assetId: 'us_stock:AAPL',
        asOf: DateTime.utc(2026, 5, 2),
      ),
      isEmpty,
    );
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
      await _seedTradeAccounts(trackingDb);

      final prepared = await trackingService.prepare(
        _buyRequest(omitPrice: true),
      );

      expect(market.calls, 1);
      expect(market.transactionDepthAtLookup, 0);
      expect(market.persistedRowsAtLookup, 0);
      expect(prepared.frozenPrice, Decimal.fromInt(123));
      expect(prepared.transactionId, 'tx-test');
      expect(prepared.priceProvenance.wasBackfilled, isTrue);
      expect(await trackingDb.select(trackingDb.assets).get(), isEmpty);

      final receipt = await trackingService.commit(prepared);
      expect(receipt.price!.after.perUnit, Decimal.fromInt(123));
      expect(market.calls, 1);
    },
  );

  test(
    'prepared sell revalidates fresh lots and balance before writing',
    () async {
      final market = _CountingMarket();
      final strict = makeService(
        trades: DefaultTradeEntryService(
          market: market,
          fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'opening-buy',
          quantity: Decimal.fromInt(10),
        ),
      );
      final prepared = await strict.prepare(
        _buyRequest(
          transactionId: 'planned-sell',
          type: TradeType.sell,
          quantity: Decimal.fromInt(10),
          tradeDate: DateTime.utc(2026, 5, 2),
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'intervening-sell',
          type: TradeType.sell,
          quantity: Decimal.fromInt(5),
          tradeDate: DateTime.utc(2026, 5, 2),
        ),
      );
      final before = await _snapshot(db);

      await expectLater(
        strict.commit(prepared),
        throwsA(
          isA<TradeSubmissionContractError>().having(
            (error) => error.code,
            'code',
            TradeSubmissionContractErrorCode.insufficientFreshHoldings,
          ),
        ),
      );

      expect(await _snapshot(db), before);
      expect(market.calls, 0);
    },
  );

  test(
    'sell older than a new relevant movement is rejected atomically',
    () async {
      final market = _CountingMarket();
      final strict = makeService(
        trades: DefaultTradeEntryService(
          market: market,
          fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'opening-buy',
          quantity: Decimal.fromInt(10),
        ),
      );
      final prepared = await strict.prepare(
        _buyRequest(
          transactionId: 'planned-sell',
          type: TradeType.sell,
          quantity: Decimal.one,
          tradeDate: DateTime.utc(2026, 5, 2),
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'later-buy',
          quantity: Decimal.one,
          tradeDate: DateTime.utc(2026, 5, 3),
        ),
      );
      final before = await _snapshot(db);

      await expectLater(
        strict.commit(prepared),
        throwsA(
          isA<TradeSubmissionContractError>().having(
            (error) => error.code,
            'code',
            TradeSubmissionContractErrorCode.backdatedSell,
          ),
        ),
      );

      expect(await _snapshot(db), before);
      expect(market.calls, 0);
    },
  );

  test('account changes after prepare fail before trade writes', () async {
    final prepared = await service.prepare(_buyRequest());
    await (db.update(db.accounts)..where((row) => row.id.equals('broker')))
        .write(const AccountsCompanion(archived: Value(true)));

    await expectLater(
      service.commit(prepared),
      throwsA(
        isA<TradeSubmissionContractError>().having(
          (error) => error.code,
          'code',
          TradeSubmissionContractErrorCode.accountInvalid,
        ),
      ),
    );

    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.prices).get(), isEmpty);
  });

  test('incompatible existing asset structure fails without writes', () async {
    final cases =
        <
          ({
            String label,
            AssetType type,
            String currency,
            String market,
            String symbol,
          })
        >[
          (
            label: 'type',
            type: AssetType.etf,
            currency: 'USD',
            market: 'us_stock',
            symbol: 'AAPL',
          ),
          (
            label: 'currency',
            type: AssetType.stock,
            currency: 'CNY',
            market: 'us_stock',
            symbol: 'AAPL',
          ),
          (
            label: 'market',
            type: AssetType.stock,
            currency: 'USD',
            market: 'cn_a',
            symbol: 'AAPL',
          ),
          (
            label: 'symbol',
            type: AssetType.stock,
            currency: 'USD',
            market: 'us_stock',
            symbol: 'aapl',
          ),
        ];

    for (final candidate in cases) {
      await _insertRawAsset(
        db,
        type: candidate.type,
        currency: candidate.currency,
        market: candidate.market,
        symbol: candidate.symbol,
      );
      final before = await _snapshot(db);

      await expectLater(
        service.submit(_buyRequest(transactionId: 'struct-${candidate.label}')),
        throwsA(
          isA<TradeSubmissionContractError>().having(
            (error) => error.code,
            'code',
            TradeSubmissionContractErrorCode.assetInvalid,
          ),
        ),
        reason: candidate.label,
      );

      expect(await _snapshot(db), before, reason: candidate.label);
      expect(await outbox.depth(), 0, reason: candidate.label);
      await (db.delete(
        db.assets,
      )..where((row) => row.id.equals('us_stock:AAPL'))).go();
    }
  });

  test('compatible existing asset allows name and ISIN enrichment', () async {
    await _insertRawAsset(
      db,
      type: AssetType.stock,
      currency: 'usd',
      market: 'us_stock',
      symbol: 'AAPL',
      name: 'Old name',
      isin: 'OLD-ISIN',
    );

    final receipt = await service.submit(
      _buyRequest(
        transactionId: 'metadata-enrichment',
        assetName: 'Apple Inc.',
        isin: 'US0378331005',
      ),
    );

    final asset = (await securitiesRepo.findById('us_stock:AAPL'))!;
    expect(receipt.assetId, 'us_stock:AAPL');
    expect(asset.symbol, 'AAPL');
    expect(asset.market, 'us_stock');
    expect(asset.type, AssetType.stock);
    expect(asset.currency, 'USD');
    expect(asset.name, 'Apple Inc.');
    expect(asset.isin, 'US0378331005');
    expect(await journalEntryRepo.getById('metadata-enrichment'), isNotNull);
  });

  test('sell rejects an otherwise eligible lot in another currency', () async {
    final cnyJournal = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );
    final cnyService = TradeEntrySubmissionService(
      db: db,
      securitiesRepo: securitiesRepo,
      tradeService: DefaultTradeEntryService(
        market: _CountingMarket(),
        fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      ),
      journalEntryRepo: cnyJournal,
      priceRepo: priceRepo,
      currentUserId: () async => 'u-test',
    );
    final strict = makeService(
      trades: DefaultTradeEntryService(
        market: _CountingMarket(),
        fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      ),
    );
    await cnyService.submit(
      _buyRequest(
        transactionId: 'cny-lot',
        currency: 'CNY',
        useCashAccount: false,
      ),
    );
    final prepared = await strict.prepare(
      _buyRequest(
        transactionId: 'usd-close',
        type: TradeType.sell,
        tradeDate: DateTime.utc(2026, 5, 2),
      ),
    );
    final before = await _snapshot(db);

    await expectLater(
      strict.commit(prepared),
      throwsA(
        isA<TradeSubmissionContractError>().having(
          (error) => error.code,
          'code',
          TradeSubmissionContractErrorCode.lotCurrencyMismatch,
        ),
      ),
    );
    expect(await _snapshot(db), before);
  });

  test('final plan mutations fail before any write', () async {
    final mutations = <(String, PlannedTrade Function(PlannedTrade))>[
      ('id', (tx) => _copyTrade(tx, id: 'changed-id')),
      ('account', (tx) => _copyTrade(tx, accountId: 'changed-account')),
      ('asset', (tx) => _copyTrade(tx, assetId: 'us_stock:MSFT')),
      ('type', (tx) => _copyTrade(tx, type: TradeType.sell)),
      ('quantity', (tx) => _copyTrade(tx, quantity: tx.quantity + Decimal.one)),
      ('price', (tx) => _copyTrade(tx, price: tx.price + Decimal.one)),
      ('currency', (tx) => _copyTrade(tx, currency: 'CNY')),
      (
        'date',
        (tx) => _copyTrade(
          tx,
          tradeDate: tx.tradeDate.add(const Duration(days: 1)),
        ),
      ),
      ('settle', (tx) => _copyTrade(tx, settleDate: tx.tradeDate)),
      ('fee', (tx) => _copyTrade(tx, fee: Decimal.one)),
      ('tax', (tx) => _copyTrade(tx, tax: Decimal.one)),
      ('counter', (tx) => _copyTrade(tx, counterAccountId: 'cash')),
      ('note', (tx) => _copyTrade(tx, note: 'changed')),
    ];

    for (final (label, mutate) in mutations) {
      final probe = _ProbingPriceRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final strict = makeService(
        prices: probe,
        trades: _MutateFinalPlanService(mutate),
      );
      final prepared = await strict.prepare(
        _buyRequest(transactionId: 'mutated-$label'),
      );
      final before = await _snapshot(db);

      await expectLater(
        strict.commit(prepared),
        throwsA(
          isA<TradeSubmissionContractError>().having(
            (error) => error.code,
            'code',
            TradeSubmissionContractErrorCode.identityMismatch,
          ),
        ),
        reason: label,
      );

      expect(probe.calls, 0, reason: label);
      expect(await _snapshot(db), before, reason: label);
    }
  });

  test('mutated created-lot cost fails before any write', () async {
    final probe = _ProbingPriceRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final strict = makeService(
      prices: probe,
      trades: _MutateFinalBuyLotService(),
    );
    final prepared = await strict.prepare(
      _buyRequest(transactionId: 'mutated-lot', fee: Decimal.fromInt(10)),
    );
    final before = await _snapshot(db);

    await expectLater(
      strict.commit(prepared),
      throwsA(
        isA<TradeSubmissionContractError>().having(
          (error) => error.code,
          'code',
          TradeSubmissionContractErrorCode.identityMismatch,
        ),
      ),
    );
    expect(probe.calls, 0);
    expect(await _snapshot(db), before);
  });

  test(
    'multi-lot sell persists, reduces, and fully restores exact lots',
    () async {
      var generatedId = 0;
      final strict = makeService(
        trades: DefaultTradeEntryService(
          market: _CountingMarket(),
          fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
          idGenerator: () => 'generated-${generatedId++}',
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'lot-buy-1',
          quantity: Decimal.fromInt(5),
          price: Decimal.fromInt(100),
          tradeDate: DateTime.utc(2026, 5, 1),
        ),
      );
      await strict.submit(
        _buyRequest(
          transactionId: 'lot-buy-2',
          quantity: Decimal.fromInt(5),
          price: Decimal.fromInt(120),
          tradeDate: DateTime.utc(2026, 5, 2),
        ),
      );

      final receipt = await strict.submit(
        _buyRequest(
          transactionId: 'multi-sell',
          type: TradeType.sell,
          quantity: Decimal.fromInt(7),
          price: Decimal.fromInt(150),
          tradeDate: DateTime.utc(2026, 5, 3),
        ),
      );
      final closing = receipt.journal.after.postings
          .where(
            (posting) =>
                posting.accountId == 'broker' &&
                posting.unit == 'us_stock:AAPL' &&
                posting.units < Decimal.zero,
          )
          .toList();
      expect(closing, hasLength(2));
      expect(closing.map((posting) => posting.units), [
        Decimal.fromInt(-5),
        Decimal.fromInt(-2),
      ]);
      expect(closing.map((posting) => posting.cost?.perUnit), [
        Decimal.fromInt(100),
        Decimal.fromInt(120),
      ]);
      final gains = receipt.journal.after.postings.singleWhere(
        (posting) => posting.units == Decimal.fromInt(-310),
      );
      expect(gains.units, Decimal.fromInt(-310));

      final reader = LedgerLotReader(db);
      var lots = await reader.lotsAt(
        ownerUserId: 'u-test',
        accountId: 'broker',
        assetId: 'us_stock:AAPL',
        asOf: DateTime.utc(2026, 5, 3),
      );
      expect(lots.map((lot) => lot.remainingQuantity), [
        Decimal.zero,
        Decimal.fromInt(3),
      ]);
      expect(
        await strict.balanceByAccountUnit('broker', 'us_stock:AAPL'),
        Decimal.fromInt(3),
      );

      await strict.undoMutation(receipt);
      lots = await reader.lotsAt(
        ownerUserId: 'u-test',
        accountId: 'broker',
        assetId: 'us_stock:AAPL',
        asOf: DateTime.utc(2026, 5, 3),
      );
      expect(lots.map((lot) => lot.remainingQuantity), [
        Decimal.fromInt(5),
        Decimal.fromInt(5),
      ]);
      expect(
        await strict.balanceByAccountUnit('broker', 'us_stock:AAPL'),
        Decimal.fromInt(10),
      );

      await db.customStatement('''
        CREATE TRIGGER reject_multi_sell_price
        BEFORE INSERT ON prices
        WHEN NEW.id = 'multi-sell-trigger'
        BEGIN SELECT RAISE(ABORT, 'multi sell price failed'); END
      ''');
      final beforeTrigger = await _snapshot(db);
      await expectLater(
        strict.submit(
          _buyRequest(
            transactionId: 'multi-sell-trigger',
            type: TradeType.sell,
            quantity: Decimal.fromInt(7),
            price: Decimal.fromInt(150),
            tradeDate: DateTime.utc(2026, 5, 3),
          ),
        ),
        throwsA(anything),
      );
      expect(await _snapshot(db), beforeTrigger);
      await db.customStatement('DROP TRIGGER reject_multi_sell_price');

      final casReceipt = await strict.submit(
        _buyRequest(
          transactionId: 'multi-sell-cas',
          type: TradeType.sell,
          quantity: Decimal.fromInt(7),
          price: Decimal.fromInt(150),
          tradeDate: DateTime.utc(2026, 5, 3),
        ),
      );
      final secondClose = casReceipt.journal.after.postings
          .where(
            (posting) =>
                posting.accountId == 'broker' &&
                posting.unit == 'us_stock:AAPL' &&
                posting.units < Decimal.zero,
          )
          .last;
      await (db.update(
        db.postings,
      )..where((row) => row.id.equals(secondClose.id))).write(
        PostingsCompanion(
          units: Value(Decimal.fromInt(-1)),
          updatedAt: Value(DateTime.utc(2027)),
          updatedByDevice: const Value('remote'),
          hlc: const Value(
            Hlc(wallMillis: 30_000, counter: 0, nodeId: 'remote'),
          ),
        ),
      );
      final beforeCasUndo = await _snapshot(db);
      await expectLater(
        strict.undoMutation(casReceipt),
        throwsA(isA<JournalMutationConflict>()),
      );
      expect(await _snapshot(db), beforeCasUndo);
    },
  );
}

TradeEntrySubmissionRequest _buyRequest({
  String transactionId = 'tx-test',
  TradeType type = TradeType.buy,
  Decimal? quantity,
  DateTime? tradeDate,
  Decimal? price,
  bool omitPrice = false,
  String assetName = 'Apple Inc.',
  String currency = 'USD',
  bool useCashAccount = true,
  Decimal? fee,
  String? isin,
}) {
  return TradeEntrySubmissionRequest(
    transactionId: transactionId,
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    assetType: AssetType.stock,
    assetCurrency: 'USD',
    assetName: assetName,
    isin: isin,
    type: type,
    accountId: 'broker',
    cashAccountId: useCashAccount ? 'cash' : null,
    quantity: quantity ?? Decimal.fromInt(10),
    price: omitPrice ? null : (price ?? Decimal.fromInt(150)),
    currency: currency,
    tradeDate: tradeDate ?? DateTime.utc(2026, 5, 1),
    fee: fee,
    defaultNarration: (asset) => 'Buy 10 ${asset.symbol} (${asset.name})',
  );
}

Future<void> _insertRawAsset(
  AppDatabase database, {
  required AssetType type,
  required String currency,
  required String market,
  required String symbol,
  String? name,
  String? isin,
}) => database
    .into(database.assets)
    .insert(
      AssetsCompanion.insert(
        id: 'us_stock:AAPL',
        type: type,
        symbol: symbol,
        currency: currency,
        name: Value(name),
        market: Value(market),
        isin: Value(isin),
        ownerUserId: 'u-test',
        updatedAt: DateTime.utc(2026),
        updatedByDevice: 'dev-test',
        hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
      ),
    );

Future<void> _seedTradeAccounts(AppDatabase database) async {
  for (final (id, type) in const [
    ('broker', AccountCategory.broker),
    ('cash', AccountCategory.cash),
  ]) {
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            type: type,
            name: id,
            currency: 'USD',
            category: const Value(AccountSide.asset),
            ownerUserId: 'u-test',
            updatedAt: DateTime.utc(2026),
            updatedByDevice: 'dev-test',
            hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
          ),
        );
  }
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
    final price = draft.price ?? Decimal.one;
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId ?? 'tx-test',
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: price,
        currency: draft.currency,
        tradeDate: draft.tradeDate,
        fee: draft.fee,
        tax: draft.tax,
        note: draft.note,
      ),
      createdLot: draft.type == TradeType.buy
          ? Lot(
              id: '${draft.transactionId}-lot',
              openingTransactionId: draft.transactionId!,
              accountId: draft.accountId,
              assetId: draft.asset.id,
              currency: draft.currency,
              originalQuantity: draft.quantity,
              remainingQuantity: draft.quantity,
              costPerUnit:
                  ((draft.quantity * price + draft.feeOrZero) / draft.quantity)
                      .toDecimal(scaleOnInfinitePrecision: 16),
              openedAt: draft.tradeDate,
            )
          : null,
      pricing: PriceProvenance.userSupplied,
    );
  }
}

final class _MutateFinalPlanService extends _EchoTradeEntryService {
  _MutateFinalPlanService(this.mutate);

  final PlannedTrade Function(PlannedTrade trade) mutate;
  var calls = 0;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    final plan = await super.buildPlan(draft, openLots: openLots);
    calls += 1;
    if (calls == 1) return plan;
    return TradeEntryPlan(
      trade: mutate(plan.trade),
      createdLot: plan.createdLot,
      updatedLots: plan.updatedLots,
      realizedPnL: plan.realizedPnL,
      unfulfilledQuantity: plan.unfulfilledQuantity,
      pricing: plan.pricing,
    );
  }
}

final class _MutateFinalBuyLotService extends _EchoTradeEntryService {
  var calls = 0;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    final plan = await super.buildPlan(draft, openLots: openLots);
    calls += 1;
    if (calls == 1) return plan;
    return TradeEntryPlan(
      trade: plan.trade,
      createdLot: plan.createdLot!.copyWith(
        costPerUnit: plan.createdLot!.costPerUnit + Decimal.one,
      ),
      updatedLots: plan.updatedLots,
      realizedPnL: plan.realizedPnL,
      unfulfilledQuantity: plan.unfulfilledQuantity,
      pricing: plan.pricing,
    );
  }
}

PlannedTrade _copyTrade(
  PlannedTrade trade, {
  String? id,
  String? accountId,
  String? assetId,
  TradeType? type,
  Decimal? quantity,
  Decimal? price,
  String? currency,
  DateTime? tradeDate,
  DateTime? settleDate,
  Decimal? fee,
  Decimal? tax,
  String? counterAccountId,
  String? note,
}) => PlannedTrade(
  id: id ?? trade.id,
  accountId: accountId ?? trade.accountId,
  assetId: assetId ?? trade.assetId,
  type: type ?? trade.type,
  quantity: quantity ?? trade.quantity,
  price: price ?? trade.price,
  currency: currency ?? trade.currency,
  tradeDate: tradeDate ?? trade.tradeDate,
  settleDate: settleDate ?? trade.settleDate,
  fee: fee ?? trade.fee,
  tax: tax ?? trade.tax,
  counterAccountId: counterAccountId ?? trade.counterAccountId,
  note: note ?? trade.note,
);

final class _ProbingPriceRepository extends PriceRepository {
  _ProbingPriceRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
  });

  var calls = 0;

  @override
  Future<PriceMutationReceipt> upsertWithReceipt({
    required String id,
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
    bool allowZero = false,
  }) {
    calls += 1;
    return super.upsertWithReceipt(
      id: id,
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: observedOn,
      perUnit: perUnit,
      source: source,
      allowZero: allowZero,
    );
  }
}

final class _RecordingOutbox implements OutboxStore {
  final items = <({String table, String rowId})>[];

  @override
  Future<int> depth() async => items.length;

  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    items.add((table: table, rowId: rowId));
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

class _CountingMarket implements MarketDataService {
  int calls = 0;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    calls += 1;
    throw StateError('market data must not run for frozen explicit prices');
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
