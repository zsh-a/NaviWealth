import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_output.dart';
import 'system_tts_driver.dart';

/// The first production speech output capability.
///
/// The platform owns the actual voice model and audio routing. This adapter
/// only translates one semantic [OutputSegment] into a
/// [SpeechOutputSession]. It deliberately does not own InteractionSession
/// timing, queueing, or business semantics.
final class SystemSpeechOutput implements SpeechOutput {
  SystemSpeechOutput({SystemTtsDriver? driver, FlutterTts? textToSpeech})
    : _driver =
          driver ?? FlutterTtsSystemTtsDriver(textToSpeech ?? FlutterTts());

  final SystemTtsDriver _driver;
  Future<SpeechOutputStatus>? _statusFuture;
  bool _active = false;

  @override
  Future<SpeechOutputStatus> status() => _statusFuture ??= _resolveStatus();

  Future<SpeechOutputStatus> _resolveStatus() async {
    try {
      // Do not wait for an utterance here. This only configures the native
      // plugin so the first session can be started without changing the
      // caller's delivery semantics.
      await _driver.awaitSpeakCompletion(false);
      return const SpeechOutputStatus(SpeechOutputAvailability.ready);
    } on Object {
      return const SpeechOutputStatus(
        SpeechOutputAvailability.unsupported,
        reason: 'System text-to-speech is unavailable',
      );
    }
  }

  @override
  Future<SpeechOutputSession> speak(SpeechOutputRequest request) async {
    if (request.segment.text.trim().isEmpty) {
      throw const SpeechOutputException(
        SpeechOutputErrorCode.synthesisFailed,
        'Speech output cannot speak an empty segment',
      );
    }
    // Reserve the process-wide plugin before the asynchronous status check.
    // Otherwise two callers can both pass the check and start overlapping
    // native utterances.
    if (_active) {
      throw const SpeechOutputException(
        SpeechOutputErrorCode.sessionBusy,
        'Another system speech output session is active',
      );
    }
    _active = true;

    final available = await status();
    if (!available.isReady) {
      _active = false;
      throw SpeechOutputException(
        SpeechOutputErrorCode.engineUnavailable,
        available.reason ?? 'System text-to-speech is unavailable',
      );
    }

    final session = _SystemSpeechOutputSession(
      driver: _driver,
      request: request,
      onFinished: () => _active = false,
    );
    try {
      await session.start();
      return session;
    } on Object {
      // [session.start] has already attempted terminal cleanup. This second
      // assignment is intentionally idempotent for setup failures before the
      // session could emit an event.
      _active = false;
      rethrow;
    }
  }
}

final class _SystemSpeechOutputSession implements SpeechOutputSession {
  _SystemSpeechOutputSession({
    required SystemTtsDriver driver,
    required SpeechOutputRequest request,
    required void Function() onFinished,
  }) : _driver = driver,
       _request = request,
       _onFinished = onFinished;

  final SystemTtsDriver _driver;
  final SpeechOutputRequest _request;
  final void Function() _onFinished;
  final StreamController<SpeechOutputEvent> _events =
      StreamController<SpeechOutputEvent>();

  bool _started = false;
  bool _paused = false;
  bool _pausedEventSent = false;
  bool _resumedEventSent = true;
  bool _closed = false;
  SpeechOutputStopReason? _requestedStopReason;
  Future<void>? _ending;

  @override
  Stream<SpeechOutputEvent> get events => _events.stream;

