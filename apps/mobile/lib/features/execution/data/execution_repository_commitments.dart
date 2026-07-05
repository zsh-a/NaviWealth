part of 'execution_repository.dart';

mixin ExecutionCommitmentRepositoryMixin {
  AppDatabase get _db;

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

  Future<void> softDeleteCommitment({
    required ExecutionCommitment commitment,
    required SyncMeta sync,
  }) {
    final tombstone = sync.copyWith(deletedAt: sync.updatedAt);
    return upsertCommitment(
      ExecutionCommitment(
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
      ),
    );
  }

  Future<void> updateCommitmentStatus({
    required ExecutionCommitment commitment,
    required ExecutionCommitmentStatus status,
    required SyncMeta sync,
  }) {
    return upsertCommitment(
      _commitmentWithStatus(commitment, status: status, sync: sync),
    );
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
