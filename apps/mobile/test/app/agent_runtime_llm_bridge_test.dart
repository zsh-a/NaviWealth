import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';

void main() {
  test('buildRequest maps LlmProfile to agent-llm request shape', () {
    final bridge = AgentRuntimeLlmBridge(
      bridge: _FakeNativeBridge(),
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

  test('completeMock sends request through native bridge', () async {
    final native = _FakeNativeBridge();
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
      final native = _FakeNativeBridge();
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
    final native = _FakeNativeBridge();
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
}

class _FakeCredentialsNotifier extends LlmCredentialsNotifier {
  _FakeCredentialsNotifier(this._credentials);

  final LlmCredentials _credentials;

  @override
  Future<LlmCredentials?> fetch() async => _credentials;
}

class _FakeNativeBridge implements AgentRuntimeNativeBridge {
  final llmRequests = <Map<String, Object?>>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    llmRequests.add(request);
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    llmRequests.add(request);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'mock': true},
    };
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    llmRequests.add(request);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': 'profile response',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    };
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    final response = await completeProfileLlm(request: llmRequest);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': response,
      'step': <String, Object?>{
        'protocol_version': 'agent.v1',
        'agent_id': agentId,
        'status': 'completed',
        'output': <String, Object?>{'content': response['content']},
      },
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    return const <String, Object?>{'status': 'completed'};
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    return previousStep;
  }
}
