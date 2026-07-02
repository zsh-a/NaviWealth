import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_proposal_undo.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';

/// Concept proposal writer owned by the Knowledge application layer.
class KnowledgeConceptProposalApplier {
  KnowledgeConceptProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final KnowledgeRepository repo;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;
  final DateTime Function() _now;

  Future<ProposalApplyState> applyConceptLink(ReadyProposalPlan plan) async {
    final fromId = plan.get('from_concept_id');
    final toId = plan.get('to_concept_id');
    if (fromId == null || toId == null || fromId == toId) {
      throw ProposalApplyException('concept_link 缺少 from/to 或两者相同');
    }
    final a = await repo.findConcept(ownerUserId: ownerUserId, id: fromId);
    final b = await repo.findConcept(ownerUserId: ownerUserId, id: toId);
    if (a == null || b == null) {
      throw ProposalApplyException('concept_link 引用的概念不存在');
    }
    final (updatedA, _) = await repo.linkConcepts(a: a, b: b, stamp: stamp);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: updatedA.id,
      appliedTable: 'knowledge_concepts',
      appliedAt: _now(),
      undoData: knowledgeProposalUndoData(
        restore: [snapshotKnowledgeConcept(a), snapshotKnowledgeConcept(b)],
      ),
      shortLabel: '已关联「${a.name}」↔「${b.name}」',
    );
  }
}
