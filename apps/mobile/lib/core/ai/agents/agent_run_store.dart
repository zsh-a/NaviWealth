/// Persistent lifecycle state for scheduled LifeOS agents.
///
/// This belongs to the agent framework, not the native agent runtime: runtime
/// code executes profile turns / effect plans, while this store records
/// product-level state such as last run, failures, and schedule gates.
library;

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'agent.dart';

enum AgentRunTrigger { manual, schedule, backgroundDue, catchUp }

extension AgentRunTriggerWire on AgentRunTrigger {
  String get wire => switch (this) {
    AgentRunTrigger.manual => 'manual',
    AgentRunTrigger.schedule => 'schedule',
    AgentRunTrigger.backgroundDue => 'background_due',
    AgentRunTrigger.catchUp => 'catch_up',
  };
}

enum AgentRunLifecycleStatus { running, ready, noFinding, failed }

extension AgentRunLifecycleStatusWire on AgentRunLifecycleStatus {
  String get wire => switch (this) {
    AgentRunLifecycleStatus.running => 'running',
    AgentRunLifecycleStatus.ready => 'ready',
    AgentRunLifecycleStatus.noFinding => 'no_finding',
    AgentRunLifecycleStatus.failed => 'failed',
  };
}

AgentRunTrigger agentRunTriggerFromWire(String value) => switch (value) {
  'manual' => AgentRunTrigger.manual,
  'schedule' => AgentRunTrigger.schedule,
  'background_due' => AgentRunTrigger.backgroundDue,
  'catch_up' => AgentRunTrigger.catchUp,
  _ => AgentRunTrigger.manual,
};

AgentRunLifecycleStatus agentRunLifecycleStatusFromWire(String value) =>
    switch (value) {
      'running' => AgentRunLifecycleStatus.running,
      'ready' => AgentRunLifecycleStatus.ready,
      'no_finding' => AgentRunLifecycleStatus.noFinding,
      'failed' => AgentRunLifecycleStatus.failed,
      _ => AgentRunLifecycleStatus.failed,
    };

class AgentRunRecord {
  const AgentRunRecord({
    required this.id,
    required this.ownerUserId,
    required this.agentId,
    required this.agentName,
    required this.status,
    required this.trigger,
    required this.startedAt,
    this.finishedAt,
    this.summary,
    this.error,
    this.memoryId,
    this.artifactId,
  });

  final String id;
  final String ownerUserId;
  final String agentId;
  final String agentName;
  final AgentRunLifecycleStatus status;
  final AgentRunTrigger trigger;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? summary;
  final String? error;
  final String? memoryId;
  final String? artifactId;

  bool get isNonFailed =>
      status == AgentRunLifecycleStatus.ready ||
      status == AgentRunLifecycleStatus.noFinding;
}

abstract interface class AgentRunStore {
  Future<void> markRunning({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
  });

  Future<void> finishRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime runStartedAt,
    required AgentRunResult result,
    required AgentRunTrigger trigger,
  });

  Future<AgentRunRecord?> latestForAgent({
    required String ownerUserId,
    required String agentId,
  });

  Future<DateTime?> lastNonFailedRunAt({
    required String ownerUserId,
    required String agentId,
  });
}

class InMemoryAgentRunStore implements AgentRunStore {
  final Map<String, AgentRunRecord> _runs = <String, AgentRunRecord>{};

  @override
  Future<void> markRunning({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
  }) async {
    final id = agentRunId(agentId: agent.id, startedAt: startedAt);
    _runs[id] = AgentRunRecord(
      id: id,
      ownerUserId: ownerUserId,
      agentId: agent.id,
      agentName: agent.name,
      status: AgentRunLifecycleStatus.running,
      trigger: trigger,
      startedAt: startedAt.toUtc(),
    );
  }

