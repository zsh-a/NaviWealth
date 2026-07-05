part of 'knowledge_repository.dart';

Future<KnowledgeAssumption> _mergeKnowledgeAssumptions(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeAssumption primary,
  required List<KnowledgeAssumption> duplicates,
  required Future<SyncMeta> Function() stamp,
}) async {
  final dups = duplicates
      .where((d) => d.id != primary.id)
      .toList(growable: false);
  final dupIds = dups.map((d) => d.id).toSet();
  final ownerUserId = primary.sync.ownerUserId;

  final evidence = <String>{...primary.evidenceIds};
  for (final d in dups) {
    evidence.addAll(d.evidenceIds);
  }

  final decisions = await repo.listDecisions(
    ownerUserId: ownerUserId,
    limit: _knowledgeRepositoryFullScanLimit,
  );
  final affectedDecisions = decisions
      .where((d) => d.assumptionIds.any(dupIds.contains))
      .toList(growable: false);
  final experiments = await repo.listExperiments(
    ownerUserId: ownerUserId,
    limit: _knowledgeRepositoryFullScanLimit,
  );
  final affectedExperiments = experiments
      .where((e) => dupIds.contains(e.targetAssumptionId))
      .toList(growable: false);

  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];
  final decMetas = <SyncMeta>[
    for (var i = 0; i < affectedDecisions.length; i++) await stamp(),
  ];
  final expMetas = <SyncMeta>[
    for (var i = 0; i < affectedExperiments.length; i++) await stamp(),
  ];

  final survivor = KnowledgeAssumption(
    id: primary.id,
    statement: primary.statement,
    confidence: primary.confidence,
    scope: primary.scope,
    evidenceIds: evidence.toList(growable: false),
    status: primary.status,
    declaredAt: primary.declaredAt,
    lastVerifiedAt: primary.lastVerifiedAt,
    sync: survivorMeta,
  );

  await repo._db.transaction(() async {
    await repo.upsertAssumption(survivor);
    for (var i = 0; i < dups.length; i++) {
      await _tombstoneKnowledgeAssumption(
        repo,
        dups[i],
        primary.id,
        tombMetas[i],
      );
    }
    for (var i = 0; i < affectedDecisions.length; i++) {
      final d = affectedDecisions[i];
      await repo.upsertDecision(
        _redirectKnowledgeDecision(
          d,
          assumptionIds: _redirectKnowledgeIds(
            d.assumptionIds,
            dupIds,
            primary.id,
          ),
          sync: decMetas[i],
        ),
      );
    }
    for (var i = 0; i < affectedExperiments.length; i++) {
      final e = affectedExperiments[i];
      await repo.upsertExperiment(
        _redirectKnowledgeExperiment(
          e,
          targetAssumptionId: primary.id,
          sync: expMetas[i],
        ),
      );
    }
  });
  return survivor;
}
