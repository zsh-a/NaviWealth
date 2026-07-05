part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexConcepts(
  MemoryRuntime runtime,
  List<KnowledgeConcept> cs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeConceptMemorySource,
    liveSourceIds: {for (final c in cs) c.id},
  );
  for (final c in cs) {
    final id = '$kKnowledgeConceptMemorySource:semantic:${c.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeConceptMemorySource,
        sourceId: c.id,
        title: c.name,
        summary: c.summaryMd.isEmpty
            ? c.name
            : '${c.name}: ${_truncate(c.summaryMd)}',
        payload: <String, Object?>{
          'aliases': c.aliases,
          'summary_md': c.summaryMd,
          'related_concept_ids': c.relatedConceptIds,
        },
        entities: <String>{
          'knowledge_concept',
          c.id,
          ...c.aliases.map((a) => 'alias:$a'),
        },
        importance: 0.7,
        confidence: 0.9,
        validFrom: c.createdAt.toUtc(),
        createdAt: c.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeConceptMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeConcept>(
    ref,
    streamOf: (r, uid) => r.watchConcepts(ownerUserId: uid),
    reindex: _reindexConcepts,
  );
});
