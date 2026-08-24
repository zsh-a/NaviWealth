import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_turn_metadata.dart';
import 'package:naviwealth/features/ai_chat/state/chat_controller.dart';

void main() {
  const sessionId = 'session-1';
  const ownerUserId = 'owner-1';

  ProviderContainer makeContainer(_FakeChatRepository repo) {
    final container = ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWithValue(ownerUserId),
        chatRepositoryProvider.overrideWith((_) async => repo),
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
}

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
