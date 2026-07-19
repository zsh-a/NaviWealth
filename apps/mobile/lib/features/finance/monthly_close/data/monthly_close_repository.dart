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

  Future<MonthlyClose> toggleStep({
    required String periodMonth,
    required MonthlyCloseStep step,
    required DateTime now,
  }) async {
    final current = await _find(periodMonth);
    final completed = {...?current?.completedSteps};
    completed.contains(step) ? completed.remove(step) : completed.add(step);
    return _write(
      current: current,
      periodMonth: periodMonth,
      completed: completed,
      closedAt: null,
      now: now,
    );
  }

  Future<MonthlyClose> close({
    required String periodMonth,
    required DateTime now,
  }) async {
    final current = await _find(periodMonth);
    if (current == null || !current.isComplete) {
      throw StateError('all monthly close steps must be complete');
    }
    return _write(
      current: current,
      periodMonth: periodMonth,
      completed: current.completedSteps,
      closedAt: now,
      now: now,
    );
  }

  Future<MonthlyClose?> _find(String periodMonth) async {
    final owner = await _stamper.currentUserId();
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

  Future<MonthlyClose> _write({
    required MonthlyClose? current,
    required String periodMonth,
    required Set<MonthlyCloseStep> completed,
    required DateTime? closedAt,
    required DateTime now,
  }) async {
    final stamp = await _stamper.stamp();
    final id = current?.id ?? _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.financialMonthlyCloses)
          .insertOnConflictUpdate(
            FinancialMonthlyClosesCompanion.insert(
              id: id,
              periodMonth: periodMonth,
              completedStepsJson: Value(
                jsonEncode(completed.map((step) => step.name).toList()..sort()),
              ),
              status: Value(closedAt == null ? 'open' : 'closed'),
              startedAt: current?.startedAt ?? now,
              closedAt: Value(closedAt),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _find(periodMonth))!;
  }

  MonthlyClose _fromRow(FinancialMonthlyCloseRow row) => MonthlyClose(
    id: row.id,
    periodMonth: row.periodMonth,
    completedSteps: (jsonDecode(row.completedStepsJson) as List<Object?>)
        .map((name) => MonthlyCloseStep.values.byName(name! as String))
        .toSet(),
    startedAt: row.startedAt,
    closedAt: row.closedAt,
  );
}
