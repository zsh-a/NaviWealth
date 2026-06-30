import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/frb_chat_event.dart';

void main() {
  test('parses FRB tool call end events', () {
    final event = FrbChatStreamEvent.parse(const <String, Object?>{
      'kind': 'tool_call_end',
      'round': 2,
      'tool_call_id': 'call_1',
      'tool_name': 'read_task',
      'tool_input': <String, Object?>{'id': 'task_1'},
      'metadata': <String, Object?>{'stream': true},
    });

    expect(event, isA<FrbChatToolCallEndEvent>());
    final toolEvent = event as FrbChatToolCallEndEvent;
    expect(toolEvent.round, 2);
    expect(toolEvent.id, 'call_1');
    expect(toolEvent.name, 'read_task');
    expect(toolEvent.input, <String, Object?>{'id': 'task_1'});
    expect(toolEvent.metadata['stream'], true);
  });

  test('parses FRB usage events', () {
    final event = FrbChatStreamEvent.parse(const <String, Object?>{
      'kind': 'usage',
      'usage': <String, Object?>{'input_tokens': 7, 'output_tokens': 5},
    });

    expect(event, isA<FrbChatUsageEvent>());
    final usageEvent = event as FrbChatUsageEvent;
    expect(usageEvent.usage.input, 7);
    expect(usageEvent.usage.output, 5);
    expect(usageEvent.usage.total, 12);
  });

  test('returns invalid events for malformed required fields', () {
    final event = FrbChatStreamEvent.parse(const <String, Object?>{
      'kind': 'tool_call_start',
      'tool_call_id': 'call_1',
    });

    expect(event, isA<FrbInvalidChatEvent>());
    expect(
      (event as FrbInvalidChatEvent).message,
      'FRB LLM tool_call_start event requires tool_call_id and tool_name',
    );
  });

  test('returns unknown events for unsupported kinds', () {
    final event = FrbChatStreamEvent.parse(const <String, Object?>{
      'kind': 'provider_ping',
    });

    expect(event, isA<FrbUnknownChatEvent>());
    expect(
      (event as FrbUnknownChatEvent).message,
      'unknown FRB LLM stream event kind: provider_ping',
    );
  });

  test('parses the shared agent chat turn event fixture', () {
    final fixture =
        jsonDecode(
              File(
                '../../docs/fixtures/agent_chat_turn_events.json',
              ).readAsStringSync(),
            )
            as List<Object?>;
    final events = [
      for (final raw in fixture)
        FrbChatStreamEvent.parse((raw as Map).cast<String, Object?>()),
    ];

    expect(events.map((event) => event.kind), <String>[
      'started',
      'delta',
      'tool_call_start',
      'tool_call_delta',
      'tool_call_end',
      'usage',
      'round_finished',
    ]);
    expect((events[2] as FrbChatToolCallStartEvent).name, 'get_holdings');
    expect((events[4] as FrbChatToolCallEndEvent).input, <String, Object?>{
      'as_of': 'today',
    });
    expect((events[5] as FrbChatUsageEvent).usage.total, 18);
    expect(
      (events[6] as FrbChatRoundFinishedEvent).metadata['status'],
      'requires_tool_results',
    );
  });
}
