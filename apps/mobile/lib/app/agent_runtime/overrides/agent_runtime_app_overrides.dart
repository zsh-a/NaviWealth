/// FRB-backed provider overrides for app-level AI integrations.
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/app/agent_runtime/bindings/agent_runtime_profile_turn_binding.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/app/agent_runtime/bridges/frb_llm_connectivity_probe.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_runner.dart';
import 'package:naviwealth/app/agent_runtime/context/app_chat_context_assembler.dart';
import 'package:naviwealth/app/agent_runtime/persistence/drift_agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/app/agents/daily_navigator_agent.dart';
import 'package:naviwealth/app/agents/daily_navigator_synthesizer.dart';
import 'package:naviwealth/app/agents/providers.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/composition/system_prompt_blocks.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart'
    as llm_credentials;
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/personal_profile/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart'
    as ai_chat_providers;
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';

List<Override> agentRuntimeAppProviderOverrides() => <Override>[
  dailyNavigatorAgentProvider.overrideWith((ref) {
    final runtime = agentRuntimeProfileTurnBinding(
      ref,
      agentId: kDailyNavigatorAgentId,
      domain: 'life',
      surface: 'life_daily_navigator',
      resolveAvailability: false,
    )!;
    return DailyNavigatorAgent(
      synthesizer: FrbDailyNavigatorSynthesizer(runtime: runtime),
    );
  }),
  agentRuntimeProfileTurnRunnerProvider.overrideWith(
    buildAgentRuntimeProfileTurnRunner,
  ),
  agentRuntimeProfileTurnTraceRecorderFactoryProvider.overrideWith((ref) {
    final recorder = ref.read(agentRuntimeTraceRecorderProvider);
    return ({required agentId, required domain, required surface}) {
      return recorder.profileTurnRecorder(
        agentId: agentId,
        domain: domain,
        surface: surface,
      );
    };
  }),
  llm_credentials.llmConnectivityProbeProvider.overrideWith(
    (ref) => FrbLlmConnectivityProbe(
      bridge: ref.watch(agentRuntimeNativeBridgeProvider),
    ),
  ),
  ai_chat_providers.chatAgentProvider.overrideWith((ref) {
    final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
    final streamBridge = ref.watch(agentRuntimeLlmStreamBridgeProvider);
    if (llmBridge == null || streamBridge == null) return null;

    final toolHost = ref.watch(agentRuntimeToolHostProvider);
    return FrbChatRunner.lazyTools(
      streamBridge: streamBridge,
      toolsReader: () => [
        for (final tool in ref.read(agentRuntimeCatalogProvider).tools)
          tool.toJson(),
      ],
      toolLineHandler: toolHost.handleLine,
      snapshotStore: DriftAgentRuntimeChatSnapshotStore(
        databaseReader: () => ref.read(appDatabaseProvider.future),
        ownerUserIdReader: ref.watch(currentUserIdProvider),
      ),
    );
  }),
  ai_chat_providers.chatContextBlockPrepProvider.overrideWith((ref) {
    return (request) async {
      // Keep the trusted system instructions independent from retrieval. A
      // local index/embedder failure must not silently remove the active OS
      // rules from the Chat request.
      final systemInstructions = buildAppChatSystemInstructionBlock(
        systemPrompt: ref.read(assembledSystemPromptProvider),
        now: DateTime.now().toUtc(),
      );
      try {
        final contextBuilder = await ref.read(contextBuilderProvider.future);
        final profileBuilder = await ref.read(
          personalProfileSnapshotBuilderProvider.future,
        );
        final blocks = await prepareAppChatContextBlocks(
          contextBuilder: contextBuilder,
          accessPolicy: ref.read(memoryAccessPolicyProvider),
          profileBuilder: profileBuilder,
          activeDomainScopes: ref.read(
            activePersonalProfileDomainScopesProvider,
          ),
          aiContext: ref.read(aiContextProvider),
          request: request,
        );
        return List<AgentRuntimeContextBlock>.unmodifiable([
          systemInstructions,
          ...blocks,
        ]);
      } catch (_) {
        return <AgentRuntimeContextBlock>[systemInstructions];
      }
    };
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
];
