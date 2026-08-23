part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexAssumptions(
  MemoryRuntime runtime,
  List<KnowledgeAssumption> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeAssumptionMemorySource,
    liveSourceIds: {for (final a in xs) a.id},
  );
  for (final a in xs) {
    final id = '$kKnowledgeAssumptionMemorySource:semantic:${a.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        role: MemoryRole.guidance,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: a.scope,
        source: kKnowledgeAssumptionMemorySource,
        sourceId: a.id,
        title: a.statement,
        summary: a.statement,
        payload: <String, Object?>{
          'status': a.status.wire,
          'confidence': a.confidence,
          'evidence_ids': a.evidenceIds,
          if (a.lastVerifiedAt != null)
            'last_verified_at': a.lastVerifiedAt!.toUtc().toIso8601String(),
        },
        entities: <String>{'knowledge_assumption', a.id},
        // Map the user's own stated confidence directly. Falsified
        // assumptions stay in memory (so ContradictionAgent can still
        // see them) but with much lower importance.
        importance: switch (a.status) {
          AssumptionStatus.active => a.confidence,
          AssumptionStatus.weakened => a.confidence * 0.5,
          AssumptionStatus.falsified => 0.2,
          AssumptionStatus.retired => 0.2,
        },
        confidence: a.confidence,
        validFrom: a.declaredAt.toUtc(),
        createdAt: a.declaredAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeAssumptionMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeAssumption>(
    ref,
    streamOf: (r, uid) => r.watchAssumptions(ownerUserId: uid),
    reindex: _reindexAssumptions,
  );
});
