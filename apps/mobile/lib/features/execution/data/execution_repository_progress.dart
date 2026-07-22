part of 'execution_repository.dart';

mixin ExecutionProgressRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Future<void> recordProgress(
    ExecutionProgressEntry progress, {
    ExecutionAction? linkedAction,
    ExecutionActionStatus? linkedActionStatus,
  }) async {
    final updatedAction = linkedAction == null || linkedActionStatus == null
        ? null
        : _executionActionWithStatus(
            linkedAction,
            status: linkedActionStatus,
            sync: progress.sync,
          );
    await _db.transaction(() async {
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
      if (updatedAction != null) {
        await _db
            .into(_db.executionActions)
            .insert(
              executionActionCompanion(updatedAction),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(
          table: ExecutionRepository._actionsTable,
          rowId: updatedAction.id,
        );
      }
    });
  }

  Stream<List<ExecutionProgressEntry>> watchRecentProgress({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProgressFromRow).toList());
  }

  Stream<List<ExecutionProgressEntry>> watchProgressForAction({
    required String ownerUserId,
    required String actionId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.actionId.equals(actionId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProgressFromRow).toList());
  }

  Stream<List<ExecutionProgressEntry>> watchProgressForCommitment({
    required String ownerUserId,
    required String commitmentId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.commitmentId.equals(commitmentId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProgressFromRow).toList());
  }

  Stream<List<ExecutionProgressEntry>> watchProgressForProject({
    required String ownerUserId,
    required String projectId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.projectId.equals(projectId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProgressFromRow).toList());
  }

  Future<List<ExecutionProgressEntry>> listRecentProgress({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionProgressEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(executionProgressFromRow).toList();
  }

  Future<void> upsertProgress(ExecutionProgressEntry progress) {
    return _upsertAndEnqueue(
      _db.executionProgressEntries,
      executionProgressCompanion(progress),
      tableName: ExecutionRepository._progressTable,
      rowId: progress.id,
    );
  }

  Future<void> softDeleteProgress({
    required ExecutionProgressEntry progress,
    required SyncMeta sync,
  }) {
    final tombstone = _executionTombstone(sync);
    return upsertProgress(
      ExecutionProgressEntry(
        id: progress.id,
        actionId: progress.actionId,
        projectId: progress.projectId,
        commitmentId: progress.commitmentId,
        kind: progress.kind,
        note: progress.note,
        createdAt: progress.createdAt,
        sync: tombstone,
      ),
    );
  }

  Future<ExecutionProgressEntry?> findProgress({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionProgressEntries)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : executionProgressFromRow(row);
  }
}
