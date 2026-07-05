part of 'knowledge_repository.dart';

Future<KnowledgeDecision> _mergeKnowledgeDecisions(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeDecision primary,
  required List<KnowledgeDecision> duplicates,
  required Future<SyncMeta> Function() stamp,
}) async {
  final dups = duplicates
      .where((d) => d.id != primary.id)
      .toList(growable: false);
  final dupIds = dups.map((d) => d.id).toSet();
  final ownerUserId = primary.sync.ownerUserId;

  final decisions = await repo.listDecisions(
    ownerUserId: ownerUserId,
    limit: _knowledgeRepositoryFullScanLimit,
  );
  final affected = decisions
      .where(
        (d) =>
            d.id != primary.id &&
            !dupIds.contains(d.id) &&
            dupIds.contains(d.supersededByDecisionId),
      )
      .toList(growable: false);

  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];
  final refMetas = <SyncMeta>[
    for (var i = 0; i < affected.length; i++) await stamp(),
  ];

  final survivor = _redirectKnowledgeDecision(primary, sync: survivorMeta);

  await repo._db.transaction(() async {
    await repo.upsertDecision(survivor);
    for (var i = 0; i < dups.length; i++) {
      final d = dups[i];
      await repo.upsertDecision(
        _redirectKnowledgeDecision(
          d,
          mergedIntoId: primary.id,
          deletedSync: tombMetas[i],
        ),
      );
    }
    for (var i = 0; i < affected.length; i++) {
      await repo.upsertDecision(
        _redirectKnowledgeDecision(
          affected[i],
          supersededByDecisionId: primary.id,
          sync: refMetas[i],
        ),
      );
    }
  });
  return survivor;
}
