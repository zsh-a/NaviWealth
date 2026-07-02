/// `knowledge_routine_due` — daily routine reminder agent
/// (`docs/domains/knowledgeos-domain.md` §7).
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

import '../../../app/agent_runtime/agent_runtime_tool_plan_binding.dart';
import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_l10n.dart';
import '_agent_memory.dart';
import 'knowledge_notifications.dart';

const String kKnowledgeRoutineAgentId = 'knowledge_routine_due';
const String kKnowledgeRoutineMemorySource = 'agent:knowledge_routine_due';

/// Look-ahead window: surface routines coming due within 7 days, not
/// just already-overdue ones, so the user can act before the deadline
/// (e.g. activate a HK card before the dormancy mark).
const Duration kRoutineDueLookahead = Duration(days: 7);

class RoutineDueAgent implements Agent {
  const RoutineDueAgent({
    this.notifier,
    this.hourLocal = 8,
    this.dueReader = const RepositoryRoutineDueReader(),
  });

  /// Optional local-notification hook. When supplied and the platform
  /// has granted permission, the agent posts a one-shot toast after
  /// each successful run on the Knowledge review notification channel.
  final NotificationService? notifier;

  /// Local hour-of-day anchor (0–23). Default 08:00 keeps the toast in
  /// morning routine territory without colliding with HealthOS's 07:00
  /// Morning Briefing.
  final int hourLocal;
  final RoutineDueReader dueReader;

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
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = knowledgeAgentL10n(ctx.ref);

    final due = await dueReader.listDue(ctx);
    final finished = DateTime.now().toUtc();

    if (due.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeRoutineAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: l10n.knowledgeAgentRoutineNoneDue(kRoutineDueLookahead.inDays),
      );
    }

    // Split overdue vs. upcoming so the summary line can lead with the
    // more urgent count when both are non-empty.
    final overdue = due.where((r) => r.isDue(start)).toList(growable: false);
    final upcoming = due.where((r) => !r.isDue(start)).toList(growable: false);

    final summary = _summarize(
      l10n: l10n,
      overdueCount: overdue.length,
      upcomingCount: upcoming.length,
      first: due.first,
      now: start,
    );

    final built = buildAgentMemory(
      source: kKnowledgeRoutineMemorySource,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: l10n.knowledgeAgentRoutineTitle,
      summary: summary,
      payload: <String, Object?>{
        'context':
            'routine-due agent tick at ${start.toUtc().toIso8601String()}',
        'overdue_routine_ids': overdue.map((r) => r.id).toList(growable: false),
        'upcoming_routine_ids': upcoming
            .map((r) => r.id)
            .toList(growable: false),
        'lookahead_days': kRoutineDueLookahead.inDays,
      },
      entities: <String>{'knowledge_routine', 'routine_due'},
      importance: overdue.isNotEmpty ? 0.75 : 0.5,
      confidence: 0.95,
    );
    await runtime.remember(built.record);

    final n = notifier;
    if (n != null) {
      await _maybeNotify(start.toLocal(), l10n, summary, n);
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
      memoryId: built.memoryId,
    );
  }

  static String _summarize({
    required AppLocalizations l10n,
    required int overdueCount,
    required int upcomingCount,
    required RoutineDueItem first,
    required DateTime now,
  }) {
    final days = first.daysUntilDue(now);
    final leadFirst = days < 0
        ? l10n.knowledgeAgentRoutineLeadOverdue(-days, first.statement)
        : days == 0
        ? l10n.knowledgeAgentRoutineLeadToday(first.statement)
        : l10n.knowledgeAgentRoutineLeadUpcoming(days, first.statement);
    if (overdueCount > 0 && upcomingCount > 0) {
      return l10n.knowledgeAgentRoutineSummaryMixed(
        leadFirst,
        overdueCount,
        upcomingCount,
      );
    }
    if (overdueCount > 0) {
      if (overdueCount == 1) {
        return l10n.knowledgeAgentRoutineSummaryOverdueOne(leadFirst);
      }
      return l10n.knowledgeAgentRoutineSummaryOverdueMany(
        overdueCount,
        leadFirst,
      );
    }
    if (upcomingCount == 1) {
      return l10n.knowledgeAgentRoutineSummaryUpcomingOne(leadFirst);
    }
    return l10n.knowledgeAgentRoutineSummaryUpcomingMany(
      upcomingCount,
      leadFirst,
    );
  }

  Future<void> _maybeNotify(
    DateTime localDay,
    AppLocalizations l10n,
    String summary,
    NotificationService n,
  ) async {
    try {
      if (!await n.hasPermissions()) return;
      await n.showNow(
        id: KnowledgeNotifications.idForRoutineDigest(localDay),
        title: l10n.knowledgeAgentRoutineTitle,
        body: summary,
        payload: kKnowledgeRoutineAgentId,
        channel: kKnowledgeReviewNotificationChannel,
      );
    } on Object {
      // Best-effort — a notification failure must not mark the agent
      // run failed. The memory record above is the durable surface.
    }
  }
}

