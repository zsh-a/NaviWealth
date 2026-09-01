import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_error.dart';
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

  testWidgets('failed trailing assistant turn exposes a retry action', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      _message(
        content: '已经接收的部分回复',
        status: ChatMessageStatus.errored,
        stopReason: ChatStopReason.error,
      ),
      isLastAssistant: true,
    );

    expect(find.text('重新生成'), findsOneWidget);
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

  testWidgets('configuration errors show a localized repair message', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      _message(
        content: '',
        status: ChatMessageStatus.errored,
        stopReason: ChatStopReason.error,
        errorMessage: kChatErrorAuthentication,
      ),
      withAccessibilityScope: true,
    );

    expect(find.text('模型服务商拒绝了访问，请检查 API Key 或权限。'), findsOneWidget);
    expect(find.text('添加模型服务商'), findsOneWidget);
  });
}

ChatMessage _message({
  required String content,
  required ChatMessageStatus status,
  required ChatStopReason stopReason,
  String? errorMessage,
}) => ChatMessage(
  id: 'assistant-1',
  sessionId: 'session-1',
  ownerUserId: 'user-1',
  role: ChatRole.assistant,
  content: content,
  status: status,
  errorMessage: errorMessage,
  stopReason: stopReason,
  createdAt: DateTime.utc(2026, 8, 24),
);

Future<void> _pumpMessage(
  WidgetTester tester,
  ChatMessage message, {
  bool isLastAssistant = false,
  bool withAccessibilityScope = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        builder: (context, child) => withAccessibilityScope
            ? FAccessibilityScope(
                data: const FAccessibility(
                  accessibleNavigation: false,
                  motion: FAccessibilityMotion.disabled,
                  focusHighlight: false,
                ),
                child: child!,
              )
            : child!,
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: FScaffold(
            childPad: false,
            child: MessageBubble(
              sessionId: message.sessionId,
              message: message,
              isLastAssistant: isLastAssistant,
              animateIn: false,
            ),
          ),
        ),
      ),
    ),
  );
}
