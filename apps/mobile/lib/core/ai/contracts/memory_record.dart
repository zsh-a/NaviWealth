/// Typed memory record — the canonical row of the Memory Runtime
/// (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Four kinds:
///
/// - **event** — something happened (trade opened, sleep recorded, file
///   saved). Usually mirrored from the [events] table; kept in
///   memories when the event itself is durable signal (e.g. "made
///   first $1k of options income").
/// - **semantic** — a long-term fact about the user (preferences,
///   goals, constraints, principles). Stable across months.
/// - **episodic** — a specific decision with reasoning + outcome. The
///   "why did I do X last time" memory.
/// - **procedural** — an actionable rule the user (or AI on their
///   behalf) should apply ("close put when premium captured >= 70%").
///
/// All four share the same envelope (this class); the kind-specific
/// fields live in [payload]. Contract layer is **domain-neutral**:
/// `source` / `scope` / `entities` are free-form strings,
/// `MemoryKind` is the only closed set.
library;

import 'dart:convert';

enum MemoryKind { event, semantic, episodic, procedural }

extension MemoryKindWire on MemoryKind {
  String get wire => switch (this) {
    MemoryKind.event => 'event',
    MemoryKind.semantic => 'semantic',
    MemoryKind.episodic => 'episodic',
    MemoryKind.procedural => 'procedural',
  };

  static MemoryKind parse(String s) => switch (s) {
    'event' => MemoryKind.event,
    'semantic' => MemoryKind.semantic,
    'episodic' => MemoryKind.episodic,
    'procedural' => MemoryKind.procedural,
    _ => MemoryKind.event,
  };
}

/// One typed memory row. Created by an Extractor (per-feature indexer
/// like `trade_journal_memory_indexer.dart`), stored by [MemoryStore],
/// scored by [HybridScorer], assembled into a [ContextPack] by
/// [ContextBuilder].
class MemoryRecord {
  const MemoryRecord({
    required this.id,
    required this.kind,
    required this.ownerUserId,
    required this.title,
    required this.summary,
    required this.payload,
    required this.entities,
    required this.importance,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
    this.scope = '*',
    this.source,
    this.sourceId,
    this.sourceEventId,
    this.validFrom,
    this.validUntil,
    this.lastAccessedAt,
  });

  /// Opaque stable id. Convention: `<source>:<kind>:<sourceId>` so
  /// re-extraction is naturally idempotent. Treat as opaque outside the
  /// extractor that minted it.
  final String id;

  final MemoryKind kind;

  /// Owner scope for multi-user data isolation. Mirrors every other
  /// owner_user_id column.
  final String ownerUserId;

  /// Short label shown to the LLM ("NVDA put closed for 70% credit").
  final String title;

  /// One-paragraph synopsis. **This is what the embedder sees** — keep
  /// it dense and self-contained so cosine similarity has signal.
  final String summary;

  /// Kind-specific structured payload. Free-form map so HealthOS /
  /// TimeOS don't need new contract types when they add memory.
  ///
  /// Suggested per-kind shapes (not enforced):
  ///
  /// - `event`: `{type, ...domain-specific}`
  /// - `semantic`: `{statement, scope}` (e.g. "user prefers local-first")
  /// - `episodic`: `{context, decision, reasoning, outcome}`
  /// - `procedural`: `{rule, scope, conditions, action}`
  final Map<String, Object?> payload;

  /// Domain tag, e.g. `'options_trading'`, `'sleep'`, `'*'` for
  /// global. ContextBuilder filters applicable rules / preferences by
  /// scope.
  final String scope;

  /// Origin source label (`'options_trade_journal'`,
  /// `'health:sleep_session'`, etc.). Free string.
  final String? source;

  /// Back-pointer to the origin entity in its own table. Together
  /// with [source] gives a deep-link target for the UI.
  final String? sourceId;

  /// Back-pointer to a row in `events` when this memory was derived
  /// from a specific event. `null` for memories with no event proper
  /// (e.g. a manually-set preference).
  final String? sourceEventId;

  /// Free-form entity tags (`'NVDA'`, `'put'`, `'short-put'`).
  /// Hybrid scoring boosts memories whose entities overlap with the
  /// intent's entities.
  final Set<String> entities;