abstract class RoutineDueReader {
  Future<List<RoutineDueItem>> listDue(AgentContext ctx);
}

class RepositoryRoutineDueReader implements RoutineDueReader {
  const RepositoryRoutineDueReader();

  @override
  Future<List<RoutineDueItem>> listDue(AgentContext ctx) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final due = await repo.listDueRoutines(
      ownerUserId: ownerUserId,
      asOf: ctx.now.add(kRoutineDueLookahead),
      excludeDoneSince: _startOfLocalDay(ctx.now),
    );
    return due.map(RoutineDueItem.fromRoutine).toList(growable: false);
  }
}

class FrbRoutineDueReader implements RoutineDueReader {
  const FrbRoutineDueReader({
    required AgentRuntimeToolPlanBinding runtime,
    this.fallback = const RepositoryRoutineDueReader(),
  }) : _runtime = runtime;

  final AgentRuntimeToolPlanBinding _runtime;
  final RoutineDueReader fallback;

  @override
  Future<List<RoutineDueItem>> listDue(AgentContext ctx) async {
    final asOf = ctx.now.add(kRoutineDueLookahead).toUtc().toIso8601String();
    return _runtime.readFromToolPlan(
      toolPlan: <Map<String, Object?>>[
        <String, Object?>{
          'name': 'list_due_routines',
          'input': <String, Object?>{'as_of': asOf, 'limit': 50},
        },
      ],
      maxToolSteps: 1,
      fallback: () => fallback.listDue(ctx),
      decode: (terminalStep) {
        final result = agentRuntimeTerminalToolResult(
          terminalStep,
          'list_due_routines',
        );
        return routineDueItemsFromToolResult(result);
      },
    );
  }
}

class RoutineDueItem {
  const RoutineDueItem({
    required this.id,
    required this.statement,
    required this.nextDueAt,
  });

  factory RoutineDueItem.fromRoutine(KnowledgeRoutine routine) {
    return RoutineDueItem(
      id: routine.id,
      statement: routine.statement,
      nextDueAt: routine.nextDueAt,
    );
  }

  final String id;
  final String statement;
  final DateTime nextDueAt;

  int daysUntilDue(DateTime now) =>
      nextDueAt.toUtc().difference(now.toUtc()).inDays;

  bool isDue(DateTime now) => !nextDueAt.toUtc().isAfter(now.toUtc());
}

List<RoutineDueItem>? routineDueItemsFromToolResult(
  Map<String, Object?>? result,
) {
  final rawRoutines = result?['routines'];
  if (rawRoutines is! List) return null;
  final items = <RoutineDueItem>[];
  for (final raw in rawRoutines) {
    final routine = _asObject(raw);
    final id = routine?['id'];
    final statement = routine?['statement'];
    final nextDueAt = routine?['next_due_at'];
    if (id is! String || statement is! String || nextDueAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(nextDueAt);
    if (parsed == null) return null;
    items.add(
      RoutineDueItem(id: id, statement: statement, nextDueAt: parsed.toUtc()),
    );
  }
  return items;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

DateTime _startOfLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
