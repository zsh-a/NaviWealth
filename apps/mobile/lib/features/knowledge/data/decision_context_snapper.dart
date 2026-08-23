/// Auto-capture for `KnowledgeDecision.contextSnapshot`
/// (`docs/domains/knowledgeos-domain.md` §3 + §9 — "为什么当时做错可解释").
///
/// Reads the last 7 days of cross-domain events via [MemoryRuntime]
/// and packs the top finance / health rows into a compact JSON map
/// the Decision row can hold inline. Non-blocking — any read failure
/// resolves to `null` so the user's Decision write still goes through;
/// the column being NULL is a normal state, not an error.
///
/// Independent of the writer UI: any caller that goes through
/// `KnowledgeRepository.upsertDecision` can pre-call this and pass
/// the result. (We avoid hardwiring into `upsertDecision` itself to
/// keep [KnowledgeRepository] a pure Drift wrapper — see §3 mapping.)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/domain_scope.dart';

const Duration kDecisionSnapshotWindow = Duration(days: 7);
const int kDecisionSnapshotPerDomainCap = 5;

class DecisionContextSnapper {
  const DecisionContextSnapper(this._ref);
  final Ref _ref;

  /// Build the snapshot map for [ownerUserId]. Returns `null` if the
  /// Memory Runtime isn't reachable or both event slices are empty —
  /// the caller stores `null` and the column stays NULL, which the
  /// detail page handles by simply not rendering the section.
  Future<Map<String, Object?>?> snapshot({
    required String ownerUserId,
    DateTime? now,
  }) async {
    final ts = (now ?? DateTime.now()).toUtc();
    try {
      final runtime = await _ref.read(memoryRuntimeProvider.future);
      final all = await runtime.recentEvents(
        ownerUserId: ownerUserId,
        domains: const <DomainScope>{DomainScope.finance, DomainScope.health},
        window: kDecisionSnapshotWindow,
        limit: 200,
      );
      final finance = _pickByDomain(all, DomainScope.finance);
      final health = _pickByDomain(all, DomainScope.health);
      if (finance.isEmpty && health.isEmpty) return null;
      return <String, Object?>{
        'captured_at': ts.toIso8601String(),
        'window_days': kDecisionSnapshotWindow.inDays,
        'recent_finance_events': finance,
        'recent_health_events': health,
        'counts': <String, Object?>{
          'finance_total': finance.length,
          'health_total': health.length,
        },
      };
    } catch (_) {
      // Memory layer not booted, opt-in race, embedder absent —
      // never block the Decision write on snapshot capture.
      return null;
    }
  }

  static List<Map<String, Object?>> _pickByDomain(
    List<EventRecord> events,
    DomainScope domain,
  ) {
    final filtered = events.where((event) => event.domain == domain).toList()
      ..sort((a, b) {
        // Importance first, then most recent.
        final cmp = b.importance.compareTo(a.importance);
        if (cmp != 0) return cmp;
        return b.occurredAt.compareTo(a.occurredAt);
      });
    return filtered
        .take(kDecisionSnapshotPerDomainCap)
        .map(_packOne)
        .toList(growable: false);
  }

  static Map<String, Object?> _packOne(EventRecord e) => <String, Object?>{
    'kind': e.kind.wire,
    'source_identity': e.sourceIdentity.toJson(),
    'occurred_at': e.occurredAt.toUtc().toIso8601String(),
    'title': ?e.title,
    'summary': e.summary,
    'importance': e.importance,
  };
}

final decisionContextSnapperProvider = Provider<DecisionContextSnapper>(
  DecisionContextSnapper.new,
);
