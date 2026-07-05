part of 'knowledge_repository.dart';

Future<KnowledgeExperiment> _mergeKnowledgeExperiments(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeExperiment primary,
  required List<KnowledgeExperiment> duplicates,
  required Future<SyncMeta> Function() stamp,
}) async {
  final dups = duplicates
      .where((d) => d.id != primary.id)
      .toList(growable: false);
  final metrics = <String>{...primary.metrics};
  for (final d in dups) {
    metrics.addAll(d.metrics);
  }
  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];

  final survivor = KnowledgeExperiment(
    id: primary.id,
    hypothesis: primary.hypothesis,
    methodMd: primary.methodMd,
    metrics: metrics.toList(growable: false),
    status: primary.status,
    resultMd: primary.resultMd,
    conclusionMd: primary.conclusionMd,
    targetAssumptionId: primary.targetAssumptionId,
    startedAt: primary.startedAt,
    endedAt: primary.endedAt,
    sync: survivorMeta,
  );

  await repo._db.transaction(() async {
    await repo.upsertExperiment(survivor);
    for (var i = 0; i < dups.length; i++) {
      final d = dups[i];
      await repo.upsertExperiment(
        KnowledgeExperiment(
          id: d.id,
          hypothesis: d.hypothesis,
          methodMd: d.methodMd,
          metrics: d.metrics,
          status: d.status,
          resultMd: d.resultMd,
          conclusionMd: d.conclusionMd,
          targetAssumptionId: d.targetAssumptionId,
          startedAt: d.startedAt,
          endedAt: d.endedAt,
          mergedIntoId: primary.id,
          sync: tombMetas[i].copyWith(deletedAt: tombMetas[i].updatedAt),
        ),
      );
    }
  });
  return survivor;
}
