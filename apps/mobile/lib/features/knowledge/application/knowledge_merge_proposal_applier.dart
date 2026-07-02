import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_proposal_undo.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

/// Knowledge merge proposal writer owned by the Knowledge application layer.
class KnowledgeMergeProposalApplier {
  KnowledgeMergeProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final KnowledgeRepository repo;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;
  final DateTime Function() _now;

  Future<ProposalApplyState> applyMerge(ReadyProposalPlan plan) async {
    final entityType = plan.get('entity_type');
    final primaryId = plan.get('primary_id');
    final dupRaw = plan.payload['duplicate_ids'];
    final duplicateIds = dupRaw is List
        ? dupRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    if (primaryId == null || duplicateIds.isEmpty) {
      throw ProposalApplyException('merge 缺少 primary_id / duplicate_ids');
    }

    switch (entityType) {
      case 'note':
        final primary = await repo.findNote(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('note $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findNote(ownerUserId: ownerUserId, id: id),
          entityType: 'note',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 note');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgeNote(primary),
          for (final d in dups) snapshotKnowledgeNote(d),
        ];
        final survivor = await repo.mergeNotes(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
          mergedTitle: plan.get('merged_title'),
          mergedBody: plan.get('merged_body'),
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_notes',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.title}」',
        );
      case 'concept':
        final primary = await repo.findConcept(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('concept $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findConcept(ownerUserId: ownerUserId, id: id),
          entityType: 'concept',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 concept');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgeConcept(primary),
          for (final d in dups) snapshotKnowledgeConcept(d),
          ...await _conceptRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeConcepts(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
          mergedName: plan.get('merged_name'),
          mergedSummary: plan.get('merged_summary'),
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_concepts',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.name}」',
        );
      case 'principle':
        final primary = await repo.findPrinciple(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('principle $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findPrinciple(ownerUserId: ownerUserId, id: id),
          entityType: 'principle',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 principle');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgePrinciple(primary),
          for (final d in dups) snapshotKnowledgePrinciple(d),
          ...await _principleRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergePrinciples(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_principles',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.statement}」',
        );
      case 'assumption':
        final primary = await repo.findAssumption(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('assumption $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findAssumption(ownerUserId: ownerUserId, id: id),
          entityType: 'assumption',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 assumption');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgeAssumption(primary),
          for (final d in dups) snapshotKnowledgeAssumption(d),
          ...await _assumptionRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeAssumptions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_assumptions',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.statement}」',
        );
      case 'decision':
        final primary = await repo.findDecision(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('decision $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findDecision(ownerUserId: ownerUserId, id: id),
          entityType: 'decision',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 decision');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgeDecision(primary),
          for (final d in dups) snapshotKnowledgeDecision(d),
          ...await _decisionRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeDecisions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_decisions',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.question}」',
        );
      case 'experiment':
        final primary = await repo.findExperiment(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('experiment $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findExperiment(ownerUserId: ownerUserId, id: id),
          entityType: 'experiment',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 experiment');
        }
        final restore = <Map<String, Object?>>[
          snapshotKnowledgeExperiment(primary),
          for (final d in dups) snapshotKnowledgeExperiment(d),
        ];
        final survivor = await repo.mergeExperiments(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_experiments',
          appliedAt: _now(),
          undoData: knowledgeProposalUndoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.hypothesis}」',
        );
      default:
        throw ProposalApplyException(
          'merge entity_type 只支持 note / concept / principle / '
          'assumption / decision / experiment',
        );
    }
  }

  /// Hydrate ids into rows. Apply is all-or-nothing: missing ids usually
  /// mean the proposal is stale or points outside the active owner.
  Future<List<T>> _hydrate<T>(
    List<String> ids,
    Future<T?> Function(String) find, {
    required String entityType,
  }) async {
    final out = <T>[];
    final missing = <String>[];
    for (final id in ids) {
      final row = await find(id);
      if (row == null) {
        missing.add(id);
      } else {
        out.add(row);
      }
    }
    if (missing.isNotEmpty) {
      throw ProposalApplyException(
        '以下 $entityType 不存在或不属于当前用户: ${missing.join(", ")}',
      );
    }
    return out;
  }

  Future<List<Map<String, Object?>>> _conceptRepointSnapshots(
    KnowledgeConcept primary,
    List<KnowledgeConcept> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final concepts = await repo.listConcepts(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final concept in concepts)
        if (concept.id != primary.id &&
            !dupIds.contains(concept.id) &&
            concept.relatedConceptIds.any(dupIds.contains))
          snapshotKnowledgeConcept(concept),
    ];
  }

  Future<List<Map<String, Object?>>> _principleRepointSnapshots(
    KnowledgePrinciple primary,
    List<KnowledgePrinciple> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.principleIds.any(dupIds.contains))
          snapshotKnowledgeDecision(decision),
    ];
  }

  Future<List<Map<String, Object?>>> _assumptionRepointSnapshots(
    KnowledgeAssumption primary,
    List<KnowledgeAssumption> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    final experiments = await repo.listExperiments(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.assumptionIds.any(dupIds.contains))
          snapshotKnowledgeDecision(decision),
      for (final experiment in experiments)
        if (dupIds.contains(experiment.targetAssumptionId))
          snapshotKnowledgeExperiment(experiment),
    ];
  }

  Future<List<Map<String, Object?>>> _decisionRepointSnapshots(
    KnowledgeDecision primary,
    List<KnowledgeDecision> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.id != primary.id &&
            !dupIds.contains(decision.id) &&
            dupIds.contains(decision.supersededByDecisionId))
          snapshotKnowledgeDecision(decision),
    ];
  }
}

const int _allRows = 100000;
