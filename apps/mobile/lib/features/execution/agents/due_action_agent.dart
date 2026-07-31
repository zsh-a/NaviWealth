import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/notifications/notification_service.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';

const String kExecutionDueActionAgentId = 'execution_due_actions';

const NotificationChannelSpec kExecutionDueNotificationChannel =
    NotificationChannelSpec(
      id: 'lifeos.execution.due',
      name: 'Execution Due Actions',
      description: 'ExecutionOS reminders for actions due soon.',
    );

class ExecutionDueActionAgent implements Agent {
  const ExecutionDueActionAgent({this.notifier});

  final NotificationService? notifier;

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
        createdAt: finishedAt,
      ),
    );

    final activeNotifier = notifier;
    if (activeNotifier != null) {
      final preferences = await ctx.ref.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final enabled = await preferences.areNotificationsEnabled(
        ownerUserId: ownerUserId,
        agentId: id,
      );
      if (enabled &&
          await activeNotifier.isAvailable() &&
          await activeNotifier.hasPermissions()) {
        await activeNotifier.showNow(
          id:
              0x20000000 +
              startedAt.year * 10000 +
              startedAt.month * 100 +
              startedAt.day,
          title: l10n.executionDueAgentTitle,
          body: summary,
          channel: kExecutionDueNotificationChannel,
          payload: AgentArtifactRoutes.detail(artifactId),
        );
      }
    }

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
