import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_output.dart';

/// The first production speech output capability.
///
/// The platform owns the actual voice model and audio routing. This adapter
/// only translates one semantic [OutputSegment] into a
/// [SpeechOutputSession]. It deliberately does not own InteractionSession
/// timing, queueing, or business semantics.
final class SystemSpeechOutput implements SpeechOutput {
  SystemSpeechOutput({FlutterTts? textToSpeech})
    : _textToSpeech = textToSpeech ?? FlutterTts();

  final FlutterTts _textToSpeech;
  Future<SpeechOutputStatus>? _statusFuture;
  bool _active = false;

  @override
  Future<SpeechOutputStatus> status() => _statusFuture ??= _resolveStatus();

  Future<SpeechOutputStatus> _resolveStatus() async {
    try {
      // Do not wait for an utterance here. This only configures the native
      // plugin so the first session can be started without changing the
      // caller's delivery semantics.
      await _textToSpeech.awaitSpeakCompletion(false);
      return const SpeechOutputStatus(SpeechOutputAvailability.ready);
    } on Object catch (error) {
      return SpeechOutputStatus(
        SpeechOutputAvailability.unsupported,
        reason: 'System text-to-speech is unavailable: $error',
      );
    }
  }

  @override
  Future<SpeechOutputSession> speak(SpeechOutputRequest request) async {
    if (request.segment.text.trim().isEmpty) {
      throw StateError('Speech output cannot speak an empty segment');
    }
    if (_active) {
      throw StateError('Another system speech output session is active');
    }

    final available = await status();
    if (!available.isReady) {
      throw StateError(available.reason ?? 'System text-to-speech unavailable');
    }

    _active = true;
    final session = _SystemSpeechOutputSession(
      textToSpeech: _textToSpeech,
      request: request,
      onFinished: () => _active = false,
    );
    try {
      await session.start();
      return session;
    } on Object {
      _active = false;
      rethrow;
    }
  }
}

final class _SystemSpeechOutputSession implements SpeechOutputSession {
  _SystemSpeechOutputSession({
    required FlutterTts textToSpeech,
    required SpeechOutputRequest request,
    required void Function() onFinished,
  }) : _textToSpeech = textToSpeech,
       _request = request,
       _onFinished = onFinished;

  final FlutterTts _textToSpeech;
  final SpeechOutputRequest _request;
  final void Function() _onFinished;
  final StreamController<SpeechOutputEvent> _events =
      StreamController<SpeechOutputEvent>();

  bool _started = false;
  bool _paused = false;
  bool _pausedEventSent = false;
  bool _resumedEventSent = true;
  bool _closed = false;
  Future<void>? _ending;

  @override
  Stream<SpeechOutputEvent> get events => _events.stream;

  Future<void> start() async {
    _textToSpeech.setStartHandler(_onNativeStart);
    _textToSpeech.setCompletionHandler(_onNativeComplete);
    _textToSpeech.setPauseHandler(_onNativePause);
    _textToSpeech.setContinueHandler(_onNativeContinue);
    _textToSpeech.setCancelHandler(_onNativeCancel);
    _textToSpeech.setErrorHandler(_onNativeError);

    await _setLanguageForText(_request.segment.text);
    try {
      // Completion is delivered through the plugin callbacks. Awaiting the
      // plugin's speak Future would make Android's pause callback look like a
      // completed utterance, which would incorrectly mark the segment done.
      await _textToSpeech.speak(_request.segment.text);
    } on Object {
      await _finish(interrupted: true);
      rethrow;
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
      await _textToSpeech.setLanguage(language);
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
      await _textToSpeech.pause();
    } on Object {
      _paused = false;
      rethrow;
    }
    _emitPaused();
  }

  @override
  Future<void> resume() async {
    if (_closed || !_paused) return;
    _paused = false;
    try {
      // flutter_tts resumes the native utterance when speak receives the
      // same text after pause (AVSpeechSynthesizer on iOS and the plugin's
      // pauseText cursor on Android).
      await _textToSpeech.speak(_request.segment.text);
    } on Object {
      await _finish(interrupted: true);
      rethrow;
    }
    _emitResumed();
  }

  @override
  Future<void> stop() => _stop(interrupted: true);

  @override
  Future<void> cancel() => _stop(interrupted: true);

  void _onNativeStart() {
    if (_closed) return;
    _emitStarted();
  }

  void _onNativeComplete() {
    if (_closed || _paused) return;
    unawaited(_finish(interrupted: false));
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
    if (_paused) {
      _emitPaused();
      return;
    }
    unawaited(_finish(interrupted: true));
  }

  void _onNativeError(dynamic _) {
    if (_closed) return;
    unawaited(_finish(interrupted: true));
  }

  Future<void> _stop({required bool interrupted}) {
    if (_closed) return Future<void>.value();
    return _ending ??= _stopInternal(interrupted: interrupted);
  }

  Future<void> _stopInternal({required bool interrupted}) async {
    _paused = false;
    try {
      await _textToSpeech.stop();
    } finally {
      await _finish(interrupted: interrupted);
    }
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

  Future<void> _finish({required bool interrupted}) async {
    if (_closed) return;
    _closed = true;
    _onFinished();
    if (!interrupted) {
      _events.add(
        SpeechOutputSegmentDelivered(
          stamp: _request.stamp,
          segmentId: _request.segment.id,
        ),
      );
    }
    _events.add(
      SpeechOutputStopped(stamp: _request.stamp, interrupted: interrupted),
    );
    await _events.close();
  }
}

bool _containsCjk(String text) => RegExp(r'[\u3400-\u9fff]').hasMatch(text);

SpeechOutput createSpeechOutput() => SystemSpeechOutput();
