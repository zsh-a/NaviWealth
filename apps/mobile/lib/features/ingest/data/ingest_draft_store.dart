/// §5.10.10 / S5a — Drift-backed staging store for ingest drafts.
///
/// Same engineering shape as `DriftUndoStack` / `DriftAiTouchedStore`:
/// owner-partitioned raw SQL over a side table, a broadcast tick so
/// providers re-query on mutation. Crucially this table is **never**
/// in the sync OpLog — drafts are device-local until confirmed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import '../domain/ingest_models.dart';

class IngestDraftStore {
  IngestDraftStore(this._db, {this.ownerUserId});

  final AppDatabase _db;
  final String? ownerUserId;

  String get _owner => ownerUserId ?? '';

  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> putAll(List<IngestDraft> drafts) async {
    if (drafts.isEmpty) return;
    await _db.transaction(() async {
      for (final d in drafts) {
        await _db.customInsert(
          'INSERT OR REPLACE INTO ingest_drafts '
          '(draft_id, owner_user_id, created_at_iso, source_kind, '
          ' origin_label, parsed_json, confidence, dedup_verdict, '
          ' dedup_target_entry_id, trace_id, status, expires_at_iso) '
          'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)',
          variables: [
            Variable.withString(d.draftId),
            Variable.withString(_owner),
            Variable.withString(d.createdAt.toUtc().toIso8601String()),
            Variable.withString(d.sourceKind.wire),
            d.originLabel == null
                ? const Variable<String>(null)
                : Variable.withString(d.originLabel!),
            Variable.withString(jsonEncode(d.parsed.toJson())),
            Variable.withReal(d.confidence),
            Variable.withString(d.verdict.wire),
            d.dedupTargetEntryId == null
                ? const Variable<String>(null)
                : Variable.withString(d.dedupTargetEntryId!),
            d.traceId == null
                ? const Variable<String>(null)
                : Variable.withString(d.traceId!),
            Variable.withString(d.status.wire),
            d.expiresAt == null
                ? const Variable<String>(null)
                : Variable.withString(d.expiresAt!.toUtc().toIso8601String()),
          ],
        );
      }
    });
    _notify();
  }

  Future<List<IngestDraft>> listByStatus(
    DraftStatus status, {
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM ingest_drafts '
          'WHERE owner_user_id = ?1 AND status = ?2 '
          'ORDER BY created_at_iso DESC LIMIT ?3',
          variables: [
            Variable.withString(_owner),
            Variable.withString(status.wire),
            Variable.withInt(limit),
          ],
        )
        .get();
    return rows.map(_rowToDraft).toList(growable: false);
  }

  Stream<List<IngestDraft>> watchByStatus(
    DraftStatus status, {
    int limit = 200,
  }) async* {
    yield await listByStatus(status, limit: limit);
    await for (final _ in _changes.stream) {
      yield await listByStatus(status, limit: limit);
    }
  }

  Future<int> countByStatus(DraftStatus status) async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM ingest_drafts '
          'WHERE owner_user_id = ?1 AND status = ?2',
          variables: [
            Variable.withString(_owner),
            Variable.withString(status.wire),
          ],
        )
        .get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('n');
  }

  Future<void> updateStatus(String draftId, DraftStatus status) async {
    await _db.customStatement(
      'UPDATE ingest_drafts SET status = ?1 '
      'WHERE draft_id = ?2 AND owner_user_id = ?3',
      [status.wire, draftId, _owner],
    );
    _notify();
  }

  /// Drop confirmed/dismissed rows older than [cutoff] (housekeeping).
  Future<void> pruneSettledBefore(DateTime cutoff) async {
    await _db.customStatement(
      'DELETE FROM ingest_drafts '
      "WHERE owner_user_id = ?1 AND status != 'pending' "
      'AND created_at_iso < ?2',
      [_owner, cutoff.toUtc().toIso8601String()],
    );
    _notify();
  }

  IngestDraft _rowToDraft(QueryRow row) {
    final parsed = ParsedTransaction.fromJson(
      jsonDecode(row.read<String>('parsed_json')) as Map<String, Object?>,
    );
    final expiresIso = row.read<String?>('expires_at_iso');
    return IngestDraft(
      draftId: row.read<String>('draft_id'),
      ownerUserId: row.read<String>('owner_user_id'),
      createdAt:
          DateTime.tryParse(row.read<String>('created_at_iso'))?.toUtc() ??
          DateTime.now().toUtc(),
      sourceKind: IngestSourceKindX.parse(row.read<String>('source_kind')),
      parsed: parsed,
      verdict: DedupVerdictX.parse(row.read<String>('dedup_verdict')),
      status: DraftStatusX.parse(row.read<String>('status')),
      originLabel: row.read<String?>('origin_label'),
      dedupTargetEntryId: row.read<String?>('dedup_target_entry_id'),
      traceId: row.read<String?>('trace_id'),
      expiresAt: expiresIso == null ? null : DateTime.tryParse(expiresIso),
    );
  }

  void dispose() {
    if (!_changes.isClosed) _changes.close();
  }
}
