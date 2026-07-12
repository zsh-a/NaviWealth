/// App-owned durable checkpoints for the embedded Rust agent runtime.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AgentRuntimeCheckpointStatus {
  awaitingEffect('awaiting_effect'),
  dispatching('dispatching'),
  effectRecorded('effect_recorded'),
  terminal('terminal');

  const AgentRuntimeCheckpointStatus(this.wire);

  final String wire;

  static AgentRuntimeCheckpointStatus fromWire(String value) => switch (value) {
    'awaiting_effect' => awaitingEffect,
    'dispatching' => dispatching,
    'effect_recorded' => effectRecorded,
    'terminal' => terminal,
    _ => throw FormatException(
      'unknown agent runtime checkpoint status',
      value,
    ),
  };
}

enum AgentRuntimeCheckpointErrorCode {
  corrupt,
  staleRevision,
  invalidTransition,
  interruptedEffect,
}

final class AgentRuntimeCheckpointException implements Exception {
  const AgentRuntimeCheckpointException(this.code, this.message);

  final AgentRuntimeCheckpointErrorCode code;
  final String message;

  @override
  String toString() => 'AgentRuntimeCheckpointException($code): $message';
}

final class AgentRuntimeCheckpoint {
  const AgentRuntimeCheckpoint({
    required this.ownerUserId,
    required this.runId,
    required this.agentId,
    required this.requestFingerprint,
    required this.snapshotVersion,
    required this.revision,
    required this.status,
    required this.snapshot,
    required this.resumeContext,
    required this.createdAt,
    required this.updatedAt,
    this.effectKind,
    this.effectId,
    this.effectPayload,
    this.expiresAt,
  });

  final String ownerUserId;
  final String runId;
  final String agentId;
  final String requestFingerprint;
  final int snapshotVersion;
  final int revision;
  final AgentRuntimeCheckpointStatus status;
  final Map<String, Object?> snapshot;
  final Map<String, Object?> resumeContext;
  final String? effectKind;
  final String? effectId;
  final Map<String, Object?>? effectPayload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  bool get isTerminal => status == AgentRuntimeCheckpointStatus.terminal;
}

abstract interface class AgentRuntimeCheckpointStore {
  Future<AgentRuntimeCheckpoint?> findResumable({
    required String agentId,
    required String requestFingerprint,
  });

  Future<AgentRuntimeCheckpoint> create({
    required String requestFingerprint,
    required Map<String, Object?> snapshot,
    Map<String, Object?> resumeContext = const <String, Object?>{},
  });

  Future<AgentRuntimeCheckpoint> replaceSnapshot({
    required String runId,
    required int expectedRevision,
    required String requestFingerprint,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> resumeContext,
  });

  Future<AgentRuntimeCheckpoint> reserveEffect({
    required String runId,
    required int expectedRevision,
    required String effectKind,
    required String effectId,
  });

  Future<AgentRuntimeCheckpoint> recordEffectPayload({
    required String runId,
    required int expectedRevision,
    required String effectKind,
    required String effectId,
    required Map<String, Object?> payload,
  });

  Future<void> pruneTerminalBefore(DateTime cutoff);
}

typedef AgentRuntimeCheckpointClock = DateTime Function();

