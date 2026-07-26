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

import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../agents/contradiction_agent.dart' show kKnowledgeContradictionAgentId;
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class ReviewKnowledgeHealthTool implements DeviceTool {
  const ReviewKnowledgeHealthTool();

  /// Assumptions unverified for longer than this count as stale.
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
        .where((a) => a.daysSinceVerify(now) >= kKnowledgeAssumptionStaleDays)
        .toList(growable: false);
    final notes = await _listAllNotes(repo, ownerUserId);
    final relatedNoteIds = await repo.listRelatedObjectIds(
      ownerUserId: ownerUserId,
      kind: KnowledgeEntryKind.note.name,
    );
    final orphanGraceStart = now.subtract(const Duration(hours: 24));
    final orphans = notes
        .where(
          (note) =>
              note.createdAt.toUtc().isBefore(orphanGraceStart) &&
              note.tags.isEmpty &&
              (note.projectTag == null || note.projectTag!.trim().isEmpty) &&
              !relatedNoteIds.contains(note.id),
        )
        .toList(growable: false);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
    final pendingTriage = await triage.listPending(
      ownerUserId: ownerUserId,
      limit: 100,
    );
    final findingStore = await ctx.ref.read(
      agent_providers.agentFindingStoreProvider.future,
    );
    final contradictions = await findingStore.listOpen(
      ownerUserId: ownerUserId,
      domain: 'knowledge',
      agentId: kKnowledgeContradictionAgentId,
      limit: 100,
    );

    final sections = <Map<String, Object?>>[
      _section(
        'contradictions',
        '待处理的知识矛盾',
        contradictions.length,
        contradictions
            .take(sample)
            .map(
              (finding) => _item(
                finding.id,
                '${finding.payload['subject_kind']} '
                '${finding.payload['subject_id']} ↔ '
                '${finding.payload['reference_id']}',
              ),
            ),
      ),
      _section(
        'due_reviews',
        '到期复盘的决策',
        dueReviews.length,
        dueReviews.take(sample).map((d) => _item(d.id, d.question)),
      ),
      _section(
        'inbox_triage',
        '待确认的 Inbox 建议',
        pendingTriage.length,
        pendingTriage
            .take(sample)
            .map(
              (record) => _item(record.noteId, 'Inbox note ${record.noteId}'),
            ),
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
      // Risk order is deliberate: one overdue decision matters more than a
      // large low-risk cleanup backlog.
      'sections': sections.where((s) => (s['count'] as int) > 0).toList()
        ..sort(
          (a, b) => _sectionPriority(
            a['key'] as String,
          ).compareTo(_sectionPriority(b['key'] as String)),
        ),
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

int _sectionPriority(String key) => switch (key) {
  'contradictions' => 0,
  'due_reviews' => 1,
  'stale_assumptions' => 2,
  'due_routines' => 3,
  'inbox_triage' => 4,
  'orphan_notes' => 5,
  _ => 99,
};

Future<List<KnowledgeNote>> _listAllNotes(
  KnowledgeRepository repo,
  String ownerUserId,
) async {
  const pageSize = 500;
  final out = <KnowledgeNote>[];
  var offset = 0;
  while (true) {
    final page = await repo.listNotes(
      ownerUserId: ownerUserId,
      limit: pageSize,
      offset: offset,
    );
    out.addAll(page);
    if (page.length < pageSize) return out;
    offset += page.length;
  }
}

DateTime _startOfLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
