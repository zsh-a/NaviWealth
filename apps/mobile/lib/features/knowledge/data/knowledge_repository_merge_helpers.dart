part of 'knowledge_repository.dart';

// Replace any id in [ids] that is a duplicate with [survivorId], dedup,
// preserving order.
List<String> _redirectKnowledgeIds(
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

// Rebuild a decision row, overriding only the reference fields a merge touches
// plus a fresh stamp. [deletedSync] tombstones the duplicate side; otherwise
// [sync] carries a normal update stamp.
KnowledgeDecision _redirectKnowledgeDecision(
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
    revisitConditions: d.revisitConditions,
    actualOutcomeMd: d.actualOutcomeMd,
    status: d.status,
    supersededByDecisionId: supersededByDecisionId ?? d.supersededByDecisionId,
    contextSnapshot: d.contextSnapshot,
    decidedAt: d.decidedAt,
    mergedIntoId: mergedIntoId ?? d.mergedIntoId,
    sync: meta,
  );
}

KnowledgeExperiment _redirectKnowledgeExperiment(
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

Future<void> _tombstoneKnowledgePrinciple(
  KnowledgeRepositoryMerge repo,
  KnowledgePrinciple p,
  String survivorId,
  SyncMeta meta,
) => repo.upsertPrinciple(
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

Future<void> _tombstoneKnowledgeAssumption(
  KnowledgeRepositoryMerge repo,
  KnowledgeAssumption a,
  String survivorId,
  SyncMeta meta,
) => repo.upsertAssumption(
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
