import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/attachments/attachment_storage.dart';
import 'package:naviwealth/features/knowledge/data/attachments/knowledge_attachment_store.dart';
import 'package:naviwealth/features/knowledge/ui/_widgets.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_attachment_image.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_image_insert.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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

// A valid 1x1 transparent PNG.
final Uint8List _pngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x62,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Future<void> _pumpMarkdown(
  WidgetTester tester,
  KnowledgeAttachmentStore store,
  String markdown,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        knowledgeAttachmentStoreProvider.overrideWith((ref) async => store),
      ],
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: KnowledgeMarkdown(text: markdown),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late KnowledgeAttachmentStore store;
  late InMemoryAttachmentStorage storage;

  setUp(() {
    storage = InMemoryAttachmentStorage();
    store = KnowledgeAttachmentStore(db: makeTestDatabase(), storage: storage);
  });

  testWidgets('standalone attachment image renders as a block image', (
    tester,
  ) async {
    final attachment = await store.importImage(
      ownerUserId: 'user-1',
      fileName: 'chart.png',
      bytes: _pngBytes,
    );
    await _pumpMarkdown(
      tester,
      store,
      'before\n\n![chart](${attachment.markdownSrc})\n\nafter',
    );
    await tester.pumpAndSettle();

    expect(find.byType(KnowledgeAttachmentImage), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('before'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
  });

  testWidgets('missing attachment falls back to the unavailable chip', (
    tester,
  ) async {
    await _pumpMarkdown(tester, store, '![gone](attachment://missing-id)');
    await tester.pumpAndSettle();

    expect(find.byType(KnowledgeAttachmentImage), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(FLucideIcons.imageOff), findsOneWidget);
  });

  test('insertKnowledgeAttachmentMarkdown separates blocks with blank lines', () {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    final attachment = KnowledgeAttachment(
      id: 'abc',
      fileName: 'shot.png',
      mimeType: 'image/png',
      byteSize: 3,
      sha256: 'x',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      relativePath: 'knowledge_attachments/abc.png',
    );

    insertKnowledgeAttachmentMarkdown(controller, attachment);
    expect(controller.text, 'hello\n\n![shot.png](attachment://abc)\n');

    // Second insert lands after the previous one without blank-line pileup.
    insertKnowledgeAttachmentMarkdown(controller, attachment);
    expect(
      controller.text,
      'hello\n\n![shot.png](attachment://abc)\n\n![shot.png](attachment://abc)\n',
    );
  });
}
