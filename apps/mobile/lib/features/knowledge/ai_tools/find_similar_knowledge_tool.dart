/// `find_similar_knowledge` — KnowledgeOS dedupe / cross-type read tool
/// (`docs/knowledgeos-domain.md` §15.3).
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

import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_object_memory_indexers.dart';

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
      'text': {
        'type': 'string',
        'description': '要查重的文本(标题+正文拼一起即可)。',
      },
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
      'top_k': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'default': 5,
      },
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
      return <String, Object?>{
        'error': 'text 必填且非空。',
        'code': 'bad_request',
      };
    }
    final excludeId = (input['exclude_id'] as String?)?.trim();
    final threshold = (input['threshold'] is num)
        ? (input['threshold'] as num).toDouble().clamp(0.0, 1.0)
        : kDefaultThreshold;
    final topK = (input['top_k'] is num)
        ? (input['top_k'] as num).toInt().clamp(1, 20)
        : 5;

    final typesRaw = input['types'];
    final wantTypes = typesRaw is List
        ? typesRaw.whereType<String>().toSet()
        : kKnowledgeMemorySources.keys.toSet();
    final sources = <String, String>{
      for (final e in kKnowledgeMemorySources.entries)
        if (wantTypes.contains(e.key)) e.key: e.value,
    };
    if (sources.isEmpty) {
      return <String, Object?>{'candidates': const <Object?>[]};
    }

    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final queryTokens = _tokenize(text);

    final candidates = <Map<String, Object?>>[];
    for (final entry in sources.entries) {
      final type = entry.key;
      final source = entry.value;
      final hits = await runtime.recall(
        ownerUserId: ownerUserId,
        queryText: text,
        source: source,
        // Pull a cushion above top_k so the threshold + exclude filter
        // still leaves enough per source.
        topK: (topK * 2).clamp(topK, 20),
      );
      for (final h in hits) {
        final sourceId = h.record.sourceId;
        if (sourceId == null) continue;
        if (excludeId != null && sourceId == excludeId) continue;
        final cosine = h.semanticSim ?? 0.0;
        if (cosine < threshold) continue;
        final overlap = _tokenOverlap(
          queryTokens,
          _tokenize('${h.record.title} ${h.record.summary}'),
        );
        candidates.add(<String, Object?>{
          'id': sourceId,
          'kind': type,
          'title': h.record.title,
          'similarity': double.parse(cosine.toStringAsFixed(4)),
          'token_overlap': double.parse(overlap.toStringAsFixed(4)),
          'source': source,
        });
      }
    }

    candidates.sort((a, b) {
      final sa = (a['similarity'] as num).toDouble();
      final sb = (b['similarity'] as num).toDouble();
      final c = sb.compareTo(sa);
      if (c != 0) return c;
      // Tie-break on token overlap so a literal near-match wins.
      return (b['token_overlap'] as num).toDouble().compareTo(
        (a['token_overlap'] as num).toDouble(),
      );
    });

    return <String, Object?>{
      'candidates': candidates.take(topK).toList(growable: false),
    };
  }

  /// Lowercased word/CJK-bigram token set. CJK has no spaces, so we add
  /// character bigrams for those runs; ASCII falls back to word splitting.
  static Set<String> _tokenize(String s) {
    final lower = s.toLowerCase();
    final tokens = <String>{};
    for (final word in lower.split(RegExp(r'[^a-z0-9一-鿿]+'))) {
      if (word.isEmpty) continue;
      if (RegExp(r'[一-鿿]').hasMatch(word)) {
        // CJK run → character bigrams (+ singletons for length-1 words).
        if (word.length == 1) {
          tokens.add(word);
        } else {
          for (var i = 0; i < word.length - 1; i++) {
            tokens.add(word.substring(i, i + 2));
          }
        }
      } else {
        tokens.add(word);
      }
    }
    return tokens;
  }

  /// Jaccard overlap of two token sets, 0 when either is empty.
  static double _tokenOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.where(b.contains).length;
    final union = (<String>{...a, ...b}).length;
    return union == 0 ? 0 : inter / union;
  }
}
