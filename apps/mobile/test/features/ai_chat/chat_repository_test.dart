import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/core/ai/progress/long_task_progress.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/ai/trace/trace.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_turn_metadata.dart';

import '../../core/persistence/test_database.dart';

class _FakeApi implements AiChatApiClient {
  _FakeApi();

  final List<AiChatEvent> script = <AiChatEvent>[];
  List<WireMessage>? lastMessages;
  String? lastTurnId;
  String? lastSessionId;
  String? lastThreadId;
  String? lastSurface;
  String? lastAgentId;
  String? lastMode;
  Map<String, Object?>? lastMetadata;
  ContextPack? lastContextPack;
  List<AgentRuntimeContextBlock>? lastContextBlocks;
  AiInteractionResponse? lastInteractionResponse;
  Object? errorToThrow;
  Object? cancelBeforeThrow;

  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? turnId,
    String? sessionId,
    String? threadId,
    String? surface,
    String? agentId,
    String? mode,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    List<AgentRuntimeContextBlock> contextBlocks =
        const <AgentRuntimeContextBlock>[],
    AgentRuntimeContextPolicy? contextPolicy,
    AiInteractionResponse? interactionResponse,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    lastMessages = messages;
    lastTurnId = turnId;
    lastSessionId = sessionId;
    lastThreadId = threadId;
    lastSurface = surface;
    lastAgentId = agentId;
    lastMode = mode;
    lastMetadata = metadata;
    lastContextPack = contextPack;
    lastContextBlocks = contextBlocks;
    lastInteractionResponse = interactionResponse;
    if (errorToThrow != null) {
      final reason = cancelBeforeThrow;
      if (reason != null) {
        cancelToken?.cancel(reason);
      }
      throw errorToThrow!;
    }
    for (final e in script) {
      // Mimic real network latency so the controller's "isStreaming"
      // window has a chance to be observed.
      await Future<void>.delayed(Duration.zero);
      yield e;
    }
  }
}

class _NoDoneApi implements AiChatApiClient {
  _NoDoneApi(this.script);

