import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/progress/long_task_progress.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';

import '../../core/persistence/test_database.dart';

void main() {
  group('ChatHistoryStore', () {
    late ChatHistoryStore store;

    setUp(() {
      store = ChatHistoryStore(makeTestDatabase());
    });

    tearDown(() => store.dispose());

    test('round-trips a session and its messages', () async {
      final session = ChatSession(
        id: 'sess-1',
        ownerUserId: 'user-1',
        title: '新对话',
        createdAt: DateTime.utc(2026, 4, 30, 10),
        updatedAt: DateTime.utc(2026, 4, 30, 10),
      );
      await store.insertSession(session);

      final user = ChatMessage(
        id: 'm-1',
        sessionId: 'sess-1',
        ownerUserId: 'user-1',
        role: ChatRole.user,
        content: '我的总资产是多少？',
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30, 10, 5),
      );
      final assistant = ChatMessage(
        id: 'm-2',
        sessionId: 'sess-1',
        ownerUserId: 'user-1',
        role: ChatRole.assistant,
        content: '约 ¥123,456。',
        toolCalls: [
          const ToolInvocation(
            id: 'call-1',
            name: 'get_holdings',
            input: <String, Object?>{'as_of': '2026-04-30'},
            output: <String, Object?>{'rows': []},
          ),
        ],
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30, 10, 6),
      );
      await store.insertMessage(user);
      await store.insertMessage(assistant);

      final messages = await store.listMessages('sess-1');
      expect(messages, hasLength(2));
      expect(messages[0].content, '我的总资产是多少？');
      expect(messages[1].content, '约 ¥123,456。');
      expect(messages[1].toolCalls, hasLength(1));
      expect(messages[1].toolCalls.single.name, 'get_holdings');
      expect((messages[1].toolCalls.single.output! as Map)['rows'], isEmpty);
    });

    test('updateMessage rewrites content and tool calls in place', () async {
      await store.insertSession(
        ChatSession(
          id: 's',
          ownerUserId: 'u',
          title: '新对话',
          createdAt: DateTime.utc(2026, 4, 30),
          updatedAt: DateTime.utc(2026, 4, 30),
        ),
      );
      final placeholder = ChatMessage(
        id: 'm',
        sessionId: 's',
        ownerUserId: 'u',
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
        createdAt: DateTime.utc(2026, 4, 30),
      );
      await store.insertMessage(placeholder);
      final updated = placeholder.copyWith(
        content: '回答',
        reasoningText: 'checked read models',
        usage: const TokenUsage(
          input: 10,
          output: 5,
          cacheRead: 2,
          cacheWrite: 1,
        ),
        progress: LongTaskProgress(
          id: 'tool:t',
          label: 'tool',
          detail: 'compute_xirr',
          startedAt: DateTime.utc(2026, 4, 30, 0, 0, 1),
          ratio: 0.5,
        ),
        status: ChatMessageStatus.complete,
        toolCalls: [
          const ToolInvocation(id: 't', name: 'compute_xirr', input: {}),
        ],
      );
      await store.updateMessage(updated);

      final rows = await store.listMessages('s');
      expect(rows.single.content, '回答');
      expect(rows.single.reasoningText, 'checked read models');
      expect(rows.single.usage?.total, 18);
      expect(rows.single.progress?.detail, 'compute_xirr');
      expect(rows.single.progress?.normalisedRatio, 0.5);
      expect(rows.single.status, ChatMessageStatus.complete);
      expect(rows.single.toolCalls.single.name, 'compute_xirr');
    });

    test('watchSessions emits a fresh snapshot after each mutation', () async {
      final collected = <List<ChatSession>>[];
      final sub = store.watchSessions('u').listen(collected.add);
      addTearDown(sub.cancel);

      Future<List<ChatSession>> nextSnapshot() async {
        final start = collected.length;
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (collected.length > start) return collected.last;
        }
        fail('no snapshot emitted within 500ms');
      }

      // Wait for the initial empty snapshot before any mutations.
      for (var i = 0; i < 50 && collected.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(collected.last, isEmpty);

      await store.insertSession(
        ChatSession(
          id: 'a',
          ownerUserId: 'u',
          title: '一',
          createdAt: DateTime.utc(2026, 4, 30, 9),
          updatedAt: DateTime.utc(2026, 4, 30, 9),
        ),
      );
      expect((await nextSnapshot()).map((s) => s.id), ['a']);

      await store.insertSession(
        ChatSession(
          id: 'b',
          ownerUserId: 'u',
          title: '二',
          createdAt: DateTime.utc(2026, 4, 30, 10),
          updatedAt: DateTime.utc(2026, 4, 30, 10),
          lastMessageAt: DateTime.utc(2026, 4, 30, 11),
        ),
      );
      // 'b' has a more recent last_message_at, so it sorts ahead of 'a'.
      expect((await nextSnapshot()).map((s) => s.id), ['b', 'a']);
    });

    test('deleteSession removes the session and its messages', () async {
      await store.insertSession(
        ChatSession(
          id: 's',
          ownerUserId: 'u',
          title: '新对话',
          createdAt: DateTime.utc(2026, 4, 30),
          updatedAt: DateTime.utc(2026, 4, 30),
        ),
      );
      await store.insertMessage(
        ChatMessage(
          id: 'm',
          sessionId: 's',
          ownerUserId: 'u',
          role: ChatRole.user,
          content: 'hi',
          status: ChatMessageStatus.complete,
          createdAt: DateTime.utc(2026, 4, 30),
        ),
      );
      await store.deleteSession('s');
      expect(await store.findSession('s'), isNull);
      expect(await store.listMessages('s'), isEmpty);
    });
  });
}
