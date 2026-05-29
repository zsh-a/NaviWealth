/// KnowledgeOS Decision → Memory indexer
/// (`docs/knowledgeos-domain.md` §3 — "写一份,索引两次").
///
/// Subscribes to the decisions stream when the Knowledge domain is
/// opt-in and mirrors each row into Memory as `kind='episodic'` so
/// cross-domain Recall via `build_context` finds them without
/// special-casing KnowledgeOS.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_object_memory_indexers.dart'
    show kKnowledgeDecisionMemorySource, subscribeKnowledgeIndexer;

class KnowledgeDecisionMemoryIndexer {
  const KnowledgeDecisionMemoryIndexer();

  /// Reindex the supplied list. Idempotent — uses a stable id derived
  /// from the source decision so re-runs overwrite the same row.
  Future<void> reindex(
    MemoryRuntime runtime,
    List<KnowledgeDecision> decisions, {
    required String ownerUserId,
  }) async {
    final now = DateTime.now().toUtc();
    for (final d in decisions) {
      final memoryId = '$kKnowledgeDecisionMemorySource:episodic:${d.id}';
      final memory = MemoryRecord(
        id: memoryId,
        kind: MemoryKind.episodic,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeDecisionMemorySource,
        sourceId: d.id,
        title: d.question,
        summary: _summarize(d),
        payload: <String, Object?>{
          'context':
              'decision recorded at ${d.decidedAt.toUtc().toIso8601String()}',
          'decision': d.selectedLabel,
          'reasoning': d.rationaleMd,
          'outcome': <String, Object?>{
            'expected': d.expectedOutcome,
            'actual': d.actualOutcomeMd,
            'status': d.status.wire,
          },
          'principle_ids': d.principleIds,
          'assumption_ids': d.assumptionIds,
          'review_date': d.reviewDate?.toUtc().toIso8601String(),
        },
        entities: <String>{
          'knowledge_decision',
          d.id,
          ...d.principleIds.map((id) => 'principle:$id'),
          ...d.assumptionIds.map((id) => 'assumption:$id'),
        },
        // Active decisions outrank superseded ones for recall.
        importance: _importance(d.status),
        confidence: 0.9,
        validFrom: d.decidedAt.toUtc(),
        // expired / falsified / superseded decisions stay queryable but
        // are flagged via status in the payload; no validUntil clamp so
        // historical recall keeps working ("我去年为什么决定 X").
        createdAt: d.decidedAt.toUtc(),
        updatedAt: now,
      );
      await runtime.remember(memory);
    }
  }

  String _summarize(KnowledgeDecision d) {
    final tail = d.rationaleMd.isEmpty
        ? ''
        : ' — ${d.rationaleMd.length > 200 ? '${d.rationaleMd.substring(0, 200)}…' : d.rationaleMd}';
    final sel = d.selectedLabel.isEmpty ? '(undecided)' : d.selectedLabel;
    return '${d.question} → $sel$tail';
  }

  double _importance(DecisionStatus status) {
    return switch (status) {
      DecisionStatus.active => 0.85,
      DecisionStatus.verified => 0.9,
      DecisionStatus.draft => 0.5,
      DecisionStatus.paused => 0.6,
      DecisionStatus.expired => 0.55,
      DecisionStatus.falsified => 0.7,
      DecisionStatus.superseded => 0.7,
    };
  }
}

/// Wires the indexer to the decisions stream via the shared
/// [subscribeKnowledgeIndexer] plumbing (opt-in gate + re-entrance guard
/// + dispose all enforced there). Stays inert when Knowledge is OFF.
final knowledgeDecisionMemoryIndexerProvider = Provider<void>((ref) {
  const indexer = KnowledgeDecisionMemoryIndexer();
  subscribeKnowledgeIndexer<KnowledgeDecision>(
    ref,
    streamOf: (repo, uid) => repo.watchDecisions(ownerUserId: uid, limit: 200),
    reindex: indexer.reindex,
  );
});
