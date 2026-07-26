import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'agent_artifact.dart';

enum AgentFindingStatus { open, resolved, ignored, snoozed }

class AgentFinding {
  AgentFinding({
    required this.id,
    required this.ownerUserId,
    required this.agentId,
    required this.domain,
    required this.kind,
    required this.severity,
    required this.confidence,
    required this.payload,
  });

  final String id;
  final String ownerUserId;
  final String agentId;
  final String domain;
  final String kind;
  final AgentArtifactSeverity severity;
  final double confidence;
  final Map<String, Object?> payload;

  String get evidenceFingerprint {
    final encoded = jsonEncode(_canonicalize(payload));
    return sha256.convert(utf8.encode(encoded)).toString();
  }
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

class AgentFindingReconcileResult {
  const AgentFindingReconcileResult({
    required this.openIds,
    required this.changedIds,
    required this.resolvedIds,
  });

  final Set<String> openIds;
  final Set<String> changedIds;
  final Set<String> resolvedIds;
}

class StoredAgentFinding {
  const StoredAgentFinding({
    required this.id,
    required this.agentId,
    required this.domain,
    required this.kind,
    required this.severity,
    required this.confidence,
    required this.payload,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  final String id;
  final String agentId;
  final String domain;
  final String kind;
  final AgentArtifactSeverity severity;
  final double confidence;
  final Map<String, Object?> payload;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
}

abstract interface class AgentFindingStore {
  Future<AgentFindingReconcileResult> reconcile({
    required String ownerUserId,
    required String agentId,
    required Iterable<AgentFinding> findings,
    required DateTime observedAt,
  });

  Future<List<StoredAgentFinding>> listOpen({
    required String ownerUserId,
    String? domain,
    String? agentId,
    int limit = 100,
  });

  Future<void> ignore({
    required String ownerUserId,
    required String id,
    required DateTime at,
  });

  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  });

  Future<void> ignoreOpenForAgent({
    required String ownerUserId,
    required String agentId,
    required DateTime at,
  });

  Future<void> snoozeOpenForAgent({
    required String ownerUserId,
    required String agentId,
    required DateTime until,
  });
}

class SqliteAgentFindingStore implements AgentFindingStore {
  SqliteAgentFindingStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> ignore({
    required String ownerUserId,
    required String id,
    required DateTime at,
  }) {
    return _db.customStatement(
      'UPDATE agent_findings SET status = \'ignored\', resolved_at = ?, '
      'snoozed_until = NULL WHERE owner_user_id = ? AND id = ?',
      <Object?>[at.toUtc().millisecondsSinceEpoch, ownerUserId, id],
    );
  }

