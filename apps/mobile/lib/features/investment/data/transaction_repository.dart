import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../core/sync/op.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/domain/transaction.dart';
import '../../../data/repositories/mutation_context.dart';
import '../domain/trade_entry/trade_entry_plan.dart';

/// Read/write API for [Transaction] rows — the persistence counterpart of
/// [TradeEntryService].
///
/// Every write lives in a single Drift transaction that:
///   1. inserts/updates the `transactions` row;
///   2. enqueues a sync [Op] into the outbox.
///
/// Lots and RealizedPnL are domain-only (no Drift table) — they are replayed
/// by [HoldingService] from the transaction log, so this repository only
/// persists the `transactions` row.
class TransactionRepository {
  TransactionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper,
        _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  static const String _tableName = 'transactions';

  // ---------- Reads ----------

  Future<Transaction?> findById(String id) async {
    final row = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _toTransaction(row);
  }

  /// All non-deleted transactions for a given asset, newest first.
  Future<List<Transaction>> findByAssetId(String assetId) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.assetId.equals(assetId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.tradeDate)]))
        .get();
    return rows.map(_toTransaction).toList();
  }

  /// Live stream of transactions for an asset.
  Stream<List<Transaction>> watchByAssetId(String assetId) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.assetId.equals(assetId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.tradeDate)]);
    return query.watch().map((rows) => rows.map(_toTransaction).toList());
  }

  /// All non-deleted transactions, newest first.
  Future<List<Transaction>> listAll() async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.tradeDate)]))
        .get();
    return rows.map(_toTransaction).toList();
  }

  // ---------- Writes ----------

  /// Persist a [TradeEntryPlan]: writes the transaction row and enqueues
  /// a sync op. Returns the persisted [Transaction].
  ///
  /// The plan's [Lot] / [RealizedPnL] lists are **not** persisted here —
  /// they are replayed by [HoldingService] from the transaction log.
  Future<Transaction> recordTrade(TradeEntryPlan plan) async {
    final tx = plan.transaction;
    final stamp = await _stamper.stamp();
    final companion = _toCompanion(tx, stamp);
    final fields = _insertFields(tx, stamp);

    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(companion);
      await _enqueue(
        opType: OpType.insert,
        rowId: tx.id,
        fields: fields,
        stamp: stamp,
      );
    });
    return (await findById(tx.id))!;
  }

  /// Soft-delete a transaction by id and enqueue a delete op. Used by the
  /// FIR-67 propose-card 60s undo path, which knows the row id but not the
  /// originally-created lots; lot bookkeeping is replayed by HoldingService
  /// so dropping the transaction is sufficient.
  Future<void> softDeleteById(String transactionId) async {
    final stamp = await _stamper.stamp();
    final companion = TransactionsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(_db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: transactionId,
        fields: null,
        stamp: stamp,
      );
    });
  }

  /// Soft-delete a transaction and enqueue a delete op.
  Future<void> deleteTrade(TransactionDeletePlan plan) async {
    final stamp = await _stamper.stamp();
    final companion = TransactionsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(_db.transactions)
            ..where((t) => t.id.equals(plan.transactionId)))
          .write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: plan.transactionId,
        fields: null,
        stamp: stamp,
      );
    });
  }

  // ---------- Helpers ----------

  Future<void> _enqueue({
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: _tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
  }

  TransactionsCompanion _toCompanion(Transaction tx, MutationStamp stamp) {
    return TransactionsCompanion.insert(
      id: tx.id,
      accountId: tx.accountId,
      assetId: Value(tx.assetId),
      type: tx.type,
      quantity: tx.quantity,
      price: tx.price,
      currency: tx.currency,
      tradeDate: tx.tradeDate,
      settleDate: Value(tx.settleDate),
      fee: Value(tx.fee),
      tax: Value(tx.tax),
      counterAccountId: Value(tx.counterAccountId),
      lotId: Value(tx.lotId),
      note: Value(tx.note),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
  }

  Map<String, Object?> _insertFields(Transaction tx, MutationStamp stamp) {
    return {
      'id': tx.id,
      'account_id': tx.accountId,
      'asset_id': tx.assetId,
      'type': tx.type.name,
      'quantity': tx.quantity.toString(),
      'price': tx.price.toString(),
      'currency': tx.currency,
      'trade_date': tx.tradeDate.toUtc().toIso8601String(),
      'settle_date': tx.settleDate?.toUtc().toIso8601String(),
      'fee': tx.fee?.toString(),
      'tax': tx.tax?.toString(),
      'counter_account_id': tx.counterAccountId,
      'lot_id': tx.lotId,
      'note': tx.note,
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
  }

  Transaction _toTransaction(TransactionRow row) {
    return Transaction(
      id: row.id,
      accountId: row.accountId,
      assetId: row.assetId,
      type: row.type,
      quantity: row.quantity,
      price: row.price,
      currency: row.currency,
      tradeDate: row.tradeDate,
      settleDate: row.settleDate,
      fee: row.fee,
      tax: row.tax,
      counterAccountId: row.counterAccountId,
      lotId: row.lotId,
      note: row.note,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }
}
