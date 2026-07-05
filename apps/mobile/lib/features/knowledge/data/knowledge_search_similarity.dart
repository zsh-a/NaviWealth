part of 'knowledge_search_service.dart';

Future<List<KnowledgeSimilarityHit>> _findSimilarKnowledge(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String text,
  Set<String>? types,
  String? excludeId,
  double threshold = 0.82,
  int topK = 5,
}) async {
  final q = text.trim();
  if (q.isEmpty || topK <= 0) return const <KnowledgeSimilarityHit>[];
  final effectiveTopK = topK.clamp(1, 20).toInt();
  final effectiveThreshold = threshold.clamp(0.0, 1.0).toDouble();
  final wantTypes = (types == null || types.isEmpty)
      ? kKnowledgeDedupeMemorySources.keys.toSet()
      : types;
  final sources = <String, String>{
    for (final entry in kKnowledgeDedupeMemorySources.entries)
      if (wantTypes.contains(entry.key)) entry.key: entry.value,
  };
  if (sources.isEmpty) return const <KnowledgeSimilarityHit>[];

  final queryTokens = _tokenize(q);
  final out = <KnowledgeSimilarityHit>[];
  for (final entry in sources.entries) {
    final hits = await service._memoryRuntime.recall(
      ownerUserId: ownerUserId,
      queryText: q,
      source: entry.value,
      topK: (effectiveTopK * 3).clamp(effectiveTopK, 40).toInt(),
    );
    for (final hit in hits) {
      final id = hit.record.sourceId;
      if (id == null) continue;
      if (excludeId != null && excludeId.isNotEmpty && id == excludeId) {
        continue;
      }
      final cosine = hit.semanticSim ?? 0.0;
      if (cosine < effectiveThreshold) continue;
      final doc = await _documentForId(
        service,
        ownerUserId: ownerUserId,
        kind: entry.key,
        id: id,
      );
      if (doc == null) continue;
      final overlap = _jaccard(queryTokens, _tokenize(doc.searchText));
      out.add(
        KnowledgeSimilarityHit(
          document: doc,
          similarity: cosine,
          tokenOverlap: overlap,
          source: entry.value,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = b.similarity.compareTo(a.similarity);
    if (c != 0) return c;
    return b.tokenOverlap.compareTo(a.tokenOverlap);
  });
  return out.take(effectiveTopK).toList(growable: false);
}
