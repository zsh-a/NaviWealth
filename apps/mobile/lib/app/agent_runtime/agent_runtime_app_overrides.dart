/// FRB-backed provider overrides for app-level AI integrations.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import '../../core/ai/llm_credentials/providers.dart' as llm_credentials;
import '../../features/activity/data/activity_entry_insight_client.dart';
import '../../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../../features/ingest/data/ingest_llm_client.dart';
import '../../features/knowledge/data/knowledge_llm_client.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';
import 'agent_runtime_native_bridge.dart';
import 'agent_runtime_profile_completion_clients.dart';
import 'agent_runtime_tool_host.dart';
import 'agent_runtime_trace_recorder.dart';
import 'frb_chat_runner.dart';
import 'frb_llm_connectivity_probe.dart';

List<Override> agentRuntimeAppProviderOverrides() => <Override>[
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
];
