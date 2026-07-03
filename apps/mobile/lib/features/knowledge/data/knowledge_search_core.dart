part of 'knowledge_search_service.dart';

Future<List<KnowledgeSearchHit>> _searchKnowledge(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  Set<String>? types,
  int topK = 8,
}) async {
  final q = query.trim();
  if (q.isEmpty || topK <= 0) return const <KnowledgeSearchHit>[];
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
    final hits = await service._memoryRuntime.recall(
      ownerUserId: ownerUserId,
      queryText: q,
      source: entry.value,
      topK: (limit * 4).clamp(limit, 80).toInt(),
    );
    for (final hit in hits) {
      final id = hit.record.sourceId;
      if (id == null) continue;
      final doc = await _documentForId(
        service,
        ownerUserId: ownerUserId,
        kind: entry.key,
        id: id,
      );
      if (doc == null) continue;
      final lexical = KnowledgeLexicalMatch.calculate(q, doc);
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

  if (byKey.isEmpty) {
    return _lexicalFallback(
      service,
      ownerUserId: ownerUserId,
      query: q,
      types: wantTypes,
      limit: limit,
    );
  }

  final out = byKey.values.toList(growable: false)..sort(_compareHits);
  return out.take(limit).toList(growable: false);
}

Future<KnowledgeSearchDocument?> _documentForId(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String kind,
  required String id,
}) async {
  return switch (kind) {
    'note' =>
      service._repository
          .findNote(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromNote(
                    v,
                    untitled: service.displayCopy.untitled,
                  ),
          ),
    'principle' =>
      service._repository
          .findPrinciple(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromPrinciple(v),
          ),
    'assumption' =>
      service._repository
          .findAssumption(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromAssumption(v),
          ),
    'concept' =>
      service._repository
          .findConcept(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromConcept(v),
          ),
    'experiment' =>
      service._repository
          .findExperiment(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromExperiment(v),
          ),
    'decision' =>
      service._repository
          .findDecision(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromDecision(v),
          ),
    'routine' =>
      service._repository
          .findRoutine(ownerUserId: ownerUserId, id: id)
          .then(
            (v) => v == null || v.sync.deletedAt != null
                ? null
                : KnowledgeSearchDocument.fromRoutine(
                    v,
                    routineInterval: service.displayCopy.routineInterval,
                  ),
          ),
    _ => Future<KnowledgeSearchDocument?>.value(),
  };
}

Future<List<KnowledgeSearchHit>> _lexicalFallback(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  required Set<String> types,
  required int limit,
}) async {
  final hits = <KnowledgeSearchHit>[];
  for (final type in types) {
    var offset = 0;
    while (true) {
      final docs = await _documentsForKind(
        service,
        ownerUserId,
        type,
        limit: _lexicalFallbackPageSize,
        offset: offset,
      );
      if (docs.isEmpty) break;
      for (final doc in docs) {
        final lexical = KnowledgeLexicalMatch.calculate(query, doc);
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
}) async {
  return switch (kind) {
    'note' => (await service._repository.listNotes(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromNote).toList(growable: false),
    'principle' => (await service._repository.listPrinciples(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromPrinciple).toList(growable: false),
    'assumption' => (await service._repository.listAssumptions(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromAssumption).toList(growable: false),
    'concept' => (await service._repository.listConcepts(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromConcept).toList(growable: false),
    'experiment' => (await service._repository.listExperiments(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromExperiment).toList(growable: false),
    'decision' => (await service._repository.listDecisions(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromDecision).toList(growable: false),
    'routine' => (await service._repository.listRoutines(
      ownerUserId: ownerUserId,
      limit: limit,
      offset: offset,
    )).map(KnowledgeSearchDocument.fromRoutine).toList(growable: false),
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
