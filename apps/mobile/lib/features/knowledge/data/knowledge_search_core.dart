part of 'knowledge_search_service.dart';

Future<List<KnowledgeSearchHit>> _searchKnowledge(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  Set<String>? types,
  int topK = 8,
  Set<String> noteTags = const <String>{},
}) async {
  final q = query.trim();
  if (q.isEmpty || topK <= 0) return const <KnowledgeSearchHit>[];
  final queryTokens = _tokenize(q);
  final limit = topK.clamp(1, 100).toInt();
  final wantTypes = (types == null || types.isEmpty)
      ? kKnowledgeMemorySources.keys.toSet()
      : types;
  final sources = <String, String>{
    for (final entry in kKnowledgeMemorySources.entries)
      if (wantTypes.contains(entry.key)) entry.key: entry.value,
  };
  if (sources.isEmpty) return const <KnowledgeSearchHit>[];

  final byKey = <String, KnowledgeSearchHit>{};
  for (final entry in sources.entries) {
    final List<MemoryHit> hits;
    try {
      hits = await service._memoryRuntime.recall(
        ownerUserId: ownerUserId,
        queryText: q,
        source: entry.value,
        topK: (limit * 4).clamp(1, 80).toInt(),
      );
    } on Object {
      // The semantic index is derived and optional. A missing native embedder,
      // cold index, or unavailable Web runtime must not make canonical
      // KnowledgeOS data unsearchable.
      continue;
    }
    final documents = await _documentsForIds(
      service,
      ownerUserId: ownerUserId,
      kind: entry.key,
      ids: hits.map((hit) => hit.record.sourceId).whereType<String>().toSet(),
    );
    for (final hit in hits) {
      final id = hit.record.sourceId;
      if (id == null) continue;
      final doc = documents[id];
      if (doc == null) continue;
      if (doc.note case final note?) {
        if (!_matchesNoteFilters(note, tags: noteTags)) continue;
      }
      final lexical = KnowledgeLexicalMatch.calculate(
        q,
        doc,
        queryTokens: queryTokens,
      );
      final score = _combinedSearchScore(
        semanticScore: hit.score,
        lexicalScore: lexical.score,
      );
      _keepBest(
        byKey,
        KnowledgeSearchHit(
          document: doc,
          score: score,
          semanticScore: hit.score,
          semanticSim: hit.semanticSim,
          lexicalScore: lexical.score,
          matchedFields: lexical.matchedFields,
        ),
      );
    }
  }

  // Always merge lexical matches. A partially populated semantic index can
  // otherwise return an unrelated indexed row and hide an exact canonical
  // match that has not been indexed yet.
  final lexicalHits = await _lexicalFallback(
    service,
    ownerUserId: ownerUserId,
    query: q,
    types: wantTypes,
    limit: limit,
    noteTags: noteTags,
  );
  for (final hit in lexicalHits) {
    byKey.putIfAbsent('${hit.kind}:${hit.id}', () => hit);
  }

  final out = byKey.values.toList(growable: false)..sort(_compareHits);
  return out.take(limit).toList(growable: false);
}

Future<Map<String, KnowledgeSearchDocument>> _documentsForIds(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String kind,
  required Set<String> ids,
}) async {
  final docs = switch (kind) {
    'note' => (await service._repository.listNotesByIds(
      ownerUserId: ownerUserId,
      ids: ids,
    )).map(KnowledgeSearchDocument.fromNote),
    'decision' => (await service._repository.listDecisionsByIds(
      ownerUserId: ownerUserId,
      ids: ids,
    )).map(KnowledgeSearchDocument.fromDecision),
    _ => const <KnowledgeSearchDocument>[],
  };
  return {for (final doc in docs) doc.id: doc};
}

Future<List<KnowledgeSearchHit>> _lexicalFallback(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  required Set<String> types,
  required int limit,
  Set<String> noteTags = const <String>{},
}) async {
  final hits = <KnowledgeSearchHit>[];
  final queryTokens = _tokenize(query);
  for (final type in types) {
    var offset = 0;
    while (true) {
      final docs = await _documentsForKind(
        service,
        ownerUserId,
        type,
        limit: _lexicalFallbackPageSize,
        offset: offset,
        noteTags: noteTags,
      );
      if (docs.isEmpty) break;
      for (final doc in docs) {
        final lexical = KnowledgeLexicalMatch.calculate(
          query,
          doc,
          queryTokens: queryTokens,
        );
        if (lexical.score <= 0) continue;
        hits.add(
          KnowledgeSearchHit(
            document: doc,
            score: lexical.score,
            semanticScore: null,
            semanticSim: null,
            lexicalScore: lexical.score,
            matchedFields: lexical.matchedFields,
          ),
        );
      }
      hits.sort(_compareHits);
      if (hits.length > limit) {
        hits.removeRange(limit, hits.length);
      }
      if (docs.length < _lexicalFallbackPageSize) break;
      offset += docs.length;
    }
  }
  hits.sort(_compareHits);
  return hits.take(limit).toList(growable: false);
}

Future<List<KnowledgeSearchDocument>> _documentsForKind(
  KnowledgeSearchService service,
  String ownerUserId,
  String kind, {
  required int limit,
  required int offset,
  Set<String> noteTags = const <String>{},
}) async {
  return switch (kind) {
    'note' => (await service._repository.listNotes(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
      tags: noteTags,
    )).map(KnowledgeSearchDocument.fromNote).toList(growable: false),
    'decision' => (await service._repository.listDecisions(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromDecision).toList(growable: false),
    _ => const <KnowledgeSearchDocument>[],
  };
}

double _combinedSearchScore({
  required double semanticScore,
  required double lexicalScore,
}) {
  return (semanticScore.clamp(0.0, 1.0).toDouble() * 0.75 +
          lexicalScore.clamp(0.0, 1.0).toDouble() * 0.25)
      .clamp(0.0, 1.0)
      .toDouble();
}

void _keepBest(Map<String, KnowledgeSearchHit> byKey, KnowledgeSearchHit hit) {
  final key = '${hit.kind}:${hit.id}';
  final prior = byKey[key];
  if (prior == null || hit.score > prior.score) {
    byKey[key] = hit;
  }
}

int _compareHits(KnowledgeSearchHit a, KnowledgeSearchHit b) {
  final c = b.score.compareTo(a.score);
  if (c != 0) return c;
  return b.document.updatedAt.compareTo(a.document.updatedAt);
}
