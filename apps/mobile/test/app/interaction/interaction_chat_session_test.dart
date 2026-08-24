import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/interaction/interaction_chat_session.dart';
import 'package:naviwealth/core/ai/contracts/chat_events.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';
import 'package:naviwealth/core/speech/speech_output.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_turn_metadata.dart';

void main() {
  test(
    'routes ChatRepository events through one interaction session',
    () async {
      final repository = _FakeChatRepository(
        events: const <AiChatEvent>[
          TextEvent('本月支出 7230 元。'),
          DoneEvent(stopReason: 'end_turn', rounds: 1),
        ],
      );
      final speechOutput = _FakeSpeechOutput();
      final session = InteractionChatSession(
        repository: repository,
        ownerUserId: 'owner-1',
        sessionId: 'chat-1',
        speechOutput: speechOutput,
      );

      session.startTurn(InteractionInputOrigin.voice);
      session.commitInput('我这个月消费多少？', origin: InteractionInputOrigin.voice);
      await _flush();
      await _flush();

      expect(repository.lastContent, '我这个月消费多少？');
      expect(
        repository.lastTurnMetadata.inputOrigin,
        InteractionInputOrigin.voice,
      );
      expect(session.coordinator.state.generatedText, '本月支出 7230 元。');
      expect(speechOutput.requests, hasLength(1));
      expect(
        session.coordinator.state.executionLane,
        InteractionExecutionLane.done,
      );

      speechOutput.sessions.single.complete();
      await _flush();
      expect(
        session.coordinator.state.deliveryLedger.deliveredText,
        '本月支出 7230 元。',
      );
      expect(session.coordinator.state.outputLane, InteractionOutputLane.idle);

      await session.close();
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository({required this.events});

  final List<AiChatEvent> events;
  String? lastContent;
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
    lastContent = content;
    lastTurnMetadata = turnMetadata;
    for (final event in events) {
      onAiChatEvent?.call(event);
      await _flush();
    }
    return SendOutcome.completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSpeechOutput implements SpeechOutput {
  final List<SpeechOutputRequest> requests = <SpeechOutputRequest>[];
  final List<_FakeSpeechOutputSession> sessions = <_FakeSpeechOutputSession>[];

  @override
  Future<SpeechOutputStatus> status() async =>
      const SpeechOutputStatus(SpeechOutputAvailability.ready);

  @override
  Future<SpeechOutputSession> speak(SpeechOutputRequest request) async {
    requests.add(request);
    final session = _FakeSpeechOutputSession(request);
    sessions.add(session);
    return session;
  }
}

final class _FakeSpeechOutputSession implements SpeechOutputSession {
  _FakeSpeechOutputSession(this.request);

  final SpeechOutputRequest request;
  final StreamController<SpeechOutputEvent> _events =
      StreamController<SpeechOutputEvent>.broadcast();

  @override
  Stream<SpeechOutputEvent> get events => _events.stream;

  void complete() {
    if (_events.isClosed) return;
    _events
      ..add(
        SpeechOutputStarted(
          stamp: request.stamp,
          segmentId: request.segment.id,
        ),
      )
      ..add(
        SpeechOutputSegmentDelivered(
          stamp: request.stamp,
          segmentId: request.segment.id,
        ),
      )
      ..add(SpeechOutputStopped(stamp: request.stamp, interrupted: false));
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() => cancel();

  @override
  Future<void> cancel() async {
    if (_events.isClosed) return;
    _events.add(SpeechOutputStopped(stamp: request.stamp, interrupted: true));
    await _events.close();
  }
}
