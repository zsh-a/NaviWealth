import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_apply_state.dart';

import '../../data/db/test_database.dart';

class _NoopApi implements AiChatApiClient {
  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    throw UnimplementedError('not used in this test');
  }
}

void main() {
  group('ProposalApplyState round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final state = ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: 'je-1',
        appliedTable: 'journal_entries',
        appliedAt: DateTime.utc(2026, 4, 30, 12),
        errorMessage: null,
        undoData: const <String, Object?>{'previous_value': '100'},
        shortLabel: '已记录买入 AAPL',
      );
      final round = ProposalApplyState.fromJson(state.toJson());
      expect(round.status, state.status);
      expect(round.appliedEntityId, state.appliedEntityId);
      expect(round.appliedTable, state.appliedTable);
      expect(round.appliedAt, state.appliedAt);
      expect(round.undoData, state.undoData);
      expect(round.shortLabel, state.shortLabel);
    });

    test('isUndoableAt returns true within the 60s window', () {
      final state = ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedAt: DateTime.utc(2026, 4, 30, 12),
        appliedEntityId: 'x',
        appliedTable: 'journal_entries',
      );
      expect(state.isUndoableAt(DateTime.utc(2026, 4, 30, 12, 0, 30)), isTrue);
      expect(state.isUndoableAt(DateTime.utc(2026, 4, 30, 12, 1, 30)), isFalse);
    });

    test('cancelled / pending states are never undoable', () {
      const cancelled = ProposalApplyState(
        status: ProposalApplyStatus.cancelled,
      );
      expect(cancelled.isUndoableAt(DateTime.now()), isFalse);
      expect(ProposalApplyState.pending.isUndoableAt(DateTime.now()), isFalse);
    });
  });

  group('ToolInvocation persistence', () {
    test('survives JSON encode/decode with apply state attached', () {
      final t = ToolInvocation(
        id: 'call-1',
        name: 'propose_trade',
        input: const <String, Object?>{'symbol': 'AAPL'},
        output: const <String, Object?>{'kind': 'trade'},
        applyState: ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: 'je-1',
          appliedTable: 'journal_entries',
          appliedAt: DateTime.utc(2026, 4, 30),
          shortLabel: '已记录',
        ),
      );
      final encoded = ToolInvocation.encodeList([t]);
      final decoded = ToolInvocation.decodeList(encoded);
      expect(decoded, hasLength(1));
      expect(decoded.single.applyState, isNotNull);
      expect(decoded.single.applyState!.status, ProposalApplyStatus.applied);
      expect(decoded.single.applyState!.appliedEntityId, 'je-1');
    });

    test('decoder handles legacy payload without apply_state field', () {
      // Tool calls written before FIR-67 won't carry an apply_state
      // sub-object — the decoder must treat that as `pending`.
      const legacy =
          '[{"id":"c","name":"get_holdings","input":null,"output":null}]';
      final decoded = ToolInvocation.decodeList(legacy);
      expect(decoded.single.applyState, isNull);
    });
  });

  group('ChatRepository.updateToolApplyState', () {
    test('rewrites only the targeted tool invocation', () async {
      final store = ChatHistoryStore(makeTestDatabase());
      addTearDown(store.dispose);
      final repo = ChatRepository(
        store: store,
        api: _NoopApi(),
        sessionReader: () => null,
      );
      const sessionId = 's';
      const messageId = 'm';
      await store.insertSession(
        ChatSession(
          id: sessionId,
          ownerUserId: 'u',
          title: '新对话',
          createdAt: DateTime.utc(2026, 4, 30),
          updatedAt: DateTime.utc(2026, 4, 30),
        ),
      );
      await store.insertMessage(
        ChatMessage(
          id: messageId,
          sessionId: sessionId,
          ownerUserId: 'u',
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.complete,
          toolCalls: const [
            ToolInvocation(
              id: 't-1',
              name: 'propose_trade',
              input: null,
              output: null,
            ),
            ToolInvocation(
              id: 't-2',
              name: 'propose_expense',
              input: null,
              output: null,
            ),
          ],
          createdAt: DateTime.utc(2026, 4, 30),
        ),
      );

      await repo.updateToolApplyState(
        sessionId: sessionId,
        messageId: messageId,
        toolInvocationId: 't-1',
        newState: const ProposalApplyState(
          status: ProposalApplyStatus.cancelled,
        ),
      );

      final messages = await store.listMessages(sessionId);
      final calls = messages.single.toolCalls;
      expect(calls[0].applyState?.status, ProposalApplyStatus.cancelled);
      expect(calls[1].applyState, isNull);
    });
  });
}
