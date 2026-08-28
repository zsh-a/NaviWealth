part of 'execution_repository.dart';

mixin ExecutionProjectRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<ExecutionProject>> watchActiveProjects({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.active.wire,
          ExecutionProjectStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProjectFromRow).toList());
  }

  Stream<List<ExecutionProject>> watchClosedProjects({
    required String ownerUserId,
    int limit = 100,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.completed.wire,
          ExecutionProjectStatus.archived.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProjectFromRow).toList());
  }

  Future<List<ExecutionProject>> listActiveProjects({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionProjectStatus.active.wire,
          ExecutionProjectStatus.paused.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.targetDate, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(executionProjectFromRow).toList();
  }

  Stream<List<ExecutionProject>> watchProjectsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionProjectFromRow).toList());
  }

  Future<void> upsertProject(ExecutionProject project) {
    return _upsertAndEnqueue(
      _db.executionProjects,
      executionProjectCompanion(project),
      tableName: ExecutionRepository._projectsTable,
      rowId: project.id,
    );
  }

  Future<List<ExecutionAction>> softDeleteProject({
    required ExecutionProject project,
    required SyncMeta sync,
  }) async {
    final tombstone = sync.copyWith(deletedAt: sync.updatedAt);
    return _db.transaction(() async {
      final deleted = ExecutionProject(
        id: project.id,
        title: project.title,
        description: project.description,
        status: project.status,
        horizon: project.horizon,
        targetDate: project.targetDate,
        source: project.source,
        createdAt: project.createdAt,
        completedAt: project.completedAt,
        sync: tombstone,
      );
      await _db
          .into(_db.executionProjects)
          .insert(
            executionProjectCompanion(deleted),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._projectsTable,
        rowId: project.id,
      );
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        projectId: project.id,
        sync: sync,
      );
    });
  }

  Future<List<ExecutionAction>> updateProjectStatus({
    required ExecutionProject project,
    required ExecutionProjectStatus status,
    required SyncMeta sync,
    required ExecutionProgressEntry progress,
  }) async {
    final updated = _projectWithStatus(project, status: status, sync: sync);
    return _db.transaction(() async {
      await _db
          .into(_db.executionProjects)
          .insert(
            executionProjectCompanion(updated),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._projectsTable,
        rowId: project.id,
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
      if (status != ExecutionProjectStatus.completed &&
          status != ExecutionProjectStatus.archived) {
        return <ExecutionAction>[];
      }
      return await _detachOpenActionsToInbox(
        db: _db,
        outbox: _outbox,
        ownerUserId: sync.ownerUserId,
        projectId: project.id,
        sync: sync,
      );
    });
  }

  Future<void> restoreProjectLifecycle({
    required ExecutionProject project,
    required List<ExecutionAction> actions,
    required String? progressId,
    required SyncMeta sync,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.executionProjects)
          .insert(
            executionProjectCompanion(project.copyWith(sync: sync)),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._projectsTable,
        rowId: project.id,
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

  Future<ExecutionProject?> findProject({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionProjects)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : executionProjectFromRow(row);
  }

  Stream<ExecutionProject?> watchProjectById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionProjects)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) => row == null || row.deletedAt != null
          ? null
          : executionProjectFromRow(row),
    );
  }

  Future<List<ExecutionProject>> listProjectsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionProject>[];
    final q = _db.select(_db.executionProjects)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(executionProjectFromRow).toList(growable: false);
  }

  ExecutionProject _projectWithStatus(
    ExecutionProject project, {
    required ExecutionProjectStatus status,
    required SyncMeta sync,
  }) {
    final completedAt = switch (status) {
      ExecutionProjectStatus.completed ||
      ExecutionProjectStatus.archived => sync.updatedAt,
      ExecutionProjectStatus.active || ExecutionProjectStatus.paused => null,
    };
    return project.copyWith(
      status: status,
      completedAt: completedAt,
      sync: sync,
    );
  }
}