  final List<AiChatEvent> script;

  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? turnId,
    String? sessionId,
    String? threadId,
    String? surface,
    String? agentId,
    String? mode,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    List<AgentRuntimeContextBlock> contextBlocks =
        const <AgentRuntimeContextBlock>[],
    AgentRuntimeContextPolicy? contextPolicy,
    AiInteractionResponse? interactionResponse,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    for (final e in script) {
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
      expect(
        msgs.where((m) => m.role == ChatRole.user).single.content,
        '我的总资产？',
      );
      final assistant = msgs.where((m) => m.role == ChatRole.assistant).single;
      expect(assistant.content, '约 ¥123,456。');
      expect(assistant.status, ChatMessageStatus.complete);

      // Wire form sent to the API: just the new user turn (no prior history).
      expect(api.lastMessages, hasLength(1));
      expect(api.lastMessages!.single.role, 'user');
      expect(api.lastTurnId, isNotEmpty);
      expect(api.lastSessionId, id);
      expect(api.lastThreadId, id);
      expect(api.lastSurface, 'ai_chat');
      expect(api.lastAgentId, 'ai_chat');
      expect(api.lastMode, 'chat');
      expect(api.lastMetadata?['owner_user_id'], 'user-1');
      expect(api.lastMetadata?['assistant_message_id'], api.lastTurnId);
    });

    test('prepares and forwards host context blocks for every turn', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      repo = ChatRepository(
        store: store,
        api: api,
        sessionReader: () => _fakeSession,
        contextBlockPrep: (request) async {
          expect(request.ownerUserId, 'user-1');
          expect(request.userMessage, 'remember my preference');
          return <AgentRuntimeContextBlock>[
            AgentRuntimeContextBlock(
              id: 'memory:preference',
              kind: AgentRuntimeContextBlockKind.memory,
              source: 'test',
              content: const {'summary': 'local first'},
            ),
          ];
        },
      );

      final outcome = await repo.sendMessage(
        sessionId: await activeSessionId(),
        ownerUserId: 'user-1',
        content: 'remember my preference',
      );

      expect(outcome, SendOutcome.completed);
      expect(api.lastContextBlocks, hasLength(1));
      expect(api.lastContextBlocks!.single.id, 'memory:preference');
    });

    test('context preparation failure does not break chat', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      repo = ChatRepository(
        store: store,
        api: api,
        sessionReader: () => _fakeSession,
        contextBlockPrep: (_) async => throw StateError('index unavailable'),
      );

      final outcome = await repo.sendMessage(
        sessionId: await activeSessionId(),
        ownerUserId: 'user-1',
        content: 'continue without memory',
      );

      expect(outcome, SendOutcome.completed);
      expect(api.lastContextBlocks, isEmpty);
    });

    test('clears long-task progress when the turn completes', () async {
      api.script.addAll(<AiChatEvent>[
        ProgressEvent(
          LongTaskProgress(
            id: 'tool:t1',
            label: 'tool',
            detail: 'get_holdings',
            startedAt: DateTime.utc(2026, 4, 30),
          ),
        ),
        const TextEvent('done'),
        const DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '查一下持仓',
      );
      expect(outcome, SendOutcome.completed);

      final assistant = (await store.listMessages(
        id,
      )).where((m) => m.role == ChatRole.assistant).single;
      expect(assistant.content, 'done');
      expect(assistant.progress, isNull);
    });

    test('creates a missing session before inserting messages', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      const missingSessionId = '5be4c844-2c5f-4f42-8a56-b3056ca44b8e';

      final outcome = await repo.sendMessage(
        sessionId: missingSessionId,
        ownerUserId: 'user-1',
        content: '我最近三个月赚了多少？',
      );

      expect(outcome, SendOutcome.completed);
      final session = await store.findSession(missingSessionId);
      expect(session, isNotNull);
      expect(session!.ownerUserId, 'user-1');
      expect(session.title, '我最近三个月赚了多少？');
      final messages = await store.listMessages(missingSessionId);
      expect(messages.where((m) => m.role == ChatRole.user), hasLength(1));
      expect(messages.where((m) => m.role == ChatRole.assistant), hasLength(1));
    });

    test(
      'creates a missing session before inserting a system notice',
      () async {
        const missingSessionId = '5be4c844-2c5f-4f42-8a56-b3056ca44b8e';

        await repo.insertSystemNotice(
          sessionId: missingSessionId,
          ownerUserId: 'user-1',
          content: '同步稍后会继续。',
        );

        expect(await store.findSession(missingSessionId), isNotNull);
        final messages = await store.listMessages(missingSessionId);
        expect(messages.single.role, ChatRole.system);
        expect(messages.single.content, '同步稍后会继续。');
      },
    );

    test('rejects writes to a session owned by another user', () async {
      final session = await repo.createSession(ownerUserId: 'other-user');

      await expectLater(
        repo.sendMessage(
          sessionId: session.id,
          ownerUserId: 'user-1',
          content: 'hello',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'records tool invocations on the assistant turn in arrival order',
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

        final assistant = (await store.listMessages(
          id,
        )).firstWhere((m) => m.role == ChatRole.assistant);
        expect(assistant.toolCalls.map((t) => t.name), [
          'get_holdings',
          'compute_xirr',
        ]);
        expect(assistant.toolCalls.map((t) => t.status), [
          ToolInvocationStatus.completed,
          ToolInvocationStatus.completed,
        ]);
        expect(assistant.toolCalls.first.output, isA<Map<String, Object?>>());
        expect(assistant.toolCalls.last.output, isA<Map<String, Object?>>());
        expect(assistant.content, '好的，XIRR 是 12%');
      },
    );

    test('records streaming tool input lifecycle', () async {
      api.script.addAll(<AiChatEvent>[
        const ToolCallStartEvent(id: 'a', name: 'get_holdings'),
        const ToolCallDeltaEvent(id: 'a', partialInputJson: '{"as_of"'),
        const ToolCallDeltaEvent(id: 'a', partialInputJson: ':"today"}'),
        const ToolCallEvent(
          id: 'a',
          name: 'get_holdings',
          input: <String, Object?>{'as_of': 'today'},
        ),
        const ToolResultEvent(
          id: 'a',
          name: 'get_holdings',
          output: <String, Object?>{'rows': <Object?>[]},
        ),
        const DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '查持仓',
      );

      final assistant = (await store.listMessages(
        id,
      )).firstWhere((m) => m.role == ChatRole.assistant);
      final invocation = assistant.toolCalls.single;
      expect(invocation.status, ToolInvocationStatus.completed);
      expect(invocation.partialInputJson, '{"as_of":"today"}');
      expect(invocation.input, <String, Object?>{'as_of': 'today'});
      expect(invocation.output, <String, Object?>{'rows': <Object?>[]});
    });

    test(
      'records ask_user decision selection and forwards next-turn metadata',
      () async {
        final id = await activeSessionId();
        final assistant = ChatMessage(
          id: 'assistant-1',
          sessionId: id,
          ownerUserId: 'user-1',
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.complete,
          createdAt: DateTime.utc(2026, 5, 1),
          toolCalls: const <ToolInvocation>[
            ToolInvocation(
              id: 'decision-1',
              name: 'ask_user',
              input: <String, Object?>{},
              output: <String, Object?>{
                'type': 'decision_request',
                'title': '选择方案',
                'options': <Object?>[
                  <String, Object?>{'id': 'a', 'label': '方案 A'},
                  <String, Object?>{'id': 'b', 'label': '方案 B'},
                ],
                'interaction': <String, Object?>{
                  'protocol_version': 'agent.v1',
                  'interaction_id': 'interaction-decision-1',
                  'kind': 'choice',
                  'mode': 'one_tap',
                  'status': 'pending',
                  'title': '选择方案',
                  'options': <Object?>[
                    <String, Object?>{
                      'id': 'a',
                      'label': '方案 A',
                      'description': '',
                      'metadata': <String, Object?>{},
                    },
                    <String, Object?>{
                      'id': 'b',
                      'label': '方案 B',
                      'description': '',
                      'metadata': <String, Object?>{},
                    },
                  ],
                  'response_schema': <String, Object?>{},
                  'payload': <String, Object?>{},
                  'metadata': <String, Object?>{},
                  'resume': <String, Object?>{'kind': 'chat_turn'},
                  'created_at': '2026-05-01T00:00:00Z',
                },
              },
            ),
          ],
        );
        await store.insertMessage(assistant);

        final selection = DecisionSelection(
          optionId: 'a',
          label: '方案 A',
          reply: '我选择「方案 A」。请在此方案下继续。',
          selectedAt: DateTime.utc(2026, 5, 1, 12),
        );
        final interactionResponse = await repo.recordDecisionSelection(
          sessionId: id,
          messageId: assistant.id,
          toolInvocationId: 'decision-1',
          selection: selection,
        );
        api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
        await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: selection.reply,
          turnMetadata: ChatTurnMetadata.forDecision(
            selection: selection,
            messageId: assistant.id,
            toolInvocationId: 'decision-1',
            interactionResponse: interactionResponse,
          ),
        );

        final updated = (await store.listMessages(
          id,
        )).firstWhere((message) => message.id == assistant.id);
        expect(updated.toolCalls.single.decisionSelection?.optionId, 'a');
        expect(
          updated.toolCalls.single.interactionResponse?.interactionId,
          'interaction-decision-1',
        );
        expect(
          updated.toolCalls.single.interactionResponse?.action,
          AiInteractionAction.submit,
        );
        expect(api.lastTurnId, assistant.id);
        expect(
          api.lastInteractionResponse?.interactionId,
          'interaction-decision-1',
        );
        expect(api.lastInteractionResponse?.value, <String, Object?>{
          'option_id': 'a',
          'label': '方案 A',
          'reply': '我选择「方案 A」。请在此方案下继续。',
        });
        expect(api.lastMetadata?['decision_message_id'], assistant.id);
        expect(api.lastMetadata?['decision_tool_invocation_id'], 'decision-1');
        final metadataDecision = api.lastMetadata?['decision'] as Map;
        expect(metadataDecision['option_id'], 'a');
      },
    );

    test('marks turn errored when the stream throws', () async {
      api.errorToThrow = const AiChatRequestException(
        statusCode: 500,
        message: 'boom',
      );

      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'hi',
      );
      expect(outcome, SendOutcome.errored);

      final assistant = (await store.listMessages(
        id,
      )).firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.errored);
      expect(assistant.errorMessage, 'boom');
    });

    test('marks turn errored when the response stream is empty', () async {
      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'hi',
      );

      expect(outcome, SendOutcome.errored);
      final assistant = (await store.listMessages(
        id,
      )).firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.errored);
      expect(
        assistant.errorMessage,
        'AI response stream ended without any events',
      );
    });

    test(
      'marks turn errored when the response stream closes before done',
      () async {
        repo = ChatRepository(
          store: store,
          api: _NoDoneApi(const [TextEvent('partial')]),
          sessionReader: () => _fakeSession,
        );

        final id = await activeSessionId();
        final outcome = await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: 'hi',
        );

        expect(outcome, SendOutcome.errored);
        final assistant = (await store.listMessages(
          id,
        )).firstWhere((m) => m.role == ChatRole.assistant);
        expect(assistant.content, 'partial');
        expect(assistant.status, ChatMessageStatus.errored);
        expect(assistant.errorMessage, 'AI response stream ended before done');
      },
    );

    test(
      'does not show cancelled for internal stream cleanup errors',
      () async {
        api
          ..errorToThrow = const AiChatRequestException(
            statusCode: 0,
            message: 'stream closed',
          )
          ..cancelBeforeThrow = 'listener cancelled';

        final id = await activeSessionId();
        final outcome = await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: 'hi',
        );

        expect(outcome, SendOutcome.errored);
        final assistant = (await store.listMessages(
          id,
        )).firstWhere((m) => m.role == ChatRole.assistant);
        expect(assistant.status, ChatMessageStatus.errored);
        expect(assistant.errorMessage, 'stream closed');
      },
    );

    test('shows cancelled only for user-triggered cancellation', () async {
      api
        ..errorToThrow = const AiChatRequestException(
          statusCode: 0,
          message: 'request cancelled',
        )
        ..cancelBeforeThrow = 'user cancelled';

      final id = await activeSessionId();
      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'hi',
      );

      expect(outcome, SendOutcome.cancelled);
      final assistant = (await store.listMessages(
        id,
      )).firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.errored);
      expect(assistant.errorMessage, kCancelledError);
    });

    test(
      'records textSegments interleaved with tool calls in arrival order',
      () async {
        api.script.addAll(<AiChatEvent>[
          const TextEvent('好的，我先查一下你的 XIRR。'),
          const ToolCallEvent(
            id: 'a',
            name: 'compute_xirr',
            input: {'scope': 'portfolio'},
          ),
          const ToolResultEvent(
            id: 'a',
            name: 'compute_xirr',
            output: {'value': 0.12},
          ),
          const TextEvent('数据不够，让我查交易记录。'),
          const ToolCallEvent(
            id: 'b',
            name: 'get_transactions',
            input: <String, Object?>{},
          ),
          const ToolResultEvent(
            id: 'b',
            name: 'get_transactions',
            output: {'rows': <Object?>[]},
          ),
          const TextEvent('账户里只有 100 CNY 现金存入。'),
          const DoneEvent(stopReason: 'end_turn', rounds: 3),
        ]);
        final id = await activeSessionId();
        await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: '帮我看 XIRR',
        );
        final assistant = (await store.listMessages(
          id,
        )).firstWhere((m) => m.role == ChatRole.assistant);
        expect(assistant.toolCalls.map((t) => t.name), [
          'compute_xirr',
          'get_transactions',
        ]);
        expect(assistant.textSegments, [
          '好的，我先查一下你的 XIRR。',
          '数据不够，让我查交易记录。',
          '账户里只有 100 CNY 现金存入。',
        ]);
        // displaySegments == textSegments when length matches the
        // toolCalls.length + 1 invariant.
        expect(assistant.displaySegments, assistant.textSegments);
        // Flat content stays available for replay / search.
        expect(
          assistant.content,
          '好的，我先查一下你的 XIRR。数据不够，让我查交易记录。账户里只有 100 CNY 现金存入。',
        );
      },
    );

    test('persists the stop_reason from the SSE done frame', () async {
      api.script.addAll(const [
        TextEvent('truncated mid-thought'),
        DoneEvent(stopReason: 'max_tokens', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'long question',
      );
      final assistant = (await store.listMessages(
        id,
      )).firstWhere((m) => m.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.complete);
      expect(assistant.stopReason, ChatStopReason.maxTokens);
    });

    test(
      'records ChatStopReason.error when the stream ends without done',
      () async {
        final noDoneApi = _NoDoneApi(const [TextEvent('partial')]);
        final repo2 = ChatRepository(
          store: store,
          api: noDoneApi,
          sessionReader: () => _fakeSession,
        );
        final id = await activeSessionId();
        final outcome = await repo2.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: 'q',
        );
        expect(outcome, SendOutcome.errored);
        final assistant = (await store.listMessages(
          id,
        )).firstWhere((m) => m.role == ChatRole.assistant);
        expect(assistant.status, ChatMessageStatus.errored);
        expect(assistant.stopReason, ChatStopReason.error);
      },
    );

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

    test('sends route context as a user turn, not a system role', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '你好',
        systemContext: 'User is currently on: /ai',
      );

      expect(api.lastMessages!.map((m) => m.role), ['user', 'user']);
      expect(
        api.lastMessages!.first.content,
        'Context:\nUser is currently on: /ai',
      );
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

    test(
      'injects a structured checkpoint when older turns leave the window',
      () async {
        api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
        final id = await activeSessionId();
        for (var i = 0; i < 6; i++) {
          await store.insertMessage(
            ChatMessage(
              id: 'history-$i',
              sessionId: id,
              ownerUserId: 'user-1',
              role: i.isEven ? ChatRole.user : ChatRole.assistant,
              content: 'turn-$i ${'x' * 5000}',
              status: ChatMessageStatus.complete,
              createdAt: DateTime.utc(2026, 7, 1, 0, i),
            ),
          );
        }

        await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: '继续',
        );

        final block = api.lastContextBlocks!.singleWhere(
          (item) => item.kind == AgentRuntimeContextBlockKind.compactionSummary,
        );
        expect(block.source, 'chat_history_checkpoint');
        expect(block.metadata['trusted_as_instruction'], isFalse);
        final content = block.content! as Map<String, Object?>;
        expect(content['checkpoint_version'], 1);
        expect(content['source_message_count'], 2);
        expect(content['summary_through_message_id'], 'history-1');
        expect(content['topic'], startsWith('turn-0'));
        expect(api.lastMessages, hasLength(5));

        final persisted = await store.findConversationCheckpoint(
          sessionId: id,
          ownerUserId: 'user-1',
        );
        expect(persisted?.summaryThroughMessageId, 'history-1');
        expect(persisted?.sourceMessageCount, 2);
      },
    );
  });

  group('ChatRepository — Phase 2-A trace + context pack', () {
    late ChatHistoryStore store;
    late _FakeApi api;
    late InMemoryAiTraceStore traceStore;
    late ChatRepository repo;

    setUp(() async {
      store = ChatHistoryStore(makeTestDatabase());
      api = _FakeApi();
      traceStore = InMemoryAiTraceStore();
      repo = ChatRepository(
        store: store,
        api: api,
        sessionReader: () => _fakeSession,
        tracePrep: ({required requestId, required userMessage}) async {
          const route = RouteContext(path: '/expense', area: 'expense');
          const intent = IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
            label: 'chat_turn',
          );
          final pack = const ContextCompressor().compress(
            route: route,
            intent: intent,
            baseCurrency: 'USD',
            expenseAnomalyDelta: 0.3,
          );
          final seed = AiTrace(
            requestId: requestId,
            startedAtIso: '2026-05-10T10:00:00.000Z',
            intent: intent,
            backend: Backend.hybrid,
            budgetTier: pack.budget.tier,
            routingReason: 'analyze_hybrid',
            totalDurationMs: 0,
          );
          return (pack: pack, traceSeed: seed, traceVerbose: false);
        },
        traceStore: traceStore,
      );
      await repo.createSession(ownerUserId: 'user-1');
    });

    tearDown(() => store.dispose());

    Future<String> activeSessionId() async {
      final sessions = await store.watchSessions('user-1').first;
      return sessions.single.id;
    }

    test('passes the prep ContextPack to the API', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '上月咖啡花了多少？',
      );
      expect(api.lastContextPack, isNotNull);
      expect(api.lastContextPack!.task.intent.label, 'chat_turn');
      expect(api.lastContextPack!.task.signals, isNotEmpty);
      expect(api.lastContextPack!.budget.tier, BudgetTier.standard);
    });

    test('appends a finalised AiTrace to the store with tool spans', () async {
      final t0 = DateTime.parse('2026-05-10T10:00:00.100Z');
      api.script.addAll(<AiChatEvent>[
        const TextEvent('查到了。'),
        const ToolCallEvent(
          id: 't_1',
          name: 'list_recent_expenses',
          input: <String, Object?>{},
        ),
        const ToolResultEvent(
          id: 't_1',
          name: 'list_recent_expenses',
          output: <String, Object?>{'count': 12},
        ),
        SpanEvent(
          id: 'tool:t_1',
          parentId: 'r1',
          kind: AiSpanKind.tool,
          name: 'tool:list_recent_expenses',
          startedAt: t0,
          endedAt: t0.add(const Duration(milliseconds: 40)),
        ),
        const DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '本月支出明细',
      );

      final traces = await traceStore.recent();
      expect(traces, hasLength(1));
      final trace = traces.single;
      expect(trace.intent.label, 'chat_turn');
      expect(trace.backend, Backend.hybrid);
      final rootAttrs = trace.spans.first.attributes!;
      expect(rootAttrs['context_pack_present'], isTrue);
      expect(rootAttrs['context_pack_json_bytes'], isA<int>());
      expect(rootAttrs['context_pack_budget_tier'], 'standard');
      expect(rootAttrs['context_appendix_present'], isTrue);
      expect(rootAttrs['context_appendix_bytes'], isA<int>());
      expect(trace.toolSpans, hasLength(1));
      expect(trace.toolSpans.single.name, 'tool:list_recent_expenses');
      expect(trace.toolSpans.single.isError, isFalse);
    });

    test('persists invocation trace metadata on finalised AiTrace', () async {
      api.script.add(const DoneEvent(stopReason: 'end_turn', rounds: 1));
      final id = await activeSessionId();

      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'Explain this card',
        turnMetadata: const ChatTurnMetadata(
          invocationTrace: <String, Object?>{
            'source': '/wealth/portfolio',
            'intent': 'summarize_account',
            'object_type': 'account',
            'object_id': 'acct-1',
            'domain': 'finance',
          },
        ),
      );

      final trace = (await traceStore.recent()).single;
      expect(trace.invocation, isNotNull);
      expect(trace.invocation!['source'], '/wealth/portfolio');
      expect(trace.invocation!['intent'], 'summarize_account');
      expect(trace.invocation!['object_type'], 'account');
      expect(trace.invocation!['object_id'], 'acct-1');
      expect(trace.invocation!['domain'], 'finance');
    });

    test('flags tool error in trace when span status is error', () async {
      final t0 = DateTime.parse('2026-05-10T10:00:00.100Z');
      api.script.addAll(<AiChatEvent>[
        const ToolCallEvent(
          id: 't_err',
          name: 'propose_trade',
          input: <String, Object?>{},
        ),
        const ToolResultEvent(
          id: 't_err',
          name: 'propose_trade',
          output: <String, Object?>{
            'error': 'proposal_cap_exceeded',
            'code': 'proposal_cap_exceeded',
          },
        ),
        SpanEvent(
          id: 'tool:t_err',
          parentId: 'r1',
          kind: AiSpanKind.tool,
          name: 'tool:propose_trade',
          startedAt: t0,
          endedAt: t0.add(const Duration(milliseconds: 5)),
          status: AiSpanStatus.error,
          errorCode: 'proposal_cap_exceeded',
        ),
        const DoneEvent(stopReason: 'end_turn', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: '买点 AAPL',
      );

      final trace = (await traceStore.recent()).single;
      expect(trace.toolSpans.single.isError, isTrue);
      expect(trace.toolSpans.single.errorCode, 'proposal_cap_exceeded');
    });

    test('still finalises trace when stream errors mid-flight', () async {
      api.script.addAll(const <AiChatEvent>[
        TextEvent('开始回答…'),
        ErrorEvent('upstream timeout'),
        DoneEvent(stopReason: 'error', rounds: 1),
      ]);
      final id = await activeSessionId();
      await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'Q',
      );
      expect(await traceStore.recent(), hasLength(1));
    });

    test(
      'records FRB chat tool budget errors as stream-error traces',
      () async {
        api.script.addAll(const <AiChatEvent>[
          ErrorEvent(
            'FRB chat exceeded the tool round budget',
            code: 'frb_chat_tool_round_budget_exceeded',
          ),
          DoneEvent(stopReason: 'error', rounds: 1),
        ]);
        final id = await activeSessionId();

        final outcome = await repo.sendMessage(
          sessionId: id,
          ownerUserId: 'user-1',
          content: 'Use a tool',
        );

        expect(outcome, SendOutcome.errored);
        final trace = (await traceStore.recent()).single;
        expect(trace.terminalReason, TerminalReason.streamError);
        expect(trace.spans.first.status, AiSpanStatus.error);
        expect(
          trace.spans.first.attributes,
          containsPair('terminal_reason', 'stream_error'),
        );
      },
    );

    test('records error-only done frames as stream-error traces', () async {
      api.script.add(const DoneEvent(stopReason: 'error', rounds: 1));
      final id = await activeSessionId();

      final outcome = await repo.sendMessage(
        sessionId: id,
        ownerUserId: 'user-1',
        content: 'Q',
      );

      expect(outcome, SendOutcome.errored);
      final messages = await store.listMessages(id);
      expect(messages.last.status, ChatMessageStatus.errored);
      final trace = (await traceStore.recent()).single;
      expect(trace.terminalReason, TerminalReason.streamError);
      expect(trace.spans.first.status, AiSpanStatus.error);
    });
  });
}
