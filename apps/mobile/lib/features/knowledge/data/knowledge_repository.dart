/// KnowledgeOS read / write API (`docs/knowledgeos-domain.md` §3 + §9).
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

class KnowledgeRepository {
  KnowledgeRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

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
    return q.watch().map((rows) => rows.map(_noteFromRow).toList());
  }

  Future<List<KnowledgeNote>> listNotes({
    required String ownerUserId,
    int limit = 200,
  }) async {
    final q = _db.select(_db.knowledgeNotes)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_noteFromRow).toList();
  }

  Future<KnowledgeNote?> findNote(String id) async {
    final row = await (_db.select(
      _db.knowledgeNotes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _noteFromRow(row);
  }

  Future<void> upsertNote(KnowledgeNote note) async {
    final companion = KnowledgeNotesCompanion.insert(
      id: note.id,
      title: note.title,
      bodyMd: note.bodyMd,
      sourceUrl: Value(note.sourceUrl),
      tagsJson: Value(encodeStringList(note.tags)),
      projectTag: Value(note.projectTag),
      createdAt: note.createdAt,
      mergedIntoId: Value(note.mergedIntoId),
      ownerUserId: note.sync.ownerUserId,
      updatedAt: note.sync.updatedAt,
      updatedByDevice: note.sync.updatedByDevice,
      hlc: note.sync.hlc,
      deletedAt: Value(note.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeNotes,
      companion,
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
    return q.watch().map((rows) => rows.map(_principleFromRow).toList());
  }

  Future<List<KnowledgePrinciple>> listPrinciples({
    required String ownerUserId,
    int limit = 1000,
  }) async {
    final q = _db.select(_db.knowledgePrinciples)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_principleFromRow).toList();
  }

  Future<List<KnowledgePrinciple>> listActivePrinciples({
    required String ownerUserId,
  }) async {
    final q = _db.select(_db.knowledgePrinciples)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.status.equals(PrincipleStatus.active.wire));
    final rows = await q.get();
    return rows.map(_principleFromRow).toList();
  }

  Future<KnowledgePrinciple?> findPrinciple(String id) async {
    final row = await (_db.select(
      _db.knowledgePrinciples,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _principleFromRow(row);
  }

  Future<void> upsertPrinciple(KnowledgePrinciple p) async {
    final companion = KnowledgePrinciplesCompanion.insert(
      id: p.id,
      statement: p.statement,
      rationaleMd: Value(p.rationaleMd),
      scope: Value(p.scope),
      status: Value(p.status.wire),
      declaredAt: p.declaredAt,
      mergedIntoId: Value(p.mergedIntoId),
      ownerUserId: p.sync.ownerUserId,
      updatedAt: p.sync.updatedAt,
      updatedByDevice: p.sync.updatedByDevice,
      hlc: p.sync.hlc,
      deletedAt: Value(p.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgePrinciples,
      companion,
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
    return q.watch().map((rows) => rows.map(_assumptionFromRow).toList());
  }

  Future<List<KnowledgeAssumption>> listAssumptions({
    required String ownerUserId,
    int limit = 1000,
  }) async {
    final q = _db.select(_db.knowledgeAssumptions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.declaredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_assumptionFromRow).toList();
  }

  Future<KnowledgeAssumption?> findAssumption(String id) async {
    final row = await (_db.select(
      _db.knowledgeAssumptions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _assumptionFromRow(row);
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
    return rows.map(_assumptionFromRow).toList();
  }

  Future<void> upsertAssumption(KnowledgeAssumption a) async {
    final companion = KnowledgeAssumptionsCompanion.insert(
      id: a.id,
      statement: a.statement,
      confidence: Value(a.confidence),
      scope: Value(a.scope),
      evidenceIdsJson: Value(encodeStringList(a.evidenceIds)),
      status: Value(a.status.wire),
      lastVerifiedAt: Value(a.lastVerifiedAt),
      declaredAt: a.declaredAt,
      mergedIntoId: Value(a.mergedIntoId),
      ownerUserId: a.sync.ownerUserId,
      updatedAt: a.sync.updatedAt,
      updatedByDevice: a.sync.updatedByDevice,
      hlc: a.sync.hlc,
      deletedAt: Value(a.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeAssumptions,
      companion,
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
    return q.watch().map((rows) => rows.map(_decisionFromRow).toList());
  }

  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
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
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_decisionFromRow).toList();
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
    return rows.map(_decisionFromRow).toList();
  }

  Future<KnowledgeDecision?> findDecision(String id) async {
    final row = await (_db.select(
      _db.knowledgeDecisions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _decisionFromRow(row);
  }

  Future<void> upsertDecision(KnowledgeDecision d) async {
    final companion = KnowledgeDecisionsCompanion.insert(
      id: d.id,
      question: d.question,
      optionsJson: Value(DecisionOption.encode(d.options)),
      selectedLabel: Value(d.selectedLabel),
      rationaleMd: Value(d.rationaleMd),
      principleIdsJson: Value(encodeStringList(d.principleIds)),
      assumptionIdsJson: Value(encodeStringList(d.assumptionIds)),
      expectedOutcome: Value(d.expectedOutcome),
      reviewDate: Value(d.reviewDate),
      actualOutcomeMd: Value(d.actualOutcomeMd),
      status: Value(d.status.wire),
      supersededByDecisionId: Value(d.supersededByDecisionId),
      contextSnapshotJson: Value(encodeNullableJsonMap(d.contextSnapshot)),
      decidedAt: d.decidedAt,
      mergedIntoId: Value(d.mergedIntoId),
      ownerUserId: d.sync.ownerUserId,
      updatedAt: d.sync.updatedAt,
      updatedByDevice: d.sync.updatedByDevice,
      hlc: d.sync.hlc,
      deletedAt: Value(d.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeDecisions,
      companion,
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
    return q.watch().map((rows) => rows.map(_conceptFromRow).toList());
  }

  Future<KnowledgeConcept?> findConcept(String id) async {
    final row = await (_db.select(
      _db.knowledgeConcepts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _conceptFromRow(row);
  }

  Future<void> upsertConcept(KnowledgeConcept c) async {
    final companion = KnowledgeConceptsCompanion.insert(
      id: c.id,
      name: c.name,
      aliasesJson: Value(encodeStringList(c.aliases)),
      summaryMd: Value(c.summaryMd),
      relatedConceptIdsJson: Value(encodeStringList(c.relatedConceptIds)),
      createdAt: c.createdAt,
      mergedIntoId: Value(c.mergedIntoId),
      ownerUserId: c.sync.ownerUserId,
      updatedAt: c.sync.updatedAt,
      updatedByDevice: c.sync.updatedByDevice,
      hlc: c.sync.hlc,
      deletedAt: Value(c.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeConcepts,
      companion,
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
    return q.watch().map((rows) => rows.map(_experimentFromRow).toList());
  }

  Future<List<KnowledgeExperiment>> listExperiments({
    required String ownerUserId,
    int limit = 1000,
  }) async {
    final q = _db.select(_db.knowledgeExperiments)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_experimentFromRow).toList();
  }

  Future<KnowledgeExperiment?> findExperiment(String id) async {
    final row = await (_db.select(
      _db.knowledgeExperiments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _experimentFromRow(row);
  }

  Future<void> upsertExperiment(KnowledgeExperiment e) async {
    final companion = KnowledgeExperimentsCompanion.insert(
      id: e.id,
      hypothesis: e.hypothesis,
      methodMd: Value(e.methodMd),
      metricsJson: Value(encodeStringList(e.metrics)),
      status: Value(e.status.wire),
      resultMd: Value(e.resultMd),
      conclusionMd: Value(e.conclusionMd),
      targetAssumptionId: Value(e.targetAssumptionId),
      startedAt: e.startedAt,
      endedAt: Value(e.endedAt),
      mergedIntoId: Value(e.mergedIntoId),
      ownerUserId: e.sync.ownerUserId,
      updatedAt: e.sync.updatedAt,
      updatedByDevice: e.sync.updatedByDevice,
      hlc: e.sync.hlc,
      deletedAt: Value(e.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeExperiments,
      companion,
      tableName: _experimentsTable,
      rowId: e.id,
    );
  }

  // ---------- Routines ----------

  static const String _routinesTable = 'knowledge_routines';

  Stream<List<KnowledgeRoutine>> watchRoutines({required String ownerUserId}) {
    final q = _db.select(_db.knowledgeRoutines)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)]);
    return q.watch().map((rows) => rows.map(_routineFromRow).toList());
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
    return rows.map(_routineFromRow).toList();
  }

  Future<List<KnowledgeRoutine>> listRoutines({
    required String ownerUserId,
    int limit = 1000,
  }) async {
    final q = _db.select(_db.knowledgeRoutines)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_routineFromRow).toList();
  }

  Future<KnowledgeRoutine?> findRoutine(String id) async {
    final row = await (_db.select(
      _db.knowledgeRoutines,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _routineFromRow(row);
  }

  Future<void> upsertRoutine(KnowledgeRoutine r) async {
    final companion = KnowledgeRoutinesCompanion.insert(
      id: r.id,
      statement: r.statement,
      intervalDays: r.intervalDays,
      lastDoneAt: Value(r.lastDoneAt),
      nextDueAt: r.nextDueAt,
      scope: Value(r.scope),
      status: Value(r.status.wire),
      createdAt: r.createdAt,
      ownerUserId: r.sync.ownerUserId,
      updatedAt: r.sync.updatedAt,
      updatedByDevice: r.sync.updatedByDevice,
      hlc: r.sync.hlc,
      deletedAt: Value(r.sync.deletedAt),
    );
    await _upsertAndEnqueue(
      _db.knowledgeRoutines,
      companion,
      tableName: _routinesTable,
      rowId: r.id,
    );
  }

  // ---------- Dedupe / merge (§15.3) ----------

  Future<List<KnowledgeConcept>> listConcepts({
    required String ownerUserId,
    int limit = 1000,
  }) async {
    final q = _db.select(_db.knowledgeConcepts)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(_conceptFromRow).toList();
  }

  /// Merge [duplicates] into [primary] (`docs/knowledgeos-domain.md`
  /// §15.3). Unions tags onto the survivor, optionally overrides its
  /// title/body, then tombstones each duplicate stamped with
  /// `mergedIntoId = primary.id`. [stamp] mints one fresh [SyncMeta] per
  /// touched row (so each carries its own HLC); all stamps are minted
  /// **before** the transaction opens so the factory never re-enters the
  /// DB zone. One transaction → primary-update + duplicate-tombstones land
  /// together (the two-row-update sync story in §15.3). Returns the
  /// surviving note. Notes carry no inbound id references, so there is
  /// nothing to re-point.
  Future<KnowledgeNote> mergeNotes({
    required KnowledgeNote primary,
    required List<KnowledgeNote> duplicates,
    required Future<SyncMeta> Function() stamp,
    String? mergedTitle,
    String? mergedBody,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final mergedTags = <String>{...primary.tags};
    for (final d in dups) {
      mergedTags.addAll(d.tags);
    }
    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];

    final survivor = KnowledgeNote(
      id: primary.id,
      title: (mergedTitle != null && mergedTitle.trim().isNotEmpty)
          ? mergedTitle.trim()
          : primary.title,
      bodyMd: (mergedBody != null && mergedBody.trim().isNotEmpty)
          ? mergedBody.trim()
          : primary.bodyMd,
      sourceUrl: primary.sourceUrl,
      tags: mergedTags.toList(growable: false),
      projectTag: primary.projectTag,
      createdAt: primary.createdAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertNote(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        final meta = tombMetas[i];
        await upsertNote(
          KnowledgeNote(
            id: d.id,
            title: d.title,
            bodyMd: d.bodyMd,
            sourceUrl: d.sourceUrl,
            tags: d.tags,
            projectTag: d.projectTag,
            createdAt: d.createdAt,
            mergedIntoId: primary.id,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] concept (§15.3). Beyond the note
  /// behaviour it also (a) folds each duplicate's name into the survivor's
  /// aliases so the old name still resolves, (b) unions related-concept
  /// ids, and (c) **re-points inbound links** — any other live concept
  /// whose `relatedConceptIds` referenced a duplicate now references the
  /// primary. All in one transaction. Returns the surviving concept.
  Future<KnowledgeConcept> mergeConcepts({
    required KnowledgeConcept primary,
    required List<KnowledgeConcept> duplicates,
    required Future<SyncMeta> Function() stamp,
    String? mergedName,
    String? mergedSummary,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();

    final aliases = <String>{...primary.aliases};
    final related = <String>{...primary.relatedConceptIds};
    for (final d in dups) {
      aliases.addAll(d.aliases);
      aliases.add(d.name);
      related.addAll(d.relatedConceptIds);
    }
    related.removeAll(dupIds);
    related.remove(primary.id);
    aliases.remove(primary.name);

    // Re-point inbound related links across other live concepts.
    final ownerUserId = primary.sync.ownerUserId;
    final all = await listConcepts(ownerUserId: ownerUserId);
    final repoints = <(KnowledgeConcept, List<String>)>[];
    for (final c in all) {
      if (c.id == primary.id || dupIds.contains(c.id)) continue;
      if (!c.relatedConceptIds.any(dupIds.contains)) continue;
      final next = <String>{
        for (final r in c.relatedConceptIds)
          dupIds.contains(r) ? primary.id : r,
      }..remove(c.id);
      repoints.add((c, next.toList(growable: false)));
    }

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final repointMetas = <SyncMeta>[
      for (var i = 0; i < repoints.length; i++) await stamp(),
    ];

    final survivor = KnowledgeConcept(
      id: primary.id,
      name: (mergedName != null && mergedName.trim().isNotEmpty)
          ? mergedName.trim()
          : primary.name,
      aliases: aliases.toList(growable: false),
      summaryMd: (mergedSummary != null && mergedSummary.trim().isNotEmpty)
          ? mergedSummary.trim()
          : primary.summaryMd,
      relatedConceptIds: related.toList(growable: false),
      createdAt: primary.createdAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertConcept(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        final meta = tombMetas[i];
        await upsertConcept(
          KnowledgeConcept(
            id: d.id,
            name: d.name,
            aliases: d.aliases,
            summaryMd: d.summaryMd,
            relatedConceptIds: d.relatedConceptIds,
            createdAt: d.createdAt,
            mergedIntoId: primary.id,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
      for (var i = 0; i < repoints.length; i++) {
        final (c, next) = repoints[i];
        await upsertConcept(
          KnowledgeConcept(
            id: c.id,
            name: c.name,
            aliases: c.aliases,
            summaryMd: c.summaryMd,
            relatedConceptIds: next,
            createdAt: c.createdAt,
            mergedIntoId: c.mergedIntoId,
            sync: repointMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Create a bidirectional `[[concept]]` soft link between [a] and [b]
  /// (`docs/knowledgeos-domain.md` §14.2 — the `propose_concept_link` apply
  /// path). Each concept gains the other's id in `relatedConceptIds`
  /// (idempotent — re-linking is a no-op set union). [stamp] mints one
  /// fresh [SyncMeta] per touched concept; one transaction. Returns the two
  /// updated concepts. Throws nothing on an already-linked pair — it just
  /// re-writes the same set.
  Future<(KnowledgeConcept, KnowledgeConcept)> linkConcepts({
    required KnowledgeConcept a,
    required KnowledgeConcept b,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final aMeta = await stamp();
    final bMeta = await stamp();
    final aNext = (<String>{
      ...a.relatedConceptIds,
      b.id,
    }..remove(a.id)).toList(growable: false);
    final bNext = (<String>{
      ...b.relatedConceptIds,
      a.id,
    }..remove(b.id)).toList(growable: false);
    final updatedA = KnowledgeConcept(
      id: a.id,
      name: a.name,
      aliases: a.aliases,
      summaryMd: a.summaryMd,
      relatedConceptIds: aNext,
      createdAt: a.createdAt,
      mergedIntoId: a.mergedIntoId,
      sync: aMeta,
    );
    final updatedB = KnowledgeConcept(
      id: b.id,
      name: b.name,
      aliases: b.aliases,
      summaryMd: b.summaryMd,
      relatedConceptIds: bNext,
      createdAt: b.createdAt,
      mergedIntoId: b.mergedIntoId,
      sync: bMeta,
    );
    await _db.transaction(() async {
      await upsertConcept(updatedA);
      await upsertConcept(updatedB);
    });
    return (updatedA, updatedB);
  }

  /// Merge [duplicates] into [primary] principle (§15.3 P1). Tombstones each
  /// duplicate (`mergedIntoId = primary.id`) and **re-points inbound refs**:
  /// any live Decision citing a duplicate in `principleIds` now cites the
  /// survivor. Principles carry no list fields to union, so the survivor's
  /// own statement/rationale stand. One transaction. Returns the survivor.
  Future<KnowledgePrinciple> mergePrinciples({
    required KnowledgePrinciple primary,
    required List<KnowledgePrinciple> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _all,
    );
    final affected = decisions
        .where((d) => d.principleIds.any(dupIds.contains))
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final refMetas = <SyncMeta>[
      for (var i = 0; i < affected.length; i++) await stamp(),
    ];

    final survivor = KnowledgePrinciple(
      id: primary.id,
      statement: primary.statement,
      rationaleMd: primary.rationaleMd,
      scope: primary.scope,
      status: primary.status,
      declaredAt: primary.declaredAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertPrinciple(survivor);
      for (var i = 0; i < dups.length; i++) {
        await _tombstonePrinciple(dups[i], primary.id, tombMetas[i]);
      }
      for (var i = 0; i < affected.length; i++) {
        final d = affected[i];
        await upsertDecision(
          _redirectDecision(
            d,
            principleIds: _redirectIds(d.principleIds, dupIds, primary.id),
            sync: refMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] assumption (§15.3 P1). Unions evidence
  /// ids onto the survivor, tombstones each duplicate, and re-points inbound
  /// refs: live Decisions' `assumptionIds` and Experiments'
  /// `targetAssumptionId` that pointed at a duplicate now point at the
  /// survivor. One transaction. Returns the survivor.
  Future<KnowledgeAssumption> mergeAssumptions({
    required KnowledgeAssumption primary,
    required List<KnowledgeAssumption> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final evidence = <String>{...primary.evidenceIds};
    for (final d in dups) {
      evidence.addAll(d.evidenceIds);
    }

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _all,
    );
    final affectedDecisions = decisions
        .where((d) => d.assumptionIds.any(dupIds.contains))
        .toList(growable: false);
    final experiments = await listExperiments(
      ownerUserId: ownerUserId,
      limit: _all,
    );
    final affectedExperiments = experiments
        .where((e) => dupIds.contains(e.targetAssumptionId))
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final decMetas = <SyncMeta>[
      for (var i = 0; i < affectedDecisions.length; i++) await stamp(),
    ];
    final expMetas = <SyncMeta>[
      for (var i = 0; i < affectedExperiments.length; i++) await stamp(),
    ];

    final survivor = KnowledgeAssumption(
      id: primary.id,
      statement: primary.statement,
      confidence: primary.confidence,
      scope: primary.scope,
      evidenceIds: evidence.toList(growable: false),
      status: primary.status,
      declaredAt: primary.declaredAt,
      lastVerifiedAt: primary.lastVerifiedAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertAssumption(survivor);
      for (var i = 0; i < dups.length; i++) {
        await _tombstoneAssumption(dups[i], primary.id, tombMetas[i]);
      }
      for (var i = 0; i < affectedDecisions.length; i++) {
        final d = affectedDecisions[i];
        await upsertDecision(
          _redirectDecision(
            d,
            assumptionIds: _redirectIds(d.assumptionIds, dupIds, primary.id),
            sync: decMetas[i],
          ),
        );
      }
      for (var i = 0; i < affectedExperiments.length; i++) {
        final e = affectedExperiments[i];
        await upsertExperiment(
          _redirectExperiment(
            e,
            targetAssumptionId: primary.id,
            sync: expMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] decision (§15.3 P1). Tombstones each
  /// duplicate and re-points any other live decision whose
  /// `supersededByDecisionId` pointed at a duplicate to the survivor (so the
  /// evolution chain stays intact). Distinct from a supersede edit — merge
  /// says "these rows were the same decision". One transaction. Returns the
  /// survivor.
  Future<KnowledgeDecision> mergeDecisions({
    required KnowledgeDecision primary,
    required List<KnowledgeDecision> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _all,
    );
    final affected = decisions
        .where(
          (d) =>
              d.id != primary.id &&
              !dupIds.contains(d.id) &&
              dupIds.contains(d.supersededByDecisionId),
        )
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final refMetas = <SyncMeta>[
      for (var i = 0; i < affected.length; i++) await stamp(),
    ];

    final survivor = _redirectDecision(primary, sync: survivorMeta);

    await _db.transaction(() async {
      await upsertDecision(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        await upsertDecision(
          _redirectDecision(
            d,
            mergedIntoId: primary.id,
            deletedSync: tombMetas[i],
          ),
        );
      }
      for (var i = 0; i < affected.length; i++) {
        await upsertDecision(
          _redirectDecision(
            affected[i],
            supersededByDecisionId: primary.id,
            sync: refMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] experiment (§15.3 P1). Experiments
  /// carry no inbound id references, so this only unions metrics onto the
  /// survivor and tombstones each duplicate. One transaction. Returns the
  /// survivor.
  Future<KnowledgeExperiment> mergeExperiments({
    required KnowledgeExperiment primary,
    required List<KnowledgeExperiment> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final metrics = <String>{...primary.metrics};
    for (final d in dups) {
      metrics.addAll(d.metrics);
    }
    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];

    final survivor = KnowledgeExperiment(
      id: primary.id,
      hypothesis: primary.hypothesis,
      methodMd: primary.methodMd,
      metrics: metrics.toList(growable: false),
      status: primary.status,
      resultMd: primary.resultMd,
      conclusionMd: primary.conclusionMd,
      targetAssumptionId: primary.targetAssumptionId,
      startedAt: primary.startedAt,
      endedAt: primary.endedAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertExperiment(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        await upsertExperiment(
          KnowledgeExperiment(
            id: d.id,
            hypothesis: d.hypothesis,
            methodMd: d.methodMd,
            metrics: d.metrics,
            status: d.status,
            resultMd: d.resultMd,
            conclusionMd: d.conclusionMd,
            targetAssumptionId: d.targetAssumptionId,
            startedAt: d.startedAt,
            endedAt: d.endedAt,
            mergedIntoId: primary.id,
            sync: tombMetas[i].copyWith(deletedAt: tombMetas[i].updatedAt),
          ),
        );
      }
    });
    return survivor;
  }

  // Large cap for full-table redirect scans during a merge — every live row
  // referencing a duplicate must be re-pointed, so we can't page.
  static const int _all = 100000;

  // Replace any id in [ids] that is a duplicate with [survivorId], dedup,
  // preserving order.
  List<String> _redirectIds(
    List<String> ids,
    Set<String> dupIds,
    String survivorId,
  ) {
    final out = <String>[];
    for (final id in ids) {
      final next = dupIds.contains(id) ? survivorId : id;
      if (!out.contains(next)) out.add(next);
    }
    return out;
  }

  // Rebuild a decision row, overriding only the reference fields a merge
  // touches plus a fresh stamp. [deletedSync] tombstones the row (used for
  // the duplicate side); otherwise [sync] carries a normal update stamp.
  KnowledgeDecision _redirectDecision(
    KnowledgeDecision d, {
    List<String>? principleIds,
    List<String>? assumptionIds,
    String? supersededByDecisionId,
    String? mergedIntoId,
    SyncMeta? sync,
    SyncMeta? deletedSync,
  }) {
    final meta = deletedSync != null
        ? deletedSync.copyWith(deletedAt: deletedSync.updatedAt)
        : sync!;
    return KnowledgeDecision(
      id: d.id,
      question: d.question,
      options: d.options,
      selectedLabel: d.selectedLabel,
      rationaleMd: d.rationaleMd,
      principleIds: principleIds ?? d.principleIds,
      assumptionIds: assumptionIds ?? d.assumptionIds,
      expectedOutcome: d.expectedOutcome,
      reviewDate: d.reviewDate,
      actualOutcomeMd: d.actualOutcomeMd,
      status: d.status,
      supersededByDecisionId:
          supersededByDecisionId ?? d.supersededByDecisionId,
      contextSnapshot: d.contextSnapshot,
      decidedAt: d.decidedAt,
      mergedIntoId: mergedIntoId ?? d.mergedIntoId,
      sync: meta,
    );
  }

  KnowledgeExperiment _redirectExperiment(
    KnowledgeExperiment e, {
    required String targetAssumptionId,
    required SyncMeta sync,
  }) => KnowledgeExperiment(
    id: e.id,
    hypothesis: e.hypothesis,
    methodMd: e.methodMd,
    metrics: e.metrics,
    status: e.status,
    resultMd: e.resultMd,
    conclusionMd: e.conclusionMd,
    targetAssumptionId: targetAssumptionId,
    startedAt: e.startedAt,
    endedAt: e.endedAt,
    mergedIntoId: e.mergedIntoId,
    sync: sync,
  );

  Future<void> _tombstonePrinciple(
    KnowledgePrinciple p,
    String survivorId,
    SyncMeta meta,
  ) => upsertPrinciple(
    KnowledgePrinciple(
      id: p.id,
      statement: p.statement,
      rationaleMd: p.rationaleMd,
      scope: p.scope,
      status: p.status,
      declaredAt: p.declaredAt,
      mergedIntoId: survivorId,
      sync: meta.copyWith(deletedAt: meta.updatedAt),
    ),
  );

  Future<void> _tombstoneAssumption(
    KnowledgeAssumption a,
    String survivorId,
    SyncMeta meta,
  ) => upsertAssumption(
    KnowledgeAssumption(
      id: a.id,
      statement: a.statement,
      confidence: a.confidence,
      scope: a.scope,
      evidenceIds: a.evidenceIds,
      status: a.status,
      declaredAt: a.declaredAt,
      lastVerifiedAt: a.lastVerifiedAt,
      mergedIntoId: survivorId,
      sync: meta.copyWith(deletedAt: meta.updatedAt),
    ),
  );

  // ---------- Row → model ----------

  KnowledgeNote _noteFromRow(KnowledgeNoteRow r) => KnowledgeNote(
    id: r.id,
    title: r.title,
    bodyMd: r.bodyMd,
    sourceUrl: r.sourceUrl,
    tags: decodeStringList(r.tagsJson),
    projectTag: r.projectTag,
    createdAt: r.createdAt,
    mergedIntoId: r.mergedIntoId,
    sync: SyncMeta(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );

  KnowledgePrinciple _principleFromRow(KnowledgePrincipleRow r) =>
      KnowledgePrinciple(
        id: r.id,
        statement: r.statement,
        rationaleMd: r.rationaleMd,
        scope: r.scope,
        status: PrincipleStatus.parse(r.status),
        declaredAt: r.declaredAt,
        mergedIntoId: r.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: r.ownerUserId,
          updatedAt: r.updatedAt,
          updatedByDevice: r.updatedByDevice,
          hlc: r.hlc,
          deletedAt: r.deletedAt,
        ),
      );

  KnowledgeAssumption _assumptionFromRow(KnowledgeAssumptionRow r) =>
      KnowledgeAssumption(
        id: r.id,
        statement: r.statement,
        confidence: r.confidence,
        scope: r.scope,
        evidenceIds: decodeStringList(r.evidenceIdsJson),
        status: AssumptionStatus.parse(r.status),
        declaredAt: r.declaredAt,
        lastVerifiedAt: r.lastVerifiedAt,
        mergedIntoId: r.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: r.ownerUserId,
          updatedAt: r.updatedAt,
          updatedByDevice: r.updatedByDevice,
          hlc: r.hlc,
          deletedAt: r.deletedAt,
        ),
      );

  KnowledgeDecision _decisionFromRow(KnowledgeDecisionRow r) =>
      KnowledgeDecision(
        id: r.id,
        question: r.question,
        options: DecisionOption.decode(r.optionsJson),
        selectedLabel: r.selectedLabel,
        rationaleMd: r.rationaleMd,
        principleIds: decodeStringList(r.principleIdsJson),
        assumptionIds: decodeStringList(r.assumptionIdsJson),
        expectedOutcome: r.expectedOutcome,
        reviewDate: r.reviewDate,
        actualOutcomeMd: r.actualOutcomeMd,
        status: DecisionStatus.parse(r.status),
        supersededByDecisionId: r.supersededByDecisionId,
        contextSnapshot: decodeNullableJsonMap(r.contextSnapshotJson),
        decidedAt: r.decidedAt,
        mergedIntoId: r.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: r.ownerUserId,
          updatedAt: r.updatedAt,
          updatedByDevice: r.updatedByDevice,
          hlc: r.hlc,
          deletedAt: r.deletedAt,
        ),
      );

  KnowledgeConcept _conceptFromRow(KnowledgeConceptRow r) => KnowledgeConcept(
    id: r.id,
    name: r.name,
    aliases: decodeStringList(r.aliasesJson),
    summaryMd: r.summaryMd,
    relatedConceptIds: decodeStringList(r.relatedConceptIdsJson),
    createdAt: r.createdAt,
    mergedIntoId: r.mergedIntoId,
    sync: SyncMeta(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );

  KnowledgeRoutine _routineFromRow(KnowledgeRoutineRow r) => KnowledgeRoutine(
    id: r.id,
    statement: r.statement,
    intervalDays: r.intervalDays,
    lastDoneAt: r.lastDoneAt,
    nextDueAt: r.nextDueAt,
    scope: r.scope,
    status: RoutineStatus.parse(r.status),
    createdAt: r.createdAt,
    sync: SyncMeta(
      ownerUserId: r.ownerUserId,
      updatedAt: r.updatedAt,
      updatedByDevice: r.updatedByDevice,
      hlc: r.hlc,
      deletedAt: r.deletedAt,
    ),
  );

  KnowledgeExperiment _experimentFromRow(KnowledgeExperimentRow r) =>
      KnowledgeExperiment(
        id: r.id,
        hypothesis: r.hypothesis,
        methodMd: r.methodMd,
        metrics: decodeStringList(r.metricsJson),
        status: ExperimentStatus.parse(r.status),
        resultMd: r.resultMd,
        conclusionMd: r.conclusionMd,
        targetAssumptionId: r.targetAssumptionId,
        startedAt: r.startedAt,
        endedAt: r.endedAt,
        mergedIntoId: r.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: r.ownerUserId,
          updatedAt: r.updatedAt,
          updatedByDevice: r.updatedByDevice,
          hlc: r.hlc,
          deletedAt: r.deletedAt,
        ),
      );
}
