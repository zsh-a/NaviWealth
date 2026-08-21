import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/knowledge/data/attachments/attachment_storage.dart';
import 'package:naviwealth/features/knowledge/data/attachments/knowledge_attachment_store.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_text.dart';

import '../../../core/persistence/test_database.dart';

class InMemoryAttachmentStorage implements AttachmentStorage {
  final Map<String, Uint8List> files = {};

  @override
  bool get isSupported => true;

  @override
  Future<String> save(String fileName, Uint8List bytes) async {
    files[fileName] = bytes;
    return 'knowledge_attachments/$fileName';
  }

  @override
  Future<Uint8List?> read(String relativePath) async =>
      files[relativePath.split('/').last];

  @override
  Future<void> delete(String relativePath) async =>
      files.remove(relativePath.split('/').last);
}

void main() {
  late AppDatabase db;
  late InMemoryAttachmentStorage storage;
  late KnowledgeAttachmentStore store;

  setUp(() {
    db = makeTestDatabase();
    storage = InMemoryAttachmentStorage();
    store = KnowledgeAttachmentStore(db: db, storage: storage);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'importImage persists metadata and bytes, find/readBytes round-trip',
    () async {
      final bytes = Uint8List.fromList(List<int>.filled(32, 7));
      final attachment = await store.importImage(
        ownerUserId: 'user-1',
        fileName: 'Receipt.JPG',
        bytes: bytes,
        noteId: 'note-1',
      );

      expect(attachment.mimeType, 'image/jpeg');
      expect(attachment.byteSize, bytes.length);
      expect(attachment.markdownSrc, 'attachment://${attachment.id}');

      final found = await store.find(attachment.id);
      expect(found, isNotNull);
      expect(found!.noteId, 'note-1');
      expect(found.mimeType, 'image/jpeg');
      expect(found.sha256, sha256Bytes(bytes));

      final read = await store.readBytes(attachment.id);
      expect(read, bytes);
    },
  );

  test(
    'importImage rejects unsupported extensions and oversize images',
    () async {
      await expectLater(
        store.importImage(
          ownerUserId: 'user-1',
          fileName: 'notes.txt',
          bytes: Uint8List(4),
        ),
        throwsA(isA<KnowledgeAttachmentImportRejected>()),
      );
      await expectLater(
        store.importImage(
          ownerUserId: 'user-1',
          fileName: 'huge.png',
          bytes: Uint8List(kKnowledgeAttachmentMaxBytes + 1),
        ),
        throwsA(isA<KnowledgeAttachmentImportRejected>()),
      );
      expect(await store.find('anything'), isNull);
      expect(storage.files, isEmpty);
    },
  );

  test('bindToNote attaches an orphan attachment to its note', () async {
    final attachment = await store.importImage(
      ownerUserId: 'user-1',
      fileName: 'scan.png',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );
    expect((await store.find(attachment.id))!.noteId, isNull);
    await store.bindToNote(attachment.id, 'note-9');
    expect((await store.find(attachment.id))!.noteId, 'note-9');
  });

  group('markdown text helpers', () {
    test('knowledgeAttachmentIdFromSrc only accepts the attachment scheme', () {
      expect(knowledgeAttachmentIdFromSrc('attachment://abc-123'), 'abc-123');
      expect(knowledgeAttachmentIdFromSrc('attachment://'), isNull);
      expect(knowledgeAttachmentIdFromSrc('https://x.test/a.png'), isNull);
      expect(knowledgeAttachmentIdFromSrc(''), isNull);
    });

    test('knowledgeMarkdownWithoutAttachments swaps refs for text markers', () {
      expect(
        knowledgeMarkdownWithoutAttachments(
          'before\n\n![chart.png](attachment://abc-123)\n\nafter',
        ),
        'before\n\n[image: chart.png]\n\nafter',
      );
      expect(
        knowledgeMarkdownWithoutAttachments('![](attachment://abc-123)'),
        '[image]',
      );
      // Remote images keep their markdown untouched.
      expect(
        knowledgeMarkdownWithoutAttachments('![x](https://x.test/a.png)'),
        '![x](https://x.test/a.png)',
      );
    });
  });
}
