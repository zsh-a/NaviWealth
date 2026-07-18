import '../logging/app_logger.dart';
import 'speech_recognizer.dart';

enum SpeechDiagnosticEventKind {
  started,
  firstPartial,
  completed,
  cancelled,
  maxDuration,
  failed,
}

extension on SpeechDiagnosticEventKind {
  String get wire => switch (this) {
    SpeechDiagnosticEventKind.started => 'started',
    SpeechDiagnosticEventKind.firstPartial => 'first_partial',
    SpeechDiagnosticEventKind.completed => 'completed',
    SpeechDiagnosticEventKind.cancelled => 'cancelled',
    SpeechDiagnosticEventKind.maxDuration => 'max_duration',
    SpeechDiagnosticEventKind.failed => 'failed',
  };
}

extension on SpeechRecognitionErrorCode {
  String get wire => switch (this) {
    SpeechRecognitionErrorCode.modelNotInstalled => 'model_not_installed',
    SpeechRecognitionErrorCode.permissionDenied => 'permission_denied',
    SpeechRecognitionErrorCode.recorderUnavailable => 'recorder_unavailable',
    SpeechRecognitionErrorCode.runtimeUnavailable => 'runtime_unavailable',
    SpeechRecognitionErrorCode.sessionBusy => 'session_busy',
  };
}

class SpeechDiagnosticEvent {
  const SpeechDiagnosticEvent({
    required this.kind,
    required this.elapsed,
    this.errorCode,
  });

  final SpeechDiagnosticEventKind kind;
  final Duration elapsed;
  final SpeechRecognitionErrorCode? errorCode;
}

class SpeechDiagnosticsSnapshot {
  const SpeechDiagnosticsSnapshot({
    required this.started,
    required this.completed,
    required this.cancelled,
    required this.failed,
    required this.maxDurationStops,
    this.lastFirstPartialLatency,
    this.lastSessionDuration,
    this.lastErrorCode,
  });

  final int started;
  final int completed;
  final int cancelled;
  final int failed;
  final int maxDurationStops;
  final Duration? lastFirstPartialLatency;
  final Duration? lastSessionDuration;
  final SpeechRecognitionErrorCode? lastErrorCode;
}

abstract interface class SpeechDiagnostics {
  void record(SpeechDiagnosticEvent event);
}

/// Bounded, transcript-free ASR diagnostics.
///
/// Only counters, durations, and stable error enums are retained. Microphone
/// bytes and recognized text never enter this object or [AppLogger].
class SpeechDiagnosticsRecorder implements SpeechDiagnostics {
  SpeechDiagnosticsRecorder({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  var _started = 0;
  var _completed = 0;
  var _cancelled = 0;
  var _failed = 0;
  var _maxDurationStops = 0;
  Duration? _lastFirstPartialLatency;
  Duration? _lastSessionDuration;
  SpeechRecognitionErrorCode? _lastErrorCode;

  SpeechDiagnosticsSnapshot get snapshot => SpeechDiagnosticsSnapshot(
    started: _started,
    completed: _completed,
    cancelled: _cancelled,
    failed: _failed,
    maxDurationStops: _maxDurationStops,
    lastFirstPartialLatency: _lastFirstPartialLatency,
    lastSessionDuration: _lastSessionDuration,
    lastErrorCode: _lastErrorCode,
  );

  @override
  void record(SpeechDiagnosticEvent event) {
    switch (event.kind) {
      case SpeechDiagnosticEventKind.started:
        _started++;
      case SpeechDiagnosticEventKind.firstPartial:
        _lastFirstPartialLatency = event.elapsed;
      case SpeechDiagnosticEventKind.completed:
        _completed++;
        _lastSessionDuration = event.elapsed;
      case SpeechDiagnosticEventKind.cancelled:
        _cancelled++;
        _lastSessionDuration = event.elapsed;
      case SpeechDiagnosticEventKind.maxDuration:
        _maxDurationStops++;
        _completed++;
        _lastSessionDuration = event.elapsed;
      case SpeechDiagnosticEventKind.failed:
        _failed++;
        _lastSessionDuration = event.elapsed;
        _lastErrorCode = event.errorCode;
    }

    final failure = event.kind == SpeechDiagnosticEventKind.failed;
    _logger.event(
      'core.speech.session.${event.kind.wire}',
      level: failure ? AppLogLevel.warning : AppLogLevel.info,
      fields: <String, Object?>{
        'outcome': event.kind.wire,
        'duration_ms': event.elapsed.inMilliseconds,
        if (event.errorCode != null) 'error_code': event.errorCode!.wire,
      },
    );
  }
}
