/// `search_knowledge` — KnowledgeOS cross-type semantic search
/// (`docs/knowledgeos-domain.md` §15.3).
///
/// Where `search_notes` only sees notes and `recall_decision` only sees
/// decisions, this searches **every** KnowledgeOS type at once — the
/// "查我的知识库" surface. Hybrid-scored via `MemoryRuntime.recall` over each
/// concrete `know:*` source (recall's `source` filter is exact-match, no
/// `know:*` wildcard), merged and ranked by hybrid score. Returns id / kind
/// / title / excerpt / score per hit for browsing (not deduping — use
/// `find_similar_knowledge` for that).
library;

import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_object_memory_indexers.dart';

class SearchKnowledgeTool implements DeviceTool {
  const SearchKnowledgeTool();

  @override
  String get name => 'search_knowledge';

  @override
  String get description =>
      '在整个 KnowledgeOS 知识库里跨类型语义检索（笔记 / 概念 / 决策 / 原则 / 假设 / 实验）。'
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
          'enum': <String>[
            'note',
            'concept',
            'decision',
            'principle',
            'assumption',
            'experiment',
            'routine',
          ],
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
      return <String, Object?>{'error': 'query 必填且非空。', 'code': 'bad_request'};
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

    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final results = <Map<String, Object?>>[];
    for (final entry in sources.entries) {
      final hits = await runtime.recall(
        ownerUserId: ownerUserId,
        queryText: query,
        source: entry.value,
        topK: topK,
      );
      for (final h in hits) {
        final sourceId = h.record.sourceId;
        if (sourceId == null) continue;
        results.add(<String, Object?>{
          'id': sourceId,
          'kind': entry.key,
          'title': h.record.title,
          'excerpt': _excerpt(h.record.summary),
          'score': double.parse(h.score.toStringAsFixed(4)),
        });
      }
    }

    results.sort(
      (a, b) => (b['score'] as num).toDouble().compareTo(
        (a['score'] as num).toDouble(),
      ),
    );

    return <String, Object?>{
      'results': results.take(topK).toList(growable: false),
    };
  }

  static String _excerpt(String s, [int n = 160]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
