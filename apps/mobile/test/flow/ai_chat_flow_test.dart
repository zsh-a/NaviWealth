// Flow / Task test: "Ask the AI" - Task #6 in docs/development/testing-strategy.md.
//
// This boots the real app shell, opens the shell-level AI sheet, sends a
// question through the visible composer, and renders the resulting user /
// assistant exchange. The model turn is faked at the chat-controller seam so
// the flow stays headless and deterministic while still covering the real
// sheet, composer, and conversation widgets.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/state/chat_controller.dart';
import 'package:naviwealth/features/ai_chat/state/chat_session_scope.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

class _ScriptedChatController extends ChatController {
  _ScriptedChatController({
    required super.ref,
    required super.sessionId,
    required this.onSend,
  });

  final Future<void> Function(String content, {String? systemContext}) onSend;

  @override
  Future<void> send(String content, {String? systemContext}) {
    return onSend(content, systemContext: systemContext);
  }
}

void main() {
  group('Task: Ask the AI', () {
    testWidgets('user asks a question from the shell AI sheet', (tester) async {
      const sessionId = 'flow-ai-session';
      const question = 'What needs attention today?';
      const answer = 'Your flow test answer is grounded in local data.';
      final messages = StreamController<List<ChatMessage>>.broadcast();
      var sentQuestion = '';

      await bootApp(
        tester,
        extraOverrides: [
          authStateProvider.overrideWithValue(const AuthLocalOnly()),
          activeUserIdProvider.overrideWithValue(kLocalOnlyUserId),
          defaultChatSessionProvider.overrideWith((ref, ownerUserId) async {
            return sessionId;
          }),
          chatMessagesStreamProvider.overrideWith((ref, id) async* {
            yield const <ChatMessage>[];
            yield* messages.stream;
          }),
          chatControllerProvider.overrideWith((ref, id) {
            return _ScriptedChatController(
              ref: ref,
              sessionId: id,
              onSend: (content, {systemContext}) async {
                sentQuestion = content;
                final now = DateTime.utc(2026, 6, 19, 8);
                messages.add([
                  ChatMessage(
                    id: 'user-message',
                    sessionId: id,
                    ownerUserId: kLocalOnlyUserId,
                    role: ChatRole.user,
                    content: content,
                    status: ChatMessageStatus.complete,
                    createdAt: now,
                  ),
                  ChatMessage(
                    id: 'assistant-message',
                    sessionId: id,
                    ownerUserId: kLocalOnlyUserId,
                    role: ChatRole.assistant,
                    content: answer,
                    status: ChatMessageStatus.complete,
                    createdAt: now.add(const Duration(milliseconds: 1)),
                  ),
                ]);
              },
            );
          }),
          journalEntriesWithPostingsStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          allAccountsStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
      );
      addTearDown(messages.close);

      final shell = AppShell(tester)..expectMounted();
      await shell.openAi();

      final ai = AiChatSheetObject(tester);
      ai.expectReady();
      await ai.ask(question);

      expect(sentQuestion, question);
      ai.expectExchange(question: question, answer: answer);
      await closeApp(tester);
    }, tags: 'flow');
  });
}
