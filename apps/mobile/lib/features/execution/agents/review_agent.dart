/// `execution_review` — weekly ExecutionOS review agent.
///
/// Summarises the open execution surface (today-worthy actions, blocked work,
/// active projects/commitments, and recent progress) into an episodic memory.
/// The UI remains repository-driven; this memory is for recall and agent
/// continuity.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

const String kExecutionReviewAgentId = 'execution_review';
const String kExecutionReviewMemorySource = 'agent:execution_review';

class ExecutionReviewAgent implements Agent {
  const ExecutionReviewAgent({
    this.reviewReader = const RepositoryExecutionReviewReader(),
  });

  final ExecutionReviewReader reviewReader;

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
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = agentL10n(ctx.ref);

    final snapshot = await reviewReader.read(ctx);
    final openActions = snapshot.openActions;
    final projects = snapshot.activeProjects;
    final commitments = snapshot.activeCommitments;
    final recentProgress = snapshot.recentProgress;

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
        snapshot.activeProjectCount == 0 &&
        snapshot.activeCommitmentCount == 0 &&
        weeklyProgress.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kExecutionReviewAgentId,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        reason: l10n.executionAgentReviewSkipNoSignals,
      );
    }

    final finishedAt = DateTime.now().toUtc();
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kExecutionReviewMemorySource:$dayKey';
    final artifactId = '$kExecutionReviewAgentId:$dayKey';
    final summary = _summary(
      l10n: l10n,
      todayActions: todayActions,
      openActions: openActions,
      blockedActions: blockedActions,
      dueActions: dueActions,
      activeProjectCount: snapshot.activeProjectCount,
      activeCommitmentCount: snapshot.activeCommitmentCount,
      weeklyProgress: weeklyProgress,
    );
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kExecutionReviewMemorySource,
      sourceId: dayKey,
      title: l10n.executionAgentReviewMemoryTitle(dayKey),
      summary: summary,
      payload: <String, Object?>{
        'context':
            'execution review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': <String, Object?>{
          'today_action_count': todayActions.length,
          'open_action_count': openActions.length,
          'blocked_action_count': blockedActions.length,
          'due_action_count': dueActions.length,
          'active_project_count': snapshot.activeProjectCount,
          'active_commitment_count': snapshot.activeCommitmentCount,
          'weekly_progress_count': weeklyProgress.length,
          if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
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
        'artifact_id': artifactId,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
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
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _artifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        memoryId: memoryId,
        createdAt: startedAt,
        summary: summary,
        todayActions: todayActions,
        openActions: openActions,
        blockedActions: blockedActions,
        dueActions: dueActions,
        projects: projects,
        commitments: commitments,
        weeklyProgress: weeklyProgress,
        traceId: snapshot.traceId,
        l10n: l10n,
      ),
    );

    return AgentRunResult(
      agentId: kExecutionReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: summary,
      payload: memory.payload,
      memoryId: memoryId,
      artifactId: artifactId,
      traceId: snapshot.traceId,
    );
  }

  static AgentArtifact _artifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required DateTime createdAt,
    required String summary,
    required List<ExecutionReviewAction> todayActions,
    required List<ExecutionReviewAction> openActions,
    required List<ExecutionReviewAction> blockedActions,
    required List<ExecutionReviewAction> dueActions,
    required List<ExecutionReviewRef> projects,
    required List<ExecutionReviewRef> commitments,
    required List<ExecutionReviewProgress> weeklyProgress,
    required String? traceId,
    required AppLocalizations l10n,
  }) {
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kExecutionReviewAgentId,
      domain: 'execution',
      kind: AgentArtifactKind.review,
      severity: blockedActions.isNotEmpty || dueActions.isNotEmpty
          ? AgentArtifactSeverity.attention
          : AgentArtifactSeverity.info,
      title: l10n.executionAgentReviewTitle,
      summary: summary,
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.executionAgentReviewInsightTodayTitle,
          value: todayActions.length.toString(),
        ),
        AgentMetric(
          label: l10n.executionAgentReviewInsightBlockedTitle,
          value: blockedActions.length.toString(),
          severity: blockedActions.isNotEmpty
              ? AgentArtifactSeverity.warning
              : null,
        ),
        AgentMetric(
          label: l10n.executionAgentReviewInsightDueTitle,
          value: dueActions.length.toString(),
          severity: dueActions.isNotEmpty
              ? AgentArtifactSeverity.attention
              : null,
        ),
      ],
      insights: <AgentInsight>[
        AgentInsight(
          id: 'today_focus',
          title: l10n.executionAgentReviewInsightTodayTitle,
          body: l10n.executionAgentReviewInsightTodayBody(
            todayActions.length,
            openActions.length,
          ),
          severity: todayActions.isEmpty
              ? AgentArtifactSeverity.info
              : AgentArtifactSeverity.attention,
          evidenceIds: <String>[for (final item in todayActions) item.id],
          route: ExecutionRoutes.today,
          payload: <String, Object?>{
            'today_action_count': todayActions.length,
            'open_action_count': openActions.length,
          },
        ),
        if (blockedActions.isNotEmpty)
          AgentInsight(
            id: 'blocked_actions',
            title: l10n.executionAgentReviewInsightBlockedTitle,
            body: l10n.executionAgentReviewInsightBlockedBody(
              blockedActions.length,
            ),
            severity: AgentArtifactSeverity.warning,
            evidenceIds: <String>[for (final item in blockedActions) item.id],
            route: blockedActions.isEmpty
                ? ExecutionRoutes.review
                : ExecutionRoutes.action(blockedActions.first.id),
            payload: <String, Object?>{
              'blocked_action_count': blockedActions.length,
              'blocked_action_ids': blockedActions
                  .take(5)
                  .map((action) => action.id)
                  .toList(growable: false),
            },
          ),
        if (dueActions.isNotEmpty)
          AgentInsight(
            id: 'due_actions',
            title: l10n.executionAgentReviewInsightDueTitle,
            body: l10n.executionAgentReviewInsightDueBody(dueActions.length),
            severity: AgentArtifactSeverity.attention,
            evidenceIds: <String>[for (final item in dueActions) item.id],
            route: dueActions.isEmpty
                ? ExecutionRoutes.review
                : ExecutionRoutes.action(dueActions.first.id),
            payload: <String, Object?>{
              'due_action_count': dueActions.length,
              'due_action_ids': dueActions
                  .take(5)
                  .map((action) => action.id)
                  .toList(growable: false),
            },
          ),
        AgentInsight(
          id: 'weekly_progress',
          title: l10n.executionAgentReviewInsightProgressTitle,
          body: l10n.executionAgentReviewInsightProgressBody(
            weeklyProgress.length,
            projects.length,
            commitments.length,
          ),
          route: ExecutionRoutes.review,
          payload: <String, Object?>{
            'weekly_progress_count': weeklyProgress.length,
            'active_project_count': projects.length,
            'active_commitment_count': commitments.length,
          },
        ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final action in todayActions.take(8))
          AgentEvidenceRef(
            type: 'execution_action',
            id: action.id,
            label: action.title,
            route: ExecutionRoutes.action(action.id),
            payload: <String, Object?>{
              'status': action.status.wire,
              'priority': action.priority.wire,
            },
          ),
        for (final project in projects.take(5))
          AgentEvidenceRef(
            type: 'execution_project',
            id: project.id,
            route: ExecutionRoutes.commitments,
          ),
        for (final commitment in commitments.take(5))
          AgentEvidenceRef(
            type: 'execution_commitment',
            id: commitment.id,
            route: ExecutionRoutes.commitment(commitment.id),
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.executionAgentReviewAction,
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: ExecutionRoutes.review,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.executionAgentReviewTitle,
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }

  static bool _isTodayOrEarlier(DateTime? value, DateTime now) {
    if (value == null) return false;
    final local = value.toLocal();
    final todayEnd = DateTime(now.year, now.month, now.day + 1);
    return local.isBefore(todayEnd);
  }

  static String _summary({
    required AppLocalizations l10n,
    required List<ExecutionReviewAction> todayActions,
    required List<ExecutionReviewAction> openActions,
    required List<ExecutionReviewAction> blockedActions,
    required List<ExecutionReviewAction> dueActions,
    required int activeProjectCount,
    required int activeCommitmentCount,
    required List<ExecutionReviewProgress> weeklyProgress,
  }) {
    final parts = <String>[
      l10n.executionAgentReviewSummaryPartToday(todayActions.length),
      l10n.executionAgentReviewSummaryPartOpen(openActions.length),
      l10n.executionAgentReviewSummaryPartProjects(activeProjectCount),
      l10n.executionAgentReviewSummaryPartCommitments(activeCommitmentCount),
      l10n.executionAgentReviewSummaryPartProgress(weeklyProgress.length),
    ];
    if (blockedActions.isNotEmpty) {
      parts.add(
        l10n.executionAgentReviewSummaryPartBlocked(blockedActions.length),
      );
    }
    if (dueActions.isNotEmpty) {
      parts.add(l10n.executionAgentReviewSummaryPartDue(dueActions.length));
    }
    final sample = todayActions.isNotEmpty
        ? l10n.executionAgentReviewSummaryFirst(todayActions.first.title)
        : '';
    return l10n.executionAgentReviewSummary(parts.join(' · '), sample);
  }
}

