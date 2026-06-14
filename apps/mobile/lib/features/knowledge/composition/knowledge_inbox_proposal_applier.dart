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

import '../data/inbox_triage_repository.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class KnowledgeInboxProposalApplier {
  KnowledgeInboxProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
  });

  final KnowledgeRepository repo;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;

  Future<void> accept({
    required KnowledgeNote note,
    required InboxProposal proposal,
  }) async {
    final current = await repo.findNote(ownerUserId: ownerUserId, id: note.id);
    if (current == null) return;

    final tagSet = current.tags.toSet();
    String? projectTag = current.projectTag;

    switch (proposal.kind) {
      case InboxProposalKind.classification:
        final kind = proposal.payload['kind'] as String?;
        if (kind == null || kind.isEmpty) return;
        tagSet.add('kind:$kind');
      case InboxProposalKind.tags:
        final raw = proposal.payload['tags'];
        if (raw is List) {
          for (final t in raw.whereType<String>()) {
            final lower = t.trim().toLowerCase();
            if (lower.isNotEmpty) tagSet.add(lower);
          }
        }
        final pt = proposal.payload['project_tag'];
        if (pt is String && pt.trim().isNotEmpty) {
          projectTag = pt.trim();
        }
      case InboxProposalKind.linkToDecision:
        final raw = proposal.payload['related_decision_ids'];
        if (raw is List) {
          for (final id in raw.whereType<String>()) {
            final trimmed = id.trim();
            if (trimmed.isNotEmpty) tagSet.add('decision:$trimmed');
          }
        }
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
      mergedIntoId: current.mergedIntoId,
      sync: meta,
    );
    await repo.upsertNote(updated);
  }
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
