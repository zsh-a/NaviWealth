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
    int? limit,
  }) {
    final q = _db.select(_db.knowledgeNotes)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit);
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

  Future<KnowledgeNote?> findNoteBySourceUrl({
    required String ownerUserId,
    required String sourceUrl,
    String? excludeId,
  }) async {
    final normalized = normalizeKnowledgeSourceUrl(sourceUrl);
    if (normalized == null) return null;
    final query = _db.select(_db.knowledgeNotes)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.deletedAt.isNull() &
            table.sourceUrl.equals(normalized),
      );
    if (excludeId != null) {
      query.where((table) => table.id.equals(excludeId).not());
    }
    query
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
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