abstract class ExecutionReviewReader {
  Future<ExecutionReviewSnapshot> read(AgentContext ctx);
}

class RepositoryExecutionReviewReader implements ExecutionReviewReader {
  const RepositoryExecutionReviewReader();

  @override
  Future<ExecutionReviewSnapshot> read(AgentContext ctx) async {
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(executionRepositoryProvider.future);
    final openActions = await repo.listOpenActions(ownerUserId: ownerUserId);
    final projects = await repo.listActiveProjects(ownerUserId: ownerUserId);
    final commitments = await repo.listActiveCommitments(
      ownerUserId: ownerUserId,
    );
    final recentProgress = await repo.listRecentProgress(
      ownerUserId: ownerUserId,
    );
    return ExecutionReviewSnapshot(
      openActions: openActions
          .map(ExecutionReviewAction.fromAction)
          .toList(growable: false),
      activeProjects: projects
          .map((p) => ExecutionReviewRef(id: p.id))
          .toList(growable: false),
      activeCommitments: commitments
          .map((c) => ExecutionReviewRef(id: c.id))
          .toList(growable: false),
      recentProgress: recentProgress
          .map(ExecutionReviewProgress.fromProgress)
          .toList(growable: false),
      activeProjectCount: projects.length,
      activeCommitmentCount: commitments.length,
    );
  }
}

