/// FRB-backed provider overrides for HealthOS agents.
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/core/ai/contracts/ai_domain.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';
import 'package:naviwealth/features/health/data/meal_recognition_client.dart';

List<Override> agentRuntimeHealthProviderOverrides() => <Override>[
  mealRecognitionClientProvider.overrideWith((ref) {
    final bridge = ref.watch(agentRuntimeLlmBridgeProvider);
    final profile = ref.watch(llmCredentialsProvider).value?.active;
    if (bridge == null || profile == null) return null;
    return FrbMealRecognitionClient(
      llmBridge: bridge,
      providerLabel:
          '${profile.displayName}${profile.model == null ? '' : ' · ${profile.model}'}',
      recordTrace: ref
          .read(agentRuntimeTraceRecorderProvider)
          .recordProfileCompletion,
    );
  }),
  recoveryAlertAgentProvider.overrideWith((ref) {
    return RecoveryAlertAgent(
      signalReader: FrbRecoveryAlertSignalReader(
        runtime: agentRuntimeEffectPlanBinding(
          ref,
          agentId: kRecoveryAlertAgentId,
          domain: const AiDomain.domain(DomainScope.health),
          surface: 'health_recovery_alert',
        ),
      ),
    );
  }),
  weeklySummaryAgentProvider.overrideWith((ref) {
    return WeeklySummaryAgent(
      summaryReader: FrbWeeklySummaryReader(
        runtime: agentRuntimeEffectPlanBinding(
          ref,
          agentId: kWeeklySummaryAgentId,
          domain: const AiDomain.domain(DomainScope.health),
          surface: 'health_weekly_summary',
        ),
      ),
    );
  }),
];
