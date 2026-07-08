/// User-visible outputs produced by LifeOS agents.
///
/// Artifacts are product-level results (briefings, reviews, alerts), not chat
/// messages and not native runtime state. Domain agents can persist one after
/// a run; domain surfaces render them consistently.
library;

import 'dart:convert';

enum AgentArtifactKind { briefing, review, alert, reminder }

extension AgentArtifactKindWire on AgentArtifactKind {
  String get wire => switch (this) {
    AgentArtifactKind.briefing => 'briefing',
    AgentArtifactKind.review => 'review',
    AgentArtifactKind.alert => 'alert',
    AgentArtifactKind.reminder => 'reminder',
  };
}

AgentArtifactKind agentArtifactKindFromWire(String value) => switch (value) {
  'briefing' => AgentArtifactKind.briefing,
  'review' => AgentArtifactKind.review,
  'alert' => AgentArtifactKind.alert,
  'reminder' => AgentArtifactKind.reminder,
  _ => AgentArtifactKind.review,
};

enum AgentArtifactSeverity { info, attention, warning }

extension AgentArtifactSeverityWire on AgentArtifactSeverity {
  String get wire => switch (this) {
    AgentArtifactSeverity.info => 'info',
    AgentArtifactSeverity.attention => 'attention',
    AgentArtifactSeverity.warning => 'warning',
  };
}

AgentArtifactSeverity agentArtifactSeverityFromWire(String value) =>
    switch (value) {
      'info' => AgentArtifactSeverity.info,
      'attention' => AgentArtifactSeverity.attention,
      'warning' => AgentArtifactSeverity.warning,
      _ => AgentArtifactSeverity.info,
    };

class AgentArtifact {
  const AgentArtifact({
    required this.id,
    required this.ownerUserId,
    required this.agentId,
    required this.domain,
    required this.kind,
    required this.severity,
    required this.title,
    required this.summary,
    this.insights = const <AgentInsight>[],
    this.evidence = const <AgentEvidenceRef>[],
    this.actions = const <AgentAction>[],
    this.memoryId,
    this.traceId,
    required this.createdAt,
    this.expiresAt,
    this.dismissedAt,
    this.snoozedUntil,
  });

  final String id;
  final String ownerUserId;
  final String agentId;
  final String domain;
  final AgentArtifactKind kind;
  final AgentArtifactSeverity severity;
  final String title;
  final String summary;
  final List<AgentInsight> insights;
  final List<AgentEvidenceRef> evidence;
  final List<AgentAction> actions;
  final String? memoryId;
  final String? traceId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? dismissedAt;
  final DateTime? snoozedUntil;

  bool isVisibleAt(DateTime now) {
    final at = now.toUtc();
    return dismissedAt == null &&
        (snoozedUntil == null || !snoozedUntil!.toUtc().isAfter(at)) &&
        (expiresAt == null || expiresAt!.toUtc().isAfter(at));
  }

  String encodeInsights() =>
      jsonEncode([for (final insight in insights) insight.toJson()]);

  String encodeEvidence() =>
      jsonEncode([for (final ref in evidence) ref.toJson()]);

  String encodeActions() =>
      jsonEncode([for (final action in actions) action.toJson()]);
}

class AgentInsight {
  const AgentInsight({
    required this.title,
    required this.body,
    this.severity,
    this.payload = const <String, Object?>{},
  });

  final String title;
  final String body;
  final AgentArtifactSeverity? severity;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'body': body,
    if (severity != null) 'severity': severity!.wire,
    if (payload.isNotEmpty) 'payload': payload,
  };

  factory AgentInsight.fromJson(Map<String, Object?> json) {
    return AgentInsight(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      severity: switch (json['severity']) {
        final String value => agentArtifactSeverityFromWire(value),
        _ => null,
      },
      payload:
          (json['payload'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }
}

class AgentEvidenceRef {
  const AgentEvidenceRef({
    required this.type,
    required this.id,
    this.label,
    this.route,
    this.payload = const <String, Object?>{},
  });

  final String type;
  final String id;
  final String? label;
  final String? route;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    if (label != null) 'label': label,
    if (route != null) 'route': route,
    if (payload.isNotEmpty) 'payload': payload,
  };

  factory AgentEvidenceRef.fromJson(Map<String, Object?> json) {
    return AgentEvidenceRef(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      label: json['label'] as String?,
      route: json['route'] as String?,
      payload:
          (json['payload'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }
}

class AgentAction {
  const AgentAction({
    required this.kind,
    required this.label,
    this.description,
    this.intent,
    this.objectType,
    this.objectId,
    this.capabilities = const <String>[],
    this.payload = const <String, Object?>{},
  });

  final String kind;
  final String label;
  final String? description;
  final String? intent;
  final String? objectType;
  final String? objectId;
  final List<String> capabilities;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'label': label,
    if (description != null) 'description': description,
    if (intent != null) 'intent': intent,
    if (objectType != null) 'object_type': objectType,
    if (objectId != null) 'object_id': objectId,
    if (capabilities.isNotEmpty) 'capabilities': capabilities,
    if (payload.isNotEmpty) 'payload': payload,
  };

  factory AgentAction.fromJson(Map<String, Object?> json) {
    return AgentAction(
      kind: json['kind'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      intent: json['intent'] as String?,
      objectType: json['object_type'] as String?,
      objectId: json['object_id'] as String?,
      capabilities:
          (json['capabilities'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      payload:
          (json['payload'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }
}

List<AgentInsight> decodeAgentInsights(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) return const <AgentInsight>[];
  return [
    for (final item in decoded)
      if (item is Map) AgentInsight.fromJson(item.cast<String, Object?>()),
  ];
}

List<AgentEvidenceRef> decodeAgentEvidenceRefs(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) return const <AgentEvidenceRef>[];
  return [
    for (final item in decoded)
      if (item is Map) AgentEvidenceRef.fromJson(item.cast<String, Object?>()),
  ];
}

List<AgentAction> decodeAgentActions(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) return const <AgentAction>[];
  return [
    for (final item in decoded)
      if (item is Map) AgentAction.fromJson(item.cast<String, Object?>()),
  ];
}
