import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../audit/event_log_writer.dart';
import '../db/app_database.dart';
import '../domain/enums.dart';
import '../domain/expense.dart';
import '../domain/expense_metadata.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// FIR-68 — read/write API for expense [Transactions].
///
/// An expense is a [Transactions] row with `type = expense`. We store the
/// signed amount as a *negative* `quantity` and `price = 1` so a naive
/// `SUM(quantity * price)` over an account's transactions yields the
/// correct cash flow without any per-type sign-flipping. The expense
/// payload (category, tags) lives in `expense_metadata_json`.
///
/// Account-balance "linkage" with [AccountRepository] is implicit: the
/// account balance is *always* derived by summing transactions, never
/// stored as a column, so writing the expense row is the linkage. (Credit
/// cards behave correctly because the account's signed sum naturally
/// becomes the outstanding-balance figure shown on the "待还款" tile.)
///
/// The expense currency may differ from the account's currency (e.g. a
/// USD-denominated account that records a CNY meal). The transaction
/// stores the amount in the *expense* currency; conversion to the
/// account/base currency is the consumer's responsibility via
/// `CurrencyConverter`.
class ExpenseRepository {
  ExpenseRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    EventLogWriter? eventLog,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _eventLog = eventLog ?? EventLogWriter(db: db, uuid: uuid),
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final EventLogWriter _eventLog;
  final Uuid _uuid;

  static const String _tableName = 'transactions';

  // ---------- Reads ----------

