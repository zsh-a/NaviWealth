import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/chat_events.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/speech/speech_input.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';
import 'package:naviwealth/core/speech/speech_recognizer_provider.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_turn_metadata.dart';
import 'package:naviwealth/features/ai_chat/state/chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sessionId = 'session-1';
  const ownerUserId = 'owner-1';
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer(
    _FakeChatRepository repo, {
    SpeechInput? speechInput,
  }) {
    final container = ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWithValue(ownerUserId),
        chatRepositoryProvider.overrideWith((_) async => repo),
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (speechInput != null)
          speechInputProvider.overrideWithValue(speechInput),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'send() transitions idle -> streaming -> idle and blocks overlap',
    () async {
      final repo = _FakeChatRepository()..gate = Completer<void>();
      final container = makeContainer(repo);
      final provider = chatControllerProvider(sessionId);
      final sub = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(provider.notifier);
      expect(container.read(provider).isIdle, isTrue);

      final sending = controller.send('  hello  ', systemContext: 'ctx');
      expect(container.read(provider).isStreaming, isTrue);

      await repo.entered.future;
      expect(repo.sendCount, 1);
      expect(repo.lastSessionId, sessionId);
      expect(repo.lastOwnerUserId, ownerUserId);
      expect(repo.lastContent, 'hello');
      expect(repo.lastSystemContext, 'ctx');
      expect(repo.lastCancelToken, isNotNull);

      await controller.send('second');
      expect(repo.sendCount, 1);

      repo.gate!.complete();
      await sending;

      expect(container.read(provider).isIdle, isTrue);
      expect(container.read(provider).cancelToken, isNull);
    },
  );

  test('send() returns to idle when the repository throws', () async {
    final repo = _FakeChatRepository()..failWith = StateError('stream failed');
    final container = makeContainer(repo);
    final provider = chatControllerProvider(sessionId);
    final sub = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await expectLater(
      container.read(provider.notifier).send('hello'),
      throwsA(isA<StateError>()),
    );

    expect(repo.sendCount, 1);
    expect(container.read(provider).isIdle, isTrue);
    expect(container.read(provider).cancelToken, isNull);
  });

  test('send() preserves the input origin in turn metadata', () async {
    final repo = _FakeChatRepository();
    final container = makeContainer(repo);
    final provider = chatControllerProvider(sessionId);

    await container
        .read(provider.notifier)
        .send(
          '记录今天午饭 38 元',
          turnMetadata: const ChatTurnMetadata(
            inputOrigin: InteractionInputOrigin.voice,
          ),
        );

    expect(repo.lastTurnMetadata.inputOrigin, InteractionInputOrigin.voice);
  });

  test('voice interaction metadata preserves the original turn for resume', () {
    final metadata = ChatTurnMetadata(
      interactionResponse: AiInteractionResponse(
        interactionId: 'interaction-1',
        action: AiInteractionAction.approve,
        value: true,
        respondedAt: DateTime.utc(2026, 8, 24),
      ),
      resumeTurnId: 'turn-1',
    );

    expect(metadata.resumeTurnId, 'turn-1');
  });

  test('send() is a no-op without content or active user', () async {
    final repo = _FakeChatRepository();
    final container = ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWithValue(null),
        chatRepositoryProvider.overrideWith((_) async => repo),
      ],
    );
    addTearDown(container.dispose);
    final provider = chatControllerProvider(sessionId);
    final sub = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await container.read(provider.notifier).send('   ');
    await container.read(provider.notifier).send('hello');

    expect(repo.sendCount, 0);
    expect(container.read(provider).isIdle, isTrue);
  });

  test('cancel() cancels the in-flight token', () async {
    final repo = _FakeChatRepository()..gate = Completer<void>();
    final container = makeContainer(repo);
    final provider = chatControllerProvider(sessionId);
    final sub = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final sending = container.read(provider.notifier).send('hello');
    await repo.entered.future;

    container.read(provider.notifier).cancel();

    expect(repo.lastCancelToken?.isCancelled, isTrue);
    repo.gate!.complete();
    await sending;
    expect(container.read(provider).isIdle, isTrue);
  });

  test(
    'startVoice commits the semantic transcript through the chat session',
    () async {
      final repo = _FakeChatRepository();
      final input = _FakeSpeechInput();
      final container = makeContainer(repo, speechInput: input);
      final provider = chatControllerProvider(sessionId);
      final sub = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(provider.notifier);
      await controller.startVoice(systemContext: '当前页面上下文');
      expect(input.started, isTrue);
      expect(container.read(provider).voiceActive, isTrue);

      input.session.emit(
        const SpeechInputTranscript(text: '记录今天午饭 38 元', isFinal: true),
      );
      await _flush();
      await _flush();

      expect(repo.lastContent, '记录今天午饭 38 元');
      expect(repo.lastSystemContext, '当前页面上下文');
      expect(repo.lastTurnMetadata.inputOrigin, InteractionInputOrigin.voice);

      await controller.stopVoice();
      await _flush();
      expect(input.session.stopped, isTrue);
      expect(container.read(provider).voiceActive, isFalse);
    },
  );

  test(
    'voice capsule state follows live transcript and cancellation',
    () async {
      final repo = _FakeChatRepository();
      final input = _FakeSpeechInput();
      final container = makeContainer(repo, speechInput: input);
      final provider = chatControllerProvider(sessionId);
      final sub = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(provider.notifier);
      await controller.startVoice();
      input.session.emit(
        const SpeechInputTranscript(text: '看看本月支出', isFinal: false),
      );
      await _flush();

      expect(container.read(provider).voiceCapsuleVisible, isTrue);
      expect(container.read(provider).voiceTranscript, '看看本月支出');
      expect(
        container.read(provider).voiceInputLane,
        InteractionInputLane.speechDetected,
      );

      await controller.cancelVoice();

      expect(input.session.cancelled, isTrue);
      expect(container.read(provider).voiceCapsuleVisible, isFalse);
      expect(container.read(provider).voiceTranscript, isEmpty);
      expect(
        container.read(provider).voiceInputLane,
        InteractionInputLane.idle,
      );
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _FakeChatRepository implements ChatRepository {
  int sendCount = 0;
  Completer<void>? gate;
  Object? failWith;
  final Completer<void> entered = Completer<void>();

  String? lastSessionId;
  String? lastOwnerUserId;
  String? lastContent;
  String? lastSystemContext;
  CancelToken? lastCancelToken;
  ChatTurnMetadata lastTurnMetadata = const ChatTurnMetadata.empty();

  @override
  Future<SendOutcome> sendMessage({
    required String sessionId,
    required String ownerUserId,
    required String content,
    String? systemContext,
    String? model,
    CancelToken? cancelToken,
    ChatTurnMetadata turnMetadata = const ChatTurnMetadata.empty(),
    void Function(AiChatEvent event)? onAiChatEvent,
  }) async {
    sendCount += 1;
    lastSessionId = sessionId;
    lastOwnerUserId = ownerUserId;
    lastContent = content;
    lastSystemContext = systemContext;
    lastCancelToken = cancelToken;
    lastTurnMetadata = turnMetadata;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return SendOutcome.completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSpeechInput implements SpeechInput {
  final session = _FakeSpeechInputSession();
  bool started = false;

  @override
  Future<SpeechRecognizerStatus> status() async =>
      const SpeechRecognizerStatus(SpeechRecognizerAvailability.ready);

  @override
  Future<SpeechInputSession> start() async {
    started = true;
    return session;
  }
}

final class _FakeSpeechInputSession implements SpeechInputSession {
  final StreamController<SpeechInputEvent> _events =
      StreamController<SpeechInputEvent>.broadcast();
  bool stopped = false;
  bool cancelled = false;

  @override
  Stream<SpeechInputEvent> get events => _events.stream;

  void emit(SpeechInputEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> stop() async {
    stopped = true;
    emit(const SpeechInputEnded(cancelled: false));
    await _flush();
    await _events.close();
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_events.isClosed) {
      emit(const SpeechInputEnded(cancelled: true));
      await _events.close();
    }
  }
}
