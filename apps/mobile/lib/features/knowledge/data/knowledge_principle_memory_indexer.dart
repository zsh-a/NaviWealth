part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexPrinciples(
  MemoryRuntime runtime,
  List<KnowledgePrinciple> ps, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgePrincipleMemorySource,
    liveSourceIds: {for (final p in ps) p.id},
  );
  for (final p in ps) {
    final id = '$kKnowledgePrincipleMemorySource:semantic:${p.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        ownerUserId: ownerUserId,
        scope: p.scope,
        source: kKnowledgePrincipleMemorySource,
        sourceId: p.id,
        title: p.statement,
        summary: p.rationaleMd.isEmpty
            ? p.statement
            : '${p.statement} — ${_truncate(p.rationaleMd)}',
        payload: <String, Object?>{
          'rationale_md': p.rationaleMd,
          'status': p.status.wire,
        },
        entities: <String>{'knowledge_principle', p.id},
        // Active principles outrank retired ones for recall.
        importance: switch (p.status) {
          PrincipleStatus.active => 0.9,
          PrincipleStatus.paused => 0.6,
          PrincipleStatus.retired => 0.4,
        },
        confidence: 0.95,
        validFrom: p.declaredAt.toUtc(),
        createdAt: p.declaredAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgePrincipleMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgePrinciple>(
    ref,
    streamOf: (r, uid) => r.watchPrinciples(ownerUserId: uid),
    reindex: _reindexPrinciples,
  );
});
