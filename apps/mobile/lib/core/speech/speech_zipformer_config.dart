import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const speechInputSampleRate = 16000;

/// Builds the one authoritative native configuration for the bundled Mandarin
/// streaming Zipformer. The app runtime and the native smoke tool share this
/// function so verification cannot silently drift from production settings.
sherpa.OnlineRecognizerConfig streamingZipformerZhConfig(
  String modelDirectory,
) {
  String modelPath(String name) => p.join(modelDirectory, name);

  return sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: modelPath('encoder-epoch-99-avg-1.int8.onnx'),
        decoder: modelPath('decoder-epoch-99-avg-1.int8.onnx'),
        joiner: modelPath('joiner-epoch-99-avg-1.int8.onnx'),
      ),
      tokens: modelPath('tokens.txt'),
      numThreads: 2,
      debug: false,
      modelType: 'zipformer',
    ),
    enableEndpoint: true,
    rule1MinTrailingSilence: 2.0,
    rule2MinTrailingSilence: 0.8,
    rule3MinUtteranceLength: 20,
  );
}
