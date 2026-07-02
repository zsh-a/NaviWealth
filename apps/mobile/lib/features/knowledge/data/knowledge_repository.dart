/// KnowledgeOS read / write API (`docs/domains/knowledgeos-domain.md` §3 + §9).
///
/// Thin Drift wrapper over the six `knowledge_*` tables. Mirrors
/// `HealthMetricRepository`: the caller stamps sync metadata via the
/// cross-domain `mutationStamperProvider` and passes the stamped
/// `SyncMeta` in on every write. The repository owns the
/// transaction + outbox enqueue.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/knowledge_models.dart';
import 'knowledge_row_mappers.dart';

part 'knowledge_repository_merge.dart';

enum KnowledgeEntryKind {
  note('knowledge_notes'),
  principle('knowledge_principles'),
  assumption('knowledge_assumptions'),
  decision('knowledge_decisions'),
  concept('knowledge_concepts'),
  experiment('knowledge_experiments'),
  routine('knowledge_routines');

  const KnowledgeEntryKind(this.tableName);

  final String tableName;
}

String experimentConclusionNoteId(String experimentId) =>
    'experiment_conclusion:$experimentId';

class KnowledgeExperimentClosure {
  const KnowledgeExperimentClosure({
    required this.experiment,
    this.evidenceNote,
    this.targetAssumption,
  });

  final KnowledgeExperiment experiment;
  final KnowledgeNote? evidenceNote;
  final KnowledgeAssumption? targetAssumption;
}

class KnowledgeRepository with KnowledgeRepositoryMerge {
  KnowledgeRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  @override
  final AppDatabase _db;
  final OutboxStore _outbox;

