part of 'knowledge_repository.dart';

const int _knowledgeRepositoryFullScanLimit = 100000;

mixin KnowledgeRepositoryMerge {
  AppDatabase get _db;

  Future<void> upsertNote(KnowledgeNote note);

  Future<void> upsertDecision(KnowledgeDecision decision);

  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
    int offset = 0,
  });

  Future<KnowledgeNote> mergeNotes({
    required KnowledgeNote primary,
    required List<KnowledgeNote> duplicates,
    required Future<SyncMeta> Function() stamp,
    String? mergedTitle,
    String? mergedBody,
  }) => _mergeKnowledgeNotes(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
    mergedTitle: mergedTitle,
    mergedBody: mergedBody,
  );

  Future<KnowledgeDecision> mergeDecisions({
    required KnowledgeDecision primary,
    required List<KnowledgeDecision> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) => _mergeKnowledgeDecisions(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
  );
}
