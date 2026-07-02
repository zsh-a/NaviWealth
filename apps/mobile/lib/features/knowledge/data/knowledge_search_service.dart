/// Unified KnowledgeOS search service.
///
/// Drift tables remain the source of truth; Memory Runtime is the semantic
/// index. This service is the domain seam that hydrates `know:*` memory hits
/// back into real KnowledgeOS objects, adds a lightweight lexical score, and
/// provides deterministic Drift fallbacks for cold-start indexing.
library;

import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';

import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_object_memory_indexers.dart';
import 'knowledge_repository.dart';

part 'knowledge_search_models.dart';

const int _lexicalFallbackPageSize = 100;

class KnowledgeSearchService {
  KnowledgeSearchService({
    required KnowledgeRepository repository,
    required MemoryRuntime memoryRuntime,
    this.displayCopy = const KnowledgeSearchDisplayCopy(),
  }) : _repository = repository,
       _memoryRuntime = memoryRuntime;

  final KnowledgeRepository _repository;
  final MemoryRuntime _memoryRuntime;
  final KnowledgeSearchDisplayCopy displayCopy;

  Future<List<KnowledgeSearchHit>> searchKnowledge({
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
      final hits = await _memoryRuntime.recall(
        ownerUserId: ownerUserId,
        queryText: q,
        source: entry.value,
        topK: (limit * 4).clamp(limit, 80).toInt(),
      );
      for (final hit in hits) {
        final id = hit.record.sourceId;
        if (id == null) continue;
        final doc = await _documentForId(
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
        ownerUserId: ownerUserId,
        query: q,
        types: wantTypes,
        limit: limit,
      );
    }

    final out = byKey.values.toList(growable: false)..sort(_compareHits);
    return out.take(limit).toList(growable: false);
  }

  Future<List<KnowledgeSearchHit>> searchNotes({
    required String ownerUserId,
    required String query,
    Set<String> tags = const <String>{},
    String? project,
    int limit = 20,
  }) async {
    final effectiveLimit = limit.clamp(1, 100).toInt();
    final q = query.trim();
    if (q.isNotEmpty) {
      final semantic = await searchKnowledge(
        ownerUserId: ownerUserId,
        query: q,
        types: const <String>{'note'},
        topK: (effectiveLimit * 4).clamp(effectiveLimit, 100).toInt(),
      );
      final filtered = semantic
          .where((hit) {
            final note = hit.document.note;
            if (note == null) return false;
            if (!_matchesNoteFilters(note, tags: tags, project: project)) {
              return false;
            }
            return true;
          })
          .take(effectiveLimit)
          .toList(growable: false);
      if (filtered.isNotEmpty) return filtered;
    }

    final notes = await _repository.listNotes(
      ownerUserId: ownerUserId,
      limit: 500,
    );
    final hits = <KnowledgeSearchHit>[];
    for (final note in notes) {
      if (!_matchesNoteFilters(note, tags: tags, project: project)) continue;
      final doc = KnowledgeSearchDocument.fromNote(
        note,
        untitled: displayCopy.untitled,
      );
      final lexical = q.isEmpty
          ? const KnowledgeLexicalMatch(
              score: 1,
              matchedFields: <String>['list'],
            )
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

  Future<List<KnowledgeDecisionSearchHit>> recallDecisions({
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
      final semantic = await searchKnowledge(
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
      final decisions = await _repository.listDecisions(
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

  Future<List<KnowledgeSimilarityHit>> findSimilarKnowledge({
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
      final hits = await _memoryRuntime.recall(
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

  Future<KnowledgeSearchDocument?> _documentForId({
    required String ownerUserId,
    required String kind,
    required String id,
  }) async {
    return switch (kind) {
      'note' =>
        _repository
            .findNote(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromNote(
                      v,
                      untitled: displayCopy.untitled,
                    ),
            ),
      'principle' =>
        _repository
            .findPrinciple(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromPrinciple(v),
            ),
      'assumption' =>
        _repository
            .findAssumption(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromAssumption(v),
            ),
      'concept' =>
        _repository
            .findConcept(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromConcept(v),
            ),
      'experiment' =>
        _repository
            .findExperiment(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromExperiment(v),
            ),
      'decision' =>
        _repository
            .findDecision(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromDecision(v),
            ),
      'routine' =>
        _repository
            .findRoutine(ownerUserId: ownerUserId, id: id)
            .then(
              (v) => v == null || v.sync.deletedAt != null
                  ? null
                  : KnowledgeSearchDocument.fromRoutine(
                      v,
                      routineInterval: displayCopy.routineInterval,
                    ),
            ),
      _ => Future<KnowledgeSearchDocument?>.value(),
    };
  }

  Future<List<KnowledgeSearchHit>> _lexicalFallback({
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
    String ownerUserId,
    String kind, {
    required int limit,
    required int offset,
  }) async {
    return switch (kind) {
      'note' => (await _repository.listNotes(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromNote).toList(growable: false),
      'principle' => (await _repository.listPrinciples(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromPrinciple).toList(growable: false),
      'assumption' => (await _repository.listAssumptions(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromAssumption).toList(growable: false),
      'concept' => (await _repository.listConcepts(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromConcept).toList(growable: false),
      'experiment' => (await _repository.listExperiments(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromExperiment).toList(growable: false),
      'decision' => (await _repository.listDecisions(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromDecision).toList(growable: false),
      'routine' => (await _repository.listRoutines(
        ownerUserId: ownerUserId,
        limit: limit,
        offset: offset,
      )).map(KnowledgeSearchDocument.fromRoutine).toList(growable: false),
      _ => const <KnowledgeSearchDocument>[],
    };
  }

  static bool _matchesNoteFilters(
    KnowledgeNote note, {
    required Set<String> tags,
    required String? project,
  }) {
    if (tags.isNotEmpty && !tags.every(note.tags.contains)) return false;
    if (project != null && project.isNotEmpty && note.projectTag != project) {
      return false;
    }
    return true;
  }

  static bool _matchesDecisionFilters(
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

  static double _combinedSearchScore({
    required double semanticScore,
    required double lexicalScore,
  }) {
    return (semanticScore.clamp(0.0, 1.0).toDouble() * 0.75 +
            lexicalScore.clamp(0.0, 1.0).toDouble() * 0.25)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static void _keepBest(
    Map<String, KnowledgeSearchHit> byKey,
    KnowledgeSearchHit hit,
  ) {
    final key = '${hit.kind}:${hit.id}';
    final prior = byKey[key];
    if (prior == null || hit.score > prior.score) {
      byKey[key] = hit;
    }
  }

  static int _compareHits(KnowledgeSearchHit a, KnowledgeSearchHit b) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    return b.document.updatedAt.compareTo(a.document.updatedAt);
  }
}
