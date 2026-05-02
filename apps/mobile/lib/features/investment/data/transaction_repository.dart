import 'package:decimal/decimal.dart';
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

  /// FIR-124: persist an account-to-account cash transfer as **two** rows
  /// inside one Drift transaction so the pair can never end up half-written.
  ///
  /// Both legs share the returned `transferGroupId`:
  ///   - `transferOut`: `accountId = fromAccountId`,
  ///     `counterAccountId = toAccountId`
  ///   - `transferIn`:  `accountId = toAccountId`,
  ///     `counterAccountId = fromAccountId`
  ///
  /// Cash-flow shape mirrors the existing transferIn/transferOut convention
  /// the rest of the codebase already understands (`net_worth_service` ⋯
  /// `cash_flow_extractor`): the row carries `quantity = 1` and
  /// `price = amount`, so `notional = quantity * price = amount`. No asset
  /// is referenced — pure cash movement.
  ///
  /// `fee`, when present, is charged to the **outgoing** leg (the source
  /// account is the one the bank debits). The incoming leg lands the full
  /// `amount`. Cross-currency transfers are out of scope for v1; both legs
  /// share [currency].
  ///
  /// Both inserts and both outbox `Op`s ride the same Drift transaction.
  /// If any statement throws, the whole pair rolls back — neither leg
  /// reaches the database, neither op reaches the outbox, so peers can
  /// never observe a partial transfer.
  Future<TransferRecord> recordTransfer({
    required String fromAccountId,
    required String toAccountId,
    required Decimal amount,
    required String currency,
    required DateTime tradeDate,
    Decimal? fee,
    String? note,
    DateTime? settleDate,
    String? transferGroupId,
    String? outgoingId,
    String? incomingId,
  }) async {
    if (fromAccountId.isEmpty || toAccountId.isEmpty) {
      throw ArgumentError('fromAccountId and toAccountId must be non-empty.');
    }
    if (fromAccountId == toAccountId) {
      throw ArgumentError(
        'A transfer must move cash between two different accounts.',
      );
    }
    if (amount.sign <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }
    if (fee != null && fee.sign < 0) {
      throw ArgumentError.value(fee, 'fee', 'must be >= 0');
    }
    if (currency.trim().isEmpty) {
      throw ArgumentError.value(currency, 'currency', 'must not be empty');
    }

    final groupId = transferGroupId ?? _uuid.v4();
    final outId = outgoingId ?? _uuid.v4();
    final inId = incomingId ?? _uuid.v4();
    if (outId == inId) {
      throw ArgumentError('outgoingId and incomingId must differ.');
    }
    final stamp = await _stamper.stamp();

    final outgoingTx = _buildTransferLeg(
      id: outId,
      type: TransactionType.transferOut,
      accountId: fromAccountId,
      counterAccountId: toAccountId,
      amount: amount,
      currency: currency,
      tradeDate: tradeDate,
      settleDate: settleDate,
      fee: fee,
      note: note,
      transferGroupId: groupId,
      stamp: stamp,
    );
    final incomingTx = _buildTransferLeg(
      id: inId,
      type: TransactionType.transferIn,
      accountId: toAccountId,
      counterAccountId: fromAccountId,
      amount: amount,
      currency: currency,
      tradeDate: tradeDate,
      settleDate: settleDate,
      // Fee is borne by the source account; the incoming leg receives the
      // full amount intact.
      fee: null,
      note: note,
      transferGroupId: groupId,
      stamp: stamp,
    );

    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(_toCompanion(outgoingTx, stamp));
      await _enqueue(
        opType: OpType.insert,
        rowId: outgoingTx.id,
        fields: _insertFields(outgoingTx, stamp),
        stamp: stamp,
      );
      await _db.into(_db.transactions).insert(_toCompanion(incomingTx, stamp));
      await _enqueue(
        opType: OpType.insert,
        rowId: incomingTx.id,
        fields: _insertFields(incomingTx, stamp),
        stamp: stamp,
      );
    });

    final outReloaded = (await findById(outgoingTx.id))!;
    final inReloaded = (await findById(incomingTx.id))!;
    return TransferRecord(
      transferGroupId: groupId,
      outgoing: outReloaded,
      incoming: inReloaded,
    );
  }

  Transaction _buildTransferLeg({
    required String id,
    required TransactionType type,
    required String accountId,
    required String counterAccountId,
    required Decimal amount,
    required String currency,
    required DateTime tradeDate,
    DateTime? settleDate,
    Decimal? fee,
    String? note,
    required String transferGroupId,
    required MutationStamp stamp,
  }) {
    return Transaction(
      id: id,
      accountId: accountId,
      assetId: null,
      type: type,
      // Conventional cash-flow shape: quantity = 1, price = amount, so
      // `notional = amount` and downstream services (net worth, returns)
      // continue to reason about the row without a special case.
      quantity: Decimal.one,
      price: amount,
      currency: currency,
      tradeDate: tradeDate,
      settleDate: settleDate,
      fee: fee,
      tax: null,
      counterAccountId: counterAccountId,
      lotId: null,
      note: note,
      transferGroupId: transferGroupId,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  /// Soft-delete a transaction by id and enqueue a delete op. Used by the
  /// FIR-67 propose-card 60s undo path, which knows the row id but not the
  /// originally-created lots; lot bookkeeping is replayed by HoldingService
  /// so dropping the transaction is sufficient.
  ///
  /// FIR-124: if the row belongs to a transfer group, the partner leg is
  /// soft-deleted in the same Drift transaction and its delete op queued
  /// alongside. Removing one half of a transfer would otherwise leave
  /// account balances unbalanced — the audit query would flag it, but by
  /// then the user has already seen the wrong number.
  Future<void> softDeleteById(String transactionId) =>
      _softDeleteRespectingGroup(transactionId);

  /// Soft-delete a transaction and enqueue a delete op.
  Future<void> deleteTrade(TransactionDeletePlan plan) =>
      _softDeleteRespectingGroup(plan.transactionId);

  Future<void> _softDeleteRespectingGroup(String transactionId) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      // Look up the target row's transfer group id while we're inside the
      // transaction so a concurrent edit cannot race the lookup against
      // the delete.
      final groupRow = await (_db.selectOnly(_db.transactions)
            ..addColumns([_db.transactions.transferGroupId])
            ..where(_db.transactions.id.equals(transactionId)))
          .getSingleOrNull();
      final groupId = groupRow?.read(_db.transactions.transferGroupId);

      final ids = <String>{transactionId};
      if (groupId != null && groupId.isNotEmpty) {
        // Pull every still-live leg in the same group. Already-tombstoned
        // legs stay tombstoned (their `deleted_at` is preserved by the
        // `deleted_at IS NULL` filter).
        final partnerRows = await (_db.selectOnly(_db.transactions)
              ..addColumns([_db.transactions.id])
              ..where(_db.transactions.transferGroupId.equals(groupId) &
                  _db.transactions.id.equals(transactionId).not() &
                  _db.transactions.deletedAt.isNull()))
            .get();
        for (final r in partnerRows) {
          ids.add(r.read(_db.transactions.id)!);
        }
      }

      final companion = TransactionsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      for (final id in ids) {
        await (_db.update(_db.transactions)
              ..where((t) => t.id.equals(id)))
            .write(companion);
        await _enqueue(
          opType: OpType.delete,
          rowId: id,
          fields: null,
          stamp: stamp,
        );
      }
    });
  }

  /// FIR-124 audit query: every `transfer_group_id` whose live leg count
  /// is not exactly 2. Returns an empty list when the ledger is balanced.
  ///
  /// Wired into the same admin / sync-monitoring surfaces that flag other
  /// data-integrity drift; CI tests assert it returns 0 rows after every
  /// representative scenario.
  Future<List<TransferGroupAuditRow>> findUnbalancedTransferGroups() async {
    final rows = await _db.customSelect(
      'SELECT transfer_group_id AS gid, COUNT(*) AS leg_count '
      'FROM transactions '
      "WHERE type IN ('transferIn', 'transferOut') "
      'AND deleted_at IS NULL '
      'AND transfer_group_id IS NOT NULL '
      'GROUP BY transfer_group_id '
      'HAVING COUNT(*) != 2',
      readsFrom: {_db.transactions},
    ).get();
    return rows
        .map((r) => TransferGroupAuditRow(
              transferGroupId: r.read<String>('gid'),
              legCount: r.read<int>('leg_count'),
            ))
        .toList(growable: false);
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

/// Result of [TransactionRepository.recordTransfer]: the two persisted
/// rows (transferOut + transferIn) plus the shared `transferGroupId` that
/// links them. Callers that need to display the pair (e.g. to undo the
/// transfer) can hold onto either id.
class TransferRecord {
  const TransferRecord({
    required this.transferGroupId,
    required this.outgoing,
    required this.incoming,
  });

  final String transferGroupId;
  final Transaction outgoing;
  final Transaction incoming;
}

/// One row returned by
/// [TransactionRepository.findUnbalancedTransferGroups]: a
/// `transfer_group_id` whose live leg count is anything other than 2.
/// `legCount == 1` is the canonical "user dropped a leg" case; values of
/// 0 or >2 indicate a sync replay bug or hand-edited data and should be
/// surfaced to monitoring.
class TransferGroupAuditRow {
  const TransferGroupAuditRow({required this.transferGroupId, required this.legCount});

  final String transferGroupId;
  final int legCount;

  @override
  String toString() =>
      'TransferGroupAuditRow($transferGroupId, legCount=$legCount)';
}
