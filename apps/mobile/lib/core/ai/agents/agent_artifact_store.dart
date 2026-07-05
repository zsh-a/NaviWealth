/// Local-only persistence for [AgentArtifact] records.
library;

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'agent_artifact.dart';

abstract interface class AgentArtifactStore {
  Future<void> save(AgentArtifact artifact);

  Future<AgentArtifact?> read(String id);

  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
  });

  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
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
        insights_json,
        evidence_json,
        actions_json,
        memory_id,
        trace_id,
        created_at,
        expires_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
  }) async {
    if (limit <= 0) return const <AgentArtifact>[];
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_artifacts
          WHERE owner_user_id = ? AND agent_id = ?
          ORDER BY created_at DESC
          LIMIT $limit
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
          ],
        )
        .get();
    return [for (final row in rows) _rowToArtifact(row)];
  }

  @override
  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
  }) async {
    if (limit <= 0) return const <AgentArtifact>[];
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_artifacts
          WHERE owner_user_id = ? AND domain = ?
          ORDER BY created_at DESC
          LIMIT $limit
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(domain),
          ],
        )
        .get();
    return [for (final row in rows) _rowToArtifact(row)];
  }
}

AgentArtifact _rowToArtifact(QueryRow row) {
  final expiresAtMillis = row.read<int?>('expires_at');
  return AgentArtifact(
    id: row.read<String>('id'),
    ownerUserId: row.read<String>('owner_user_id'),
    agentId: row.read<String>('agent_id'),
    domain: row.read<String>('domain'),
    kind: agentArtifactKindFromWire(row.read<String>('kind')),
    severity: agentArtifactSeverityFromWire(row.read<String>('severity')),
    title: row.read<String>('title'),
    summary: row.read<String>('summary'),
    insights: decodeAgentInsights(row.read<String>('insights_json')),
    evidence: decodeAgentEvidenceRefs(row.read<String>('evidence_json')),
    actions: decodeAgentActions(row.read<String>('actions_json')),
    memoryId: row.read<String?>('memory_id'),
    traceId: row.read<String?>('trace_id'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    expiresAt: expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis, isUtc: true),
  );
}
