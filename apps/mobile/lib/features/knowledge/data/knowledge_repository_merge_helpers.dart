part of 'knowledge_repository.dart';

KnowledgeDecision _redirectKnowledgeDecision(
  KnowledgeDecision decision, {
  String? supersededByDecisionId,
  String? mergedIntoId,
  SyncMeta? sync,
  SyncMeta? deletedSync,
}) {
  final meta = deletedSync != null
      ? deletedSync.copyWith(deletedAt: deletedSync.updatedAt)
      : sync!;
  return KnowledgeDecision(
    id: decision.id,
    question: decision.question,
    options: decision.options,
    selectedLabel: decision.selectedLabel,
    rationaleMd: decision.rationaleMd,
    expectedOutcome: decision.expectedOutcome,
    reviewDate: decision.reviewDate,
    revisitConditions: decision.revisitConditions,
    actualOutcomeMd: decision.actualOutcomeMd,
    status: decision.status,
    supersededByDecisionId:
        supersededByDecisionId ?? decision.supersededByDecisionId,
    decidedAt: decision.decidedAt,
    mergedIntoId: mergedIntoId ?? decision.mergedIntoId,
    sync: meta,
  );
}
