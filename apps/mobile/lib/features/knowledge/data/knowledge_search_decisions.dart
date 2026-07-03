part of 'knowledge_search_service.dart';

Future<List<KnowledgeDecisionSearchHit>> _recallDecisions(
  KnowledgeSearchService service, {
  required String ownerUserId,
  required String query,
  String? topic,
  DateTime? from,
  DateTime? to,
  int limit = 10,
}) async {
  final q = query.trim();
  final effectiveLimit = limit.clamp(1, 50).toInt();
  final topicQuery = topic?.trim();

  if (q.isNotEmpty) {
    final semantic = await service.searchKnowledge(
      ownerUserId: ownerUserId,
      query: q,
      types: const <String>{'decision'},
      topK: (effectiveLimit * 4).clamp(effectiveLimit, 50).toInt(),
    );
    final out = <KnowledgeDecisionSearchHit>[];
    for (final hit in semantic) {
      final decision = hit.document.decision;
      if (decision == null) continue;
      if (!_matchesDecisionFilters(
        decision,
        query: null,
        topic: topicQuery,
        from: from,
        to: to,
      )) {
        continue;
      }
      out.add(KnowledgeDecisionSearchHit(decision: decision, hit: hit));
      if (out.length >= effectiveLimit) return out;
    }
    if (out.isNotEmpty) return out;
  }

  final out = <KnowledgeDecisionSearchHit>[];
  var offset = 0;
  while (true) {
    final decisions = await service._repository.listDecisions(
      ownerUserId: ownerUserId,
      limit: _lexicalFallbackPageSize,
      offset: offset,
    );
    if (decisions.isEmpty) break;
    for (final decision in decisions) {
      if (!_matchesDecisionFilters(
        decision,
        query: q,
        topic: topicQuery,
        from: from,
        to: to,
      )) {
        continue;
      }
      final doc = KnowledgeSearchDocument.fromDecision(decision);
      final lexical = q.isEmpty
          ? const KnowledgeLexicalMatch(score: 1, matchedFields: <String>[])
          : KnowledgeLexicalMatch.calculate(q, doc);
      out.add(
        KnowledgeDecisionSearchHit(
          decision: decision,
          hit: KnowledgeSearchHit(
            document: doc,
            score: q.isEmpty ? 1 : lexical.score,
            semanticScore: null,
            semanticSim: null,
            lexicalScore: q.isEmpty ? 1 : lexical.score,
            matchedFields: lexical.matchedFields,
          ),
        ),
      );
    }
    out.sort((a, b) => _compareHits(a.hit, b.hit));
    if (out.length > effectiveLimit) {
      out.removeRange(effectiveLimit, out.length);
    }
    if (q.isEmpty && out.length >= effectiveLimit) break;
    if (decisions.length < _lexicalFallbackPageSize) break;
    offset += decisions.length;
  }
  out.sort((a, b) => _compareHits(a.hit, b.hit));
  return out.take(effectiveLimit).toList(growable: false);
}

bool _matchesDecisionFilters(
  KnowledgeDecision decision, {
  required String? query,
  required String? topic,
  required DateTime? from,
  required DateTime? to,
}) {
  if (from != null && decision.decidedAt.isBefore(from)) return false;
  if (to != null && decision.decidedAt.isAfter(to)) return false;
  final haystack =
      '${decision.question} ${decision.rationaleMd} ${decision.selectedLabel}'
          .toLowerCase();
  final q = query?.trim().toLowerCase();
  if (q != null && q.isNotEmpty && !haystack.contains(q)) return false;
  final t = topic?.trim().toLowerCase();
  if (t != null && t.isNotEmpty && !haystack.contains(t)) return false;
  return true;
}
