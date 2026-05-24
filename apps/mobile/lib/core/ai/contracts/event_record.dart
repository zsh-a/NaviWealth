/// Cross-domain event log entry (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// Events are durable, append-only(ish) records of "something
/// happened": a trade opened, a sleep night ended, a file was saved.
/// They're written by domain indexers (e.g. trade journal extractor),
/// queried by [ContextBuilder] under the "recent_events" slot, and
/// optionally promoted to a [MemoryRecord] (kind=`event`) when the
/// event itself has long-term significance.
///
/// Events vs memories:
///
/// - **Event** — happened at a specific instant; cheap to write; many.
/// - **Memory** — synthesised across one-or-more events; carries
///   confidence + importance + lifecycle.
///
/// Most events do NOT become memories. The Extractor decides.
library;

import 'dart:convert';

class EventRecord {
  const EventRecord({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.source,
    required this.ownerUserId,
    required this.summary,
    required this.payload,
    required this.entities,
    this.title,
    this.importance = 0.5,
  });

  /// Opaque stable id; convention `<source>:<type>:<sourceId>`.
  final String id;

  /// Free-form event type (`'trade_opened'`, `'sleep_session_ended'`).
  /// Not enum'd — new domains add their own types.
  final String type;

  final DateTime timestamp;

  /// Source system label (`'options_trade_journal'`,
  /// `'health:sleep'`). Free string.
  final String source;

  final String ownerUserId;

  /// Optional short label. UI/LLM can render this directly.
  final String? title;

  /// Required one-line synopsis — what happened. The Extractor uses
  /// this when promoting to a [MemoryRecord].
  final String summary;

  /// Type-specific structured fields, JSON-encoded for storage.
  final Map<String, Object?> payload;

  /// Entity tags. Same convention as [MemoryRecord.entities].
  final Set<String> entities;

  /// `0..1`. Drives "is this worth surfacing in recent_events"
  /// reranking.
  final double importance;

  EventRecord copyWith({
    String? type,
    DateTime? timestamp,
    String? source,
    String? title,
    String? summary,
    Map<String, Object?>? payload,
    Set<String>? entities,
    double? importance,
  }) => EventRecord(
    id: id,
    ownerUserId: ownerUserId,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    source: source ?? this.source,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    payload: payload ?? this.payload,
    entities: entities ?? this.entities,
    importance: importance ?? this.importance,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'source': source,
    'owner_user_id': ownerUserId,
    if (title != null) 'title': title,
    'summary': summary,
    'payload': payload,
    'entities': entities.toList(growable: false),
    'importance': importance,
  };

  factory EventRecord.fromJson(Map<String, Object?> json) {
    final entitiesRaw = json['entities'];
    final ts = json['timestamp'];
    return EventRecord(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      timestamp: ts is String
          ? DateTime.parse(ts).toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: (json['source'] as String?) ?? '',
      ownerUserId: (json['owner_user_id'] as String?) ?? '',
      title: json['title'] as String?,
      summary: (json['summary'] as String?) ?? '',
      payload: _mapOf(json['payload']),
      entities: entitiesRaw is List
          ? entitiesRaw.whereType<String>().toSet()
          : <String>{},
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
    );
  }

  String encodePayload() => jsonEncode(payload);
  static Map<String, Object?> decodePayload(String s) {
    if (s.isEmpty) return const <String, Object?>{};
    final v = jsonDecode(s);
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return const <String, Object?>{};
  }

  String encodeEntities() => jsonEncode(entities.toList(growable: false));
  static Set<String> decodeEntities(String s) {
    if (s.isEmpty) return <String>{};
    final v = jsonDecode(s);
    if (v is List) return v.whereType<String>().toSet();
    return <String>{};
  }
}

Map<String, Object?> _mapOf(Object? raw) {
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return const <String, Object?>{};
}
