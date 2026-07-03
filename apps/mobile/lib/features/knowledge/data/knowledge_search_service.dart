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

part 'knowledge_search_core.dart';
part 'knowledge_search_decisions.dart';
part 'knowledge_search_models.dart';
part 'knowledge_search_notes.dart';
part 'knowledge_search_similarity.dart';

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
  }) => _searchKnowledge(
    this,
    ownerUserId: ownerUserId,
    query: query,
    types: types,
    topK: topK,
  );

  Future<List<KnowledgeSearchHit>> searchNotes({
    required String ownerUserId,
    required String query,
    Set<String> tags = const <String>{},
    String? project,
    int limit = 20,
  }) => _searchNotes(
    this,
    ownerUserId: ownerUserId,
    query: query,
    tags: tags,
    project: project,
    limit: limit,
  );

  Future<List<KnowledgeDecisionSearchHit>> recallDecisions({
    required String ownerUserId,
    required String query,
    String? topic,
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) => _recallDecisions(
    this,
    ownerUserId: ownerUserId,
    query: query,
    topic: topic,
    from: from,
    to: to,
    limit: limit,
  );

  Future<List<KnowledgeSimilarityHit>> findSimilarKnowledge({
    required String ownerUserId,
    required String text,
    Set<String>? types,
    String? excludeId,
    double threshold = 0.82,
    int topK = 5,
  }) => _findSimilarKnowledge(
    this,
    ownerUserId: ownerUserId,
    text: text,
    types: types,
    excludeId: excludeId,
    threshold: threshold,
    topK: topK,
  );
}
