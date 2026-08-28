import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/messages/message_bubble.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('interrupted assistant text exposes a continue action', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      _message(
        content: '已经接收的部分回复',
        status: ChatMessageStatus.errored,
        stopReason: ChatStopReason.error,
      ),
    );

    expect(find.text('连接中断，回复未完整接收'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('empty failed assistant turn does not offer continuation', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      _message(
        content: '',
        status: ChatMessageStatus.errored,
        stopReason: ChatStopReason.error,
      ),
    );

    expect(find.text('连接中断，回复未完整接收'), findsNothing);
    expect(find.text('继续'), findsNothing);
  });

  testWidgets('pending interaction does not offer truncation continuation', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      _message(
        content: '请先选择一个方案。',
        status: ChatMessageStatus.complete,
        stopReason: ChatStopReason.requiresInteraction,
      ),
    );

    expect(find.text('继续'), findsNothing);
    expect(find.text('回答未完整接收'), findsNothing);
  });
}

ChatMessage _message({
  required String content,
  required ChatMessageStatus status,
  required ChatStopReason stopReason,
}) => ChatMessage(
  id: 'assistant-1',
  sessionId: 'session-1',
  ownerUserId: 'user-1',
  role: ChatRole.assistant,
  content: content,
  status: status,
  stopReason: stopReason,
  createdAt: DateTime.utc(2026, 8, 24),
);

Future<void> _pumpMessage(WidgetTester tester, ChatMessage message) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: FScaffold(
            childPad: false,
            child: MessageBubble(
              sessionId: message.sessionId,
              message: message,
              animateIn: false,
            ),
          ),
        ),
      ),
    ),
  );
}
