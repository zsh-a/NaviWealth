import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import '../ai/local/embedding/model_install_paths.dart';
import '../ai/local/embedding/model_manifest.dart';
import 'speech_recognizer.dart';

/// Android native Zipformer recognizer.
///
/// The Android AudioRecord bridge owns capture, PCM conversion, VAD and
/// sherpa-onnx decode. This adapter receives only semantic speech and text
/// events. It is opt-in; the platform on-device SpeechRecognizer remains the
/// default provider.
final class AndroidSherpaSpeechRecognizer implements SpeechRecognizer {
  AndroidSherpaSpeechRecognizer({
    required this.resolvePaths,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Stream<Object?> Function()? eventStream,
    this.isBundleComplete,
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

  final Future<ModelInstallPaths> Function() resolvePaths;

  /// Test seam for the large model bundle check. Production uses
  /// [ModelInstallPaths.isComplete].
  final Future<bool> Function(ModelInstallPaths, ModelBundle)? isBundleComplete;

  final MethodChannel _methodChannel;
  final Stream<Object?> Function() _eventStream;

  @override
  Future<SpeechRecognizerStatus> status() async {
    final paths = await resolvePaths();
    final bundle = streamingZipformerLargeCtcZhBundle();
    final complete =
        await (isBundleComplete?.call(paths, bundle) ??
            paths.isComplete(bundle));
    return SpeechRecognizerStatus(
      complete
          ? SpeechRecognizerAvailability.ready
          : SpeechRecognizerAvailability.modelNotInstalled,
      reason: complete ? null : 'Streaming Zipformer model is not installed',
    );
  }

  @override
  Future<SpeechRecognitionSession> start() async {
    final paths = await resolvePaths();
    final bundle = streamingZipformerLargeCtcZhBundle();
    final complete =
        await (isBundleComplete?.call(paths, bundle) ??
            paths.isComplete(bundle));
    if (!complete) {
      throw const SpeechRecognitionException(
        SpeechRecognitionErrorCode.modelNotInstalled,
        'Streaming Zipformer model is not installed',
      );
    }

    final session = _AndroidSherpaSpeechRecognitionSession(
      methodChannel: _methodChannel,
      eventStream: _eventStream,
      modelDirectory: paths.dirForBundle(bundle).path,
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

class _AndroidSherpaSpeechRecognitionSession
    implements SpeechRecognitionSession {
  _AndroidSherpaSpeechRecognitionSession({
    required MethodChannel methodChannel,
    required Stream<Object?> Function() eventStream,
    required this.modelDirectory,
  }) : _methodChannel = methodChannel {
    _events = StreamController<SpeechRecognitionEvent>.broadcast(
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
  final String modelDirectory;
  late final StreamController<SpeechRecognitionEvent> _events;
  final Queue<SpeechRecognitionEvent> _pendingEvents =
      Queue<SpeechRecognitionEvent>();
  late final StreamSubscription<Object?> _platformSubscription;
  Future<void>? _ending;
  bool _closed = false;
  bool _terminal = false;
  bool _streamClosed = false;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod<Object?>('start', <String, Object?>{
        'model_directory': modelDirectory,
      });
    } on PlatformException catch (error) {
      throw _speechExceptionFromPlatform(error);
    } on Object catch (error) {
      throw SpeechRecognitionException(
        SpeechRecognitionErrorCode.runtimeUnavailable,
        'Unable to start the native Zipformer recognizer',
        cause: error,
      );
    }
  }

  void _onPlatformEvent(Object? value) {
    if (_closed) return;
    final map = _objectMap(value);
    switch (map?['type']) {
      case 'speech_started':
        _emit(
          SpeechRecognitionEvent(
            text: '',
            isFinal: false,
            speechStarted: true,
            startedAt: _dateTimeFromMillis(map?['started_at_ms']),
          ),
        );
      case 'transcript':
        final text = map?['text'];
        if (text is! String) return;
        _emit(
          SpeechRecognitionEvent(text: text, isFinal: map?['is_final'] == true),
        );
      case 'capture_stopped':
        unawaited(_finish());
      case 'error':
        final errorCode = map?['code'];
        final message = map?['message'];
        _events.addError(
          SpeechRecognitionException(
            _errorCodeFromWire(errorCode),
            message is String ? message : 'Native Zipformer recognition failed',
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

  void _emit(SpeechRecognitionEvent event) {
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
      // The host may already have gone away during Activity teardown.
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
      // The start call may have failed before the native session existed.
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

DateTime? _dateTimeFromMillis(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
    : null;

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
  error.message ?? 'Native Zipformer recognition failed',
  cause: error.details,
);

SpeechRecognitionException _speechExceptionFromObject(Object error) {
  if (error is PlatformException) return _speechExceptionFromPlatform(error);
  return SpeechRecognitionException(
    SpeechRecognitionErrorCode.runtimeUnavailable,
    'Native Zipformer event stream failed',
    cause: error,
  );
}

SpeechRecognitionErrorCode _errorCodeFromWire(Object? value) => switch (value) {
  'permission_denied' => SpeechRecognitionErrorCode.permissionDenied,
  'recorder_unavailable' => SpeechRecognitionErrorCode.recorderUnavailable,
  'session_busy' => SpeechRecognitionErrorCode.sessionBusy,
  'model_not_installed' => SpeechRecognitionErrorCode.modelNotInstalled,
  _ => SpeechRecognitionErrorCode.runtimeUnavailable,
};
