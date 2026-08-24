import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/interaction/agent_event_adapter.dart';
import 'package:naviwealth/app/interaction/interaction_session_coordinator.dart';
import 'package:naviwealth/app/interaction/speech_output_bridge.dart';
import 'package:naviwealth/core/ai/contracts/chat_events.dart';
import 'package:naviwealth/core/ai/session/delivery_ledger.dart';
import 'package:naviwealth/core/ai/session/interaction_ids.dart';
import 'package:naviwealth/core/ai/session/interaction_state.dart';
import 'package:naviwealth/core/speech/speech_output.dart';

void main() {
  test(
    'plays queued segments in order and finishes after Agent Done',
    () async {
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
      );
      coordinator.startTurn(InteractionInputOrigin.voice);
      final output = _FakeSpeechOutput();
      final bridge = SerializedSpeechOutputBridge(
        speechOutput: output,
        coordinator: coordinator,
      );
      const first = OutputSegment(id: 'segment-1', text: '第一段。');
      const second = OutputSegment(id: 'segment-2', text: '第二段。');
      final epoch = coordinator.state.responseEpoch;

      coordinator.queueOutputSegment(first);
      bridge.enqueue(first);
      coordinator.queueOutputSegment(second);
      bridge.enqueue(second);
      await _flush();
      expect(output.requests, hasLength(1));

      await bridge.finish(epoch, interrupted: false);
      expect(coordinator.state.outputLane, isNot(InteractionOutputLane.idle));

      output.sessions.first.complete();
      await _flush();
      expect(output.requests, hasLength(2));
      expect(coordinator.state.deliveryLedger.deliveredText, '第一段。');

      output.sessions[1].complete();
      await _flush();
      expect(coordinator.state.deliveryLedger.deliveredText, '第一段。第二段。');
      expect(coordinator.state.outputLane, InteractionOutputLane.idle);
      expect(
        coordinator.state.lastContextProjection?.deliveredText,
        '第一段。第二段。',
      );

      await bridge.close();
      await coordinator.close();
    },
  );

  test(
    'candidate pause and committed epoch discard stop old playback',
    () async {
      final coordinator = InteractionSessionCoordinator(
        sessionId: const SessionId('session-1'),
      );
      coordinator.startTurn(InteractionInputOrigin.voice);
      coordinator.outputPlaybackStarted();
      final output = _FakeSpeechOutput();
      final bridge = SerializedSpeechOutputBridge(
        speechOutput: output,
        coordinator: coordinator,
      );
      const segment = OutputSegment(id: 'segment-1', text: '旧回答。');
      final staleEpoch = coordinator.state.responseEpoch;
      coordinator.queueOutputSegment(segment);
      bridge.enqueue(segment);
      await _flush();

      coordinator.speechStarted();
      expect(coordinator.state.bargeInPhase, BargeInPhase.candidate);
      await bridge.pause();
      expect(output.sessions.single.paused, isTrue);
      coordinator.updateTranscript('等等', isFinal: false);
      expect(coordinator.state.responseEpoch, staleEpoch.next());

      await bridge.interrupt(staleEpoch: staleEpoch);
      expect(output.sessions.single.cancelled, isTrue);
      expect(coordinator.state.outputLane, InteractionOutputLane.interrupted);

      const nextSegment = OutputSegment(id: 'segment-2', text: '新回答。');
      coordinator.queueOutputSegment(nextSegment);
      bridge.enqueue(nextSegment);
      await _flush();
      expect(output.requests, hasLength(2));
      expect(output.requests.last.stamp.epoch.value, 1);

      await bridge.close();
      await coordinator.close();
    },
  );

  test('stale queued output is never sent to the provider', () async {
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
    );
    coordinator.startTurn(InteractionInputOrigin.voice);
    final output = _FakeSpeechOutput();
    final bridge = SerializedSpeechOutputBridge(
      speechOutput: output,
      coordinator: coordinator,
    );
    const oldSegment = OutputSegment(id: 'old', text: '旧回答');
    const newSegment = OutputSegment(id: 'new', text: '新回答');
    final oldEpoch = coordinator.state.responseEpoch;

    coordinator.queueOutputSegment(oldSegment);
    bridge.enqueue(oldSegment);
    await _flush();
    coordinator.startTurn(InteractionInputOrigin.touch);
    await bridge.interrupt(staleEpoch: oldEpoch);
    await _flush();

    coordinator.queueOutputSegment(newSegment);
    bridge.enqueue(newSegment);
    await _flush();
    expect(output.requests, hasLength(2));
    expect(output.requests.last.segment.id, 'new');
    expect(output.requests.last.stamp.epoch.value, 1);

    await bridge.close();
    await coordinator.close();
  });

  test('AgentEventAdapter closes the bridge after the final segment', () async {
    final coordinator = InteractionSessionCoordinator(
      sessionId: const SessionId('session-1'),
    );
    final turnId = coordinator.startTurn(InteractionInputOrigin.voice);
    final output = _FakeSpeechOutput();
    final bridge = SerializedSpeechOutputBridge(
      speechOutput: output,
      coordinator: coordinator,
    );
    final adapter = AgentEventAdapter(
      coordinator,
      onOutputSegment: bridge.enqueue,
      onOutputFinished: (epoch, {required interrupted}) =>
          unawaited(bridge.finish(epoch, interrupted: interrupted)),
    );

    adapter.accept(
      const TextEvent('本月支出 7230 元。'),
      turnId: turnId,
      epoch: const ResponseEpoch.initial(),
    );
    adapter.accept(
      const DoneEvent(stopReason: 'end_turn', rounds: 1),
      turnId: turnId,
      epoch: const ResponseEpoch.initial(),
    );
    await _flush();
    expect(output.requests, hasLength(1));
    expect(coordinator.state.outputLane, isNot(InteractionOutputLane.idle));

    output.sessions.single.complete();
    await _flush();
    expect(coordinator.state.outputLane, InteractionOutputLane.idle);
    expect(coordinator.state.deliveryLedger.deliveredText, '本月支出 7230 元。');

    await bridge.close();
    await coordinator.close();
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

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
  bool paused = false;
  bool cancelled = false;

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
  Future<void> pause() async {
    paused = true;
    if (!_events.isClosed) {
      _events.add(SpeechOutputPaused(stamp: request.stamp));
    }
  }

  @override
  Future<void> resume() async {
    paused = false;
    if (!_events.isClosed) {
      _events.add(SpeechOutputResumed(stamp: request.stamp));
    }
  }

  @override
  Future<void> stop() => cancel();

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (_events.isClosed) return;
    _events.add(SpeechOutputStopped(stamp: request.stamp, interrupted: true));
    await _events.close();
  }
}
