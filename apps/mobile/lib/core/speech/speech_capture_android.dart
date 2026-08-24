import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import 'speech_capture.dart';

/// Android AudioRecord capture bridge for native ASR/VAD consumers.
///
/// Android owns AudioRecord, voice communication processing, and the native
/// PCM ring buffer. This Dart adapter only carries semantic lifecycle and
/// aggregate buffer events; it never receives audio frames.
final class AndroidNativeAudioCapture implements SpeechCapture {
  AndroidNativeAudioCapture({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Stream<Object?> Function()? eventStream,
  }) : _methodChannel =
           methodChannel ??
           const MethodChannel('com.naviwealth/audio_capture_android'),
       _eventStream =
           eventStream ??
           (() =>
               (eventChannel ??
                       const EventChannel(
                         'com.naviwealth/audio_capture_android/events',
                       ))
                   .receiveBroadcastStream()
                   .cast<Object?>());

  final MethodChannel _methodChannel;
  final Stream<Object?> Function() _eventStream;

  @override
  Future<SpeechCaptureStatus> status() async {
    try {
      final value = await _methodChannel.invokeMethod<Object?>('status');
      return _statusFromPlatform(value);
    } on PlatformException catch (error) {
      throw _exceptionFromPlatform(error);
    } on Object catch (error) {
      throw SpeechCaptureException(
        SpeechCaptureErrorCode.runtimeUnavailable,
        'Unable to query Android native audio capture',
        cause: error,
      );
    }
  }

  @override
  Future<SpeechCaptureSession> start() async {
    final session = _AndroidSpeechCaptureSession(
      methodChannel: _methodChannel,
      eventStream: _eventStream,
    );
    try {
      await session.start();
      return session;
    } on Object {
      await session.close();
      rethrow;
    }
  }
}

class _AndroidSpeechCaptureSession implements SpeechCaptureSession {
  _AndroidSpeechCaptureSession({
    required MethodChannel methodChannel,
    required Stream<Object?> Function() eventStream,
  }) : _methodChannel = methodChannel {
    _events = StreamController<SpeechCaptureEvent>.broadcast(
      sync: true,
      onListen: _flushPending,
    );
    _platformSubscription = eventStream().listen(
      _onPlatformEvent,
      onError: _onPlatformError,
      onDone: _onPlatformDone,
      cancelOnError: false,
    );
  }

  final MethodChannel _methodChannel;
  late final StreamController<SpeechCaptureEvent> _events;
  final Queue<SpeechCaptureEvent> _pendingEvents = Queue<SpeechCaptureEvent>();
  late final StreamSubscription<Object?> _platformSubscription;
  Future<void>? _ending;
  bool _closed = false;
  bool _terminal = false;
  bool _streamClosed = false;

  @override
  Stream<SpeechCaptureEvent> get events => _events.stream;

  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod<Object?>('start');
    } on PlatformException catch (error) {
      throw _exceptionFromPlatform(error);
    } on Object catch (error) {
      throw SpeechCaptureException(
        SpeechCaptureErrorCode.runtimeUnavailable,
        'Unable to start Android native audio capture',
        cause: error,
      );
    }
  }

  void _onPlatformEvent(Object? value) {
    if (_closed) return;
    final map = _objectMap(value);
    switch (map?['type']) {
      case 'capture_started':
        _emit(SpeechCaptureStarted(capabilities: _capabilitiesFromMap(map!)));
      case 'speech_started':
        _emit(
          SpeechCaptureSpeechStarted(
            startedAt: _dateTimeFromMillis(map?['started_at_ms']),
            vadMode: map?['vad_mode'] is String
                ? map!['vad_mode']! as String
                : null,
          ),
        );
      case 'speech_stopped':
        _emit(
          SpeechCaptureSpeechStopped(
            stoppedAt: _dateTimeFromMillis(map?['stopped_at_ms']),
            durationMs: _intValue(map?['duration_ms']),
            vadMode: map?['vad_mode'] is String
                ? map!['vad_mode']! as String
                : null,
          ),
        );
      case 'capture_stopped':
        _emit(
          SpeechCaptureStopped(
            cancelled: map?['cancelled'] == true,
            capturedBytes: _intValue(map?['captured_bytes']),
            bufferedBytes: _intValue(map?['buffered_bytes']),
            droppedBytes: _intValue(map?['dropped_bytes']),
            readErrors: _intValue(map?['read_errors']),
          ),
        );
        unawaited(_finish());
      case 'error':
        _emit(
          SpeechCaptureError(
            code: _errorCodeFromWire(map?['code']),
            message: map?['message'] is String
                ? map!['message']! as String
                : 'Android native audio capture failed',
          ),
        );
    }
  }

  void _onPlatformError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    final exception = _exceptionFromObject(error);
    _emit(SpeechCaptureError(code: exception.code, message: exception.message));
    unawaited(_finish());
  }

  void _onPlatformDone() {
    unawaited(_finish());
  }

  void _emit(SpeechCaptureEvent event) {
    if (_closed) return;
    if (_events.hasListener) {
      _events.add(event);
    } else {
      _pendingEvents.addLast(event);
    }
  }

  void _flushPending() {
    while (_pendingEvents.isNotEmpty && !_streamClosed) {
      _events.add(_pendingEvents.removeFirst());
    }
    _closeStreamIfReady();
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
    try {
      await _methodChannel.invokeMethod<Object?>(cancelled ? 'cancel' : 'stop');
    } on MissingPluginException {
      // Native host teardown can remove the channel before Dart closes the
      // session. The semantic session still needs to be closed locally.
    } on PlatformException catch (error) {
      if (!_closed) {
        _emit(
          SpeechCaptureError(
            code: _errorCodeFromWire(error.code),
            message: error.message ?? 'Android native audio capture failed',
          ),
        );
      }
    } finally {
      await _finish();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await _methodChannel.invokeMethod<Object?>('cancel');
    } on Object {
      // The host may already be detached. Closing the semantic stream remains
      // necessary so a pending microphone lease cannot be retained in Dart.
    } finally {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (_terminal) return;
    _closed = true;
    _terminal = true;
    await _platformSubscription.cancel();
    _closeStreamIfReady();
  }

  void _closeStreamIfReady() {
    if (!_terminal || !_events.hasListener || _streamClosed) return;
    _streamClosed = true;
    unawaited(_events.close());
  }
}

