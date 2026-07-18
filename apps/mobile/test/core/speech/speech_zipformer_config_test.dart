import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/speech/speech_zipformer_config.dart';
import 'package:path/path.dart' as p;

void main() {
  test('builds the production streaming Zipformer Large CTC config', () {
    final config = streamingZipformerLargeCtcZhConfig('/models/zipformer');

    expect(
      config.model.zipformer2Ctc.model,
      p.join('/models/zipformer', 'model.int8.onnx'),
    );
    expect(config.model.tokens, p.join('/models/zipformer', 'tokens.txt'));
    expect(config.model.transducer.encoder, isEmpty);
    expect(config.model.transducer.decoder, isEmpty);
    expect(config.model.transducer.joiner, isEmpty);
    expect(config.model.numThreads, 1);
    expect(config.enableEndpoint, isTrue);
    expect(config.rule1MinTrailingSilence, 2.0);
    expect(config.rule2MinTrailingSilence, 0.8);
    expect(speechInputSampleRate, 16000);
  });
}
