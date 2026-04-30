import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';

import '../../data/db/test_database.dart';

class _FakeApi implements AiChatApiClient {
  _FakeApi();

  final List<AiChatEvent> script = <AiChatEvent>[];
  List<WireMessage>? lastMessages;
  Object? errorToThrow;

  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    lastMessages = messages;
    if (errorToThrow != null) throw errorToThrow!;
    for (final e in script) {
      // Mimic real network latency so the controller's "isStreaming"
      // window has a chance to be observed.
      await Future<void>.delayed(Duration.zero);
      yield e;
    }
  }
}

final _fakeSession = AuthSession(
  accessToken: 'tkn',
  expiresAt: DateTime.utc(2099, 1, 1),
  userId: 'user-1',
  deviceId: 'dev-1',
);

void main() {
  group('ChatRepository.sendMessage', () {
    late ChatHistoryStore store;
    late _FakeApi api;
    late ChatRepository repo;

    setUp(() async {
      store = ChatHistoryStore(makeTestDatabase());
      api = _FakeApi();
      repo = ChatRepository(
        store: store,
        api: api,
        sessionReader: () => _fakeSession,
      );
      await repo.createSession(ownerUserId: 'user-1');
    });

    tearDown(() => store.dispose());

    Future<String> activeSessionId() async {
      final sessions = await store.watchSessions('user-1').first;
      return sessions.single.id;
    }

    test('persists user turn and streamed assistant turn', () async {
      api.script.addAll(<AiChatEvent>[
        const TextEvent('约 ¥123,'),
        const TextEvent('456。'),
        const DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '我的总资产？',
      );
      expect(outcome, SendOutcome.completed);

      final msgs = await store.listMessages(id);
      // user + assistant
      expect(msgs.where((m) => m.role == ChatRole.user).single.content,
          '我的总资产？');
      final assistant = msgs.where((m) => m.role == ChatRole.assistant).single;
      expect(assistant.content, '约 ¥123,456。');
      expect(assistant.status, ChatMessageStatus.complete);

      // Wire form sent to the API: just the new user turn (no prior history).
      expect(api.lastMessages, hasLength(1));
      expect(api.lastMessages!.single.role, 'user');
    });

    test('records tool invocations on the assistant turn in arrival order',
        () async {
      api.script.addAll(<AiChatEvent>[
        const ToolCallEvent(
          id: 'a',
          name: 'get_holdings',
          input: {'as_of': '2026-04-30'},
        ),
        const ToolResultEvent(
          id: 'a',
          name: 'get_holdings',
          output: <String, Object?>{'rows': <Object?>[]},
        ),
        const TextEvent('好的，'),
        const ToolCallEvent(
          id: 'b',
          name: 'compute_xirr',
          input: {'scope': 'portfolio'},
        ),
        const ToolResultEvent(
          id: 'b',
          name: 'compute_xirr',
          output: {'value': 0.12},
        ),
        const TextEvent('XIRR 是 12%'),
        const DoneEvent(stopReason: 'end_turn', rounds: 2),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '帮我看看持仓和 XIRR',
      );

      final assistant = (await store.listMessages(id))
          .firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.toolCalls.map((t) => t.name),
          ['get_holdings', 'compute_xirr']);
      expect(assistant.toolCalls.first.output, isA<Map<String, Object?>>());
      expect(assistant.toolCalls.last.output, isA<Map<String, Object?>>());
      expect(assistant.content, '好的，XIRR 是 12%');
    });

    test('marks turn errored when the stream throws', () async {
      api.errorToThrow =
          const AiChatRequestException(statusCode: 500, message: 'boom');

      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'hi',
      );
      expect(outcome, SendOutcome.errored);

      final assistant = (await store.listMessages(id))
          .firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.errored);
      expect(assistant.errorMessage, 'boom');
    });

    test('autotitles the session from the first user prompt', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '我的总资产是多少？',
      );
      final session = await store.findSession(id);
      expect(session!.title, '我的总资产是多少？');
    });

    test('replays prior turns to the API for follow-up questions', () async {
      api.script.addAll(const [
        TextEvent('A1'),
        DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'Q1',
      );
      api.script
        ..clear()
        ..addAll(const [
          TextEvent('A2'),
          DoneEvent(stopReason: 'end_turn', rounds: 1),
        ]);
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'Q2',
      );
      // The wire payload for the second turn should contain the prior
      // user / assistant pair plus the new prompt.
      expect(api.lastMessages!.map((m) => m.content), ['Q1', 'A1', 'Q2']);
    });
  });
}
