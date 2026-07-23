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
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart'
    as llm_credentials;
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart'
    as ai_chat_providers;
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';

List<Override> agentRuntimeAppProviderOverrides() => <Override>[
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
      final contextBuilder = await ref.read(contextBuilderProvider.future);
      return prepareAppChatContextBlocks(
        contextBuilder: contextBuilder,
        activePacks: ref.read(activeDomainPacksProvider),
        aiContext: ref.read(aiContextProvider),
        request: request,
      );
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
