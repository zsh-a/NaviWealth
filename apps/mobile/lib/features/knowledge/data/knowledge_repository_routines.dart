part of 'knowledge_repository.dart';

mixin KnowledgeRoutinesRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgeRoutine>> watchRoutines({required String ownerUserId}) {
    final q = _db.select(_db.knowledgeRoutines)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)]);
    return q.watch().map((rows) => rows.map(knowledgeRoutineFromRow).toList());
  }

  /// Routines whose `nextDueAt <= asOf` and status == active. Ordered by
  /// nextDueAt ascending so the most-overdue is first. The caller decides
  /// the look-ahead window (e.g. `asOf = now + 7d` for "due this week").
  Future<List<KnowledgeRoutine>> listDueRoutines({
    required String ownerUserId,
    required DateTime asOf,
    DateTime? excludeDoneSince,
    int limit = 50,
  }) async {
    final q = _db.select(_db.knowledgeRoutines)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.status.equals(RoutineStatus.active.wire))
      ..where((t) => t.nextDueAt.isSmallerOrEqualValue(asOf));
    if (excludeDoneSince != null) {
      final cutoff = excludeDoneSince.toUtc();
      q.where(
        (t) => t.lastDoneAt.isNull() | t.lastDoneAt.isSmallerThanValue(cutoff),
      );
    }
    q
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(knowledgeRoutineFromRow).toList();
  }

  Future<List<KnowledgeRoutine>> listRoutines({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeRoutines)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeRoutineFromRow).toList();
  }

  Future<KnowledgeRoutine?> findRoutine({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeRoutines)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeRoutineFromRow(row);
  }

  Future<void> upsertRoutine(KnowledgeRoutine r) async {
    await _upsertAndEnqueue(
      _db.knowledgeRoutines,
      knowledgeRoutineCompanion(r),
      tableName: _knowledgeRoutinesTable,
      rowId: r.id,
    );
  }
}