  /// `0..1`. How much this should influence future decisions. A
  /// trivial open trade event: 0.3. A closed losing trade with notes:
  /// 0.8. A long-term preference: 0.9.
  final double importance;

  /// `0..1`. How sure we are this fact is correct. Auto-extracted: 0.7.
  /// User-confirmed: 0.95. Stale-but-not-superseded: 0.5.
  final double confidence;

  /// First moment this memory was true. `null` = "always".
  final DateTime? validFrom;

  /// First moment this memory stops being true. `null` = "open-ended".
  /// ContextBuilder filters out expired memories.
  final DateTime? validUntil;

  /// Last time the memory was returned from a retrieval. Drives
  /// recency-aware reranking + LRU forgetting.
  final DateTime? lastAccessedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  MemoryRecord copyWith({
    MemoryKind? kind,
    String? scope,
    String? source,
    String? sourceId,
    String? sourceEventId,
    String? title,
    String? summary,
    Map<String, Object?>? payload,
    Set<String>? entities,
    double? importance,
    double? confidence,
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime? lastAccessedAt,
    DateTime? updatedAt,
  }) => MemoryRecord(
    id: id,
    ownerUserId: ownerUserId,
    kind: kind ?? this.kind,
    scope: scope ?? this.scope,
    source: source ?? this.source,
    sourceId: sourceId ?? this.sourceId,
    sourceEventId: sourceEventId ?? this.sourceEventId,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    payload: payload ?? this.payload,
    entities: entities ?? this.entities,
    importance: importance ?? this.importance,
    confidence: confidence ?? this.confidence,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.wire,
    'owner_user_id': ownerUserId,
    'scope': scope,
    if (source != null) 'source': source,
    if (sourceId != null) 'source_id': sourceId,
    if (sourceEventId != null) 'source_event_id': sourceEventId,
    'title': title,
    'summary': summary,
    'payload': payload,
    'entities': entities.toList(growable: false),
    'importance': importance,
    'confidence': confidence,
    if (validFrom != null) 'valid_from': validFrom!.toUtc().toIso8601String(),
    if (validUntil != null)
      'valid_until': validUntil!.toUtc().toIso8601String(),
    if (lastAccessedAt != null)
      'last_accessed_at': lastAccessedAt!.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory MemoryRecord.fromJson(Map<String, Object?> json) {
    final entitiesRaw = json['entities'];
    return MemoryRecord(
      id: (json['id'] as String?) ?? '',
      kind: MemoryKindWire.parse(json['kind'] as String? ?? 'event'),
      ownerUserId: (json['owner_user_id'] as String?) ?? '',
      scope: (json['scope'] as String?) ?? '*',
      source: json['source'] as String?,
      sourceId: json['source_id'] as String?,
      sourceEventId: json['source_event_id'] as String?,
      title: (json['title'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      payload: _payloadOf(json['payload']),
      entities: entitiesRaw is List
          ? entitiesRaw.whereType<String>().toSet()
          : <String>{},
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      validFrom: _dt(json['valid_from']),
      validUntil: _dt(json['valid_until']),
      lastAccessedAt: _dt(json['last_accessed_at']),
      createdAt:
          _dt(json['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          _dt(json['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Encode the payload to a JSON string suitable for the Drift TEXT
  /// column.
  String encodePayload() => jsonEncode(payload);

  static Map<String, Object?> decodePayload(String s) {
    if (s.isEmpty) return const <String, Object?>{};
    final v = jsonDecode(s);
    if (v is Map) {
      return v.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, Object?>{};
  }

  /// Encode entities to a JSON array for the Drift TEXT column.
  String encodeEntities() => jsonEncode(entities.toList(growable: false));

  static Set<String> decodeEntities(String s) {
    if (s.isEmpty) return <String>{};
    final v = jsonDecode(s);
    if (v is List) return v.whereType<String>().toSet();
    return <String>{};
  }
}

Map<String, Object?> _payloadOf(Object? raw) {
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, Object?>{};
}

DateTime? _dt(Object? raw) {
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toUtc();
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
  }
  return null;
}
