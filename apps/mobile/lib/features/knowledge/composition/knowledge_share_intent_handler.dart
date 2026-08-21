/// KnowledgeOS share-intent handling.
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifeos/share_intent.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/attachments/knowledge_attachment_store.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_route_paths.dart';

class KnowledgeShareIntentHandler extends DomainShareIntentHandler {
  const KnowledgeShareIntentHandler() : super(priority: 100);

  @override
  Future<DomainShareIntentResult?> handle(
    Ref ref,
    SharedIntentPayload payload,
  ) async {
    if (payload.kind == SharedIntentKind.image) {
      return _handleImage(ref, payload);
    }
    if (!payload.isTextual) return null;
    final raw = payload.value.trim();
    if (raw.isEmpty) return null;

    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    final isUrl =
        payload.kind == SharedIntentKind.url ||
        raw.startsWith('http://') ||
        raw.startsWith('https://');
    final firstLine = raw.split('\n').first.trim();
    final title = knowledgeExcerpt(
      firstLine,
      max: kKnowledgeSharedTitleMaxChars,
    );

    await repo.upsertNote(
      KnowledgeNote(
        id: kKnowledgeUuid.v4(),
        title: title.isEmpty ? '(shared)' : title,
        bodyMd: raw,
        sourceUrl: isUrl ? raw : null,
        tags: const <String>['source:share'],
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      ),
    );

    return const DomainShareIntentResult(
      destinationPath: KnowledgeRoutes.inbox,
    );
  }

  /// Shared image → stored attachment + an Inbox note referencing it.
  ///
  /// Stays within the capture rule: a local file write and one note upsert,
  /// no synchronous LLM call. Attachments are device-local in phase A, so the
  /// handler declines cleanly where storage is unsupported (web).
  Future<DomainShareIntentResult?> _handleImage(
    Ref ref,
    SharedIntentPayload payload,
  ) async {
    final store = await ref.read(knowledgeAttachmentStoreProvider.future);
    if (!store.canWrite) return null;

    final file = XFile(payload.value);
    final bytes = await file.readAsBytes();
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    final noteId = kKnowledgeUuid.v4();

    final KnowledgeAttachment attachment;
    try {
      attachment = await store.importImage(
        ownerUserId: stamp.ownerUserId,
        fileName: file.name,
        bytes: bytes,
        noteId: noteId,
      );
    } on KnowledgeAttachmentImportRejected {
      return null;
    }

    final repo = await ref.read(knowledgeRepositoryProvider.future);
    await repo.upsertNote(
      KnowledgeNote(
        id: noteId,
        title: attachment.fileName,
        bodyMd: '![${attachment.fileName}](${attachment.markdownSrc})',
        tags: const <String>['source:share'],
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      ),
    );

    return const DomainShareIntentResult(
      destinationPath: KnowledgeRoutes.inbox,
    );
  }
}
