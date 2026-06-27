/// `review_knowledge_health` — KnowledgeOS "give me suggestions" read tool
/// (`docs/domains/knowledgeos-domain.md` §15.3).
///
/// The pull counterpart to the five background agents: one call aggregates
/// everything the user should act on right now —
///   - decisions due for review (`review_date <= now`)
///   - routines due this week (`next_due_at <= now + 7d`)
///   - stale assumptions (never verified, or not in > 90d)
///   - orphan notes (no tags, no project — never triaged / linked)
/// Read-only: it returns a prioritised digest; the agent turns individual
/// items into `propose_*` actions. Backs the Inbox「本周建议」chip.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class ReviewKnowledgeHealthTool implements DeviceTool {
  const ReviewKnowledgeHealthTool();

  /// Assumptions unverified for longer than this count as stale.
  static const int kStaleAssumptionDays = 90;

  @override
  String get name => 'review_knowledge_health';

  @override
  String get description =>
      '汇总当前知识库里需要用户关注的事项,返回一个按优先级排序的摘要:'
      '到期复盘的决策 / 本周到期的定期事项 / 长期未校验的假设 / 没有标签也没有链接的孤儿笔记。'
      '只读,不写库;用户说「给我点建议 / 本周该做什么 / 我的知识库健康吗」时调用,'
      '再据此用 propose_* 工具给出具体行动。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'lookahead_days': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 30,
        'description': '定期事项的前瞻窗口,默认 7 天。',
      },
      'sample': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 10,
        'description': '每类返回的样例条数,默认 5。',
      },
    },
    'required': <String>[],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final lookahead = (input['lookahead_days'] is num)
        ? (input['lookahead_days'] as num).toInt().clamp(0, 30)
        : 7;
    final sample = (input['sample'] is num)
        ? (input['sample'] as num).toInt().clamp(1, 10)
        : 5;

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final now = DateTime.now().toUtc();

    final dueReviews = await repo.listDueReviews(
      ownerUserId: ownerUserId,
      asOf: now,
    );
    final dueRoutines = await repo.listDueRoutines(
      ownerUserId: ownerUserId,
      asOf: now.add(Duration(days: lookahead)),
      excludeDoneSince: _startOfLocalDay(now),
    );
    final assumptions = await repo.listOpenAssumptions(
      ownerUserId: ownerUserId,
    );
    final staleAssumptions = assumptions
        .where((a) {
          final v = a.lastVerifiedAt;
          if (v == null) return true;
          return now.difference(v.toUtc()).inDays > kStaleAssumptionDays;
        })
        .toList(growable: false);
    final notes = await repo.listNotes(ownerUserId: ownerUserId, limit: 500);
    final orphans = notes
        .where((n) => n.tags.isEmpty && (n.projectTag == null))
        .toList(growable: false);

    final sections = <Map<String, Object?>>[
      _section(
        'due_reviews',
        '到期复盘的决策',
        dueReviews.length,
        dueReviews.take(sample).map((d) => _item(d.id, d.question)),
      ),
      _section(
        'due_routines',
        '本周到期的定期事项',
        dueRoutines.length,
        dueRoutines.take(sample).map((r) => _item(r.id, r.statement)),
      ),
      _section(
        'stale_assumptions',
        '长期未校验的假设',
        staleAssumptions.length,
        staleAssumptions.take(sample).map((a) => _item(a.id, a.statement)),
      ),
      _section(
        'orphan_notes',
        '没有标签 / 链接的孤儿笔记',
        orphans.length,
        orphans.take(sample).map((KnowledgeNote n) => _item(n.id, n.title)),
      ),
    ];

    final total = sections.fold<int>(0, (sum, s) => sum + (s['count'] as int));

    return <String, Object?>{
      'as_of': now.toIso8601String(),
      'total_items': total,
      // Highest-count, most-actionable first so the model leads with it.
      'sections': sections.where((s) => (s['count'] as int) > 0).toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int)),
      if (total == 0) 'note': '知识库当前没有待办事项 —— 一切都在掌控中。',
    };
  }

  static Map<String, Object?> _section(
    String key,
    String labelZh,
    int count,
    Iterable<Map<String, Object?>> items,
  ) => <String, Object?>{
    'key': key,
    'label_zh': labelZh,
    'count': count,
    'items': items.toList(growable: false),
  };

  static Map<String, Object?> _item(String id, String label) =>
      <String, Object?>{'id': id, 'label': label};
}

DateTime _startOfLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
