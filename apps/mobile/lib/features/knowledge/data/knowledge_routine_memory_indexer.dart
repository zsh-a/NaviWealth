part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexRoutines(
  MemoryRuntime runtime,
  List<KnowledgeRoutine> routines, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeRoutineMemorySource,
    liveSourceIds: {for (final r in routines) r.id},
  );
  for (final r in routines) {
    final id = '$kKnowledgeRoutineMemorySource:episodic:${r.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        role: MemoryRole.guidance,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: r.scope,
        source: kKnowledgeRoutineMemorySource,
        sourceId: r.id,
        title: r.statement,
        summary:
            '${r.statement} — every ${r.intervalDays} days; next due '
            '${r.nextDueAt.toUtc().toIso8601String()}',
        payload: <String, Object?>{
          'interval_days': r.intervalDays,
          'status': r.status.wire,
          'next_due_at': r.nextDueAt.toUtc().toIso8601String(),
          if (r.lastDoneAt != null)
            'last_done_at': r.lastDoneAt!.toUtc().toIso8601String(),
        },
        entities: <String>{'knowledge_routine', r.id, 'scope:${r.scope}'},
        importance: switch (r.status) {
          RoutineStatus.active => 0.65,
          RoutineStatus.paused => 0.35,
          RoutineStatus.archived => 0.25,
        },
        confidence: 0.9,
        validFrom: r.createdAt.toUtc(),
        createdAt: r.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeRoutineMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeRoutine>(
    ref,
    streamOf: (r, uid) => r.watchRoutines(ownerUserId: uid),
    reindex: _reindexRoutines,
  );
});
