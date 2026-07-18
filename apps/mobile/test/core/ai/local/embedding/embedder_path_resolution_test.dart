import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder_path_resolution.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:path/path.dart' as p;

const _config = AppConfig(
  apiBaseUrl: 'http://127.0.0.1:8787',
  environment: AppEnvironment.dev,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('embedder-paths-');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('dart-define paths win over auto-discovery', () async {
    final resolution = await resolveEmbedderPaths(
      const AppConfig(
        apiBaseUrl: 'http://127.0.0.1:8787',
        environment: AppEnvironment.dev,
        rustEmbedderModelDir: '/models/gemma',
        rustEmbedderOrtDylibPath: '/lib/libonnxruntime.dylib',
        rustEmbedderLibraryPath: '/lib/liblifeos_native.dylib',
      ),
      supportDirectory: tmp,
      hostPlatform: EmbedderHostPlatform.other,
    );

    expect(resolution.isComplete, isTrue);
    expect(resolution.modelSource, EmbedderModelPathSource.dartDefine);
    expect(resolution.ortSource, EmbedderOrtPathSource.dartDefine);
    expect(resolution.libraryPath, '/lib/liblifeos_native.dylib');
  });

  test(
    'detects an installed EmbeddingGemma bundle under app support',
    () async {
      final bundle = embeddingGemmaBundle();
      final dir = Directory(p.join(tmp.path, 'ai-models', bundle.id));
      await dir.create(recursive: true);
      for (final f in bundle.files) {
        final disk = File(p.join(dir.path, f.localName));
        final raf = await disk.open(mode: FileMode.write);
        await raf.truncate(f.sizeBytes ?? 1);
        await raf.close();
      }

      final resolution = await resolveEmbedderPaths(
        _config,
        supportDirectory: tmp,
        hostPlatform: EmbedderHostPlatform.android,
      );

      expect(resolution.modelDir, dir.path);
      expect(resolution.modelSource, EmbedderModelPathSource.installedBundle);
      expect(resolution.ortDylibPath, 'libonnxruntime.so');
      expect(resolution.ortSource, EmbedderOrtPathSource.bundled);
    },
  );

  test('discovers macOS ORT beside the app Frameworks directory', () async {
    final exec = p.join(tmp.path, 'MacOS', 'NaviWealth');
    final frameworks = Directory(p.join(tmp.path, 'Frameworks'));
    await frameworks.create(recursive: true);
    final ort = p.join(frameworks.path, 'libonnxruntime.dylib');
    await File(ort).writeAsBytes(const [1]);

    expect(
      discoverBundledOrtDylib(
        hostPlatform: EmbedderHostPlatform.macos,
        resolvedExecutable: exec,
      ),
      ort,
    );
  });

  test('prefers sherpa bundled versioned macOS ORT', () async {
    final exec = p.join(tmp.path, 'MacOS', 'NaviWealth');
    final frameworks = Directory(p.join(tmp.path, 'Frameworks'));
    await frameworks.create(recursive: true);
    final ort = p.join(frameworks.path, 'libonnxruntime.1.27.0.dylib');
    await File(ort).writeAsBytes(const [1]);

    expect(
      discoverBundledOrtDylib(
        hostPlatform: EmbedderHostPlatform.macos,
        resolvedExecutable: exec,
      ),
      ort,
    );
  });

  test('returns null for unsupported native platforms', () {
    expect(
      discoverBundledOrtDylib(hostPlatform: EmbedderHostPlatform.other),
      isNull,
    );
  });
}
