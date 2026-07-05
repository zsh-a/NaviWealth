import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/data/context_window.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';

ChatMessage _msg({
  required ChatRole role,
  required String content,
  ChatMessageStatus status = ChatMessageStatus.complete,
  List<ToolInvocation> toolCalls = const <ToolInvocation>[],
}) => ChatMessage(
  id: 'id-${DateTime.now().microsecondsSinceEpoch}-${content.hashCode}',
  sessionId: 'sess',
  ownerUserId: 'u',
  role: role,
  content: content,
  status: status,
  createdAt: DateTime.utc(2026, 1, 1),
  toolCalls: toolCalls,
);

void main() {
  group('buildContextWindow', () {
    test('preserves all turns when comfortably under budget', () {
      final history = [
        _msg(role: ChatRole.user, content: '问题 1'),
        _msg(role: ChatRole.assistant, content: '回答 1'),
        _msg(role: ChatRole.user, content: '问题 2'),
        _msg(role: ChatRole.assistant, content: '回答 2'),
      ];
      final ctx = buildContextWindow(
        history: history,
        pending: '问题 3',
        charBudget: 1000,
      );
      expect(ctx.droppedTurns, 0);
      expect(ctx.wire.map((m) => m.content), [
        '问题 1',
        '回答 1',
        '问题 2',
        '回答 2',
        '问题 3',
      ]);
    });

    test('drops oldest eligible turns when budget exceeded', () {
      final big = 'x' * 500;
      final history = [
        _msg(role: ChatRole.user, content: '$big-1'),
        _msg(role: ChatRole.assistant, content: '$big-2'),
        _msg(role: ChatRole.user, content: '$big-3'),
        _msg(role: ChatRole.assistant, content: '$big-4'),
        _msg(role: ChatRole.user, content: '$big-5'),
        _msg(role: ChatRole.assistant, content: '$big-6'),
      ];
      final ctx = buildContextWindow(
        history: history,
        pending: 'final',
        charBudget: 2200,
        minKept: 4,
      );
      // We always keep the last `minKept` (4) turns plus the pending one.
      expect(ctx.wire.last.content, 'final');
      expect(ctx.wire.length, 5); // 4 kept + 1 pending
      expect(ctx.droppedTurns, 2);
      expect(ctx.wire.map((m) => m.content), [
        '$big-3',
        '$big-4',
        '$big-5',
        '$big-6',
        'final',
      ]);
    });

    test('skips system / error / streaming rows entirely', () {
      final history = [
        _msg(role: ChatRole.system, content: '已折叠 5 条历史'),
        _msg(role: ChatRole.user, content: 'real-1'),
        _msg(
          role: ChatRole.assistant,
          content: '半成品',
          status: ChatMessageStatus.streaming,
        ),
        _msg(role: ChatRole.error, content: '网络错误'),
        _msg(role: ChatRole.assistant, content: 'real-2'),
      ];
      final ctx = buildContextWindow(
        history: history,
        pending: 'next',
        charBudget: 1000,
      );
      expect(ctx.wire.map((m) => m.content), ['real-1', 'real-2', 'next']);
      expect(ctx.droppedTurns, 0);
    });

    test(
      'keeps ask_user decision transcript even when assistant text is empty',
      () {
        final history = [
          _msg(role: ChatRole.user, content: '接下来怎么实现？'),
          _msg(
            role: ChatRole.assistant,
            content: '',
            toolCalls: [
              ToolInvocation(
                id: 'decision-1',
                name: 'ask_user',
                input: <String, Object?>{},
                output: <String, Object?>{
                  'type': 'decision_request',
                  'title': '实现路径选择',
                  'context': '需要在通用 chat agent 架构下继续推进。',
                  'options': <Object?>[
                    <String, Object?>{
                      'id': 'a',
                      'label': '先补上下文',
                      'description': '确保用户选择能被下一轮模型看到。',
                      'recommended': true,
                    },
                    <String, Object?>{
                      'id': 'b',
                      'label': '先做 UI',
                      'description': '先优化展示层。',
                    },
                  ],
                },
                decisionSelection: DecisionSelection(
                  optionId: 'a',
                  label: '先补上下文',
                  reply: '我选择「先补上下文」。请在此方案下继续。',
                  selectedAt: DateTime.utc(2026, 6, 30),
                ),
              ),
            ],
          ),
        ];

        final ctx = buildContextWindow(
          history: history,
          pending: '继续',
          charBudget: 1000,
        );

        expect(ctx.droppedTurns, 0);
        expect(ctx.wire.map((m) => m.role), ['user', 'assistant', 'user']);
        final transcript = ctx.wire[1].content;
        expect(transcript, contains('Decision requested: 实现路径选择'));
        expect(transcript, contains('a: 先补上下文'));
        expect(transcript, contains('Selected option: a (先补上下文)'));
        expect(transcript, contains('User reply: 我选择「先补上下文」。请在此方案下继续。'));
      },
    );
  });
}
