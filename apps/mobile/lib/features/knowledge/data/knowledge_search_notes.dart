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
    final semantic = await service.searchKnowledge(
      ownerUserId: ownerUserId,
      query: q,
      types: const <String>{'note'},
      topK: (effectiveLimit * 4).clamp(effectiveLimit, 100).toInt(),
    );
    final filtered = semantic
        .where((hit) {
          final note = hit.document.note;
          if (note == null) return false;
          if (!_matchesNoteFilters(note, tags: tags)) {
            return false;
          }
          return true;
        })
        .take(effectiveLimit)
        .toList(growable: false);
    if (filtered.isNotEmpty) return filtered;
  }

  final notes = await service._repository.listNotes(
    ownerUserId: ownerUserId,
    limit: 500,
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
