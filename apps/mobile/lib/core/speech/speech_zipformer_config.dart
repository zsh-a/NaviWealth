import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const speechInputSampleRate = 16000;

/// Builds the one authoritative native configuration for the bundled Mandarin
/// streaming Zipformer Large CTC. The app runtime and native smoke tool share
/// this function so verification cannot silently drift from production.
sherpa.OnlineRecognizerConfig streamingZipformerLargeCtcZhConfig(
  String modelDirectory,
) {
  String modelPath(String name) => p.join(modelDirectory, name);

  return sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(
        model: modelPath('model.int8.onnx'),
      ),
      tokens: modelPath('tokens.txt'),
      numThreads: 1,
      debug: false,
    ),
    enableEndpoint: true,
    rule1MinTrailingSilence: 2.0,
    rule2MinTrailingSilence: 0.8,
    rule3MinUtteranceLength: 20,
  );
}
