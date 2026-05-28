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

class KnowledgeRepository {
  KnowledgeRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  final AppDatabase _db;
  final OutboxStore _outbox;

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
      ownerUserId: note.sync.ownerUserId,
      updatedAt: note.sync.updatedAt,
      updatedByDevice: note.sync.updatedByDevice,
      hlc: note.sync.hlc,
      deletedAt: Value(note.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeNotes)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _notesTable, rowId: note.id);
    });
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

  Future<void> upsertPrinciple(KnowledgePrinciple p) async {
    final companion = KnowledgePrinciplesCompanion.insert(
      id: p.id,
      statement: p.statement,
      rationaleMd: Value(p.rationaleMd),
      scope: Value(p.scope),
      status: Value(p.status.wire),
      declaredAt: p.declaredAt,
      ownerUserId: p.sync.ownerUserId,
      updatedAt: p.sync.updatedAt,
      updatedByDevice: p.sync.updatedByDevice,
      hlc: p.sync.hlc,
      deletedAt: Value(p.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgePrinciples)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _principlesTable, rowId: p.id);
    });
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
      ownerUserId: a.sync.ownerUserId,
      updatedAt: a.sync.updatedAt,
      updatedByDevice: a.sync.updatedByDevice,
      hlc: a.sync.hlc,
      deletedAt: Value(a.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeAssumptions)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _assumptionsTable, rowId: a.id);
    });
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
        (t) => t.status.isIn(statuses.map((s) => s.wire).toList(growable: false)),
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
      ownerUserId: d.sync.ownerUserId,
      updatedAt: d.sync.updatedAt,
      updatedByDevice: d.sync.updatedByDevice,
      hlc: d.sync.hlc,
      deletedAt: Value(d.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeDecisions)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _decisionsTable, rowId: d.id);
    });
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
      ownerUserId: c.sync.ownerUserId,
      updatedAt: c.sync.updatedAt,
      updatedByDevice: c.sync.updatedByDevice,
      hlc: c.sync.hlc,
      deletedAt: Value(c.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeConcepts)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _conceptsTable, rowId: c.id);
    });
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
      ownerUserId: e.sync.ownerUserId,
      updatedAt: e.sync.updatedAt,
      updatedByDevice: e.sync.updatedByDevice,
      hlc: e.sync.hlc,
      deletedAt: Value(e.sync.deletedAt),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.knowledgeExperiments)
          .insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: _experimentsTable, rowId: e.id);
    });
  }

  // ---------- Row → model ----------

  KnowledgeNote _noteFromRow(KnowledgeNoteRow r) => KnowledgeNote(
    id: r.id,
    title: r.title,
    bodyMd: r.bodyMd,
    sourceUrl: r.sourceUrl,
    tags: decodeStringList(r.tagsJson),
    projectTag: r.projectTag,
    createdAt: r.createdAt,
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
        sync: SyncMeta(
          ownerUserId: r.ownerUserId,
          updatedAt: r.updatedAt,
          updatedByDevice: r.updatedByDevice,
          hlc: r.hlc,
          deletedAt: r.deletedAt,
        ),
      );
}
