part of 'knowledge_repository.dart';

/// Atomic Note → typed-object promotion writes.
///
/// Target ids are deterministic, so a retry (or the same promotion on another
/// device) converges on one typed row instead of creating duplicates.
mixin KnowledgePromotionsRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<String> promoteNoteToDecision({
    required KnowledgeNote source,
    required KnowledgeDecision decision,
    required SyncMeta noteSync,
  }) => _promote(
    source: source,
    targetKind: KnowledgeEntryKind.decision,
    targetId: decision.id,
    targetTable: _db.knowledgeDecisions,
    targetCompanion: knowledgeDecisionCompanion(decision),
    targetTableName: _knowledgeDecisionsTable,
    noteSync: noteSync,
  );

  Future<String> promoteNoteToConcept({
    required KnowledgeNote source,
    required KnowledgeConcept concept,
    required SyncMeta noteSync,
  }) => _promote(
    source: source,
    targetKind: KnowledgeEntryKind.concept,
    targetId: concept.id,
    targetTable: _db.knowledgeConcepts,
    targetCompanion: knowledgeConceptCompanion(concept),
    targetTableName: _knowledgeConceptsTable,
    noteSync: noteSync,
  );

  Future<String> promoteNoteToPrinciple({
    required KnowledgeNote source,
    required KnowledgePrinciple principle,
    required SyncMeta noteSync,
  }) => _promote(
    source: source,
    targetKind: KnowledgeEntryKind.principle,
    targetId: principle.id,
    targetTable: _db.knowledgePrinciples,
    targetCompanion: knowledgePrincipleCompanion(principle),
    targetTableName: _knowledgePrinciplesTable,
    noteSync: noteSync,
  );

  Future<String> promoteNoteToAssumption({
    required KnowledgeNote source,
    required KnowledgeAssumption assumption,
    required SyncMeta noteSync,
  }) => _promote(
    source: source,
    targetKind: KnowledgeEntryKind.assumption,
    targetId: assumption.id,
    targetTable: _db.knowledgeAssumptions,
    targetCompanion: knowledgeAssumptionCompanion(assumption),
    targetTableName: _knowledgeAssumptionsTable,
    noteSync: noteSync,
  );

  Future<String> promoteNoteToExperiment({
    required KnowledgeNote source,
    required KnowledgeExperiment experiment,
    required SyncMeta noteSync,
  }) => _promote(
    source: source,
    targetKind: KnowledgeEntryKind.experiment,
    targetId: experiment.id,
    targetTable: _db.knowledgeExperiments,
    targetCompanion: knowledgeExperimentCompanion(experiment),
    targetTableName: _knowledgeExperimentsTable,
    noteSync: noteSync,
  );

  Future<String> _promote<R>({
    required KnowledgeNote source,
    required KnowledgeEntryKind targetKind,
    required String targetId,
    required TableInfo<Table, R> targetTable,
    required Insertable<R> targetCompanion,
    required String targetTableName,
    required SyncMeta noteSync,
  }) async {
    return _db.transaction(() async {
      final existingRow =
          await (_db.select(_db.knowledgeNotes)..where(
                (table) =>
                    table.id.equals(source.id) &
                    table.ownerUserId.equals(noteSync.ownerUserId),
              ))
              .getSingleOrNull();
      final current = existingRow == null
          ? source
          : knowledgeNoteFromRow(existingRow);
      if (current.isPromoted) {
        if (current.promotedToKind == targetKind.name) {
          return current.promotedToId!;
        }
        throw StateError(
          'note ${source.id} is already promoted to '
          '${current.promotedToKind}:${current.promotedToId}',
        );
      }

      await _db
          .into(targetTable)
          .insert(targetCompanion, mode: InsertMode.insertOrReplace);
      final promotedSource = KnowledgeNote(
        id: current.id,
        title: current.title,
        bodyMd: current.bodyMd,
        sourceUrl: current.sourceUrl,
        tags: current.tags,
        projectTag: current.projectTag,
        createdAt: current.createdAt,
        promotedToKind: targetKind.name,
        promotedToId: targetId,
        promotedAt: noteSync.updatedAt,
        mergedIntoId: current.mergedIntoId,
        sync: noteSync,
      );
      await _db
          .into(_db.knowledgeNotes)
          .insert(
            knowledgeNoteCompanion(promotedSource),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(table: targetTableName, rowId: targetId);
      await _outbox.enqueue(table: _knowledgeNotesTable, rowId: source.id);
      return targetId;
    });
  }
}
