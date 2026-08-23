/// Fingerprinted, domain-neutral input for cross-domain Life synthesis.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../ai/contracts/context_evidence.dart';
import '../ai/contracts/event_record.dart';
import '../ai/contracts/memory_record.dart';
import '../auth/domain_scope.dart';
import 'life_signal.dart';
import 'personal_profile/personal_profile_fact.dart';
import 'personal_profile/personal_profile_snapshot.dart';

enum LifeContextFreshness { fresh, stale, unavailable }

@immutable
class LifeContextDomainState {
  const LifeContextDomainState({
    required this.domain,
    required this.freshness,
    required this.evaluatedSourceFamilies,
    required this.signals,
    this.latestObservedAt,
  });

  final DomainScope domain;
  final LifeContextFreshness freshness;
  final Set<String> evaluatedSourceFamilies;
  final List<LifeEvent> signals;
  final DateTime? latestObservedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'domain': domain.wire,
    'freshness': freshness.name,
    'evaluated_source_families': evaluatedSourceFamilies.toList()..sort(),
    'signals': [for (final signal in signals) signal.toJson()],
    if (latestObservedAt != null)
      'latest_observed_at': latestObservedAt!.toUtc().toIso8601String(),
  };

  Map<String, Object?> materialJson() => <String, Object?>{
    'domain': domain.wire,
    'freshness': freshness.name,
    'evaluated_source_families': evaluatedSourceFamilies.toList()..sort(),
    'signals': [
      for (final signal in signals)
        <String, Object?>{
          'id': signal.id,
          'domain': signal.domain.wire,
          'template': signal.template.name,
          'params': signal.params,
          'priority': signal.priority.name,
          if (signal.actionSuggestion != null)
            'action_suggestion': signal.actionSuggestion!.toJson(),
          'evidence': [for (final source in signal.evidence) source.toJson()],
        },
    ],
  };
}

@immutable
class LifeContextSnapshot {
  LifeContextSnapshot({
    required this.ownerUserId,
    required this.generatedAt,
    required this.profile,
    required Iterable<DomainScope> activeDomains,
    required Iterable<LifeContextDomainState> domainStates,
    required Iterable<EventRecord> recentChanges,
    required Iterable<MemoryRecord> relevantHistory,
  }) : activeDomains = List<DomainScope>.unmodifiable(
         activeDomains.toList()..sort((a, b) => a.wire.compareTo(b.wire)),
       ),
       domainStates = List<LifeContextDomainState>.unmodifiable(
         domainStates.toList()
           ..sort((a, b) => a.domain.wire.compareTo(b.domain.wire)),
       ),
       recentChanges = List<EventRecord>.unmodifiable(
         recentChanges.toList()..sort((a, b) {
           final occurred = b.occurredAt.compareTo(a.occurredAt);
           return occurred != 0 ? occurred : a.id.compareTo(b.id);
         }),
       ),
       relevantHistory = List<MemoryRecord>.unmodifiable(
         relevantHistory.toList()..sort((a, b) => a.id.compareTo(b.id)),
       ) {
    fingerprint = _fingerprint(materialJson());
  }

  final String ownerUserId;
  final DateTime generatedAt;
  final PersonalProfileSnapshot profile;
  final List<DomainScope> activeDomains;
  final List<LifeContextDomainState> domainStates;
  final List<EventRecord> recentChanges;
  final List<MemoryRecord> relevantHistory;
  late final String fingerprint;

  List<PersonalProfileFact> get activeGoals =>
      List<PersonalProfileFact>.unmodifiable(
        profile.facts.where(
          (fact) => fact.kind == PersonalProfileFactKind.goal,
        ),
      );
  List<PersonalProfileFact> get constraints =>
      List<PersonalProfileFact>.unmodifiable(
        profile.facts.where(
          (fact) => fact.kind == PersonalProfileFactKind.constraint,
        ),
      );

  bool get hasStaleDomain => domainStates.any(
    (state) => state.freshness != LifeContextFreshness.fresh,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'owner_user_id': ownerUserId,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'fingerprint': fingerprint,
    'active_domains': [for (final domain in activeDomains) domain.wire],
    'personal_profile': _profileJson(profile),
    'current_state': [for (final state in domainStates) state.toJson()],
    'recent_changes': [for (final event in recentChanges) event.toJson()],
    'active_goals': [for (final goal in activeGoals) goal.toJson()],
    'constraints': [for (final constraint in constraints) constraint.toJson()],
    'relevant_history': [for (final memory in relevantHistory) memory.toJson()],
  };

  Map<String, Object?> materialJson() => <String, Object?>{
    'owner_user_id': ownerUserId,
    'active_domains': [for (final domain in activeDomains) domain.wire],
    'personal_profile_fingerprint': _profileFingerprint(profile),
    'current_state': [for (final state in domainStates) state.materialJson()],
    'recent_changes': [
      for (final event in recentChanges) _materialEvent(event),
    ],
    'relevant_history': [
      for (final memory in relevantHistory) _materialMemory(memory),
    ],
  };
}

Map<String, Object?> _materialEvent(EventRecord event) => <String, Object?>{
  'id': event.id,
  if (event.domain != null) 'domain': event.domain!.wire,
  'kind': event.kind.wire,
  'occurred_at': event.occurredAt.toUtc().toIso8601String(),
  'source_identity': event.sourceIdentity.toJson(),
  'summary': event.summary,
  'facts': event.facts,
  'entities': event.entities.toList()..sort(),
  'importance': event.importance,
  'confidence': event.confidence,
};

Map<String, Object?> _profileJson(PersonalProfileSnapshot profile) =>
    <String, Object?>{
      'as_of': profile.asOf.toUtc().toIso8601String(),
      'fingerprint': _profileFingerprint(profile),
      'facts': [for (final fact in profile.facts) fact.toJson()],
    };

String _profileFingerprint(PersonalProfileSnapshot profile) =>
    _fingerprint(<String, Object?>{
      'facts': [
        for (final fact in profile.facts)
          <String, Object?>{
            'id': fact.id,
            'kind': fact.kind.wire,
            'key': fact.key,
            'value': fact.value,
            'summary': fact.summary,
            'domain_scope': fact.domainScope,
            'authority': fact.authority.wire,
            'provenance': fact.provenance.toJson(),
            'confidence': fact.confidence,
            'confirmed_at': fact.confirmedAt?.toUtc().toIso8601String(),
            'valid_from': fact.validFrom.toUtc().toIso8601String(),
            'valid_until': fact.validUntil?.toUtc().toIso8601String(),
            'supersedes_fact_id': fact.supersedesFactId,
          },
      ],
    });

Map<String, Object?> _materialMemory(MemoryRecord memory) => <String, Object?>{
  'id': memory.id,
  'kind': memory.kind.wire,
  'scope': memory.scope,
  'source': memory.source,
  'source_id': memory.sourceId,
  'summary': memory.summary,
  'payload': memory.payload,
  'entities': memory.entities.toList()..sort(),
  'importance': memory.importance,
  'confidence': memory.confidence,
  'valid_from': memory.validFrom?.toUtc().toIso8601String(),
  'valid_until': memory.validUntil?.toUtc().toIso8601String(),
};

String _fingerprint(Object? value) {
  final canonical = jsonEncode(_canonicalize(value));
  return 'sha256:${sha256.convert(utf8.encode(canonical))}';
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries = <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    final keys = entries.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(entries[key]),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) _canonicalize(item)];
  }
  if (value is DateTime) return value.toUtc().toIso8601String();
  return value;
}
