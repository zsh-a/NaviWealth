part of 'execution_repository.dart';

mixin ExecutionActionRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<ExecutionAction>> watchTodayActions({
    required String ownerUserId,
    required DateTime asOf,
    int? limit,
  }) {
    final endOfToday = DateTime(asOf.year, asOf.month, asOf.day + 1);
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) =>
            t.status.isIn(<String>[
              ExecutionActionStatus.todo.wire,
              ExecutionActionStatus.doing.wire,
              ExecutionActionStatus.blocked.wire,
            ]) &
            (t.status.equals(ExecutionActionStatus.doing.wire) |
                t.status.equals(ExecutionActionStatus.blocked.wire) |
                t.scheduledFor.isSmallerThanValue(endOfToday) |
                t.dueAt.isSmallerThanValue(endOfToday) |
                t.priority.equals(ExecutionPriority.high.wire)),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.dueAt, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchOpenActions({
    required String ownerUserId,
    int? limit,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.todo.wire,
          ExecutionActionStatus.doing.wire,
          ExecutionActionStatus.blocked.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchClosedActions({
    required String ownerUserId,
    int? limit,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.done.wire,
          ExecutionActionStatus.dropped.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchActionsForCommitment({
    required String ownerUserId,
    required String commitmentId,
    int limit = 200,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.commitmentId.equals(commitmentId))
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.isIn(<String>[
            ExecutionActionStatus.todo.wire,
            ExecutionActionStatus.doing.wire,
            ExecutionActionStatus.blocked.wire,
          ]),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Stream<List<ExecutionAction>> watchActionsForProject({
    required String ownerUserId,
    required String projectId,
    int limit = 200,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.projectId.equals(projectId))
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.status.isIn(<String>[
            ExecutionActionStatus.todo.wire,
            ExecutionActionStatus.doing.wire,
            ExecutionActionStatus.blocked.wire,
          ]),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.status.equals(ExecutionActionStatus.blocked.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(
          expression: t.priority.equals(ExecutionPriority.high.wire),
          mode: OrderingMode.desc,
        ),
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Future<List<ExecutionAction>> listOpenActions({
    required String ownerUserId,
    int? limit,
    int offset = 0,
  }) async {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.todo.wire,
          ExecutionActionStatus.doing.wire,
          ExecutionActionStatus.blocked.wire,
        ]),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(executionActionFromRow).toList();
  }

  Future<List<ExecutionAction>> listClosedActions({
    required String ownerUserId,
    DateTime? since,
    int limit = 500,
  }) async {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          ExecutionActionStatus.done.wire,
          ExecutionActionStatus.dropped.wire,
        ]),
      );
    if (since != null) {
      q.where((t) => t.completedAt.isBiggerOrEqualValue(since.toUtc()));
    }
    q
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(executionActionFromRow).toList(growable: false);
  }

  Stream<List<ExecutionAction>> watchActionsForMemoryIndex({
    required String ownerUserId,
    int limit = 500,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(executionActionFromRow).toList());
  }

  Future<ExecutionAction?> findAction({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.executionActions)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : executionActionFromRow(row);
  }

  Stream<ExecutionAction?> watchActionById({
    required String ownerUserId,
    required String id,
  }) {
    final q = _db.select(_db.executionActions)
      ..where((t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId))
      ..limit(1);
    return q.watchSingleOrNull().map(
      (row) => row == null || row.deletedAt != null
          ? null
          : executionActionFromRow(row),
    );
  }

  Future<List<ExecutionAction>> listActionsByIds({
    required String ownerUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const <ExecutionAction>[];
    final q = _db.select(_db.executionActions)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.id.isIn(ids.toList(growable: false)),
      );
    final rows = await q.get();
    return rows.map(executionActionFromRow).toList(growable: false);
  }

  Future<void> upsertAction(ExecutionAction action) {
    return _upsertAndEnqueue(
      _db.executionActions,
      executionActionCompanion(action),
      tableName: ExecutionRepository._actionsTable,
      rowId: action.id,
    );
  }

  Future<void> upsertActions(List<ExecutionAction> actions) async {
    if (actions.isEmpty) return;
    await _db.transaction(() async {
      for (final action in actions) {
        await _db
            .into(_db.executionActions)
            .insert(
              executionActionCompanion(action),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(
          table: ExecutionRepository._actionsTable,
          rowId: action.id,
        );
      }
    });
  }

  Future<void> softDeleteAction({
    required ExecutionAction action,
    required SyncMeta sync,
  }) {
    return upsertAction(action.copyWith(sync: _executionTombstone(sync)));
  }

  Future<void> updateActionStatus({
    required ExecutionAction action,
    required ExecutionActionStatus status,
    required SyncMeta sync,
    String? progressId,
    String? progressNote,
  }) async {
    final updated = _executionActionWithStatus(
      action,
      status: status,
      sync: sync,
    );
    await _db.transaction(() async {
      await _db
          .into(_db.executionActions)
          .insert(
            executionActionCompanion(updated),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: ExecutionRepository._actionsTable,
        rowId: action.id,
      );
      if (progressId != null &&
          progressNote != null &&
          progressNote.trim().isNotEmpty) {
        final progress = ExecutionProgressEntry(
          id: progressId,
          actionId: action.id,
          projectId: action.projectId,
          commitmentId: action.commitmentId,
          kind: switch (status) {
            ExecutionActionStatus.blocked => ExecutionProgressKind.blocker,
            ExecutionActionStatus.done => ExecutionProgressKind.completion,
            ExecutionActionStatus.dropped => ExecutionProgressKind.dropped,
            _ => ExecutionProgressKind.checkin,
          },
          note: progressNote.trim(),
          createdAt: sync.updatedAt,
          sync: sync,
        );
        await _db
            .into(_db.executionProgressEntries)
            .insert(executionProgressCompanion(progress));
        await _outbox.enqueue(
          table: ExecutionRepository._progressTable,
          rowId: progress.id,
        );
      }
    });
  }
}
