import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_profile_completion_clients.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_runner.dart';
import 'package:naviwealth/app/agent_runtime/overrides/agent_runtime_provider_overrides.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/app/agents/daily_navigator_agent.dart';
import 'package:naviwealth/app/agents/daily_navigator_synthesizer.dart';
import 'package:naviwealth/app/agents/providers.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/notifications/notification_preferences.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart'
    as ai_chat_providers;
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_llm_client.dart';
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_runtime_effect_plan_test_harness.dart';

void main() {
  test('app runtime overrides and DomainPack provider overrides wire FRB integrations', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedBoolPreferenceController.notificationsEnabledKey: false,
    });
    final prefs = await SharedPreferences.getInstance();
    final native = FakeAgentRuntimeEffectPlanBridge();
    final llmBridge = _llmBridge(native);
    final toolHost = AgentRuntimeToolHost(dispatcher: const _NoopDispatcher());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        agentRuntimeCatalogProvider.overrideWithValue(_catalog()),
        agentRuntimeNativeBridgeProvider.overrideWithValue(native),
        agentRuntimeLlmBridgeProvider.overrideWithValue(llmBridge),
        agentRuntimeLlmStreamBridgeProvider.overrideWithValue(
          AgentRuntimeLlmStreamBridge(
            llmBridge: llmBridge,
            initRuntime: ({String? libraryPath}) async {},
            streamChatTurnJson: ({required String requestJson}) =>
                const Stream<String>.empty(),
          ),
        ),
        agentRuntimeToolHostProvider.overrideWithValue(toolHost),
        agentRuntimeNativeStepRunnerProvider.overrideWithValue(
          AgentRuntimeNativeStepRunner(bridge: native, toolHost: toolHost),
        ),
        agentRuntimeTraceRecorderProvider.overrideWithValue(
          AgentRuntimeTraceRecorder(appendTrace: (_) async {}),
        ),
        ..._runtimeOverridesWithDomains([
          kHealthPack,
          kKnowledgePack,
          kExecutionPack,
        ]),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(ai_chat_providers.chatAgentProvider),
      isA<FrbChatRunner>(),
    );
    expect(
      container.read(activityEntryInsightClientProvider),
      isA<FrbActivityEntryInsightClient>(),
    );
    expect(
      container.read(ingestLlmProfileClientProvider),
      isA<FrbIngestLlmProfileClient>(),
    );

    expect(
      container.read(dailyNavigatorAgentProvider),
      isA<DailyNavigatorAgent>().having(
        (agent) => agent.synthesizer,
        'synthesizer',
        isA<FrbDailyNavigatorSynthesizer>(),
      ),
    );
    expect(
      container.read(execution_agent_providers.executionReviewAgentProvider),
      isA<ExecutionReviewAgent>().having(
        (agent) => agent.reviewReader,
        'reviewReader',
        isA<FrbExecutionReviewReader>(),
      ),
    );
    expect(
      container.read(recoveryAlertAgentProvider),
      isA<RecoveryAlertAgent>().having(
        (agent) => agent.signalReader,
        'signalReader',
        isA<FrbRecoveryAlertSignalReader>(),
      ),
    );
    expect(
      container.read(weeklySummaryAgentProvider),
      isA<WeeklySummaryAgent>().having(
        (agent) => agent.summaryReader,
        'summaryReader',
        isA<FrbWeeklySummaryReader>(),
      ),
    );
  });

  test(
    'agent runtime catalog excludes domains without background agents',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedBoolPreferenceController.notificationsEnabledKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final native = FakeAgentRuntimeEffectPlanBridge();
      final llmBridge = _llmBridge(native);
      final toolHost = AgentRuntimeToolHost(
        dispatcher: const _NoopDispatcher(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeDomainPacksProvider.overrideWith(
            (ref) => [kHealthPack, kKnowledgePack],
          ),
          agentRegistrationProvider.overrideWith(
            (ref) => domainAgentRegistrations(
              ref,
              ref.watch(activeDomainPacksProvider),
            ),
          ),
          agentRuntimeNativeBridgeProvider.overrideWithValue(native),
          agentRuntimeLlmBridgeProvider.overrideWithValue(llmBridge),
          agentRuntimeToolHostProvider.overrideWithValue(toolHost),
          agentRuntimeNativeStepRunnerProvider.overrideWithValue(
            AgentRuntimeNativeStepRunner(bridge: native, toolHost: toolHost),
          ),
          agentRuntimeTraceRecorderProvider.overrideWithValue(
            AgentRuntimeTraceRecorder(appendTrace: (_) async {}),
          ),
          ..._runtimeOverridesWithDomains([kHealthPack, kKnowledgePack]),
        ],
      );
      addTearDown(container.dispose);

      final catalog = container.read(agentRuntimeCatalogProvider);

      expect(catalog.activeDomains, ['health', 'knowledge']);
      expect(
        catalog.agents.map((agent) => agent.id),
        containsAll(<String>['recovery_alert']),
      );
    },
  );

  test(
    'agent runtime catalog does not construct FRB execution providers',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedBoolPreferenceController.notificationsEnabledKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeDomainPacksProvider.overrideWith(
            (ref) => [kHealthPack, kKnowledgePack, kExecutionPack],
          ),
          agentRegistrationProvider.overrideWith(
            (ref) => domainAgentRegistrations(
              ref,
              ref.watch(activeDomainPacksProvider),
            ),
          ),
          agentRuntimeNativeStepRunnerProvider.overrideWith((ref) {
            throw StateError('step runner should be read lazily');
          }),
          agentRuntimeTraceRecorderProvider.overrideWithValue(
            AgentRuntimeTraceRecorder(appendTrace: (_) async {}),
          ),
          ..._runtimeOverridesWithDomains([
            kHealthPack,
            kKnowledgePack,
            kExecutionPack,
          ]),
        ],
      );
      addTearDown(container.dispose);

      final catalog = container.read(agentRuntimeCatalogProvider);

      expect(catalog.activeDomains, ['health', 'knowledge', 'execution']);
      expect(
        catalog.agents.map((agent) => agent.id),
        containsAll(<String>['recovery_alert', 'execution_review']),
      );
    },
  );

  test('chat runner construction does not read the runtime catalog', () async {
    final native = FakeAgentRuntimeEffectPlanBridge();
    final llmBridge = _llmBridge(native);
    final container = ProviderContainer(
      overrides: [
        agentRuntimeCatalogProvider.overrideWith((ref) {
          throw StateError('catalog should be read lazily');
        }),
        agentRuntimeLlmBridgeProvider.overrideWithValue(llmBridge),
        agentRuntimeLlmStreamBridgeProvider.overrideWithValue(
          AgentRuntimeLlmStreamBridge(
            llmBridge: llmBridge,
            initRuntime: ({String? libraryPath}) async {},
            streamChatTurnJson: ({required String requestJson}) =>
                const Stream<String>.empty(),
          ),
        ),
        agentRuntimeToolHostProvider.overrideWithValue(
          AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
        ),
        ...agentRuntimeProviderOverrides(),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(ai_chat_providers.chatAgentProvider),
      isA<FrbChatRunner>(),
    );
  });
}

AgentRuntimeLlmBridge _llmBridge(AgentRuntimeNativeBridge native) {
  return AgentRuntimeLlmBridge(
    bridge: native,
    profile: const LlmProfile(
      id: 'profile_1',
      name: 'Local profile',
      provider: LlmProvider.openai,
      apiKey: 'sk-test',
      model: 'gpt-test',
    ),
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['execution', 'health', 'knowledge'],
    agents: const <AgentRuntimeAgentSpec>[],
    tools: const <AgentRuntimeToolSpec>[],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

List<Override> _runtimeOverridesWithDomains(List<DomainPack> packs) => [
  ...agentRuntimeProviderOverrides(),
  ...domainProviderOverrides(packs),
];

class _NoopDispatcher implements DeviceToolDispatcher {
  const _NoopDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    return const <String, Object?>{};
  }
}
