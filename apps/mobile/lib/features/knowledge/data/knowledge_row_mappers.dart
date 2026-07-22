import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

KnowledgeNotesCompanion knowledgeNoteCompanion(KnowledgeNote note) {
  return KnowledgeNotesCompanion.insert(
    id: note.id,
    title: note.title,
    bodyMd: note.bodyMd,
    sourceUrl: Value(note.sourceUrl),
    tagsJson: Value(encodeStringList(note.tags)),
    projectTag: Value(note.projectTag),
    createdAt: note.createdAt,
    promotedToKind: Value(note.promotedToKind),
    promotedToId: Value(note.promotedToId),
    promotedAt: Value(note.promotedAt),
    mergedIntoId: Value(note.mergedIntoId),
    ownerUserId: note.sync.ownerUserId,
    updatedAt: note.sync.updatedAt,
    updatedByDevice: note.sync.updatedByDevice,
    hlc: note.sync.hlc,
    deletedAt: Value(note.sync.deletedAt),
  );
}

KnowledgePrinciplesCompanion knowledgePrincipleCompanion(KnowledgePrinciple p) {
  return KnowledgePrinciplesCompanion.insert(
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
}

KnowledgeAssumptionsCompanion knowledgeAssumptionCompanion(
  KnowledgeAssumption a,
) {
  return KnowledgeAssumptionsCompanion.insert(
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
}

KnowledgeDecisionsCompanion knowledgeDecisionCompanion(KnowledgeDecision d) {
  return KnowledgeDecisionsCompanion.insert(
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
}

KnowledgeConceptsCompanion knowledgeConceptCompanion(KnowledgeConcept c) {
  return KnowledgeConceptsCompanion.insert(
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
}

KnowledgeExperimentsCompanion knowledgeExperimentCompanion(
  KnowledgeExperiment e,
) {
  return KnowledgeExperimentsCompanion.insert(
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
}

KnowledgeRoutinesCompanion knowledgeRoutineCompanion(KnowledgeRoutine r) {
  return KnowledgeRoutinesCompanion.insert(
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
}

KnowledgeNote knowledgeNoteFromRow(KnowledgeNoteRow r) => KnowledgeNote(
  id: r.id,
  title: r.title,
  bodyMd: r.bodyMd,
  sourceUrl: r.sourceUrl,
  tags: decodeStringList(r.tagsJson),
  projectTag: r.projectTag,
  createdAt: r.createdAt,
  promotedToKind: r.promotedToKind,
  promotedToId: r.promotedToId,
  promotedAt: r.promotedAt,
  mergedIntoId: r.mergedIntoId,
  sync: _syncFromRow(
    ownerUserId: r.ownerUserId,
    updatedAt: r.updatedAt,
    updatedByDevice: r.updatedByDevice,
    hlc: r.hlc,
    deletedAt: r.deletedAt,
  ),
);

KnowledgePrinciple knowledgePrincipleFromRow(KnowledgePrincipleRow r) =>
    KnowledgePrinciple(
      id: r.id,
      statement: r.statement,
      rationaleMd: r.rationaleMd,
      scope: r.scope,
      status: PrincipleStatus.parse(r.status),
      declaredAt: r.declaredAt,
      mergedIntoId: r.mergedIntoId,
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

KnowledgeAssumption knowledgeAssumptionFromRow(KnowledgeAssumptionRow r) =>
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
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

KnowledgeDecision knowledgeDecisionFromRow(KnowledgeDecisionRow r) =>
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
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

KnowledgeConcept knowledgeConceptFromRow(KnowledgeConceptRow r) =>
    KnowledgeConcept(
      id: r.id,
      name: r.name,
      aliases: decodeStringList(r.aliasesJson),
      summaryMd: r.summaryMd,
      relatedConceptIds: decodeStringList(r.relatedConceptIdsJson),
      createdAt: r.createdAt,
      mergedIntoId: r.mergedIntoId,
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

KnowledgeRoutine knowledgeRoutineFromRow(KnowledgeRoutineRow r) =>
    KnowledgeRoutine(
      id: r.id,
      statement: r.statement,
      intervalDays: r.intervalDays,
      lastDoneAt: r.lastDoneAt,
      nextDueAt: r.nextDueAt,
      scope: r.scope,
      status: RoutineStatus.parse(r.status),
      createdAt: r.createdAt,
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

KnowledgeExperiment knowledgeExperimentFromRow(KnowledgeExperimentRow r) =>
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
      sync: _syncFromRow(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );

SyncMeta _syncFromRow({
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
  required DateTime? deletedAt,
}) => SyncMeta(
  ownerUserId: ownerUserId,
  updatedAt: updatedAt,
  updatedByDevice: updatedByDevice,
  hlc: hlc,
  deletedAt: deletedAt,
);

KnowledgeRelationsCompanion knowledgeRelationCompanion(KnowledgeRelation r) =>
    KnowledgeRelationsCompanion.insert(
      id: r.id,
      fromKind: r.fromKind,
      fromId: r.fromId,
      relation: r.relation.wire,
      toKind: r.toKind,
      toId: r.toId,
      createdAt: r.createdAt,
      ownerUserId: r.sync.ownerUserId,
      updatedAt: r.sync.updatedAt,
      updatedByDevice: r.sync.updatedByDevice,
      hlc: r.sync.hlc,
      deletedAt: Value(r.sync.deletedAt),
    );

KnowledgeRelation knowledgeRelationFromRow(KnowledgeRelationRow r) =>
    KnowledgeRelation(
      id: r.id,
      fromKind: r.fromKind,
      fromId: r.fromId,
      relation: KnowledgeRelationType.parse(r.relation),
      toKind: r.toKind,
      toId: r.toId,
      createdAt: r.createdAt,
      sync: SyncMeta(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );
