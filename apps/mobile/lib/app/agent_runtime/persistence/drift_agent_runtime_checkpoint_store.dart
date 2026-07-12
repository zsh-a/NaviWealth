/// Drift persistence adapter for agent runtime checkpoints.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

typedef AgentRuntimeDatabaseReader = Future<AppDatabase> Function();
typedef AgentRuntimeOwnerUserIdReader = Future<String> Function();
typedef AgentRuntimeCheckpointClock = DateTime Function();

final class DriftAgentRuntimeCheckpointStore
    implements AgentRuntimeCheckpointStore {
  DriftAgentRuntimeCheckpointStore({
    required AgentRuntimeDatabaseReader databaseReader,
    required AgentRuntimeOwnerUserIdReader ownerUserIdReader,
    AgentRuntimeCheckpointClock? clock,
    this.retention = const Duration(days: 1),
  }) : _databaseReader = databaseReader,
       _ownerUserIdReader = ownerUserIdReader,
       _clock = clock ?? _utcNow;

  final AgentRuntimeDatabaseReader _databaseReader;
  final AgentRuntimeOwnerUserIdReader _ownerUserIdReader;
  final AgentRuntimeCheckpointClock _clock;
  final Duration retention;

  @override
  Future<AgentRuntimeCheckpoint?> findResumable({
    required String agentId,
    required String requestFingerprint,
  }) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final now = _clock().toUtc();
    final row = await db
        .customSelect(
          '''
          SELECT *
          FROM agent_runtime_checkpoints
          WHERE owner_user_id = ?
            AND agent_id = ?
            AND request_fingerprint = ?
            AND status != 'terminal'
            AND (expires_at IS NULL OR expires_at > ?)
          ORDER BY updated_at DESC
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
            Variable.withString(requestFingerprint),
            Variable.withInt(now.millisecondsSinceEpoch),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _checkpointFromRow(row);
  }

  @override
  Future<AgentRuntimeCheckpoint> create({
    required String requestFingerprint,
    required Map<String, Object?> snapshot,
    Map<String, Object?> resumeContext = const <String, Object?>{},
  }) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final now = _clock().toUtc();
    final record = checkpointFromRuntimeSnapshot(
      ownerUserId: ownerUserId,
      requestFingerprint: requestFingerprint,
      snapshot: snapshot,
      resumeContext: resumeContext,
      revision: 0,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(retention),
    );
    await db.customInsert('''
      INSERT INTO agent_runtime_checkpoints (
        owner_user_id, run_id, agent_id, request_fingerprint,
        snapshot_version, revision, status, snapshot_json,
        resume_context_json, effect_kind, effect_id, effect_payload_json,
        created_at, updated_at, expires_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', variables: _recordVariables(record));
    return record;
  }

  @override
  Future<AgentRuntimeCheckpoint> replaceSnapshot({
    required String runId,
    required int expectedRevision,
    required String requestFingerprint,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> resumeContext,
  }) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final previous = await _requireRecord(db, ownerUserId, runId);
    requireCheckpointRevision(previous, expectedRevision);
    final now = _clock().toUtc();
    final next = checkpointFromRuntimeSnapshot(
      ownerUserId: ownerUserId,
      requestFingerprint: requestFingerprint,
      snapshot: snapshot,
      resumeContext: resumeContext,
      revision: expectedRevision + 1,
      createdAt: previous.createdAt,
      updatedAt: now,
      expiresAt: now.add(retention),
    );
    if (next.runId != runId) {
      throw const AgentRuntimeCheckpointException(
        AgentRuntimeCheckpointErrorCode.corrupt,
        'replacement snapshot run_id does not match checkpoint',
      );
    }
    final updated = await db.customUpdate(
      '''
      UPDATE agent_runtime_checkpoints
      SET request_fingerprint = ?, snapshot_version = ?, revision = ?,
          status = ?, snapshot_json = ?, resume_context_json = ?,
          effect_kind = ?, effect_id = ?, effect_payload_json = NULL,
          updated_at = ?, expires_at = ?
      WHERE owner_user_id = ? AND run_id = ? AND revision = ?
      ''',
      variables: <Variable<Object>>[
        Variable.withString(next.requestFingerprint),
        Variable.withInt(next.snapshotVersion),
        Variable.withInt(next.revision),
        Variable.withString(next.status.wire),
        Variable.withString(jsonEncode(next.snapshot)),
        Variable.withString(jsonEncode(next.resumeContext)),
        Variable<String>(next.effectKind),
        Variable<String>(next.effectId),
        Variable.withInt(next.updatedAt.millisecondsSinceEpoch),
        Variable<int>(next.expiresAt?.millisecondsSinceEpoch),
        Variable.withString(ownerUserId),
        Variable.withString(runId),
        Variable.withInt(expectedRevision),
      ],
    );
    _requireUpdated(updated);
    return next;
  }

  @override
  Future<AgentRuntimeCheckpoint> reserveEffect({
    required String runId,
    required int expectedRevision,
    required String effectKind,
    required String effectId,
  }) {
    return _transitionEffect(
      runId: runId,
      expectedRevision: expectedRevision,
      expectedStatus: AgentRuntimeCheckpointStatus.awaitingEffect,
      nextStatus: AgentRuntimeCheckpointStatus.dispatching,
      effectKind: effectKind,
      effectId: effectId,
    );
  }

  @override
  Future<AgentRuntimeCheckpoint> recordEffectPayload({
    required String runId,
    required int expectedRevision,
    required String effectKind,
    required String effectId,
    required Map<String, Object?> payload,
  }) {
    return _transitionEffect(
      runId: runId,
      expectedRevision: expectedRevision,
      expectedStatus: AgentRuntimeCheckpointStatus.dispatching,
      nextStatus: AgentRuntimeCheckpointStatus.effectRecorded,
      effectKind: effectKind,
      effectId: effectId,
      payload: payload,
    );
  }

  Future<AgentRuntimeCheckpoint> _transitionEffect({
    required String runId,
    required int expectedRevision,
    required AgentRuntimeCheckpointStatus expectedStatus,
    required AgentRuntimeCheckpointStatus nextStatus,
    required String effectKind,
    required String effectId,
    Map<String, Object?>? payload,
  }) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final previous = await _requireRecord(db, ownerUserId, runId);
    requireCheckpointRevision(previous, expectedRevision);
    if (previous.status != expectedStatus ||
        previous.effectKind != effectKind ||
        previous.effectId != effectId) {
      throw const AgentRuntimeCheckpointException(
        AgentRuntimeCheckpointErrorCode.invalidTransition,
        'checkpoint effect transition does not match the pending effect',
      );
    }
    final now = _clock().toUtc();
    final next = AgentRuntimeCheckpoint(
      ownerUserId: previous.ownerUserId,
      runId: previous.runId,
      agentId: previous.agentId,
      requestFingerprint: previous.requestFingerprint,
      snapshotVersion: previous.snapshotVersion,
      revision: expectedRevision + 1,
      status: nextStatus,
      snapshot: previous.snapshot,
      resumeContext: previous.resumeContext,
      effectKind: effectKind,
      effectId: effectId,
      effectPayload: payload,
      createdAt: previous.createdAt,
      updatedAt: now,
      expiresAt: now.add(retention),
    );
    final updated = await db.customUpdate(
      '''
      UPDATE agent_runtime_checkpoints
      SET revision = ?, status = ?, effect_payload_json = ?,
          updated_at = ?, expires_at = ?
      WHERE owner_user_id = ? AND run_id = ? AND revision = ?
      ''',
      variables: <Variable<Object>>[
        Variable.withInt(next.revision),
        Variable.withString(next.status.wire),
        Variable<String>(
          next.effectPayload == null ? null : jsonEncode(next.effectPayload),
        ),
        Variable.withInt(next.updatedAt.millisecondsSinceEpoch),
        Variable<int>(next.expiresAt?.millisecondsSinceEpoch),
        Variable.withString(ownerUserId),
        Variable.withString(runId),
        Variable.withInt(expectedRevision),
      ],
    );
    _requireUpdated(updated);
    return next;
  }

  @override
  Future<void> pruneTerminalBefore(DateTime cutoff) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    await db.customStatement(
      '''
      DELETE FROM agent_runtime_checkpoints
      WHERE owner_user_id = ? AND status = 'terminal' AND updated_at < ?
      ''',
      <Object?>[ownerUserId, cutoff.toUtc().millisecondsSinceEpoch],
    );
  }
}

