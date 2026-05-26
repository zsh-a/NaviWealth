/// Wave 39 — Drift-backed "this entity was touched by AI" store.
///
/// Detail pages query [latestTouch] / [watchLatest] to decide whether
/// to render an [AiSourceMark] next to a value. The `ai_touched_entities`
/// table is keyed by `(owner_user_id, entity_type, entity_id)` — the
/// latest touch overwrites the previous one rather than appending, so
/// the table stays bounded (≤ N entities × M owners).
///
/// **Why a side table rather than a column on each entity?** Pollution
/// across `journal_entries / accounts / liabilities / assets` would
/// require four migrations, four serialisation passes, and a guarantee
/// that every write path threads the value. A side table keeps the
/// concern in one module — `ProposalApplier` writes here in one place
/// after `apply()` succeeds, and every detail page reads through the
/// same provider.
library;

import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/persistence/app_database.dart';

class AiTouchedEntity {
  const AiTouchedEntity({
    required this.entityType,
    required this.entityId,
    required this.touchedAt,
    this.kindLabel,
    this.traceId,
  });

  /// Type discriminator. Match `appliedTable` from `ProposalApplyState`
  /// (`journal_entries` / `accounts` / `assets` / etc.) — consumers
  /// pass the same string when reading.
  final String entityType;

  /// Entity id (e.g. `JournalEntry.id`).
  final String entityId;

  final DateTime touchedAt;

  /// Optional `ProposalKind.name` so tooltips can read "AI 提议的支出"
  /// vs "AI 提议的交易" rather than a generic message.
  final String? kindLabel;

  /// `AiTrace.requestId` of the turn that applied this proposal. Lets
  /// future surfaces deep-link from the source mark to the trace.
  final String? traceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'entity_type': entityType,
    'entity_id': entityId,
    'touched_at': touchedAt.toUtc().toIso8601String(),
    if (kindLabel != null) 'kind_label': kindLabel,
    if (traceId != null) 'trace_id': traceId,
  };
}

class DriftAiTouchedStore {
  DriftAiTouchedStore(this._db, {this.ownerUserId});

  final AppDatabase _db;
  final String? ownerUserId;

  String get _owner => ownerUserId ?? '';

  /// Wave 39 — manual change channel. Same pattern as
  /// [DriftUndoStack]: customStatement table → no built-in Drift
  /// change notification → we push a no-op signal after each mutation
  /// so [watchLatest] subscribers re-fetch.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _notifyChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() => _changes.close();

  /// Record (or overwrite) a touch. Called by `ProposalApplier` after
  /// `apply()` succeeds.
  Future<void> recordTouch(AiTouchedEntity touch) async {
    await _db.customInsert(
      'INSERT OR REPLACE INTO ai_touched_entities '
      '(owner_user_id, entity_type, entity_id, touched_at, kind_label, trace_id) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6)',
      variables: [
        Variable.withString(_owner),
        Variable.withString(touch.entityType),
        Variable.withString(touch.entityId),
        Variable.withString(touch.touchedAt.toUtc().toIso8601String()),
        if (touch.kindLabel != null)
          Variable.withString(touch.kindLabel!)
        else
          const Variable<String>(null),
        if (touch.traceId != null)
          Variable.withString(touch.traceId!)
        else
          const Variable<String>(null),
      ],
    );
    _notifyChange();
  }

  /// Latest touch for one entity, or `null` if not recorded.
  Future<AiTouchedEntity?> latestTouch(
    String entityType,
    String entityId,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT touched_at, kind_label, trace_id '
          'FROM ai_touched_entities '
          'WHERE owner_user_id = ?1 AND entity_type = ?2 AND entity_id = ?3 '
          'LIMIT 1',
          variables: [
            Variable.withString(_owner),
            Variable.withString(entityType),
            Variable.withString(entityId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    final ts = r.read<String>('touched_at');
    return AiTouchedEntity(
      entityType: entityType,
      entityId: entityId,
      touchedAt: DateTime.parse(ts).toUtc(),
      kindLabel: r.readNullable<String>('kind_label'),
      traceId: r.readNullable<String>('trace_id'),
    );
  }

  /// Watch a single entity's touch state. Emits an initial snapshot
  /// then re-emits after every [recordTouch] / [forget] mutation
  /// routed through this stack instance.
  Stream<AiTouchedEntity?> watchLatest(
    String entityType,
    String entityId,
  ) async* {
    yield await latestTouch(entityType, entityId);
    await for (final _ in _changes.stream) {
      yield await latestTouch(entityType, entityId);
    }
  }

  /// Drop the touch record. Used when a write is undone or an entity
  /// is otherwise reset — the mark shouldn't linger past its truth.
  Future<void> forget(String entityType, String entityId) async {
    await _db.customStatement(
      'DELETE FROM ai_touched_entities '
      'WHERE owner_user_id = ?1 AND entity_type = ?2 AND entity_id = ?3',
      [_owner, entityType, entityId],
    );
    _notifyChange();
  }
}
