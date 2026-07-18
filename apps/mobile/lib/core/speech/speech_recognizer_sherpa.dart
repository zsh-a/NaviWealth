import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../ai/local/embedding/model_install_paths.dart';
import '../ai/local/embedding/model_manifest.dart';
import 'speech_audio.dart';
import 'speech_recognizer.dart';
import 'speech_zipformer_config.dart';

SpeechRecognizer createSpeechRecognizer(Ref ref) => SherpaSpeechRecognizer(
  resolvePaths: () => ref.read(modelInstallPathsProvider.future),
);

class SherpaSpeechRecognizer implements SpeechRecognizer {
  SherpaSpeechRecognizer({required this.resolvePaths});

  final Future<ModelInstallPaths> Function() resolvePaths;

  static bool _bindingsInitialized = false;

  @override
  Future<SpeechRecognizerStatus> status() async {
    final paths = await resolvePaths();
    final installed = await paths.isComplete(streamingZipformerZhBundle());
    return SpeechRecognizerStatus(
      installed
          ? SpeechRecognizerAvailability.ready
          : SpeechRecognizerAvailability.modelNotInstalled,
      reason: installed ? null : 'Streaming Zipformer model is not installed',
    );
  }

  @override
  Future<SpeechRecognitionSession> start() async {
    final paths = await resolvePaths();
    final bundle = streamingZipformerZhBundle();
    if (!await paths.isComplete(bundle)) {
      throw const SpeechRecognitionException(
        SpeechRecognitionErrorCode.modelNotInstalled,
        'Streaming Zipformer model is not installed',
      );
    }

    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      throw const SpeechRecognitionException(
        SpeechRecognitionErrorCode.permissionDenied,
        'Microphone permission was denied',
      );
    }
    if (!await recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      await recorder.dispose();
      throw const SpeechRecognitionException(
        SpeechRecognitionErrorCode.recorderUnavailable,
        '16 kHz PCM recording is unavailable on this device',
      );
    }

    sherpa.OnlineRecognizer? recognizer;
    sherpa.OnlineStream? recognitionStream;
    try {
      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }
      final dir = paths.dirForBundle(bundle);
      recognizer = sherpa.OnlineRecognizer(
        streamingZipformerZhConfig(dir.path),
      );
      recognitionStream = recognizer.createStream();
      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: speechInputSampleRate,
          numChannels: 1,
        ),
      );
      return _SherpaSpeechRecognitionSession(
        recorder: recorder,
        recognizer: recognizer,
        recognitionStream: recognitionStream,
        audio: audio,
      );
    } on Object catch (error) {
      recognitionStream?.free();
      recognizer?.free();
      await recorder.dispose();
      if (error is SpeechRecognitionException) rethrow;
      throw SpeechRecognitionException(
        SpeechRecognitionErrorCode.runtimeUnavailable,
        'Unable to start the on-device speech recognizer',
        cause: error,
      );
    }
  }
}

class _SherpaSpeechRecognitionSession implements SpeechRecognitionSession {
  _SherpaSpeechRecognitionSession({
    required this.recorder,
    required this.recognizer,
    required this.recognitionStream,
    required Stream<Uint8List> audio,
  }) {
    _audioSubscription = audio.listen(
      _acceptAudio,
      onError: _onAudioError,
      cancelOnError: true,
    );
  }

  final AudioRecorder recorder;
  final sherpa.OnlineRecognizer recognizer;
  final sherpa.OnlineStream recognitionStream;
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();
  late final StreamSubscription<Uint8List> _audioSubscription;

  String _committed = '';
  String _partial = '';
  bool _closed = false;
  Future<void>? _ending;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  void _acceptAudio(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    try {
      recognitionStream.acceptWaveform(
        samples: pcm16BytesToFloat32(bytes),
        sampleRate: speechInputSampleRate,
      );
      while (recognizer.isReady(recognitionStream)) {
        recognizer.decode(recognitionStream);
      }
      _partial = recognizer.getResult(recognitionStream).text.trim();
      if (recognizer.isEndpoint(recognitionStream)) {
        _commitPartial();
        recognizer.reset(recognitionStream);
      }
      _emit(isFinal: false);
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  void _commitPartial() {
    if (_partial.isEmpty) return;
    _committed = _joinText(_committed, _partial);
    _partial = '';
  }

  void _emit({required bool isFinal}) {
    final text = _joinText(_committed, _partial);
    if (text.isEmpty && !isFinal) return;
    _events.add(SpeechRecognitionEvent(text: text, isFinal: isFinal));
  }

  void _onAudioError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _events.addError(error, stackTrace);
  }

  @override
  Future<void> stop() => _end(finalizeTranscript: true);

  @override
  Future<void> cancel() => _end(finalizeTranscript: false);

  Future<void> _end({required bool finalizeTranscript}) {
    if (_closed) return Future<void>.value();
    return _ending ??= _endInternal(finalizeTranscript: finalizeTranscript);
  }

  Future<void> _endInternal({required bool finalizeTranscript}) async {
    try {
      await recorder.stop();
      await _audioSubscription.cancel();
      if (finalizeTranscript) {
        recognitionStream.inputFinished();
        while (recognizer.isReady(recognitionStream)) {
          recognizer.decode(recognitionStream);
        }
        _partial = recognizer.getResult(recognitionStream).text.trim();
        _commitPartial();
        _emit(isFinal: true);
      }
    } finally {
      // Both recorder shutdown and plugin stream cancellation can throw.
      // Always release the native recognizer even when either one fails.
      try {
        await _audioSubscription.cancel();
      } finally {
        await _close();
      }
    }
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    recognitionStream.free();
    recognizer.free();
    await recorder.dispose();
    // Do not await close: a UI subscriber normally cancels only after stop()
    // returns, so awaiting it here would create a circular wait.
    unawaited(_events.close());
  }
}

String _joinText(String settled, String next) {
  if (settled.isEmpty) return next;
  if (next.isEmpty) return settled;
  final needsSpace =
      _isAsciiWord(settled.codeUnitAt(settled.length - 1)) &&
      _isAsciiWord(next.codeUnitAt(0));
  return '$settled${needsSpace ? ' ' : ''}$next';
}

bool _isAsciiWord(int codeUnit) =>
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122);
