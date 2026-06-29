import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_agent_loop.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';

class _ScriptedAdapter {
  _ScriptedAdapter(this._rounds);
  final List<List<LlmStreamEvent>> _rounds;
  int calls = 0;

  Stream<LlmStreamEvent> stream(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async* {
    final round = _rounds[calls++];
    for (final e in round) {
      yield e;
    }
  }
}

class _OkDispatcher implements DeviceToolDispatcher {
  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async => {'ok': true, 'tool': name};
}

class _ErrDispatcher implements DeviceToolDispatcher {
  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async => {'error': 'boom', 'code': 'tool_error'};
}

DeviceSession _session() => DeviceSession(
  messages: [const AnthropicChatMessage(role: 'user', content: 'hi')],
);

void main() {
  group('DeviceAgentLoop span emission', () {
    test(
      'emits one llm span with tokens / model / stop / parent=turn',
      () async {
        final adapter = _ScriptedAdapter([
          [
            const LlmTextDelta('答案'),
            const LlmUsage(
              inputTokens: 120,
              outputTokens: 30,
              cacheReadTokens: 8,
              cacheWriteTokens: 0,
            ),
            const LlmMessageStop(LlmStopReason.endTurn),
          ],
        ]);
        final loop = DeviceAgentLoop(
          streamFn: adapter.stream,
          model: 'claude-sonnet-4-6',
          dispatcher: _OkDispatcher(),
        );
        final events = await loop.run(_session()).toList();

        final span = events.whereType<SpanEvent>().single;
        expect(span.kind, AiSpanKind.llm);
        expect(span.id, 'r1');
        expect(span.parentId, kTurnSpanId);
        expect(span.status, AiSpanStatus.ok);
        expect(span.model, 'claude-sonnet-4-6');
        expect(span.stopReason, 'end_turn');
        expect(span.tokens!.input, 120);
        expect(span.tokens!.cacheRead, 8);
        expect(span.endedAt.isBefore(span.startedAt), isFalse);
      },
    );

    test('tool span parents onto its round and carries IO', () async {
      final adapter = _ScriptedAdapter([
        [
          const LlmToolCallStart(id: 't1', name: 'get_holdings'),
          const LlmToolCallEnd(
            id: 't1',
            name: 'get_holdings',
            input: {'unit': 'USD'},
          ),
          const LlmMessageStop(LlmStopReason.toolUse),
        ],
        [
          const LlmTextDelta('done'),
          const LlmMessageStop(LlmStopReason.endTurn),
        ],
      ]);
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: _OkDispatcher(),
      );
      final spans = (await loop.run(_session()).toList())
          .whereType<SpanEvent>()
          .toList();

      final tool = spans.singleWhere((s) => s.kind == AiSpanKind.tool);
      expect(tool.id, 'tool:t1');
      expect(tool.parentId, 'r1');
      expect(tool.name, 'tool:get_holdings');
      expect(tool.status, AiSpanStatus.ok);
      expect(tool.input, {'unit': 'USD'});
      expect(tool.output, {'ok': true, 'tool': 'get_holdings'});
      // Two llm rounds + one tool.
      expect(spans.where((s) => s.kind == AiSpanKind.llm).length, 2);
    });

    test('tool error marks the tool span errored with its code', () async {
      final adapter = _ScriptedAdapter([
        [
          const LlmToolCallStart(id: 't1', name: 'get_holdings'),
          const LlmToolCallEnd(id: 't1', name: 'get_holdings', input: {}),
          const LlmMessageStop(LlmStopReason.toolUse),
        ],
        [const LlmMessageStop(LlmStopReason.endTurn)],
      ]);
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: _ErrDispatcher(),
      );
      final tool = (await loop.run(_session()).toList())
          .whereType<SpanEvent>()
          .singleWhere((s) => s.kind == AiSpanKind.tool);
      expect(tool.status, AiSpanStatus.error);
      expect(tool.errorCode, 'tool_error');
    });

    test('provider error round emits an errored llm span', () async {
      final adapter = _ScriptedAdapter([
        [const LlmStreamErrorEvent(code: 'rate_limit', message: 'slow down')],
      ]);
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: _OkDispatcher(),
      );
      final span = (await loop.run(_session()).toList())
          .whereType<SpanEvent>()
          .single;
      expect(span.kind, AiSpanKind.llm);
      expect(span.status, AiSpanStatus.error);
      expect(span.errorCode, 'rate_limit');
    });
  });
}
