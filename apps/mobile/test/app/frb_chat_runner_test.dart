import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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

    expect(events, hasLength(4));
    expect((events[0] as UsageEvent).usage.input, 7);
    expect((events[0] as UsageEvent).usage.output, 3);
    expect((events[1] as TextEvent).text, 'FRB answer');
    final span = events[2] as SpanEvent;
    expect(span.kind, AiSpanKind.llm);
    expect(span.status, AiSpanStatus.ok);
    expect(span.model, 'gpt-test');
    expect(span.stopReason, 'end_turn');
    expect(span.tokens?.total, 10);
    expect(span.attributes, containsPair('streaming', false));
    final done = events[3] as DoneEvent;
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

    expect(events, hasLength(10));
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
    final span = events[8] as SpanEvent;
    expect(span.kind, AiSpanKind.llm);
    expect(span.status, AiSpanStatus.ok);
    expect(span.tokens?.total, 7);
    expect((events[9] as DoneEvent).stopReason, 'end_turn');
    final request = streamBridge.requests.single;
    expect(request['messages'], <Object?>[
      <String, Object?>{'role': 'user', 'content': 'Hello'},
    ]);
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['streaming'], true);
  });

  test('executes FRB tool calls and continues with tool results', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridgeBatches(
      bridge,
      eventBatches: const <List<String>>[
        <String>[
          '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
          '{"kind":"thinking_delta","content":"plan","metadata":{"stream":true}}',
          '{"kind":"thinking_signature_delta","content":"sig_1","metadata":{"stream":true}}',
          '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
          '{"kind":"tool_call_delta","tool_call_id":"call_1","tool_name":"read_task","partial_input_json":"{\\"id\\":\\"task_1\\"}","metadata":{"stream":true}}',
          '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
          '{"kind":"finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"stream":true}}',
        ],
        <String>[
          '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
          '{"kind":"delta","content":"Task title","metadata":{"stream":true}}',
          '{"kind":"finished","response":{"content":"Task title","finish_reason":"stop","usage":{"input_tokens":5,"output_tokens":3,"total_tokens":8}},"metadata":{"stream":true}}',
        ],
      ],
    );
    final toolRequests = <Map<String, Object?>>[];
    final runner = FrbChatRunner(
      llmBridge: bridge,
      streamBridge: streamBridge,
      tools: const <Map<String, Object?>>[
        <String, Object?>{
          'name': 'read_task',
          'description': 'Read a task',
          'input_schema': <String, Object?>{'type': 'object'},
          'risk': 'read_only',
        },
      ],
      toolLineHandler: (line) async {
        toolRequests.add(jsonDecode(line) as Map<String, Object?>);
        return jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'call_1',
          'result': <String, Object?>{'title': 'Task title'},
        });
      },
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Read task task_1'),
          ],
        )
        .toList();

    expect(streamBridge.requests, hasLength(2));
    expect(toolRequests.single['method'], 'tool.call');
    final params = toolRequests.single['params'] as Map<String, Object?>;
    expect(params['name'], 'read_task');
    expect(params['input'], <String, Object?>{'id': 'task_1'});
    expect(events.whereType<ToolResultEvent>().single.output, <String, Object?>{
      'title': 'Task title',
    });
    expect(events.whereType<TextEvent>().single.text, 'Task title');
    expect(events.whereType<ProgressEvent>(), hasLength(1));
    final spans = events.whereType<SpanEvent>().toList();
    expect(spans.map((span) => span.kind), <AiSpanKind>[
      AiSpanKind.llm,
      AiSpanKind.tool,
      AiSpanKind.llm,
    ]);
    expect(spans[1].parentId, 'r1');
    expect(spans[1].status, AiSpanStatus.ok);
    final done = events.last as DoneEvent;
    expect(done.stopReason, 'end_turn');
    expect(done.rounds, 2);

    final firstRequest = streamBridge.requests.first;
    expect(firstRequest['tools'], hasLength(1));
    final secondMessages = streamBridge.requests[1]['messages'] as List;
    expect(secondMessages, hasLength(3));
    expect(secondMessages[1], <String, Object?>{
      'role': 'assistant',
      'content': <Object?>[
        <String, Object?>{
          'type': 'thinking',
          'thinking': 'plan',
          'signature': 'sig_1',
        },
        <String, Object?>{
          'type': 'tool_use',
          'id': 'call_1',
          'name': 'read_task',
          'input': <String, Object?>{'id': 'task_1'},
        },
      ],
    });
    expect(secondMessages[2], <String, Object?>{
      'role': 'user',
      'content': <Object?>[
        <String, Object?>{
          'type': 'tool_result',
          'tool_use_id': 'call_1',
          'content': '{"title":"Task title"}',
        },
      ],
    });
    final secondMetadata =
        streamBridge.requests[1]['metadata'] as Map<String, Object?>;
    expect(secondMetadata['round'], 2);
  });

  test('reports a missing FRB tool host without continuing', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridge(
      bridge,
      events: const <String>[
        '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
        '{"kind":"finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"stream":true}}',
      ],
    );
    final runner = FrbChatRunner(
      llmBridge: bridge,
      streamBridge: streamBridge,
      tools: const <Map<String, Object?>>[
        <String, Object?>{
          'name': 'read_task',
          'description': 'Read a task',
          'input_schema': <String, Object?>{'type': 'object'},
          'risk': 'read_only',
        },
      ],
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Read task task_1'),
          ],
        )
        .toList();

    expect(streamBridge.requests, hasLength(1));
    expect(events.whereType<ToolResultEvent>(), isEmpty);
    final spans = events.whereType<SpanEvent>().toList();
    expect(spans, hasLength(1));
    expect(spans.single.status, AiSpanStatus.ok);
    final error = events.whereType<ErrorEvent>().single;
    expect(error.code, 'frb_chat_tool_host_unavailable');
    expect(error.message, 'FRB chat received a tool call without a tool host');
    final done = events.last as DoneEvent;
    expect(done.stopReason, 'error');
    expect(done.rounds, 1);
  });

  test('enforces the FRB chat tool round budget', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridge(
      bridge,
      events: const <String>[
        '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
        '{"kind":"finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"stream":true}}',
      ],
    );
    var toolHostCalls = 0;
    final runner = FrbChatRunner(
      llmBridge: bridge,
      streamBridge: streamBridge,
      maxToolRounds: 1,
      toolLineHandler: (line) async {
        toolHostCalls += 1;
        return jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'call_1',
          'result': <String, Object?>{'title': 'Task title'},
        });
      },
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Read task task_1'),
          ],
        )
        .toList();

    expect(streamBridge.requests, hasLength(1));
    expect(toolHostCalls, 0);
    expect(events.whereType<ToolResultEvent>(), isEmpty);
    final error = events.whereType<ErrorEvent>().single;
    expect(error.code, 'frb_chat_tool_round_budget_exceeded');
    expect(error.message, 'FRB chat exceeded the tool round budget');
    final done = events.last as DoneEvent;
    expect(done.stopReason, 'error');
    expect(done.rounds, 1);
  });

  test('stops after ask_user tool result without another model round', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridgeBatches(
      bridge,
      eventBatches: const <List<String>>[
        <String>[
          '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
          '{"kind":"tool_call_start","tool_call_id":"decision_1","tool_name":"ask_user","metadata":{"stream":true}}',
          '{"kind":"tool_call_end","tool_call_id":"decision_1","tool_name":"ask_user","tool_input":{"question":"Pick one","options":[{"id":"a","label":"A"}]},"metadata":{"stream":true}}',
          '{"kind":"finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"stream":true}}',
        ],
        <String>[
          '{"kind":"delta","content":"should not run","metadata":{"stream":true}}',
          '{"kind":"finished","response":{"content":"should not run","finish_reason":"stop"},"metadata":{"stream":true}}',
        ],
      ],
    );
    final runner = FrbChatRunner(
      llmBridge: bridge,
      streamBridge: streamBridge,
      toolLineHandler: (line) async {
        return jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'decision_1',
          'result': <String, Object?>{
            'type': 'decision_request',
            'question': 'Pick one',
            'options': <Object?>[
              <String, Object?>{'id': 'a', 'label': 'A'},
            ],
          },
        });
      },
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Need a decision'),
          ],
        )
        .toList();

    expect(streamBridge.requests, hasLength(1));
    expect(events.whereType<ToolResultEvent>().single.name, 'ask_user');
    expect(events.whereType<TextEvent>(), isEmpty);
    final done = events.last as DoneEvent;
    expect(done.stopReason, 'end_turn');
    expect(done.rounds, 1);
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

    expect(events, hasLength(3));
    expect((events[0] as SpanEvent).status, AiSpanStatus.error);
    expect((events[1] as ErrorEvent).code, 'provider_http_401');
    expect((events[1] as ErrorEvent).message, 'bad key');
    expect((events[2] as DoneEvent).stopReason, 'error');
  });

  test('rejects malformed FRB finished response events', () async {
    final runner = FrbChatRunner(
      llmBridge: _FakeLlmBridge(),
      streamBridge: _streamBridge(
        _FakeLlmBridge(),
        events: const <String>[
          '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
          '{"kind":"delta","content":"partial","metadata":{"stream":true}}',
          '{"kind":"finished","response":"bad","metadata":{"stream":true}}',
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

    expect(events.whereType<TextEvent>().single.text, 'partial');
    final span = events.whereType<SpanEvent>().single;
    expect(span.status, AiSpanStatus.error);
    expect(span.errorCode, 'frb_chat_event_invalid');
    final error = events.whereType<ErrorEvent>().single;
    expect(error.code, 'frb_chat_event_invalid');
    expect(error.message, contains('finished event response'));
    final done = events.last as DoneEvent;
    expect(done.stopReason, 'error');
    expect(done.rounds, 1);
  });

  test('emits a cancelled span when the turn token is cancelled', () async {
    late CancelToken cancelToken;
    Stream<String> hangingStream() async* {
      yield '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}';
      cancelToken.cancel('user cancelled');
      yield '{"kind":"delta","content":"late","metadata":{"stream":true}}';
    }

    final streamBridge = _streamBridgeStreams(
      _FakeLlmBridge(),
      eventBatches: <Stream<String>>[hangingStream()],
    );
    final runner = FrbChatRunner(
      llmBridge: _FakeLlmBridge(),
      streamBridge: streamBridge,
    );
    cancelToken = CancelToken();

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Hello'),
          ],
          cancelToken: cancelToken,
        )
        .toList();

    expect(events, hasLength(2));
    final span = events[0] as SpanEvent;
    expect(span.status, AiSpanStatus.cancelled);
    expect(span.errorCode, 'cancelled');
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

      expect(events.whereType<DoneEvent>().single.stopReason, entry.value);
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
  return _streamBridgeStreams(
    bridge,
    eventBatches: <Stream<String>>[Stream<String>.fromIterable(events)],
  );
}

_RecordingStreamBridge _streamBridgeBatches(
  _FakeLlmBridge bridge, {
  required List<List<String>> eventBatches,
}) {
  return _streamBridgeStreams(
    bridge,
    eventBatches: [
      for (final batch in eventBatches) Stream<String>.fromIterable(batch),
    ],
  );
}

_RecordingStreamBridge _streamBridgeStreams(
  _FakeLlmBridge bridge, {
  required List<Stream<String>> eventBatches,
}) {
  return _RecordingStreamBridge(llmBridge: bridge, eventBatches: eventBatches);
}

class _RecordingStreamBridge extends AgentRuntimeLlmStreamBridge {
  factory _RecordingStreamBridge({
    required _FakeLlmBridge llmBridge,
    required List<Stream<String>> eventBatches,
  }) {
    final requests = <Map<String, Object?>>[];
    var requestIndex = 0;
    return _RecordingStreamBridge._(
      llmBridge: llmBridge,
      eventBatches: eventBatches,
      requests: requests,
      nextRequestIndex: () => requestIndex++,
    );
  }

  _RecordingStreamBridge._({
    required _FakeLlmBridge llmBridge,
    required List<Stream<String>> eventBatches,
    required this.requests,
    required int Function() nextRequestIndex,
  }) : super(
         llmBridge: llmBridge,
         initRuntime: ({String? libraryPath}) async {},
         streamProfileJson: ({required String requestJson}) {
           requests.add(jsonDecode(requestJson) as Map<String, Object?>);
           final index = nextRequestIndex();
           final batchIndex = index >= eventBatches.length
               ? eventBatches.length - 1
               : index;
           return eventBatches[batchIndex];
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
