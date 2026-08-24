import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart'
    show kDefaultLlmMaxOutputTokens;

import 'agent_runtime_native_bridge_test_harness.dart';

void main() {
  test('buildRequest maps LlmProfile to agent-llm request shape', () {
    final bridge = AgentRuntimeLlmBridge(
      bridge: FakeAgentRuntimeNativeBridge(),
      profile: const LlmProfile(
        id: 'profile_1',
        name: 'Work gateway',
        provider: LlmProvider.openai,
        apiKey: 'sk-test',
        baseUrl: 'https://llm.example.test/v1',
        model: 'custom-model',
      ),
    );

    final request = bridge.buildRequest(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'Summarize'},
      ],
      temperature: 0,
      maxOutputTokens: 128,
      metadata: const <String, Object?>{'trace_id': 'trace_1'},
    );

    expect(request['protocol_version'], 'agent.v1');
    expect(request['provider'], 'openai');
    expect(request['model'], 'custom-model');
    expect(request['temperature'], 0);
    expect(request['max_output_tokens'], 128);
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['profile_id'], 'profile_1');
    expect(metadata['profile_name'], 'Work gateway');
    expect(metadata['base_url'], 'https://llm.example.test/v1');
    expect(metadata['api_key'], 'sk-test');
    expect(metadata['trace_id'], 'trace_1');
  });

  test('buildRequest always applies the shared default output budget', () {
    final bridge = AgentRuntimeLlmBridge(
      bridge: FakeAgentRuntimeNativeBridge(),
      profile: const LlmProfile(
        id: 'profile_1',
        name: '',
        provider: LlmProvider.anthropic,
        apiKey: 'sk-ant',
      ),
    );

    final request = bridge.buildRequest(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'Explain'},
      ],
    );

    expect(request['max_output_tokens'], kDefaultLlmMaxOutputTokens);
  });

  test('buildRequest rejects a non-positive output budget', () {
    final bridge = AgentRuntimeLlmBridge(
      bridge: FakeAgentRuntimeNativeBridge(),
      profile: const LlmProfile(
        id: 'profile_1',
        name: '',
        provider: LlmProvider.openai,
        apiKey: 'sk-openai',
      ),
    );

    expect(
      () => bridge.buildRequest(
        messages: const <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': 'Explain'},
        ],
        maxOutputTokens: 0,
      ),
      throwsRangeError,
    );
  });

  test('completeMock sends request through native bridge', () async {
    final native = FakeAgentRuntimeNativeBridge();
    final bridge = AgentRuntimeLlmBridge(
      bridge: native,
      profile: const LlmProfile(
        id: 'profile_1',
        name: '',
        provider: LlmProvider.anthropic,
        apiKey: 'sk-ant',
      ),
    );

    final response = await bridge.completeMock(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'Ping'},
      ],
      responseText: 'Pong',
    );

    expect(response['content'], 'Pong');
    expect(native.llmRequests.single['provider'], 'anthropic');
    expect(native.llmRequests.single['model'], 'claude-sonnet-4-5');
  });

  test(
    'completeProfile sends active profile request through native bridge',
    () async {
      final native = FakeAgentRuntimeNativeBridge();
      final bridge = AgentRuntimeLlmBridge(
        bridge: native,
        profile: const LlmProfile(
          id: 'profile_1',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk-openai',
        ),
      );

      final response = await bridge.completeProfile(
        messages: const <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': 'Ping'},
        ],
      );

      expect(response['content'], 'profile response');
      expect(native.llmRequests.single['provider'], 'openai');
      expect(
        (native.llmRequests.single['metadata']
            as Map<String, Object?>)['api_key'],
        'sk-openai',
      );
    },
  );

  test('provider returns bridge for active usable profile', () async {
    final native = FakeAgentRuntimeNativeBridge();
    final container = ProviderContainer(
      overrides: [
        agentRuntimeNativeBridgeProvider.overrideWithValue(native),
        llmCredentialsProvider.overrideWith(
          () => _FakeCredentialsNotifier(
            const LlmCredentials(
              profiles: <LlmProfile>[
                LlmProfile(
                  id: 'profile_1',
                  name: '',
                  provider: LlmProvider.openai,
                  apiKey: 'sk-openai',
                ),
              ],
              activeId: 'profile_1',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(llmCredentialsProvider.future);
    final bridge = container.read(agentRuntimeLlmBridgeProvider);

    expect(bridge, isNotNull);
    final request = await bridge!.validateRequest(
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'Hello'},
      ],
    );
    expect(request['provider'], 'openai');
    expect(request['model'], 'gpt-5-mini');
  });

  test('provider returns null when active profile has no key', () {
    final container = ProviderContainer(
      overrides: [
        llmCredentialsProvider.overrideWith(
          () => _FakeCredentialsNotifier(
            const LlmCredentials(
              profiles: <LlmProfile>[
                LlmProfile(
                  id: 'profile_1',
                  name: '',
                  provider: LlmProvider.openai,
                  apiKey: '',
                ),
              ],
              activeId: 'profile_1',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(agentRuntimeLlmBridgeProvider), isNull);
  });

  test('provider returns null when platform does not support device LLM', () {
    final container = ProviderContainer(
      overrides: [
        deviceLlmPlatformSupportedProvider.overrideWithValue(false),
        llmCredentialsProvider.overrideWith(
          () => _FakeCredentialsNotifier(
            const LlmCredentials(
              profiles: <LlmProfile>[
                LlmProfile(
                  id: 'profile_1',
                  name: '',
                  provider: LlmProvider.openai,
                  apiKey: 'sk-openai',
                ),
              ],
              activeId: 'profile_1',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(agentRuntimeLlmBridgeProvider), isNull);
  });
}

class _FakeCredentialsNotifier extends LlmCredentialsNotifier {
  _FakeCredentialsNotifier(this._credentials);

  final LlmCredentials _credentials;

  @override
  Future<LlmCredentials?> fetch() async => _credentials;
}