List<Variable<Object>> _recordVariables(AgentRuntimeCheckpoint record) =>
    <Variable<Object>>[
      Variable.withString(record.ownerUserId),
      Variable.withString(record.runId),
      Variable.withString(record.agentId),
      Variable.withString(record.requestFingerprint),
      Variable.withInt(record.snapshotVersion),
      Variable.withInt(record.revision),
      Variable.withString(record.status.wire),
      Variable.withString(jsonEncode(record.snapshot)),
      Variable.withString(jsonEncode(record.resumeContext)),
      Variable<String>(record.effectKind),
      Variable<String>(record.effectId),
      Variable<String>(
        record.effectPayload == null ? null : jsonEncode(record.effectPayload),
      ),
      Variable.withInt(record.createdAt.millisecondsSinceEpoch),
      Variable.withInt(record.updatedAt.millisecondsSinceEpoch),
      Variable<int>(record.expiresAt?.millisecondsSinceEpoch),
    ];

Future<AgentRuntimeCheckpoint> _requireRecord(
  AppDatabase db,
  String ownerUserId,
  String runId,
) async {
  final row = await db
      .customSelect(
        '''
        SELECT * FROM agent_runtime_checkpoints
        WHERE owner_user_id = ? AND run_id = ?
        ''',
        variables: <Variable<Object>>[
          Variable.withString(ownerUserId),
          Variable.withString(runId),
        ],
      )
      .getSingleOrNull();
  if (row == null) {
    throw const AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.corrupt,
      'checkpoint does not exist',
    );
  }
  return _checkpointFromRow(row);
}

