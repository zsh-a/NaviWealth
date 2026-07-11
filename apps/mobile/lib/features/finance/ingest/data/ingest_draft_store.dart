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

import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/persistence/app_database.dart';
import '../domain/ingest_models.dart';
import 'ingest_confirm_service.dart'
    show
        ConfirmedIngestItem,
        IngestDraftBatchLifecycleStore,
        IngestLifecycleMutationOutcome,
        IngestLifecycleMutationResult,
        IngestLifecycleTransition,
        IngestReviewItem;

class IngestDraftStore implements IngestDraftBatchLifecycleStore {
  IngestDraftStore(this._db, {this.ownerUserId});

  final AppDatabase _db;
  final String? ownerUserId;

  String get _owner => ownerUserId ?? '';

  final StreamController<void> _changes = StreamController<void>.broadcast();
  var _batchDepth = 0;
  var _batchNotificationPending = false;

  void _notify() {
    if (_batchDepth > 0) {
      _batchNotificationPending = true;
      return;
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Runs a bounded confirmation chunk in one outer transaction. Repository
  /// transactions opened by the proposal applier become nested savepoints, so
  /// one rejected row can still roll back independently while successful rows
  /// commit together. Observers receive one refresh after the chunk commits.
  @override
  Future<T> runBatch<T>(Future<T> Function() action) async {
    _batchDepth++;
    try {
      return await _db.transaction(action);
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _batchNotificationPending) {
        _batchNotificationPending = false;
        if (!_changes.isClosed) _changes.add(null);
      }
    }
  }

  Future<void> putAll(List<IngestDraft> drafts) async {
    if (drafts.isEmpty) return;
    const sql =
        'INSERT OR REPLACE INTO ingest_drafts '
        '(draft_id, owner_user_id, created_at_iso, source_kind, '
        ' origin_label, parsed_json, confidence, dedup_verdict, '
        ' dedup_target_entry_id, trace_id, status, expires_at_iso) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    await _db.batch((batch) {
      for (final d in drafts) {
        batch.customStatement(sql, [
          d.draftId,
          _owner,
          d.createdAt.toUtc().toIso8601String(),
          d.sourceKind.wire,
          d.originLabel,
          jsonEncode(d.parsed.toJson()),
          d.confidence,
          d.verdict.wire,
          d.dedupTargetEntryId,
          d.traceId,
          d.status.wire,
          d.expiresAt?.toUtc().toIso8601String(),
        ]);
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

  Future<List<IngestReviewItem>> listPendingReviewItems({
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM ingest_drafts '
          'WHERE owner_user_id = ?1 AND status IN (?2, ?3) '
          'ORDER BY created_at_iso DESC LIMIT ?4',
          variables: [
            Variable.withString(_owner),
            Variable.withString(DraftStatus.pending.wire),
            Variable.withString(DraftStatus.confirming.wire),
            Variable.withInt(limit),
          ],
        )
        .get();
    return rows.map(_rowToReviewItem).toList(growable: false);
  }

  Stream<List<IngestReviewItem>> watchPendingReviewItems({
    int limit = 200,
  }) async* {
    yield await listPendingReviewItems(limit: limit);
    await for (final _ in _changes.stream) {
      yield await listPendingReviewItems(limit: limit);
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

  @override
  Future<IngestLifecycleMutationResult> transition(
    IngestLifecycleTransition transition,
  ) async {
    if (transition.ownerUserId != _owner || _owner.isEmpty) {
      return const IngestLifecycleMutationResult(
        IngestLifecycleMutationOutcome.notFound,
      );
    }
    final nextRevision = transition.expectedRevision + 1;
    final changed = await _db.customUpdate(
      'UPDATE ingest_drafts SET status = ?1, recovery_kind = ?2, '
      'recovery_apply_state_json = ?3, revision = ?4, '
      'operation_token = ?5, invocation_started = ?6 '
      'WHERE draft_id = ?7 AND owner_user_id = ?8 AND status = ?9 '
      'AND revision = ?10 AND recovery_kind IS ?11 '
      'AND operation_token IS ?12 AND invocation_started = ?13',
      variables: [
        Variable.withString(transition.nextStatus.wire),
        _nullableString(transition.nextRecoveryKind),
        _nullableString(
          transition.nextRecoveryApplyState == null
              ? null
              : jsonEncode(transition.nextRecoveryApplyState!.toJson()),
        ),
        Variable.withInt(nextRevision),
        _nullableString(transition.nextOperationToken),
        Variable.withInt(transition.nextInvocationStarted ? 1 : 0),
        Variable.withString(transition.draftId),
        Variable.withString(_owner),
        Variable.withString(transition.expectedStatus.wire),
        Variable.withInt(transition.expectedRevision),
        _nullableString(transition.expectedRecoveryKind),
        _nullableString(transition.expectedOperationToken),
        Variable.withInt(transition.expectedInvocationStarted ? 1 : 0),
      ],
    );
    if (changed == 1) {
      _notify();
      return IngestLifecycleMutationResult(
        IngestLifecycleMutationOutcome.applied,
        revision: nextRevision,
      );
    }
    final visible = await _db
        .customSelect(
          'SELECT 1 FROM ingest_drafts WHERE draft_id = ?1 '
          'AND owner_user_id = ?2 LIMIT 1',
          variables: [
            Variable.withString(transition.draftId),
            Variable.withString(_owner),
          ],
        )
        .getSingleOrNull();
    return IngestLifecycleMutationResult(
      visible == null
          ? IngestLifecycleMutationOutcome.notFound
          : IngestLifecycleMutationOutcome.conflict,
    );
  }

  /// Drop confirmed/dismissed rows older than [cutoff] (housekeeping).
  Future<void> pruneSettledBefore(DateTime cutoff) async {
    await _db.customStatement(
      'DELETE FROM ingest_drafts '
      "WHERE owner_user_id = ?1 AND status IN ('confirmed', 'dismissed') "
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
      revision: row.read<int>('revision'),
    );
  }

  IngestReviewItem _rowToReviewItem(QueryRow row) {
    final draft = _rowToDraft(row);
    final recoveryKind = row.read<String?>('recovery_kind');
    if (draft.status == DraftStatus.confirming) {
      return IngestReviewItem(draft: draft, recoveryUnreadable: true);
    }
    if (recoveryKind == null) {
      return IngestReviewItem(draft: draft);
    }
    if (recoveryKind != 'finalize_applied') {
      return IngestReviewItem(draft: draft, recoveryUnreadable: true);
    }
    final raw = row.read<String?>('recovery_apply_state_json');
    if (raw == null) {
      return IngestReviewItem(draft: draft, recoveryUnreadable: true);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return IngestReviewItem(draft: draft, recoveryUnreadable: true);
      }
      final state = ProposalApplyState.fromJson(decoded);
      if (state.appliedEntityId == null) {
        return IngestReviewItem(draft: draft, recoveryUnreadable: true);
      }
      return IngestReviewItem(
        draft: draft,
        pendingFinalize: ConfirmedIngestItem(draft: draft, applyState: state),
      );
    } catch (_) {
      return IngestReviewItem(draft: draft, recoveryUnreadable: true);
    }
  }

  static Variable<String> _nullableString(String? value) =>
      value == null ? const Variable<String>(null) : Variable.withString(value);

  void dispose() {
    if (!_changes.isClosed) _changes.close();
  }
}
