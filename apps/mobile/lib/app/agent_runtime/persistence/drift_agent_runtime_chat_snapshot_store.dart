/// Drift adapter for durable chat-turn snapshots.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

typedef AgentRuntimeChatDatabaseReader = Future<AppDatabase> Function();
typedef AgentRuntimeChatOwnerUserIdReader = Future<String> Function();

final class DriftAgentRuntimeChatSnapshotStore
    implements AgentRuntimeChatSnapshotStore {
  DriftAgentRuntimeChatSnapshotStore({
    required AgentRuntimeChatDatabaseReader databaseReader,
    required AgentRuntimeChatOwnerUserIdReader ownerUserIdReader,
    AgentRuntimeChatSnapshotClock? clock,
    this.retention = const Duration(days: 1),
  }) : _databaseReader = databaseReader,
       _ownerUserIdReader = ownerUserIdReader,
       _clock = clock ?? _utcNow;

  final AgentRuntimeChatDatabaseReader _databaseReader;
  final AgentRuntimeChatOwnerUserIdReader _ownerUserIdReader;
  final AgentRuntimeChatSnapshotClock _clock;
  final Duration retention;

  @override
  Future<AgentRuntimeChatSnapshotRecord?> loadResumable(String turnId) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final now = _clock().toUtc();
    final row = await db
        .customSelect(
          '''
      SELECT * FROM agent_runtime_chat_snapshots
      WHERE owner_user_id = ? AND turn_id = ?
        AND status NOT IN ('completed', 'cancelled', 'failed')
        AND (expires_at IS NULL OR expires_at > ?)
      ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withString(turnId),
            Variable.withInt(now.millisecondsSinceEpoch),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _recordFromRow(row);
  }

  @override
  Future<AgentRuntimeChatSnapshotRecord> save({
    required Map<String, Object?> snapshot,
    int? expectedRevision,
  }) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    final identity = parseAgentRuntimeChatSnapshot(snapshot);
    final now = _clock().toUtc();
    final expiresAt = now.add(retention);
    if (expectedRevision == null) {
      final inserted = await db.customUpdate(
        '''
        INSERT OR IGNORE INTO agent_runtime_chat_snapshots (
          owner_user_id, turn_id, snapshot_version, revision, status,
          snapshot_json, created_at, updated_at, expires_at
        ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable.withString(ownerUserId),
          Variable.withString(identity.turnId),
          Variable.withInt(identity.snapshotVersion),
          Variable.withString(identity.status),
          Variable.withString(jsonEncode(snapshot)),
          Variable.withInt(now.millisecondsSinceEpoch),
          Variable.withInt(now.millisecondsSinceEpoch),
          Variable.withInt(expiresAt.millisecondsSinceEpoch),
        ],
      );
      if (inserted != 1) {
        throw const AgentRuntimeChatSnapshotException(
          AgentRuntimeChatSnapshotErrorCode.staleRevision,
          'chat snapshot already exists',
        );
      }
      return AgentRuntimeChatSnapshotRecord(
        ownerUserId: ownerUserId,
        turnId: identity.turnId,
        snapshotVersion: identity.snapshotVersion,
        revision: 0,
        status: identity.status,
        snapshot: Map<String, Object?>.from(snapshot),
        createdAt: now,
        updatedAt: now,
        expiresAt: expiresAt,
      );
    }
    final updated = await db.customUpdate(
      '''
      UPDATE agent_runtime_chat_snapshots
      SET snapshot_version = ?, revision = ?, status = ?, snapshot_json = ?,
          updated_at = ?, expires_at = ?
      WHERE owner_user_id = ? AND turn_id = ? AND revision = ?
      ''',
      variables: <Variable<Object>>[
        Variable.withInt(identity.snapshotVersion),
        Variable.withInt(expectedRevision + 1),
        Variable.withString(identity.status),
        Variable.withString(jsonEncode(snapshot)),
        Variable.withInt(now.millisecondsSinceEpoch),
        Variable.withInt(expiresAt.millisecondsSinceEpoch),
        Variable.withString(ownerUserId),
        Variable.withString(identity.turnId),
        Variable.withInt(expectedRevision),
      ],
    );
    if (updated != 1) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.staleRevision,
        'chat snapshot update lost an optimistic revision race',
      );
    }
    final row = await db
        .customSelect(
          '''
      SELECT * FROM agent_runtime_chat_snapshots
      WHERE owner_user_id = ? AND turn_id = ?
      ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withString(identity.turnId),
          ],
        )
        .getSingle();
    return _recordFromRow(row);
  }

  @override
  Future<void> pruneTerminalBefore(DateTime cutoff) async {
    final db = await _databaseReader();
    final ownerUserId = await _ownerUserIdReader();
    await db.customStatement(
      '''
      DELETE FROM agent_runtime_chat_snapshots
      WHERE owner_user_id = ?
        AND status IN ('completed', 'cancelled', 'failed')
        AND updated_at < ?
      ''',
      <Object?>[ownerUserId, cutoff.toUtc().millisecondsSinceEpoch],
    );
  }
}

AgentRuntimeChatSnapshotRecord _recordFromRow(QueryRow row) {
  final snapshotValue = jsonDecode(row.read<String>('snapshot_json'));
  final snapshot = chatSnapshotObject(snapshotValue, 'snapshot_json');
  final identity = parseAgentRuntimeChatSnapshot(snapshot);
  final rowTurnId = row.read<String>('turn_id');
  final rowVersion = row.read<int>('snapshot_version');
  final rowStatus = row.read<String>('status');
  if (rowTurnId != identity.turnId ||
      rowVersion != identity.snapshotVersion ||
      rowStatus != identity.status) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot row does not match its payload',
    );
  }
  return AgentRuntimeChatSnapshotRecord(
    ownerUserId: row.read<String>('owner_user_id'),
    turnId: rowTurnId,
    snapshotVersion: rowVersion,
    revision: row.read<int>('revision'),
    status: rowStatus,
    snapshot: snapshot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('updated_at'),
      isUtc: true,
    ),
    expiresAt: switch (row.readNullable<int>('expires_at')) {
      final int value => DateTime.fromMillisecondsSinceEpoch(
        value,
        isUtc: true,
      ),
      null => null,
    },
  );
}

DateTime _utcNow() => DateTime.now().toUtc();
