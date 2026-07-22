/// KnowledgeOS implementation of [ProposalApplier]
/// (`docs/domains/knowledgeos-domain.md` §15.6).
///
/// Dispatches confirmed KnowledgeOS `propose_*` plans from the chat
/// propose-card to the matching Knowledge application writer. The
/// cross-domain composite routes KnowledgeOS kinds here through the
/// `kKnowledgePack` proposal applier route.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../application/knowledge_concept_proposal_applier.dart';
import '../application/knowledge_merge_proposal_applier.dart';
import '../application/knowledge_promotion_service.dart';
import '../application/knowledge_proposal_undo.dart';
import '../application/knowledge_routine_proposal_applier.dart';
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
    KnowledgeRoutineProposalApplier? routineApplier,
    KnowledgeConceptProposalApplier? conceptApplier,
    KnowledgeMergeProposalApplier? mergeApplier,
    KnowledgeProposalUndoRunner? undoRunner,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       routineApplier =
           routineApplier ??
           KnowledgeRoutineProposalApplier(
             repo: repo,
             stamp: stamp,
             createId: kKnowledgeUuid.v4,
             now: now,
           ),
       conceptApplier =
           conceptApplier ??
           KnowledgeConceptProposalApplier(
             repo: repo,
             ownerUserId: ownerUserId,
             stamp: stamp,
             now: now,
           ),
       mergeApplier =
           mergeApplier ??
           KnowledgeMergeProposalApplier(
             repo: repo,
             ownerUserId: ownerUserId,
             stamp: stamp,
             now: now,
           ),
       undoRunner =
           undoRunner ?? KnowledgeProposalUndoRunner(repo: repo, stamp: stamp),
       promotionService = KnowledgePromotionService(
         repository: repo,
         ownerUserId: ownerUserId,
         stamp: stamp,
       );

  final KnowledgeRepository repo;
  final String ownerUserId;

  /// Mints one fresh [SyncMeta] per touched row (own HLC). Production
  /// wiring delegates to [MutationStamper.stamp]; tests inject a fake.
  final Future<SyncMeta> Function() stamp;
  final KnowledgeRoutineProposalApplier routineApplier;
  final KnowledgeConceptProposalApplier conceptApplier;
  final KnowledgeMergeProposalApplier mergeApplier;
  final KnowledgeProposalUndoRunner undoRunner;
  final KnowledgePromotionService promotionService;
  final DateTime Function() _now;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'capture_upgrade' => await _applyCaptureUpgrade(plan),
        'knowledge_merge' => await mergeApplier.applyMerge(plan),
        'knowledge_routine' => await routineApplier.applyRoutine(plan),
        'knowledge_concept_link' => await conceptApplier.applyConceptLink(plan),
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
    if (state.status != ProposalApplyStatus.applied) return;
    final undoData = state.undoData;
    if (undoData == null) {
      throw ProposalApplyException('KnowledgeOS undo data missing');
    }
    await undoRunner.run(undoData);
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
    if (existing?.isPromoted ?? false) {
      throw ProposalApplyException(
        'note $noteId 已升级为 ${existing!.promotedToKind}',
      );
    }
    final sourceRelations = existing == null
        ? const <KnowledgeRelation>[]
        : await repo.listRelationsFrom(
            ownerUserId: ownerUserId,
            fromKind: KnowledgeEntryKind.note.name,
            fromId: existing.id,
          );

    if (detected == CaptureKind.routine) {
      if (existing == null) return routineApplier.applyRoutine(plan);
      final intervalDays = plan.num_('interval_days')?.toInt() ?? 0;
      final statement = plan.get('statement');
      if (statement == null || intervalDays <= 0) {
        throw ProposalApplyException(
          'capture_upgrade routine 缺少 statement / interval_days',
        );
      }
      final promoted = await promotionService.promoteToRoutine(
        existing,
        intervalDays: intervalDays,
        statement: statement,
        scope: plan.get('scope') ?? '*',
        nextDueAt: DateTime.tryParse(plan.get('next_due_at') ?? '')?.toUtc(),
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: promoted.id,
        appliedTable: promoted.kind.tableName,
        appliedAt: _now(),
        undoData: knowledgeProposalUndoData(
          delete: [
            knowledgeProposalDeleteRow(promoted.kind.tableName, promoted.id),
            ..._redirectedRelationDeletes(sourceRelations, promoted),
          ],
          restore: [
            snapshotKnowledgeNote(existing),
            ...sourceRelations.map(snapshotKnowledgeRelation),
          ],
        ),
        shortLabel: '已升级为 routine：${_short(statement)}',
      );
    }

    final meta = await stamp();
    final note = KnowledgeNote(
      id: existing?.id ?? kKnowledgeUuid.v4(),
      title: _captureTitle(plan, existing),
      bodyMd: _captureBody(plan, existing),
      sourceUrl: existing?.sourceUrl,
      tags: existing?.tags ?? const <String>[],
      projectTag: existing?.projectTag,
      createdAt: existing?.createdAt ?? meta.updatedAt,
      mergedIntoId: existing?.mergedIntoId,
      sync: meta,
    );
    await repo.upsertNote(note);

    if (detected != CaptureKind.note) {
      final promoted = await promotionService.promoteCapture(
        note: note,
        kind: detected,
        scope: plan.get('scope'),
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: promoted.id,
        appliedTable: promoted.kind.tableName,
        appliedAt: _now(),
        undoData: knowledgeProposalUndoData(
          delete: <Map<String, Object?>>[
            knowledgeProposalDeleteRow(promoted.kind.tableName, promoted.id),
            ..._redirectedRelationDeletes(sourceRelations, promoted),
            if (existing == null)
              knowledgeProposalDeleteRow('knowledge_notes', note.id),
          ],
          restore: existing == null
              ? const <Map<String, Object?>>[]
              : <Map<String, Object?>>[
                  snapshotKnowledgeNote(existing),
                  ...sourceRelations.map(snapshotKnowledgeRelation),
                ],
        ),
        shortLabel: '已升级为 ${detected.wire}：${_short(note.title)}',
      );
    }

    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: note.id,
      appliedTable: 'knowledge_notes',
      appliedAt: _now(),
      undoData: existing == null
          ? knowledgeProposalUndoData(
              delete: [knowledgeProposalDeleteRow('knowledge_notes', note.id)],
            )
          : knowledgeProposalUndoData(
              restore: [snapshotKnowledgeNote(existing)],
            ),
      shortLabel:
          '已更新 Note：${_short(note.title.isEmpty ? note.bodyMd : note.title)}',
    );
  }
}

Iterable<Map<String, Object?>> _redirectedRelationDeletes(
  List<KnowledgeRelation> relations,
  KnowledgePromotionResult promoted,
) sync* {
  for (final relation in relations) {
    if (relation.toKind == promoted.kind.name && relation.toId == promoted.id) {
      continue;
    }
    yield knowledgeProposalDeleteRow(
      'knowledge_relations',
      knowledgeRelationId(
        fromKind: promoted.kind.name,
        fromId: promoted.id,
        relation: relation.relation,
        toKind: relation.toKind,
        toId: relation.toId,
      ),
    );
  }
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
