/// KnowledgeOS implementation of [ProposalApplier]
/// (`docs/knowledgeos-domain.md` §15.6).
///
/// Dispatches confirmed KnowledgeOS `propose_*` plans from the chat
/// propose-card to the matching `KnowledgeRepository` write. The
/// cross-domain composite routes KnowledgeOS kinds here through the
/// `kKnowledgePack` proposal applier route.
///
/// Handled kinds:
///  - `capture_upgrade`        → Capture-sheet-equivalent promotion:
///                               routine rows are created and temp notes are
///                               tombstoned; other detected kinds update or
///                               create a candidate-tagged note.
///  - `knowledge_merge`        → `mergeNotes` / `mergeConcepts` /
///                               `mergePrinciples` / `mergeAssumptions` /
///                               `mergeDecisions` / `mergeExperiments`
///                               (§15.3 dedupe — assumption/principle/decision
///                               merges also re-point inbound references)
///  - `knowledge_routine`      → `upsertRoutine`
///  - `knowledge_concept_link` → `linkConcepts` (§14.2 — bidirectional edge)
///
/// Knowledge writes do **not** expose the 60s one-tap undo: `apply` returns
/// no `appliedAt`, so the card never offers it. Merge stays reversible at
/// the data layer (`mergedIntoId` + tombstone). [undo] is a safety net that
/// throws if ever reached. Inbox kinds are intentionally not handled here —
/// they flow through the Review-tab triage side-table, not chat-apply (§5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../data/capture_kind.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';

export 'knowledge_proposal_kinds.dart' show kKnowledgeProposalAppliedKinds;

/// Drift table-name prefix for KnowledgeOS rows — used by the composite to
/// route [ProposalApplier.undo] (which carries the table, not the kind).
const String kKnowledgeTablePrefix = 'knowledge_';

