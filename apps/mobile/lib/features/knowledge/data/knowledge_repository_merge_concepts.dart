part of 'knowledge_repository.dart';

Future<KnowledgeConcept> _mergeKnowledgeConcepts(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeConcept primary,
  required List<KnowledgeConcept> duplicates,
  required Future<SyncMeta> Function() stamp,
  String? mergedName,
  String? mergedSummary,
}) async {
  final dups = duplicates
      .where((d) => d.id != primary.id)
      .toList(growable: false);
  final dupIds = dups.map((d) => d.id).toSet();

  final aliases = <String>{...primary.aliases};
  final related = <String>{...primary.relatedConceptIds};
  for (final d in dups) {
    aliases.addAll(d.aliases);
    aliases.add(d.name);
    related.addAll(d.relatedConceptIds);
  }
  related.removeAll(dupIds);
  related.remove(primary.id);
  aliases.remove(primary.name);

  final ownerUserId = primary.sync.ownerUserId;
  final all = await repo.listConcepts(ownerUserId: ownerUserId);
  final repoints = <(KnowledgeConcept, List<String>)>[];
  for (final c in all) {
    if (c.id == primary.id || dupIds.contains(c.id)) continue;
    if (!c.relatedConceptIds.any(dupIds.contains)) continue;
    final next = <String>{
      for (final r in c.relatedConceptIds) dupIds.contains(r) ? primary.id : r,
    }..remove(c.id);
    repoints.add((c, next.toList(growable: false)));
  }

  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];
  final repointMetas = <SyncMeta>[
    for (var i = 0; i < repoints.length; i++) await stamp(),
  ];

  final survivor = KnowledgeConcept(
    id: primary.id,
    name: (mergedName != null && mergedName.trim().isNotEmpty)
        ? mergedName.trim()
        : primary.name,
    aliases: aliases.toList(growable: false),
    summaryMd: (mergedSummary != null && mergedSummary.trim().isNotEmpty)
        ? mergedSummary.trim()
        : primary.summaryMd,
    relatedConceptIds: related.toList(growable: false),
    createdAt: primary.createdAt,
    sync: survivorMeta,
  );

  await repo._db.transaction(() async {
    await repo.upsertConcept(survivor);
    for (var i = 0; i < dups.length; i++) {
      final d = dups[i];
      final meta = tombMetas[i];
      await repo.upsertConcept(
        KnowledgeConcept(
          id: d.id,
          name: d.name,
          aliases: d.aliases,
          summaryMd: d.summaryMd,
          relatedConceptIds: d.relatedConceptIds,
          createdAt: d.createdAt,
          mergedIntoId: primary.id,
          sync: meta.copyWith(deletedAt: meta.updatedAt),
        ),
      );
    }
    for (var i = 0; i < repoints.length; i++) {
      final (c, next) = repoints[i];
      await repo.upsertConcept(
        KnowledgeConcept(
          id: c.id,
          name: c.name,
          aliases: c.aliases,
          summaryMd: c.summaryMd,
          relatedConceptIds: next,
          createdAt: c.createdAt,
          mergedIntoId: c.mergedIntoId,
          sync: repointMetas[i],
        ),
      );
    }
  });
  return survivor;
}

Future<(KnowledgeConcept, KnowledgeConcept)> _linkKnowledgeConcepts(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeConcept a,
  required KnowledgeConcept b,
  required Future<SyncMeta> Function() stamp,
}) async {
  final aMeta = await stamp();
  final bMeta = await stamp();
  final aNext = (<String>{
    ...a.relatedConceptIds,
    b.id,
  }..remove(a.id)).toList(growable: false);
  final bNext = (<String>{
    ...b.relatedConceptIds,
    a.id,
  }..remove(b.id)).toList(growable: false);
  final updatedA = KnowledgeConcept(
    id: a.id,
    name: a.name,
    aliases: a.aliases,
    summaryMd: a.summaryMd,
    relatedConceptIds: aNext,
    createdAt: a.createdAt,
    mergedIntoId: a.mergedIntoId,
    sync: aMeta,
  );
  final updatedB = KnowledgeConcept(
    id: b.id,
    name: b.name,
    aliases: b.aliases,
    summaryMd: b.summaryMd,
    relatedConceptIds: bNext,
    createdAt: b.createdAt,
    mergedIntoId: b.mergedIntoId,
    sync: bMeta,
  );
  await repo._db.transaction(() async {
    await repo.upsertConcept(updatedA);
    await repo.upsertConcept(updatedB);
  });
  return (updatedA, updatedB);
}
