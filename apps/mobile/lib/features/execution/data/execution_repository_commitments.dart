part of 'execution_repository.dart';

mixin ExecutionCommitmentRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<ExecutionCommitment>> watchActiveCommitments({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.active.wire,
          ExecutionCommitmentStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map(
      (rows) => rows.map(executionCommitmentFromRow).toList(),
    );
  }

  Stream<List<ExecutionCommitment>> watchClosedCommitments({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.completed.wire,
          ExecutionCommitmentStatus.archived.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map(
      (rows) => rows.map(executionCommitmentFromRow).toList(),
    );
  }

  Stream<List<ExecutionCommitment>> watchCommitmentsForProject({
    required String ownerUserId,
    required String projectId,
    int limit = 200,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.projectId.equals(projectId))
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.isIn(<String>[
            ExecutionCommitmentStatus.active.wire,
            ExecutionCommitmentStatus.paused.wire,
          ]),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map(
      (rows) => rows.map(executionCommitmentFromRow).toList(),
    );
  }

  Future<List<ExecutionCommitment>> listActiveCommitments({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionCommitmentStatus.active.wire,
          ExecutionCommitmentStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(executionCommitmentFromRow).toList();
  }

  Stream<List<ExecutionCommitment>> watchCommitmentsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map(
      (rows) => rows.map(executionCommitmentFromRow).toList(),
    );
  }

  Future<void> upsertCommitment(ExecutionCommitment commitment) {
    return _upsertAndEnqueue(
      _db.executionCommitments,
      executionCommitmentCompanion(commitment),
      tableName: ExecutionRepository._commitmentsTable,
      rowId: commitment.id,
    );
  }

  Future<List<ExecutionAction>> softDeleteCommitment({
    required ExecutionCommitment commitment,
    required SyncMeta sync,
  }) async {
    final tombstone = sync.copyWith(deletedAt: sync.updatedAt);
    return _db.transaction(() async {
      final deleted = ExecutionCommitment(
        id: commitment.id,
        title: commitment.title,
        description: commitment.description,
        status: commitment.status,
        horizon: commitment.horizon,
        targetDate: commitment.targetDate,
        projectId: commitment.projectId,
        source: commitment.source,
        createdAt: commitment.createdAt,
        completedAt: commitment.completedAt,
        sync: tombstone,
      );
      await _db
          .into(_db.executionCommitments)
          .insert(
            executionCommitmentCompanion(deleted),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._commitmentsTable,
        rowId: commitment.id,
      );
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        commitmentId: commitment.id,
        sync: sync,
      );
    });
  }

  Future<List<ExecutionAction>> updateCommitmentStatus({
    required ExecutionCommitment commitment,
    required ExecutionCommitmentStatus status,
    required SyncMeta sync,
    required ExecutionProgressEntry progress,
  }) async {
    final updated = _commitmentWithStatus(
      commitment,
      status: status,
      sync: sync,
    );
    return _db.transaction(() async {
      await _db
          .into(_db.executionCommitments)
          .insert(
            executionCommitmentCompanion(updated),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._commitmentsTable,
        rowId: commitment.id,
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
      if (status != ExecutionCommitmentStatus.completed &&
          status != ExecutionCommitmentStatus.archived) {
        return <ExecutionAction>[];
      }
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        commitmentId: commitment.id,
        sync: sync,
      );
    });
  }

  Future<void> restoreCommitmentLifecycle({
    required ExecutionCommitment commitment,
    required List<ExecutionAction> actions,
    required String? progressId,
    required SyncMeta sync,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.executionCommitments)
          .insert(
            executionCommitmentCompanion(commitment.copyWith(sync: sync)),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._commitmentsTable,
        rowId: commitment.id,
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

  Future<ExecutionCommitment?> findCommitment({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionCommitments)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : executionCommitmentFromRow(row);
  }

  Stream<ExecutionCommitment?> watchCommitmentById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionCommitments)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) => row == null || row.deletedAt != null
          ? null
          : executionCommitmentFromRow(row),
    );
  }

  Future<List<ExecutionCommitment>> listCommitmentsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionCommitment>[];
    final q = _db.select(_db.executionCommitments)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(executionCommitmentFromRow).toList(growable: false);
  }

  ExecutionCommitment _commitmentWithStatus(
    ExecutionCommitment commitment, {
    required ExecutionCommitmentStatus status,
    required SyncMeta sync,
  }) {
    final completedAt = switch (status) {
      ExecutionCommitmentStatus.completed ||
      ExecutionCommitmentStatus.archived => sync.updatedAt,
      ExecutionCommitmentStatus.active ||
      ExecutionCommitmentStatus.paused => null,
    };
    return commitment.copyWith(
      status: status,
      completedAt: completedAt,
      sync: sync,
    );
  }
}
