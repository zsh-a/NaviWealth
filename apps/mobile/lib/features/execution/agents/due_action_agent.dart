import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';

const String kExecutionDueActionAgentId = 'execution_due_actions';

class ExecutionDueActionAgent implements Agent {
  const ExecutionDueActionAgent();

  @override
  String get id => kExecutionDueActionAgentId;

  @override
  String get name => 'Due Actions';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: 8);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final startedAt = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repository = await ctx.ref.read(executionRepositoryProvider.future);
    final l10n = agentL10n(ctx.ref);
    final cutoff = startedAt.add(const Duration(days: 1));
    final due = (await repository.listOpenActions(ownerUserId: ownerUserId))
        .where(
          (action) =>
              action.dueAt != null &&
              !action.dueAt!.toUtc().isAfter(cutoff.toUtc()),
        )
        .toList(growable: false);
    final finishedAt = DateTime.now().toUtc();
    if (due.isEmpty) {
      return AgentRunResult.skipped(
        agentId: id,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: l10n.executionDueAgentNothingDue,
      );
    }

    final summary = l10n.executionDueAgentSummary(due.length, due.first.title);
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final artifactId = '$id:$dayKey';
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      AgentArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        agentId: id,
        domain: 'execution',
        kind: AgentArtifactKind.reminder,
        severity: AgentArtifactSeverity.attention,
        title: l10n.executionDueAgentTitle,
        summary: summary,
        metrics: <AgentMetric>[
          AgentMetric(
            label: l10n.executionAgentReviewInsightDueTitle,
            value: due.length.toString(),
            severity: AgentArtifactSeverity.attention,
          ),
        ],
        insights: <AgentInsight>[
          AgentInsight(
            id: 'due_actions',
            title: l10n.executionAgentReviewInsightDueTitle,
            body: l10n.executionAgentReviewInsightDueBody(due.length),
            evidenceIds: due.map((action) => action.id).toList(growable: false),
            route: ExecutionRoutes.today,
          ),
        ],
        evidence: <AgentEvidenceRef>[
          for (final action in due.take(8))
            AgentEvidenceRef(
              type: 'execution_action',
              id: action.id,
              label: action.title,
              route: ExecutionRoutes.action(action.id),
            ),
        ],
        actions: <AgentAction>[
          AgentAction(
            kind: 'open_route',
            label: l10n.executionAgentReviewAction,
            route: ExecutionRoutes.today,
          ),
        ],
        methodology: localAgentMethodology(
          l10n,
          sourceLabel: l10n.executionDueAgentTitle,
        ),
        createdAt: finishedAt,
      ),
    );

    return AgentRunResult(
      agentId: id,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: summary,
      payload: <String, Object?>{
        'due_action_ids': due
            .map((action) => action.id)
            .toList(growable: false),
      },
      artifactId: artifactId,
    );
  }
}
