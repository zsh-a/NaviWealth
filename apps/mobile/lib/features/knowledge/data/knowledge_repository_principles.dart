part of 'knowledge_repository.dart';

mixin KnowledgePrinciplesRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgePrinciple>> watchPrinciples({
    required String ownerUserId,
  }) {
    final q = _db.select(_db.knowledgePrinciples)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ]);
    return q.watch().map(
      (rows) => rows.map(knowledgePrincipleFromRow).toList(),
    );
  }

  Future<List<KnowledgePrinciple>> listPrinciples({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgePrinciples)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgePrincipleFromRow).toList();
  }

  Future<List<KnowledgePrinciple>> listActivePrinciples({
    required String ownerUserId,
  }) async {
    final q = _db.select(_db.knowledgePrinciples)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.status.equals(PrincipleStatus.active.wire));
    final rows = await q.get();
    return rows.map(knowledgePrincipleFromRow).toList();
  }

  Future<KnowledgePrinciple?> findPrinciple({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgePrinciples)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgePrincipleFromRow(row);
  }

  Future<void> upsertPrinciple(KnowledgePrinciple p) async {
    await _upsertAndEnqueue(
      _db.knowledgePrinciples,
      knowledgePrincipleCompanion(p),
      tableName: _knowledgePrinciplesTable,
      rowId: p.id,
    );
  }
}
