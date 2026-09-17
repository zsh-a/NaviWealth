import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/agents/agent_l10n.dart';
import '../../core/ai/agents/agent_schedule.dart';
import '../../core/ai/agents/scheduled_agent_store.dart';
import '../../core/ai/agents/scheduled_agent_task.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import 'scheduled_llm_executor.dart';

List<DomainAgentRegistration> composeScheduledAgents(
  Ref ref,
  List<DomainAgentRegistration> registrations,
) {
  final tasks =
      ref.watch(scheduledAgentTasksProvider).value ??
      const <ScheduledAgentTask>[];
  final overrides = {for (final task in tasks) task.id: task};
  final l = agentL10n(ref);
  final result = <DomainAgentRegistration>[];
  for (final registration in registrations) {
    final agent = registration.agent;
    final builtin = switch (agent.id) {
      'weekly_wealth_review' => ScheduledAgentTask(
        id: agent.id,
        title: l.agentPresentationWeeklyWealthReviewLabel,
        instructions: l.scheduledWealthGoal,
        domain: DomainScope.finance,
        schedule: const AgentSchedule.weekly(
          weekday: DateTime.sunday,
          hour: 18,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        revision: 0, // Unsaved preset; first user override must insert.
      ),
      'weekly_summary' => ScheduledAgentTask(
        id: agent.id,
        title: l.agentPresentationWeeklySummaryLabel,
        instructions: l.scheduledHealthGoal,
        domain: DomainScope.health,
        schedule: const AgentSchedule.weekly(
          weekday: DateTime.sunday,
          hour: 20,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        revision: 0,
      ),
      _ => null,
    };
    result.add(
      builtin == null
          ? registration
          : DomainAgentRegistration(
              agent: ScheduledLlmAgent(
                overrides[agent.id] ?? builtin,
                executeScheduledLlmTask,
              ),
              domain: registration.domain,
            ),
    );
  }
  return result;
}
