import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/hlc.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

enum KnowledgeEditFailure implements Exception { changed, missing }

final knowledgeEditServiceProvider = FutureProvider<KnowledgeEditService>((
  ref,
) async {
  return KnowledgeEditService(
    repository: await ref.watch(knowledgeRepositoryProvider.future),
    stamper: await ref.watch(mutationStamperProvider.future),
  );
});

/// Optimistic protection for explicit editor saves. Sync remains row-state LWW;
/// the local read/check/write is atomic and never revives a deleted source.
class KnowledgeEditService {
  const KnowledgeEditService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<KnowledgeNote> saveNote({
    required KnowledgeNote draft,
    required Hlc expectedHlc,
  }) async {
    final stamp = await _stamper.stamp();
    return _repository.transaction(() async {
      final current = await _repository.findNote(
        ownerUserId: stamp.ownerUserId,
        id: draft.id,
      );
      _check(current?.sync, expectedHlc);
      final saved = KnowledgeNote(
        id: draft.id,
        title: draft.title,
        bodyMd: draft.bodyMd,
        sourceUrl: draft.sourceUrl,
        tags: draft.tags,
        createdAt: current!.createdAt,
        mergedIntoId: current.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await _repository.upsertNote(saved);
      return saved;
    });
  }

  Future<KnowledgeDecision> saveDecision({
    required KnowledgeDecision draft,
    required Hlc expectedHlc,
  }) async {
    final stamp = await _stamper.stamp();
    return _repository.transaction(() async {
      final current = await _repository.findDecision(
        ownerUserId: stamp.ownerUserId,
        id: draft.id,
      );
      _check(current?.sync, expectedHlc);
      final saved = KnowledgeDecision(
        id: draft.id,
        question: draft.question,
        options: draft.options,
        selectedLabel: draft.selectedLabel,
        rationaleMd: draft.rationaleMd,
        expectedOutcome: draft.expectedOutcome,
        reviewDate: current!.reviewDate,
        revisitConditions: current.revisitConditions,
        actualOutcomeMd: current.actualOutcomeMd,
        status: current.status,
        supersededByDecisionId: current.supersededByDecisionId,
        decidedAt: current.decidedAt,
        mergedIntoId: current.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await _repository.upsertDecision(saved);
      return saved;
    });
  }

  void _check(SyncMeta? current, Hlc expectedHlc) {
    if (current == null || current.deletedAt != null) {
      throw KnowledgeEditFailure.missing;
    }
    if (current.hlc != expectedHlc) throw KnowledgeEditFailure.changed;
  }
}