  @override
  Future<void> finishRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime runStartedAt,
    required AgentRunResult result,
    required AgentRunTrigger trigger,
  }) async {
    final id = agentRunId(agentId: agent.id, startedAt: runStartedAt);
    _runs[id] = _recordFromResult(
      id: id,
      ownerUserId: ownerUserId,
      agent: agent,
      result: result,
      trigger: trigger,
    );
  }

  @override
  Future<AgentRunRecord?> latestForAgent({
    required String ownerUserId,
    required String agentId,
  }) async {
    final rows =
        _runs.values
            .where(
              (run) => run.ownerUserId == ownerUserId && run.agentId == agentId,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<DateTime?> lastNonFailedRunAt({
    required String ownerUserId,
    required String agentId,
  }) async {
    final rows =
        _runs.values
            .where(
              (run) =>
                  run.ownerUserId == ownerUserId &&
                  run.agentId == agentId &&
                  run.isNonFailed,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows.isEmpty ? null : rows.first.startedAt;
  }
}

class SqliteAgentRunStore implements AgentRunStore {
  SqliteAgentRunStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> markRunning({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
  }) async {
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO agent_runs (
        id,
        owner_user_id,
        agent_id,
        agent_name,
        status,
        trigger,
        started_at,
        finished_at,
        summary,
        error,
        memory_id,
        artifact_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        agentRunId(agentId: agent.id, startedAt: startedAt),
        ownerUserId,
        agent.id,
        agent.name,
        AgentRunLifecycleStatus.running.wire,
        trigger.wire,
        startedAt.toUtc().millisecondsSinceEpoch,
        null,
        null,
        null,
        null,
        null,
      ],
    );
  }

  @override
  Future<void> finishRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime runStartedAt,
    required AgentRunResult result,
    required AgentRunTrigger trigger,
  }) async {
    final record = _recordFromResult(
      id: agentRunId(agentId: agent.id, startedAt: runStartedAt),
      ownerUserId: ownerUserId,
      agent: agent,
      result: result,
      trigger: trigger,
    );
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO agent_runs (
        id,
        owner_user_id,
        agent_id,
        agent_name,
        status,
        trigger,
        started_at,
        finished_at,
        summary,
        error,
        memory_id,
        artifact_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        record.id,
        record.ownerUserId,
        record.agentId,
        record.agentName,
        record.status.wire,
        record.trigger.wire,
        record.startedAt.toUtc().millisecondsSinceEpoch,
        record.finishedAt?.toUtc().millisecondsSinceEpoch,
        record.summary,
        record.error,
        record.memoryId,
        record.artifactId,
      ],
    );
  }

  @override
  Future<AgentRunRecord?> latestForAgent({
    required String ownerUserId,
    required String agentId,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_runs
          WHERE owner_user_id = ? AND agent_id = ?
          ORDER BY started_at DESC
          LIMIT 1
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _rowToRecord(row);
  }

  @override
  Future<DateTime?> lastNonFailedRunAt({
    required String ownerUserId,
    required String agentId,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT started_at
          FROM agent_runs
          WHERE owner_user_id = ?
            AND agent_id = ?
            AND status IN ('ready', 'no_finding')
          ORDER BY started_at DESC
          LIMIT 1
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
          ],
        )
        .getSingleOrNull();
    final millis = row?.read<int>('started_at');
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
}

String agentRunId({required String agentId, required DateTime startedAt}) {
  return '$agentId:${startedAt.toUtc().microsecondsSinceEpoch}';
}

AgentRunRecord _recordFromResult({
  required String id,
  required String ownerUserId,
  required Agent agent,
  required AgentRunResult result,
  required AgentRunTrigger trigger,
}) {
  return AgentRunRecord(
    id: id,
    ownerUserId: ownerUserId,
    agentId: agent.id,
    agentName: agent.name,
    status: switch (result.status) {
      AgentRunStatus.completed => AgentRunLifecycleStatus.ready,
      AgentRunStatus.skipped => AgentRunLifecycleStatus.noFinding,
      AgentRunStatus.failed => AgentRunLifecycleStatus.failed,
    },
    trigger: trigger,
    startedAt: result.startedAt.toUtc(),
    finishedAt: result.finishedAt.toUtc(),
    summary: result.summary,
    error: result.error,
    memoryId: result.memoryId,
    artifactId: result.artifactId,
  );
}

AgentRunRecord _rowToRecord(QueryRow row) {
  final finishedAtMillis = row.read<int?>('finished_at');
  return AgentRunRecord(
    id: row.read<String>('id'),
    ownerUserId: row.read<String>('owner_user_id'),
    agentId: row.read<String>('agent_id'),
    agentName: row.read<String>('agent_name'),
    status: agentRunLifecycleStatusFromWire(row.read<String>('status')),
    trigger: agentRunTriggerFromWire(row.read<String>('trigger')),
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('started_at'),
      isUtc: true,
    ),
    finishedAt: finishedAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(finishedAtMillis, isUtc: true),
    summary: row.read<String?>('summary'),
    error: row.read<String?>('error'),
    memoryId: row.read<String?>('memory_id'),
    artifactId: row.read<String?>('artifact_id'),
  );
}
