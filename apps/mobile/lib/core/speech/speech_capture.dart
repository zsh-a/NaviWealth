/// Native audio capture capability used by a future in-process ASR/VAD engine.
///
/// This contract intentionally exposes no PCM frames. Audio stays in the
/// platform/native hot path; Dart receives only capability, lifecycle, and
/// aggregate buffer events, and native VAD speech boundary events.
library;

enum SpeechCaptureAvailability { ready, permissionDenied, unsupported }

enum SpeechCaptureErrorCode {
  permissionDenied,
  recorderUnavailable,
  runtimeUnavailable,
  sessionBusy,
}

class SpeechCaptureException implements Exception {
  const SpeechCaptureException(this.code, this.message, {this.cause});

  final SpeechCaptureErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class SpeechCaptureCapabilities {
  const SpeechCaptureCapabilities({
    required this.sampleRateHz,
    required this.channelCount,
    required this.encoding,
    required this.ringCapacityBytes,
    required this.aecAvailable,
    required this.noiseSuppressionAvailable,
    required this.automaticGainControlAvailable,
    this.aecEnabled = false,
    this.noiseSuppressionEnabled = false,
    this.automaticGainControlEnabled = false,
    this.vadMode = 'none',
    this.vadFrameDurationMs = 0,
    this.vadMinSpeechFrames = 0,
    this.vadMinSilenceFrames = 0,
  });

  final int sampleRateHz;
  final int channelCount;
  final String encoding;
  final int ringCapacityBytes;
  final bool aecAvailable;
  final bool noiseSuppressionAvailable;
  final bool automaticGainControlAvailable;
  final bool aecEnabled;
  final bool noiseSuppressionEnabled;
  final bool automaticGainControlEnabled;
  final String vadMode;
  final int vadFrameDurationMs;
  final int vadMinSpeechFrames;
  final int vadMinSilenceFrames;

  bool get vadAvailable => vadMode != 'none';
}

class SpeechCaptureStatus {
  const SpeechCaptureStatus(
    this.availability, {
    this.reason,
    this.capabilities,
  });

  final SpeechCaptureAvailability availability;
  final String? reason;
  final SpeechCaptureCapabilities? capabilities;

  bool get isReady => availability == SpeechCaptureAvailability.ready;
}

sealed class SpeechCaptureEvent {
  const SpeechCaptureEvent();
}

final class SpeechCaptureStarted extends SpeechCaptureEvent {
  const SpeechCaptureStarted({required this.capabilities});

  final SpeechCaptureCapabilities capabilities;
}

/// Native VAD detected a sustained speech interval.
///
/// This event contains no audio data. InteractionSession may use it as the
/// first phase of a two-stage barge-in candidate before a transcript exists.
final class SpeechCaptureSpeechStarted extends SpeechCaptureEvent {
  const SpeechCaptureSpeechStarted({this.startedAt, this.vadMode});

  final DateTime? startedAt;
  final String? vadMode;
}

/// Native VAD detected the end of a sustained speech interval.
final class SpeechCaptureSpeechStopped extends SpeechCaptureEvent {
  const SpeechCaptureSpeechStopped({
    this.stoppedAt,
    required this.durationMs,
    this.vadMode,
  });

  final DateTime? stoppedAt;
  final int durationMs;
  final String? vadMode;
}

final class SpeechCaptureStopped extends SpeechCaptureEvent {
  const SpeechCaptureStopped({
    required this.cancelled,
    required this.capturedBytes,
    required this.bufferedBytes,
    required this.droppedBytes,
    required this.readErrors,
  });

  final bool cancelled;
  final int capturedBytes;
  final int bufferedBytes;
  final int droppedBytes;
  final int readErrors;
}

final class SpeechCaptureError extends SpeechCaptureEvent {
  const SpeechCaptureError({required this.code, required this.message});

  final SpeechCaptureErrorCode code;
  final String message;
}

abstract interface class SpeechCaptureSession {
  Stream<SpeechCaptureEvent> get events;

  Future<void> stop();

  Future<void> cancel();
}

/// Audio capability above platform-specific AudioRecord/AudioUnit details.
///
/// The current Android implementation is a native hot-path skeleton for the
/// later Sherpa/native ASR backend. The production Android system ASR remains
/// exposed through [SpeechRecognizer] and does not use this capture contract.
abstract interface class SpeechCapture {
  Future<SpeechCaptureStatus> status();

  Future<SpeechCaptureSession> start();
}