final class InMemoryAgentRuntimeCheckpointStore
    implements AgentRuntimeCheckpointStore {
  InMemoryAgentRuntimeCheckpointStore({
    AgentRuntimeCheckpointClock? clock,
    this.retention = const Duration(days: 1),
    this.ownerUserId = 'test-user',
  }) : _clock = clock ?? _utcNow;

  final AgentRuntimeCheckpointClock _clock;
  final Duration retention;
  final String ownerUserId;
  final Map<String, AgentRuntimeCheckpoint> _records =
      <String, AgentRuntimeCheckpoint>{};

  @override
  Future<AgentRuntimeCheckpoint?> findResumable({
    required String agentId,
    required String requestFingerprint,
  }) async {
    final now = _clock().toUtc();
    final matches =
        _records.values
            .where(
              (record) =>
                  record.agentId == agentId &&
                  record.requestFingerprint == requestFingerprint &&
                  !record.isTerminal &&
                  (record.expiresAt == null || record.expiresAt!.isAfter(now)),
            )
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<AgentRuntimeCheckpoint> create({
    required String requestFingerprint,
    required Map<String, Object?> snapshot,
    Map<String, Object?> resumeContext = const <String, Object?>{},
  }) async {
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
    if (_records.containsKey(record.runId)) {
      throw const AgentRuntimeCheckpointException(
        AgentRuntimeCheckpointErrorCode.invalidTransition,
        'checkpoint already exists',
      );
    }
    _records[record.runId] = record;
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
    final previous = _requireMemoryRecord(runId, expectedRevision);
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
    _records[runId] = next;
    return next;
  }

  @override
  Future<AgentRuntimeCheckpoint> reserveEffect({
    required String runId,
    required int expectedRevision,
    required String effectKind,
    required String effectId,
  }) {
    return _transition(
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
    return _transition(
      runId: runId,
      expectedRevision: expectedRevision,
      expectedStatus: AgentRuntimeCheckpointStatus.dispatching,
      nextStatus: AgentRuntimeCheckpointStatus.effectRecorded,
      effectKind: effectKind,
      effectId: effectId,
      payload: payload,
    );
  }

  Future<AgentRuntimeCheckpoint> _transition({
    required String runId,
    required int expectedRevision,
    required AgentRuntimeCheckpointStatus expectedStatus,
    required AgentRuntimeCheckpointStatus nextStatus,
    required String effectKind,
    required String effectId,
    Map<String, Object?>? payload,
  }) async {
    final previous = _requireMemoryRecord(runId, expectedRevision);
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
    _records[runId] = next;
    return next;
  }

  AgentRuntimeCheckpoint _requireMemoryRecord(
    String runId,
    int expectedRevision,
  ) {
    final record = _records[runId];
    if (record == null) {
      throw const AgentRuntimeCheckpointException(
        AgentRuntimeCheckpointErrorCode.corrupt,
        'checkpoint does not exist',
      );
    }
    requireCheckpointRevision(record, expectedRevision);
    return record;
  }

  @override
  Future<void> pruneTerminalBefore(DateTime cutoff) async {
    _records.removeWhere(
      (_, record) =>
          record.isTerminal && record.updatedAt.isBefore(cutoff.toUtc()),
    );
  }

  AgentRuntimeCheckpoint? debugRecord(String runId) => _records[runId];
}

String agentRuntimeRequestFingerprint({
  required String agentId,
  required Map<String, Object?> catalog,
  required Map<String, Object?> request,
  String kind = 'run',
}) {
  final canonical = _canonicalize(<String, Object?>{
    'protocol_version': catalog['protocol_version'],
    'catalog_version': catalog['catalog_version'],
    'agent_id': agentId,
    'kind': kind,
    'request': request,
  });
  return 'agent-runtime-request/v1:${sha256.convert(utf8.encode(jsonEncode(canonical)))}';
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  return value;
}

AgentRuntimeCheckpoint checkpointFromRuntimeSnapshot({
  required String ownerUserId,
  required String requestFingerprint,
  required Map<String, Object?> snapshot,
  required Map<String, Object?> resumeContext,
  required int revision,
  required DateTime createdAt,
  required DateTime updatedAt,
  required DateTime? expiresAt,
}) {
  final snapshotVersion = snapshot['snapshot_version'];
  final step = checkpointObject(snapshot['step'], 'snapshot.step');
  final runId = _nonEmptyString(step['run_id'], 'snapshot.step.run_id');
  final agentId = _nonEmptyString(step['agent_id'], 'snapshot.step.agent_id');
  if (snapshotVersion is! int || snapshotVersion <= 0) {
    throw const AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.corrupt,
      'snapshot_version must be a positive integer',
    );
  }
  final terminal = step['status'] != 'effect_requested';
  final effect = terminal
      ? null
      : checkpointObject(step['effect'], 'snapshot.step.effect');
  final effectKind = effect == null
      ? null
      : _nonEmptyString(effect['kind'], 'snapshot.step.effect.kind');
  final effectId = effect == null
      ? null
      : _nonEmptyString(effect['effect_id'], 'snapshot.step.effect.effect_id');
  if (effectKind != null && effectKind != 'tool' && effectKind != 'subagent') {
    throw AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.corrupt,
      'unsupported checkpoint effect kind $effectKind',
    );
  }
  return AgentRuntimeCheckpoint(
    ownerUserId: ownerUserId,
    runId: runId,
    agentId: agentId,
    requestFingerprint: requestFingerprint,
    snapshotVersion: snapshotVersion,
    revision: revision,
    status: terminal
        ? AgentRuntimeCheckpointStatus.terminal
        : AgentRuntimeCheckpointStatus.awaitingEffect,
    snapshot: Map<String, Object?>.from(snapshot),
    resumeContext: Map<String, Object?>.from(resumeContext),
    effectKind: effectKind,
    effectId: effectId,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    expiresAt: expiresAt?.toUtc(),
  );
}

Map<String, Object?> checkpointObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$field must be an object', value);
}

String _nonEmptyString(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw AgentRuntimeCheckpointException(
    AgentRuntimeCheckpointErrorCode.corrupt,
    '$field must be a non-empty string',
  );
}

void requireCheckpointRevision(
  AgentRuntimeCheckpoint record,
  int expectedRevision,
) {
  if (record.revision != expectedRevision) {
    throw AgentRuntimeCheckpointException(
      AgentRuntimeCheckpointErrorCode.staleRevision,
      'checkpoint revision ${record.revision} does not match expected '
      '$expectedRevision',
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
