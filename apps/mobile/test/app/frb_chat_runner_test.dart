import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/frb_chat_runner.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';

void main() {
  test('maps FRB profile completion into chat events', () async {
    final bridge = _FakeLlmBridge(
      response: const <String, Object?>{
        'protocol_version': 'agent.v1',
        'provider': 'openai',
        'model': 'gpt-test',
        'content': 'FRB answer',
        'finish_reason': 'stop',
        'usage': <String, Object?>{
          'input_tokens': 7,
          'output_tokens': 3,
          'total_tokens': 10,
        },
      },
    );
    final runner = FrbChatRunner(llmBridge: bridge);

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Hello'),
          ],
          model: 'requested-model',
        )
        .toList();

    expect(events, hasLength(3));
    expect((events[0] as UsageEvent).usage.input, 7);
    expect((events[0] as UsageEvent).usage.output, 3);
    expect((events[1] as TextEvent).text, 'FRB answer');
    final done = events[2] as DoneEvent;
    expect(done.stopReason, 'end_turn');
    expect(done.rounds, 1);
    expect(bridge.messages.single, <String, Object?>{
      'role': 'user',
      'content': 'Hello',
    });
    expect(bridge.metadata['agent_id'], kFrbChatRunnerAgentId);
    expect(bridge.metadata['surface'], 'ai_chat');
    expect(bridge.metadata['requested_model'], 'requested-model');
    expect(bridge.metadata['streaming'], false);
  });

  test('maps FRB native stream events into chat events', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridge(
      bridge,
      events: const <String>[
        '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
        '{"kind":"thinking_delta","content":"reason","metadata":{"stream":true}}',
        '{"kind":"delta","content":"Hello ","metadata":{"synthetic_stream":true}}',
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_delta","tool_call_id":"call_1","tool_name":"read_task","partial_input_json":"{\\"","metadata":{"stream":true}}',
        '{"kind":"tool_call_delta","tool_call_id":"call_1","tool_name":"read_task","partial_input_json":"id\\":\\"task_1\\"}","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
        '{"kind":"delta","content":"from FRB","metadata":{"synthetic_stream":true}}',
        '{"kind":"finished","response":{"content":"Hello from FRB","finish_reason":"stop","usage":{"input_tokens":4,"output_tokens":3,"total_tokens":7}},"metadata":{"synthetic_stream":true}}',
      ],
    );
    final runner = FrbChatRunner(llmBridge: bridge, streamBridge: streamBridge);

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Hello'),
          ],
        )
        .toList();

    expect(events, hasLength(9));
    expect((events[0] as ThinkingDeltaEvent).text, 'reason');
    expect((events[1] as TextEvent).text, 'Hello ');
    expect((events[2] as ToolCallStartEvent).name, 'read_task');
    expect((events[3] as ToolCallDeltaEvent).partialInputJson, '{"');
    expect((events[4] as ToolCallDeltaEvent).partialInputJson, 'id":"task_1"}');
    final toolCall = events[5] as ToolCallEvent;
    expect(toolCall.id, 'call_1');
    expect(toolCall.input, <String, Object?>{'id': 'task_1'});
    expect((events[6] as TextEvent).text, 'from FRB');
    expect((events[7] as UsageEvent).usage.total, 7);
    expect((events[8] as DoneEvent).stopReason, 'end_turn');
    final request = streamBridge.requests.single;
    expect(request['messages'], <Object?>[
      <String, Object?>{'role': 'user', 'content': 'Hello'},
    ]);
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['streaming'], true);
  });

  test('maps FRB native stream error events into chat errors', () async {
    final runner = FrbChatRunner(
      llmBridge: _FakeLlmBridge(),
      streamBridge: _streamBridge(
        _FakeLlmBridge(),
        events: const <String>[
          '{"kind":"error","metadata":{"code":"provider_http_401","message":"bad key","retryable":false}}',
        ],
      ),
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Hello'),
          ],
        )
        .toList();

    expect(events, hasLength(2));
    expect((events[0] as ErrorEvent).code, 'provider_http_401');
    expect((events[0] as ErrorEvent).message, 'bad key');
    expect((events[1] as DoneEvent).stopReason, 'error');
  });

  test('maps native finish reasons to chat stop reasons', () async {
    final cases = <String, String>{
      'length': 'max_tokens',
      'tool_call': 'tool_use',
      'content_filter': 'refusal',
      'error': 'error',
    };

    for (final entry in cases.entries) {
      final runner = FrbChatRunner(
        llmBridge: _FakeLlmBridge(
          response: <String, Object?>{
            'content': '',
            'finish_reason': entry.key,
          },
        ),
      );

      final events = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect((events.single as DoneEvent).stopReason, entry.value);
    }
  });

  test(
    'emits existing chat error vocabulary when FRB completion fails',
    () async {
      final runner = FrbChatRunner(
        llmBridge: _FakeLlmBridge(error: StateError('native unavailable')),
      );

      final events = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect(events, hasLength(2));
      expect((events[0] as ErrorEvent).code, 'frb_chat_error');
      expect((events[1] as DoneEvent).stopReason, 'error');
    },
  );
}

_RecordingStreamBridge _streamBridge(
  _FakeLlmBridge bridge, {
  required List<String> events,
}) {
  return _RecordingStreamBridge(llmBridge: bridge, events: events);
}

class _RecordingStreamBridge extends AgentRuntimeLlmStreamBridge {
  factory _RecordingStreamBridge({
    required _FakeLlmBridge llmBridge,
    required List<String> events,
  }) {
    final requests = <Map<String, Object?>>[];
    return _RecordingStreamBridge._(
      llmBridge: llmBridge,
      events: events,
      requests: requests,
    );
  }

  _RecordingStreamBridge._({
    required _FakeLlmBridge llmBridge,
    required List<String> events,
    required this.requests,
  }) : super(
         llmBridge: llmBridge,
         initRuntime: ({String? libraryPath}) async {},
         streamProfileJson: ({required String requestJson}) {
           requests.add(jsonDecode(requestJson) as Map<String, Object?>);
           return Stream<String>.fromIterable(events);
         },
       );

  final List<Map<String, Object?>> requests;
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({
    this.response = const <String, Object?>{
      'content': 'ok',
      'finish_reason': 'stop',
    },
    this.error,
  });

  final Map<String, Object?> response;
  final Object? error;
  List<Map<String, Object?>> messages = const <Map<String, Object?>>[];
  Map<String, Object?> metadata = const <String, Object?>{};

  @override
  Map<String, Object?> buildRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'messages': messages,
      'tools': tools,
      'metadata': metadata,
    };
  }

  @override
  Future<Map<String, Object?>> completeMock({
    required List<Map<String, Object?>> messages,
    required String responseText,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    this.messages = messages;
    this.metadata = metadata;
    final error = this.error;
    if (error != null) throw error;
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}
