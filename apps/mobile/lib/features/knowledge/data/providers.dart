/// KnowledgeOS Riverpod composition.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_repository.dart';
import 'knowledge_search_service.dart';

const Uuid kKnowledgeUuid = Uuid();

final knowledgeRepositoryProvider = FutureProvider<KnowledgeRepository>((
  ref,
) async {
  return KnowledgeRepository(
    db: await ref.watch(appDatabaseProvider.future),
    outbox: await ref.watch(outboxStoreProvider.future),
  );
});

final knowledgeOwnerUserIdProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(currentUserIdProvider)();
});

final knowledgeNotesProvider = StreamProvider.autoDispose<List<KnowledgeNote>>((
  ref,
) async* {
  final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
  final repository = await ref.watch(knowledgeRepositoryProvider.future);
  yield* repository.watchNotes(ownerUserId: ownerUserId, limit: 200);
});

final knowledgeDecisionsProvider =
    StreamProvider.autoDispose<List<KnowledgeDecision>>((ref) async* {
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchDecisions(ownerUserId: ownerUserId, limit: 200);
    });

final knowledgeSearchServiceProvider = FutureProvider<KnowledgeSearchService>((
  ref,
) async {
  return KnowledgeSearchService(
    repository: await ref.watch(knowledgeRepositoryProvider.future),
    memoryRuntime: await ref.watch(memoryRuntimeProvider.future),
  );
});
