import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:uuid/uuid.dart';

import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';

part 'recurring_materialisation_service.dart';
part 'recurring_transaction_template_codec.dart';

class RecurringTransactionRepository {
  RecurringTransactionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  static const String tableName = 'recurring_transactions';

  Stream<List<RecurringTransaction>> watchAll() {
    final query = _db.select(_db.recurringTransactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.enabled, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.nextDueAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<List<RecurringTransaction>> dueAt(DateTime now) async {
    final rows =
        await (_db.select(_db.recurringTransactions)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.enabled.equals(true))
              ..where((t) => t.nextDueAt.isSmallerOrEqualValue(now))
              ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)]))
            .get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  Future<RecurringTransaction?> getById(String id) async {
    final row =
        await (_db.select(_db.recurringTransactions)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<RecurringTransaction> create({
    String? id,
    required String templateJournalBuildJson,
    required String rrule,
    required DateTime nextDueAt,
    DateTime? lastMaterialisedAt,
    bool enabled = true,
  }) async {
    const RecurrenceEngine().parse(rrule);
    JournalBuildTemplateCodec.decode(templateJournalBuildJson);
    final stamp = await _stamper.stamp();
    final transaction = RecurringTransaction(
      id: id ?? _uuid.v4(),
      templateJournalBuildJson: templateJournalBuildJson,
      rrule: rrule,
      nextDueAt: _dateOnlyUtc(nextDueAt),
      lastMaterialisedAt: lastMaterialisedAt == null
          ? null
          : _dateOnlyUtc(lastMaterialisedAt),
      enabled: enabled,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db.into(_db.recurringTransactions).insert(_companion(transaction));
      await _outbox.enqueue(table: tableName, rowId: transaction.id);
    });
    return transaction;
  }

  Future<RecurringTransaction> update(
    String id, {
    String? templateJournalBuildJson,
    String? rrule,
    DateTime? nextDueAt,
    DateTime? lastMaterialisedAt,
    bool? enabled,
  }) async {
    if (rrule != null) const RecurrenceEngine().parse(rrule);
    if (templateJournalBuildJson != null) {
      JournalBuildTemplateCodec.decode(templateJournalBuildJson);
    }
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Unknown recurring transaction id=$id');
    }
    final stamp = await _stamper.stamp();
    final updated = existing.copyWith(
      templateJournalBuildJson: templateJournalBuildJson,
      rrule: rrule,
      nextDueAt: nextDueAt == null ? null : _dateOnlyUtc(nextDueAt),
      lastMaterialisedAt: lastMaterialisedAt == null
          ? existing.lastMaterialisedAt
          : _dateOnlyUtc(lastMaterialisedAt),
      enabled: enabled,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.recurringTransactions,
      )..where((t) => t.id.equals(id))).write(_updateCompanion(updated));
      await _outbox.enqueue(table: tableName, rowId: id);
    });
    return updated;
  }

  Future<RecurringTransaction> markMaterialised({
    required String id,
    required DateTime occurrenceDate,
    required DateTime nextDueAt,
  }) {
    return update(
      id,
      lastMaterialisedAt: _dateOnlyUtc(occurrenceDate),
      nextDueAt: _dateOnlyUtc(nextDueAt),
    );
  }

  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.recurringTransactions,
      )..where((t) => t.id.equals(id))).write(
        RecurringTransactionsCompanion(
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
          deletedAt: Value(stamp.now),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: id);
    });
  }

  RecurringTransaction _rowToDomain(RecurringTransactionRow row) {
    return RecurringTransaction(
      id: row.id,
      templateJournalBuildJson: row.templateJournalBuildJson,
      rrule: row.rrule,
      nextDueAt: row.nextDueAt,
      lastMaterialisedAt: row.lastMaterialisedAt,
      enabled: row.enabled,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }

  RecurringTransactionsCompanion _companion(RecurringTransaction tx) {
    return RecurringTransactionsCompanion.insert(
      id: tx.id,
      templateJournalBuildJson: tx.templateJournalBuildJson,
      rrule: tx.rrule,
      nextDueAt: tx.nextDueAt,
      lastMaterialisedAt: Value(tx.lastMaterialisedAt),
      enabled: Value(tx.enabled),
      ownerUserId: tx.sync.ownerUserId,
      updatedAt: tx.sync.updatedAt,
      updatedByDevice: tx.sync.updatedByDevice,
      hlc: tx.sync.hlc,
    );
  }

  RecurringTransactionsCompanion _updateCompanion(RecurringTransaction tx) {
    return RecurringTransactionsCompanion(
      templateJournalBuildJson: Value(tx.templateJournalBuildJson),
      rrule: Value(tx.rrule),
      nextDueAt: Value(tx.nextDueAt),
      lastMaterialisedAt: Value(tx.lastMaterialisedAt),
      enabled: Value(tx.enabled),
      updatedAt: Value(tx.sync.updatedAt),
      updatedByDevice: Value(tx.sync.updatedByDevice),
      hlc: Value(tx.sync.hlc),
      deletedAt: Value(tx.sync.deletedAt),
    );
  }

  static DateTime _dateOnlyUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
