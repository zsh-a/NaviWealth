import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_downloader.dart';
import 'package:naviwealth/core/ai/local/embedding/model_install_paths.dart';
import 'package:naviwealth/core/ai/local/embedding/model_install_state.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:path/path.dart' as p;

const _bundle = ModelBundle(
  id: 'fallback-test',
  displayName: 'Fallback test',
  description: 'Fallback test',
  archiveFallback: ModelArchiveSource(
    url: 'https://fallback.test/model.tar.bz2',
    sizeBytes: 100,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    rootDirectory: 'model-root',
  ),
  files: [
    ModelFile(
      localName: 'one.bin',
      url: 'https://primary.test/one.bin',
      sizeBytes: 4,
    ),
    ModelFile(
      localName: 'two.bin',
      url: 'https://primary.test/two.bin',
      sizeBytes: 6,
    ),
  ],
);

void main() {
  test(
    'install falls back to the bundle archive after primary failure',
    () async {
      final tmp = await Directory.systemTemp.createTemp('model-state-');
      final downloader = _FallbackDownloader();
      final container = ProviderContainer(
        overrides: [
          modelInstallPathsProvider.overrideWith(
            (ref) async => ModelInstallPaths.unsafeForDir(tmp),
          ),
          modelDownloaderProvider.overrideWithValue(downloader),
        ],
      );
      final provider = modelInstallProvider(_bundle);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });

      await container.read(provider.future);
      await container.read(provider.notifier).install();

      final result = container.read(provider).requireValue;
      expect(result.isInstalled, isTrue);
      expect(downloader.primaryAttempts, 1);
      expect(downloader.archiveAttempts, 1);
      expect(File(p.join(result.installDir, 'one.bin')).lengthSync(), 4);
      expect(File(p.join(result.installDir, 'two.bin')).lengthSync(), 6);
    },
  );
}

class _FallbackDownloader extends ModelDownloader {
  int primaryAttempts = 0;
  int archiveAttempts = 0;

  @override
  Future<void> download({
    required ModelFile file,
    required String destDir,
    void Function(int received, int? total)? onProgress,
    DownloadCancellation? cancel,
  }) async {
    primaryAttempts++;
    throw StateError('primary unavailable');
  }

  @override
  Future<void> downloadArchiveFallback({
    required ModelBundle bundle,
    required String destDir,
    void Function(int received, int? total)? onProgress,
    DownloadCancellation? cancel,
  }) async {
    archiveAttempts++;
    await Directory(destDir).create(recursive: true);
    onProgress?.call(100, 100);
    for (final file in bundle.files) {
      await File(
        p.join(destDir, file.localName),
      ).writeAsBytes(List<int>.filled(file.sizeBytes!, 1));
    }
  }
}
