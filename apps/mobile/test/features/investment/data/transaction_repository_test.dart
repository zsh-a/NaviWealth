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

  // FIR-124: cash transfers must land on both accounts atomically.
  group('recordTransfer (FIR-124)', () {
    test('writes both legs in one transaction with a shared group id',
        () async {
      final tradeDate = DateTime.utc(2026, 5, 1);
      final record = await txRepo.recordTransfer(
        fromAccountId: 'acct-A',
        toAccountId: 'acct-B',
        amount: Decimal.parse('100'),
        currency: 'CNY',
        tradeDate: tradeDate,
      );

      expect(record.transferGroupId, isNotEmpty);
      expect(record.outgoing.transferGroupId, record.transferGroupId);
      expect(record.incoming.transferGroupId, record.transferGroupId);

      // Outgoing leg lives on the source account, incoming on the target;
      // counter-account points the other way on each row.
      expect(record.outgoing.type, TransactionType.transferOut);
      expect(record.outgoing.accountId, 'acct-A');
      expect(record.outgoing.counterAccountId, 'acct-B');

      expect(record.incoming.type, TransactionType.transferIn);
      expect(record.incoming.accountId, 'acct-B');
      expect(record.incoming.counterAccountId, 'acct-A');

      // Cash-flow shape: notional = quantity * price = amount.
      expect(record.outgoing.quantity, Decimal.one);
      expect(record.outgoing.price, Decimal.parse('100'));
      expect(record.incoming.quantity, Decimal.one);
      expect(record.incoming.price, Decimal.parse('100'));

      // Both legs must hit the outbox so peers see both halves.
      final ops = await outbox.peekBatch();
      expect(ops, hasLength(2));
      expect(ops.every((o) => o.tableName == 'transactions'), isTrue);
      expect(ops.every((o) => o.opType == OpType.insert), isTrue);
      final emittedIds = ops.map((o) => o.rowId).toSet();
      expect(
        emittedIds,
        containsAll(<String>[record.outgoing.id, record.incoming.id]),
      );
      // The outbox payload must carry the group id so the server-side
      // materialised payload retains the link after sync.
      for (final op in ops) {
        expect(
          op.fieldsDiff?['transfer_group_id'],
          record.transferGroupId,
        );
      }
    });

    test('balances the two account cash positions to zero', () async {
      final record = await txRepo.recordTransfer(
        fromAccountId: 'acct-A',
        toAccountId: 'acct-B',
        amount: Decimal.parse('250.50'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
      );

      Decimal accountCash(String accountId) {
        final notionalIn = (record.incoming.accountId == accountId)
            ? record.incoming.quantity * record.incoming.price
            : Decimal.zero;
        final notionalOut = (record.outgoing.accountId == accountId)
            ? record.outgoing.quantity * record.outgoing.price
            : Decimal.zero;
        return notionalIn - notionalOut;
      }

      // From: -250.50, To: +250.50. Their sum is zero — the global cash
      // pool is unchanged, which is the whole point of an atomic transfer.
      expect(accountCash('acct-A'), Decimal.parse('-250.50'));
      expect(accountCash('acct-B'), Decimal.parse('250.50'));
      expect(
        accountCash('acct-A') + accountCash('acct-B'),
        Decimal.zero,
      );
    });

    test('charges fee to the outgoing leg only', () async {
      final record = await txRepo.recordTransfer(
        fromAccountId: 'acct-A',
        toAccountId: 'acct-B',
        amount: Decimal.parse('100'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
        fee: Decimal.parse('2.5'),
      );
      expect(record.outgoing.fee, Decimal.parse('2.5'));
      expect(record.incoming.fee, isNull);
    });

    test('rejects same-account or non-positive transfers', () async {
      expect(
        () => txRepo.recordTransfer(
          fromAccountId: 'acct-A',
          toAccountId: 'acct-A',
          amount: Decimal.parse('100'),
          currency: 'CNY',
          tradeDate: DateTime.utc(2026, 5, 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => txRepo.recordTransfer(
          fromAccountId: 'acct-A',
          toAccountId: 'acct-B',
          amount: Decimal.zero,
          currency: 'CNY',
          tradeDate: DateTime.utc(2026, 5, 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => txRepo.recordTransfer(
          fromAccountId: 'acct-A',
          toAccountId: 'acct-B',
          amount: Decimal.parse('100'),
          currency: 'CNY',
          tradeDate: DateTime.utc(2026, 5, 1),
          fee: Decimal.parse('-1'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // FIR-124: deleting one leg of a transfer must tombstone the partner so
  // the pair never goes out of balance after a half-undo.
  group('softDeleteById cascades within a transfer group', () {
    test('soft-deleting one leg also soft-deletes the partner', () async {
      final record = await txRepo.recordTransfer(
        fromAccountId: 'acct-A',
        toAccountId: 'acct-B',
        amount: Decimal.parse('100'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
      );
      // Drop the insert ops so the cascade ops are easy to inspect.
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      await txRepo.softDeleteById(record.outgoing.id);

      // Both legs are now invisible to live reads.
      expect(await txRepo.findById(record.outgoing.id), isNull);
      expect(await txRepo.findById(record.incoming.id), isNull);

      // Two delete ops were enqueued — one per leg — so peers replay the
      // tombstones in lock-step with the local soft-delete.
      final ops = await outbox.peekBatch();
      expect(ops, hasLength(2));
      expect(ops.every((o) => o.opType == OpType.delete), isTrue);
      expect(ops.every((o) => o.tableName == 'transactions'), isTrue);
      final ids = ops.map((o) => o.rowId).toSet();
      expect(ids, {record.outgoing.id, record.incoming.id});
    });

    test('non-transfer rows still soft-delete in isolation', () async {
      // A plain expense / cash flow without a transfer_group_id should
      // continue to behave the way it always did — single tombstone, one
      // delete op.
      final tx = Transaction(
        id: 'cash-1',
        accountId: 'acct-1',
        assetId: null,
        type: TransactionType.deposit,
        quantity: Decimal.one,
        price: Decimal.parse('100'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
        sync: SyncMeta(
          ownerUserId: 'u',
          updatedAt: DateTime.utc(2026, 5, 1),
          updatedByDevice: 'dev',
          hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
        ),
      );
      await txRepo.recordTrade(_plan(tx));
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      await txRepo.softDeleteById('cash-1');
      expect(await txRepo.findById('cash-1'), isNull);

      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.single.opType, OpType.delete);
      expect(ops.single.rowId, 'cash-1');
    });
  });

  // FIR-124: the transfer-group audit must stay at zero unbalanced groups
  // for every well-formed scenario — that is the contract that protects
  // the global cash pool.
  group('findUnbalancedTransferGroups (FIR-124 audit)', () {
    test('returns nothing when every group has exactly two live legs',
        () async {
      await txRepo.recordTransfer(
        fromAccountId: 'a',
        toAccountId: 'b',
        amount: Decimal.parse('10'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
      );
      await txRepo.recordTransfer(
        fromAccountId: 'b',
        toAccountId: 'c',
        amount: Decimal.parse('20'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 2),
      );

      final unbalanced = await txRepo.findUnbalancedTransferGroups();
      expect(unbalanced, isEmpty);
    });

    test('also stays balanced after a full group is soft-deleted',
        () async {
      // Cascading delete tombstones BOTH legs, so the group disappears
      // from the audit (no live rows match the WHERE clause). Conversely,
      // anyone who manages to tombstone only one leg surfaces here.
      final r = await txRepo.recordTransfer(
        fromAccountId: 'a',
        toAccountId: 'b',
        amount: Decimal.parse('10'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
      );
      await txRepo.softDeleteById(r.outgoing.id);
      expect(await txRepo.findUnbalancedTransferGroups(), isEmpty);
    });

    test('flags a group whose partner leg was tombstoned out-of-band',
        () async {
      // Simulate a hand-edited / sync-replay bug: only one leg is alive
      // after the delete. The audit must surface the orphaned group so
      // monitoring can page someone.
      final r = await txRepo.recordTransfer(
        fromAccountId: 'a',
        toAccountId: 'b',
        amount: Decimal.parse('10'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 5, 1),
      );
      // Bypass the cascade by writing the tombstone with a raw update —
      // mirrors what a buggy code path or a stale replicated op would do.
      await db.customStatement(
        'UPDATE transactions SET deleted_at = ? WHERE id = ?',
        [
          DateTime.utc(2026, 5, 2).millisecondsSinceEpoch ~/ 1000,
          r.outgoing.id,
        ],
      );

      final unbalanced = await txRepo.findUnbalancedTransferGroups();
      expect(unbalanced, hasLength(1));
      expect(unbalanced.single.transferGroupId, r.transferGroupId);
      expect(unbalanced.single.legCount, 1);
    });
  });
}
