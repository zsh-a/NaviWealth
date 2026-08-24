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

    recognizer.session.emit('吃饭', isFinal: false);
    recognizer.session.emit('吃饭了吗', isFinal: true);
    await session.stop();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect((events[0] as SpeechInputTranscript).text, '吃饭');
    expect((events[0] as SpeechInputTranscript).isFinal, isFalse);
    expect((events[1] as SpeechInputTranscript).text, '吃饭了吗');
    expect((events[1] as SpeechInputTranscript).isFinal, isTrue);
    expect((events[2] as SpeechInputEnded).cancelled, isFalse);

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
