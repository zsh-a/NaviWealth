/// `search_notes` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// MVP: substring scan over title + body, optionally narrowed by
/// tag / project. The §4 spec calls for "全文 + 语义混合(复用
/// hybridScore)" — that arrives when the Memory indexer for knowledge
/// notes is wired (mirror of trade journal indexer). Until then this is
/// a deterministic local search that covers the dogfood use cases.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class SearchNotesTool implements DeviceTool {
  const SearchNotesTool();

  @override
  String get name => 'search_notes';

  @override
  String get description =>
      '在 KnowledgeOS knowledge_notes 表里按 query 做不区分大小写的子串匹配,'
      '可选 tags/project 做窄化。返回每条 note 的 id / title / excerpt (匹配处 ±60 字符) / '
      'score (匹配次数)。MVP 子串 + tag 过滤;后续会接入 Memory hybridScore。';

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
    final qLower = query.toLowerCase();
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
        hits.add(_record(n.id, n.title, n.bodyMd, score: 1, hitIndex: 0));
        if (hits.length >= limit) break;
        continue;
      }
      var score = 0;
      final titleLower = n.title.toLowerCase();
      final bodyLower = n.bodyMd.toLowerCase();
      // Cheap occurrence count.
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
    final out = hits.take(limit).toList(growable: false);
    return <String, Object?>{'notes': out};
  }

  Map<String, Object?> _record(
    String id,
    String title,
    String body, {
    required int score,
    required int hitIndex,
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
    };
  }
}
