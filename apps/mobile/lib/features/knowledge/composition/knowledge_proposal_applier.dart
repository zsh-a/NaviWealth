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
           undoRunner ?? KnowledgeProposalUndoRunner(repo: repo, stamp: stamp);

  final KnowledgeRepository repo;
  final String ownerUserId;

  /// Mints one fresh [SyncMeta] per touched row (own HLC). Production
  /// wiring delegates to [MutationStamper.stamp]; tests inject a fake.
  final Future<SyncMeta> Function() stamp;
  final KnowledgeRoutineProposalApplier routineApplier;
  final KnowledgeConceptProposalApplier conceptApplier;
  final KnowledgeMergeProposalApplier mergeApplier;
  final KnowledgeProposalUndoRunner undoRunner;
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

    if (detected == CaptureKind.routine) {
      final state = await routineApplier.applyRoutine(plan);
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
      return existing == null
          ? state
          : state.copyWith(
              undoData: mergeKnowledgeProposalUndoData(
                state.undoData,
                restore: [snapshotKnowledgeNote(existing)],
              ),
            );
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
      appliedAt: _now(),
      undoData: existing == null
          ? knowledgeProposalUndoData(
              delete: [knowledgeProposalDeleteRow('knowledge_notes', note.id)],
            )
          : knowledgeProposalUndoData(
              restore: [snapshotKnowledgeNote(existing)],
            ),
      shortLabel:
          '$action：${_short(note.title.isEmpty ? note.bodyMd : note.title)}',
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