class KnowledgeProposalApplier implements ProposalApplier {
  KnowledgeProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
  });

  final KnowledgeRepository repo;
  final String ownerUserId;

  /// Mints one fresh [SyncMeta] per touched row (own HLC). Production
  /// wiring delegates to [MutationStamper.stamp]; tests inject a fake.
  final Future<SyncMeta> Function() stamp;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'capture_upgrade' => await _applyCaptureUpgrade(plan),
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

  Future<ProposalApplyState> _applyCaptureUpgrade(
    ReadyProposalPlan plan,
  ) async {
    final rawKind = plan.get('detected_kind');
    if (rawKind == null) {
      throw ProposalApplyException('capture_upgrade 缺少 detected_kind');
    }
    final detected = CaptureKind.parse(rawKind);
    if (detected == CaptureKind.note && rawKind != CaptureKind.note.wire) {
      throw ProposalApplyException(
        'capture_upgrade detected_kind 不支持: $rawKind',
      );
    }

    final noteId = plan.get('note_id');
    final existing = noteId == null
        ? null
        : await repo.findNote(ownerUserId: ownerUserId, id: noteId);
    if (noteId != null && existing == null) {
      throw ProposalApplyException('note $noteId 不存在');
    }

    if (detected == CaptureKind.routine) {
      final state = await _createRoutine(
        statement: _requireRoutineStatement(plan),
        intervalDays: _requireRoutineIntervalDays(plan),
        scope: plan.get('scope') ?? '*',
        nextDueAt: _parseOptionalUtc(plan.get('next_due_at')),
        summaryZh: plan.summaryZh,
      );
      if (existing != null) {
        final meta = await stamp();
        await repo.upsertNote(
          KnowledgeNote(
            id: existing.id,
            title: existing.title,
            bodyMd: existing.bodyMd,
            sourceUrl: existing.sourceUrl,
            tags: existing.tags,
            projectTag: existing.projectTag,
            createdAt: existing.createdAt,
            mergedIntoId: existing.mergedIntoId,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
      return state;
    }

    final meta = await stamp();
    final tags = <String>{...?existing?.tags};
    if (detected != CaptureKind.note) {
      tags.add('kind:${detected.wire}_candidate');
      final scope = plan.get('scope');
      if (scope != null) tags.add('scope:$scope');
    }

    final note = KnowledgeNote(
      id: existing?.id ?? kKnowledgeUuid.v4(),
      title: _captureTitle(plan, existing),
      bodyMd: _captureBody(plan, existing),
      sourceUrl: existing?.sourceUrl,
      tags: tags.toList(growable: false),
      projectTag: existing?.projectTag,
      createdAt: existing?.createdAt ?? meta.updatedAt,
      mergedIntoId: existing?.mergedIntoId,
      sync: meta,
    );
    await repo.upsertNote(note);

    final action = detected == CaptureKind.note ? '已更新 Note' : '已标记候选';
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: note.id,
      appliedTable: 'knowledge_notes',
      shortLabel:
          '$action：${_short(note.title.isEmpty ? note.bodyMd : note.title)}',
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
        final primary = await repo.findNote(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('note $primaryId 不存在');
        }
        final dups = <KnowledgeNote>[];
        final missing = <String>[];
        for (final id in duplicateIds) {
          final d = await repo.findNote(ownerUserId: ownerUserId, id: id);
          if (d == null) {
            missing.add(id);
          } else {
            dups.add(d);
          }
        }
        if (missing.isNotEmpty) {
          throw ProposalApplyException(
            '以下 note 不存在或不属于当前用户: ${missing.join(", ")}',
          );
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
        final primary = await repo.findConcept(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('concept $primaryId 不存在');
        }
        final dups = <KnowledgeConcept>[];
        final missing = <String>[];
        for (final id in duplicateIds) {
          final d = await repo.findConcept(ownerUserId: ownerUserId, id: id);
          if (d == null) {
            missing.add(id);
          } else {
            dups.add(d);
          }
        }
        if (missing.isNotEmpty) {
          throw ProposalApplyException(
            '以下 concept 不存在或不属于当前用户: ${missing.join(", ")}',
          );
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
        final survivor = await repo.mergePrinciples(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_principles',
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
        final survivor = await repo.mergeAssumptions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_assumptions',
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
        final survivor = await repo.mergeDecisions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_decisions',
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
        final survivor = await repo.mergeExperiments(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_experiments',
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

  Future<ProposalApplyState> _applyConceptLink(ReadyProposalPlan plan) async {
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
      shortLabel: '已关联「${a.name}」↔「${b.name}」',
    );
  }

  Future<ProposalApplyState> _applyRoutine(ReadyProposalPlan plan) async {
    return _createRoutine(
      statement: _requireRoutineStatement(plan),
      intervalDays: _requireRoutineIntervalDays(plan),
      scope: plan.get('scope') ?? '*',
      nextDueAt: _parseOptionalUtc(plan.get('next_due_at')),
      summaryZh: plan.summaryZh,
    );
  }

  Future<ProposalApplyState> _createRoutine({
    required String statement,
    required int intervalDays,
    required String scope,
    required DateTime? nextDueAt,
    required String summaryZh,
  }) async {
    final meta = await stamp();
    final routine = KnowledgeRoutine(
      id: kKnowledgeUuid.v4(),
      statement: statement,
      intervalDays: intervalDays,
      nextDueAt: nextDueAt ?? meta.updatedAt.add(Duration(days: intervalDays)),
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
      shortLabel: '已建立 Routine：${summaryZh.isEmpty ? statement : summaryZh}',
    );
  }
}

String _requireRoutineStatement(ReadyProposalPlan plan) {
  final statement = plan.get('statement');
  if (statement == null) {
    throw ProposalApplyException('routine 缺少 statement / interval_days');
  }
  return statement;
}

int _requireRoutineIntervalDays(ReadyProposalPlan plan) {
  final intervalDays = plan.num_('interval_days')?.toInt() ?? 0;
  if (intervalDays <= 0) {
    throw ProposalApplyException('routine 缺少 statement / interval_days');
  }
  return intervalDays;
}

DateTime? _parseOptionalUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

String _captureTitle(ReadyProposalPlan plan, KnowledgeNote? existing) {
  final polished = plan.get('polished_title');
  if (polished != null) return polished;
  if (existing != null && existing.title.trim().isNotEmpty) {
    return existing.title.trim();
  }
  final statement = plan.get('statement');
  if (statement != null) {
    return _short(statement, max: kKnowledgeHeadlineExcerptMaxChars);
  }
  final source = plan.get('source_text');
  if (source != null) {
    return _short(
      source.split('\n').first.trim(),
      max: kKnowledgeHeadlineExcerptMaxChars,
    );
  }
  return '';
}

String _captureBody(ReadyProposalPlan plan, KnowledgeNote? existing) {
  final polished = plan.get('polished_body');
  if (polished != null) return polished;
  if (existing != null && existing.bodyMd.trim().isNotEmpty) {
    return existing.bodyMd;
  }
  return plan.get('source_text') ?? plan.get('statement') ?? '';
}

String _short(String value, {int max = kKnowledgeInlineExcerptMaxChars}) {
  final trimmed = value.trim();
  return knowledgeExcerpt(trimmed, max: max);
}

/// KnowledgeOS applier wiring. Resolves the repo + a per-row [SyncMeta]
/// factory from the stamper. `kKnowledgePack` uses this provider to build
/// its cross-domain proposal route.
final knowledgeProposalApplierProvider =
    FutureProvider<KnowledgeProposalApplier>((ref) async {
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final stamper = await ref.watch(mutationStamperProvider.future);
      return KnowledgeProposalApplier(
        repo: repo,
        ownerUserId: ownerUserId,
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
    });
