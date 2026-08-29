/// `search_knowledge` — KnowledgeOS cross-type semantic search
/// (`docs/domains/knowledgeos-domain.md` §15.3).
///
/// Where `search_notes` only sees notes and `recall_decision` only sees
/// decisions, this searches **every** KnowledgeOS type at once — the
/// "查我的知识库" surface. Hybrid-scored via `MemoryRuntime.recall` over each
/// concrete `know:*` source (recall's `source` filter is exact-match, no
/// `know:*` wildcard), merged and ranked by hybrid score. Returns id / kind
/// / title / excerpt / score per hit for browsing (not deduping — use
/// `find_similar_knowledge` for that).
library;

import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_memory_indexer_support.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '_tool_support.dart';

class SearchKnowledgeTool implements DeviceTool {
  const SearchKnowledgeTool();

  @override
  String get name => 'search_knowledge';

  @override
  String get description =>
      '在 KnowledgeOS 的笔记与决策中进行语义检索。'
      'query 必填。types 限定类型，省略 = 全部。'
      '返回 [{id, kind, title, excerpt, score}]，按混合分降序。'
      '用于「我之前在哪写过 X / 关于 Y 我都记了什么」这类浏览式检索；'
      '查重复请用 find_similar_knowledge，专查决策用 recall_decision。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
      'types': {
        'type': 'array',
        'items': <String, Object?>{
          'type': 'string',
          'enum': <String>['note', 'decision'],
        },
      },
      'top_k': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 8},
    },
    'required': <String>['query'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final query = ((input['query'] as String?) ?? '').trim();
    if (query.isEmpty) {
      return badRequest('query 必填且非空。');
    }
    final topK = (input['top_k'] is num)
        ? (input['top_k'] as num).toInt().clamp(1, 20)
        : 8;

    final typesRaw = input['types'];
    final wantTypes = typesRaw is List
        ? typesRaw.whereType<String>().toSet()
        : kKnowledgeMemorySources.keys.toSet();
    final sources = <String, String>{
      for (final e in kKnowledgeMemorySources.entries)
        if (wantTypes.contains(e.key)) e.key: e.value,
    };
    if (sources.isEmpty) {
      return <String, Object?>{'results': const <Object?>[]};
    }

    final service = await ctx.ref.read(knowledgeSearchServiceProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final results = await service.searchKnowledge(
      ownerUserId: ownerUserId,
      query: query,
      types: wantTypes,
      topK: topK,
    );

    return withEvidence(
      result: <String, Object?>{
        'results': results.map(_hitToWire).toList(growable: false),
      },
      anchors: results
          .take(8)
          .map(
            (hit) => EvidenceAnchor(
              entityTable: _tableForKind(hit.kind),
              entityId: hit.id,
              label: hit.title,
            ),
          ),
    );
  }

  static String _tableForKind(String kind) => switch (kind) {
    'note' => 'knowledge_notes',
    'decision' => 'knowledge_decisions',
    _ => 'knowledge_notes',
  };

  static Map<String, Object?> _hitToWire(KnowledgeSearchHit hit) =>
      <String, Object?>{
        'id': hit.id,
        'kind': hit.kind,
        'title': hit.title,
        'excerpt': hit.excerpt,
        'score': double.parse(hit.score.toStringAsFixed(4)),
        'semantic_score': hit.semanticScore == null
            ? null
            : double.parse(hit.semanticScore!.toStringAsFixed(4)),
        'semantic_sim': hit.semanticSim == null
            ? null
            : double.parse(hit.semanticSim!.toStringAsFixed(4)),
        'lexical_score': double.parse(hit.lexicalScore.toStringAsFixed(4)),
        'matched_fields': hit.matchedFields,
      };
}
