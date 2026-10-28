import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_archive.dart';

Uint8List makeBcrBackup({
  String body = 'Equity allocation stays below 60%.',
  String title = 'Asset allocation',
  int count = 1,
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'knowledge/manifest.json',
        '{"format":"bcr-knowledge","version":1}',
      ),
    );
  for (var i = 0; i < count; i++) {
    final meta = jsonEncode({
      'bcr': 1,
      'id': 'note-$i',
      'title': i == count - 1 ? title : 'Other note $i',
      'tags': ['investing'],
      'collectionId': null,
      'createdAt': 1735689600000,
      'updatedAt': 1735776000000,
    });
    archive
      ..addFile(
        ArchiveFile.string(
          'knowledge/notes/note-$i.md',
          '---\n$meta\n---\n${i == count - 1 ? body : 'Unrelated material'}',
        ),
      )
      ..addFile(ArchiveFile.string('knowledge/citations/note-$i.json', '[]'));
  }
  return ZipEncoder().encodeBytes(archive);
}

BcrKnowledgeArchive makeBcrArchive({
  String body = 'Equity allocation stays below 60%.',
  String title = 'Asset allocation',
  int count = 1,
}) => BcrKnowledgeArchive.decode(
  makeBcrBackup(body: body, title: title, count: count),
);
