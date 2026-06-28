/// `execution_review` — weekly ExecutionOS review agent.
///
/// Summarises the open execution surface (today-worthy actions, blocked work,
/// active projects/commitments, and recent progress) into an episodic memory.
/// The UI remains repository-driven; this memory is for recall and agent
/// continuity.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

const String kExecutionReviewAgentId = 'execution_review';
const String kExecutionReviewMemorySource = 'agent:execution_review';

class ExecutionReviewAgent implements Agent {
  const ExecutionReviewAgent();

  @override
  String get id => kExecutionReviewAgentId;

  @override
  String get name => 'Execution Review';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 7), preferredHourLocal: 17);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final startedAt = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(executionRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);

    final openActions = await repo.listOpenActions(ownerUserId: ownerUserId);
    final projects = await repo.listActiveProjects(ownerUserId: ownerUserId);
    final commitments = await repo.listActiveCommitments(
      ownerUserId: ownerUserId,
    );
    final recentProgress = await repo.listRecentProgress(
      ownerUserId: ownerUserId,
    );

    final weekStart = startedAt.toUtc().subtract(const Duration(days: 7));
    final weeklyProgress = recentProgress
        .where((entry) => !entry.createdAt.toUtc().isBefore(weekStart))
        .toList(growable: false);
    final dueActions = openActions
        .where((action) => action.isDue(startedAt))
        .toList(growable: false);
    final blockedActions = openActions
        .where((action) => action.status == ExecutionActionStatus.blocked)
        .toList(growable: false);
    final todayActions = openActions
        .where(
          (action) =>
              action.status == ExecutionActionStatus.doing ||
              action.status == ExecutionActionStatus.blocked ||
              action.priority == ExecutionPriority.high ||
              action.isDue(startedAt) ||
              _isTodayOrEarlier(action.scheduledFor, startedAt),
        )
        .toList(growable: false);

    if (openActions.isEmpty &&
        projects.isEmpty &&
        commitments.isEmpty &&
        weeklyProgress.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kExecutionReviewAgentId,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        reason: 'no execution signals to review',
      );
    }

    final finishedAt = DateTime.now().toUtc();
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kExecutionReviewMemorySource:$dayKey';
    final summary = _summary(
      todayActions: todayActions,
      openActions: openActions,
      blockedActions: blockedActions,
      dueActions: dueActions,
      projects: projects,
      commitments: commitments,
      weeklyProgress: weeklyProgress,
    );
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kExecutionReviewMemorySource,
      sourceId: dayKey,
      title: 'Execution review · $dayKey',
      summary: summary,
      payload: <String, Object?>{
        'context':
            'execution review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': <String, Object?>{
          'today_action_count': todayActions.length,
          'open_action_count': openActions.length,
          'blocked_action_count': blockedActions.length,
          'due_action_count': dueActions.length,
          'active_project_count': projects.length,
          'active_commitment_count': commitments.length,
          'weekly_progress_count': weeklyProgress.length,
        },
        'sample_action_ids': todayActions
            .take(5)
            .map((action) => action.id)
            .toList(growable: false),
        'sample_project_ids': projects
            .take(5)
            .map((project) => project.id)
            .toList(growable: false),
        'sample_commitment_ids': commitments
            .take(5)
            .map((commitment) => commitment.id)
            .toList(growable: false),
      },
      entities: <String>{
        'execution',
        'execution_review',
        dayKey,
        for (final action in todayActions.take(8))
          'execution_action:${action.id}',
        for (final project in projects.take(8))
          'execution_project:${project.id}',
        for (final commitment in commitments.take(8))
          'execution_commitment:${commitment.id}',
      },
      importance: blockedActions.isNotEmpty || dueActions.isNotEmpty
          ? 0.78
          : 0.62,
      confidence: 0.9,
      validFrom: startedAt.toUtc(),
      createdAt: startedAt.toUtc(),
      updatedAt: finishedAt,
    );
    await runtime.remember(memory);

    return AgentRunResult(
      agentId: kExecutionReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: summary,
      payload: memory.payload,
      memoryId: memoryId,
    );
  }

  static bool _isTodayOrEarlier(DateTime? value, DateTime now) {
    if (value == null) return false;
    final local = value.toLocal();
    final todayEnd = DateTime(now.year, now.month, now.day + 1);
    return local.isBefore(todayEnd);
  }

  static String _summary({
    required List<ExecutionAction> todayActions,
    required List<ExecutionAction> openActions,
    required List<ExecutionAction> blockedActions,
    required List<ExecutionAction> dueActions,
    required List<ExecutionProject> projects,
    required List<ExecutionCommitment> commitments,
    required List<ExecutionProgressEntry> weeklyProgress,
  }) {
    final parts = <String>[
      '${todayActions.length} today actions',
      '${openActions.length} open actions',
      '${projects.length} active projects',
      '${commitments.length} active commitments',
      '${weeklyProgress.length} progress entries this week',
    ];
    if (blockedActions.isNotEmpty) {
      parts.add('${blockedActions.length} blocked');
    }
    if (dueActions.isNotEmpty) {
      parts.add('${dueActions.length} due');
    }
    final sample = todayActions.isNotEmpty
        ? ' First: ${todayActions.first.title}.'
        : '';
    return 'Execution review: ${parts.join(' · ')}.$sample';
  }
}