AgentRuntimeCheckpoint _checkpointFromRow(QueryRow row) {
  final ownerUserId = row.read<String>('owner_user_id');
  final runId = row.read<String>('run_id');
  final agentId = row.read<String>('agent_id');
  final requestFingerprint = row.read<String>('request_fingerprint');
  final snapshotVersion = row.read<int>('snapshot_version');
  final revision = row.read<int>('revision');
  final status = AgentRuntimeCheckpointStatus.fromWire(
    row.read<String>('status'),
  );
  final snapshot = _decodeObject(
    row.read<String>('snapshot_json'),
    'snapshot_json',
  );
  final resumeContext = _decodeObject(
    row.readNullable<String>('resume_context_json') ?? '{}',
    'resume_context_json',
  );
  final effectKind = row.readNullable<String>('effect_kind');
  final effectId = row.readNullable<String>('effect_id');
  final effectPayload = switch (row.readNullable<String>(
    'effect_payload_json',
  )) {
    final String payload => _decodeObject(payload, 'effect_payload_json'),
    null => null,
  };
  final createdAt = DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('created_at'),
    isUtc: true,
  );
  final updatedAt = DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('updated_at'),
    isUtc: true,
  );
  final expiresAt = switch (row.readNullable<int>('expires_at')) {
    final int value => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    null => null,
  };
  final derived = checkpointFromRuntimeSnapshot(
    ownerUserId: ownerUserId,
    requestFingerprint: requestFingerprint,
    snapshot: snapshot,
    resumeContext: resumeContext,
    revision: revision,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
  );
  final identityMatches =
      derived.runId == runId &&
      derived.agentId == agentId &&
      derived.snapshotVersion == snapshotVersion;
  final journalMatches = switch (status) {
    AgentRuntimeCheckpointStatus.terminal =>
      derived.status == AgentRuntimeCheckpointStatus.terminal &&
          effectKind == null &&
          effectId == null &&
          effectPayload == null,
    AgentRuntimeCheckpointStatus.awaitingEffect ||
    AgentRuntimeCheckpointStatus.dispatching =>
      derived.status == AgentRuntimeCheckpointStatus.awaitingEffect &&
          derived.effectKind == effectKind &&
          derived.effectId == effectId &&
          effectPayload == null,
    AgentRuntimeCheckpointStatus.effectRecorded =>
      derived.status == AgentRuntimeCheckpointStatus.awaitingEffect &&
          derived.effectKind == effectKind &&
          derived.effectId == effectId &&
          effectPayload != null,
  };
  if (!identityMatches || !journalMatches) {
    throw const AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.corrupt,
      'checkpoint row does not match its embedded runtime snapshot',
    );
  }
  return AgentRuntimeCheckpoint(
    ownerUserId: ownerUserId,
    runId: runId,
    agentId: agentId,
    requestFingerprint: requestFingerprint,
    snapshotVersion: snapshotVersion,
    revision: revision,
    status: status,
    snapshot: snapshot,
    resumeContext: resumeContext,
    effectKind: effectKind,
    effectId: effectId,
    effectPayload: effectPayload,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
  );
}

Map<String, Object?> _decodeObject(String value, String field) {
  try {
    return checkpointObject(jsonDecode(value), field);
  } on FormatException catch (error) {
    throw AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.corrupt,
      '$field is corrupt: ${error.message}',
    );
  }
}

void _requireUpdated(int updated) {
  if (updated != 1) {
    throw const AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.staleRevision,
      'checkpoint update lost an optimistic revision race',
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
