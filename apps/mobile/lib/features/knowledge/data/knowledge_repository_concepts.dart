part of 'knowledge_repository.dart';

mixin KnowledgeConceptsRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgeConcept>> watchConcepts({required String ownerUserId}) {
    final q = _db.select(_db.knowledgeConcepts)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return q.watch().map((rows) => rows.map(knowledgeConceptFromRow).toList());
  }

  Future<List<KnowledgeConcept>> listConcepts({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeConcepts)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeConceptFromRow).toList();
  }

  Future<KnowledgeConcept?> findConcept({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeConcepts)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeConceptFromRow(row);
  }

  Future<void> upsertConcept(KnowledgeConcept c) async {
    await _upsertAndEnqueue(
      _db.knowledgeConcepts,
      knowledgeConceptCompanion(c),
      tableName: _knowledgeConceptsTable,
      rowId: c.id,
    );
  }
}
