part of 'knowledge_search_service.dart';

Future<List<KnowledgeSearchHit>> _searchNotes(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  Set<String> tags = const <String>{},
  int limit = 20,
}) async {
  final effectiveLimit = limit.clamp(1, 100).toInt();
  final q = query.trim();
  if (q.isNotEmpty) {
    return _searchKnowledge(
      service,
      ownerUserId: ownerUserId,
      query: q,
      types: const <String>{'note'},
      topK: effectiveLimit,
      noteTags: tags,
    );
  }

  final notes = await service._repository.listNotes(
    ownerUserId: ownerUserId,
    limit: effectiveLimit,
    tags: tags,
  );
  final hits = <KnowledgeSearchHit>[];
  for (final note in notes) {
    if (!_matchesNoteFilters(note, tags: tags)) continue;
    final doc = KnowledgeSearchDocument.fromNote(note);
    final lexical = q.isEmpty
        ? const KnowledgeLexicalMatch(score: 1, matchedFields: <String>['list'])
        : KnowledgeLexicalMatch.calculate(q, doc);
    if (q.isNotEmpty && lexical.score <= 0) continue;
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
    if (q.isEmpty && hits.length >= effectiveLimit) break;
  }
  hits.sort(_compareHits);
  return hits.take(effectiveLimit).toList(growable: false);
}

bool _matchesNoteFilters(KnowledgeNote note, {required Set<String> tags}) {
  if (tags.isNotEmpty && !tags.every(note.tags.contains)) return false;
  return true;
}
