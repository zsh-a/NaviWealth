import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_archive.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_knowledge_models.dart';

void main() {
  group('BCR read-only knowledge archive', () {
    test('reads an actual BCR v2 export without regenerating identity', () {
      final archive = BcrKnowledgeArchive.decode(_fixture('bcr-v2.zip'));
      final note = archive.notes.single;
      expect(note.id, 'source-note-1');
      expect(note.title, '资产配置');
      expect(note.body, '# 资产配置\n\n权益仓位上限为 60%。\n');
      expect(note.path, '投资/资产配置.md');
      expect(note.tags, <String>['投资', '配置']);
      expect(note.createdAt, DateTime.utc(2025));
      expect(note.updatedAt, DateTime.utc(2025, 1, 2));
      expect(note.fingerprint, startsWith('sha256:'));
      expect(archive.attachmentCount, 0);
    });

    test(
      'reads actual BCR v4 collections, citations and attachment metadata',
      () {
        final archive = BcrKnowledgeArchive.decode(_fixture('bcr-v4.zip'));
        expect(archive.attachmentCount, 1);
        final note = archive.notes.single;
        expect(note.collectionId, 'research');
        expect(note.citations.single['route'], '/reader?book=source-book');
        expect(note.body, contains('[证据](attachment:asset-one)'));
      },
    );

    test('reads legacy v1 and folder-aware v3 manifests', () {
      expect(
        BcrKnowledgeArchive.decode(_zip(_files())).notes.single.path,
        isNull,
      );
      final files = _files(version: 3)..['knowledge/folders.json'] = '["研究"]';
      expect(BcrKnowledgeArchive.decode(_zip(files)).notes.single.id, 'note');
      expect(
        () => BcrKnowledgeArchive.decode(_zip(_files(version: 3))),
        throwsFormatException,
      );
    });

    test(
      'same export has the same snapshot fingerprint after JSON persistence',
      () {
        final note = BcrKnowledgeArchive.decode(_fixture('bcr-v4.zip'))
            .notes
            .single;
        final roundTrip = BcrKnowledgeNote.fromJson(
          (jsonDecode(jsonEncode(note.toJson())) as Map)
              .cast<String, Object?>(),
        );
        expect(roundTrip.fingerprint, note.fingerprint);
        expect(roundTrip.toJson(), note.toJson());
        final reorderedCitation = <String, Object?>{
          for (final key in note.citations.single.keys.toList().reversed)
            key: note.citations.single[key],
        };
        final reordered = BcrKnowledgeNote.fromJson(<String, Object?>{
          ...note.toJson(),
          'citations': <Map<String, Object?>>[reorderedCitation],
        });
        expect(reordered.fingerprint, note.fingerprint);
      },
    );

    test(
      'fingerprint covers body, metadata and provenance and detects corruption',
      () {
        final note = BcrKnowledgeArchive.decode(_fixture('bcr-v4.zip'))
            .notes
            .single;
        for (final field in <Map<String, Object?>>[
          <String, Object?>{'body': '${note.body}new material'},
          <String, Object?>{'title': 'renamed'},
          <String, Object?>{
            'tags': <String>['new'],
          },
          <String, Object?>{'citations': <Object?>[]},
          <String, Object?>{'updatedAt': 1735862400000},
        ]) {
          final changed = <String, Object?>{...note.toJson(), ...field};
          expect(
            () => BcrKnowledgeNote.fromJson(changed),
            throwsFormatException,
          );
          changed.remove('fingerprint');
          expect(
            BcrKnowledgeNote.fromJson(changed).fingerprint,
            isNot(note.fingerprint),
          );
        }
        expect(() => note.tags.add('mutate'), throwsUnsupportedError);
        expect(
          () => note.citations.single['text'] = 'mutate',
          throwsUnsupportedError,
        );
      },
    );

    test('requires the official backup and every note citation sidecar', () {
      final missingManifest = _files()..remove('knowledge/manifest.json');
      final missingCitation = _files()..remove('knowledge/citations/note.json');
      final danglingCitation = _files()
        ..['knowledge/citations/missing.json'] = '[]';
      final missingCollection = _files()
        ..['knowledge/notes/note.md'] = _note.replaceFirst(
          'collectionId: null',
          'collectionId: missing',
        );
      final unsupported = _files(version: 5);
      for (final files in <Map<String, Object>>[
        missingManifest,
        missingCitation,
        danglingCitation,
        missingCollection,
        unsupported,
        <String, Object>{'notes/plain.md': '# Plain Markdown'},
      ]) {
        expect(
          () => BcrKnowledgeArchive.decode(_zip(files)),
          throwsFormatException,
        );
      }
    });

    test('rejects mismatched ids, duplicate YAML keys, aliases and invalid field types', () {
      for (final raw in <String>[
        _note.replaceFirst('id: note', 'id: other'),
        _note.replaceFirst('id: note', 'id: constructor'),
        _note.replaceFirst('id: note', 'id: note\nid: note'),
        _note.replaceFirst('title: Note', 'title: &title Note\nother: *title'),
        _note.replaceFirst('title: Note', 'title: [Note]'),
        _note.replaceFirst('createdAt: 1', 'createdAt: -1'),
        _note.replaceFirst('tags: []', 'tags: [1]'),
        _note.replaceFirst('bcr: 1', 'bcr: 3'),
        '# No frontmatter',
      ]) {
        final files = _files()..['knowledge/notes/note.md'] = raw;
        expect(
          () => BcrKnowledgeArchive.decode(_zip(files)),
          throwsFormatException,
        );
      }
    });

    test(
      'rejects alias DAGs, structural keys and depth before loading YAML nodes',
      () {
        final dag = StringBuffer('a: &a [x, x]\n');
        var previous = 'a';
        for (var index = 0; index < 24; index++) {
          final key = 'n$index';
          dag.writeln('$key: &$key [*$previous, *$previous]');
          previous = key;
        }
        dag.writeln('? *$previous\n: ignored');
        final cases = <(String, String)>[
          (dag.toString(), 'BCR YAML aliases are not supported'),
          (
            '? [one, two]\n: ignored\n',
            'BCR YAML mapping keys must be scalars',
          ),
          (
            'extra: ${'[' * 10000}0${']' * 10000}\n',
            'BCR YAML nesting exceeds its limit',
          ),
        ];
        for (final payload in cases) {
          final files = _files()
            ..['knowledge/notes/note.md'] = _note.replaceFirst(
              '---\nbody',
              '${payload.$1}---\nbody',
            );
          expect(
            () => BcrKnowledgeArchive.decode(_zip(files)),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'preflight',
                payload.$2,
              ),
            ),
          );
        }
      },
    );

    test('keeps ordinary ampersands, stars and Unicode scalars compatible', () {
      final files = _files()
        ..['knowledge/notes/note.md'] = _note
            .replaceFirst('title: Note', 'title: A & B * C')
            .replaceFirst('tags: []', 'tags: ["*tag", "A & B", "é", "👩‍💻"]');
      final note = BcrKnowledgeArchive.decode(_zip(files)).notes.single;
      expect(note.title, 'A & B * C');
      expect(note.tags, <String>['*tag', 'A & B', 'é', '👩‍💻']);
      expect(
        BcrKnowledgeNote.fromJson(note.toJson()).fingerprint,
        note.fingerprint,
      );
    });

    test('accepts an official v3 library containing only an empty folder', () {
      final files = _files(version: 3)
        ..remove('knowledge/notes/note.md')
        ..remove('knowledge/citations/note.json')
        ..['knowledge/folders.json'] = '["空目录"]';
      final archive = BcrKnowledgeArchive.decode(_zip(files));
      expect(archive.notes, isEmpty);
      expect(archive.attachmentCount, 0);
    });

    test('rejects unsafe, unknown and duplicate ZIP paths', () {
      for (final path in <String>[
        'knowledge/../secret.md',
        '/knowledge/notes/note.md',
        'knowledge/./notes/note.md',
        'knowledge/notes/note.txt',
        'unknown.txt',
      ]) {
        final files = _files()..[path] = 'bad';
        expect(
          () => BcrKnowledgeArchive.decode(_zip(files)),
          throwsFormatException,
        );
      }
      final duplicate = _zipEntries(<ArchiveFile>[
        ..._files().entries.map(_archiveFile),
        ArchiveFile.string('knowledge/notes/note.md', _note),
      ]);
      expect(
        () => BcrKnowledgeArchive.decode(duplicate),
        throwsFormatException,
      );
    });

    test(
      'rejects encrypted entries and symlinks before reading their data',
      () {
        final original = _zip(_files());
        for (final mutation in <void Function(Uint8List)>[
          (bytes) => _patchEntry(bytes, 'knowledge/notes/note.md', flags: 1),
          (bytes) =>
              _patchEntry(bytes, 'knowledge/notes/note.md', mode: 0xa1ff),
        ]) {
          final bytes = Uint8List.fromList(original);
          mutation(bytes);
          expect(
            () => BcrKnowledgeArchive.decode(bytes),
            throwsFormatException,
          );
        }
      },
    );

    test('rejects malformed UTF-8 and invalid text CRCs', () {
      final files = _files()
        ..['knowledge/notes/note.md'] = Uint8List.fromList(<int>[0xff, 0xfe]);
      expect(
        () => BcrKnowledgeArchive.decode(_zip(files)),
        throwsFormatException,
      );
      final corrupt = _zip(_files());
      final entry = _entry(corrupt, 'knowledge/notes/note.md');
      ByteData.sublistView(corrupt).setUint32(entry.$1 + 16, 0, Endian.little);
      expect(() => BcrKnowledgeArchive.decode(corrupt), throwsFormatException);
    });

    test(
      'bounds declared text size and actual inflation with forged size fields',
      () {
        final oversized = _zip(_files());
        _patchEntry(
          oversized,
          'knowledge/notes/note.md',
          size: 2 * 1024 * 1024 + 1,
        );
        expect(
          () => BcrKnowledgeArchive.decode(oversized),
          throwsFormatException,
        );

        final forged = _zip(<String, Object>{
          ..._files(),
          'knowledge/notes/note.md': 'x' * (2 * 1024 * 1024 + 1),
        });
        _patchEntry(forged, 'knowledge/notes/note.md', size: 1);
        expect(() => BcrKnowledgeArchive.decode(forged), throwsFormatException);
      },
    );

    test('bounds total declared expansion and ZIP directory count', () {
      final files = _files();
      final paths = <String>[];
      for (var index = 0; index < 5; index++) {
        final path = 'knowledge/attachments/${'$index' * 64}.bin';
        paths.add(path);
        files[path] = 'small';
      }
      final inflated = _zip(files);
      for (final path in paths) {
        _patchEntry(inflated, path, size: 128 * 1024 * 1024);
      }
      expect(() => BcrKnowledgeArchive.decode(inflated), throwsFormatException);

      final tooMany = _zip(_files());
      final end = tooMany.length - 22;
      final view = ByteData.sublistView(tooMany);
      view.setUint16(end + 8, 22011, Endian.little);
      view.setUint16(end + 10, 22011, Endian.little);
      expect(() => BcrKnowledgeArchive.decode(tooMany), throwsFormatException);
      expect(
        () => BcrKnowledgeArchive.decode(Uint8List(64 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    });

    test(
      'preflights the actual central directory count before ZIP parsing',
      () {
        final forged = _zipEntries(<ArchiveFile>[
          ..._files().entries.map(_archiveFile),
          for (var index = 0; index < 22011; index++)
            ArchiveFile.string('knowledge/citations/repeated.json', '[]'),
        ]);
        final end = forged.length - 22;
        final view = ByteData.sublistView(forged);
        view.setUint16(end + 8, 3, Endian.little);
        view.setUint16(end + 10, 3, Endian.little);
        expect(
          () => BcrKnowledgeArchive.decode(forged),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'rejects during preflight',
              'BCR ZIP directory entry count differs',
            ),
          ),
        );
      },
    );

    test('never inflates binary attachments in the text projection', () {
      final bytes = _fixture('bcr-v4.zip');
      final binaryPath = _entryNames(bytes)
          .singleWhere((name) => name.endsWith('.bin'));
      _patchEntry(bytes, binaryPath, method: 8);
      final offsets = _entry(bytes, binaryPath);
      final view = ByteData.sublistView(bytes);
      final dataStart =
          offsets.$2 +
          30 +
          view.getUint16(offsets.$2 + 26, Endian.little) +
          view.getUint16(offsets.$2 + 28, Endian.little);
      bytes[dataStart] = 0xff;
      final archive = BcrKnowledgeArchive.decode(bytes);
      expect(archive.attachmentCount, 1);
      expect(archive.notes.single.id, 'source-note-1');
    });

    test('rejects missing attachment files and metadata length mismatches', () {
      final original = _fixture('bcr-v4.zip');
      final binaryPath = _entryNames(original)
          .singleWhere((name) => name.endsWith('.bin'));
      final wrongLength = Uint8List.fromList(original);
      _patchEntry(wrongLength, binaryPath, size: 100);
      expect(
        () => BcrKnowledgeArchive.decode(wrongLength),
        throwsFormatException,
      );
      final archive = ZipDecoder().decodeBytes(original);
      archive.removeAt(
        archive.files.indexWhere((file) => file.name == binaryPath),
      );
      expect(
        () => BcrKnowledgeArchive.decode(ZipEncoder().encodeBytes(archive)),
        throwsFormatException,
      );
    });
  });
}

