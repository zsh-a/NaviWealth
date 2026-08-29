import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../domain/knowledge_models.dart';

class KnowledgeMergeProposalApplier {
  KnowledgeMergeProposalApplier({
    required this.repository,
    required this.ownerUserId,
    required this.stamp,
  });

  final KnowledgeRepository repository;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;

  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    final type = plan.get('entity_type');
    final primaryId = plan.get('primary_id');
    final duplicateIds = plan.payload['duplicate_ids'] is List
        ? (plan.payload['duplicate_ids'] as List<Object?>)
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];
    if (primaryId == null || duplicateIds.isEmpty) {
      throw ProposalApplyException('merge 缺少 primary_id / duplicate_ids');
    }
    final appliedAt = DateTime.now().toUtc();
    if (type == 'note') {
      final primary = await repository.findNote(
        ownerUserId: ownerUserId,
        id: primaryId,
      );
      if (primary == null) throw ProposalApplyException('note 不存在');
      final duplicates = await _notes(duplicateIds);
      final survivor = await repository.mergeNotes(
        primary: primary,
        duplicates: duplicates,
        stamp: stamp,
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: survivor.id,
        appliedTable: 'knowledge_notes',
        appliedAt: appliedAt,
        undoData: <String, Object?>{
          'restore': <Object?>[
            snapshotNote(primary),
            ...duplicates.map(snapshotNote),
          ],
        },
        shortLabel: '已合并 ${duplicates.length} 条笔记',
      );
    }
    if (type == 'decision') {
      final primary = await repository.findDecision(
        ownerUserId: ownerUserId,
        id: primaryId,
      );
      if (primary == null) throw ProposalApplyException('decision 不存在');
      final duplicates = await _decisions(duplicateIds);
      final survivor = await repository.mergeDecisions(
        primary: primary,
        duplicates: duplicates,
        stamp: stamp,
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: survivor.id,
        appliedTable: 'knowledge_decisions',
        appliedAt: appliedAt,
        undoData: <String, Object?>{
          'restore': <Object?>[
            snapshotDecision(primary),
            ...duplicates.map(snapshotDecision),
          ],
        },
        shortLabel: '已合并 ${duplicates.length} 条决策',
      );
    }
    throw ProposalApplyException('merge 只支持 note / decision');
  }

  Future<List<KnowledgeNote>> _notes(List<String> ids) async {
    final rows = <KnowledgeNote>[];
    for (final id in ids) {
      final row = await repository.findNote(ownerUserId: ownerUserId, id: id);
      if (row == null) throw ProposalApplyException('note $id 不存在');
      rows.add(row);
    }
    return rows;
  }

  Future<List<KnowledgeDecision>> _decisions(List<String> ids) async {
    final rows = <KnowledgeDecision>[];
    for (final id in ids) {
      final row = await repository.findDecision(
        ownerUserId: ownerUserId,
        id: id,
      );
      if (row == null) throw ProposalApplyException('decision $id 不存在');
      rows.add(row);
    }
    return rows;
  }
}

Map<String, Object?> snapshotNote(KnowledgeNote note) => <String, Object?>{
  'entity_type': 'note',
  'id': note.id,
  'title': note.title,
  'body': note.bodyMd,
  'source_url': note.sourceUrl,
  'tags': note.tags,
  'created_at': note.createdAt.toUtc().toIso8601String(),
  'merged_into_id': note.mergedIntoId,
};

Map<String, Object?> snapshotDecision(KnowledgeDecision decision) =>
    <String, Object?>{
      'entity_type': 'decision',
      'id': decision.id,
      'question': decision.question,
      'options': decision.options.map((value) => value.toJson()).toList(),
      'selected_label': decision.selectedLabel,
      'rationale': decision.rationaleMd,
      'expected_outcome': decision.expectedOutcome,
      'review_date': decision.reviewDate?.toUtc().toIso8601String(),
      'revisit_conditions': decision.revisitConditions
          .map((value) => value.toJson())
          .toList(),
      'actual_outcome': decision.actualOutcomeMd,
      'status': decision.status.wire,
      'superseded_by': decision.supersededByDecisionId,
      'decided_at': decision.decidedAt.toUtc().toIso8601String(),
      'merged_into_id': decision.mergedIntoId,
    };