class FrbExecutionReviewReader implements ExecutionReviewReader {
  const FrbExecutionReviewReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryExecutionReviewReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final ExecutionReviewReader fallback;

  @override
  Future<ExecutionReviewSnapshot> read(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'list_open_actions',
          input: <String, Object?>{'limit': 100},
        ),
        AgentRuntimeEffect.tool(
          name: 'summarize_execution_progress',
          input: <String, Object?>{'limit': 100},
        ),
      ],
      maxEffectSteps: 2,
      fallback: () => fallback.read(ctx),
      decode: (stepRun) => executionReviewSnapshotFromTerminalStep(
        stepRun.terminalStep,
        traceId: stepRun.traceId,
      ),
    );
  }
}

class ExecutionReviewSnapshot {
  const ExecutionReviewSnapshot({
    required this.openActions,
    required this.activeProjects,
    required this.activeCommitments,
    required this.recentProgress,
    required this.activeProjectCount,
    required this.activeCommitmentCount,
    this.traceId,
  });

  final List<ExecutionReviewAction> openActions;
  final List<ExecutionReviewRef> activeProjects;
  final List<ExecutionReviewRef> activeCommitments;
  final List<ExecutionReviewProgress> recentProgress;
  final int activeProjectCount;
  final int activeCommitmentCount;
  final String? traceId;
}

class ExecutionReviewAction {
  const ExecutionReviewAction({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.dueAt,
    this.scheduledFor,
  });

