import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_install_paths.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:path/path.dart' as p;

const _bundle = ModelBundle(
  id: 'test-bundle',
  displayName: 'Test',
  description: 'Test bundle',
  files: [
    ModelFile(localName: 'one.bin', url: 'https://x/one', sizeBytes: 1024),
    ModelFile(localName: 'two.bin', url: 'https://x/two', sizeBytes: 2048),
  ],
);

void main() {
  late Directory tmp;
  late ModelInstallPaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mip-');
    paths = ModelInstallPaths.unsafeForDir(tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('ModelInstallPaths', () {
    test('dirForBundle joins root + bundle.id', () {
      final dir = paths.dirForBundle(_bundle);
      expect(dir.path, p.join(tmp.path, _bundle.id));
    });

    test('filePath joins root + bundle.id + file.localName', () {
      final fp = paths.filePath(_bundle, _bundle.files.first);
      expect(fp, p.join(tmp.path, _bundle.id, 'one.bin'));
    });

    test('isComplete: false when bundle dir missing', () async {
      expect(await paths.isComplete(_bundle), isFalse);
    });

    test('isComplete: false when one file missing', () async {
      final dir = paths.dirForBundle(_bundle);
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'one.bin'))
          .writeAsBytes(List.filled(1024, 0));
      expect(await paths.isComplete(_bundle), isFalse);
    });

    test(
      'isComplete: true when every file present with matching size',
      () async {
        final dir = paths.dirForBundle(_bundle);
        await dir.create(recursive: true);
        await File(p.join(dir.path, 'one.bin'))
            .writeAsBytes(List.filled(1024, 0));
        await File(p.join(dir.path, 'two.bin'))
            .writeAsBytes(List.filled(2048, 0));
        expect(await paths.isComplete(_bundle), isTrue);
      },
    );

    test(
      'isComplete: accepts ±5% size wiggle (manifest sizes approx)',
      () async {
        final dir = paths.dirForBundle(_bundle);
        await dir.create(recursive: true);
        // 1024 ±5% = [972, 1075]
        await File(p.join(dir.path, 'one.bin'))
            .writeAsBytes(List.filled(1000, 0));
        await File(p.join(dir.path, 'two.bin'))
            .writeAsBytes(List.filled(2000, 0));
        expect(await paths.isComplete(_bundle), isTrue);
      },
    );

    test('isComplete: false when size differs > 5%', () async {
      final dir = paths.dirForBundle(_bundle);
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'one.bin')).writeAsBytes(List.filled(100, 0));
      await File(p.join(dir.path, 'two.bin'))
          .writeAsBytes(List.filled(2048, 0));
      expect(await paths.isComplete(_bundle), isFalse);
    });
  });

  test(
    'resolveModelInstallRoot migrates the legacy embedders folder',
    () async {
      final support = await Directory.systemTemp.createTemp('model-root-');
      addTearDown(() async {
        if (support.existsSync()) await support.delete(recursive: true);
      });
      final legacy = Directory(p.join(support.path, 'embedders'));
      await legacy.create();
      await File(p.join(legacy.path, 'marker')).writeAsString('installed');

      final root = await resolveModelInstallRoot(support);

      expect(root.path, p.join(support.path, 'ai-models'));
      expect(File(p.join(root.path, 'marker')).readAsStringSync(), 'installed');
      expect(legacy.existsSync(), isFalse);
    },
  );
}
