/// Structured outcome feedback for user-visible Agent Artifacts.
///
/// Feedback is local policy evidence, not long-term personal memory. It links
/// a user response to the exact context/finding/attention fingerprints that
/// caused the result to appear.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../persistence/app_database.dart';
import 'agent_artifact.dart';

enum AgentFeedbackKind { accepted, dismissed, snoozed, completed, undone }

class AgentFeedback {
  const AgentFeedback({
    required this.id,
    required this.ownerUserId,
    required this.artifactId,
    required this.agentId,
    required this.domain,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.actionKind,
    this.lifeContextFingerprint,
    this.findingFingerprint,
    this.attentionDecisionId,
  });

  final String id;
  final String ownerUserId;
  final String artifactId;
  final String agentId;
  final String domain;
  final AgentFeedbackKind kind;
  final String? actionKind;
  final String? lifeContextFingerprint;
  final String? findingFingerprint;
  final String? attentionDecisionId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

abstract interface class AgentFeedbackStore {
  Future<AgentFeedback> record({
    required AgentArtifact artifact,
    required AgentFeedbackKind kind,
    AgentAction? action,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? at,
  });

  Future<List<AgentFeedback>> listForArtifact({
    required String ownerUserId,
    required String artifactId,
  });
}

class SqliteAgentFeedbackStore implements AgentFeedbackStore {
  SqliteAgentFeedbackStore({required AppDatabase db, Uuid uuid = const Uuid()})
    : _db = db,
      _uuid = uuid;

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Future<AgentFeedback> record({
    required AgentArtifact artifact,
    required AgentFeedbackKind kind,
    AgentAction? action,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? at,
  }) async {
    final createdAt = (at ?? DateTime.now()).toUtc();
    final actionPayload = action?.payload ?? const <String, Object?>{};
    final feedback = AgentFeedback(
      id: _uuid.v4(),
      ownerUserId: artifact.ownerUserId,
      artifactId: artifact.id,
      agentId: artifact.agentId,
      domain: artifact.domain,
      kind: kind,
      actionKind: action?.kind,
      lifeContextFingerprint:
          actionPayload['life_context_fingerprint'] as String?,
      findingFingerprint: actionPayload['finding_fingerprint'] as String?,
      attentionDecisionId: actionPayload['attention_decision_id'] as String?,
      payload: <String, Object?>{
        ...payload,
        if (action != null) 'action_label': action.label,
        if (artifact.traceId != null) 'trace_id': artifact.traceId,
      },
      createdAt: createdAt,
    );
    await _db.customStatement(
      '''
      INSERT INTO agent_feedback (
        id, owner_user_id, artifact_id, agent_id, domain, kind, action_kind,
        life_context_fingerprint, finding_fingerprint, attention_decision_id,
        payload_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        feedback.id,
        feedback.ownerUserId,
        feedback.artifactId,
        feedback.agentId,
        feedback.domain,
        feedback.kind.name,
        feedback.actionKind,
        feedback.lifeContextFingerprint,
        feedback.findingFingerprint,
        feedback.attentionDecisionId,
        jsonEncode(feedback.payload),
        feedback.createdAt.millisecondsSinceEpoch,
      ],
    );
    return feedback;
  }

  @override
  Future<List<AgentFeedback>> listForArtifact({
    required String ownerUserId,
    required String artifactId,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT * FROM agent_feedback
      WHERE owner_user_id = ? AND artifact_id = ?
      ORDER BY created_at ASC, id ASC
      ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withString(artifactId),
          ],
        )
        .get();
    return <AgentFeedback>[for (final row in rows) _feedbackFromRow(row)];
  }
}

AgentFeedback _feedbackFromRow(QueryRow row) {
  final decoded = jsonDecode(row.read<String>('payload_json'));
  return AgentFeedback(
    id: row.read<String>('id'),
    ownerUserId: row.read<String>('owner_user_id'),
    artifactId: row.read<String>('artifact_id'),
    agentId: row.read<String>('agent_id'),
    domain: row.read<String>('domain'),
    kind: AgentFeedbackKind.values.byName(row.read<String>('kind')),
    actionKind: row.read<String?>('action_kind'),
    lifeContextFingerprint: row.read<String?>('life_context_fingerprint'),
    findingFingerprint: row.read<String?>('finding_fingerprint'),
    attentionDecisionId: row.read<String?>('attention_decision_id'),
    payload: decoded is Map
        ? decoded.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{},
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
  );
}
