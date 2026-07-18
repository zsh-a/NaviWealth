import 'dart:io';

import 'package:naviwealth/core/speech/speech_zipformer_config.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/asr_native_smoke.dart '
      '<native-library-dir> <model-dir> <wav-file>',
    );
    exitCode = 64;
    return;
  }

  final nativeLibraryDir = arguments[0];
  final modelDir = arguments[1];
  final wavPath = arguments[2];

  sherpa.initBindings(nativeLibraryDir);
  final wave = sherpa.readWave(wavPath);
  if (wave.samples.isEmpty || wave.sampleRate <= 0) {
    stderr.writeln('Unable to read WAV input: $wavPath');
    exitCode = 65;
    return;
  }

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
    stdout.writeln(result);
    if (result.isEmpty) {
      stderr.writeln('Native recognizer returned an empty transcript.');
      exitCode = 1;
    }
  } finally {
    stream.free();
    recognizer.free();
  }
}
