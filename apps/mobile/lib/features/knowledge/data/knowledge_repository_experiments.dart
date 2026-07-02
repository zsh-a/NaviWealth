part of 'knowledge_repository.dart';

mixin KnowledgeExperimentsRepositoryMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Future<KnowledgeAssumption?> findAssumption({
    required String ownerUserId,
    required String id,
  });

  Stream<List<KnowledgeExperiment>> watchExperiments({
    required String ownerUserId,
  }) {
    final q = _db.select(_db.knowledgeExperiments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
      ]);
    return q.watch().map(
      (rows) => rows.map(knowledgeExperimentFromRow).toList(),
    );
  }

  Future<List<KnowledgeExperiment>> listExperiments({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeExperiments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeExperimentFromRow).toList();
  }

  Future<KnowledgeExperiment?> findExperiment({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeExperiments)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeExperimentFromRow(row);
  }

  Future<void> upsertExperiment(KnowledgeExperiment e) async {
    await _upsertAndEnqueue(
      _db.knowledgeExperiments,
      knowledgeExperimentCompanion(e),
      tableName: _knowledgeExperimentsTable,
      rowId: e.id,
    );
  }

  /// Complete an experiment and close the result loop back to its target
  /// assumption.
  ///
  /// When the experiment has both a [KnowledgeExperiment.targetAssumptionId]
  /// and a non-empty conclusion, this writes a stable conclusion note and
  /// appends that note id to the target assumption's `evidenceIds`. Re-running
  /// the closure updates the same note and keeps evidence ids de-duplicated.
  Future<KnowledgeExperimentClosure> completeExperiment({
    required KnowledgeExperiment experiment,
    required SyncMeta sync,
    AssumptionStatus? assumptionStatus,
    double? assumptionConfidence,
  }) async {
    final completed = KnowledgeExperiment(
      id: experiment.id,
      hypothesis: experiment.hypothesis,
      methodMd: experiment.methodMd,
      metrics: experiment.metrics,
      status: ExperimentStatus.done,
      resultMd: experiment.resultMd,
      conclusionMd: experiment.conclusionMd,
      targetAssumptionId: experiment.targetAssumptionId,
      startedAt: experiment.startedAt,
      endedAt: experiment.endedAt ?? sync.updatedAt,
      mergedIntoId: experiment.mergedIntoId,
      sync: sync,
    );

    KnowledgeNote? evidenceNote;
    KnowledgeAssumption? linkedAssumption;
    final targetId = completed.targetAssumptionId;
    final conclusion = completed.conclusionMd?.trim();
    if (targetId != null &&
        targetId.isNotEmpty &&
        conclusion != null &&
        conclusion.isNotEmpty) {
      final target = await findAssumption(
        ownerUserId: sync.ownerUserId,
        id: targetId,
      );
      if (target != null && target.sync.deletedAt == null) {
        final noteId = experimentConclusionNoteId(completed.id);
        evidenceNote = KnowledgeNote(
          id: noteId,
          title: 'Experiment conclusion: ${completed.hypothesis}',
          bodyMd: _experimentConclusionNoteBody(completed),
          tags: const <String>['experiment', 'evidence'],
          projectTag: target.scope.isEmpty ? null : target.scope,
          createdAt: sync.updatedAt,
          sync: sync,
        );
        linkedAssumption = KnowledgeAssumption(
          id: target.id,
          statement: target.statement,
          confidence: assumptionConfidence ?? target.confidence,
          scope: target.scope,
          evidenceIds: <String>{
            ...target.evidenceIds,
            noteId,
          }.toList(growable: false),
          status: assumptionStatus ?? target.status,
          declaredAt: target.declaredAt,
          lastVerifiedAt: sync.updatedAt,
          mergedIntoId: target.mergedIntoId,
          sync: sync,
        );
      }
    }

    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeExperiments)
          .insert(
            knowledgeExperimentCompanion(completed),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: _knowledgeExperimentsTable,
        rowId: completed.id,
      );

      final note = evidenceNote;
      if (note != null) {
        await _db
            .into(_db.knowledgeNotes)
            .insert(
              knowledgeNoteCompanion(note),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(table: _knowledgeNotesTable, rowId: note.id);
      }

      final assumption = linkedAssumption;
      if (assumption != null) {
        await _db
            .into(_db.knowledgeAssumptions)
            .insert(
              knowledgeAssumptionCompanion(assumption),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(
          table: _knowledgeAssumptionsTable,
          rowId: assumption.id,
        );
      }
    });

    return KnowledgeExperimentClosure(
      experiment: completed,
      evidenceNote: evidenceNote,
      targetAssumption: linkedAssumption,
    );
  }

  String _experimentConclusionNoteBody(KnowledgeExperiment e) {
    final parts = <String>[
      '## Hypothesis',
      e.hypothesis,
      if (e.methodMd.trim().isNotEmpty) ...['', '## Method', e.methodMd.trim()],
      if (e.resultMd != null && e.resultMd!.trim().isNotEmpty) ...[
        '',
        '## Result',
        e.resultMd!.trim(),
      ],
      if (e.conclusionMd != null && e.conclusionMd!.trim().isNotEmpty) ...[
        '',
        '## Conclusion',
        e.conclusionMd!.trim(),
      ],
    ];
    return parts.join('\n');
  }
}
