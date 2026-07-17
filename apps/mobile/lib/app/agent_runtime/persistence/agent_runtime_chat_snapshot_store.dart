/// Durable app-owned chat-turn snapshots for Android process recovery.
library;

const int kAgentRuntimeChatSnapshotVersion = 1;

enum AgentRuntimeChatSnapshotErrorCode {
  corrupt,
  staleRevision,
  interruptedAtMostOnce,
}

final class AgentRuntimeChatSnapshotException implements Exception {
  const AgentRuntimeChatSnapshotException(this.code, this.message);

  final AgentRuntimeChatSnapshotErrorCode code;
  final String message;

  @override
  String toString() => 'AgentRuntimeChatSnapshotException($code): $message';
}

final class AgentRuntimeChatSnapshotRecord {
  const AgentRuntimeChatSnapshotRecord({
    required this.ownerUserId,
    required this.turnId,
    required this.snapshotVersion,
    required this.revision,
    required this.status,
    required this.snapshot,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String ownerUserId;
  final String turnId;
  final int snapshotVersion;
  final int revision;
  final String status;
  final Map<String, Object?> snapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  bool get isTerminal =>
      const <String>{'completed', 'cancelled', 'failed'}.contains(status);
}

abstract interface class AgentRuntimeChatSnapshotStore {
  Future<AgentRuntimeChatSnapshotRecord?> loadResumable(String turnId);

  Future<AgentRuntimeChatSnapshotRecord> save({
    required Map<String, Object?> snapshot,
    int? expectedRevision,
  });

  Future<void> pruneTerminalBefore(DateTime cutoff);
}

typedef AgentRuntimeChatSnapshotClock = DateTime Function();

final class InMemoryAgentRuntimeChatSnapshotStore
    implements AgentRuntimeChatSnapshotStore {
  InMemoryAgentRuntimeChatSnapshotStore({
    this.ownerUserId = 'test-user',
    this.retention = const Duration(days: 1),
    AgentRuntimeChatSnapshotClock? clock,
  }) : _clock = clock ?? _utcNow;

  final String ownerUserId;
  final Duration retention;
  final AgentRuntimeChatSnapshotClock _clock;
  final Map<String, AgentRuntimeChatSnapshotRecord> _records =
      <String, AgentRuntimeChatSnapshotRecord>{};

  @override
  Future<AgentRuntimeChatSnapshotRecord?> loadResumable(String turnId) async {
    final record = _records[turnId];
    final now = _clock().toUtc();
    if (record == null ||
        record.isTerminal ||
        (record.expiresAt?.isBefore(now) ?? false)) {
      return null;
    }
    return record;
  }

  @override
  Future<AgentRuntimeChatSnapshotRecord> save({
    required Map<String, Object?> snapshot,
    int? expectedRevision,
  }) async {
    final identity = parseAgentRuntimeChatSnapshot(snapshot);
    final previous = _records[identity.turnId];
    if (previous == null && expectedRevision != null) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.staleRevision,
        'chat snapshot does not exist',
      );
    }
    if (previous != null && previous.revision != expectedRevision) {
      throw AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.staleRevision,
        'chat snapshot revision ${previous.revision} does not match '
        '$expectedRevision',
      );
    }
    final now = _clock().toUtc();
    final record = AgentRuntimeChatSnapshotRecord(
      ownerUserId: ownerUserId,
      turnId: identity.turnId,
      snapshotVersion: identity.snapshotVersion,
      revision: (previous?.revision ?? -1) + 1,
      status: identity.status,
      snapshot: Map<String, Object?>.from(snapshot),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      expiresAt: now.add(retention),
    );
    _records[record.turnId] = record;
    return record;
  }

  @override
  Future<void> pruneTerminalBefore(DateTime cutoff) async {
    _records.removeWhere(
      (_, record) =>
          record.isTerminal && record.updatedAt.isBefore(cutoff.toUtc()),
    );
  }

  AgentRuntimeChatSnapshotRecord? debugRecord(String turnId) =>
      _records[turnId];
}

