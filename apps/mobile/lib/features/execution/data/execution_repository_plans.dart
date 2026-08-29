part of 'execution_repository.dart';

mixin ExecutionPlanRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<ExecutionPlan>> watchActivePlans({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionPlans)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionPlanStatus.active.wire,
          ExecutionPlanStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionPlanFromRow).toList());
  }

  Stream<List<ExecutionPlan>> watchClosedPlans({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionPlans)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionPlanStatus.completed.wire,
          ExecutionPlanStatus.archived.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionPlanFromRow).toList());
  }

  Future<List<ExecutionPlan>> listActivePlans({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionPlans)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionPlanStatus.active.wire,
          ExecutionPlanStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(executionPlanFromRow).toList();
  }

  Stream<List<ExecutionPlan>> watchPlansForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionPlans)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionPlanFromRow).toList());
  }

  Future<void> upsertPlan(ExecutionPlan plan) {
    return _upsertAndEnqueue(
      _db.executionPlans,
      executionPlanCompanion(plan),
      tableName: ExecutionRepository._plansTable,
      rowId: plan.id,
    );
  }

  Future<List<ExecutionAction>> softDeletePlan({
    required ExecutionPlan plan,
    required SyncMeta sync,
  }) async {
    final tombstone = sync.copyWith(deletedAt: sync.updatedAt);
    return _db.transaction(() async {
      final deleted = ExecutionPlan(
        id: plan.id,
        title: plan.title,
        description: plan.description,
        status: plan.status,
        horizon: plan.horizon,
        targetDate: plan.targetDate,
        source: plan.source,
        createdAt: plan.createdAt,
        completedAt: plan.completedAt,
        sync: tombstone,
      );
      await _db
          .into(_db.executionPlans)
          .insert(
            executionPlanCompanion(deleted),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._plansTable,
        rowId: plan.id,
      );
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        planId: plan.id,
        sync: sync,
      );
    });
  }

  Future<List<ExecutionAction>> updatePlanStatus({
    required ExecutionPlan plan,
    required ExecutionPlanStatus status,
    required SyncMeta sync,
    required ExecutionProgressEntry progress,
  }) async {
    final updated = _planWithStatus(plan, status: status, sync: sync);
    return _db.transaction(() async {
      await _db
          .into(_db.executionPlans)
          .insert(
            executionPlanCompanion(updated),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._plansTable,
        rowId: plan.id,
      );
      await _db
          .into(_db.executionProgressEntries)
          .insert(
            executionProgressCompanion(progress),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._progressTable,
        rowId: progress.id,
      );
      if (status != ExecutionPlanStatus.completed &&
          status != ExecutionPlanStatus.archived) {
        return <ExecutionAction>[];
      }
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        planId: plan.id,
        sync: sync,
      );
    });
  }

  Future<void> restorePlanLifecycle({
    required ExecutionPlan plan,
    required List<ExecutionAction> actions,
    required String? progressId,
    required SyncMeta sync,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.executionPlans)
          .insert(
            executionPlanCompanion(plan.copyWith(sync: sync)),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._plansTable,
        rowId: plan.id,
      );
      for (final action in actions) {
        final restored = action.copyWith(sync: sync);
        await _db
            .into(_db.executionActions)
            .insert(
              executionActionCompanion(restored),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(
          table: ExecutionRepository._actionsTable,
          rowId: restored.id,
        );
      }
      if (progressId == null) return;
      final row =
          await (_db.select(_db.executionProgressEntries)..where(
                (t) =>
                    t.id.equals(progressId) &
                    t.ownerUserId.equals(sync.ownerUserId),
              ))
              .getSingleOrNull();
      if (row == null) return;
      final tombstone = _tombstonedProgress(
        executionProgressFromRow(row),
        sync,
      );
      await _db
          .into(_db.executionProgressEntries)
          .insert(
            executionProgressCompanion(tombstone),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._progressTable,
        rowId: progressId,
      );
    });
  }

  Future<ExecutionPlan?> findPlan({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionPlans)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : executionPlanFromRow(row);
  }

  Stream<ExecutionPlan?> watchPlanById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionPlans)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) => row == null || row.deletedAt != null
          ? null
          : executionPlanFromRow(row),
    );
  }

  Future<List<ExecutionPlan>> listPlansByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionPlan>[];
    final q = _db.select(_db.executionPlans)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(executionPlanFromRow).toList(growable: false);
  }

  ExecutionPlan _planWithStatus(
    ExecutionPlan plan, {
    required ExecutionPlanStatus status,
    required SyncMeta sync,
  }) {
    final completedAt = switch (status) {
      ExecutionPlanStatus.completed ||
      ExecutionPlanStatus.archived => sync.updatedAt,
      ExecutionPlanStatus.active || ExecutionPlanStatus.paused => null,
    };
    return plan.copyWith(status: status, completedAt: completedAt, sync: sync);
  }
}
