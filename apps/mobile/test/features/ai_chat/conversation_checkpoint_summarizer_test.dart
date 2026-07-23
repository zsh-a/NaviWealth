import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/data/conversation_checkpoint_summarizer.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';

ChatMessage _message({
  required String id,
  required ChatRole role,
  required String content,
  List<ToolInvocation> tools = const <ToolInvocation>[],
}) {
  return ChatMessage(
    id: id,
    sessionId: 'session-1',
    ownerUserId: 'user-1',
    role: role,
    content: content,
    toolCalls: tools,
    status: ChatMessageStatus.complete,
    createdAt: DateTime.utc(2026, 7, 1, 0, int.parse(id.substring(1))),
  );
}

void main() {
  test(
    'deterministic checkpoint quotes evidence and selected decisions',
    () async {
      final messages = <ChatMessage>[
        _message(
          id: 'm1',
          role: ChatRole.user,
          content: '请规划 2026-09-30 前的现金目标。',
        ),
        _message(
          id: 'm2',
          role: ChatRole.assistant,
          content: '我先读取账户。',
          tools: <ToolInvocation>[
            const ToolInvocation(
              id: 'tool-1',
              name: 'get_account',
              input: <String, Object?>{'account_id': 'cash-1'},
              output: <String, Object?>{
                'account_id': 'cash-1',
                'balance': 120000,
                'as_of': '2026-07-01',
              },
            ),
            ToolInvocation(
              id: 'decision-1',
              name: 'ask_user',
              input: const <String, Object?>{},
              output: const <String, Object?>{
                'type': 'decision_request',
                'title': '选择储蓄节奏',
              },
              decisionSelection: DecisionSelection(
                optionId: 'steady',
                label: '稳健',
                reply: '选择稳健方案。',
                selectedAt: DateTime.utc(2026, 7, 1),
              ),
            ),
          ],
        ),
      ];

      final summary =
          await const DeterministicConversationCheckpointSummarizer().summarize(
            ConversationCheckpointSummaryRequest(
              sessionId: 'session-1',
              ownerUserId: 'user-1',
              messages: messages,
            ),
          );

      expect(summary.topic, contains('2026-09-30'));
      expect(summary.verifiedFacts.single, contains('"balance":120000'));
      expect(summary.decisions.single, contains('selected steady: 稳健'));
      expect(summary.entities, contains('account_id:cash-1'));
      expect(summary.timeAnchors, containsAll(['2026-09-30', '2026-07-01']));
      expect(summary.rejectedOptions, isEmpty);
      expect(summary.turnDigest.map((turn) => turn.messageId), ['m1', 'm2']);
    },
  );

  test('fingerprint changes whenever summarized source changes', () {
    final first = <ChatMessage>[
      _message(id: 'm1', role: ChatRole.user, content: '原始内容'),
    ];
    final changed = <ChatMessage>[
      _message(id: 'm1', role: ChatRole.user, content: '修改后的内容'),
    ];

    expect(
      conversationCheckpointFingerprint(first),
      isNot(conversationCheckpointFingerprint(changed)),
    );
  });
}
