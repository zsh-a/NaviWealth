part of 'knowledge_repository.dart';

mixin KnowledgeRelationsRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Future<void> upsertRelation(KnowledgeRelation relation) {
    return _upsertAndEnqueue(
      _db.knowledgeRelations,
      knowledgeRelationCompanion(relation),
      tableName: _knowledgeRelationsTable,
      rowId: relation.id,
    );
  }

  Future<KnowledgeRelation?> findRelation({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeRelations)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) & table.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeRelationFromRow(row);
  }

  Future<void> deleteRelation({
    required String id,
    required SyncMeta sync,
  }) async {
    final existing = await findRelation(ownerUserId: sync.ownerUserId, id: id);
    if (existing == null) return;
    await upsertRelation(
      KnowledgeRelation(
        id: existing.id,
        fromKind: existing.fromKind,
        fromId: existing.fromId,
        relation: existing.relation,
        toKind: existing.toKind,
        toId: existing.toId,
        createdAt: existing.createdAt,
        sync: sync.copyWith(deletedAt: sync.updatedAt),
      ),
    );
  }

  Future<List<KnowledgeRelation>> listRelationsFrom({
    required String ownerUserId,
    required String fromKind,
    required String fromId,
  }) async {
    final rows =
        await (_db.select(_db.knowledgeRelations)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) &
                  table.fromKind.equals(fromKind) &
                  table.fromId.equals(fromId) &
                  table.deletedAt.isNull(),
            ))
            .get();
    return rows.map(knowledgeRelationFromRow).toList(growable: false);
  }

  /// Lists every live relation touching an object, regardless of direction.
  Future<List<KnowledgeRelation>> listRelationsForObject({
    required String ownerUserId,
    required String kind,
    required String id,
  }) async {
    final rows =
        await (_db.select(_db.knowledgeRelations)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) &
                  table.deletedAt.isNull() &
                  ((table.fromKind.equals(kind) & table.fromId.equals(id)) |
                      (table.toKind.equals(kind) & table.toId.equals(id))),
            ))
            .get();
    return rows.map(knowledgeRelationFromRow).toList(growable: false);
  }

  Stream<List<KnowledgeRelation>> watchRelationsForObject({
    required String ownerUserId,
    required String kind,
    required String id,
  }) {
    final query = _db.select(_db.knowledgeRelations)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.deletedAt.isNull() &
            ((table.fromKind.equals(kind) & table.fromId.equals(id)) |
                (table.toKind.equals(kind) & table.toId.equals(id))),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map(
      (rows) => rows.map(knowledgeRelationFromRow).toList(growable: false),
    );
  }

  /// Returns ids of objects of [kind] that participate in any live relation.
  ///
  /// This intentionally checks both directions: a Note linked *to* a
  /// Decision is just as non-orphaned as a Note linking *from* itself.
  Future<Set<String>> listRelatedObjectIds({
    required String ownerUserId,
    required String kind,
  }) async {
    final rows =
        await (_db.select(_db.knowledgeRelations)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) &
                  table.deletedAt.isNull() &
                  (table.fromKind.equals(kind) | table.toKind.equals(kind)),
            ))
            .get();
    return <String>{
      for (final row in rows)
        if (row.fromKind == kind) row.fromId else row.toId,
    };
  }
}

String knowledgeRelationId({
  required String fromKind,
  required String fromId,
  required KnowledgeRelationType relation,
  required String toKind,
  required String toId,
}) {
  String part(String value) => Uri.encodeComponent(value);
  return 'relation:${part(fromKind)}:${part(fromId)}:'
      '${relation.wire}:${part(toKind)}:${part(toId)}';
}