  /// Shared write path for the 6 typed KnowledgeOS tables: open a
  /// transaction, upsert via `insertOrReplace`, then enqueue the
  /// dirty-pointer outbox entry for sync. The previous version of
  /// this file repeated that 4-line dance in every `upsertX` —
  /// mechanical and identical across types, so collapsed here.
  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  }) async {
    await _db.transaction(() async {
      await _db.into(table).insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: tableName, rowId: rowId);
    });
  }

  /// Soft-delete one KnowledgeOS row using the shared sync columns.
  ///
  /// This is intentionally type-agnostic: every `knowledge_*` table carries
  /// the same `SyncableTable` metadata, so Library UI delete can stay one
  /// path while still writing a tombstone peers can sync.
  Future<void> deleteEntry({
    required KnowledgeEntryKind kind,
    required String id,
    required SyncMeta sync,
  }) async {
    final deletedAt = sync.deletedAt ?? sync.updatedAt;
    await _db.transaction(() async {
      final changed = await _db.customUpdate(
        '''
UPDATE ${kind.tableName}
SET updated_at = ?, updated_by_device = ?, hlc = ?, deleted_at = ?
WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL
''',
        variables: [
          Variable<DateTime>(sync.updatedAt),
          Variable<String>(sync.updatedByDevice),
          Variable<String>(sync.hlc.toString()),
          Variable<DateTime>(deletedAt),
          Variable<String>(id),
          Variable<String>(sync.ownerUserId),
        ],
        updates: {_tableFor(kind)},
      );
      if (changed > 0) {
        await _outbox.enqueue(table: kind.tableName, rowId: id);
      }
    });
  }

  TableInfo<Table, Object?> _tableFor(KnowledgeEntryKind kind) =>
      switch (kind) {
        KnowledgeEntryKind.note => _db.knowledgeNotes,
        KnowledgeEntryKind.principle => _db.knowledgePrinciples,
        KnowledgeEntryKind.assumption => _db.knowledgeAssumptions,
        KnowledgeEntryKind.decision => _db.knowledgeDecisions,
        KnowledgeEntryKind.concept => _db.knowledgeConcepts,
        KnowledgeEntryKind.experiment => _db.knowledgeExperiments,
        KnowledgeEntryKind.routine => _db.knowledgeRoutines,
      };

  // ---------- Notes ----------

  static const String _notesTable = 'knowledge_notes';

  Stream<List<KnowledgeNote>> watchNotes({
    required String ownerUserId,
    int limit = 200,
  }) {
    final q = _db.select(_db.knowledgeNotes)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
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

  @override
  Future<void> upsertNote(KnowledgeNote note) async {
    await _upsertAndEnqueue(
      _db.knowledgeNotes,
      knowledgeNoteCompanion(note),
      tableName: _notesTable,
      rowId: note.id,
    );
  }

  // ---------- Principles ----------

  static const String _principlesTable = 'knowledge_principles';

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

  @override
  Future<void> upsertPrinciple(KnowledgePrinciple p) async {
    await _upsertAndEnqueue(
      _db.knowledgePrinciples,
      knowledgePrincipleCompanion(p),
      tableName: _principlesTable,
      rowId: p.id,
    );
  }

  // ---------- Assumptions ----------

  static const String _assumptionsTable = 'knowledge_assumptions';

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

  @override
  Future<void> upsertAssumption(KnowledgeAssumption a) async {
    await _upsertAndEnqueue(
      _db.knowledgeAssumptions,
      knowledgeAssumptionCompanion(a),
      tableName: _assumptionsTable,
      rowId: a.id,
    );
  }

  // ---------- Decisions ----------

  static const String _decisionsTable = 'knowledge_decisions';

  Stream<List<KnowledgeDecision>> watchDecisions({
    required String ownerUserId,
    int limit = 200,
  }) {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.decidedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(knowledgeDecisionFromRow).toList());
  }

  @override
  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull());
    if (statuses != null && statuses.isNotEmpty) {
      q.where(
        (t) =>
            t.status.isIn(statuses.map((s) => s.wire).toList(growable: false)),
      );
    }
    q
      ..orderBy([
        (t) => OrderingTerm(expression: t.decidedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeDecisionFromRow).toList();
  }

  Future<List<KnowledgeDecision>> listDueReviews({
    required String ownerUserId,
    required DateTime asOf,
    int limit = 100,
  }) async {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn(<String>[
          DecisionStatus.active.wire,
          DecisionStatus.draft.wire,
          DecisionStatus.paused.wire,
        ]),
      )
      ..where((t) => t.reviewDate.isNotNull())
      ..where((t) => t.reviewDate.isSmallerOrEqualValue(asOf))
      ..orderBy([
        (t) => OrderingTerm(expression: t.reviewDate, mode: OrderingMode.asc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(knowledgeDecisionFromRow).toList();
  }

  Future<KnowledgeDecision?> findDecision({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeDecisions)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeDecisionFromRow(row);
  }

  @override
  Future<void> upsertDecision(KnowledgeDecision d) async {
    await _upsertAndEnqueue(
      _db.knowledgeDecisions,
      knowledgeDecisionCompanion(d),
      tableName: _decisionsTable,
      rowId: d.id,
    );
  }

  // ---------- Concepts ----------

  static const String _conceptsTable = 'knowledge_concepts';

  Stream<List<KnowledgeConcept>> watchConcepts({required String ownerUserId}) {
    final q = _db.select(_db.knowledgeConcepts)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return q.watch().map((rows) => rows.map(knowledgeConceptFromRow).toList());
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

  @override
  Future<void> upsertConcept(KnowledgeConcept c) async {
    await _upsertAndEnqueue(
      _db.knowledgeConcepts,
      knowledgeConceptCompanion(c),
      tableName: _conceptsTable,
      rowId: c.id,
    );
  }

  // ---------- Experiments ----------

  static const String _experimentsTable = 'knowledge_experiments';

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

  @override
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

  @override
  Future<void> upsertExperiment(KnowledgeExperiment e) async {
    await _upsertAndEnqueue(
      _db.knowledgeExperiments,
      knowledgeExperimentCompanion(e),
      tableName: _experimentsTable,
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
      await _outbox.enqueue(table: _experimentsTable, rowId: completed.id);

      final note = evidenceNote;
      if (note != null) {
        await _db
            .into(_db.knowledgeNotes)
            .insert(
              knowledgeNoteCompanion(note),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(table: _notesTable, rowId: note.id);
      }

      final assumption = linkedAssumption;
      if (assumption != null) {
        await _db
            .into(_db.knowledgeAssumptions)
            .insert(
              knowledgeAssumptionCompanion(assumption),
              mode: InsertMode.insertOrReplace,
            );
        await _outbox.enqueue(table: _assumptionsTable, rowId: assumption.id);
      }
    });

    return KnowledgeExperimentClosure(
      experiment: completed,
      evidenceNote: evidenceNote,
      targetAssumption: linkedAssumption,
    );
  }

  // ---------- Routines ----------

  static const String _routinesTable = 'knowledge_routines';

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
      tableName: _routinesTable,
      rowId: r.id,
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
