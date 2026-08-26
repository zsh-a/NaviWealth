import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/interaction/interaction_session_coordinator.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/session/delivery_ledger.dart';
import 'package:naviwealth/core/ai/session/interaction_events.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';
import 'package:naviwealth/core/ai/session/interruption_policy.dart';
import 'package:naviwealth/core/speech/speech_input.dart';
import 'package:naviwealth/core/speech/speech_output.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';

void main() {
  test('projects reducer state through the host callback', () async {
    InteractionState? projected;
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      onStateChanged: (state) => projected = state,
    );

    coordinator.startTurn(InteractionInputOrigin.voice);
    coordinator.updateTranscript('记一笔午饭', isFinal: false);

    expect(projected, same(coordinator.state));
    expect(projected?.transcript, '记一笔午饭');
    expect(projected?.inputLane, InteractionInputLane.speechDetected);
    await coordinator.close();
  });

  test(
    'Coordinator assigns one global sequence and commits valid barge-in',
    () async {
      ResponseEpoch? staleEpoch;
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
        onEpochAdvanced: (epoch) => staleEpoch = epoch,
        clock: () => DateTime.utc(2026, 8, 24),
      );

      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.agentTextGenerated('本月消费 12430 元。');
      coordinator.queueOutputSegment(
        const OutputSegment(id: 'segment-1', text: '本月消费 12430 元。'),
      );
      coordinator.outputPlaybackStarted();
      final beforeCandidate = coordinator.state.sequence;

      coordinator.speechStarted();
      expect(coordinator.state.outputLane, InteractionOutputLane.paused);
      expect(coordinator.state.bargeInPhase, BargeInPhase.candidate);

      coordinator.updateTranscript('等等，不算房租。', isFinal: false);

      expect(coordinator.state.responseEpoch.value, 1);
      expect(coordinator.state.transcript, '等等，不算房租。');
      expect(coordinator.state.sequence, greaterThan(beforeCandidate));
      expect(staleEpoch?.value, 0);

      // Explicitly replay a late old-epoch event through the Coordinator seam.
      coordinator.dispatch(
        (stamp) => AgentTextGenerated(stamp: stamp, text: 'stale'),
        epoch: const ResponseEpoch.initial(),
      );
      expect(coordinator.state.generatedText, isEmpty);

      await coordinator.close();
    },
  );

  test(
    'typed HITL voice text does not bypass the on-screen confirmation path',
    () async {
      final requests = <InteractionTurnRequest>[];
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
        onTurnCommitted: (request) async => requests.add(request),
      );
      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.agentWaitingForInteraction(
        AiInteractionEnvelope(
          interactionId: 'typed-1',
          kind: AiInteractionKind.approval,
          mode: AiInteractionMode.typed,
          status: AiInteractionStatus.pending,
          title: '输入确认文本',
          createdAt: DateTime.utc(2026, 8, 24),
          resumeKind: AiInteractionResumeKind.chatTurn,
          confirmation: const AiInteractionConfirmation(requiredText: '执行'),
        ),
      );

      await coordinator.commitInput('执行');

      expect(coordinator.state.pendingInteraction, isNotNull);
      expect(requests, isEmpty);
      await coordinator.close();
    },
  );

  test(
    'projects SpeechOutput delivery and rejects stale provider events',
    () async {
      const sessionId = SessionId('session-1');
      final coordinator = InteractionSessionCoordinator(sessionId: sessionId);
      final turnId = coordinator.startTurn(InteractionInputOrigin.voice);
      const epoch = ResponseEpoch.initial();
      coordinator.queueOutputSegment(
        const OutputSegment(id: 'segment-1', text: '本月消费 12430 元。'),
      );
      final providerStamp = InteractionStamp(
        sessionId: sessionId,
        turnId: turnId,
        epoch: epoch,
        sequence: 1,
      );

      coordinator.acceptSpeechOutputEvent(
        SpeechOutputStarted(stamp: providerStamp, segmentId: 'segment-1'),
      );
      coordinator.acceptSpeechOutputEvent(
        SpeechOutputSegmentDelivered(
          stamp: providerStamp,
          segmentId: 'segment-1',
        ),
      );
      expect(coordinator.state.outputLane, InteractionOutputLane.playing);
      expect(coordinator.state.deliveryLedger.deliveredText, '本月消费 12430 元。');

      coordinator.acceptSpeechOutputEvent(
        SpeechOutputStopped(stamp: providerStamp, interrupted: false),
      );
      expect(coordinator.state.outputLane, InteractionOutputLane.idle);
      expect(
        coordinator.state.lastContextProjection?.deliveredText,
        '本月消费 12430 元。',
      );

      coordinator.outputPlaybackStarted();
      coordinator.speechStarted();
      coordinator.updateTranscript('等等', isFinal: false);
      expect(coordinator.state.responseEpoch.value, 1);
      final staleOutputStamp = InteractionStamp(
        sessionId: sessionId,
        turnId: turnId,
        epoch: epoch,
        sequence: 99,
      );
      coordinator.acceptSpeechOutputEvent(
        SpeechOutputStopped(stamp: staleOutputStamp, interrupted: false),
      );
      expect(coordinator.state.outputLane, InteractionOutputLane.interrupted);

      await coordinator.close();
    },
  );

  test('pending interaction preserves its durable resume token', () async {
    final requests = <InteractionTurnRequest>[];
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      onTurnCommitted: (request) async => requests.add(request),
    );
    coordinator.startTurn(InteractionInputOrigin.voice);
    final interaction = AiInteractionEnvelope(
      interactionId: 'interaction-1',
      kind: AiInteractionKind.approval,
      mode: AiInteractionMode.oneTap,
      status: AiInteractionStatus.pending,
      title: '确认操作',
      createdAt: DateTime.utc(2026, 8, 24),
      resumeKind: AiInteractionResumeKind.chatTurn,
      resumeToken: 'durable-turn-1',
    );
    coordinator.agentWaitingForInteraction(interaction);

    final response = AiInteractionResponse(
      interactionId: interaction.interactionId,
      action: AiInteractionAction.approve,
      value: true,
      respondedAt: DateTime.utc(2026, 8, 24),
      respondedBy: 'voice',
    );
    await coordinator.commitInput('确认', interactionResponse: response);

    expect(requests, hasLength(1));
    expect(requests.single.resumeTurnId, 'durable-turn-1');
    expect(requests.single.interactionResponse, same(response));
    await coordinator.close();
  });

  test(
    'short barge-in candidate resumes output when speech input ends',
    () async {
      final input = _FakeSpeechInput();
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
        speechInput: input,
        bargeInPolicy: const BargeInPolicy(
          minimumSpeechDuration: Duration(seconds: 1),
        ),
      );
      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.queueOutputSegment(
        const OutputSegment(id: 'segment-1', text: '继续回答。'),
      );
      coordinator.outputPlaybackStarted();

      await coordinator.startVoice();
      input.session.emit(const SpeechInputSpeechStarted());
      await _flush();
      expect(coordinator.state.bargeInPhase, BargeInPhase.candidate);
      expect(coordinator.state.outputLane, InteractionOutputLane.paused);

      input.session.emit(
        const SpeechInputSpeechStopped(duration: Duration(milliseconds: 100)),
      );
      await _flush();
      expect(coordinator.state.bargeInPhase, BargeInPhase.none);
      expect(coordinator.state.outputLane, InteractionOutputLane.playing);

      await coordinator.stopVoice();
      await _flush();

      expect(coordinator.state.outputLane, InteractionOutputLane.playing);
      await coordinator.close();
    },
  );

  test('cancelVoice ends the input session without finalizing it', () async {
    final input = _FakeSpeechInput();
    bool? endedAsCancelled;
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      speechInput: input,
      onSpeechEnded: ({required cancelled}) => endedAsCancelled = cancelled,
    );

    await coordinator.startVoice();
    await coordinator.cancelVoice();

    expect(input.session.cancelled, isTrue);
    expect(endedAsCancelled, isTrue);
    await coordinator.close();
  });

  test('full-duplex input opens a fresh turn for the next utterance', () async {
    ResponseEpoch? staleEpoch;
    final input = _FakeSpeechInput(
      statusValue: const SpeechRecognizerStatus(
        SpeechRecognizerAvailability.ready,
        capabilities: SpeechRecognizerCapabilities(
          supportsBargeIn: true,
          nativeAudioPath: true,
          vad: true,
          fullDuplex: true,
        ),
      ),
    );
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      speechInput: input,
      onEpochAdvanced: (epoch) => staleEpoch = epoch,
    );

    await coordinator.startVoice();
    final firstTurn = coordinator.state.activeTurnId;
    input.session.emit(const SpeechInputSpeechStarted());
    input.session.emit(
      const SpeechInputTranscript(text: '第一句话', isFinal: true),
    );
    await _flush();
    expect(coordinator.state.responseEpoch.value, 0);

    input.session.emit(const SpeechInputSpeechStarted());
    await _flush();

    expect(coordinator.state.responseEpoch.value, 1);
    expect(coordinator.state.activeTurnId, isNot(firstTurn));
    expect(coordinator.state.inputLane, InteractionInputLane.speechDetected);
    expect(staleEpoch?.value, 0);

    await coordinator.cancelVoice();
    await coordinator.close();
  });

  test('cancelled native input discards a barge-in candidate', () async {
    final input = _FakeSpeechInput();
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      speechInput: input,
    );
    coordinator.startTurn(InteractionInputOrigin.voice);
    coordinator.queueOutputSegment(
      const OutputSegment(id: 'segment-1', text: '继续回答。'),
    );
    coordinator.outputPlaybackStarted();

    await coordinator.startVoice();
    input.session.emit(const SpeechInputSpeechStarted());
    await _flush();
    expect(coordinator.state.bargeInPhase, BargeInPhase.candidate);

    await coordinator.cancelVoice();
    expect(coordinator.state.responseEpoch.value, 0);
    expect(coordinator.state.bargeInPhase, BargeInPhase.none);
    expect(coordinator.state.outputLane, InteractionOutputLane.playing);

    await coordinator.close();
  });

  test('blocks model-missing voice start before opening a session', () async {
    final input = _FakeSpeechInput(
      statusValue: const SpeechRecognizerStatus(
        SpeechRecognizerAvailability.modelNotInstalled,
      ),
    );
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      speechInput: input,
    );

    await expectLater(
      coordinator.startVoice(),
      throwsA(
        isA<SpeechRecognitionException>().having(
          (error) => error.code,
          'code',
          SpeechRecognitionErrorCode.modelNotInstalled,
        ),
      ),
    );
    expect(input.started, isFalse);
    await coordinator.close();
  });

  test('forwards asynchronous speech failures as stable exceptions', () async {
    SpeechRecognitionException? received;
    final input = _FakeSpeechInput();
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
      speechInput: input,
      onSpeechError: (error, _) => received = error,
    );

    await coordinator.startVoice();
    input.session.emitError(
      const SpeechRecognitionException(
        SpeechRecognitionErrorCode.recorderUnavailable,
        'device-specific recorder detail',
      ),
    );
    await _flush();

    expect(received?.code, SpeechRecognitionErrorCode.recorderUnavailable);
    expect(received?.message, 'device-specific recorder detail');
    await coordinator.close();
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _FakeSpeechInput implements SpeechInput {
  _FakeSpeechInput({
    this.statusValue = const SpeechRecognizerStatus(
      SpeechRecognizerAvailability.ready,
    ),
  });

  final session = _FakeSpeechInputSession();
  final SpeechRecognizerStatus statusValue;
  bool started = false;

  @override
  Future<SpeechRecognizerStatus> status() async => statusValue;

  @override
  Future<SpeechInputSession> start() async {
    started = true;
    return session;
  }
}

final class _FakeSpeechInputSession implements SpeechInputSession {
  final StreamController<SpeechInputEvent> _events =
      StreamController<SpeechInputEvent>.broadcast(sync: true);
  bool _closed = false;
  bool cancelled = false;

  @override
  Stream<SpeechInputEvent> get events => _events.stream;

  void emit(SpeechInputEvent event) {
    if (!_closed) _events.add(event);
  }

  void emitError(Object error) {
    if (!_closed) _events.addError(error, StackTrace.current);
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    emit(const SpeechInputEnded(cancelled: false));
    _closed = true;
    await _events.close();
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    cancelled = true;
    emit(const SpeechInputEnded(cancelled: true));
    _closed = true;
    await _events.close();
  }
}
