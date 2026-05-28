/// `knowledge_routine_due` — daily routine reminder agent
/// (`docs/knowledgeos-domain.md` §7).
///
/// Fires once a day around 08:00 local. Lists active routines whose
/// `nextDueAt <= now + 7d` (this-week window) and emits a single episodic
/// memory + one local notification on the `lifeos.knowledge.review`
/// channel. The user resolves each from the Review tab — tapping "已处理"
/// bumps `lastDoneAt = now`, `nextDueAt = now + intervalDays`.
///
/// Notifications are optional: when the platform reports no permission /
/// is unsupported (web, no notifier injected), the memory record alone
/// drives the Review tab card.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

const String kKnowledgeRoutineAgentId = 'knowledge_routine_due';
const String kKnowledgeRoutineMemorySource = 'agent:knowledge_routine_due';

/// Look-ahead window: surface routines coming due within 7 days, not
/// just already-overdue ones, so the user can act before the deadline
/// (e.g. activate a HK card before the dormancy mark).
const Duration kRoutineDueLookahead = Duration(days: 7);

class RoutineDueAgent implements Agent {
  const RoutineDueAgent({this.notifier, this.hourLocal = 8});

  /// Optional local-notification hook. When supplied and the platform
  /// has granted permission, the agent posts a one-shot toast after
  /// each successful run on the [NotificationChannelSpec.knowledgeReview]
  /// channel.
  final NotificationService? notifier;

  /// Local hour-of-day anchor (0–23). Default 08:00 keeps the toast in
  /// morning routine territory without colliding with HealthOS's 07:00
  /// Morning Briefing.
  final int hourLocal;

  @override
  String get id => kKnowledgeRoutineAgentId;

  @override
  String get name => 'Routine Due';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: hourLocal);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);

    final due = await repo.listDueRoutines(
      ownerUserId: ownerUserId,
      asOf: start.add(kRoutineDueLookahead),
    );
    final finished = DateTime.now().toUtc();

    if (due.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeRoutineAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: 'no routines due in the next 7 days',
      );
    }

    // Split overdue vs. upcoming so the summary line can lead with the
    // more urgent count when both are non-empty.
    final overdue = due.where((r) => r.isDue(start)).toList(growable: false);
    final upcoming = due
        .where((r) => !r.isDue(start))
        .toList(growable: false);

    final summary = _summarize(
      overdueCount: overdue.length,
      upcomingCount: upcoming.length,
      first: due.first,
      now: start,
    );

    final dayKey = start.toUtc().toIso8601String().substring(0, 10);
    final memoryId = '$kKnowledgeRoutineMemorySource:$dayKey';
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kKnowledgeRoutineMemorySource,
      sourceId: dayKey,
      title: '本周到期的 Routine',
      summary: summary,
      payload: <String, Object?>{
        'context': 'routine-due agent tick at ${start.toUtc().toIso8601String()}',
        'overdue_routine_ids':
            overdue.map((r) => r.id).toList(growable: false),
        'upcoming_routine_ids':
            upcoming.map((r) => r.id).toList(growable: false),
        'lookahead_days': kRoutineDueLookahead.inDays,
      },
      entities: <String>{'knowledge_routine', 'routine_due'},
      importance: overdue.isNotEmpty ? 0.75 : 0.5,
      confidence: 0.95,
      validFrom: start.toUtc(),
      createdAt: start.toUtc(),
      updatedAt: finished,
    );
    await runtime.remember(memory);

    final n = notifier;
    if (n != null) {
      await _maybeNotify(start.toLocal(), summary, n);
    }

    return AgentRunResult(
      agentId: kKnowledgeRoutineAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'overdue_count': overdue.length,
        'upcoming_count': upcoming.length,
      },
      memoryId: memoryId,
    );
  }

  static String _summarize({
    required int overdueCount,
    required int upcomingCount,
    required KnowledgeRoutine first,
    required DateTime now,
  }) {
    final days = first.daysUntilDue(now);
    final leadFirst = days < 0
        ? '${first.statement}（已逾期 ${-days} 天）'
        : days == 0
            ? '${first.statement}（今日到期）'
            : '${first.statement}（$days 天后到期）';
    if (overdueCount > 0 && upcomingCount > 0) {
      return '$overdueCount 条已逾期 + $upcomingCount 条本周到期，首条:$leadFirst';
    }
    if (overdueCount > 0) {
      if (overdueCount == 1) return '1 条 Routine 已逾期:$leadFirst';
      return '$overdueCount 条 Routine 已逾期，首条:$leadFirst';
    }
    if (upcomingCount == 1) return '1 条 Routine 本周到期:$leadFirst';
    return '$upcomingCount 条 Routine 本周到期，首条:$leadFirst';
  }

  Future<void> _maybeNotify(
    DateTime localDay,
    String summary,
    NotificationService n,
  ) async {
    try {
      if (!await n.hasPermissions()) return;
      await n.showNow(
        id: KnowledgeNotifications.idForRoutineDigest(localDay),
        title: '本周到期的 Routine',
        body: summary,
        payload: kKnowledgeRoutineAgentId,
        channel: NotificationChannelSpec.knowledgeReview,
      );
    } on Object {
      // Best-effort — a notification failure must not mark the agent
      // run failed. The memory record above is the durable surface.
    }
  }
}
