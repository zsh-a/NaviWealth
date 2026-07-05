/// KnowledgeOS share-intent handling.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifeos/share_intent.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
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
}