  /// Live stream of non-deleted expense rows ordered by trade date desc.
  Stream<List<Expense>> watchExpenses({String? accountId}) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.type.equals(TransactionType.expense.name))
      ..where((t) => t.deletedAt.isNull());
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    query.orderBy([
      (t) => OrderingTerm(
        expression: t.tradeDate,
        mode: OrderingMode.desc,
      ),
    ]);
    return query.watch().map(
      (rows) => rows.map(_toExpense).whereType<Expense>().toList(),
    );
  }

  Future<List<Expense>> listExpenses({
    String? accountId,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = _db.select(_db.transactions)
      ..where((t) => t.type.equals(TransactionType.expense.name))
      ..where((t) => t.deletedAt.isNull());
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    if (from != null) {
      query.where((t) => t.tradeDate.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.tradeDate.isSmallerThanValue(to));
    }
    query.orderBy([
      (t) => OrderingTerm(
        expression: t.tradeDate,
        mode: OrderingMode.desc,
      ),
    ]);
    final rows = await query.get();
    return rows.map(_toExpense).whereType<Expense>().toList();
  }

  Future<Expense?> findById(String id) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _toExpense(row);
  }

  // ---------- Writes ----------

  // FIR-131 wave 3f — `create(...)` retired. New expenses go through
  // `JournalEntryBuilders.expense + JournalEntryRepository.create`,
  // wired up at the form (`expense_form_page._save`) and AI proposal
  // applier (`ProposalApplier._applyExpense`) call sites. The
  // remaining `update` / `softDelete` stay alive while the legacy
  // `transactions WHERE type = 'expense'` read path is still served
  // by `expense_list_page` / `expense_report_page`; FIR-132 retires
  // those reads, after which the repo file can be deleted.

  /// Updates an existing expense. Any non-null parameter is a change; the
  /// `clear*` flags allow setting fields back to null. Caller must keep
  /// passing `amount` as a positive magnitude (we re-sign internally).
  Future<Expense> update(
    String id, {
    String? accountId,
    String? categoryId,
    Decimal? amount,
    String? currency,
    DateTime? tradeDate,
    List<String>? tags,
    String? note,
    bool clearNote = false,
    String? reason,
  }) async {
    if (amount != null && amount.sign <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Expense amount must be a positive magnitude.',
      );
    }
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('Expense $id not found (or not an expense row).');
    }

    final stamp = await _stamper.stamp();
    final diff = <String, Object?>{};
    var pending = TransactionsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );

    if (accountId != null) {
      pending = pending.copyWith(accountId: Value(accountId));
      diff['account_id'] = accountId;
    }
    if (amount != null) {
      final signed = -amount;
      pending = pending.copyWith(quantity: Value(signed));
      diff['quantity'] = signed.toString();
    }
    if (currency != null) {
      pending = pending.copyWith(currency: Value(currency));
      diff['currency'] = currency;
    }
    if (tradeDate != null) {
      pending = pending.copyWith(tradeDate: Value(tradeDate));
      diff['trade_date'] = tradeDate.toUtc().toIso8601String();
    }
    if (clearNote) {
      pending = pending.copyWith(note: const Value(null));
      diff['note'] = null;
    } else if (note != null) {
      pending = pending.copyWith(note: Value(note));
      diff['note'] = note;
    }
    if (categoryId != null || tags != null) {
      final newMeta = ExpenseMetadata(
        categoryId: categoryId ?? existing.categoryId,
        tags: tags ?? existing.tags,
      );
      final encoded = newMeta.encode();
      pending = pending.copyWith(expenseMetadataJson: Value(encoded));
      diff['expense_metadata_json'] = encoded;
    }

    if (diff.isEmpty) return existing;
    // Snapshot the *user-visible* prior values for the same set of
    // fields the diff contains, so the audit row can answer "what was
    // it before?" without re-reading the row at view time.
    final auditBefore = <String, Object?>{};
    final auditAfter = <String, Object?>{};
    if (diff.containsKey('account_id')) {
      auditBefore['account_id'] = existing.accountId;
      auditAfter['account_id'] = diff['account_id'];
    }
    if (diff.containsKey('quantity')) {
      // Domain entity exposes the positive magnitude; the audit ledger
      // mirrors that so users see "100 → 300", not "-100 → -300".
      auditBefore['amount'] = existing.amount.toString();
      auditAfter['amount'] = amount!.toString();
    }
    if (diff.containsKey('currency')) {
      auditBefore['currency'] = existing.currency;
      auditAfter['currency'] = diff['currency'];
    }
    if (diff.containsKey('trade_date')) {
      auditBefore['trade_date'] = existing.tradeDate.toUtc().toIso8601String();
      auditAfter['trade_date'] = diff['trade_date'];
    }
    if (diff.containsKey('note')) {
      auditBefore['note'] = existing.note;
      auditAfter['note'] = diff['note'];
    }
    if (diff.containsKey('expense_metadata_json')) {
      auditBefore['category_id'] = existing.categoryId;
      auditBefore['tags'] = existing.tags;
      auditAfter['category_id'] = categoryId ?? existing.categoryId;
      auditAfter['tags'] = tags ?? existing.tags;
    }

    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();
    await _db.transaction(() async {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(id))).write(pending);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
      if (auditAfter.isNotEmpty) {
        await _eventLog.recordFieldChanged(
          entityTable: _tableName,
          entityId: id,
          stamp: stamp,
          before: auditBefore,
          after: auditAfter,
          reason: reason,
        );
      }
    });
    return (await findById(id))!;
  }

  /// Soft-delete (tombstone). Aggregators that respect `deletedAt IS NULL`
  /// will exclude the expense; the queued `delete` op tells peers to do
  /// the same.
  Future<void> softDelete(String id, {String? reason}) async {
    final stamp = await _stamper.stamp();
    final companion = TransactionsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
      );
    });
  }

  // ---------- Internals ----------

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

  /// Maps a Drift row to an [Expense]. Returns `null` if the row isn't an
  /// expense or the metadata blob is missing/malformed — callers use
  /// `whereType<Expense>()` to filter those out, since a corrupt blob is a
  /// data bug, not an end-user state we want to surface mid-list.
  Expense? _toExpense(TransactionRow row) {
    if (row.type != TransactionType.expense) return null;
    final metadata = ExpenseMetadata.decode(row.expenseMetadataJson);
    if (metadata == null) return null;
    return Expense(
      id: row.id,
      accountId: row.accountId,
      categoryId: metadata.categoryId,
      // Quantity is stored signed-negative; the domain entity reports the
      // positive magnitude.
      amount: -row.quantity,
      currency: row.currency,
      tradeDate: row.tradeDate,
      tags: metadata.tags,
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