final class AgentRuntimeChatSnapshotIdentity {
  const AgentRuntimeChatSnapshotIdentity({
    required this.turnId,
    required this.snapshotVersion,
    required this.status,
  });

  final String turnId;
  final int snapshotVersion;
  final String status;
}

AgentRuntimeChatSnapshotIdentity parseAgentRuntimeChatSnapshot(
  Map<String, Object?> snapshot,
) {
  if (snapshot['protocol_version'] != 'agent.v1') {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot protocol_version is unsupported',
    );
  }
  final version = snapshot['snapshot_version'];
  if (version != kAgentRuntimeChatSnapshotVersion) {
    throw AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot version $version is unsupported',
    );
  }
  final status = snapshot['status'];
  if (status is! String ||
      !const <String>{
        'ready_for_model',
        'requires_tool_results',
        'completed',
        'cancelled',
        'failed',
      }.contains(status)) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot status is invalid',
    );
  }
  final state = chatSnapshotObject(snapshot['state'], 'snapshot.state');
  final turnId = state['turn_id'];
  if (turnId is! String || turnId.trim().isEmpty) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot state.turn_id is required',
    );
  }
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot tool_dispatches must be an array',
    );
  }
  final pendingCalls = state['pending_tool_calls'];
  final pendingIds = <String>{};
  if (pendingCalls is List) {
    for (final value in pendingCalls) {
      final call = chatSnapshotObject(
        value,
        'snapshot.state.pending_tool_call',
      );
      final id = call['id'];
      if (id is! String || id.isEmpty || !pendingIds.add(id)) {
        throw const AgentRuntimeChatSnapshotException(
          AgentRuntimeChatSnapshotErrorCode.corrupt,
          'chat snapshot pending tool ids must be unique non-empty strings',
        );
      }
    }
  }
  final dispatchIds = <String>{};
  for (final value in rawDispatches) {
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final call = chatSnapshotObject(
      dispatch['call'],
      'snapshot.tool_dispatch.call',
    );
    final id = call['id'];
    final name = call['name'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        !dispatchIds.add(id)) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.corrupt,
        'chat snapshot dispatch identities must be unique and non-empty',
      );
    }
    if (!const <String>{
      'safe_retry',
      'idempotent',
      'at_most_once',
    }.contains(dispatch['replay_policy'])) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.corrupt,
        'chat snapshot replay policy is invalid',
      );
    }
    final dispatchStatus = dispatch['status'];
    if (!const <String>{
      'pending',
      'dispatching',
      'completed',
      'interrupted',
    }.contains(dispatchStatus)) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.corrupt,
        'chat snapshot dispatch status is invalid',
      );
    }
    final result = dispatch['result'];
    if (dispatchStatus == 'completed') {
      final resultObject = chatSnapshotObject(
        result,
        'snapshot.tool_dispatch.result',
      );
      if (resultObject['tool_call_id']?.toString() != id ||
          resultObject['tool_name'] != name) {
        throw const AgentRuntimeChatSnapshotException(
          AgentRuntimeChatSnapshotErrorCode.corrupt,
          'chat snapshot tool result does not match its dispatch',
        );
      }
    } else if (result != null) {
      throw const AgentRuntimeChatSnapshotException(
        AgentRuntimeChatSnapshotErrorCode.corrupt,
        'unfinished chat snapshot dispatch cannot contain a result',
      );
    }
  }
  if (status == 'requires_tool_results' &&
      (pendingIds.isEmpty || !_sameStrings(pendingIds, dispatchIds))) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot journal must match pending tool calls',
    );
  }
  if ((status == 'ready_for_model' || status == 'completed') &&
      (pendingIds.isNotEmpty || dispatchIds.isNotEmpty)) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'non-tool chat snapshot cannot retain a dispatch journal',
    );
  }
  return AgentRuntimeChatSnapshotIdentity(
    turnId: turnId,
    snapshotVersion: version as int,
    status: status,
  );
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Map<String, Object?> chatSnapshotObject(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw AgentRuntimeChatSnapshotException(
    AgentRuntimeChatSnapshotErrorCode.corrupt,
    '$label must be an object',
  );
}

DateTime _utcNow() => DateTime.now().toUtc();
