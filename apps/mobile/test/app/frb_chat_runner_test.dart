import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_runner.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/chat_agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart'
    show kMaxToolRounds;
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';

void main() {
  test('maps FRB native stream events into chat events', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridge(
      bridge,
      events: const <String>[
        '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
        '{"kind":"llm_started","round":1,"metadata":{"stream":true}}',
        '{"kind":"thinking_delta","content":"reason","metadata":{"stream":true}}',
        '{"kind":"delta","content":"Hello ","metadata":{"synthetic_stream":true}}',
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_delta","tool_call_id":"call_1","tool_name":"read_task","partial_input_json":"{\\"","metadata":{"stream":true}}',
        '{"kind":"tool_call_delta","tool_call_id":"call_1","tool_name":"read_task","partial_input_json":"id\\":\\"task_1\\"}","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
        '{"kind":"delta","content":"from FRB","metadata":{"synthetic_stream":true}}',
        '{"kind":"usage","usage":{"input_tokens":4,"output_tokens":3,"total_tokens":7},"round":1,"metadata":{}}',
        '{"kind":"round_finished","response":{"content":"Hello from FRB","finish_reason":"stop","usage":{"input_tokens":4,"output_tokens":3,"total_tokens":7}},"round":1,"metadata":{"finish_reason":"stop"}}',
        '{"kind":"done","round":1,"metadata":{"stop_reason":"end_turn"}}',
      ],
    );
    final runner = FrbChatRunner(streamBridge: streamBridge);

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
    expect(request['surface'], 'ai_chat');
    expect(request['agent_id'], kFrbChatRunnerAgentId);
    expect(request['messages'], <Object?>[
      <String, Object?>{'role': 'user', 'content': 'Hello'},
    ]);
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['streaming'], true);
  });

  test('passes ChatAgent turn metadata to the FRB chat request', () async {
    final streamBridge = _streamBridge(
      _FakeLlmBridge(),
      events: const <String>[
        '{"kind":"round_finished","response":{"content":"ok","finish_reason":"stop"},"round":1,"metadata":{"finish_reason":"stop"}}',
        '{"kind":"done","round":1,"metadata":{"stop_reason":"end_turn"}}',
      ],
    );
    final runner = FrbChatRunner(streamBridge: streamBridge);

    await runner
        .runTurn(
          const ChatAgentTurnRequest(
            messages: <ChatAgentMessage>[
              ChatAgentMessage(role: 'user', content: 'Hello'),
            ],
            turnId: 'turn_1',
            sessionId: 'session_1',
            threadId: 'thread_1',
            surface: 'ai_chat',
            agentId: 'ai_chat',
            mode: 'chat',
            metadata: <String, Object?>{'source': 'test'},
            temperature: 0,
            maxOutputTokens: 64,
          ),
        )
        .toList();

    final request = streamBridge.requests.single;
    expect(request['turn_id'], 'turn_1');
    expect(request['session_id'], 'session_1');
    expect(request['thread_id'], 'thread_1');
    expect(request['surface'], 'ai_chat');
    expect(request['agent_id'], 'ai_chat');
    expect(request['mode'], 'chat');
    expect(request['temperature'], 0);
    expect(request['max_output_tokens'], 64);
    final metadata = request['metadata'] as Map<String, Object?>;
    expect(metadata['source'], 'test');
    expect(metadata['turn_id'], 'turn_1');
    expect(metadata['session_id'], 'session_1');
    expect(metadata['thread_id'], 'thread_1');
    expect(metadata['surface'], 'ai_chat');
    expect(metadata['agent_id'], 'ai_chat');
    expect(metadata['mode'], 'chat');
  });

  test(
    'uses standalone FRB usage stream events for chat usage and trace',
    () async {
      final streamBridge = _streamBridge(
        _FakeLlmBridge(),
        events: const <String>[
          '{"kind":"delta","content":"Hello","metadata":{"stream":true}}',
          '{"kind":"usage","usage":{"input_tokens":9,"output_tokens":4,"total_tokens":13},"round":1,"metadata":{}}',
          '{"kind":"round_finished","response":{"content":"Hello","finish_reason":"stop"},"round":1,"metadata":{"finish_reason":"stop"}}',
          '{"kind":"done","round":1,"metadata":{"stop_reason":"end_turn"}}',
        ],
      );
      final runner = FrbChatRunner(streamBridge: streamBridge);

      final events = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect(events.whereType<UsageEvent>().single.usage.total, 13);
      final span = events.whereType<SpanEvent>().single;
      expect(span.tokens?.input, 9);
      expect(span.tokens?.output, 4);
      expect(span.tokens?.total, 13);
    },
  );

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
          '{"kind":"round_finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"status":"requires_tool_results","chat_state":{"round":1,"pending_tool_calls":[{"id":"call_1","name":"read_task","input":{"id":"task_1"}}]},"tool_calls":[{"id":"call_1","name":"read_task","input":{"id":"task_1"}}]}}',
        ],
        <String>[
          '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
          '{"kind":"delta","content":"Task title","metadata":{"stream":true}}',
          '{"kind":"round_finished","response":{"content":"Task title","finish_reason":"stop","usage":{"input_tokens":5,"output_tokens":3,"total_tokens":8}},"metadata":{"status":"completed","chat_state":{"round":2}}}',
          '{"kind":"done","round":2,"metadata":{"stop_reason":"end_turn"}}',
        ],
      ],
    );
    final toolRequests = <Map<String, Object?>>[];
    final runner = FrbChatRunner(
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
    expect(firstRequest['max_tool_rounds'], kMaxToolRounds);
    final secondMessages = streamBridge.requests[1]['messages'] as List;
    expect(secondMessages, hasLength(1));
    final secondMetadata =
        streamBridge.requests[1]['metadata'] as Map<String, Object?>;
    expect(secondMetadata['round'], 2);
    expect(secondMetadata['chat_state'], isA<Map<String, Object?>>());
    expect(secondMetadata['tool_results'], <Object?>[
      <String, Object?>{
        'tool_call_id': 'call_1',
        'tool_name': 'read_task',
        'output': <String, Object?>{'title': 'Task title'},
        'is_error': false,
        'outcome': <String, Object?>{
          'status': 'ok',
          'retryable': false,
          'details': <String, Object?>{},
        },
      },
    ]);
  });

  test('dispatches consecutive read-only FRB tool calls in parallel', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridgeBatches(
      bridge,
      eventBatches: const <List<String>>[
        <String>[
          '{"kind":"round_finished","response":{"content":"","finish_reason":"tool_call"},"metadata":{"status":"requires_tool_results","chat_state":{"round":1},"tool_calls":[{"id":"call_1","name":"read_first","input":{"id":"first"}},{"id":"call_2","name":"read_second","input":{"id":"second"}}]}}',
        ],
        <String>[
          '{"kind":"round_finished","response":{"content":"done","finish_reason":"stop"},"metadata":{"status":"completed"}}',
        ],
      ],
    );
    var active = 0;
    var maxActive = 0;
    final runner = FrbChatRunner(
      streamBridge: streamBridge,
      tools: const <Map<String, Object?>>[
        <String, Object?>{
          'name': 'read_first',
          'description': 'Read first',
          'input_schema': <String, Object?>{'type': 'object'},
          'risk': 'read_only',
        },
        <String, Object?>{
          'name': 'read_second',
          'description': 'Read second',
          'input_schema': <String, Object?>{'type': 'object'},
          'risk': 'read_only',
        },
      ],
      toolLineHandler: (line) async {
        active += 1;
        if (active > maxActive) maxActive = active;
        final request = jsonDecode(line) as Map<String, Object?>;
        final params = request['params'] as Map<String, Object?>;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        active -= 1;
        return jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': <String, Object?>{'name': params['name']},
        });
      },
    );

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Read both'),
          ],
        )
        .toList();

    expect(maxActive, 2);
    expect(
      events.whereType<ToolResultEvent>().map((event) => event.name),
      <String>['read_first', 'read_second'],
    );
    final secondMetadata =
        streamBridge.requests[1]['metadata'] as Map<String, Object?>;
    expect(secondMetadata['tool_results'], <Object?>[
      <String, Object?>{
        'tool_call_id': 'call_1',
        'tool_name': 'read_first',
        'output': <String, Object?>{'name': 'read_first'},
        'is_error': false,
        'outcome': <String, Object?>{
          'status': 'ok',
          'retryable': false,
          'details': <String, Object?>{},
        },
      },
      <String, Object?>{
        'tool_call_id': 'call_2',
        'tool_name': 'read_second',
        'output': <String, Object?>{'name': 'read_second'},
        'is_error': false,
        'outcome': <String, Object?>{
          'status': 'ok',
          'retryable': false,
          'details': <String, Object?>{},
        },
      },
    ]);
  });

  test('resumes completed tool results from a persisted chat snapshot', () async {
    final store = InMemoryAgentRuntimeChatSnapshotStore();
    await store.save(
      snapshot: _chatRecoverySnapshot(dispatchStatus: 'completed'),
    );
    final streamBridge = _streamBridge(
      _FakeLlmBridge(),
      events: const <String>[
        '{"kind":"round_finished","response":{"content":"recovered","finish_reason":"stop"},"round":2,"metadata":{"status":"completed","chat_state":{"protocol_version":"agent.v1","turn_id":"turn-recovery","provider":"mock","model":"mock","messages":[],"round":2,"pending_tool_calls":[]}}}',
        '{"kind":"done","round":2,"metadata":{"stop_reason":"end_turn"}}',
      ],
    );
    var toolCalls = 0;
    final runner = FrbChatRunner(
      streamBridge: streamBridge,
      snapshotStore: store,
      toolLineHandler: (_) async {
        toolCalls += 1;
        throw StateError('completed tools must not replay');
      },
    );

    final events = await runner
        .runTurn(
          const ChatAgentTurnRequest(
            turnId: 'turn-recovery',
            messages: <ChatAgentMessage>[
              ChatAgentMessage(role: 'user', content: 'resume'),
            ],
          ),
        )
        .toList();

    expect(toolCalls, 0);
    expect(streamBridge.requests, hasLength(1));
    final metadata =
        streamBridge.requests.single['metadata'] as Map<String, Object?>;
    expect(metadata['chat_state'], isA<Map<String, Object?>>());
    expect(metadata['tool_results'], hasLength(1));
    expect(events.whereType<TextEvent>().single.text, 'recovered');
    expect(await store.loadResumable('turn-recovery'), isNull);
  });

  test('does not replay interrupted at-most-once tools', () async {
    final store = InMemoryAgentRuntimeChatSnapshotStore();
    await store.save(
      snapshot: _chatRecoverySnapshot(
        dispatchStatus: 'dispatching',
        replayPolicy: 'at_most_once',
        includeResult: false,
      ),
    );
    final streamBridge = _streamBridge(
      _FakeLlmBridge(),
      events: const <String>[],
    );
    var toolCalls = 0;
    final runner = FrbChatRunner(
      streamBridge: streamBridge,
      snapshotStore: store,
      toolLineHandler: (_) async {
        toolCalls += 1;
        return '{}';
      },
    );

    final events = await runner
        .runTurn(
          const ChatAgentTurnRequest(
            turnId: 'turn-recovery',
            messages: <ChatAgentMessage>[
              ChatAgentMessage(role: 'user', content: 'resume'),
            ],
          ),
        )
        .toList();

    expect(toolCalls, 0);
    expect(streamBridge.requests, isEmpty);
    expect(
      events.whereType<ErrorEvent>().single.code,
      'frb_chat_at_most_once_interrupted',
    );
    expect(events.last, isA<DoneEvent>());
    expect(await store.loadResumable('turn-recovery'), isNull);
  });

  test('reports a missing FRB tool host without continuing', () async {
    final bridge = _FakeLlmBridge();
    final streamBridge = _streamBridge(
      bridge,
      events: const <String>[
        '{"kind":"started","metadata":{"provider":"openai","model":"gpt-test"}}',
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_name":"read_task","tool_input":{"id":"task_1"},"metadata":{"stream":true}}',
        '{"kind":"round_finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"status":"requires_tool_results","chat_state":{"round":1,"pending_tool_calls":[{"id":"call_1","name":"read_task","input":{"id":"task_1"}}]},"tool_calls":[{"id":"call_1","name":"read_task","input":{"id":"task_1"}}]}}',
      ],
    );
    final runner = FrbChatRunner(
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
        '{"kind":"error","round":1,"metadata":{"code":"validation_error","message":"chat turn exceeded the tool round budget","retryable":false}}',
      ],
    );
    var toolHostCalls = 0;
    final runner = FrbChatRunner(
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
    expect(error.code, 'validation_error');
    expect(error.message, 'chat turn exceeded the tool round budget');
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
          '{"kind":"round_finished","response":{"content":"","finish_reason":"tool_call","usage":{"input_tokens":4,"output_tokens":2,"total_tokens":6}},"metadata":{"status":"requires_tool_results","chat_state":{"round":1,"pending_tool_calls":[{"id":"decision_1","name":"ask_user","input":{"question":"Pick one","options":[{"id":"a","label":"A"}]}}]},"tool_calls":[{"id":"decision_1","name":"ask_user","input":{"question":"Pick one","options":[{"id":"a","label":"A"}]}}]}}',
        ],
        <String>[
          '{"kind":"delta","content":"should not run","metadata":{"stream":true}}',
          '{"kind":"finished","response":{"content":"should not run","finish_reason":"stop"},"metadata":{"stream":true}}',
        ],
      ],
    );
    final runner = FrbChatRunner(
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

  test('maps FRB source stream errors without incomplete fallback', () async {
    final runner = FrbChatRunner(
      streamBridge: _streamBridgeStreams(
        _FakeLlmBridge(),
        eventBatches: <Stream<String>>[
          Stream<String>.error(StateError('404 page not found')),
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
    final span = events[0] as SpanEvent;
    expect(span.status, AiSpanStatus.error);
    expect(span.errorCode, 'frb_llm_stream_error');
    expect(span.errorCode, isNot('frb_chat_stream_incomplete'));
    final error = events[1] as ErrorEvent;
    expect(error.code, 'frb_llm_stream_error');
    expect(error.message, contains('404 page not found'));
    expect((events[2] as DoneEvent).stopReason, 'error');
  });

  test('rejects malformed FRB finished response events', () async {
    final runner = FrbChatRunner(
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

  test('rejects malformed FRB tool call stream events', () async {
    Future<void> expectInvalidToolEvent({
      required List<String> events,
      required String expectedMessage,
    }) async {
      var toolHostCalls = 0;
      final runner = FrbChatRunner(
        streamBridge: _streamBridge(_FakeLlmBridge(), events: events),
        toolLineHandler: (line) async {
          toolHostCalls += 1;
          return jsonEncode(const <String, Object?>{'result': 'unexpected'});
        },
      );

      final chatEvents = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect(toolHostCalls, 0);
      expect(chatEvents.whereType<ToolCallEvent>(), isEmpty);
      final span = chatEvents.whereType<SpanEvent>().single;
      expect(span.status, AiSpanStatus.error);
      expect(span.errorCode, 'frb_chat_event_invalid');
      final error = chatEvents.whereType<ErrorEvent>().single;
      expect(error.code, 'frb_chat_event_invalid');
      expect(error.message, expectedMessage);
      final done = chatEvents.last as DoneEvent;
      expect(done.stopReason, 'error');
      expect(done.rounds, 1);
    }

    await expectInvalidToolEvent(
      events: const <String>[
        '{"kind":"tool_call_start","tool_call_id":"call_1","metadata":{"stream":true}}',
      ],
      expectedMessage:
          'FRB LLM tool_call_start event requires tool_call_id and tool_name',
    );
    await expectInvalidToolEvent(
      events: const <String>[
        '{"kind":"tool_call_delta","partial_input_json":"{}","metadata":{"stream":true}}',
      ],
      expectedMessage: 'FRB LLM tool_call_delta event requires tool_call_id',
    );
    await expectInvalidToolEvent(
      events: const <String>[
        '{"kind":"tool_call_start","tool_call_id":"call_1","tool_name":"read_task","metadata":{"stream":true}}',
        '{"kind":"tool_call_end","tool_call_id":"call_1","tool_input":{},"metadata":{"stream":true}}',
      ],
      expectedMessage:
          'FRB LLM tool_call_end event requires tool_call_id and tool_name',
    );
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
    final runner = FrbChatRunner(streamBridge: streamBridge);
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
        streamBridge: _streamBridge(
          _FakeLlmBridge(),
          events: <String>[
            jsonEncode(<String, Object?>{
              'kind': 'round_finished',
              'response': <String, Object?>{
                'content': '',
                'finish_reason': entry.key,
              },
              'round': 1,
              'metadata': <String, Object?>{'finish_reason': entry.key},
            }),
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

      expect(events.whereType<DoneEvent>().single.stopReason, entry.value);
    }
  });

  test('emits stream error vocabulary when FRB stream setup fails', () async {
    final runner = FrbChatRunner(
      streamBridge: _ThrowingStreamBridge(
        error: StateError('native unavailable'),
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
    expect((events[1] as ErrorEvent).code, 'frb_llm_stream_error');
    expect((events[2] as DoneEvent).stopReason, 'error');
  });
}

Map<String, Object?> _chatRecoverySnapshot({
  required String dispatchStatus,
  String replayPolicy = 'safe_retry',
  bool includeResult = true,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': 1,
    'status': 'requires_tool_results',
    'state': <String, Object?>{
      'protocol_version': 'agent.v1',
      'turn_id': 'turn-recovery',
      'provider': 'mock',
      'model': 'mock',
      'messages': const <Object?>[],
      'round': 1,
      'pending_tool_calls': const <Object?>[
        <String, Object?>{
          'id': 'call-recovery',
          'name': 'write_task',
          'input': <String, Object?>{'id': 'task-1'},
        },
      ],
    },
    'tool_dispatches': <Object?>[
      <String, Object?>{
        'call': const <String, Object?>{
          'id': 'call-recovery',
          'name': 'write_task',
          'input': <String, Object?>{'id': 'task-1'},
        },
        'replay_policy': replayPolicy,
        'status': dispatchStatus,
        if (includeResult)
          'result': const <String, Object?>{
            'tool_call_id': 'call-recovery',
            'tool_name': 'write_task',
            'output': <String, Object?>{'ok': true},
            'is_error': false,
            'outcome': <String, Object?>{
              'status': 'ok',
              'retryable': false,
              'details': <String, Object?>{},
            },
          },
      },
    ],
  };
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
         streamChatTurnJson: ({required String requestJson}) {
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

class _ThrowingStreamBridge extends AgentRuntimeLlmStreamBridge {
  _ThrowingStreamBridge({required Object error})
    : super(
        llmBridge: _FakeLlmBridge(),
        initRuntime: ({String? libraryPath}) async {},
        streamChatTurnJson: ({required String requestJson}) => throw error,
      );
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge();

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
      'temperature': ?temperature,
      'max_output_tokens': ?maxOutputTokens,
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
    return const <String, Object?>{'content': 'ok', 'finish_reason': 'stop'};
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