SpeechCaptureStatus _statusFromPlatform(Object? value) {
  final map = _objectMap(value);
  final availability = switch (map?['availability']) {
    'ready' => SpeechCaptureAvailability.ready,
    'permission_denied' => SpeechCaptureAvailability.permissionDenied,
    _ => SpeechCaptureAvailability.unsupported,
  };
  return SpeechCaptureStatus(
    availability,
    reason: map?['reason'] is String ? map!['reason']! as String : null,
    capabilities: availability == SpeechCaptureAvailability.ready
        ? _capabilitiesFromMap(map!)
        : null,
  );
}

SpeechCaptureCapabilities _capabilitiesFromMap(Map<Object?, Object?> map) =>
    SpeechCaptureCapabilities(
      sampleRateHz: _intValue(map['sample_rate_hz']),
      channelCount: _intValue(map['channel_count']),
      encoding: map['encoding'] is String
          ? map['encoding']! as String
          : 'pcm16le',
      ringCapacityBytes: _intValue(map['ring_capacity_bytes']),
      aecAvailable: map['aec_available'] == true,
      noiseSuppressionAvailable: map['ns_available'] == true,
      automaticGainControlAvailable: map['agc_available'] == true,
      aecEnabled: map['aec_enabled'] == true,
      noiseSuppressionEnabled: map['ns_enabled'] == true,
      automaticGainControlEnabled: map['agc_enabled'] == true,
      vadMode: map['vad_mode'] is String ? map['vad_mode']! as String : 'none',
      vadFrameDurationMs: _intValue(map['vad_frame_duration_ms']),
      vadMinSpeechFrames: _intValue(map['vad_min_speech_frames']),
      vadMinSilenceFrames: _intValue(map['vad_min_silence_frames']),
    );

DateTime? _dateTimeFromMillis(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
    : null;

int _intValue(Object? value) => value is int ? value : 0;

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) return value;
  if (value is Map) {
    return <Object?, Object?>{
      for (final entry in value.entries) entry.key: entry.value,
    };
  }
  return null;
}

SpeechCaptureException _exceptionFromPlatform(PlatformException error) =>
    SpeechCaptureException(
      _errorCodeFromWire(error.code),
      error.message ?? 'Android native audio capture failed',
      cause: error.details,
    );

SpeechCaptureException _exceptionFromObject(Object error) {
  if (error is PlatformException) return _exceptionFromPlatform(error);
  return SpeechCaptureException(
    SpeechCaptureErrorCode.runtimeUnavailable,
    'Android native audio capture event stream failed',
    cause: error,
  );
}

SpeechCaptureErrorCode _errorCodeFromWire(Object? value) => switch (value) {
  'permission_denied' => SpeechCaptureErrorCode.permissionDenied,
  'recorder_unavailable' => SpeechCaptureErrorCode.recorderUnavailable,
  'session_busy' => SpeechCaptureErrorCode.sessionBusy,
  _ => SpeechCaptureErrorCode.runtimeUnavailable,
};
