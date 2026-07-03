/// FRB-backed provider overrides for KnowledgeOS agents.
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/notifications/notification_preferences.dart';
import 'package:naviwealth/core/notifications/providers.dart' as notif_providers;
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:naviwealth/features/knowledge/agents/contradiction_agent.dart';
import 'package:naviwealth/features/knowledge/agents/inbox_triage_agent.dart';
import 'package:naviwealth/features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';
import 'package:naviwealth/features/knowledge/agents/routine_due_agent.dart';

List<Override> agentRuntimeKnowledgeProviderOverrides() => <Override>[
  knowledge_agent_providers.reviewAgentProvider.overrideWith((ref) {
    return ReviewAgent(
      dueReader: FrbReviewDueReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kKnowledgeReviewAgentId,
          domain: 'knowledge',
          surface: 'knowledge_review',
        ),
      ),
    );
  }),
  knowledge_agent_providers.assumptionAgentProvider.overrideWith((ref) {
    return AssumptionAgent(
      assumptionReader: FrbAssumptionReviewReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kKnowledgeAssumptionAgentId,
          domain: 'knowledge',
          surface: 'knowledge_assumption',
        ),
      ),
    );
  }),
  knowledge_agent_providers.inboxTriageAgentProvider.overrideWith((ref) {
    return InboxTriageAgent(
      sourceReader: FrbInboxTriageSourceReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kKnowledgeInboxTriageAgentId,
          domain: 'knowledge',
          surface: 'knowledge_inbox_triage',
        ),
      ),
    );
  }),
  knowledge_agent_providers.contradictionAgentProvider.overrideWith((ref) {
    return ContradictionAgent(
      sourceReader: FrbContradictionSourceReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kKnowledgeContradictionAgentId,
          domain: 'knowledge',
          surface: 'knowledge_contradiction',
        ),
      ),
    );
  }),
  knowledge_agent_providers.routineDueAgentProvider.overrideWith((ref) {
    return RoutineDueAgent(
      notifier: ref.watch(notificationsEnabledProvider)
          ? ref.watch(notif_providers.notificationServiceProvider)
          : null,
      dueReader: FrbRoutineDueReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kKnowledgeRoutineAgentId,
          domain: 'knowledge',
          surface: 'knowledge_routine_due',
        ),
      ),
    );
  }),
];
