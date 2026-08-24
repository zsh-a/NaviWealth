import 'dart:async';

import 'speech_recognizer.dart';

/// Semantic speech input events. Audio frames never cross this seam.
sealed class SpeechInputEvent {
  const SpeechInputEvent();
}

/// Optional event emitted by a native full-duplex engine when VAD detects
/// speech. The current push-to-talk recognizer does not synthesize it.
final class SpeechInputSpeechStarted extends SpeechInputEvent {
  const SpeechInputSpeechStarted({this.startedAt});

  final DateTime? startedAt;
}

final class SpeechInputTranscript extends SpeechInputEvent {
  const SpeechInputTranscript({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

final class SpeechInputEnded extends SpeechInputEvent {
  const SpeechInputEnded({required this.cancelled});

  final bool cancelled;
}

abstract interface class SpeechInputSession {
  Stream<SpeechInputEvent> get events;

  Future<void> stop();

  Future<void> cancel();
}

/// Input capability above the existing SpeechRecognizer contract.
///
/// This is intentionally not another ASR/provider contract. Concrete ASR
/// implementations continue to use [SpeechRecognizer] and are adapted here
/// into session-level semantic events.
abstract interface class SpeechInput {
  Future<SpeechRecognizerStatus> status();

  Future<SpeechInputSession> start();
}

/// Adapts the current managed recognizer into the InteractionSession input
/// capability. Future native full-duplex engines can implement [SpeechInput]
/// directly and emit [SpeechInputSpeechStarted] without changing consumers.
class RecognizerSpeechInput implements SpeechInput {
  const RecognizerSpeechInput(this._recognizer);

  final SpeechRecognizer _recognizer;

  @override
  Future<SpeechRecognizerStatus> status() => _recognizer.status();

  @override
  Future<SpeechInputSession> start() async =>
      _RecognizerSpeechInputSession(await _recognizer.start());
}

class _RecognizerSpeechInputSession implements SpeechInputSession {
  _RecognizerSpeechInputSession(this._delegate) {
    _subscription = _delegate.events.listen(
      _onEvent,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final SpeechRecognitionSession _delegate;
  final StreamController<SpeechInputEvent> _events =
      StreamController<SpeechInputEvent>.broadcast();

  late final StreamSubscription<SpeechRecognitionEvent> _subscription;
  Future<void>? _ending;
  bool _closed = false;
  bool _cancelled = false;

  @override
  Stream<SpeechInputEvent> get events => _events.stream;

  void _onEvent(SpeechRecognitionEvent event) {
    if (_closed) return;
    _events.add(
      SpeechInputTranscript(text: event.text, isFinal: event.isFinal),
    );
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _events.addError(error, stackTrace);
  }

  void _onDone() {
    unawaited(_finish());
  }

  @override
  Future<void> stop() => _end(cancelled: false);

  @override
  Future<void> cancel() => _end(cancelled: true);

  Future<void> _end({required bool cancelled}) {
    if (_closed) return Future<void>.value();
    return _ending ??= _endInternal(cancelled: cancelled);
  }

  Future<void> _endInternal({required bool cancelled}) async {
    _cancelled = cancelled;
    try {
      if (cancelled) {
        await _delegate.cancel();
      } else {
        await _delegate.stop();
        // The managed recognizer publishes its final transcript immediately
        // before stop completes. Give the broadcast stream one turn before
        // closing this adapter.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    _events.add(SpeechInputEnded(cancelled: _cancelled));
    await _events.close();
  }
}
