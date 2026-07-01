/// Production provider overrides that route app AI surfaces through FRB-backed
/// agent-runtime integrations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../core/ai/llm_credentials/providers.dart' as llm_credentials;
import '../../core/notifications/notification_preferences.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/providers.dart' as notif_providers;
import '../../features/activity/data/activity_entry_insight_client.dart';
import '../../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../../features/execution/agents/providers.dart'
    as execution_agent_providers;
import '../../features/execution/agents/review_agent.dart';
import '../../features/health/agents/briefing_synthesizer.dart';
import '../../features/health/agents/morning_briefing_agent.dart';
import '../../features/health/agents/recovery_alert_agent.dart';
import '../../features/health/agents/weekly_summary_agent.dart';
import '../../features/health/data/morning_briefing_preferences.dart';
import '../../features/ingest/data/ingest_llm_client.dart';
import '../../features/knowledge/agents/assumption_agent.dart';
import '../../features/knowledge/agents/contradiction_agent.dart';
import '../../features/knowledge/agents/inbox_triage_agent.dart';
import '../../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../../features/knowledge/agents/review_agent.dart';
import '../../features/knowledge/agents/routine_due_agent.dart';
import '../../features/knowledge/data/knowledge_llm_client.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';
import 'agent_runtime_native_bridge.dart';
import 'agent_runtime_profile_completion_clients.dart';
import 'agent_runtime_profile_turn_binding.dart';
import 'agent_runtime_tool_host.dart';
import 'agent_runtime_tool_plan_binding.dart';
import 'agent_runtime_trace_recorder.dart';
import 'frb_chat_runner.dart';
import 'frb_llm_connectivity_probe.dart';

List<Override> agentRuntimeProviderOverrides() => <Override>[
  llm_credentials.llmConnectivityProbeProvider.overrideWith(
    (ref) => FrbLlmConnectivityProbe(
      bridge: ref.watch(agentRuntimeNativeBridgeProvider),
    ),
  ),
  ai_chat_providers.chatAgentProvider.overrideWith((ref) {
    final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
    final streamBridge = ref.watch(agentRuntimeLlmStreamBridgeProvider);
    if (llmBridge == null || streamBridge == null) return null;

    final catalog = ref.watch(agentRuntimeCatalogProvider);
    final toolHost = ref.watch(agentRuntimeToolHostProvider);
    return FrbChatRunner(
      streamBridge: streamBridge,
      tools: [for (final tool in catalog.tools) tool.toJson()],
      toolLineHandler: toolHost.handleLine,
    );
  }),
  activityEntryInsightClientProvider.overrideWith((ref) {
    final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
    return llmBridge == null
        ? null
        : FrbActivityEntryInsightClient(
            llmBridge: llmBridge,
            recordTrace: ref
                .read(agentRuntimeTraceRecorderProvider)
                .recordProfileCompletion,
          );
  }),
  knowledgeLlmProfileClientProvider.overrideWith((ref) {
    final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
    return llmBridge == null
        ? null
        : FrbKnowledgeLlmProfileClient(
            llmBridge: llmBridge,
            recordTrace: ref
                .read(agentRuntimeTraceRecorderProvider)
                .recordProfileCompletion,
          );
  }),
  ingestLlmProfileClientProvider.overrideWith((ref) {
    final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
    return llmBridge == null
        ? null
        : FrbIngestLlmProfileClient(
            llmBridge: llmBridge,
            recordTrace: ref
                .read(agentRuntimeTraceRecorderProvider)
                .recordProfileCompletion,
          );
  }),
  execution_agent_providers.executionReviewAgentProvider.overrideWith((ref) {
    return ExecutionReviewAgent(
      reviewReader: FrbExecutionReviewReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kExecutionReviewAgentId,
          domain: 'execution',
          surface: 'execution_review',
        ),
      ),
    );
  }),
  morningBriefingAgentProvider.overrideWith((ref) {
    final frbRuntime = agentRuntimeProfileTurnBinding(
      ref,
      agentId: 'morning_briefing',
      domain: 'health',
      surface: 'health_morning_briefing',
    );
    final notifier = _briefingNotificationService(ref);
    final synth = frbRuntime == null
        ? const ProgrammaticBriefingSynthesizer()
        : FrbBriefingSynthesizer(
            runtime: frbRuntime,
            fallback: const ProgrammaticBriefingSynthesizer(),
          );
    return MorningBriefingAgent(
      synthesizer: synth,
      notifier: notifier,
      hourLocal: ref.watch(morningBriefingHourProvider),
    );
  }),
  recoveryAlertAgentProvider.overrideWith((ref) {
    return RecoveryAlertAgent(
      notifier: _briefingNotificationService(ref),
      signalReader: FrbRecoveryAlertSignalReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kRecoveryAlertAgentId,
          domain: 'health',
          surface: 'health_recovery_alert',
        ),
      ),
    );
  }),
  weeklySummaryAgentProvider.overrideWith((ref) {
    return WeeklySummaryAgent(
      summaryReader: FrbWeeklySummaryReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kWeeklySummaryAgentId,
          domain: 'health',
          surface: 'health_weekly_summary',
        ),
      ),
    );
  }),
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

NotificationService? _briefingNotificationService(Ref ref) {
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  final briefingNotificationsEnabled = ref.watch(
    healthBriefingNotificationsEnabledProvider,
  );
  return notificationsEnabled && briefingNotificationsEnabled
      ? ref.watch(notif_providers.notificationServiceProvider)
      : null;
}