const _note = '''---
bcr: 1
id: note
title: Note
tags: []
collectionId: null
createdAt: 1
updatedAt: 2
---
body
''';

Map<String, Object> _files({int version = 1}) => <String, Object>{
  'knowledge/manifest.json': jsonEncode(<String, Object>{
    'format': 'bcr-knowledge',
    'version': version,
  }),
  'knowledge/notes/note.md': _note,
  'knowledge/citations/note.json': '[]',
};

Uint8List _fixture(String name) =>
    File('test/fixtures/knowledge/bcr/$name').readAsBytesSync();

ArchiveFile _archiveFile(MapEntry<String, Object> entry) =>
    switch (entry.value) {
      final String text => ArchiveFile.string(entry.key, text),
      final Uint8List bytes => ArchiveFile.bytes(entry.key, bytes),
      _ => throw StateError('Unexpected test fixture value'),
    };

Uint8List _zip(Map<String, Object> files) =>
    _zipEntries(files.entries.map(_archiveFile));

Uint8List _zipEntries(Iterable<ArchiveFile> entries) {
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output);
  for (final entry in entries) {
    encoder.add(entry);
  }
  encoder.endEncode();
  return output.getBytes();
}

Iterable<(int, String, int)> _entries(Uint8List bytes) sync* {
  final data = ByteData.sublistView(bytes);
  final end = bytes.length - 22;
  final count = data.getUint16(end + 10, Endian.little);
  var offset = data.getUint32(end + 16, Endian.little);
  for (var index = 0; index < count; index++) {
    final length = data.getUint16(offset + 28, Endian.little);
    final path = utf8.decode(bytes.sublist(offset + 46, offset + 46 + length));
    final local = data.getUint32(offset + 42, Endian.little);
    yield (offset, path, local);
    offset +=
        46 +
        length +
        data.getUint16(offset + 30, Endian.little) +
        data.getUint16(offset + 32, Endian.little);
  }
}

Iterable<String> _entryNames(Uint8List bytes) =>
    _entries(bytes).map((entry) => entry.$2);

(int, int) _entry(Uint8List bytes, String path) {
  final entry = _entries(bytes).singleWhere((entry) => entry.$2 == path);
  return (entry.$1, entry.$3);
}

void _patchEntry(
  Uint8List bytes,
  String path, {
  int? flags,
  int? mode,
  int? size,
  int? method,
}) {
  final entry = _entry(bytes, path);
  final data = ByteData.sublistView(bytes);
  if (flags != null) {
    data.setUint16(entry.$1 + 8, flags, Endian.little);
    data.setUint16(entry.$2 + 6, flags, Endian.little);
  }
  if (mode != null) data.setUint32(entry.$1 + 38, mode << 16, Endian.little);
  if (size != null) {
    data.setUint32(entry.$1 + 24, size, Endian.little);
    data.setUint32(entry.$2 + 22, size, Endian.little);
  }
  if (method != null) {
    data.setUint16(entry.$1 + 10, method, Endian.little);
    data.setUint16(entry.$2 + 8, method, Endian.little);
  }
}
