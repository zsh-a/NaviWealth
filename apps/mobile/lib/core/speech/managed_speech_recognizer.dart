import 'dart:async';

import 'speech_diagnostics.dart';
import 'speech_recognizer.dart';

/// Adds process-local session ownership and bounded lifetime to a platform
/// recognizer. Microphone plugins are exclusive resources, so a second start
/// fails deterministically instead of racing native initialization.
class ManagedSpeechRecognizer implements SpeechRecognizer {
  ManagedSpeechRecognizer({
    required SpeechRecognizer delegate,
    required SpeechDiagnostics diagnostics,
    this.maxSessionDuration = const Duration(minutes: 5),
  }) : _delegate = delegate,
       _diagnostics = diagnostics;

  final SpeechRecognizer _delegate;
  final SpeechDiagnostics _diagnostics;
  final Duration maxSessionDuration;

  @override
  Future<SpeechRecognizerStatus> status() async {
    final stopwatch = Stopwatch()..start();
    try {
      final status = await _delegate.status();
      if (!status.isReady) {
        _diagnostics.record(
          SpeechDiagnosticEvent(
            kind: SpeechDiagnosticEventKind.statusUnavailable,
            elapsed: stopwatch.elapsed,
            errorCode: status.errorCode,
            availability: status.availability,
          ),
        );
      }
      return status;
    } on Object catch (error) {
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.failed,
          elapsed: stopwatch.elapsed,
          errorCode: error is SpeechRecognitionException
              ? error.code
              : SpeechRecognitionErrorCode.runtimeUnavailable,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<SpeechRecognitionSession> start() async {
    final release = _MicrophoneLease.tryAcquire();
    if (release == null) {
      _diagnostics.record(
        const SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.failed,
          elapsed: Duration.zero,
          errorCode: SpeechRecognitionErrorCode.sessionBusy,
        ),
      );
      throw const SpeechRecognitionException(
        SpeechRecognitionErrorCode.sessionBusy,
        'Another speech recognition session is already active',
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final session = await _delegate.start();
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.started,
          elapsed: stopwatch.elapsed,
        ),
      );
      return _ManagedSpeechRecognitionSession(
        delegate: session,
        diagnostics: _diagnostics,
        stopwatch: stopwatch,
        maxDuration: maxSessionDuration,
        release: release,
      );
    } on SpeechRecognitionException catch (error) {
      release();
      stopwatch.stop();
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.failed,
          elapsed: stopwatch.elapsed,
          errorCode: error.code,
        ),
      );
      rethrow;
    } on Object {
      release();
      stopwatch.stop();
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.failed,
          elapsed: stopwatch.elapsed,
          errorCode: SpeechRecognitionErrorCode.runtimeUnavailable,
        ),
      );
      rethrow;
    }
  }
}

/// Owns the single process-local microphone lease shared by every managed
/// recognizer instance. The returned release callback is idempotent so an
/// error and a later stream completion cannot release a newer session.
class _MicrophoneLease {
  static bool _reserved = false;

  static void Function()? tryAcquire() {
    if (_reserved) return null;
    _reserved = true;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _reserved = false;
    };
  }
}

class _ManagedSpeechRecognitionSession implements SpeechRecognitionSession {
  _ManagedSpeechRecognitionSession({
    required SpeechRecognitionSession delegate,
    required SpeechDiagnostics diagnostics,
    required Stopwatch stopwatch,
    required Duration maxDuration,
    required void Function() release,
  }) : _delegate = delegate,
       _diagnostics = diagnostics,
       _stopwatch = stopwatch,
       _release = release {
    _subscription = delegate.events.listen(
      _onEvent,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    _maxDurationTimer = Timer(
      maxDuration,
      () => unawaited(_end(_SessionEnd.maxDuration)),
    );
  }

  final SpeechRecognitionSession _delegate;
  final SpeechDiagnostics _diagnostics;
  final Stopwatch _stopwatch;
  final void Function() _release;
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();

  late final StreamSubscription<SpeechRecognitionEvent> _subscription;
  late final Timer _maxDurationTimer;
  Future<void>? _ending;
  bool _firstPartialRecorded = false;
  bool _closed = false;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  void _onEvent(SpeechRecognitionEvent event) {
    if (_closed) return;
    if (event.captureStarted) {
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.captureStarted,
          elapsed: event.captureStartupDuration ?? _stopwatch.elapsed,
        ),
      );
    }
    if (!_firstPartialRecorded && event.text.trim().isNotEmpty) {
      _firstPartialRecorded = true;
      _diagnostics.record(
        SpeechDiagnosticEvent(
          kind: SpeechDiagnosticEventKind.firstPartial,
          elapsed: _stopwatch.elapsed,
        ),
      );
    }
    _events.add(event);
    if (event.sessionEnded) {
      // Native hosts can terminate capture because an Activity stopped. The
      // lifecycle event carries cancellation explicitly; do not let the
      // following stream close be misclassified as a successful completion.
      unawaited(
        _finish(
          event.cancelled ? _SessionEnd.cancelled : _SessionEnd.completed,
          cancelSubscription: false,
        ),
      );
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _events.addError(error, stackTrace);
    unawaited(_end(_SessionEnd.failed));
  }

  void _onDone() {
    if (_closed || _ending != null) return;
    unawaited(_finish(_SessionEnd.completed, cancelSubscription: false));
  }

  @override
  Future<void> stop() => _end(_SessionEnd.completed);

  @override
  Future<void> cancel() => _end(_SessionEnd.cancelled);

  Future<void> _end(_SessionEnd end) {
    if (_closed) return Future<void>.value();
    return _ending ??= _endInternal(end);
  }

  Future<void> _endInternal(_SessionEnd end) async {
    try {
      if (end == _SessionEnd.cancelled || end == _SessionEnd.failed) {
        await _delegate.cancel();
      } else {
        await _delegate.stop();
        // The native adapter emits its final transcript immediately before
        // stop completes. Yield once so that event reaches this proxy.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await _finish(end);
    }
  }

  Future<void> _finish(
    _SessionEnd end, {
    bool cancelSubscription = true,
  }) async {
    if (_closed) return;
    _closed = true;
    _maxDurationTimer.cancel();
    _stopwatch.stop();
    if (cancelSubscription) await _subscription.cancel();
    _release();
    _diagnostics.record(
      SpeechDiagnosticEvent(
        kind: switch (end) {
          _SessionEnd.completed => SpeechDiagnosticEventKind.completed,
          _SessionEnd.cancelled => SpeechDiagnosticEventKind.cancelled,
          _SessionEnd.maxDuration => SpeechDiagnosticEventKind.maxDuration,
          _SessionEnd.failed => SpeechDiagnosticEventKind.failed,
        },
        elapsed: _stopwatch.elapsed,
        errorCode: end == _SessionEnd.failed
            ? SpeechRecognitionErrorCode.runtimeUnavailable
            : null,
      ),
    );
    unawaited(_events.close());
  }
}

enum _SessionEnd { completed, cancelled, maxDuration, failed }
