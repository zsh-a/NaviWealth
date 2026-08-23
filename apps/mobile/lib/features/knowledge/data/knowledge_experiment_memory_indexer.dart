part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexExperiments(
  MemoryRuntime runtime,
  List<KnowledgeExperiment> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeExperimentMemorySource,
    liveSourceIds: {for (final e in xs) e.id},
  );
  for (final e in xs) {
    final id = '$kKnowledgeExperimentMemorySource:episodic:${e.id}';
    final body = e.methodMd.isEmpty
        ? e.hypothesis
        : '${e.hypothesis} — method: ${_truncate(e.methodMd)}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        role: MemoryRole.episode,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeExperimentMemorySource,
        sourceId: e.id,
        title: e.hypothesis,
        summary: body,
        payload: <String, Object?>{
          'method_md': e.methodMd,
          'metrics': e.metrics,
          'status': e.status.wire,
          if (e.resultMd != null) 'result_md': e.resultMd,
          if (e.conclusionMd != null) 'conclusion_md': e.conclusionMd,
          if (e.targetAssumptionId != null)
            'target_assumption_id': e.targetAssumptionId,
          if (e.endedAt != null)
            'ended_at': e.endedAt!.toUtc().toIso8601String(),
        },
        entities: <String>{
          'knowledge_experiment',
          e.id,
          if (e.targetAssumptionId != null)
            'assumption:${e.targetAssumptionId}',
        },
        importance: switch (e.status) {
          ExperimentStatus.running => 0.8,
          ExperimentStatus.done => 0.85,
          ExperimentStatus.planned => 0.5,
          ExperimentStatus.abandoned => 0.4,
        },
        confidence: 0.85,
        validFrom: e.startedAt.toUtc(),
        createdAt: e.startedAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeExperimentMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeExperiment>(
    ref,
    streamOf: (r, uid) => r.watchExperiments(ownerUserId: uid),
    reindex: _reindexExperiments,
  );
});
