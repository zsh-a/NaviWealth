library;

enum EvidenceAuthority {
  userConfirmed,
  sourceFact,
  deterministicDerived,
  modelDerived,
  legacyUnknown,
}

extension EvidenceAuthorityWire on EvidenceAuthority {
  String get wire => switch (this) {
    EvidenceAuthority.userConfirmed => 'user_confirmed',
    EvidenceAuthority.sourceFact => 'source_fact',
    EvidenceAuthority.deterministicDerived => 'deterministic_derived',
    EvidenceAuthority.modelDerived => 'model_derived',
    EvidenceAuthority.legacyUnknown => 'legacy_unknown',
  };

  static EvidenceAuthority parse(String? wire) => switch (wire) {
    'user_confirmed' => EvidenceAuthority.userConfirmed,
    'source_fact' => EvidenceAuthority.sourceFact,
    'deterministic_derived' => EvidenceAuthority.deterministicDerived,
    'model_derived' => EvidenceAuthority.modelDerived,
    _ => EvidenceAuthority.legacyUnknown,
  };
}

class EvidenceProvenance {
  const EvidenceProvenance({
    this.source,
    this.sourceId,
    this.sourceEventId,
    this.candidateId,
    this.algorithmVersion,
    this.observedAt,
  });

  final String? source;
  final String? sourceId;
  final String? sourceEventId;
  final String? candidateId;
  final String? algorithmVersion;
  final DateTime? observedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    if (source != null) 'source': source,
    if (sourceId != null) 'source_id': sourceId,
    if (sourceEventId != null) 'source_event_id': sourceEventId,
    if (candidateId != null) 'candidate_id': candidateId,
    if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
    if (observedAt != null)
      'observed_at': observedAt!.toUtc().toIso8601String(),
  };

  factory EvidenceProvenance.fromJson(Map<String, Object?> json) {
    return EvidenceProvenance(
      source: json['source'] as String?,
      sourceId: json['source_id'] as String?,
      sourceEventId: json['source_event_id'] as String?,
      candidateId: json['candidate_id'] as String?,
      algorithmVersion: json['algorithm_version'] as String?,
      observedAt: switch (json['observed_at']) {
        final String value => DateTime.tryParse(value)?.toUtc(),
        _ => null,
      },
    );
  }
}
