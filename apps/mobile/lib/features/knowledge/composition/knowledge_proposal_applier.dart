/// KnowledgeOS implementation of [ProposalApplier]
/// (`docs/knowledgeos-domain.md` §15.6).
///
/// Dispatches confirmed KnowledgeOS `propose_*` plans from the chat
/// propose-card to the matching `KnowledgeRepository` write. Before this
/// existed, every knowledge proposal confirmed in chat hit the Finance
/// applier and failed with "unknown proposal kind"; the composite
/// (`composite_proposal_applier.dart`) now routes `knowledge_*` kinds here.
///
/// Handled kinds:
///  - `knowledge_merge`        → `mergeNotes` / `mergeConcepts` (§15.3 dedupe)
///  - `knowledge_routine`      → `upsertRoutine`
///  - `knowledge_concept_link` → `linkConcepts` (§14.2 — bidirectional edge)
///
/// Knowledge writes do **not** expose the 60s one-tap undo: `apply` returns
/// no `appliedAt`, so the card never offers it. Merge stays reversible at
/// the data layer (`mergedIntoId` + tombstone). [undo] is a safety net that
/// throws if ever reached. Capture / inbox kinds are intentionally not
/// handled here — they flow through the Review-tab triage side-table, not
/// chat-apply (§5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

/// Proposal kinds owned by KnowledgeOS. The composite routes these to
/// [KnowledgeProposalApplier]; everything else falls through to Finance.
const Set<String> kKnowledgeProposalAppliedKinds = <String>{
  'knowledge_merge',
  'knowledge_routine',
  'knowledge_concept_link',
};

/// Drift table-name prefix for KnowledgeOS rows — used by the composite to
/// route [ProposalApplier.undo] (which carries the table, not the kind).
const String kKnowledgeTablePrefix = 'knowledge_';

class KnowledgeProposalApplier implements ProposalApplier {
  KnowledgeProposalApplier({required this.repo, required this.stamp});

  final KnowledgeRepository repo;

  /// Mints one fresh [SyncMeta] per touched row (own HLC). Production
  /// wiring delegates to [MutationStamper.stamp]; tests inject a fake.
  final Future<SyncMeta> Function() stamp;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'knowledge_merge' => await _applyMerge(plan),
        'knowledge_routine' => await _applyRoutine(plan),
        'knowledge_concept_link' => await _applyConceptLink(plan),
        _ => throw ProposalApplyException(
          'unknown knowledge proposal kind: ${plan.kind}',
        ),
      };
    } on ProposalApplyException {
      rethrow;
    } catch (e) {
      throw ProposalApplyException(e.toString());
    }
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    // Knowledge apply returns no `appliedAt`, so the card never surfaces
    // the 60s undo. This is a safety net only.
    throw ProposalApplyException(
      'KnowledgeOS 暂不支持一键撤销；合并可在数据层经 mergedIntoId 恢复',
    );
  }

  Future<ProposalApplyState> _applyMerge(ReadyProposalPlan plan) async {
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
        final primary = await repo.findNote(primaryId);
        if (primary == null) {
          throw ProposalApplyException('note $primaryId 不存在');
        }
        final dups = <KnowledgeNote>[];
        for (final id in duplicateIds) {
          final d = await repo.findNote(id);
          if (d != null) dups.add(d);
        }
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 note');
        }
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
          shortLabel: '已合并 ${dups.length} 条到「${survivor.title}」',
        );
      case 'concept':
        final primary = await repo.findConcept(primaryId);
        if (primary == null) {
          throw ProposalApplyException('concept $primaryId 不存在');
        }
        final dups = <KnowledgeConcept>[];
        for (final id in duplicateIds) {
          final d = await repo.findConcept(id);
          if (d != null) dups.add(d);
        }
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 concept');
        }
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
          shortLabel: '已合并 ${dups.length} 条到「${survivor.name}」',
        );
      default:
        throw ProposalApplyException('merge entity_type 只支持 note / concept');
    }
  }

  Future<ProposalApplyState> _applyConceptLink(ReadyProposalPlan plan) async {
    final fromId = plan.get('from_concept_id');
    final toId = plan.get('to_concept_id');
    if (fromId == null || toId == null || fromId == toId) {
      throw ProposalApplyException('concept_link 缺少 from/to 或两者相同');
    }
    final a = await repo.findConcept(fromId);
    final b = await repo.findConcept(toId);
    if (a == null || b == null) {
      throw ProposalApplyException('concept_link 引用的概念不存在');
    }
    final (updatedA, _) = await repo.linkConcepts(a: a, b: b, stamp: stamp);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: updatedA.id,
      appliedTable: 'knowledge_concepts',
      shortLabel: '已关联「${a.name}」↔「${b.name}」',
    );
  }

  Future<ProposalApplyState> _applyRoutine(ReadyProposalPlan plan) async {
    final statement = plan.get('statement');
    final intervalDays = plan.num_('interval_days')?.toInt() ?? 0;
    if (statement == null || intervalDays <= 0) {
      throw ProposalApplyException('routine 缺少 statement / interval_days');
    }
    final scope = plan.get('scope') ?? '*';
    final meta = await stamp();
    final nextDue =
        DateTime.tryParse(plan.get('next_due_at') ?? '') ??
        meta.updatedAt.add(Duration(days: intervalDays));
    final routine = KnowledgeRoutine(
      id: kKnowledgeUuid.v4(),
      statement: statement,
      intervalDays: intervalDays,
      nextDueAt: nextDue,
      scope: scope,
      status: RoutineStatus.active,
      createdAt: meta.updatedAt,
      sync: meta,
    );
    await repo.upsertRoutine(routine);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: routine.id,
      appliedTable: 'knowledge_routines',
      shortLabel: '已建立 Routine：$statement',
    );
  }
}

/// KnowledgeOS applier wiring. Resolves the repo + a per-row [SyncMeta]
/// factory from the stamper. Used by `knowledge_bootstrap.dart` to build
/// the composite applier alongside Finance.
final knowledgeProposalApplierProvider = FutureProvider<KnowledgeProposalApplier>(
  (ref) async {
    final repo = await ref.watch(knowledgeRepositoryProvider.future);
    final stamper = await ref.watch(mutationStamperProvider.future);
    return KnowledgeProposalApplier(
      repo: repo,
      stamp: () async {
        final s = await stamper.stamp();
        return SyncMeta(
          ownerUserId: s.ownerUserId,
          updatedAt: s.now,
          updatedByDevice: s.deviceId,
          hlc: s.hlc,
        );
      },
    );
  },
);
