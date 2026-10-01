import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_edit_service.dart';

final knowledgeDecisionReviewServiceProvider =
    FutureProvider<KnowledgeDecisionReviewService>((ref) async {
      return KnowledgeDecisionReviewService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

class KnowledgeDecisionReviewService {
  const KnowledgeDecisionReviewService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<void> review({
    required KnowledgeDecision baseline,
    required KnowledgeDecisionReviewDraft draft,
  }) async {
    final stamp = await _stamper.stamp();
    await _repository.transaction(() async {
      final current = await _repository.findDecision(
        ownerUserId: stamp.ownerUserId,
        id: baseline.id,
      );
      if (current == null || current.sync.deletedAt != null) {
        throw KnowledgeEditFailure.missing;
      }
      if (!KnowledgeDecisionReviewDraft.fromDecision(baseline)
          .matchesDecision(current)) {
        throw KnowledgeEditFailure.changed;
      }
      if (draft.matchesDecision(current)) return;
      await _repository.upsertDecision(
        KnowledgeDecision(
          id: current.id,
          question: current.question,
          options: current.options,
          selectedLabel: current.selectedLabel,
          rationaleMd: current.rationaleMd,
          expectedOutcome: current.expectedOutcome,
          reviewDate: draft.reviewDate,
          revisitConditions: draft.revisitConditions,
          actualOutcomeMd: draft.actualOutcomeMd,
          status: draft.status,
          supersededByDecisionId: current.supersededByDecisionId,
          decidedAt: current.decidedAt,
          mergedIntoId: current.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    });
  }
}
