/// Local-only persistence for [AgentArtifact] records.
library;

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'agent_artifact.dart';

abstract interface class AgentArtifactStore {
  Future<void> save(AgentArtifact artifact);

  Future<AgentArtifact?> read(String id);

  Future<void> dismiss({
    required String ownerUserId,
    required String id,
    required DateTime dismissedAt,
  });

  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  });

  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
    DateTime? visibleAt,
  });

  Future<Map<String, AgentArtifact>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
    DateTime? visibleAt,
  });

  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
    DateTime? visibleAt,
  });
}

class SqliteAgentArtifactStore implements AgentArtifactStore {
  SqliteAgentArtifactStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> save(AgentArtifact artifact) async {
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO agent_artifacts (
        id,
        owner_user_id,
        agent_id,
        domain,
        kind,
        severity,
        title,
        summary,
        presentation_json,
        insights_json,
        evidence_json,
        actions_json,
        memory_id,
        trace_id,
        created_at,
        expires_at,
        dismissed_at,
        snoozed_until
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
      ON CONFLICT(id) DO UPDATE SET
        owner_user_id = excluded.owner_user_id,
        agent_id = excluded.agent_id,
        domain = excluded.domain,
        kind = excluded.kind,
        severity = excluded.severity,
        title = excluded.title,
        summary = excluded.summary,
        presentation_json = excluded.presentation_json,
        insights_json = excluded.insights_json,
        evidence_json = excluded.evidence_json,
        actions_json = excluded.actions_json,
        memory_id = excluded.memory_id,
        trace_id = excluded.trace_id,
        created_at = excluded.created_at,
        expires_at = excluded.expires_at,
        dismissed_at = CASE
          WHEN agent_artifacts.owner_user_id = excluded.owner_user_id
          THEN agent_artifacts.dismissed_at
          ELSE NULL
        END,
        snoozed_until = CASE
          WHEN agent_artifacts.owner_user_id = excluded.owner_user_id
          THEN agent_artifacts.snoozed_until
          ELSE NULL
        END
      ''',
      <Object?>[
        artifact.id,
        artifact.ownerUserId,
        artifact.agentId,
        artifact.domain,
        artifact.kind.wire,
        artifact.severity.wire,
        artifact.title,
        artifact.summary,
        artifact.encodePresentation(),
        artifact.encodeInsights(),
        artifact.encodeEvidence(),
        artifact.encodeActions(),
        artifact.memoryId,
        artifact.traceId,
        artifact.createdAt.toUtc().millisecondsSinceEpoch,
        artifact.expiresAt?.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<AgentArtifact?> read(String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM agent_artifacts WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _rowToArtifact(row);
  }

  @override
  Future<void> dismiss({
    required String ownerUserId,
    required String id,
    required DateTime dismissedAt,
  }) async {
    await _db.customStatement(
      '''
      UPDATE agent_artifacts
      SET dismissed_at = ?, snoozed_until = NULL
      WHERE owner_user_id = ? AND id = ?
      ''',
      <Object?>[dismissedAt.toUtc().millisecondsSinceEpoch, ownerUserId, id],
    );
  }

  @override
  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  }) async {
    await _db.customStatement(
      '''
      UPDATE agent_artifacts
      SET snoozed_until = ?
      WHERE owner_user_id = ? AND id = ? AND dismissed_at IS NULL
      ''',
      <Object?>[until.toUtc().millisecondsSinceEpoch, ownerUserId, id],
    );
  }

  @override
  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
    DateTime? visibleAt,
  }) async {
    if (limit <= 0) return const <AgentArtifact>[];
    final atMillis = (visibleAt ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_artifacts
          WHERE owner_user_id = ? AND agent_id = ?
            AND dismissed_at IS NULL
            AND (snoozed_until IS NULL OR snoozed_until <= ?)
            AND (expires_at IS NULL OR expires_at > ?)
          ORDER BY created_at DESC
          LIMIT $limit
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
            Variable.withInt(atMillis),
            Variable.withInt(atMillis),
          ],
        )
        .get();
    return [for (final row in rows) _rowToArtifact(row)];
  }

  @override
  Future<Map<String, AgentArtifact>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
    DateTime? visibleAt,
  }) async {
    final ids = agentIds.toSet().toList(growable: false)..sort();
    if (ids.isEmpty) return const <String, AgentArtifact>{};
    final atMillis = (visibleAt ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_artifacts
          WHERE owner_user_id = ? AND agent_id IN ($placeholders)
            AND dismissed_at IS NULL
            AND (snoozed_until IS NULL OR snoozed_until <= ?)
            AND (expires_at IS NULL OR expires_at > ?)
          ORDER BY agent_id ASC, created_at DESC
          ''',
          variables: [
            Variable.withString(ownerUserId),
            for (final id in ids) Variable.withString(id),
            Variable.withInt(atMillis),
            Variable.withInt(atMillis),
          ],
        )
        .get();
    final byAgent = <String, AgentArtifact>{};
    for (final row in rows) {
      final artifact = _rowToArtifact(row);
      byAgent.putIfAbsent(artifact.agentId, () => artifact);
    }
    return byAgent;
  }

  @override
  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
    DateTime? visibleAt,
  }) async {
    if (limit <= 0) return const <AgentArtifact>[];
    final atMillis = (visibleAt ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_artifacts
          WHERE owner_user_id = ? AND domain = ?
            AND dismissed_at IS NULL
            AND (snoozed_until IS NULL OR snoozed_until <= ?)
            AND (expires_at IS NULL OR expires_at > ?)
          ORDER BY created_at DESC
          LIMIT $limit
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(domain),
            Variable.withInt(atMillis),
            Variable.withInt(atMillis),
          ],
        )
        .get();
    return [for (final row in rows) _rowToArtifact(row)];
  }
}

AgentArtifact _rowToArtifact(QueryRow row) {
  final presentation = decodeAgentPresentation(
    row.read<String>('presentation_json'),
  );
  final expiresAtMillis = row.read<int?>('expires_at');
  final dismissedAtMillis = row.read<int?>('dismissed_at');
  final snoozedUntilMillis = row.read<int?>('snoozed_until');
  return AgentArtifact(
    id: row.read<String>('id'),
    ownerUserId: row.read<String>('owner_user_id'),
    agentId: row.read<String>('agent_id'),
    domain: row.read<String>('domain'),
    kind: agentArtifactKindFromWire(row.read<String>('kind')),
    severity: agentArtifactSeverityFromWire(row.read<String>('severity')),
    title: row.read<String>('title'),
    summary: row.read<String>('summary'),
    metrics: presentation.metrics,
    insights: decodeAgentInsights(row.read<String>('insights_json')),
    evidence: decodeAgentEvidenceRefs(row.read<String>('evidence_json')),
    actions: decodeAgentActions(row.read<String>('actions_json')),
    methodology: presentation.methodology,
    memoryId: row.read<String?>('memory_id'),
    traceId: row.read<String?>('trace_id'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    expiresAt: expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis, isUtc: true),
    dismissedAt: dismissedAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dismissedAtMillis, isUtc: true),
    snoozedUntil: snoozedUntilMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(snoozedUntilMillis, isUtc: true),
  );
}
