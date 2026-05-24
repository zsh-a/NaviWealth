/// Wave 23 — Drift-backed [AiTraceStore].
///
/// Each row stores the trace as a JSON blob plus a few indexed columns
/// (request_id PK, started_at_iso for ORDER BY, owner_user_id for
/// multi-user scoping). 30-day retention is callers' responsibility —
/// they call [pruneOlderThan] on a schedule; the store does not run a
/// cleanup loop itself (battery + Drift lock concerns).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import '../contracts/contracts.dart';
import 'ai_trace_store.dart';

class DriftAiTraceStore implements AiTraceStore {
  DriftAiTraceStore(this._db, {this.ownerUserId});

  final AppDatabase _db;

  /// Optional owner partition. When set, every `append` stamps this id
  /// and every read scopes by it. When `null` we store/read with an
  /// empty string — fine for single-user dev builds.
  final String? ownerUserId;

  String get _owner => ownerUserId ?? '';

  @override
  Future<void> append(AiTrace trace) async {
    final payload = jsonEncode(trace.toJson());
    await _db.customInsert(
      'INSERT OR REPLACE INTO ai_traces '
      '(request_id, owner_user_id, started_at_iso, payload_json) '
      'VALUES (?1, ?2, ?3, ?4)',
      variables: [
        Variable.withString(trace.requestId),
        Variable.withString(_owner),
        Variable.withString(trace.startedAtIso),
        Variable.withString(payload),
      ],
    );
  }

  @override
  Future<List<AiTrace>> recent({int limit = 50}) async {
    if (limit <= 0) return const <AiTrace>[];
    final rows = await _db
        .customSelect(
          'SELECT payload_json FROM ai_traces '
          'WHERE owner_user_id = ?1 '
          'ORDER BY started_at_iso DESC '
          'LIMIT ?2',
          variables: [Variable.withString(_owner), Variable.withInt(limit)],
        )
        .get();
    final out = <AiTrace>[];
    for (final row in rows) {
      final raw = row.read<String>('payload_json');
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        out.add(AiTrace.fromJson(json));
      } catch (_) {
        // Skip corrupt rows rather than fail the whole listing — the
        // transparency surface is best-effort.
      }
    }
    return out;
  }

  @override
  Future<void> pruneOlderThan(DateTime cutoff) async {
    await _db.customStatement(
      'DELETE FROM ai_traces WHERE owner_user_id = ?1 '
      'AND started_at_iso < ?2',
      [_owner, cutoff.toUtc().toIso8601String()],
    );
  }

  @override
  Future<AiTrace?> findByRequestId(String requestId) async {
    final rows = await _db
        .customSelect(
          'SELECT payload_json FROM ai_traces '
          'WHERE request_id = ?1 AND owner_user_id = ?2 LIMIT 1',
          variables: [
            Variable.withString(requestId),
            Variable.withString(_owner),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      final raw = rows.first.read<String>('payload_json');
      final json = jsonDecode(raw) as Map<String, Object?>;
      return AiTrace.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
