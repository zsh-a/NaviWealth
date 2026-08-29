part of 'knowledge_repository.dart';

Future<KnowledgeNote> _mergeKnowledgeNotes(
  KnowledgeRepositoryMerge repo, {
  required KnowledgeNote primary,
  required List<KnowledgeNote> duplicates,
  required Future<SyncMeta> Function() stamp,
  String? mergedTitle,
  String? mergedBody,
}) async {
  final dups = duplicates
      .where((d) => d.id != primary.id)
      .toList(growable: false);
  final mergedTags = <String>{...primary.tags};
  for (final d in dups) {
    mergedTags.addAll(d.tags);
  }
  final survivorMeta = await stamp();
  final tombMetas = <SyncMeta>[
    for (var i = 0; i < dups.length; i++) await stamp(),
  ];

  final survivor = KnowledgeNote(
    id: primary.id,
    title: (mergedTitle != null && mergedTitle.trim().isNotEmpty)
        ? mergedTitle.trim()
        : primary.title,
    bodyMd: (mergedBody != null && mergedBody.trim().isNotEmpty)
        ? mergedBody.trim()
        : primary.bodyMd,
    sourceUrl: primary.sourceUrl,
    tags: mergedTags.toList(growable: false),
    createdAt: primary.createdAt,
    sync: survivorMeta,
  );

  await repo._db.transaction(() async {
    await repo.upsertNote(survivor);
    for (var i = 0; i < dups.length; i++) {
      final d = dups[i];
      final meta = tombMetas[i];
      await repo.upsertNote(
        KnowledgeNote(
          id: d.id,
          title: d.title,
          bodyMd: d.bodyMd,
          sourceUrl: d.sourceUrl,
          tags: d.tags,
          createdAt: d.createdAt,
          mergedIntoId: primary.id,
          sync: meta.copyWith(deletedAt: meta.updatedAt),
        ),
      );
    }
  });
  return survivor;
}
