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

const Duration kAgentRunLeaseTimeout = Duration(hours: 6);

class AgentRunAcquireResult {
  const AgentRunAcquireResult.acquired({required this.record})
    : activeRun = null;

  const AgentRunAcquireResult.busy({required this.activeRun}) : record = null;

  final AgentRunRecord? record;
  final AgentRunRecord? activeRun;

  bool get acquired => record != null;
}

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
    this.traceId,
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
  final String? traceId;

  bool get isNonFailed =>
      status == AgentRunLifecycleStatus.ready ||
      status == AgentRunLifecycleStatus.noFinding;
}

abstract interface class AgentRunStore {
  Future<AgentRunAcquireResult> acquireRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
    Duration leaseTimeout = kAgentRunLeaseTimeout,
  });

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

  Future<Map<String, AgentRunRecord>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
  });

  Future<List<AgentRunRecord>> listForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 20,
  });

  Future<DateTime?> lastNonFailedRunAt({
    required String ownerUserId,
    required String agentId,
  });
}

class InMemoryAgentRunStore implements AgentRunStore {
  final Map<String, AgentRunRecord> _runs = <String, AgentRunRecord>{};

  @override
  Future<AgentRunAcquireResult> acquireRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
    Duration leaseTimeout = kAgentRunLeaseTimeout,
  }) async {
    final staleBefore = startedAt.toUtc().subtract(leaseTimeout);
    final active = _latestRunningRun(
      ownerUserId: ownerUserId,
      agentId: agent.id,
    );
    if (active != null && active.startedAt.isAfter(staleBefore)) {
      return AgentRunAcquireResult.busy(activeRun: active);
    }
    if (active != null) {
      _abandonStaleRuns(
        ownerUserId: ownerUserId,
        agentId: agent.id,
        staleBefore: staleBefore,
        abandonedAt: startedAt,
      );
    }
    final record = _runningRecord(
      ownerUserId: ownerUserId,
      agent: agent,
      startedAt: startedAt,
      trigger: trigger,
    );
    _runs[record.id] = record;
    return AgentRunAcquireResult.acquired(record: record);
  }

  @override
  Future<void> markRunning({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
  }) async {
    final record = _runningRecord(
      ownerUserId: ownerUserId,
      agent: agent,
      startedAt: startedAt,
      trigger: trigger,
    );
    _runs[record.id] = record;
  }

  @override
  Future<void> finishRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime runStartedAt,
    required AgentRunResult result,
    required AgentRunTrigger trigger,
  }) async {
    if (result.status == AgentRunStatus.busy) {
      throw StateError('busy agent results are transient and cannot finish');
    }
    final id = agentRunId(agentId: agent.id, startedAt: runStartedAt);
    final existing = _runs[id];
    if (existing != null &&
        existing.status != AgentRunLifecycleStatus.running) {
      return;
    }
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
    final rows = await listForAgent(
      ownerUserId: ownerUserId,
      agentId: agentId,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<Map<String, AgentRunRecord>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
  }) async {
    final ids = agentIds.toSet();
    if (ids.isEmpty) return const <String, AgentRunRecord>{};
    final rows =
        _runs.values
            .where(
              (run) =>
                  run.ownerUserId == ownerUserId && ids.contains(run.agentId),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final byAgent = <String, AgentRunRecord>{};
    for (final row in rows) {
      byAgent.putIfAbsent(row.agentId, () => row);
    }
    return byAgent;
  }

  @override
  Future<List<AgentRunRecord>> listForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 20,
  }) async {
    final rows =
        _runs.values
            .where(
              (run) => run.ownerUserId == ownerUserId && run.agentId == agentId,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows.take(limit).toList(growable: false);
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
          ..sort((a, b) {
            final aCompletedAt = a.finishedAt ?? a.startedAt;
            final bCompletedAt = b.finishedAt ?? b.startedAt;
            return bCompletedAt.compareTo(aCompletedAt);
          });
    final latest = rows.isEmpty ? null : rows.first;
    return latest == null ? null : latest.finishedAt ?? latest.startedAt;
  }

  AgentRunRecord? _latestRunningRun({
    required String ownerUserId,
    required String agentId,
  }) {
    final rows =
        _runs.values
            .where(
              (run) =>
                  run.ownerUserId == ownerUserId &&
                  run.agentId == agentId &&
                  run.status == AgentRunLifecycleStatus.running,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows.isEmpty ? null : rows.first;
  }

  void _abandonStaleRuns({
    required String ownerUserId,
    required String agentId,
    required DateTime staleBefore,
    required DateTime abandonedAt,
  }) {
    for (final entry in _runs.entries.toList(growable: false)) {
      final run = entry.value;
      if (run.ownerUserId != ownerUserId ||
          run.agentId != agentId ||
          run.status != AgentRunLifecycleStatus.running ||
          run.startedAt.isAfter(staleBefore)) {
        continue;
      }
      _runs[entry.key] = AgentRunRecord(
        id: run.id,
        ownerUserId: run.ownerUserId,
        agentId: run.agentId,
        agentName: run.agentName,
        status: AgentRunLifecycleStatus.failed,
        trigger: run.trigger,
        startedAt: run.startedAt,
        finishedAt: abandonedAt.toUtc(),
        summary: 'abandoned stale running lease',
        error: 'Agent run abandoned after stale running lease expired.',
        memoryId: run.memoryId,
        artifactId: run.artifactId,
        traceId: run.traceId,
      );
    }
  }
}

class SqliteAgentRunStore implements AgentRunStore {
  SqliteAgentRunStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<AgentRunAcquireResult> acquireRun({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
    Duration leaseTimeout = kAgentRunLeaseTimeout,
  }) {
    return _db.transaction(() async {
      final startedAtUtc = startedAt.toUtc();
      final staleBefore = startedAtUtc.subtract(leaseTimeout);
      final active = await _latestRunningRun(
        ownerUserId: ownerUserId,
        agentId: agent.id,
      );
      if (active != null && active.startedAt.isAfter(staleBefore)) {
        return AgentRunAcquireResult.busy(activeRun: active);
      }
      if (active != null) {
        await _abandonStaleRuns(
          ownerUserId: ownerUserId,
          agentId: agent.id,
          staleBefore: staleBefore,
          abandonedAt: startedAtUtc,
        );
      }
      final record = _runningRecord(
        ownerUserId: ownerUserId,
        agent: agent,
        startedAt: startedAtUtc,
        trigger: trigger,
      );
      await _insertRunRecord(record);
      return AgentRunAcquireResult.acquired(record: record);
    });
  }

  @override
  Future<void> markRunning({
    required String ownerUserId,
    required Agent agent,
    required DateTime startedAt,
    required AgentRunTrigger trigger,
  }) async {
    await _insertRunRecord(
      _runningRecord(
        ownerUserId: ownerUserId,
        agent: agent,
        startedAt: startedAt,
        trigger: trigger,
      ),
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
    if (result.status == AgentRunStatus.busy) {
      throw StateError('busy agent results are transient and cannot finish');
    }
    final id = agentRunId(agentId: agent.id, startedAt: runStartedAt);
    final existing = await _runById(id);
    if (existing != null &&
        existing.status != AgentRunLifecycleStatus.running) {
      return;
    }
    final record = _recordFromResult(
      id: id,
      ownerUserId: ownerUserId,
      agent: agent,
      result: result,
      trigger: trigger,
    );
    await _insertRunRecord(record);
  }

  @override
  Future<AgentRunRecord?> latestForAgent({
    required String ownerUserId,
    required String agentId,
  }) async {
    final rows = await listForAgent(
      ownerUserId: ownerUserId,
      agentId: agentId,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<Map<String, AgentRunRecord>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
  }) async {
    final ids = agentIds.toSet().toList(growable: false)..sort();
    if (ids.isEmpty) return const <String, AgentRunRecord>{};
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_runs
          WHERE owner_user_id = ? AND agent_id IN ($placeholders)
          ORDER BY agent_id ASC, started_at DESC
          ''',
          variables: [
            Variable.withString(ownerUserId),
            for (final id in ids) Variable.withString(id),
          ],
        )
        .get();
    final byAgent = <String, AgentRunRecord>{};
    for (final row in rows) {
      final record = _rowToRecord(row);
      byAgent.putIfAbsent(record.agentId, () => record);
    }
    return byAgent;
  }

  @override
  Future<List<AgentRunRecord>> listForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 20,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_runs
          WHERE owner_user_id = ? AND agent_id = ?
          ORDER BY started_at DESC
          LIMIT ?
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
            Variable.withInt(limit),
          ],
        )
        .get();
    return [for (final item in row) _rowToRecord(item)];
  }

  @override
  Future<DateTime?> lastNonFailedRunAt({
    required String ownerUserId,
    required String agentId,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(finished_at, started_at) AS last_non_failed_at
          FROM agent_runs
          WHERE owner_user_id = ?
            AND agent_id = ?
            AND status IN ('ready', 'no_finding')
          ORDER BY last_non_failed_at DESC
          LIMIT 1
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
          ],
        )
        .getSingleOrNull();
    final millis = row?.read<int>('last_non_failed_at');
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  Future<AgentRunRecord?> _runById(String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM agent_runs WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _rowToRecord(row);
  }

  Future<AgentRunRecord?> _latestRunningRun({
    required String ownerUserId,
    required String agentId,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_runs
          WHERE owner_user_id = ?
            AND agent_id = ?
            AND status = 'running'
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

  Future<void> _abandonStaleRuns({
    required String ownerUserId,
    required String agentId,
    required DateTime staleBefore,
    required DateTime abandonedAt,
  }) {
    return _db.customStatement(
      '''
      UPDATE agent_runs
      SET status = ?,
          finished_at = ?,
          summary = ?,
          error = ?
      WHERE owner_user_id = ?
        AND agent_id = ?
        AND status = 'running'
        AND started_at <= ?
      ''',
      <Object?>[
        AgentRunLifecycleStatus.failed.wire,
        abandonedAt.toUtc().millisecondsSinceEpoch,
        'abandoned stale running lease',
        'Agent run abandoned after stale running lease expired.',
        ownerUserId,
        agentId,
        staleBefore.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> _insertRunRecord(AgentRunRecord record) {
    return _db.customStatement(
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
        artifact_id,
        trace_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        record.traceId,
      ],
    );
  }
}

String agentRunId({required String agentId, required DateTime startedAt}) {
  return '$agentId:${startedAt.toUtc().microsecondsSinceEpoch}';
}

AgentRunRecord _runningRecord({
  required String ownerUserId,
  required Agent agent,
  required DateTime startedAt,
  required AgentRunTrigger trigger,
}) {
  return AgentRunRecord(
    id: agentRunId(agentId: agent.id, startedAt: startedAt),
    ownerUserId: ownerUserId,
    agentId: agent.id,
    agentName: agent.name,
    status: AgentRunLifecycleStatus.running,
    trigger: trigger,
    startedAt: startedAt.toUtc(),
  );
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
    status: _lifecycleStatusFromResult(result.userVisibleStatus),
    trigger: trigger,
    startedAt: result.startedAt.toUtc(),
    finishedAt: result.finishedAt.toUtc(),
    summary: result.summary,
    error: result.error,
    memoryId: result.memoryId,
    artifactId: result.artifactId,
    traceId: result.traceId,
  );
}

AgentRunLifecycleStatus _lifecycleStatusFromResult(
  AgentRunUserVisibleStatus status,
) => switch (status) {
  AgentRunUserVisibleStatus.ready => AgentRunLifecycleStatus.ready,
  AgentRunUserVisibleStatus.noFinding => AgentRunLifecycleStatus.noFinding,
  AgentRunUserVisibleStatus.failed => AgentRunLifecycleStatus.failed,
};

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
    traceId: row.read<String?>('trace_id'),
  );
}
