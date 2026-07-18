import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_zipformer_config.dart';
import 'package:path/path.dart' as p;

void main() {
  test('builds the production streaming Zipformer configuration', () {
    final config = streamingZipformerZhConfig('/models/zipformer');

    expect(
      config.model.transducer.encoder,
      p.join('/models/zipformer', 'encoder-epoch-99-avg-1.int8.onnx'),
    );
    expect(
      config.model.transducer.decoder,
      p.join('/models/zipformer', 'decoder-epoch-99-avg-1.int8.onnx'),
    );
    expect(
      config.model.transducer.joiner,
      p.join('/models/zipformer', 'joiner-epoch-99-avg-1.int8.onnx'),
    );
    expect(config.model.tokens, p.join('/models/zipformer', 'tokens.txt'));
    expect(config.model.modelType, 'zipformer');
    expect(config.model.numThreads, 2);
    expect(config.enableEndpoint, isTrue);
    expect(config.rule1MinTrailingSilence, 2.0);
    expect(config.rule2MinTrailingSilence, 0.8);
    expect(speechInputSampleRate, 16000);
  });
}
