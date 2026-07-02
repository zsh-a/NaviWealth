part of 'knowledge_repository.dart';

mixin KnowledgeAssumptionsRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgeAssumption>> watchAssumptions({
    required String ownerUserId,
  }) {
    final q = _db.select(_db.knowledgeAssumptions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ]);
    return q.watch().map(
      (rows) => rows.map(knowledgeAssumptionFromRow).toList(),
    );
  }

  Future<List<KnowledgeAssumption>> listAssumptions({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeAssumptions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeAssumptionFromRow).toList();
  }

  Future<KnowledgeAssumption?> findAssumption({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeAssumptions)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeAssumptionFromRow(row);
  }

  /// Open == status == active. Optionally filter by confidence ceiling
  /// — useful for "show me the shaky ones" review queries.
  Future<List<KnowledgeAssumption>> listOpenAssumptions({
    required String ownerUserId,
    double? confidenceMax,
  }) async {
    final q = _db.select(_db.knowledgeAssumptions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.status.equals(AssumptionStatus.active.wire));
    if (confidenceMax != null) {
      q.where((t) => t.confidence.isSmallerOrEqualValue(confidenceMax));
    }
    final rows = await q.get();
    return rows.map(knowledgeAssumptionFromRow).toList();
  }

  Future<void> upsertAssumption(KnowledgeAssumption a) async {
    await _upsertAndEnqueue(
      _db.knowledgeAssumptions,
      knowledgeAssumptionCompanion(a),
      tableName: _knowledgeAssumptionsTable,
      rowId: a.id,
    );
  }
}
