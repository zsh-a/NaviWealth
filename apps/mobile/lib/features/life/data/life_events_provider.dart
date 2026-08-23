import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';

/// Complete candidate observation used by both the Life feed and deterministic
/// Action outcome comparison. No raw journal / note / action rows are exposed.
final lifeSignalSnapshotProvider = Provider<LifeSignalSnapshot>((ref) {
  final events = <LifeEvent>[];
  final evaluatedSourceFamilies = <String>{};
  final evaluatedByDomain = <DomainScope, Set<String>>{};
  final now = DateTime.now().toUtc();
  for (final pack in ref.watch(activeDomainPacksProvider)) {
    final slice = pack.lifeSignalBuilder?.call(ref, now);
    if (slice == null) continue;
    events.addAll(slice.events);
    evaluatedSourceFamilies.addAll(slice.evaluatedSourceFamilies);
    evaluatedByDomain[pack.scope] = Set<String>.unmodifiable(
      slice.evaluatedSourceFamilies,
    );
  }

  events.sort((a, b) {
    final byPriority = a.priority.index.compareTo(b.priority.index);
    if (byPriority != 0) return byPriority;
    return b.at.compareTo(a.at);
  });
  return LifeSignalSnapshot(
    observedAt: now,
    events: List.unmodifiable(events),
    evaluatedSourceFamilies: Set.unmodifiable(evaluatedSourceFamilies),
    evaluatedSourceFamiliesByDomain: Map.unmodifiable(evaluatedByDomain),
  );
});

/// Signal-only Life feed candidates. Outcome evaluation consumes the snapshot
/// above so loading/error absence can never masquerade as a cleared signal.
final lifeEventCandidatesProvider = Provider<List<LifeEvent>>((ref) {
  return ref.watch(lifeSignalSnapshotProvider).events;
});

/// Bounded signal set rendered by the Life hub. Outcome evaluation uses the
/// complete candidate set above so a lower-ranked active signal is never
/// mistaken for a cleared outcome merely because the UI shows seven rows.
final lifeEventsProvider = Provider<List<LifeEvent>>((ref) {
  return List.unmodifiable(ref.watch(lifeEventCandidatesProvider).take(7));
});

/// Compact hero metrics for the Life brief (no extra I/O).
final lifeHeroSummaryProvider = Provider<LifeHeroSummary>((ref) {
  final signals = ref.watch(lifeEventsProvider);
  final packs = ref.watch(activeDomainPacksProvider);
  final high = signals
      .where((e) => e.priority == LifeSignalPriority.high)
      .length;
  final byDomain = <DomainScope, int>{};
  final highByDomain = <DomainScope, int>{};
  for (final e in signals) {
    byDomain[e.domain] = (byDomain[e.domain] ?? 0) + 1;
    if (e.priority == LifeSignalPriority.high) {
      highByDomain[e.domain] = (highByDomain[e.domain] ?? 0) + 1;
    }
  }
  return LifeHeroSummary(
    domainCount: packs.length,
    signalCount: signals.length,
    highPriorityCount: high,
    signalCountByDomain: Map.unmodifiable(byDomain),
    highCountByDomain: Map.unmodifiable(highByDomain),
  );
});

@immutable
class LifeHeroSummary {
  const LifeHeroSummary({
    required this.domainCount,
    required this.signalCount,
    required this.highPriorityCount,
    this.signalCountByDomain = const {},
    this.highCountByDomain = const {},
  });

  final int domainCount;
  final int signalCount;
  final int highPriorityCount;
  final Map<DomainScope, int> signalCountByDomain;
  final Map<DomainScope, int> highCountByDomain;

  /// Stage number: high-priority count when any, else total signals.
  int get primaryMetric =>
      highPriorityCount > 0 ? highPriorityCount : signalCount;

  bool get hasAttention => highPriorityCount > 0;

  bool get isCalm => signalCount == 0;

  int signalsFor(DomainScope scope) => signalCountByDomain[scope] ?? 0;

  int highFor(DomainScope scope) => highCountByDomain[scope] ?? 0;
}

/// Active domains for the Life workbench chips.
final lifeWorkbenchDomainsProvider = Provider<List<DomainPack>>((ref) {
  return ref.watch(activeDomainPacksProvider);
});
