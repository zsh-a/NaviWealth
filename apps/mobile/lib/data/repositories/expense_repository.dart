import 'package:drift/drift.dart' hide Column;

import '../db/app_database.dart';
import '../domain/enums.dart';
import '../domain/expense.dart';
import '../domain/expense_metadata.dart';
import '../domain/sync_meta.dart';

/// FIR-131 wave 3h — read-only view over the legacy `transactions WHERE
/// type='expense'` rows. Writes have all moved to the journal-entry
/// stack (`JournalEntryBuilders.expense` + `JournalEntryRepository`).
///
/// The repo stays alive only because `expense_list_page` /
/// `expense_report_page` still read from the legacy table; FIR-132
/// retires those reads, after which this file can be deleted.
///
/// Quantities are stored signed-negative on the row; the [Expense]
/// domain entity reports the positive magnitude.
class ExpenseRepository {
  ExpenseRepository({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

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

  Expense? _toExpense(TransactionRow row) {
    if (row.type != TransactionType.expense) return null;
    final metadata = ExpenseMetadata.decode(row.expenseMetadataJson);
    if (metadata == null) return null;
    return Expense(
      id: row.id,
      accountId: row.accountId,
      categoryId: metadata.categoryId,
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