  Future<void> start() async {
    try {
      _driver.setStartHandler(_onNativeStart);
      _driver.setCompletionHandler(_onNativeComplete);
      _driver.setPauseHandler(_onNativePause);
      _driver.setContinueHandler(_onNativeContinue);
      _driver.setCancelHandler(_onNativeCancel);
      _driver.setErrorHandler(_onNativeError);

      await _setLanguageForText(_request.segment.text);
      // Completion is delivered through the plugin callbacks. Awaiting the
      // plugin's speak Future would make Android's pause callback look like a
      // completed utterance, which would incorrectly mark the segment done.
      await _driver.speak(_request.segment.text);
    } on Object catch (error) {
      final failure = _asSynthesisException(error);
      if (!_closed) {
        await _finish(
          interrupted: true,
          errorCode: failure.code,
          reason: SpeechOutputStopReason.providerError,
        );
      }
      throw failure;
    }

    // Native callbacks are asynchronous. The single-subscription event
    // stream buffers this fallback until the bridge attaches its listener.
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        if (!_started && !_closed) _emitStarted();
      }),
    );
  }

  Future<void> _setLanguageForText(String text) async {
    final language = _containsCjk(text) ? 'zh-CN' : 'en-US';
    try {
      await _driver.setLanguage(language);
    } on Object {
      // A device may not have the requested voice installed. The platform
      // TTS engine's default voice remains a valid fallback.
    }
  }

  @override
  Future<void> pause() async {
    if (_closed || _paused) return;
    _paused = true;
    _pausedEventSent = false;
    _resumedEventSent = false;
    try {
      await _driver.pause();
    } on Object catch (error) {
      _paused = false;
      final failure = _asSynthesisException(error);
      await _finish(
        interrupted: true,
        errorCode: failure.code,
        reason: SpeechOutputStopReason.providerError,
      );
      rethrow;
    }
    _emitPaused();
  }

  @override
  Future<void> resume() async {
    if (_closed || !_paused) return;
    _paused = false;
    try {
      // flutter_tts resumes the native utterance when speak receives the same
      // text after pause (AVSpeechSynthesizer on iOS and the plugin's pause
      // cursor on Android).
      await _driver.speak(_request.segment.text);
    } on Object catch (error) {
      final failure = _asSynthesisException(error);
      await _finish(
        interrupted: true,
        errorCode: failure.code,
        reason: SpeechOutputStopReason.providerError,
      );
      rethrow;
    }
    _emitResumed();
  }

  @override
  Future<void> stop() => _stop(reason: SpeechOutputStopReason.userCancelled);

  @override
  Future<void> cancel() => _stop(reason: SpeechOutputStopReason.interrupted);

  void _onNativeStart() {
    if (_closed) return;
    _emitStarted();
  }

  void _onNativeComplete() {
    if (_closed || _paused) return;
    unawaited(
      _finish(interrupted: false, reason: SpeechOutputStopReason.completed),
    );
  }

  void _onNativePause() {
    if (_closed) return;
    _paused = true;
    _emitPaused();
  }

  void _onNativeContinue() {
    if (_closed) return;
    _paused = false;
    _emitResumed();
  }

  void _onNativeCancel() {
    if (_closed) return;
    unawaited(
      _finish(
        interrupted: true,
        reason: _requestedStopReason ?? SpeechOutputStopReason.interrupted,
      ),
    );
  }

  void _onNativeError(dynamic _) {
    if (_closed) return;
    unawaited(
      _finish(
        interrupted: true,
        errorCode: SpeechOutputErrorCode.synthesisFailed,
        reason: SpeechOutputStopReason.providerError,
      ),
    );
  }

  Future<void> _stop({required SpeechOutputStopReason reason}) {
    if (_closed) return Future<void>.value();
    _requestedStopReason = reason;
    return _ending ??= _stopInternal(reason: reason);
  }

  Future<void> _stopInternal({required SpeechOutputStopReason reason}) async {
    _paused = false;
    Object? failure;
    try {
      await _driver.stop();
    } on Object catch (error) {
      failure = error;
    } finally {
      final error = failure;
      await _finish(
        interrupted: true,
        errorCode: error == null ? null : _asSynthesisException(error).code,
        reason: error == null ? reason : SpeechOutputStopReason.providerError,
      );
    }
    if (failure != null) throw failure;
  }

  void _emitStarted() {
    if (_closed || _started) return;
    _started = true;
    _events.add(
      SpeechOutputStarted(
        stamp: _request.stamp,
        segmentId: _request.segment.id,
      ),
    );
  }

  void _emitPaused() {
    if (_closed || _pausedEventSent) return;
    _pausedEventSent = true;
    _events.add(SpeechOutputPaused(stamp: _request.stamp));
  }

  void _emitResumed() {
    if (_closed || _resumedEventSent) return;
    _resumedEventSent = true;
    _events.add(SpeechOutputResumed(stamp: _request.stamp));
  }

  Future<void> _finish({
    required bool interrupted,
    SpeechOutputErrorCode? errorCode,
    SpeechOutputStopReason? reason,
  }) async {
    if (_closed) return;
    _closed = true;
    _onFinished();
    if (errorCode != null) {
      _events.add(SpeechOutputError(stamp: _request.stamp, code: errorCode));
    }
    if (!interrupted && errorCode == null) {
      _events.add(
        SpeechOutputSegmentDelivered(
          stamp: _request.stamp,
          segmentId: _request.segment.id,
        ),
      );
    }
    _events.add(
      SpeechOutputStopped(
        stamp: _request.stamp,
        interrupted: interrupted,
        reason:
            reason ??
            (errorCode == null
                ? SpeechOutputStopReason.interrupted
                : SpeechOutputStopReason.providerError),
      ),
    );
    // A caller is allowed to cancel before attaching a stream listener. The
    // close future waits for a listener on a single-subscription controller,
    // so awaiting it here would deadlock the output lifecycle.
    unawaited(_events.close());
  }

  SpeechOutputException _asSynthesisException(Object error) =>
      error is SpeechOutputException
      ? error
      : SpeechOutputException(
          SpeechOutputErrorCode.synthesisFailed,
          'System text-to-speech synthesis failed',
          cause: error,
        );
}

bool _containsCjk(String text) => RegExp(r'[\u3400-\u9fff]').hasMatch(text);

SpeechOutput createSpeechOutput() => SystemSpeechOutput();
