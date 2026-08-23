library;

import 'personal_profile_fact.dart';
import 'personal_profile_store.dart';

class PersonalProfileSnapshot {
  const PersonalProfileSnapshot({required this.asOf, required this.facts});

  final DateTime asOf;
  final List<PersonalProfileFact> facts;

  bool get isEmpty => facts.isEmpty;
}

class PersonalProfileSnapshotBuilder {
  const PersonalProfileSnapshotBuilder(this.store, {this.maxFacts = 32});

  final PersonalProfileStore store;
  final int maxFacts;

  Future<PersonalProfileSnapshot> build({
    required String ownerUserId,
    required Set<String> activeDomainScopes,
    DateTime? at,
  }) async {
    final instant = (at ?? DateTime.now()).toUtc();
    final facts = await store.listActive(
      ownerUserId: ownerUserId,
      at: instant,
      activeDomainScopes: activeDomainScopes,
      limit: maxFacts,
    );
    return PersonalProfileSnapshot(
      asOf: instant,
      facts: List<PersonalProfileFact>.unmodifiable(facts),
    );
  }
}
