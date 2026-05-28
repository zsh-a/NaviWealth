/// `search_notes` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// Semantic + full-text hybrid via `MemoryRuntime.recall(source='know:notes')`,
/// with the substring scan kept as a fallback for two cases:
///
/// - cold start: indexer hasn't run yet, Memory has zero `know:notes` rows
/// - empty query: hybrid recall needs `queryText`; without it we just list
///   notes that match the tag / project filter
///
/// Result rows come from `KnowledgeRepository.findNote` — Memory is the
/// index, Drift is source-of-truth (mirrors the trade journal pattern).
library;

import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/knowledge_object_memory_indexers.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';

class SearchNotesTool implements DeviceTool {
  const SearchNotesTool();

  @override
  String get name => 'search_notes';

  @override
  String get description =>
      '在 KnowledgeOS knowledge_notes 表里做混合检索:'
      'query 非空时走 MemoryRuntime.recall(source="know:notes") 的语义 + entity + recency 加权;'
      'query 为空或 Memory 冷启动无命中时回落到子串扫。'
      '可选 tags/project 做窄化。返回每条 note 的 id / title / excerpt / score。';

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
      'project': {'type': 'string'},
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 100,
        'default': 20,
      },
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
    final project = (input['project'] as String?)?.trim();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 100)
        : 20;

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    // Hybrid path — only viable when there's a query and we'll get
    // ranked semantic candidates from Memory.
    if (query.isNotEmpty) {
      final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
      // Pull more than `limit` so post-filtering by tag/project still
      // leaves enough rows. 4× cushion is what HealthOS settled on.
      final hits = await runtime.recall(
        ownerUserId: ownerUserId,
        queryText: query,
        source: kKnowledgeNoteMemorySource,
        topK: (limit * 4).clamp(limit, 100),
      );
      if (hits.isNotEmpty) {
        final results = <Map<String, Object?>>[];
        for (final h in hits) {
          final noteId = h.record.sourceId;
          if (noteId == null) continue;
          final note = await repo.findNote(noteId);
          if (note == null) continue;
          if (wantTags.isNotEmpty &&
              !wantTags.every((t) => note.tags.contains(t))) {
            continue;
          }
          if (project != null &&
              project.isNotEmpty &&
              note.projectTag != project) {
            continue;
          }
          results.add(
            _record(
              note.id,
              note.title,
              note.bodyMd,
              score: h.score,
              hitIndex: _firstHit(note.bodyMd, query),
              semantic: h.semanticSim,
            ),
          );
          if (results.length >= limit) break;
        }
        if (results.isNotEmpty) {
          return <String, Object?>{'notes': results};
        }
        // hybrid recalled but post-filter killed everything — fall through.
      }
      // hits empty → cold-start fallback.
    }

    // Fallback: substring scan (also the empty-query path).
    return _substringScan(
      repo: repo,
      ownerUserId: ownerUserId,
      query: query,
      wantTags: wantTags,
      project: project,
      limit: limit,
    );
  }

  Future<Map<String, Object?>> _substringScan({
    required KnowledgeRepository repo,
    required String ownerUserId,
    required String query,
    required Set<String> wantTags,
    required String? project,
    required int limit,
  }) async {
    final qLower = query.toLowerCase();
    final notes = await repo.listNotes(ownerUserId: ownerUserId, limit: 500);
    final hits = <Map<String, Object?>>[];
    for (final n in notes) {
      if (wantTags.isNotEmpty &&
          !wantTags.every((t) => n.tags.contains(t))) {
        continue;
      }
      if (project != null && project.isNotEmpty && n.projectTag != project) {
        continue;
      }
      if (qLower.isEmpty) {
        hits.add(
          _record(n.id, n.title, n.bodyMd, score: 1.0, hitIndex: 0),
        );
        if (hits.length >= limit) break;
        continue;
      }
      double score = 0;
      final titleLower = n.title.toLowerCase();
      final bodyLower = n.bodyMd.toLowerCase();
      var start = 0;
      while (true) {
        final i = titleLower.indexOf(qLower, start);
        if (i < 0) break;
        score += 2; // title hits weigh double
        start = i + qLower.length;
      }
      var bodyHit = -1;
      start = 0;
      while (true) {
        final i = bodyLower.indexOf(qLower, start);
        if (i < 0) break;
        if (bodyHit < 0) bodyHit = i;
        score += 1;
        start = i + qLower.length;
      }
      if (score > 0) {
        hits.add(
          _record(n.id, n.title, n.bodyMd, score: score, hitIndex: bodyHit),
        );
      }
    }
    hits.sort((a, b) {
      final sa = (a['score'] as num).toDouble();
      final sb = (b['score'] as num).toDouble();
      return sb.compareTo(sa);
    });
    return <String, Object?>{'notes': hits.take(limit).toList(growable: false)};
  }

  /// Locate the first substring occurrence of [query] in [body], -1 if
  /// none. Used to anchor excerpts in the hybrid path so the model
  /// sees a snippet around the actual literal match where possible.
  static int _firstHit(String body, String query) {
    if (query.isEmpty) return -1;
    return body.toLowerCase().indexOf(query.toLowerCase());
  }

  static Map<String, Object?> _record(
    String id,
    String title,
    String body, {
    required double score,
    required int hitIndex,
    double? semantic,
  }) {
    String excerpt;
    if (body.isEmpty) {
      excerpt = '';
    } else if (hitIndex < 0) {
      excerpt = body.length <= 120 ? body : '${body.substring(0, 120)}…';
    } else {
      final start = (hitIndex - 60).clamp(0, body.length);
      final end = (hitIndex + 60).clamp(0, body.length);
      excerpt = '${start > 0 ? '…' : ''}${body.substring(start, end)}'
          '${end < body.length ? '…' : ''}';
    }
    return <String, Object?>{
      'id': id,
      'title': title,
      'excerpt': excerpt,
      'score': score,
      'semantic_sim': ?semantic,
    };
  }
}
