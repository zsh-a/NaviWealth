import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_storage_policy.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';

import 'agent_runtime_native_bridge_test_harness.dart';

void main() {
  test('streams profile-backed FRB chat-turn events from request JSON', () async {
    final native = FakeAgentRuntimeNativeBridge();
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
      streamChatTurnJson: ({required String requestJson}) {
        requestJsons.add(requestJson);
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"started","metadata":{"provider":"openai"}}',
          '{"kind":"delta","content":"Hello"}',
          '{"kind":"finished","response":{"content":"Hello","finish_reason":"stop"}}',
        ]);
      },
    );

    final events = await streamBridge
        .streamChatTurn(
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
          contextBlocks: const <Map<String, Object?>>[
            <String, Object?>{
              'block_id': 'memory_1',
              'kind': 'memory',
              'source': 'test.memory',
              'priority': 80,
              'token_estimate': 0,
              'content_hash': 'host:test',
              'content': <String, Object?>{
                'statement': 'User prefers concise answers',
              },
              'metadata': <String, Object?>{'trusted_as_instruction': false},
            },
          ],
          contextPolicy: const <String, Object?>{
            'max_input_tokens': 32000,
            'reserve_output_tokens': 2048,
            'preserve_recent_messages': 8,
            'compact_when_over_budget': true,
          },
          temperature: 0,
          maxOutputTokens: 64,
          metadata: const <String, Object?>{
            'surface': 'ai_chat',
            'session_id': 'session_1',
            'thread_id': 'thread_1',
          },
          sessionId: 'session_1',
          threadId: 'thread_1',
          surface: 'ai_chat',
          mode: 'chat',
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
    expect(request['session_id'], 'session_1');
    expect(request['thread_id'], 'thread_1');
    expect(request['mode'], 'chat');
    expect(request['provider'], 'openai');
    expect(request['model'], 'gpt-test');
    expect(request['temperature'], 0);
    expect(request['max_output_tokens'], 64);
    expect(request['messages'], <Object?>[
      <String, Object?>{'role': 'user', 'content': 'Hello'},
    ]);
    expect(request['tools'], hasLength(1));
    expect(request['context_blocks'], hasLength(1));
    final contextBlocks = request['context_blocks'] as List<Object?>;
    final memoryBlock = contextBlocks.single as Map<String, Object?>;
    expect(memoryBlock['kind'], 'memory');
    expect(memoryBlock['source'], 'test.memory');
    expect(request['context_policy'], <String, Object?>{
      'max_input_tokens': 32000,
      'reserve_output_tokens': 2048,
      'preserve_recent_messages': 8,
      'compact_when_over_budget': true,
    });
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['profile_id'], 'profile_1');
    expect(metadata['profile_name'], 'Work gateway');
    expect(metadata['base_url'], 'https://llm.example.test/v1');
    expect(metadata['api_key'], 'sk-test');
  });

  test('streams multimodal chat turns from request JSON', () async {
    final bridge = AgentRuntimeLlmBridge(
      bridge: FakeAgentRuntimeNativeBridge(),
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
      streamChatTurnJson: ({required String requestJson}) {
        requestJsons.add(requestJson);
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"started","protocol_version":"agent.v1","turn_id":"turn_1","surface":"flutter_ai_chat"}',
          '{"kind":"delta","content":"The image shows a receipt."}',
        ]);
      },
    );

    final events = await streamBridge
        .streamChatTurn(
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
          sessionId: 'session_2',
          threadId: 'thread_2',
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
    expect(request['session_id'], 'session_2');
    expect(request['thread_id'], 'thread_2');
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

  test('forwards interaction response with resumable chat state', () async {
    final requestJsons = <String>[];
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: FakeAgentRuntimeNativeBridge(),
        profile: const LlmProfile(
          id: 'profile_1',
          name: 'Local',
          provider: LlmProvider.anthropic,
          apiKey: 'sk-ant',
          model: 'claude-test',
        ),
      ),
      initRuntime: ({String? libraryPath}) async {},
      streamChatTurnJson: ({required String requestJson}) {
        requestJsons.add(requestJson);
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"done","metadata":{"stop_reason":"end_turn"}}',
        ]);
      },
    );

    await streamBridge
        .streamChatTurn(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'resume'},
          ],
          chatState: const <String, Object?>{
            'protocol_version': 'agent.v1',
            'pending_interaction': <String, Object?>{
              'interaction_id': 'interaction_1',
            },
          },
          interactionResponse: const <String, Object?>{
            'protocol_version': 'agent.v1',
            'interaction_id': 'interaction_1',
            'action': 'submit',
            'value': <String, Object?>{'option_id': 'safe'},
            'responded_at': '2026-07-23T10:01:00Z',
            'metadata': <String, Object?>{},
          },
        )
        .toList();

    final request = jsonDecode(requestJsons.single) as Map<String, Object?>;
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['chat_state'], isA<Map<String, Object?>>());
    expect(
      (metadata['interaction_response']
          as Map<String, Object?>)['interaction_id'],
      'interaction_1',
    );
    expect(metadata, isNot(contains('tool_results')));
  });

  test('initializes the native runtime only once per stream bridge', () async {
    var initCalls = 0;
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: FakeAgentRuntimeNativeBridge(),
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
      streamChatTurnJson: ({required String requestJson}) {
        return Stream<String>.fromIterable(const <String>[
          '{"kind":"finished","response":{"content":"ok","finish_reason":"stop"}}',
        ]);
      },
    );

    await streamBridge
        .streamChatTurn(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'one'},
          ],
        )
        .drain<void>();
    await streamBridge
        .streamChatTurn(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'two'},
          ],
        )
        .drain<void>();

    expect(initCalls, 1);
  });

  test('rejects runtime-owned SQLite policy before streaming', () async {
    var initCalls = 0;
    var streamCalls = 0;
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: FakeAgentRuntimeNativeBridge(),
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
      storagePolicy: const AgentRuntimeStoragePolicy.runtimeOwnedSqliteDebug(
        storePath: '/tmp/runtime.sqlite',
      ),
      streamChatTurnJson: ({required String requestJson}) {
        streamCalls += 1;
        return Stream<String>.fromIterable(const <String>[]);
      },
    );

    await expectLater(
      streamBridge
          .streamChatTurn(
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'Hello'},
            ],
          )
          .drain<void>(),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('app-owned Drift persistence'),
        ),
      ),
    );
    expect(initCalls, 0);
    expect(streamCalls, 0);
  });

  test('rejects non-object FRB LLM stream events', () async {
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: FakeAgentRuntimeNativeBridge(),
        profile: const LlmProfile(
          id: 'profile_1',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk-openai',
        ),
      ),
      initRuntime: ({String? libraryPath}) async {},
      streamChatTurnJson: ({required String requestJson}) {
        return Stream<String>.fromIterable(const <String>['["bad"]']);
      },
    );

    expect(
      streamBridge
          .streamChatTurn(
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'Hello'},
            ],
          )
          .toList,
      throwsA(isA<FormatException>()),
    );
  });

  test('maps FRB stream source errors into error events', () async {
    final streamBridge = AgentRuntimeLlmStreamBridge(
      llmBridge: AgentRuntimeLlmBridge(
        bridge: FakeAgentRuntimeNativeBridge(),
        profile: const LlmProfile(
          id: 'profile_1',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk-openai',
        ),
      ),
      initRuntime: ({String? libraryPath}) async {},
      streamChatTurnJson: ({required String requestJson}) {
        return Stream<String>.error(StateError('404 page not found'));
      },
    );

    final events = await streamBridge
        .streamChatTurn(
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'Hello'},
          ],
        )
        .toList();

    expect(events, hasLength(1));
    expect(events.single['kind'], 'error');
    final metadata = events.single['metadata'] as Map<String, Object?>;
    expect(metadata['code'], 'frb_llm_stream_error');
    expect(metadata['message'], contains('404 page not found'));
    expect(metadata['retryable'], false);
  });
}
