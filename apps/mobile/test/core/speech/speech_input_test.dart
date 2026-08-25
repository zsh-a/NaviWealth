import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_input.dart';
import 'package:naviwealth/core/speech/speech_recognizer.dart';

void main() {
  test('adapts recognizer events into semantic SpeechInput events', () async {
    final recognizer = _FakeRecognizer();
    final input = RecognizerSpeechInput(recognizer);
    final session = await input.start();
    final events = <SpeechInputEvent>[];
    final subscription = session.events.listen(events.add);

    recognizer.session.emitSpeechStarted();
    recognizer.session.emit('吃饭', isFinal: false);
    recognizer.session.emit('吃饭了吗', isFinal: true);
    recognizer.session.emitSpeechStopped(
      duration: const Duration(milliseconds: 240),
    );
    await session.stop();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(5));
    expect(events[0], isA<SpeechInputSpeechStarted>());
    expect((events[1] as SpeechInputTranscript).text, '吃饭');
    expect((events[1] as SpeechInputTranscript).isFinal, isFalse);
    expect((events[2] as SpeechInputTranscript).text, '吃饭了吗');
    expect((events[2] as SpeechInputTranscript).isFinal, isTrue);
    expect(events[3], isA<SpeechInputSpeechStopped>());
    expect(
      (events[3] as SpeechInputSpeechStopped).duration,
      const Duration(milliseconds: 240),
    );
    expect((events[4] as SpeechInputEnded).cancelled, isFalse);

    await subscription.cancel();
  });

  test('cancel propagates without emitting a final transcript', () async {
    final recognizer = _FakeRecognizer();
    final session = await RecognizerSpeechInput(recognizer).start();
    final events = <SpeechInputEvent>[];
    final subscription = session.events.listen(events.add);

    recognizer.session.emit('草稿', isFinal: false);
    await session.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect((events.first as SpeechInputTranscript).text, '草稿');
    expect((events.last as SpeechInputEnded).cancelled, isTrue);
    expect(recognizer.session.stopCalled, isFalse);
    expect(recognizer.session.cancelCalled, isTrue);

    await subscription.cancel();
  });

  test(
    'native lifecycle cancellation reaches the semantic input session',
    () async {
      final recognizer = _FakeRecognizer();
      final session = await RecognizerSpeechInput(recognizer).start();
      final events = <SpeechInputEvent>[];
      final subscription = session.events.listen(events.add);

      recognizer.session.emitSessionEnded(cancelled: true);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single, isA<SpeechInputEnded>());
      expect((events.single as SpeechInputEnded).cancelled, isTrue);

      await subscription.cancel();
    },
  );
}

class _FakeRecognizer implements SpeechRecognizer {
  final session = _FakeRecognitionSession();

  @override
  Future<SpeechRecognizerStatus> status() async =>
      const SpeechRecognizerStatus(SpeechRecognizerAvailability.ready);

  @override
  Future<SpeechRecognitionSession> start() async => session;
}

class _FakeRecognitionSession implements SpeechRecognitionSession {
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();
  bool stopCalled = false;
  bool cancelCalled = false;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  void emit(String text, {required bool isFinal}) {
    _events.add(SpeechRecognitionEvent(text: text, isFinal: isFinal));
  }

  void emitSpeechStarted() {
    _events.add(
      const SpeechRecognitionEvent(
        text: '',
        isFinal: false,
        speechStarted: true,
      ),
    );
  }

  void emitSpeechStopped({required Duration duration}) {
    _events.add(
      SpeechRecognitionEvent(
        text: '',
        isFinal: false,
        speechStopped: true,
        speechDuration: duration,
      ),
    );
  }

  void emitSessionEnded({required bool cancelled}) {
    _events.add(
      SpeechRecognitionEvent(
        text: '',
        isFinal: false,
        sessionEnded: true,
        cancelled: cancelled,
      ),
    );
    unawaited(_events.close());
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    await _events.close();
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    await _events.close();
  }
}
