import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:uuid/uuid.dart';

import '../domain/monthly_close.dart';

class MonthlyCloseRepository {
  MonthlyCloseRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const _tableName = 'financial_monthly_closes';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Stream<MonthlyClose?> watch(String periodMonth) async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.financialMonthlyCloses)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.periodMonth.equals(periodMonth) &
            table.deletedAt.isNull(),
      );
    yield* query.watchSingleOrNull().map(
      (row) => row == null ? null : _fromRow(row),
    );
  }

  Stream<MonthlyClose?> watchPreviousClosed(String periodMonth) async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.financialMonthlyCloses)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.periodMonth.isSmallerThanValue(periodMonth) &
            table.closedAt.isNotNull() &
            table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) => OrderingTerm(
          expression: table.periodMonth,
          mode: OrderingMode.desc,
        ),
      ])
      ..limit(1);
    yield* query.watchSingleOrNull().map(
      (row) => row == null ? null : _fromRow(row),
    );
  }

  Future<MonthlyClose> begin({
    required String periodMonth,
    required MonthlyCloseEvidence evidence,
    required Map<String, Object?> snapshot,
    required DateTime now,
  }) async {
    final stamp = await _stamper.stamp();
    final current = await _find(periodMonth, stamp.ownerUserId);
    if (current != null) return current;
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.financialMonthlyCloses)
          .insert(
            FinancialMonthlyClosesCompanion.insert(
              id: id,
              periodMonth: periodMonth,
              evidenceJson: Value(jsonEncode(evidence.toJson())),
              snapshotJson: Value(jsonEncode(snapshot)),
              startedAt: now,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _find(periodMonth, stamp.ownerUserId))!;
  }

  Future<MonthlyClose> close({
    required String periodMonth,
    required MonthlyCloseEvidence evidence,
    required Map<String, Object?> snapshot,
    required DateTime now,
    String? overrideReason,
  }) async {
    final reason = overrideReason?.trim();
    if (!evidence.isVerified && (reason == null || reason.isEmpty)) {
      throw StateError('blocked evidence requires an explicit override');
    }
    final stamp = await _stamper.stamp();
    final current = await _find(periodMonth, stamp.ownerUserId);
    final id = current?.id ?? _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.financialMonthlyCloses)
          .insertOnConflictUpdate(
            FinancialMonthlyClosesCompanion.insert(
              id: id,
              periodMonth: periodMonth,
              evidenceJson: Value(jsonEncode(evidence.toJson())),
              snapshotJson: Value(jsonEncode(snapshot)),
              status: Value(
                reason == null || reason.isEmpty ? 'closed' : 'overridden',
              ),
              overrideReason: Value(reason),
              startedAt: current?.startedAt ?? now,
              closedAt: Value(now),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _find(periodMonth, stamp.ownerUserId))!;
  }

  Future<MonthlyClose?> _find(String periodMonth, String owner) async {
    final row =
        await (_db.select(_db.financialMonthlyCloses)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.periodMonth.equals(periodMonth) &
                  table.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  MonthlyClose _fromRow(FinancialMonthlyCloseRow row) => MonthlyClose(
    id: row.id,
    periodMonth: row.periodMonth,
    evidence: MonthlyCloseEvidence.fromJson(
      Map<String, Object?>.from(jsonDecode(row.evidenceJson) as Map),
    ),
    snapshot: Map<String, Object?>.from(jsonDecode(row.snapshotJson) as Map),
    status: row.status,
    startedAt: row.startedAt,
    overrideReason: row.overrideReason,
    closedAt: row.closedAt,
  );
}
