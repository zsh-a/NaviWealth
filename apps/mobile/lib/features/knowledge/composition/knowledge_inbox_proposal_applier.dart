/// Applies local-only KnowledgeOS inbox triage proposals.
///
/// These proposals are not chat proposal cards and do not go through the
/// cross-domain [ProposalApplier]. They are generated into the
/// `knowledge_inbox_triage` side-table and accepted from the Review tab, but
/// the mutation rules still belong outside widgets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../application/knowledge_promotion_service.dart';
import '../data/inbox_triage_repository.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class KnowledgeInboxProposalApplier {
  KnowledgeInboxProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
  }) : promotionService = KnowledgePromotionService(
         repository: repo,
         ownerUserId: ownerUserId,
         stamp: stamp,
       );

  final KnowledgeRepository repo;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;
  final KnowledgePromotionService promotionService;

  Future<KnowledgePromotionResult?> accept({
    required KnowledgeNote note,
    required InboxProposal proposal,
  }) async {
    final current = await repo.findNote(ownerUserId: ownerUserId, id: note.id);
    if (current == null) {
      throw StateError('note ${note.id} no longer exists');
    }

    final tagSet = current.tags.toSet();
    String? projectTag = current.projectTag;

    switch (proposal.kind) {
      case InboxProposalKind.classification:
        final kind = proposal.payload['kind'] as String?;
        if (kind == null || kind.trim().isEmpty) {
          throw StateError('classification proposal is missing kind');
        }
        return promotionService.promoteClassification(
          note: current,
          classification: kind.trim(),
          decisionOptions: _stringList(proposal.payload['decision_options']),
          expectedOutcome: _optionalString(
            proposal.payload['expected_outcome'],
          ),
        );
      case InboxProposalKind.tags:
        final raw = proposal.payload['tags'];
        var hasTag = false;
        if (raw is List) {
          for (final t in raw.whereType<String>()) {
            final lower = t.trim().toLowerCase();
            if (lower.isNotEmpty) {
              tagSet.add(lower);
              hasTag = true;
            }
          }
        }
        final pt = proposal.payload['project_tag'];
        if (pt is String && pt.trim().isNotEmpty) {
          projectTag = pt.trim();
        }
        if (!hasTag && projectTag == current.projectTag) {
          throw StateError('tags proposal has no applicable values');
        }
      case InboxProposalKind.linkToDecision:
        final raw = proposal.payload['related_decision_ids'];
        final decisionIds = <String>{};
        if (raw is List) {
          for (final id in raw.whereType<String>()) {
            final trimmed = id.trim();
            if (trimmed.isNotEmpty) {
              decisionIds.add(trimmed);
            }
          }
        }
        if (decisionIds.isEmpty) {
          throw StateError('decision-link proposal has no decision ids');
        }
        final fromKind = current.promotedToKind ?? KnowledgeEntryKind.note.name;
        final fromId = current.promotedToId ?? current.id;
        for (final decisionId in decisionIds) {
          final target = await repo.findDecision(
            ownerUserId: ownerUserId,
            id: decisionId,
          );
          if (target == null) {
            throw StateError('decision $decisionId no longer exists');
          }
          final meta = await stamp();
          await repo.upsertRelation(
            KnowledgeRelation(
              id: knowledgeRelationId(
                fromKind: fromKind,
                fromId: fromId,
                relation: KnowledgeRelationType.relatedTo,
                toKind: KnowledgeEntryKind.decision.name,
                toId: decisionId,
              ),
              fromKind: fromKind,
              fromId: fromId,
              relation: KnowledgeRelationType.relatedTo,
              toKind: KnowledgeEntryKind.decision.name,
              toId: decisionId,
              createdAt: meta.updatedAt,
              sync: meta,
            ),
          );
        }
        return null;
    }

    final meta = await stamp();
    final updated = KnowledgeNote(
      id: current.id,
      title: current.title,
      bodyMd: current.bodyMd,
      sourceUrl: current.sourceUrl,
      tags: tagSet.toList(growable: false),
      projectTag: projectTag,
      createdAt: current.createdAt,
      promotedToKind: current.promotedToKind,
      promotedToId: current.promotedToId,
      promotedAt: current.promotedAt,
      mergedIntoId: current.mergedIntoId,
      sync: meta,
    );
    await repo.upsertNote(updated);
    return null;
  }

  Future<KnowledgePromotionResult?> acceptAndResolve({
    required KnowledgeNote note,
    required InboxProposal proposal,
    required InboxTriageRepository triage,
  }) {
    return repo.transaction(() async {
      final result = await accept(note: note, proposal: proposal);
      await triage.resolve(
        noteId: note.id,
        kind: proposal.kind,
        status: InboxProposalStatus.accepted,
      );
      if (result != null) {
        await triage.supersedePending(
          noteId: note.id,
          kinds: const <InboxProposalKind>{InboxProposalKind.tags},
        );
      }
      return result;
    });
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

final knowledgeInboxProposalApplierProvider =
    FutureProvider<KnowledgeInboxProposalApplier>((ref) async {
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final stamper = await ref.watch(mutationStamperProvider.future);
      return KnowledgeInboxProposalApplier(
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
