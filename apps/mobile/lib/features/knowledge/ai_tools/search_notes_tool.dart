/// `search_notes` — KnowledgeOS device tool
/// (`docs/domains/knowledgeos-domain.md` §4).
///
/// Semantic + full-text hybrid via `MemoryRuntime.recall(source='know:notes')`,
/// with the substring scan kept as a fallback for two cases:
///
/// - cold start: indexer hasn't run yet, Memory has zero `know:notes` rows
/// - empty query: hybrid recall needs `queryText`; without it we just list
///   notes that match the tag filter
///
/// Result rows come from `KnowledgeRepository.findNote` — Memory is the
/// index, Drift is source-of-truth (mirrors the trade journal pattern).
library;

import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_text.dart';

class SearchNotesTool implements DeviceTool {
  const SearchNotesTool();

  @override
  String get name => 'search_notes';

  @override
  String get description =>
      '在 KnowledgeOS knowledge_notes 表里做混合检索:'
      'query 非空时走 MemoryRuntime.recall(source="know:notes") 的语义 + entity + recency 加权;'
      'query 为空或 Memory 冷启动无命中时回落到子串扫。'
      '可选 tags 做窄化。返回每条 note 的 id / title / excerpt / score。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
      'tags': {
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
        'description': '全部 tag 都要命中(AND)。',
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100, 'default': 20},
    },
    'required': <String>['query'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final query = ((input['query'] as String?) ?? '').trim();
    final tagsRaw = input['tags'];
    final wantTags = tagsRaw is List
        ? tagsRaw.whereType<String>().toSet()
        : const <String>{};
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 100)
        : 20;

    final service = await ctx.ref.read(knowledgeSearchServiceProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final hits = await service.searchNotes(
      ownerUserId: ownerUserId,
      query: query,
      tags: wantTags,
      limit: limit,
    );
    return withEvidence(
      result: <String, Object?>{
        'notes': hits.map((hit) => _record(hit, query)).toList(growable: false),
      },
      anchors: hits
          .take(8)
          .map(
            (hit) => EvidenceAnchor(
              entityTable: 'knowledge_notes',
              entityId: hit.id,
              label: hit.title,
            ),
          ),
    );
  }

  static Map<String, Object?> _record(KnowledgeSearchHit hit, String query) {
    final body = hit.document.note?.bodyMd ?? hit.excerpt;
    return <String, Object?>{
      'id': hit.id,
      'title': hit.title,
      'excerpt': _excerpt(body, query),
      'score': double.parse(hit.score.toStringAsFixed(4)),
      'semantic_sim': hit.semanticSim == null
          ? null
          : double.parse(hit.semanticSim!.toStringAsFixed(4)),
      'lexical_score': double.parse(hit.lexicalScore.toStringAsFixed(4)),
      'matched_fields': hit.matchedFields,
    };
  }

  static String _excerpt(String body, String query) {
    if (body.isEmpty) return '';
    final q = query.trim().toLowerCase();
    final hitIndex = q.isEmpty ? 0 : body.toLowerCase().indexOf(q);
    if (hitIndex < 0) {
      return knowledgeExcerpt(body, max: kKnowledgeSupportingExcerptMaxChars);
    }
    const contextRadius = kKnowledgeHeadlineExcerptMaxChars;
    final start = (hitIndex - contextRadius).clamp(0, body.length).toInt();
    final end = (hitIndex + contextRadius).clamp(0, body.length).toInt();
    return '${start > 0 ? '…' : ''}${body.substring(start, end)}'
        '${end < body.length ? '…' : ''}';
  }
}
