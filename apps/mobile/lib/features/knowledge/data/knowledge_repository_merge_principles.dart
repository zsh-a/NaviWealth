part of 'knowledge_repository.dart';

Future<KnowledgePrinciple> _mergeKnowledgePrinciples(
  KnowledgeRepositoryMerge repo, {
  required KnowledgePrinciple primary,
  required List<KnowledgePrinciple> duplicates,
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
      .where((d) => d.principleIds.any(dupIds.contains))
      .toList(growable: false);

  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];
  final refMetas = <SyncMeta>[
    for (var i = 0; i < affected.length; i++) await stamp(),
  ];

  final survivor = KnowledgePrinciple(
    id: primary.id,
    statement: primary.statement,
    rationaleMd: primary.rationaleMd,
    scope: primary.scope,
    status: primary.status,
    declaredAt: primary.declaredAt,
    sync: survivorMeta,
  );

  await repo._db.transaction(() async {
    await repo.upsertPrinciple(survivor);
    for (var i = 0; i < dups.length; i++) {
      await _tombstoneKnowledgePrinciple(
        repo,
        dups[i],
        primary.id,
        tombMetas[i],
      );
    }
    for (var i = 0; i < affected.length; i++) {
      final d = affected[i];
      await repo.upsertDecision(
        _redirectKnowledgeDecision(
          d,
          principleIds: _redirectKnowledgeIds(
            d.principleIds,
            dupIds,
            primary.id,
          ),
          sync: refMetas[i],
        ),
      );
    }
  });
  return survivor;
}
