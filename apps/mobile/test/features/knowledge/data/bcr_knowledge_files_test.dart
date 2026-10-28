import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_archive.dart';

void main() {
  test('fromFiles and ZIP decode produce identical notes and fingerprints', () {
    for (final fixture in <String>['bcr-v2.zip', 'bcr-v4.zip']) {
      final bytes = File('test/fixtures/knowledge/bcr/$fixture')
          .readAsBytesSync();
      final zip = BcrKnowledgeArchive.decode(bytes);
      final files = <String, String>{};
      final attachments = <String, int>{};
      for (final file in ZipDecoder().decodeBytes(bytes)) {
        if (file.name.endsWith('.bin')) {
          attachments[file.name.split('/').last.replaceFirst('.bin', '')] =
              file.size;
        } else {
          files[file.name] = utf8.decode(file.readBytes()!);
        }
      }
      final remote = BcrKnowledgeArchive.fromFiles(
        files,
        attachmentSizes: attachments,
      );
      expect(remote.attachmentCount, zip.attachmentCount);
      expect(
        remote.notes.map((note) => note.toJson()),
        zip.notes.map((note) => note.toJson()),
      );
    }
  });

  test('fromFiles retains format and attachment integrity checks', () {
    final files = _files();
    expect(BcrKnowledgeArchive.fromFiles(files).notes, isEmpty);
    expect(
      () => BcrKnowledgeArchive.fromFiles(<String, String>{}),
      throwsFormatException,
    );
    expect(
      () => BcrKnowledgeArchive.fromFiles(<String, String>{
        ...files,
        '../outside': 'bad',
      }),
      throwsFormatException,
    );
    expect(
      () => BcrKnowledgeArchive.fromFiles(
        files,
        attachmentSizes: <String, int>{'bad': 1},
      ),
      throwsFormatException,
    );
    expect(
      () => BcrKnowledgeArchive.fromFiles(
        files,
        attachmentSizes: <String, int>{'a' * 64: 1},
      ),
      throwsFormatException,
    );
  });

  test(
    'fromFiles bounds actual UTF-8 bytes rather than only String length',
    () {
      final files = <String, String>{
        ..._files(),
        'knowledge/citations/note.json': '中' * 700000,
      };
      expect(() => BcrKnowledgeArchive.fromFiles(files), throwsFormatException);
      final tooMany = <String, String>{
        for (var index = 0; index < 11011; index++)
          'knowledge/citations/$index.json': '[]',
      };
      expect(
        () => BcrKnowledgeArchive.fromFiles(tooMany),
        throwsFormatException,
      );
    },
  );
}

Map<String, String> _files() => <String, String>{
  'knowledge/manifest.json': '{"format":"bcr-knowledge","version":1}',
};
