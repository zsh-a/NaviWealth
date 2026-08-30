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
    Provider.autoDispose<AsyncValue<List<KnowledgeDecision>>>((ref) {
      final now = DateTime.now().toUtc();
      return ref.watch(knowledgeDecisionsProvider).whenData((decisions) {
        final due = decisions
            .where((decision) {
              final reviewDate = decision.reviewDate;
              return reviewDate != null &&
                  !reviewDate.toUtc().isAfter(now) &&
                  switch (decision.status) {
                    DecisionStatus.active ||
                    DecisionStatus.draft ||
                    DecisionStatus.paused => true,
                    _ => false,
                  };
            })
            .toList(growable: false);
        due.sort(
          (a, b) => a.reviewDate!.toUtc().compareTo(b.reviewDate!.toUtc()),
        );
        return due;
      });
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

typedef KnowledgeLibrarySearchRequest = ({String query, String? kind});

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
      final kind = request.kind;
      return service.searchKnowledge(
        ownerUserId: ownerUserId,
        query: request.query,
        types: kind == null ? null : <String>{kind},
        topK: 50,
      );
    });
