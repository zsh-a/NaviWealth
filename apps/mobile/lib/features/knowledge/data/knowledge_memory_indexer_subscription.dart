part of 'knowledge_object_memory_indexers.dart';

String _truncate(String s, [int n = kKnowledgeExcerptMaxChars]) =>
    knowledgeExcerpt(s, max: n);

Future<void> _forgetMissingSourceIds(
  MemoryRuntime runtime, {
  required String ownerUserId,
  required String source,
  required Set<String> liveSourceIds,
}) {
  return runtime.forgetSourceExcept(
    ownerUserId: ownerUserId,
    source: source,
    keepSourceIds: liveSourceIds,
  );
}

Future<void> recordKnowledgeStateEvent(
  MemoryRuntime runtime, {
  required String ownerUserId,
  required String kind,
  required String sourceFamily,
  required String rowId,
  required String fingerprint,
  required DateTime occurredAt,
  required DateTime observedAt,
  required String title,
  required String summary,
  required Map<String, Object?> facts,
  required Set<String> entities,
  required double importance,
  double confidence = 1,
}) {
  return runtime.recordEvent(
    EventRecord(
      id: '$sourceFamily:$kind:$rowId',
      domain: DomainScope.knowledge,
      kind: EventKind.domain(DomainScope.knowledge, kind),
      occurredAt: occurredAt.toUtc(),
      observedAt: observedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.knowledge,
        rowFamily: sourceFamily,
        rowId: rowId,
        fingerprint: fingerprint,
      ),
      ownerUserId: ownerUserId,
      title: title,
      summary: summary,
      facts: facts,
      entities: entities,
      importance: importance,
      confidence: confidence,
    ),
  );
}

/// Shared subscribe-then-reindex plumbing for every KnowledgeOS indexer
/// provider, Decision included (`docs/domains/knowledgeos-domain.md` §3).
///
/// Each indexer used to repeat ~15 lines of identical Riverpod
/// boilerplate: opt-in gate -> resolve repo/userId/runtime -> re-entrance
/// guard -> subscribe -> reindex on emit -> dispose. The varying parts
/// are only the stream factory and the reindex callback, so they're the
/// only parameters; everything else is enforced here.
void subscribeKnowledgeIndexer<T>(
  Ref ref, {
  required Stream<List<T>> Function(KnowledgeRepository repo, String userId)
  streamOf,
  required Future<void> Function(
    MemoryRuntime runtime,
    List<T> rows, {
    required String ownerUserId,
  })
  reindex,
}) {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.knowledge)) return;
  () async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    List<T>? pendingRows;
    final sub = streamOf(repo, userId).listen((rows) async {
      if (running) {
        pendingRows = rows;
        return;
      }
      running = true;
      try {
        var currentRows = rows;
        while (true) {
          await reindex(runtime, currentRows, ownerUserId: userId);
          final nextRows = pendingRows;
          pendingRows = null;
          if (nextRows == null) break;
          currentRows = nextRows;
        }
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
}
