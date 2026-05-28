/// `recall_decision` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// "我之前为什么决定 X" 主路径。Returns decisions matching a free-form
/// query, optionally narrowed by topic/time. Pure read — Drift only.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class RecallDecisionTool implements DeviceTool {
  const RecallDecisionTool();

  @override
  String get name => 'recall_decision';

  @override
  String get description =>
      '从 KnowledgeOS Decision Log 中检索历史决策。返回决策的 question / selected / rationale / '
      'assumptions / outcome / age_days,用于回答"我之前为什么决定 X"。'
      'query 是自然语言短语,会对 question + rationale 做不区分大小写的子串匹配。'
      'topic 是可选过滤(如 "fire" / "options"),会匹配 question / rationale / selected。'
      'time_range 是 ISO8601 日期窗口 `{from?, to?}`,按 decided_at 过滤。'
      'KnowledgeOS 未启用或没有匹配时返回 `decisions: []`。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': '自然语言关键词或短语。',
      },
      'topic': {
        'type': 'string',
        'description': '可选窄化关键词。',
      },
      'time_range': {
        'type': 'object',
        'properties': {
          'from': {'type': 'string', 'description': 'ISO8601 起点。'},
          'to': {'type': 'string', 'description': 'ISO8601 终点。'},
        },
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 50,
        'default': 10,
      },
    },
    'required': <String>['query'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final query = ((input['query'] as String?) ?? '').trim().toLowerCase();
    final topic = (input['topic'] as String?)?.trim().toLowerCase();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 50)
        : 10;
    DateTime? from;
    DateTime? to;
    final range = input['time_range'];
    if (range is Map) {
      from = DateTime.tryParse((range['from'] as String?) ?? '');
      to = DateTime.tryParse((range['to'] as String?) ?? '');
    }

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 500,
    );

    bool matches(KnowledgeDecision d) {
      if (from != null && d.decidedAt.isBefore(from)) return false;
      if (to != null && d.decidedAt.isAfter(to)) return false;
      bool textMatch(String s) {
        final lower = s.toLowerCase();
        if (!lower.contains(query)) return false;
        if (topic != null && topic.isNotEmpty && !lower.contains(topic)) {
          return false;
        }
        return true;
      }
      // Search in question, rationale, selected. OR'd within fields,
      // AND'd against `topic` (when set).
      if (query.isEmpty) return topic == null || topic.isEmpty;
      return textMatch(d.question) ||
          textMatch(d.rationaleMd) ||
          textMatch(d.selectedLabel);
    }

    final now = DateTime.now().toUtc();
    final hits = decisions.where(matches).take(limit).toList(growable: false);
    return <String, Object?>{
      'decisions': hits
          .map(
            (d) => <String, Object?>{
              'id': d.id,
              'question': d.question,
              'selected': d.selectedLabel,
              'rationale': d.rationaleMd,
              'principle_ids': d.principleIds,
              'assumption_ids': d.assumptionIds,
              'expected_outcome': d.expectedOutcome,
              'actual_outcome': d.actualOutcomeMd,
              'status': d.status.wire,
              'decided_at': d.decidedAt.toUtc().toIso8601String(),
              'review_date': d.reviewDate?.toUtc().toIso8601String(),
              'age_days':
                  now.difference(d.decidedAt.toUtc()).inDays.clamp(0, 100000),
            },
          )
          .toList(growable: false),
    };
  }
}
