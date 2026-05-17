import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_agent_loop.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';

/// Scripts one [LlmStreamEvent] list per round, in order.
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

class _RecordingDispatcher implements DeviceToolDispatcher {
  final List<String> calls = [];
  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    calls.add(name);
    return {'ok': true, 'tool': name};
  }
}

DeviceSession _session(List<AnthropicChatMessage> msgs) =>
    DeviceSession(messages: [...msgs]);

AnthropicChatMessage _user(String t) =>
    AnthropicChatMessage(role: 'user', content: t);

void main() {
  group('DeviceAgentLoop — ported from agent_loop.rs', () {
    test('text-only turn streams text then a single DoneEvent', () async {
      final adapter = _ScriptedAdapter([
        [const LlmTextDelta('你好'), const LlmMessageStop(LlmStopReason.endTurn)],
      ]);
      final dispatcher = _RecordingDispatcher();
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: dispatcher,
      );
      final events = await loop.run(_session([_user('hi')])).toList();

      expect(events.whereType<TextEvent>().single.text, '你好');
      final done = events.last as DoneEvent;
      expect(done.stopReason, 'end_turn');
      expect(done.rounds, 1);
      expect(dispatcher.calls, isEmpty);
    });

    test('advances multiple tool rounds and dispatches the tool', () async {
      final adapter = _ScriptedAdapter([
        [
          const LlmTextDelta('checking'),
          const LlmToolCallStart(id: 't1', name: 'get_risk_alerts'),
          const LlmToolCallEnd(id: 't1', name: 'get_risk_alerts', input: {}),
          const LlmMessageStop(LlmStopReason.toolUse),
        ],
        [
          const LlmTextDelta('done'),
          const LlmMessageStop(LlmStopReason.endTurn),
        ],
      ]);
      final dispatcher = _RecordingDispatcher();
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: dispatcher,
      );
      final session = _session([_user('hi')]);
      final events = await loop.run(session).toList();

      expect(dispatcher.calls, ['get_risk_alerts']);
      expect(session.roundsUsed, 2);
      expect(adapter.calls, 2);
      expect(events.whereType<ToolCallEvent>().single.name, 'get_risk_alerts');
      expect(
        events.whereType<ToolResultEvent>().single.name,
        'get_risk_alerts',
      );
      final done = events.last as DoneEvent;
      expect(done.stopReason, 'end_turn');
      expect(done.rounds, 2);
      // assistant(tool_use) + user(tool_result) pushed onto the seed turn.
      expect(session.messages.length, 3);
    });

    test('propose_* cap skips dispatch and returns the cap error', () async {
      final seeded = <AnthropicChatMessage>[];
      for (var i = 0; i < kMaxProposalsPerConversation; i++) {
        seeded.add(
          AnthropicChatMessage(
            role: 'assistant',
            content: [
              {
                'type': 'tool_use',
                'id': 'old_$i',
                'name': 'propose_expense',
                'input': <String, Object?>{},
              },
            ],
          ),
        );
      }
      seeded.add(_user('add another'));
      final adapter = _ScriptedAdapter([
        [
          const LlmToolCallStart(id: 't1', name: 'propose_expense'),
          const LlmToolCallEnd(id: 't1', name: 'propose_expense', input: {}),
          const LlmMessageStop(LlmStopReason.toolUse),
        ],
        [const LlmMessageStop(LlmStopReason.endTurn)],
      ]);
      final dispatcher = _RecordingDispatcher();
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: dispatcher,
      );
      final events = await loop.run(_session(seeded)).toList();

      expect(dispatcher.calls, isEmpty);
      final tr = events.whereType<ToolResultEvent>().single;
      expect((tr.output! as Map)['code'], 'proposal_cap_exceeded');
      expect((events.last as DoneEvent).stopReason, 'end_turn');
    });

    test(
      'provider stream error emits ErrorEvent then DoneEvent(error)',
      () async {
        final adapter = _ScriptedAdapter([
          [const LlmStreamErrorEvent(code: 'overloaded', message: 'busy')],
        ]);
        final loop = DeviceAgentLoop(
          streamFn: adapter.stream,
          model: 'm',
          dispatcher: _RecordingDispatcher(),
        );
        final events = await loop.run(_session([_user('hi')])).toList();

        final err = events.whereType<ErrorEvent>().single;
        expect(err.code, 'overloaded');
        expect(err.message, 'busy');
        expect((events.last as DoneEvent).stopReason, 'error');
      },
    );

    test(
      'thrown adapter error degrades to provider_error + DoneEvent',
      () async {
        Stream<LlmStreamEvent> boom(
          AnthropicRequest r, {
          CancelToken? cancelToken,
        }) => Stream.error(StateError('socket closed'));
        final loop = DeviceAgentLoop(
          streamFn: boom,
          model: 'm',
          dispatcher: _RecordingDispatcher(),
        );
        final events = await loop.run(_session([_user('hi')])).toList();
        expect(events.whereType<ErrorEvent>().single.code, 'provider_error');
        expect((events.last as DoneEvent).stopReason, 'error');
      },
    );

    test('zero turn budget short-circuits to chat_timeout', () async {
      final adapter = _ScriptedAdapter([
        [const LlmMessageStop(LlmStopReason.endTurn)],
      ]);
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: _RecordingDispatcher(),
        budget: const TurnBudget(turnTimeout: Duration.zero),
      );
      final events = await loop.run(_session([_user('hi')])).toList();

      expect(adapter.calls, 0);
      expect(events.whereType<ErrorEvent>().single.code, 'chat_timeout');
      expect((events.last as DoneEvent).stopReason, 'error');
    });

    test('budget exhausted while still tool_use flags the cap', () async {
      // Every round asks for a tool → never converges within maxRounds.
      Stream<LlmStreamEvent> toolForever(
        AnthropicRequest r, {
        CancelToken? cancelToken,
      }) async* {
        yield const LlmToolCallStart(id: 't', name: 'get_risk_alerts');
        yield const LlmToolCallEnd(id: 't', name: 'get_risk_alerts', input: {});
        yield const LlmMessageStop(LlmStopReason.toolUse);
      }

      final loop = DeviceAgentLoop(
        streamFn: toolForever,
        model: 'm',
        dispatcher: _RecordingDispatcher(),
        budget: const TurnBudget(maxRounds: 2),
      );
      final session = _session([_user('hi')]);
      final events = await loop.run(session).toList();

      expect(session.roundsUsed, 2);
      expect(
        events.whereType<ErrorEvent>().single.code,
        'tool_round_budget_exhausted',
      );
      expect((events.last as DoneEvent).stopReason, 'tool_use');
    });
  });

  group('DeviceSession.systemPrompt', () {
    test('starts with the ported SYSTEM_PROMPT and carries an appendix', () {
      final s = DeviceSession(messages: [], systemAppendix: '\n[ctx]');
      final p = s.systemPrompt();
      expect(p.startsWith(kDeviceSystemPrompt), isTrue);
      expect(p.contains('当前时间:'), isTrue);
      expect(p.endsWith('[ctx]'), isTrue);
    });
  });

  group('RuntimeRoutingAiChatApiClient (W-D7 device-only)', () {
    test('no device runtime → unavailable error, no cloud relay', () async {
      const routed = RuntimeRoutingAiChatApiClient();
      expect(routed.usesDevice, isFalse);

      final out = await routed
          .chat(
            session: AuthSession(
              accessToken: 't',
              expiresAt: DateTime.utc(2030),
              userId: 'u',
              deviceId: 'd',
            ),
            messages: const [WireMessage(role: 'user', content: 'hi')],
          )
          .toList();

      expect(out, hasLength(2));
      expect((out.first as ErrorEvent).code, 'device_unavailable');
      expect(out.last, isA<DoneEvent>());
      expect((out.last as DoneEvent).stopReason, 'error');
    });
  });

  group('multi-round CancelToken isolation', () {
    // Regression: `AnthropicClient.streamMessages` cancels whatever
    // token it is given when its SSE listener goes away — which is
    // every normal round end. Sharing the turn token across rounds
    // therefore poisoned round-2 (`DioException [request cancelled]`,
    // surfaced as `round-2 provider_error`). The loop must hand each
    // round a disposable child token so round-1's teardown can't kill
    // round-2.
    test('round-1 stream teardown does not poison round-2', () async {
      final adapter = _TokenPoisoningAdapter([
        [
          const LlmToolCallStart(id: 't1', name: 'get_holdings'),
          const LlmToolCallEnd(id: 't1', name: 'get_holdings', input: {}),
          const LlmMessageStop(LlmStopReason.toolUse),
        ],
        [
          const LlmTextDelta('完成'),
          const LlmMessageStop(LlmStopReason.endTurn),
        ],
      ]);
      final loop = DeviceAgentLoop(
        streamFn: adapter.stream,
        model: 'm',
        dispatcher: _RecordingDispatcher(),
      );

      final events = await loop
          .run(_session([_user('hi')]), cancelToken: CancelToken())
          .toList();

      // Round-2 actually ran and the turn ended cleanly — no
      // `provider_error` from a token cancelled by round-1.
      expect(adapter.calls, 2);
      expect(
        events.whereType<TextEvent>().map((e) => e.text).join(),
        contains('完成'),
      );
      expect(events.whereType<ErrorEvent>(), isEmpty);
      final done = events.whereType<DoneEvent>().single;
      expect(done.stopReason, 'end_turn');
      expect(done.rounds, 2);
    });
  });
}

/// Mirrors the real `AnthropicClient.streamMessages` cancel behaviour:
/// a controller-backed stream that (a) cancels the supplied token when
/// its own listener is torn down, and (b) rejects like Dio if handed an
/// already-cancelled token. Replays one scripted round per call.
class _TokenPoisoningAdapter {
  _TokenPoisoningAdapter(this._rounds);
  final List<List<LlmStreamEvent>> _rounds;
  int calls = 0;

  Stream<LlmStreamEvent> stream(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) {
    final controller = StreamController<LlmStreamEvent>();
    final idx = calls++;
    if (cancelToken != null && cancelToken.isCancelled) {
      controller.addError(
        DioException(
          requestOptions: RequestOptions(path: '/v1/messages'),
          type: DioExceptionType.cancel,
          error: 'request cancelled',
        ),
      );
      controller.close();
      return controller.stream;
    }
    controller.onCancel = () {
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('listener cancelled');
      }
    };
    () async {
      for (final e in _rounds[idx]) {
        controller.add(e);
      }
      await controller.close();
    }();
    return controller.stream;
  }
}
