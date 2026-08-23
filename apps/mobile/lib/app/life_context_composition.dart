/// App-owned composition of active-domain state into one Life Context.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/contracts/event_record.dart';
import '../core/ai/contracts/memory_record.dart';
import '../core/ai/local/memory/providers.dart';
import '../core/auth/current_user.dart';
import '../core/auth/domain_scope.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/lifeos/life_context.dart';
import '../core/lifeos/life_signal.dart';
import '../core/lifeos/personal_profile/personal_profile_snapshot.dart';
import '../core/lifeos/personal_profile/providers.dart';
import '../features/life/data/life_events_provider.dart';

const Duration kLifeContextEventWindow = Duration(days: 14);
const Duration kLifeContextFreshnessWindow = Duration(days: 2);

final personalProfileSnapshotProvider = FutureProvider<PersonalProfileSnapshot>(
  (ref) async {
    final ownerUserId = await ref.watch(currentUserIdProvider)();
    final now = DateTime.now().toUtc();
    final builder = await ref.watch(
      personalProfileSnapshotBuilderProvider.future,
    );
    return builder.build(
      ownerUserId: ownerUserId,
      activeDomainScopes: ref.watch(activePersonalProfileDomainScopesProvider),
      at: now,
    );
  },
);

final lifeContextSnapshotProvider = FutureProvider<LifeContextSnapshot>((
  ref,
) async {
  final now = DateTime.now().toUtc();
  final runtime = await ref.watch(memoryRuntimeProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final activePacks = ref.watch(activeDomainPacksProvider);
  final activeDomains = <DomainScope>{
    for (final pack in activePacks) pack.scope,
  };
  final sourcePrefixes = <String>{
    for (final pack in activePacks) ...pack.memorySourcePrefixes,
  };
  final profile = await ref.watch(personalProfileSnapshotProvider.future);
  final recentChanges = await runtime.recentEvents(
    ownerUserId: ownerUserId,
    domains: activeDomains,
    window: kLifeContextEventWindow,
    limit: 100,
  );
  final history = sourcePrefixes.isEmpty
      ? const <MemoryRecord>[]
      : [
          for (final hit in await runtime.recall(
            ownerUserId: ownerUserId,
            kinds: const <MemoryKind>{MemoryKind.episodic},
            sourcePrefixes: sourcePrefixes,
            validAt: now,
            topK: 12,
          ))
            hit.record,
        ];
  return composeLifeContextSnapshot(
    ownerUserId: ownerUserId,
    generatedAt: now,
    profile: profile,
    activeDomains: activeDomains,
    lifeSignals: ref.watch(lifeSignalSnapshotProvider),
    recentChanges: recentChanges,
    relevantHistory: history,
  );
});

LifeContextSnapshot composeLifeContextSnapshot({
  required String ownerUserId,
  required DateTime generatedAt,
  required PersonalProfileSnapshot profile,
  required Set<DomainScope> activeDomains,
  required LifeSignalSnapshot lifeSignals,
  required List<EventRecord> recentChanges,
  required List<MemoryRecord> relevantHistory,
  Duration freshnessWindow = kLifeContextFreshnessWindow,
}) {
  final states = <LifeContextDomainState>[];
  for (final domain in activeDomains) {
    final domainChanges = recentChanges
        .where((event) => event.domain == domain)
        .toList(growable: false);
    final latestObservedAt = domainChanges.isEmpty
        ? null
        : domainChanges
              .map((event) => event.observedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final evaluated =
        lifeSignals.evaluatedSourceFamiliesByDomain[domain] ?? const <String>{};
    final freshness = switch (latestObservedAt) {
      final observed? when generatedAt.difference(observed) > freshnessWindow =>
        LifeContextFreshness.stale,
      final DateTime _ => LifeContextFreshness.fresh,
      null when evaluated.isNotEmpty => LifeContextFreshness.fresh,
      null => LifeContextFreshness.unavailable,
    };
    states.add(
      LifeContextDomainState(
        domain: domain,
        freshness: freshness,
        evaluatedSourceFamilies: Set<String>.unmodifiable(evaluated),
        signals: List<LifeEvent>.unmodifiable(
          lifeSignals.events.where((event) => event.domain == domain),
        ),
        latestObservedAt: latestObservedAt,
      ),
    );
  }
  return LifeContextSnapshot(
    ownerUserId: ownerUserId,
    generatedAt: generatedAt,
    profile: profile,
    activeDomains: activeDomains,
    domainStates: states,
    recentChanges: recentChanges.where(
      (event) => event.domain != null && activeDomains.contains(event.domain),
    ),
    relevantHistory: relevantHistory,
  );
}
