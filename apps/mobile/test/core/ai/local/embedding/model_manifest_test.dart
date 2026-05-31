import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';

void main() {
  group('embeddingGemmaBundle', () {
    final b = embeddingGemmaBundle();

    test('id is stable + bundle metadata populated', () {
      expect(b.id, 'embeddinggemma-300m-onnx');
      expect(b.displayName, isNotEmpty);
      expect(b.description, isNotEmpty);
    });

    test('manifest contains the six required files', () {
      final names = b.files.map((f) => f.localName).toSet();
      expect(names, {
        // ONNX graph topology + external weights blob — both must
        // download for fastembed's `with_external_initializer` to
        // wire them back together at load time.
        'model_quantized.onnx',
        'model_quantized.onnx_data',
        'tokenizer.json',
        'config.json',
        'special_tokens_map.json',
        'tokenizer_config.json',
      });
    });

    test('every file has a non-empty https URL', () {
      for (final f in b.files) {
        expect(f.url, startsWith('https://'));
        expect(f.url, isNot(contains(' ')));
      }
    });

    test('totalSizeBytes is roughly 300 MB + tokenizer overhead', () {
      final total = b.totalSizeBytes;
      expect(total, isNotNull);
      expect(total!, greaterThan(300 * 1024 * 1024));
      expect(total, lessThan(400 * 1024 * 1024));
    });
  });

  // ONNX Runtime is intentionally NOT in the Dart-side manifest —
  // it's build-time managed by tool/fetch-onnxruntime.sh + discovered
  // at runtime by discoverBundledOrtDylib.

  group('ModelBundle.totalSizeBytes', () {
    test('null when any file has unknown size', () {
      const bundle = ModelBundle(
        id: 'x',
        displayName: 'x',
        description: 'x',
        files: [
          ModelFile(localName: 'a', url: 'https://x/a', sizeBytes: 100),
          ModelFile(localName: 'b', url: 'https://x/b'), // unknown
        ],
      );
      expect(bundle.totalSizeBytes, isNull);
    });

    test('sums when every size is known', () {
      const bundle = ModelBundle(
        id: 'x',
        displayName: 'x',
        description: 'x',
        files: [
          ModelFile(localName: 'a', url: 'https://x/a', sizeBytes: 100),
          ModelFile(localName: 'b', url: 'https://x/b', sizeBytes: 200),
        ],
      );
      expect(bundle.totalSizeBytes, 300);
    });
  });
}
