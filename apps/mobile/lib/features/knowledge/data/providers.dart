/// KnowledgeOS Riverpod composition.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../../core/time/current_time_provider.dart';
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

const int kKnowledgeInboxRecentNoteLimit = 8;

final knowledgeRecentNotesProvider =
    Provider.autoDispose<AsyncValue<List<KnowledgeNote>>>((ref) {
      return ref
          .watch(knowledgeNotesProvider)
          .whenData(
            (notes) => notes
                .take(kKnowledgeInboxRecentNoteLimit)
                .toList(growable: false),
          );
    });

final knowledgeDueReviewsProvider =
    StreamProvider.autoDispose<List<KnowledgeDecision>>((ref) async* {
      final asOf = ref.watch(currentTimeProvider);
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchDueReviews(
        ownerUserId: ownerUserId,
        asOf: asOf.toUtc(),
      );
    });

typedef KnowledgeRelationSubject = ({String kind, String id});

final knowledgeRelationsForObjectProvider = StreamProvider.autoDispose
    .family<List<KnowledgeRelation>, KnowledgeRelationSubject>((
      ref,
      subject,
    ) async* {
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchRelationsForObject(
        ownerUserId: ownerUserId,
        kind: subject.kind,
        id: subject.id,
      );
    });

final knowledgeSearchServiceProvider = FutureProvider<KnowledgeSearchService>((
  ref,
) async {
  return KnowledgeSearchService(
    repository: await ref.watch(knowledgeRepositoryProvider.future),
    memoryRuntime: await ref.watch(memoryRuntimeProvider.future),
  );
});

typedef KnowledgeLibrarySearchRequest = ({
  String query,
  String? kind,
  String? tag,
});

final knowledgeLibrarySearchProvider = FutureProvider.autoDispose
    .family<List<KnowledgeSearchHit>, KnowledgeLibrarySearchRequest>((
      ref,
      request,
    ) async {
      // Keep visible results in sync when a row is edited while the query is
      // still active.
      ref
        ..watch(knowledgeNotesProvider)
        ..watch(knowledgeDecisionsProvider);
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final service = await ref.watch(knowledgeSearchServiceProvider.future);
      final tag = request.tag;
      if (tag != null) {
        return service.searchNotes(
          ownerUserId: ownerUserId,
          query: request.query,
          tags: <String>{tag},
          limit: 50,
        );
      }
      final kind = request.kind;
      return service.searchKnowledge(
        ownerUserId: ownerUserId,
        query: request.query,
        types: kind == null ? null : <String>{kind},
        topK: 50,
      );
    });

typedef KnowledgeRelationSuggestionsRequest = ({String subjectId, String text});

final knowledgeRelationSuggestionsProvider = FutureProvider.autoDispose
    .family<List<KnowledgeSimilarityHit>, KnowledgeRelationSuggestionsRequest>((
      ref,
      request,
    ) async {
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final service = await ref.watch(knowledgeSearchServiceProvider.future);
      return service.findSimilarKnowledge(
        ownerUserId: ownerUserId,
        text: request.text,
        excludeId: request.subjectId,
        threshold: 0.72,
        topK: 12,
      );
    });

/// Grow the live query window on demand so edits/deletes cannot leave holes
/// between separately cached offset pages. One extra row signals more results.
final knowledgeLibraryNotesProvider = StreamProvider.autoDispose
    .family<List<KnowledgeNote>, ({int limit, String? tag})>((
      ref,
      request,
    ) async* {
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchNotes(
        ownerUserId: owner,
        limit: request.limit + 1,
        tag: request.tag,
        orderByUpdated: true,
      );
    });

final knowledgeLibraryDecisionsProvider = StreamProvider.autoDispose
    .family<List<KnowledgeDecision>, int>((ref, limit) async* {
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchDecisions(
        ownerUserId: owner,
        limit: limit + 1,
        orderByUpdated: true,
      );
    });

final knowledgeLibraryTagsProvider = StreamProvider.autoDispose<List<String>>((
  ref,
) async* {
  final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
  final repository = await ref.watch(knowledgeRepositoryProvider.future);
  yield* repository.watchNoteTags(ownerUserId: owner);
});