  @override
  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  }) {
    return _db.customStatement(
      'UPDATE agent_findings SET status = \'snoozed\', snoozed_until = ?, '
      'resolved_at = NULL WHERE owner_user_id = ? AND id = ?',
      <Object?>[until.toUtc().millisecondsSinceEpoch, ownerUserId, id],
    );
  }

  @override
  Future<void> ignoreOpenForAgent({
    required String ownerUserId,
    required String agentId,
    required DateTime at,
  }) {
    return _db.customStatement(
      "UPDATE agent_findings SET status = 'ignored', resolved_at = ?, "
      'snoozed_until = NULL WHERE owner_user_id = ? AND agent_id = ? '
      "AND status = 'open'",
      <Object?>[at.toUtc().millisecondsSinceEpoch, ownerUserId, agentId],
    );
  }

  @override
  Future<void> snoozeOpenForAgent({
    required String ownerUserId,
    required String agentId,
    required DateTime until,
  }) {
    return _db.customStatement(
      "UPDATE agent_findings SET status = 'snoozed', snoozed_until = ?, "
      'resolved_at = NULL WHERE owner_user_id = ? AND agent_id = ? '
      "AND status = 'open'",
      <Object?>[until.toUtc().millisecondsSinceEpoch, ownerUserId, agentId],
    );
  }

  @override
  Future<List<StoredAgentFinding>> listOpen({
    required String ownerUserId,
    String? domain,
    String? agentId,
    int limit = 100,
  }) async {
    final clauses = <String>['owner_user_id = ?', "status = 'open'"];
    final variables = <Variable<Object>>[Variable.withString(ownerUserId)];
    if (domain != null) {
      clauses.add('domain = ?');
      variables.add(Variable.withString(domain));
    }
    if (agentId != null) {
      clauses.add('agent_id = ?');
      variables.add(Variable.withString(agentId));
    }
    variables.add(Variable.withInt(limit.clamp(1, 500)));
    final rows = await _db
        .customSelect(
          'SELECT * FROM agent_findings WHERE ${clauses.join(' AND ')} '
          'ORDER BY last_seen_at DESC LIMIT ?',
          variables: variables,
        )
        .get();
    return rows
        .map(
          (row) => StoredAgentFinding(
            id: row.read<String>('id'),
            agentId: row.read<String>('agent_id'),
            domain: row.read<String>('domain'),
            kind: row.read<String>('kind'),
            severity: agentArtifactSeverityFromWire(
              row.read<String>('severity'),
            ),
            confidence: row.read<double>('confidence'),
            payload: (jsonDecode(row.read<String>('payload_json')) as Map)
                .cast<String, Object?>(),
            firstSeenAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('first_seen_at'),
              isUtc: true,
            ),
            lastSeenAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('last_seen_at'),
              isUtc: true,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<AgentFindingReconcileResult> reconcile({
    required String ownerUserId,
    required String agentId,
    required Iterable<AgentFinding> findings,
    required DateTime observedAt,
  }) {
    return _db.transaction(() async {
      final now = observedAt.toUtc().millisecondsSinceEpoch;
      final incoming = <String, AgentFinding>{
        for (final finding in findings) finding.id: finding,
      };
      final existing = await _db
          .customSelect(
            'SELECT id, status, evidence_fingerprint, snoozed_until '
            'FROM agent_findings '
            'WHERE owner_user_id = ? AND agent_id = ?',
            variables: <Variable<Object>>[
              Variable.withString(ownerUserId),
              Variable.withString(agentId),
            ],
          )
          .get();
      final existingById = <String, QueryRow>{
        for (final row in existing) row.read<String>('id'): row,
      };
      final open = <String>{};
      final changed = <String>{};
      for (final finding in incoming.values) {
        final previous = existingById[finding.id];
        final fingerprint = finding.evidenceFingerprint;
        final previousStatus = previous?.read<String>('status');
        final unchangedEvidence =
            previous?.read<String>('evidence_fingerprint') == fingerprint;
        final snoozedUntil = previous?.readNullable<int>('snoozed_until');
        final suppressed =
            unchangedEvidence &&
            (previousStatus == AgentFindingStatus.ignored.name ||
                (previousStatus == AgentFindingStatus.snoozed.name &&
                    snoozedUntil != null &&
                    snoozedUntil > now));
        if (suppressed) {
          await _db.customStatement(
            'UPDATE agent_findings SET last_seen_at = ? '
            'WHERE owner_user_id = ? AND id = ?',
            <Object?>[now, ownerUserId, finding.id],
          );
          continue;
        }
        open.add(finding.id);
        if (previous == null ||
            previousStatus != AgentFindingStatus.open.name ||
            !unchangedEvidence) {
          changed.add(finding.id);
        }
        await _db.customStatement(
          '''
          INSERT INTO agent_findings (
            owner_user_id, id, agent_id, domain, kind, status, severity,
            confidence, evidence_fingerprint, payload_json, first_seen_at,
            last_seen_at, resolved_at, snoozed_until
          ) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, ?, ?, ?, NULL, NULL)
          ON CONFLICT(owner_user_id, id) DO UPDATE SET
            agent_id = excluded.agent_id,
            domain = excluded.domain,
            kind = excluded.kind,
            status = 'open',
            severity = excluded.severity,
            confidence = excluded.confidence,
            evidence_fingerprint = excluded.evidence_fingerprint,
            payload_json = excluded.payload_json,
            last_seen_at = excluded.last_seen_at,
            resolved_at = NULL,
            snoozed_until = NULL
          ''',
          <Object?>[
            ownerUserId,
            finding.id,
            agentId,
            finding.domain,
            finding.kind,
            finding.severity.wire,
            finding.confidence.clamp(0, 1),
            fingerprint,
            jsonEncode(finding.payload),
            now,
            now,
          ],
        );
      }
      final resolved = <String>{};
      for (final row in existing) {
        final id = row.read<String>('id');
        if (incoming.containsKey(id) ||
            row.read<String>('status') != AgentFindingStatus.open.name) {
          continue;
        }
        resolved.add(id);
        await _db.customStatement(
          'UPDATE agent_findings SET status = ?, resolved_at = ?, '
          'last_seen_at = ? WHERE owner_user_id = ? AND id = ?',
          <Object?>[
            AgentFindingStatus.resolved.name,
            now,
            now,
            ownerUserId,
            id,
          ],
        );
      }
      return AgentFindingReconcileResult(
        openIds: open,
        changedIds: changed,
        resolvedIds: resolved,
      );
    });
  }
}
