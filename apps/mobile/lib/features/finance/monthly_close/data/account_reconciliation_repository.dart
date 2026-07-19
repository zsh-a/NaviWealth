import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:uuid/uuid.dart';

import '../domain/account_reconciliation.dart';

class AccountReconciliationRepository {
  AccountReconciliationRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const _tableName = 'financial_reconciliations';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Stream<List<AccountReconciliation>> watchPeriod(String periodMonth) async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.financialReconciliations)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.periodMonth.equals(periodMonth) &
            table.deletedAt.isNull(),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.accountId)]);
    yield* query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<Decimal> ledgerBalanceAt({
    required String accountId,
    required String unit,
    required DateTime endExclusive,
  }) async {
    final owner = await _stamper.currentUserId();
    final rows = await _db
        .customSelect(
          '''
SELECT p.units
FROM postings p
JOIN journal_entries j ON j.id = p.journal_entry_id
WHERE p.owner_user_id = ? AND j.owner_user_id = ?
  AND p.account_id = ? AND p.unit = ?
  AND p.deleted_at IS NULL AND j.deleted_at IS NULL
  AND j.date < ?
''',
          variables: [
            Variable<String>(owner),
            Variable<String>(owner),
            Variable<String>(accountId),
            Variable<String>(unit),
            Variable<int>(endExclusive.millisecondsSinceEpoch ~/ 1000),
          ],
          readsFrom: {_db.postings, _db.journalEntries},
        )
        .get();
    return rows.fold<Decimal>(
      Decimal.zero,
      (sum, row) => sum + Decimal.parse(row.read<String>('units')),
    );
  }

  Future<AccountReconciliation> verify({
    required String periodMonth,
    required String accountId,
    required String unit,
    required Decimal statementBalance,
    required DateTime now,
  }) async {
    final ledgerBalance = await ledgerBalanceAt(
      accountId: accountId,
      unit: unit,
      endExclusive: reconciliationPeriodEndExclusive(periodMonth),
    );
    final difference = statementBalance - ledgerBalance;
    return _write(
      periodMonth: periodMonth,
      accountId: accountId,
      unit: unit,
      statementBalance: statementBalance,
      ledgerBalance: ledgerBalance,
      difference: difference,
      status: reconciliationStatusFor(difference),
      note: null,
      now: now,
    );
  }

  Future<AccountReconciliation> overrideMismatch({
    required AccountReconciliation reconciliation,
    required String note,
    required DateTime now,
  }) {
    if (reconciliation.status != AccountReconciliationStatus.mismatch) {
      throw StateError('only a mismatch can be overridden');
    }
    final reason = note.trim();
    if (reason.isEmpty) throw ArgumentError.value(note, 'note');
    return _write(
      existingId: reconciliation.id,
      periodMonth: reconciliation.periodMonth,
      accountId: reconciliation.accountId,
      unit: reconciliation.unit,
      statementBalance: reconciliation.statementBalance,
      ledgerBalance: reconciliation.ledgerBalance,
      difference: reconciliation.difference,
      status: AccountReconciliationStatus.overridden,
      note: reason,
      now: now,
    );
  }

  Future<AccountReconciliation> _write({
    String? existingId,
    required String periodMonth,
    required String accountId,
    required String unit,
    required Decimal statementBalance,
    required Decimal ledgerBalance,
    required Decimal difference,
    required AccountReconciliationStatus status,
    required String? note,
    required DateTime now,
  }) async {
    final stamp = await _stamper.stamp();
    final existing = existingId == null
        ? await (_db.select(_db.financialReconciliations)..where(
                (table) =>
                    table.ownerUserId.equals(stamp.ownerUserId) &
                    table.periodMonth.equals(periodMonth) &
                    table.accountId.equals(accountId) &
                    table.unit.equals(unit),
              ))
              .getSingleOrNull()
        : null;
    final id = existingId ?? existing?.id ?? _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.financialReconciliations)
          .insertOnConflictUpdate(
            FinancialReconciliationsCompanion.insert(
              id: id,
              periodMonth: periodMonth,
              accountId: accountId,
              unit: unit,
              statementBalance: statementBalance,
              ledgerBalance: ledgerBalance,
              difference: difference,
              status: status.name,
              note: Value(note),
              verifiedAt: now,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    final row =
        await (_db.select(_db.financialReconciliations)..where(
              (table) =>
                  table.id.equals(id) &
                  table.ownerUserId.equals(stamp.ownerUserId),
            ))
            .getSingle();
    return _fromRow(row);
  }

  AccountReconciliation _fromRow(FinancialReconciliationRow row) =>
      AccountReconciliation(
        id: row.id,
        periodMonth: row.periodMonth,
        accountId: row.accountId,
        unit: row.unit,
        statementBalance: row.statementBalance,
        ledgerBalance: row.ledgerBalance,
        difference: row.difference,
        status: AccountReconciliationStatus.values.byName(row.status),
        verifiedAt: row.verifiedAt,
        note: row.note,
      );
}
