/// `find_similar_knowledge` — KnowledgeOS dedupe / cross-type read tool
/// (`docs/domains/knowledgeos-domain.md` §15.3).
///
/// Given free text, returns the most similar existing KnowledgeOS entries
/// across the requested types. Similarity = EmbeddingGemma cosine
/// (`MemoryHit.semanticSim`) re-ranked by token overlap on the indexed
/// title+summary, so a pure-vector false positive ("两段都谈钱" but unrelated)
/// is demoted. This is the read half of the dedupe loop: the agent calls
/// it after a capture, then proposes `propose_merge` on a high hit.
///
/// **`MemoryRuntime.recall(source:)` is an exact match — there is no
/// `know:*` wildcard.** So we iterate the concrete sources in
/// [kKnowledgeMemorySources] (filtered by the `types` input) and merge.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_object_memory_indexers.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '_tool_support.dart';

class FindSimilarKnowledgeTool implements DeviceTool {
  const FindSimilarKnowledgeTool();

  /// Below this cosine a hit is not considered a near-duplicate.
  static const double kDefaultThreshold = 0.82;

  @override
  String get name => 'find_similar_knowledge';

  @override
  String get description =>
      '在 KnowledgeOS 知识库里查找与给定文本语义相近的已有条目(查重 / 防重复)。'
      '相似度 = EmbeddingGemma 余弦,再用标题+摘要的 token 重叠复核以压低纯向量误判。'
      'types 限定搜索的类型(note/concept/decision/principle/assumption/experiment);默认全部。'
      'exclude_id 用于排除"自己"(对已存在条目查重时传它的 id)。'
      '返回 [{id, kind, title, similarity, token_overlap, source}],按 similarity 降序。'
      '高 similarity(≥ threshold)说明可能重复 —— 通常下一步调用 propose_merge。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': '要查重的文本(标题+正文拼一起即可)。'},
      'types': {
        'type': 'array',
        'items': <String, Object?>{
          'type': 'string',
          'enum': <String>[
            'note',
            'concept',
            'decision',
            'principle',
            'assumption',
            'experiment',
          ],
        },
        'description': '限定搜索类型;省略 = 全部。',
      },
      'exclude_id': {
        'type': 'string',
        'description': '可选,从结果里排除的 sourceId(查重已存在条目时传它自己)。',
      },
      'threshold': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'description': '余弦下限,默认 0.82。低于此不算近重复。',
      },
      'top_k': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 5},
    },
    'required': <String>['text'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final text = ((input['text'] as String?) ?? '').trim();
    if (text.isEmpty) {
      return badRequest('text 必填且非空。');
    }
    final excludeId = (input['exclude_id'] as String?)?.trim();
    final threshold = (input['threshold'] is num)
        ? (input['threshold'] as num).toDouble().clamp(0.0, 1.0).toDouble()
        : kDefaultThreshold;
    final topK = (input['top_k'] is num)
        ? (input['top_k'] as num).toInt().clamp(1, 20).toInt()
        : 5;

    final typesRaw = input['types'];
    final wantTypes = typesRaw is List
        ? typesRaw.whereType<String>().toSet()
        : kKnowledgeDedupeMemorySources.keys.toSet();
    final sources = <String, String>{
      for (final e in kKnowledgeDedupeMemorySources.entries)
        if (wantTypes.contains(e.key)) e.key: e.value,
    };
    if (sources.isEmpty) {
      return <String, Object?>{'candidates': const <Object?>[]};
    }

    final service = await ctx.ref.read(knowledgeSearchServiceProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final candidates = await service.findSimilarKnowledge(
      ownerUserId: ownerUserId,
      text: text,
      types: wantTypes,
      excludeId: excludeId,
      threshold: threshold,
      topK: topK,
    );

    return <String, Object?>{
      'candidates': candidates.map(_hitToWire).toList(growable: false),
    };
  }

  static Map<String, Object?> _hitToWire(KnowledgeSimilarityHit hit) =>
      <String, Object?>{
        'id': hit.id,
        'kind': hit.kind,
        'title': hit.title,
        'similarity': double.parse(hit.similarity.toStringAsFixed(4)),
        'token_overlap': double.parse(hit.tokenOverlap.toStringAsFixed(4)),
        'source': hit.source,
      };
}
