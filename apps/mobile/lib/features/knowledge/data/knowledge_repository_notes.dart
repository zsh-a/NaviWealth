part of 'knowledge_repository.dart';

mixin KnowledgeNotesRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgeNote>> watchNotes({
    required String ownerUserId,
    int limit = 200,
  }) {
    final q = _db.select(_db.knowledgeNotes)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.promotedToId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(knowledgeNoteFromRow).toList());
  }

  Future<List<KnowledgeNote>> listNotes({
    required String ownerUserId,
    int limit = 200,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeNotes)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.promotedToId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeNoteFromRow).toList();
  }

  Future<KnowledgeNote?> findNote({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeNotes)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeNoteFromRow(row);
  }

  Future<void> upsertNote(KnowledgeNote note) async {
    await _upsertAndEnqueue(
      _db.knowledgeNotes,
      knowledgeNoteCompanion(note),
      tableName: _knowledgeNotesTable,
      rowId: note.id,
    );
  }
}
