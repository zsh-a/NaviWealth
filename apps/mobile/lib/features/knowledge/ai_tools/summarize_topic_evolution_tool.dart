/// `summarize_topic_evolution` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// 回答 "我对 X 的看法这半年怎么变了"。Walks notes + decisions matching
/// `concept_or_topic` and returns a chronologically-ordered timeline of
/// change events with source labels.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class SummarizeTopicEvolutionTool implements DeviceTool {
  const SummarizeTopicEvolutionTool();

  @override
  String get name => 'summarize_topic_evolution';

  @override
  String get description =>
      '按时间序列出某个 concept 或自由词在 KnowledgeOS 里的演化:何时写过 note / 立过 decision / '
      '决策被 supersede。返回 timeline 数组,每条 {ts, source (note/decision/decision_superseded), '
      'id, title_or_question, change_summary}。time_range 可选。'
      '用途:复盘"我对 FIRE 的看法 12 个月怎么变",或 supersede 链回溯。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'concept_or_topic': {
        'type': 'string',
        'description': '主题词或 concept 名,不区分大小写子串匹配。',
      },
      'time_range': {
        'type': 'object',
        'properties': {
          'from': {'type': 'string'},
          'to': {'type': 'string'},
        },
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 100,
        'default': 30,
      },
    },
    'required': <String>['concept_or_topic'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final topic =
        ((input['concept_or_topic'] as String?) ?? '').trim().toLowerCase();
    if (topic.isEmpty) {
      return <String, Object?>{
        'error': 'concept_or_topic 必填',
        'code': 'bad_request',
      };
    }
    DateTime? from;
    DateTime? to;
    final range = input['time_range'];
    if (range is Map) {
      from = DateTime.tryParse((range['from'] as String?) ?? '');
      to = DateTime.tryParse((range['to'] as String?) ?? '');
    }
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 100)
        : 30;

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final notes = await repo.listNotes(ownerUserId: ownerUserId, limit: 1000);
    final decisions =
        await repo.listDecisions(ownerUserId: ownerUserId, limit: 1000);

    bool inWindow(DateTime ts) {
      if (from != null && ts.isBefore(from)) return false;
      if (to != null && ts.isAfter(to)) return false;
      return true;
    }

    final events = <Map<String, Object?>>[];

    for (final n in notes) {
      if (!inWindow(n.createdAt)) continue;
      final hay = '${n.title} ${n.bodyMd} ${n.tags.join(' ')} '
              '${n.projectTag ?? ''}'
          .toLowerCase();
      if (!hay.contains(topic)) continue;
      events.add(<String, Object?>{
        'ts': n.createdAt.toUtc().toIso8601String(),
        'source': 'note',
        'id': n.id,
        'title': n.title,
        'change_summary':
            n.bodyMd.length <= 200 ? n.bodyMd : '${n.bodyMd.substring(0, 200)}…',
      });
    }

    for (final d in decisions) {
      if (!inWindow(d.decidedAt)) continue;
      final hay = '${d.question} ${d.rationaleMd} ${d.selectedLabel}'
          .toLowerCase();
      if (!hay.contains(topic)) continue;
      final isSuperseded = d.supersededByDecisionId != null;
      events.add(<String, Object?>{
        'ts': d.decidedAt.toUtc().toIso8601String(),
        'source': isSuperseded ? 'decision_superseded' : 'decision',
        'id': d.id,
        'title': d.question,
        'status': d.status.wire,
        'superseded_by': d.supersededByDecisionId,
        'change_summary': d.rationaleMd.length <= 200
            ? d.rationaleMd
            : '${d.rationaleMd.substring(0, 200)}…',
      });
    }

    events.sort(
      (a, b) => (a['ts'] as String).compareTo(b['ts'] as String),
    );
    final out = events.take(limit).toList(growable: false);
    return <String, Object?>{'timeline': out};
  }
}
