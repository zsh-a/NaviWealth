import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/investment/data/transaction_repository.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_plan.dart';

import '../../../data/db/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';

/// Build a fully-populated [Transaction] for tests. The sync meta is
/// re-stamped by the repository, so the values supplied here are only
/// used for the row-level fields the repo doesn't own.
Transaction _tx({
  required String id,
  required String assetId,
  TransactionType type = TransactionType.buy,
  String accountId = 'acct-1',
  String quantity = '10',
  String price = '180',
  String currency = 'USD',
  required DateTime tradeDate,
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    assetId: assetId,
    type: type,
    quantity: Decimal.parse(quantity),
    price: Decimal.parse(price),
    currency: currency,
    tradeDate: tradeDate,
    sync: SyncMeta(
      ownerUserId: 'u',
      updatedAt: tradeDate,
      updatedByDevice: 'dev',
      hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
    ),
  );
}

TradeEntryPlan _plan(Transaction tx) =>
    TradeEntryPlan(transaction: tx, pricing: PriceProvenance.userSupplied);

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late TransactionRepository txRepo;
  late SecuritiesAssetRepository secRepo;

  setUp(() async {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    txRepo = TransactionRepository(db: db, outbox: outbox, stamper: stamper);
    secRepo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('recordTrade lastPrice salvage', () {
    test('forward-fills lastPrice + lastPriceAt on first trade', () async {
      final asset = await secRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
      );
      // The fresh securities row has no observed price yet.
      expect(asset.lastPrice, isNull);
      expect(asset.lastPriceAt, isNull);
      // Drop the seeding ops so we can assert the salvage queues an
      // assets-row update on its own.
      await outbox.ack(
        (await outbox.peekBatch()).map((o) => o.opId).toList(),
      );

      final tradeDate = DateTime.utc(2026, 5, 1);
      await txRepo.recordTrade(
        _plan(_tx(id: 't-1', assetId: asset.id, tradeDate: tradeDate)),
      );

      final reloaded = await secRepo.findById(asset.id);
      expect(reloaded!.lastPrice, Decimal.parse('180'));
      expect(
        reloaded.lastPriceAt!.millisecondsSinceEpoch,
        tradeDate.millisecondsSinceEpoch,
      );

      final ops = await outbox.peekBatch();
      // One transactions insert + one assets update.
      expect(ops, hasLength(2));
      final assetOp = ops.firstWhere((o) => o.tableName == 'assets');
      expect(assetOp.opType, OpType.update);
      expect(assetOp.rowId, asset.id);
      expect(assetOp.fieldsDiff?['last_price'], '180');
      expect(
        assetOp.fieldsDiff?['last_price_at'],
        tradeDate.toUtc().toIso8601String(),
      );
    });

    test('does not regress a fresher lastPriceAt with an older trade',
        () async {
      final asset = await secRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
      );
      // Seed an existing fresher price by recording a 2026-05-10 trade first.
      final fresh = DateTime.utc(2026, 5, 10);
      await txRepo.recordTrade(
        _plan(_tx(
          id: 't-fresh',
          assetId: asset.id,
          price: '200',
          tradeDate: fresh,
        )),
      );
      await outbox.ack(
        (await outbox.peekBatch()).map((o) => o.opId).toList(),
      );

      // Now record a backdated trade — should NOT overwrite the lastPrice.
      await txRepo.recordTrade(
        _plan(_tx(
          id: 't-stale',
          assetId: asset.id,
          price: '50',
          tradeDate: DateTime.utc(2026, 1, 1),
        )),
      );

      final reloaded = await secRepo.findById(asset.id);
      expect(reloaded!.lastPrice, Decimal.parse('200'));
      expect(
        reloaded.lastPriceAt!.millisecondsSinceEpoch,
        fresh.millisecondsSinceEpoch,
      );

      // Outbox should only have the transactions-insert op for the
      // stale trade — no asset update was queued.
      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.single.tableName, 'transactions');
    });

    test('skips dividends — they aren\'t per-share market quotes', () async {
      final asset = await secRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
      );
      await outbox.ack(
        (await outbox.peekBatch()).map((o) => o.opId).toList(),
      );

      await txRepo.recordTrade(
        _plan(_tx(
          id: 't-div',
          assetId: asset.id,
          type: TransactionType.dividend,
          quantity: '1',
          price: '0.24',
          tradeDate: DateTime.utc(2026, 5, 1),
        )),
      );

      final reloaded = await secRepo.findById(asset.id);
      expect(reloaded!.lastPrice, isNull,
          reason: 'dividend price must not be promoted to lastPrice');

      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.single.tableName, 'transactions');
    });

    test('no-ops when transaction has no assetId', () async {
      // Insert a transaction with assetId null (cash deposit). The repo
      // should write the row without any asset write or asset op.
      final tx = Transaction(
        id: 'cash-1',
        accountId: 'acct-1',
        assetId: null,
        type: TransactionType.deposit,
        quantity: Decimal.parse('1'),
        price: Decimal.parse('100'),
        currency: 'USD',
        tradeDate: DateTime.utc(2026, 5, 1),
        sync: SyncMeta(
          ownerUserId: 'u',
          updatedAt: DateTime.utc(2026, 5, 1),
          updatedByDevice: 'dev',
          hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
        ),
      );
      await txRepo.recordTrade(_plan(tx));

      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.single.tableName, 'transactions');
    });

    test('valuationAdjust still salvages the lastPrice', () async {
      final asset = await secRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
      );
      await outbox.ack(
        (await outbox.peekBatch()).map((o) => o.opId).toList(),
      );

      await txRepo.recordTrade(
        _plan(_tx(
          id: 't-val',
          assetId: asset.id,
          type: TransactionType.valuationAdjust,
          quantity: '0',
          price: '195',
          tradeDate: DateTime.utc(2026, 5, 5),
        )),
      );

      final reloaded = await secRepo.findById(asset.id);
      expect(reloaded!.lastPrice, Decimal.parse('195'));
    });
  });
}
