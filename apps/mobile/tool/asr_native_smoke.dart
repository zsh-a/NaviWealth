import 'dart:convert';
import 'dart:io';

import 'package:naviwealth/core/speech/speech_zipformer_config.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> arguments) {
  if (arguments.length < 3 || arguments.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/asr_native_smoke.dart '
      '<native-library-dir|auto> <model-dir> <wav-file> '
      '[expected-transcript]',
    );
    exitCode = 64;
    return;
  }

  final nativeLibraryDir = arguments[0] == 'auto'
      ? _resolveSherpaMacosLibraryDir()
      : arguments[0];
  final modelDir = arguments[1];
  final wavPath = arguments[2];
  final expectedTranscript = arguments.length == 4 ? arguments[3].trim() : null;

  sherpa.initBindings(nativeLibraryDir);
  final wave = sherpa.readWave(wavPath);
  if (wave.samples.isEmpty || wave.sampleRate <= 0) {
    stderr.writeln('Unable to read WAV input: $wavPath');
    exitCode = 65;
    return;
  }

  final stopwatch = Stopwatch()..start();
  final recognizer = sherpa.OnlineRecognizer(
    streamingZipformerZhConfig(modelDir),
  );
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }

    final result = recognizer.getResult(stream).text.trim();
    stopwatch.stop();
    stdout.writeln(result);
    if (result.isEmpty) {
      stderr.writeln('Native recognizer returned an empty transcript.');
      exitCode = 1;
      return;
    }
    if (expectedTranscript != null && result != expectedTranscript) {
      stderr
        ..writeln('Transcript regression detected.')
        ..writeln('Expected: $expectedTranscript')
        ..writeln('Actual:   $result');
      exitCode = 2;
      return;
    }

    final audioSeconds = wave.samples.length / wave.sampleRate;
    final elapsedSeconds = stopwatch.elapsedMicroseconds / 1000000;
    final realTimeFactor = audioSeconds <= 0
        ? 0.0
        : elapsedSeconds / audioSeconds;
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'event': 'core.speech.native_smoke.completed',
        'audio_ms': (audioSeconds * 1000).round(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'real_time_factor': double.parse(realTimeFactor.toStringAsFixed(3)),
      }),
    );
  } finally {
    stream.free();
    recognizer.free();
  }
}

String _resolveSherpaMacosLibraryDir() {
  final packageConfig = File('.dart_tool/package_config.json');
  if (!packageConfig.existsSync()) {
    throw StateError(
      'Run flutter pub get before using native-library-dir=auto',
    );
  }
  final json = jsonDecode(packageConfig.readAsStringSync());
  final packages = (json as Map<String, Object?>)['packages'] as List<Object?>;
  for (final entry in packages) {
    final package = entry! as Map<String, Object?>;
    if (package['name'] != 'sherpa_onnx_macos') continue;
    final rootUri = packageConfig.uri.resolve(package['rootUri']! as String);
    final rootPath = Directory.fromUri(rootUri).path;
    return '$rootPath${Platform.pathSeparator}macos';
  }
  throw StateError('sherpa_onnx_macos is missing from package_config.json');
}
