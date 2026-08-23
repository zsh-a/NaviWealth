/// Typed cross-domain event log entry.
///
/// Events capture what happened, when the source says it happened, when the
/// device observed it, and the exact source-row revision that supports the
/// claim. Every event has a stable evidence identity; infrastructure events
/// use a null domain but otherwise follow the same contract.
library;

import 'dart:convert';

import '../../auth/domain_scope.dart';
import 'evidence_anchor.dart';
import 'source_identity.dart';

class EventKind {
  const EventKind({required this.namespace, required this.name})
    : assert(namespace != ''),
      assert(name != '');

  factory EventKind.domain(DomainScope domain, String name) =>
      EventKind(namespace: domain.wire, name: name);

  factory EventKind.fromWire(String wire) {
    final normalized = wire.trim();
    final separator = normalized.indexOf('.');
    if (separator <= 0 || separator == normalized.length - 1) {
      throw FormatException('Invalid EventKind wire value: $wire');
    }
    return EventKind(
      namespace: normalized.substring(0, separator),
      name: normalized.substring(separator + 1),
    );
  }

  final String namespace;
  final String name;

  String get wire => '$namespace.$name';

  @override
  bool operator ==(Object other) =>
      other is EventKind && other.namespace == namespace && other.name == name;

  @override
  int get hashCode => Object.hash(namespace, name);
}

class EventRecord {
  EventRecord({
    required this.id,
    required this.domain,
    required this.kind,
    required this.occurredAt,
    required this.observedAt,
    required this.sourceIdentity,
    required this.ownerUserId,
    required this.summary,
    required this.facts,
    required this.entities,
    this.title,
    this.importance = 0.5,
    this.confidence = 1.0,
  }) : assert(id != ''),
       assert(ownerUserId != ''),
       assert(summary != ''),
       assert(domain == null || kind.namespace == domain.wire),
       assert(domain == sourceIdentity.domain),
       assert(importance >= 0 && importance <= 1),
       assert(confidence >= 0 && confidence <= 1);

  final String id;
  final DomainScope? domain;
  final EventKind kind;
  final DateTime occurredAt;
  final DateTime observedAt;
  final SourceIdentity sourceIdentity;
  final String ownerUserId;
  final String? title;
  final String summary;
  final Map<String, Object?> facts;
  final Set<String> entities;
  final double importance;
  final double confidence;

  EvidenceAnchor get evidenceAnchor =>
      EvidenceAnchor.fromSource(sourceIdentity, label: title);

  EventRecord copyWith({
    DomainScope? domain,
    EventKind? kind,
    DateTime? occurredAt,
    DateTime? observedAt,
    SourceIdentity? sourceIdentity,
    String? title,
    String? summary,
    Map<String, Object?>? facts,
    Set<String>? entities,
    double? importance,
    double? confidence,
  }) => EventRecord(
    id: id,
    ownerUserId: ownerUserId,
    domain: domain ?? this.domain,
    kind: kind ?? this.kind,
    occurredAt: occurredAt ?? this.occurredAt,
    observedAt: observedAt ?? this.observedAt,
    sourceIdentity: sourceIdentity ?? this.sourceIdentity,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    facts: facts ?? this.facts,
    entities: entities ?? this.entities,
    importance: importance ?? this.importance,
    confidence: confidence ?? this.confidence,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (domain != null) 'domain': domain!.wire,
    'kind': kind.wire,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'observed_at': observedAt.toUtc().toIso8601String(),
    'source_identity': sourceIdentity.toJson(),
    'owner_user_id': ownerUserId,
    if (title != null) 'title': title,
    'summary': summary,
    'facts': facts,
    'entities': entities.toList(growable: false)..sort(),
    'importance': importance,
    'confidence': confidence,
  };

  factory EventRecord.fromJson(Map<String, Object?> json) {
    final domainWire = json['domain'] as String?;
    final domain = domainWire == null ? null : _requiredDomain(domainWire);
    final sourceJson = json['source_identity'] as Map;
    final entitiesRaw = json['entities'] as List;
    return EventRecord(
      id: json['id'] as String,
      domain: domain,
      kind: EventKind.fromWire(json['kind'] as String),
      occurredAt: _requiredDateTime(json['occurred_at'], 'occurred_at'),
      observedAt: _requiredDateTime(json['observed_at'], 'observed_at'),
      sourceIdentity: SourceIdentity.fromJson(
        sourceJson.cast<String, Object?>(),
      ),
      ownerUserId: json['owner_user_id'] as String,
      title: json['title'] as String?,
      summary: json['summary'] as String,
      facts: factsOf(json['facts']),
      entities: entitiesRaw.whereType<String>().toSet(),
      importance: (json['importance'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  String encodeFacts() => jsonEncode(facts);

  static Map<String, Object?> decodeFacts(String value) =>
      factsOf(jsonDecode(value));

  String encodeEntities() =>
      jsonEncode(entities.toList(growable: false)..sort());

  static Set<String> decodeEntities(String value) {
    final decoded = jsonDecode(value) as List;
    return decoded.whereType<String>().toSet();
  }
}

Map<String, Object?> factsOf(Object? raw) {
  if (raw is! Map) throw const FormatException('Event facts must be a map');
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

DomainScope _requiredDomain(String wire) {
  final domain = DomainScope.tryParse(wire);
  if (domain == null) throw FormatException('Unknown event domain: $wire');
  return domain;
}

DateTime _requiredDateTime(Object? raw, String field) {
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw)?.toUtc();
    if (parsed != null) return parsed;
  }
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
  }
  throw FormatException('Invalid or missing EventRecord.$field');
}
