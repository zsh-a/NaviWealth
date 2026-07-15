import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

Never _fail(String message) {
  stderr.writeln('README screenshot validation failed: $message');
  exit(1);
}

void main() {
  final appRoot = Directory.current.absolute;
  final repoRoot = appRoot.parent.parent;
  final assetRoot = Directory('${repoRoot.path}/docs/assets/readme');
  final manifestFile = File('${assetRoot.path}/manifest.json');
  final readmeFile = File('${repoRoot.path}/README.md');

  if (!manifestFile.existsSync()) _fail('missing ${manifestFile.path}');
  if (!readmeFile.existsSync()) _fail('missing ${readmeFile.path}');

  final manifestValue = jsonDecode(manifestFile.readAsStringSync());
  if (manifestValue is! Map<String, Object?>) {
    _fail('manifest root must be an object');
  }
  if (manifestValue['schema_version'] != 1) {
    _fail('unsupported manifest schema_version');
  }
  final entries = manifestValue['screenshots'];
  if (entries is! List<Object?> || entries.isEmpty) {
    _fail('manifest screenshots must be a non-empty array');
  }

  final readme = readmeFile.readAsStringSync();
  final ids = <String>{};
  for (final value in entries) {
    if (value is! Map<String, Object?>) {
      _fail('each screenshot entry must be an object');
    }
    final id = value['id'];
    final relativePath = value['path'];
    final expectedWidth = value['width'];
    final expectedHeight = value['height'];
    if (id is! String || id.isEmpty || !ids.add(id)) {
      _fail('screenshot ids must be unique non-empty strings');
    }
    if (relativePath is! String ||
        expectedWidth is! int ||
        expectedHeight is! int) {
      _fail('$id has an invalid path or dimensions');
    }

    final file = File('${assetRoot.path}/$relativePath');
    if (!file.existsSync()) _fail('$id is missing at ${file.path}');
    if (file.lengthSync() > 1024 * 1024) {
      _fail('$id exceeds the 1 MiB README asset budget');
    }
    final decoded = image.decodePng(file.readAsBytesSync());
    if (decoded == null) _fail('$id is not a valid PNG');
    if (decoded.width != expectedWidth || decoded.height != expectedHeight) {
      _fail(
        '$id is ${decoded.width}x${decoded.height}; '
        'expected ${expectedWidth}x$expectedHeight',
      );
    }

    final readmePath = 'docs/assets/readme/$relativePath';
    if (!readme.contains(readmePath)) {
      _fail('$id is not referenced by README.md as $readmePath');
    }
    stdout.writeln(
      'ok $id ${decoded.width}x${decoded.height} '
      '${(file.lengthSync() / 1024).toStringAsFixed(1)} KiB',
    );
  }
}