  factory ExecutionReviewAction.fromAction(ExecutionAction action) {
    return ExecutionReviewAction(
      id: action.id,
      title: action.title,
      status: action.status,
      priority: action.priority,
      dueAt: action.dueAt,
      scheduledFor: action.scheduledFor,
    );
  }

  final String id;
  final String title;
  final ExecutionActionStatus status;
  final ExecutionPriority priority;
  final DateTime? dueAt;
  final DateTime? scheduledFor;

  bool isDue(DateTime now) {
    final due = dueAt;
    return due != null && !due.toUtc().isAfter(now.toUtc());
  }
}

class ExecutionReviewRef {
  const ExecutionReviewRef({required this.id});

  final String id;
}

class ExecutionReviewProgress {
  const ExecutionReviewProgress({required this.id, required this.createdAt});

  factory ExecutionReviewProgress.fromProgress(ExecutionProgressEntry entry) {
    return ExecutionReviewProgress(id: entry.id, createdAt: entry.createdAt);
  }

  final String id;
  final DateTime createdAt;
}

ExecutionReviewSnapshot? executionReviewSnapshotFromTerminalStep(
  Map<String, Object?> step, {
  String? traceId,
}) {
  final byTool = agentRuntimeTerminalEffectResultsByToolName(step);
  final actions = executionReviewActionsFromToolResult(
    byTool['list_open_actions'],
  );
  final summary = byTool['summarize_execution_progress'];
  final projects = _refsFromList(summary?['active_projects']);
  final commitments = _refsFromList(summary?['active_commitments']);
  final progress = executionReviewProgressFromToolResult(summary);
  final projectCount = _intValue(summary?['active_project_count']);
  final commitmentCount = _intValue(summary?['active_commitment_count']);
  if (actions == null ||
      projects == null ||
      commitments == null ||
      progress == null ||
      projectCount == null ||
      commitmentCount == null) {
    return null;
  }
  return ExecutionReviewSnapshot(
    openActions: actions,
    activeProjects: projects,
    activeCommitments: commitments,
    recentProgress: progress,
    activeProjectCount: projectCount,
    activeCommitmentCount: commitmentCount,
    traceId: traceId,
  );
}

List<ExecutionReviewAction>? executionReviewActionsFromToolResult(
  Map<String, Object?>? result,
) {
  final rawActions = result?['actions'];
  if (rawActions is! List) return null;
  final actions = <ExecutionReviewAction>[];
  for (final raw in rawActions) {
    final action = _asObject(raw);
    final id = action?['id'];
    final title = action?['title'];
    final status = action?['status'];
    final priority = action?['priority'];
    if (id is! String ||
        title is! String ||
        status is! String ||
        priority is! String) {
      return null;
    }
    actions.add(
      ExecutionReviewAction(
        id: id,
        title: title,
        status: ExecutionActionStatus.parse(status),
        priority: ExecutionPriority.parse(priority),
        dueAt: _dateTime(action?['due_at']),
        scheduledFor: _dateTime(action?['scheduled_for']),
      ),
    );
  }
  return actions;
}

List<ExecutionReviewProgress>? executionReviewProgressFromToolResult(
  Map<String, Object?>? result,
) {
  final rawProgress = result?['recent_progress'];
  if (rawProgress is! List) return null;
  final progress = <ExecutionReviewProgress>[];
  for (final raw in rawProgress) {
    final entry = _asObject(raw);
    final id = entry?['id'];
    final createdAt = entry?['created_at'];
    if (id is! String || createdAt is! String) return null;
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return null;
    progress.add(ExecutionReviewProgress(id: id, createdAt: parsed.toUtc()));
  }
  return progress;
}

List<ExecutionReviewRef>? _refsFromList(Object? value) {
  if (value is! List) return null;
  final refs = <ExecutionReviewRef>[];
  for (final raw in value) {
    final object = _asObject(raw);
    final id = object?['id'];
    if (id is! String) return null;
    refs.add(ExecutionReviewRef(id: id));
  }
  return refs;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int? _intValue(Object? value) {
  if (value is num) return value.toInt();
  return null;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
