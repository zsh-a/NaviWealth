import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../core/sync/op.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/enums.dart';
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
  static const String _assetsTableName = 'assets';

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

  /// Live stream of every non-deleted transaction. Drives the reactive
  /// holding / returns pipeline: any insert or soft-delete fires a fresh
  /// list, which re-runs the holding service without explicit invalidation.
  Stream<List<Transaction>> watchAll() {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.tradeDate)]);
    return query.watch().map((rows) => rows.map(_toTransaction).toList());
  }

  // ---------- Writes ----------

  /// Persist a [TradeEntryPlan]: writes the transaction row and enqueues
  /// a sync op. Returns the persisted [Transaction].
  ///
  /// The plan's [Lot] / [RealizedPnL] lists are **not** persisted here —
  /// they are replayed by [HoldingService] from the transaction log.
  ///
  /// As a side-effect for security trades, we forward-fill `Asset.lastPrice`
  /// from the transaction so the holdings snapshot has a non-zero market
  /// value the instant the trade is recorded — without it, a freshly-bought
  /// stock would render as "0.00" on `/assets` until the next price fetch.
  /// We only write when no price has been observed yet, or when the trade
  /// is at-or-after the last observation; otherwise we'd overwrite a
  /// fresher quote with a stale trade price.
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
      await _maybeBackfillAssetPrice(tx, stamp);
    });
    return (await findById(tx.id))!;
  }

  /// Update the underlying [Asset]'s `lastPrice` / `lastPriceAt` in-line
  /// with [tx] when the trade is fresher than the currently-recorded
  /// price. No-op for cash flows (assetId null) or when the asset row is
  /// missing — the trade entry pipeline always upserts the asset before
  /// calling [recordTrade], so a missing row indicates a manual / cash
  /// op we should leave alone.
  Future<void> _maybeBackfillAssetPrice(
    Transaction tx,
    MutationStamp stamp,
  ) async {
    final assetId = tx.assetId;
    if (assetId == null || assetId.isEmpty) return;
    // Trades whose price isn't a fair valuation marker (e.g. dividends are
    // priced per-share but don't represent an instrument quote) are skipped.
    if (!_isPriceMarkingTrade(tx.type)) return;

    final assetRow = await (_db.select(_db.assets)
          ..where((t) => t.id.equals(assetId)))
        .getSingleOrNull();
    if (assetRow == null) return;

    final last = assetRow.lastPriceAt;
    if (last != null && last.isAfter(tx.tradeDate)) {
      // A fresher price has already been observed — don't regress it.
      return;
    }

    final companion = AssetsCompanion(
      lastPrice: Value(tx.price),
      lastPriceAt: Value(tx.tradeDate),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    await (_db.update(_db.assets)..where((t) => t.id.equals(assetId)))
        .write(companion);

    final fields = <String, Object?>{
      'last_price': tx.price.toString(),
      'last_price_at': tx.tradeDate.toUtc().toIso8601String(),
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    final op = Op(
      opId: _uuid.v4(),
      tableName: _assetsTableName,
      rowId: assetId,
      opType: OpType.update,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
  }

  /// Trade types whose [Transaction.price] is the per-unit market price
  /// of the underlying instrument, and therefore safe to use as a
  /// `lastPrice` salvage. Excludes pure cash legs and bookkeeping events
  /// where `price` carries something other than a quote.
  static bool _isPriceMarkingTrade(TransactionType type) {
    switch (type) {
      case TransactionType.buy:
      case TransactionType.sell:
      case TransactionType.transferIn:
      case TransactionType.transferOut:
      case TransactionType.valuationAdjust:
      case TransactionType.reinvest:
        return true;
      case TransactionType.dividend:
      case TransactionType.interest:
      case TransactionType.deposit:
      case TransactionType.withdraw:
      case TransactionType.fee:
      case TransactionType.tax:
      case TransactionType.split:
      case TransactionType.liabilityPayment:
      case TransactionType.expense:
        return false;
    }
  }

  /// Soft-delete a transaction by id and enqueue a delete op. Used by the
  /// FIR-67 propose-card 60s undo path, which knows the row id but not the
  /// originally-created lots; lot bookkeeping is replayed by HoldingService
  /// so dropping the transaction is sufficient.
  Future<void> softDeleteById(String transactionId) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final companion = TransactionsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(transactionId))).write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: transactionId,
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
      transferGroupId: Value(tx.transferGroupId),
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
      'transfer_group_id': tx.transferGroupId,
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
      transferGroupId: row.transferGroupId,
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

