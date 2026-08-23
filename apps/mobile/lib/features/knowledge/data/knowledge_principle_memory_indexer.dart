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
    final summary = p.rationaleMd.isEmpty
        ? p.statement
        : '${p.statement} — ${_truncate(p.rationaleMd)}';
    final importance = switch (p.status) {
      PrincipleStatus.active => 0.9,
      PrincipleStatus.paused => 0.6,
      PrincipleStatus.retired => 0.4,
    };
    await recordKnowledgeStateEvent(
      runtime,
      ownerUserId: ownerUserId,
      kind: 'knowledge_principle_state',
      sourceFamily: kKnowledgePrincipleEventSourceFamily,
      rowId: p.id,
      fingerprint: p.sync.hlc.toString(),
      occurredAt: p.sync.updatedAt,
      observedAt: now,
      title: p.statement,
      summary: summary,
      facts: <String, Object?>{'status': p.status.wire, 'scope': p.scope},
      entities: <String>{'knowledge_principle', p.id},
      importance: importance,
      confidence: 1,
    );
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        role: MemoryRole.guidance,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: p.scope,
        source: kKnowledgePrincipleMemorySource,
        sourceId: p.id,
        title: p.statement,
        summary: summary,
        payload: <String, Object?>{
          'rationale_md': p.rationaleMd,
          'status': p.status.wire,
        },
        entities: <String>{'knowledge_principle', p.id},
        // Active principles outrank retired ones for recall.
        importance: importance,
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
