/// `query_memory` — flat hybrid-ranked Memory Runtime search
/// (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Kept for back-compat with the descriptor catalog + LLM prompts that
/// already know the name. For richer kind-classified output prefer
/// [BuildContextTool] (`build_context`) — that returns a structured
/// pack instead of flat hits.
///
/// Reads the Memory Runtime via [memoryRuntimeProvider]; no embedding
/// happens for unindexed sources. Population is per-feature extractors
/// (e.g. trade journal in
/// `features/finance/options_income/data/trade_journal_memory_indexer.dart`).
library;

import 'package:naviwealth/core/auth/current_user.dart';
import '../../../contracts/memory_record.dart';
import '../../../local/memory/memory_runtime.dart';
import '../../../local/memory/providers.dart';
import 'device_tool.dart';

class QueryMemoryTool implements DeviceTool {
  const QueryMemoryTool();

  @override
  String get name => 'query_memory';

  @override
  String get description =>
      '在用户的本地"记忆库"里做混合检索(语义相似度 + importance + 实体匹配 + 时近度 + confidence),'
      '返回扁平 hit 列表。**当你需要按用途分槽的结果(偏好 / 规则 / 历史决策 / 最近事件)时,'
      '改用 `build_context`**。'
      '本工具适合"模糊找回一段记忆"。可选 `kind` 限定 event/semantic/episodic/procedural,'
      '`source` 限定来源标签,`top_k` 上限 20。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': <String>['query'],
    'properties': <String, Object?>{
      'query': <String, Object?>{
        'type': 'string',
        'description': '自然语言查询;会被本地 embedder 编码后参与混合打分。',
      },
      'kind': <String, Object?>{
        'type': 'string',
        'enum': ['event', 'semantic', 'episodic', 'procedural'],
        'description': '只检索此 kind 的 memory。不传则跨 kind。',
      },
      'source': <String, Object?>{
        'type': 'string',
        'description': '只检索特定来源标签(例如 `options_trade_journal`)。不传则跨域。',
      },
      'top_k': <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': '返回的最大命中数,默认 5。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final rawQuery = input['query'];
    if (rawQuery is! String || rawQuery.trim().isEmpty) {
      return <String, Object?>{
        'error': 'query must be a non-empty string',
        'code': 'invalid_input',
      };
    }
    final query = rawQuery.trim();
    final source = (input['source'] as String?)?.trim();
    final kindRaw = input['kind'] as String?;
    final kinds = (kindRaw == null || kindRaw.isEmpty)
        ? <MemoryKind>{}
        : <MemoryKind>{MemoryKindWire.parse(kindRaw)};
    final topK = switch (input['top_k']) {
      int v => v.clamp(1, 20),
      num v => v.toInt().clamp(1, 20),
      _ => 5,
    };

    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final hits = await runtime.recall(
      ownerUserId: ownerUserId,
      queryText: query,
      kinds: kinds.isEmpty ? null : kinds,
      source: (source == null || source.isEmpty) ? null : source,
      topK: topK,
    );

    final wire = <Map<String, Object?>>[];
    for (final h in hits) {
      wire.add(_hitToWire(h));
    }

    return <String, Object?>{
      'hits': wire,
      'memory_size': await runtime.memoryCount,
      if (hits.isEmpty)
        'guidance':
            '记忆库里没有匹配条目。可能是该来源还没有索引,或者用户从未录入过相关内容;'
            '请避免基于此结果做出"用户从未做过 X"的强断言。',
    };
  }

  static Map<String, Object?> _hitToWire(MemoryHit h) => <String, Object?>{
    'id': h.record.id,
    'kind': h.record.kind.wire,
    'source': h.record.source ?? '',
    'title': h.record.title,
    'excerpt': _excerpt(h.record.summary),
    'score': h.score,
    if (h.semanticSim != null) 'semantic_sim': h.semanticSim,
    'entity_overlap': h.entityOverlap,
    'recency': h.recency,
    'importance': h.record.importance,
    'confidence': h.record.confidence,
  };

  static String _excerpt(String s) {
    const window = 120;
    if (s.length <= window) return s;
    return '${s.substring(0, window)}…';
  }
}
