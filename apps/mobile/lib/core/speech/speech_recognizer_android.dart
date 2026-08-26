import 'dart:async';

import 'package:flutter/services.dart';

import 'speech_recognizer.dart';

/// Android's system on-device speech recognizer.
///
/// The Android bridge owns microphone capture and voice-processing setup. This
/// class receives only semantic events over platform channels, so PCM never
/// crosses into Dart. Android API 31+ is required because the provider uses
/// [SpeechRecognizer.createOnDeviceSpeechRecognizer].
final class AndroidOnDeviceSpeechRecognizer
    implements
        SpeechRecognizer,
        SpeechRecognizerPreparation,
        SpeechRecognizerPendingStartCancellation {
  AndroidOnDeviceSpeechRecognizer({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Stream<Object?> Function()? eventStream,
  }) : _methodChannel = methodChannel ?? _defaultMethodChannel,
       _eventStream =
           eventStream ??
           (() => (eventChannel ?? _defaultEventChannel)
               .receiveBroadcastStream()
               .cast<Object?>());

  static const _defaultMethodChannel = MethodChannel(
    'com.naviwealth/speech_android',
  );
  static const _defaultEventChannel = EventChannel(
    'com.naviwealth/speech_android/events',
  );

  final MethodChannel _methodChannel;
  final Stream<Object?> Function() _eventStream;

  /// The platform recognizer is intentionally the low-resource push-to-talk
  /// policy. It owns capture internally and does not expose native VAD, so it
  /// is not advertised as the full-duplex barge-in path.
  static const _capabilities = SpeechRecognizerCapabilities();

  @override
  Future<void> prepare() async {
    // Android's system recognizer is owned by the platform. Querying status
    // lets the platform service initialize lazily without opening capture.
    await status();
  }

  @override
  Future<void> cancelPendingStart() async {
    try {
      await _methodChannel.invokeMethod<Object?>('cancel');
    } on MissingPluginException {
      // Host teardown is already a cancellation.
    } on PlatformException catch (error) {
      throw _speechExceptionFromPlatform(error);
    }
  }

  @override
  Future<SpeechRecognizerStatus> status() async {
    try {
      final value = await _methodChannel.invokeMethod<Object?>('status');
      return _statusFromPlatform(value);
    } on PlatformException catch (error) {
      throw _speechExceptionFromPlatform(error);
    } on Object catch (error) {
      throw SpeechRecognitionException(
        SpeechRecognitionErrorCode.runtimeUnavailable,
        'Unable to query Android on-device speech recognition',
        cause: error,
      );
    }
  }

  @override
  Future<SpeechRecognitionSession> start() async {
    final session = _AndroidSpeechRecognitionSession(
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

SpeechRecognizerStatus _statusFromPlatform(Object? value) {
  final map = _objectMap(value);
  final availability = switch (map?['availability']) {
    'ready' => SpeechRecognizerAvailability.ready,
    'model_not_installed' => SpeechRecognizerAvailability.modelNotInstalled,
    'permission_denied' => SpeechRecognizerAvailability.permissionDenied,
    _ => SpeechRecognizerAvailability.unsupported,
  };
  final reason = map?['reason'];
  return SpeechRecognizerStatus(
    availability,
    reason: reason is String ? reason : null,
    capabilities: AndroidOnDeviceSpeechRecognizer._capabilities,
  );
}

class _AndroidSpeechRecognitionSession implements SpeechRecognitionSession {
  _AndroidSpeechRecognitionSession({
    required MethodChannel methodChannel,
    required Stream<Object?> Function() eventStream,
  }) : _methodChannel = methodChannel,
       _events = StreamController<SpeechRecognitionEvent>() {
    _platformSubscription = eventStream().listen(
      _onPlatformEvent,
      onError: _onPlatformError,
      onDone: _onPlatformDone,
      cancelOnError: false,
    );
  }

  final MethodChannel _methodChannel;
  final StreamController<SpeechRecognitionEvent> _events;
  late final StreamSubscription<Object?> _platformSubscription;
  Future<void>? _ending;
  bool _closed = false;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod<Object?>('start');
    } on PlatformException catch (error) {
      throw _speechExceptionFromPlatform(error);
    } on Object catch (error) {
      throw SpeechRecognitionException(
        SpeechRecognitionErrorCode.runtimeUnavailable,
        'Unable to start Android on-device speech recognition',
        cause: error,
      );
    }
  }

  void _onPlatformEvent(Object? value) {
    if (_closed) return;
    final map = _objectMap(value);
    final type = map?['type'];
    switch (type) {
      case 'speech_started':
        final startedAtMillis = map?['started_at_ms'];
        _events.add(
          SpeechRecognitionEvent(
            text: '',
            isFinal: false,
            speechStarted: true,
            startedAt: startedAtMillis is int
                ? DateTime.fromMillisecondsSinceEpoch(
                    startedAtMillis,
                    isUtc: true,
                  )
                : null,
          ),
        );
      case 'capture_ready':
        final startupDurationMillis = map?['startup_duration_ms'];
        _events.add(
          SpeechRecognitionEvent(
            text: '',
            isFinal: false,
            captureStarted: true,
            captureStartupDuration:
                startupDurationMillis is int && startupDurationMillis >= 0
                ? Duration(milliseconds: startupDurationMillis)
                : null,
          ),
        );
      case 'speech_stopped':
        final stoppedAtMillis = map?['stopped_at_ms'];
        final durationMillis = map?['duration_ms'];
        _events.add(
          SpeechRecognitionEvent(
            text: '',
            isFinal: false,
            speechStopped: true,
            stoppedAt: stoppedAtMillis is int
                ? DateTime.fromMillisecondsSinceEpoch(
                    stoppedAtMillis,
                    isUtc: true,
                  )
                : null,
            speechDuration: durationMillis is int && durationMillis >= 0
                ? Duration(milliseconds: durationMillis)
                : null,
          ),
        );
      case 'transcript':
        final text = map?['text'];
        if (text is! String) return;
        _events.add(
          SpeechRecognitionEvent(text: text, isFinal: map?['is_final'] == true),
        );
      case 'ended':
        _events.add(
          SpeechRecognitionEvent(
            text: '',
            isFinal: false,
            sessionEnded: true,
            cancelled: map?['cancelled'] == true,
          ),
        );
        unawaited(_finish());
      case 'error':
        final errorCode = map?['code'];
        final message = map?['message'];
        _events.addError(
          SpeechRecognitionException(
            _errorCodeFromWire(errorCode),
            message is String ? message : 'Android speech recognition failed',
          ),
        );
        unawaited(_finish());
    }
  }

  void _onPlatformError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _events.addError(_speechExceptionFromObject(error), stackTrace);
    unawaited(_finish());
  }

  void _onPlatformDone() {
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
    try {
      await _methodChannel.invokeMethod<Object?>(cancelled ? 'cancel' : 'stop');
    } on MissingPluginException {
      // The native side may already have gone away during activity teardown.
    } on PlatformException catch (error) {
      if (!_closed) _events.addError(_speechExceptionFromPlatform(error));
    } finally {
      await _finish();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await _methodChannel.invokeMethod<Object?>('cancel');
    } on Object {
      // Session startup failed or the host was already detached. Closing the
      // Dart-side stream is still required to release the managed lease.
    } finally {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (_closed) return;
    _closed = true;
    await _platformSubscription.cancel();
    await _events.close();
  }
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) return value;
  if (value is Map) {
    return <Object?, Object?>{
      for (final entry in value.entries) entry.key: entry.value,
    };
  }
  return null;
}

SpeechRecognitionException _speechExceptionFromPlatform(
  PlatformException error,
) => SpeechRecognitionException(
  _errorCodeFromWire(error.code),
  error.message ?? 'Android speech recognition failed',
  cause: error.details,
);

SpeechRecognitionException _speechExceptionFromObject(Object error) {
  if (error is PlatformException) return _speechExceptionFromPlatform(error);
  return SpeechRecognitionException(
    SpeechRecognitionErrorCode.runtimeUnavailable,
    'Android speech recognition event stream failed',
    cause: error,
  );
}

SpeechRecognitionErrorCode _errorCodeFromWire(Object? value) => switch (value) {
  'permission_denied' => SpeechRecognitionErrorCode.permissionDenied,
  'unsupported' => SpeechRecognitionErrorCode.unsupported,
  'recorder_unavailable' => SpeechRecognitionErrorCode.recorderUnavailable,
  'session_busy' => SpeechRecognitionErrorCode.sessionBusy,
  _ => SpeechRecognitionErrorCode.runtimeUnavailable,
};
