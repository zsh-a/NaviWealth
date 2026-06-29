import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

void main() {
  test('streams profile-backed FRB LLM events from request JSON', () async {
    final native = _FakeNativeBridge();
    final bridge = AgentRuntimeLlmBridge(
      bridge: native,
      profile: const LlmProfile(
        id: 'profile_1',
        name: 'Work gateway',
        provider: LlmProvider.openai,
        apiKey: 'sk-test',
        baseUrl: 'https://llm.example.test/v1',
        model: 'gpt-test',
      ),
    );
    final initCalls = <String?>[];
    final requestJsons = <String>[];
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: bridge,
      libraryPath: '/tmp/liblifeos_native.dylib',
      initRuntime: ({String? libraryPath}) async {
        initCalls.add(libraryPath);
      },
      streamProfileJson: ({required String requestJson}) {
        requestJsons.add(requestJson);
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"started","metadata":{"provider":"openai"}}',
          '{"kind":"delta","content":"Hello"}',
          '{"kind":"finished","response":{"content":"Hello","finish_reason":"stop"}}',
        ]);
      },
    );

    final events = await streamBridge
        .streamProfile(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'Hello'},
          ],
          tools: const <Map<String, Object?>>[
            <String, Object?>{
              'name': 'read_task',
              'description': 'Read a task',
              'input_schema': <String, Object?>{'type': 'object'},
            },
          ],
          temperature: 0,
          maxOutputTokens: 64,
          metadata: const <String, Object?>{'surface': 'ai_chat'},
        )
        .toList();

    expect(initCalls, <String?>['/tmp/liblifeos_native.dylib']);
    expect(events.map((event) => event['kind']), <String>[
      'started',
      'delta',
      'finished',
    ]);
    expect(events[1]['content'], 'Hello');

    final request = jsonDecode(requestJsons.single) as Map<String, Object?>;
    expect(request['protocol_version'], 'agent.v1');
    expect(request['surface'], 'ai_chat');
    expect(request['mode'], 'chat');
    expect(request['provider'], 'openai');
    expect(request['model'], 'gpt-test');
    expect(request['temperature'], 0);
    expect(request['max_output_tokens'], 64);
    expect(request['messages'], <Object?>[
      <String, Object?>{'role': 'user', 'content': 'Hello'},
    ]);
    expect(request['tools'], hasLength(1));
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['profile_id'], 'profile_1');
    expect(metadata['profile_name'], 'Work gateway');
    expect(metadata['base_url'], 'https://llm.example.test/v1');
    expect(metadata['api_key'], 'sk-test');
  });

  test('streams multimodal agent turns from request JSON', () async {
    final bridge = AgentRuntimeLlmBridge(
      bridge: _FakeNativeBridge(),
      profile: const LlmProfile(
        id: 'profile_2',
        name: 'Claude',
        provider: LlmProvider.anthropic,
        apiKey: 'sk-ant',
        model: 'claude-test',
      ),
    );
    final requestJsons = <String>[];
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: bridge,
      initRuntime: ({String? libraryPath}) async {},
      streamAgentTurnJson: ({required String requestJson}) {
        requestJsons.add(requestJson);
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"started","protocol_version":"agent.v1","turn_id":"turn_1","surface":"flutter_ai_chat"}',
          '{"kind":"delta","content":"The image shows a receipt."}',
        ]);
      },
    );

    final events = await streamBridge
        .streamAgentTurn(
          messages: const <Map<String, Object?>>[
            <String, Object?>{
              'role': 'user',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'What is in this image?',
                },
                <String, Object?>{
                  'type': 'image',
                  'mime_type': 'image/png',
                  'data': 'base64-image',
                },
              ],
            },
          ],
          metadata: const <String, Object?>{'source': 'composer'},
          turnId: 'turn_1',
          surface: 'flutter_ai_chat',
          agentId: 'assistant',
          mode: 'interactive',
        )
        .toList();

    expect(events.map((event) => event['kind']), <String>['started', 'delta']);
    expect(events[1]['content'], 'The image shows a receipt.');

    final request = jsonDecode(requestJsons.single) as Map<String, Object?>;
    expect(request['protocol_version'], 'agent.v1');
    expect(request['turn_id'], 'turn_1');
    expect(request['surface'], 'flutter_ai_chat');
    expect(request['agent_id'], 'assistant');
    expect(request['mode'], 'interactive');
    expect(request['provider'], 'anthropic');
    expect(request['model'], 'claude-test');

    final messages = request['messages'] as List<Object?>;
    final userMessage = messages.single as Map<String, Object?>;
    expect(userMessage['role'], 'user');
    final content = userMessage['content'] as List<Object?>;
    expect(content, hasLength(2));
    expect(content.first, <String, Object?>{
      'type': 'text',
      'text': 'What is in this image?',
    });
    expect(content.last, <String, Object?>{
      'type': 'image',
      'mime_type': 'image/png',
      'data': 'base64-image',
    });

    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['source'], 'composer');
    expect(metadata['profile_id'], 'profile_2');
    expect(metadata['profile_name'], 'Claude');
    expect(metadata['api_key'], 'sk-ant');
  });

  test('initializes the native runtime only once per stream bridge', () async {
    var initCalls = 0;
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: _FakeNativeBridge(),
        profile: const LlmProfile(
          id: 'profile_1',
          name: '',
          provider: LlmProvider.anthropic,
          apiKey: 'sk-ant',
        ),
      ),
      initRuntime: ({String? libraryPath}) async {
        initCalls += 1;
      },
      streamProfileJson: ({required String requestJson}) {
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"finished","response":{"content":"ok","finish_reason":"stop"}}',
        ]);
      },
    );

    await streamBridge
        .streamProfile(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'one'},
          ],
        )
        .drain<void>();
    await streamBridge
        .streamProfile(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'two'},
          ],
        )
        .drain<void>();

    expect(initCalls, 1);
  });

  test('rejects non-object FRB LLM stream events', () async {
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: _FakeNativeBridge(),
        profile: const LlmProfile(
          id: 'profile_1',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk-openai',
        ),
      ),
      initRuntime: ({String? libraryPath}) async {},
      streamProfileJson: ({required String requestJson}) {
        return Stream<String>.fromIterable(const <String>['["bad"]']);
      },
    );

    expect(
      streamBridge
          .streamProfile(
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'Hello'},
            ],
          )
          .toList,
      throwsA(isA<FormatException>()),
    );
  });
}

class _FakeNativeBridge implements AgentRuntimeNativeBridge {
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
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': 'profile response',
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    return const <String, Object?>{'status': 'completed'};
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
