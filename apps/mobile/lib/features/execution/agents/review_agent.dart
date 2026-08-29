/// `execution_review` — weekly ExecutionOS review agent.
///
/// Summarises the open execution surface (today-worthy actions, blocked work,
/// active plans and recent progress) into a temporary artifact.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_finding_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

const String kExecutionReviewAgentId = 'execution_review';

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
    final l10n = agentL10n(ctx.ref);

    final snapshot = await reviewReader.read(ctx);
    final openActions = snapshot.openActions;
    final plans = snapshot.activePlans;
    final recentProgress = snapshot.recentProgress;
    final recentClosedActions = snapshot.recentClosedActions;

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
        .toList();
    todayActions.sort(
      (a, b) => b.focusScore(startedAt).compareTo(a.focusScore(startedAt)),
    );
    final stalledActions = openActions
        .where(
          (action) =>
              action.status == ExecutionActionStatus.doing &&
              startedAt.toUtc().difference(action.updatedAt).inDays >= 7,
        )
        .toList(growable: false);
    final planIdsWithActions = openActions
        .map((action) => action.planId)
        .whereType<String>()
        .toSet();
    final plansWithoutNextAction = plans
        .where((plan) => !planIdsWithActions.contains(plan.id))
        .toList(growable: false);
    final overduePlans = plans
        .where(
          (plan) =>
              plan.targetDate != null &&
              !plan.targetDate!.toUtc().isAfter(startedAt.toUtc()),
        )
        .toList(growable: false);
    final blockerOccurrences = <String, int>{};
    for (final progress in weeklyProgress) {
      final actionId = progress.actionId;
      if (progress.kind != ExecutionProgressKind.blocker ||
          actionId == null ||
          actionId.isEmpty) {
        continue;
      }
      blockerOccurrences.update(
        actionId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final repeatedBlockerActionIds = blockerOccurrences.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toSet();
    final overloaded = todayActions.length > 5;
    final completedThisWeek = recentClosedActions
        .where((action) => action.status == ExecutionActionStatus.done)
        .length;
    final droppedThisWeek = recentClosedActions
        .where((action) => action.status == ExecutionActionStatus.dropped)
        .length;
    final actionOutcomes = ctx.ref.read(actionOutcomeSummariesProvider);
    final evaluatedOutcomes = <String, ActionOutcomeSummary>{
      for (final action in recentClosedActions)
        action.id: ?actionOutcomes[action.id],
    };
    final findingStore = await ctx.ref.read(
      agent_providers.agentFindingStoreProvider.future,
    );
    await findingStore.reconcile(
      ownerUserId: ownerUserId,
      agentId: kExecutionReviewAgentId,
      observedAt: startedAt,
      findings: <AgentFinding>[
        for (final action in blockedActions)
          AgentFinding(
            id: 'execution_finding:blocked:${action.id}',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'blocked_action',
            severity: AgentArtifactSeverity.warning,
            confidence: 1,
            payload: <String, Object?>{
              'action_id': action.id,
              'title': action.title,
              'updated_at': action.updatedAt.toIso8601String(),
            },
          ),
        for (final action in dueActions)
          AgentFinding(
            id: 'execution_finding:due:${action.id}',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'due_action',
            severity: AgentArtifactSeverity.attention,
            confidence: 1,
            payload: <String, Object?>{
              'action_id': action.id,
              'title': action.title,
              'due_at': action.dueAt?.toIso8601String(),
            },
          ),
        for (final action in stalledActions)
          AgentFinding(
            id: 'execution_finding:stalled:${action.id}',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'stalled_action',
            severity: AgentArtifactSeverity.warning,
            confidence: 1,
            payload: <String, Object?>{
              'action_id': action.id,
              'title': action.title,
              'updated_at': action.updatedAt.toIso8601String(),
            },
          ),
        for (final plan in plansWithoutNextAction)
          AgentFinding(
            id: 'execution_finding:no_next_action:plan:${plan.id}',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'plan_without_next_action',
            severity: AgentArtifactSeverity.attention,
            confidence: 1,
            payload: <String, Object?>{'plan_id': plan.id, 'title': plan.title},
          ),
        for (final plan in overduePlans)
          AgentFinding(
            id: 'execution_finding:overdue_plan:${plan.id}',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'overdue_plan',
            severity: AgentArtifactSeverity.warning,
            confidence: 1,
            payload: <String, Object?>{
              'plan_id': plan.id,
              'title': plan.title,
              'target_date': plan.targetDate?.toIso8601String(),
            },
          ),
        for (final actionId in repeatedBlockerActionIds)
          AgentFinding(
            id: 'execution_finding:repeated_blocker:$actionId',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'repeated_blocker',
            severity: AgentArtifactSeverity.warning,
            confidence: 1,
            payload: <String, Object?>{
              'action_id': actionId,
              'occurrences': blockerOccurrences[actionId],
            },
          ),
        if (overloaded)
          AgentFinding(
            id: 'execution_finding:today_overload',
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
            domain: 'execution',
            kind: 'today_overload',
            severity: AgentArtifactSeverity.warning,
            confidence: 1,
            payload: <String, Object?>{
              'action_ids': todayActions
                  .map((action) => action.id)
                  .toList(growable: false),
              'suggested_focus_limit': 5,
            },
          ),
      ],
    );

    if (openActions.isEmpty &&
        snapshot.activePlanCount == 0 &&
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
    final artifactId = '$kExecutionReviewAgentId:$dayKey';
    final summary = _summary(
      l10n: l10n,
      todayActions: todayActions,
      openActions: openActions,
      blockedActions: blockedActions,
      dueActions: dueActions,
      activePlanCount: snapshot.activePlanCount,
      weeklyProgress: weeklyProgress,
    );
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _artifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        createdAt: startedAt,
        summary: summary,
        todayActions: todayActions,
        openActions: openActions,
        blockedActions: blockedActions,
        dueActions: dueActions,
        plans: plans,
        weeklyProgress: weeklyProgress,
        recentClosedActions: recentClosedActions,
        stalledActions: stalledActions,
        plansWithoutNextAction: plansWithoutNextAction,
        overduePlans: overduePlans,
        repeatedBlockerActionIds: repeatedBlockerActionIds,
        overloaded: overloaded,
        completedThisWeek: completedThisWeek,
        droppedThisWeek: droppedThisWeek,
        evaluatedOutcomes: evaluatedOutcomes,
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
      payload: <String, Object?>{
        'today_action_count': todayActions.length,
        'open_action_count': openActions.length,
        'blocked_action_count': blockedActions.length,
        'due_action_count': dueActions.length,
        'active_plan_count': snapshot.activePlanCount,
        'weekly_progress_count': weeklyProgress.length,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
      },
      artifactId: artifactId,
      traceId: snapshot.traceId,
    );
  }

  static AgentArtifact _artifact({
    required String id,
    required String ownerUserId,
    required DateTime createdAt,
    required String summary,
    required List<ExecutionReviewAction> todayActions,
    required List<ExecutionReviewAction> openActions,
    required List<ExecutionReviewAction> blockedActions,
    required List<ExecutionReviewAction> dueActions,
    required List<ExecutionReviewRef> plans,
    required List<ExecutionReviewProgress> weeklyProgress,
    required List<ExecutionReviewAction> recentClosedActions,
    required List<ExecutionReviewAction> stalledActions,
    required List<ExecutionReviewRef> plansWithoutNextAction,
    required List<ExecutionReviewRef> overduePlans,
    required Set<String> repeatedBlockerActionIds,
    required bool overloaded,
    required int completedThisWeek,
    required int droppedThisWeek,
    required Map<String, ActionOutcomeSummary> evaluatedOutcomes,
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
          evidenceIds: <String>[
            for (final item in todayActions.take(3)) item.id,
          ],
          route: ExecutionRoutes.today,
          payload: <String, Object?>{
            'today_action_count': todayActions.length,
            'open_action_count': openActions.length,
            'recommended_focus_ids': todayActions
                .take(3)
                .map((action) => action.id)
                .toList(growable: false),
          },
        ),
        if (evaluatedOutcomes.isNotEmpty)
          AgentInsight(
            id: 'execution_finding:source_outcomes',
            title: l10n.executionAgentReviewInsightOutcomeTitle,
            body: l10n.executionAgentReviewInsightOutcomeBody(
              evaluatedOutcomes.values
                  .where(
                    (outcome) =>
                        outcome.status == ActionOutcomeStatus.signalCleared,
                  )
                  .length,
              evaluatedOutcomes.values
                  .where(
                    (outcome) =>
                        outcome.status == ActionOutcomeStatus.signalStillActive,
                  )
                  .length,
            ),
            severity:
                evaluatedOutcomes.values.any(
                  (outcome) =>
                      outcome.status == ActionOutcomeStatus.signalStillActive,
                )
                ? AgentArtifactSeverity.attention
                : AgentArtifactSeverity.info,
            evidenceIds: evaluatedOutcomes.keys.toList(growable: false),
            route: ExecutionRoutes.review,
            payload: <String, Object?>{
              'finding_id': 'execution_finding:source_outcomes',
              'outcomes': <String, Object?>{
                for (final entry in evaluatedOutcomes.entries)
                  entry.key: <String, Object?>{
                    'status': entry.value.status.name,
                    'source_label': entry.value.sourceLabel,
                    'evaluated_at': entry.value.evaluatedAt
                        .toUtc()
                        .toIso8601String(),
                    'attribution': entry.value.attribution.name,
                  },
              },
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
            plans.length,
          ),
          route: ExecutionRoutes.review,
          payload: <String, Object?>{
            'weekly_progress_count': weeklyProgress.length,
            'active_plan_count': plans.length,
          },
        ),
        if (stalledActions.isNotEmpty)
          AgentInsight(
            id: 'execution_finding:stalled_actions',
            title: l10n.executionAgentReviewInsightStalledTitle,
            body: l10n.executionAgentReviewInsightStalledBody(
              stalledActions.length,
            ),
            severity: AgentArtifactSeverity.warning,
            evidenceIds: <String>[
              for (final action in stalledActions) action.id,
            ],
            route: ExecutionRoutes.action(stalledActions.first.id),
            payload: <String, Object?>{
              'finding_id': 'execution_finding:stalled_actions',
              'action_ids': stalledActions
                  .map((action) => action.id)
                  .toList(growable: false),
              'stale_days': 7,
            },
          ),
        if (plansWithoutNextAction.isNotEmpty)
          AgentInsight(
            id: 'execution_finding:no_next_action',
            title: l10n.executionAgentReviewInsightNoNextActionTitle,
            body: l10n.executionAgentReviewInsightNoNextActionBody(
              plansWithoutNextAction.length,
            ),
            severity: AgentArtifactSeverity.attention,
            evidenceIds: <String>[
              for (final plan in plansWithoutNextAction) plan.id,
            ],
            route: ExecutionRoutes.plans,
            payload: <String, Object?>{
              'finding_id': 'execution_finding:no_next_action',
              'plan_ids': plansWithoutNextAction
                  .map((plan) => plan.id)
                  .toList(growable: false),
            },
          ),
        if (overduePlans.isNotEmpty)
          AgentInsight(
            id: 'execution_finding:overdue_targets',
            title: l10n.executionAgentReviewInsightOverdueTargetsTitle,
            body: l10n.executionAgentReviewInsightOverdueTargetsBody(
              overduePlans.length,
            ),
            severity: AgentArtifactSeverity.warning,
            evidenceIds: <String>[for (final plan in overduePlans) plan.id],
            route: ExecutionRoutes.plans,
            payload: <String, Object?>{
              'finding_id': 'execution_finding:overdue_targets',
              'plan_ids': overduePlans
                  .map((plan) => plan.id)
                  .toList(growable: false),
            },
          ),
        if (repeatedBlockerActionIds.isNotEmpty)
          AgentInsight(
            id: 'execution_finding:repeated_blockers',
            title: l10n.executionAgentReviewInsightRepeatedBlockerTitle,
            body: l10n.executionAgentReviewInsightRepeatedBlockerBody(
              repeatedBlockerActionIds.length,
            ),
            severity: AgentArtifactSeverity.warning,
            evidenceIds: repeatedBlockerActionIds.toList(growable: false),
            route: ExecutionRoutes.action(repeatedBlockerActionIds.first),
            payload: <String, Object?>{
              'finding_id': 'execution_finding:repeated_blockers',
              'action_ids': repeatedBlockerActionIds.toList(growable: false),
            },
          ),
        if (overloaded)
          AgentInsight(
            id: 'execution_finding:today_overload',
            title: l10n.executionAgentReviewInsightOverloadTitle,
            body: l10n.executionAgentReviewInsightOverloadBody(
              todayActions.length,
              5,
            ),
            severity: AgentArtifactSeverity.warning,
            route: ExecutionRoutes.today,
            payload: <String, Object?>{
              'finding_id': 'execution_finding:today_overload',
              'today_action_count': todayActions.length,
              'suggested_focus_limit': 5,
            },
          ),
        AgentInsight(
          id: 'execution_finding:weekly_throughput',
          title: l10n.executionAgentReviewInsightThroughputTitle,
          body: l10n.executionAgentReviewInsightThroughputBody(
            completedThisWeek,
            droppedThisWeek,
          ),
          route: ExecutionRoutes.review,
          payload: <String, Object?>{
            'finding_id': 'execution_finding:weekly_throughput',
            'completed_count': completedThisWeek,
            'dropped_count': droppedThisWeek,
            'closed_count': recentClosedActions.length,
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
        for (final plan in plans.take(5))
          AgentEvidenceRef(
            type: 'execution_plan',
            id: plan.id,
            label: plan.title,
            route: ExecutionRoutes.plan(plan.id),
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
        if (stalledActions.isNotEmpty ||
            plansWithoutNextAction.isNotEmpty ||
            overduePlans.isNotEmpty ||
            repeatedBlockerActionIds.isNotEmpty ||
            overloaded)
          AgentAction(
            kind: 'proposal',
            label: l10n.executionAgentReviewPlanAction,
            description: l10n.executionAgentReviewPlanActionBody,
            intent: kAgentCreatePlanFromResultIntent,
            objectType: kAgentArtifactObjectType,
            objectId: id,
            capabilities: const <String>['chat', 'proposal'],
            payload: <String, Object?>{
              'stalled_action_ids': stalledActions
                  .map((action) => action.id)
                  .toList(growable: false),
              'plans_without_next_action': plansWithoutNextAction
                  .map((plan) => plan.id)
                  .toList(growable: false),
              'today_overloaded': overloaded,
              'overdue_plan_ids': overduePlans
                  .map((plan) => plan.id)
                  .toList(growable: false),
              'repeated_blocker_action_ids': repeatedBlockerActionIds.toList(
                growable: false,
              ),
            },
          ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.executionAgentReviewTitle,
      ),
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
    required int activePlanCount,
    required List<ExecutionReviewProgress> weeklyProgress,
  }) {
    final parts = <String>[
      l10n.executionAgentReviewSummaryPartToday(todayActions.length),
      l10n.executionAgentReviewSummaryPartOpen(openActions.length),
      l10n.executionAgentReviewSummaryPartPlans(activePlanCount),
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
    final plans = await repo.listActivePlans(ownerUserId: ownerUserId);
    final recentProgress = await repo.listRecentProgress(
      ownerUserId: ownerUserId,
      limit: 500,
    );
    final recentClosedActions = await repo.listClosedActions(
      ownerUserId: ownerUserId,
      since: ctx.now.toUtc().subtract(const Duration(days: 7)),
      limit: 500,
    );
    return ExecutionReviewSnapshot(
      openActions: openActions
          .map(ExecutionReviewAction.fromAction)
          .toList(growable: false),
      activePlans: plans
          .map(
            (plan) => ExecutionReviewRef(
              id: plan.id,
              title: plan.title,
              targetDate: plan.targetDate,
            ),
          )
          .toList(growable: false),
      recentProgress: recentProgress
          .map(ExecutionReviewProgress.fromProgress)
          .toList(growable: false),
      recentClosedActions: recentClosedActions
          .map(ExecutionReviewAction.fromAction)
          .toList(growable: false),
      activePlanCount: plans.length,
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
    required this.activePlans,
    required this.recentProgress,
    this.recentClosedActions = const <ExecutionReviewAction>[],
    required this.activePlanCount,
    this.traceId,
  });

  final List<ExecutionReviewAction> openActions;
  final List<ExecutionReviewRef> activePlans;
  final List<ExecutionReviewProgress> recentProgress;
  final List<ExecutionReviewAction> recentClosedActions;
  final int activePlanCount;
  final String? traceId;
}

class ExecutionReviewAction {
  ExecutionReviewAction({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.dueAt,
    this.scheduledFor,
    this.planId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
  }) : createdAt =
           createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       updatedAt =
           updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  factory ExecutionReviewAction.fromAction(ExecutionAction action) {
    return ExecutionReviewAction(
      id: action.id,
      title: action.title,
      status: action.status,
      priority: action.priority,
      dueAt: action.dueAt,
      scheduledFor: action.scheduledFor,
      planId: action.planId,
      createdAt: action.createdAt,
      updatedAt: action.sync.updatedAt,
      completedAt: action.completedAt,
    );
  }

  final String id;
  final String title;
  final ExecutionActionStatus status;
  final ExecutionPriority priority;
  final DateTime? dueAt;
  final DateTime? scheduledFor;
  final String? planId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool isDue(DateTime now) {
    final due = dueAt;
    return due != null && !due.toUtc().isAfter(now.toUtc());
  }

  int focusScore(DateTime now) {
    var score = 0;
    if (status == ExecutionActionStatus.blocked) score += 100;
    if (isDue(now)) {
      final overdueDays = now.toUtc().difference(dueAt!.toUtc()).inDays;
      score += 80 + overdueDays.clamp(0, 30);
    }
    if (priority == ExecutionPriority.high) score += 50;
    if (status == ExecutionActionStatus.doing) score += 35;
    if (scheduledFor != null && !_isAfterLocalDay(scheduledFor!, now)) {
      score += 25;
    }
    return score;
  }
}

class ExecutionReviewRef {
  const ExecutionReviewRef({
    required this.id,
    this.title = '',
    this.targetDate,
  });

  final String id;
  final String title;
  final DateTime? targetDate;
}

class ExecutionReviewProgress {
  const ExecutionReviewProgress({
    required this.id,
    required this.createdAt,
    this.kind = ExecutionProgressKind.checkin,
    this.note = '',
    this.actionId,
    this.planId,
  });

  factory ExecutionReviewProgress.fromProgress(ExecutionProgressEntry entry) {
    return ExecutionReviewProgress(
      id: entry.id,
      createdAt: entry.createdAt,
      kind: entry.kind,
      note: entry.note,
      actionId: entry.actionId,
      planId: entry.planId,
    );
  }

  final String id;
  final DateTime createdAt;
  final ExecutionProgressKind kind;
  final String note;
  final String? actionId;
  final String? planId;
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
  final plans = _refsFromList(summary?['active_plans']);
  final progress = executionReviewProgressFromToolResult(summary);
  final closedActions = executionReviewClosedActionsFromToolResult(summary);
  final planCount = agentRuntimeIntOrNull(summary?['active_plan_count']);
  if (actions == null ||
      plans == null ||
      progress == null ||
      planCount == null) {
    return null;
  }
  return ExecutionReviewSnapshot(
    openActions: actions,
    activePlans: plans,
    recentProgress: progress,
    recentClosedActions: closedActions ?? const <ExecutionReviewAction>[],
    activePlanCount: planCount,
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
    final action = agentRuntimeObjectOrNull(raw);
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
        dueAt: agentRuntimeDateTimeOrNull(action?['due_at']),
        scheduledFor: agentRuntimeDateTimeOrNull(action?['scheduled_for']),
        planId: action?['plan_id'] as String?,
        createdAt: agentRuntimeDateTimeOrNull(action?['created_at']),
        updatedAt: agentRuntimeDateTimeOrNull(action?['updated_at']),
        completedAt: agentRuntimeDateTimeOrNull(action?['completed_at']),
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
    final entry = agentRuntimeObjectOrNull(raw);
    final id = entry?['id'];
    final createdAt = entry?['created_at'];
    if (id is! String || createdAt is! String) return null;
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return null;
    progress.add(ExecutionReviewProgress(id: id, createdAt: parsed.toUtc()));
    progress[progress.length - 1] = ExecutionReviewProgress(
      id: id,
      createdAt: parsed.toUtc(),
      kind: ExecutionProgressKind.parse(entry?['kind'] as String? ?? 'checkin'),
      note: entry?['note'] as String? ?? '',
      actionId: entry?['action_id'] as String?,
      planId: entry?['plan_id'] as String?,
    );
  }
  return progress;
}

List<ExecutionReviewRef>? _refsFromList(Object? value) {
  if (value is! List) return null;
  final refs = <ExecutionReviewRef>[];
  for (final raw in value) {
    final object = agentRuntimeObjectOrNull(raw);
    final id = object?['id'];
    if (id is! String) return null;
    refs.add(
      ExecutionReviewRef(
        id: id,
        title: object?['title'] as String? ?? '',
        targetDate: agentRuntimeDateTimeOrNull(object?['target_date']),
      ),
    );
  }
  return refs;
}

List<ExecutionReviewAction>? executionReviewClosedActionsFromToolResult(
  Map<String, Object?>? result,
) {
  final raw = result?['recent_closed_actions'];
  if (raw == null) return const <ExecutionReviewAction>[];
  if (raw is! List) return null;
  return executionReviewActionsFromToolResult(<String, Object?>{
    'actions': raw,
  });
}

bool _isAfterLocalDay(DateTime value, DateTime day) {
  final local = value.toLocal();
  final end = DateTime(day.year, day.month, day.day + 1);
  return !local.isBefore(end);
}
