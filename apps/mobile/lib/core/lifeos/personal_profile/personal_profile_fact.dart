library;

import '../../ai/contracts/context_evidence.dart';

enum PersonalProfileFactKind { goal, preference, constraint, rule }

extension PersonalProfileFactKindWire on PersonalProfileFactKind {
  String get wire => switch (this) {
    PersonalProfileFactKind.goal => 'goal',
    PersonalProfileFactKind.preference => 'preference',
    PersonalProfileFactKind.constraint => 'constraint',
    PersonalProfileFactKind.rule => 'rule',
  };

  static PersonalProfileFactKind? tryParse(String? wire) => switch (wire) {
    'goal' => PersonalProfileFactKind.goal,
    'preference' => PersonalProfileFactKind.preference,
    'constraint' => PersonalProfileFactKind.constraint,
    'rule' => PersonalProfileFactKind.rule,
    _ => null,
  };
}

class PersonalProfileFact {
  const PersonalProfileFact({
    required this.id,
    required this.ownerUserId,
    required this.kind,
    required this.key,
    required this.value,
    required this.summary,
    required this.authority,
    required this.provenance,
    required this.confidence,
    required this.validFrom,
    required this.createdAt,
    required this.updatedAt,
    this.domainScope,
    this.confirmedAt,
    this.validUntil,
    this.supersedesFactId,
  });

  final String id;
  final String ownerUserId;
  final PersonalProfileFactKind kind;
  final String key;
  final Object? value;
  final String summary;
  final String? domainScope;
  final EvidenceAuthority authority;
  final EvidenceProvenance provenance;
  final double confidence;
  final DateTime? confirmedAt;
  final DateTime validFrom;
  final DateTime? validUntil;
  final String? supersedesFactId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isActiveAt(DateTime at) {
    final instant = at.toUtc();
    return !validFrom.toUtc().isAfter(instant) &&
        (validUntil == null || validUntil!.toUtc().isAfter(instant));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'owner_user_id': ownerUserId,
    'kind': kind.wire,
    'key': key,
    'value': value,
    'summary': summary,
    if (domainScope != null) 'domain_scope': domainScope,
    'authority': authority.wire,
    'provenance': provenance.toJson(),
    'confidence': confidence,
    if (confirmedAt != null)
      'confirmed_at': confirmedAt!.toUtc().toIso8601String(),
    'valid_from': validFrom.toUtc().toIso8601String(),
    if (validUntil != null)
      'valid_until': validUntil!.toUtc().toIso8601String(),
    if (supersedesFactId != null) 'supersedes_fact_id': supersedesFactId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
