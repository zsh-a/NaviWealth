import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/app_database.dart';
import 'domain_event.dart';

/// Writes append-only audit rows into `domain_event_log`.
///
/// The writer is intended to be called *inside* an existing Drift
/// transaction — repositories pair their row write and the audit row
/// in the same `_db.transaction(...)` block so a crash between the two
/// cannot leave one durable without the other.
///
/// FIR-125 strategy (a): the table is local-only. The writer therefore
/// neither enqueues a sync `Op` nor cares about the `op_outbox`. If
/// per-device audit history is later promoted to a synced ledger, the
/// callsites stay the same — only the writer's persistence backend
/// changes.
class EventLogWriter {
  EventLogWriter({required AppDatabase db, Uuid uuid = const Uuid()})
    : _db = db,
      _uuid = uuid;

  final AppDatabase _db;
  final Uuid _uuid;

  /// Records the creation of a new entity row.
  ///
  /// `after` should carry the field set the row was inserted with —
  /// callers usually pass the same `fields` map they hand to the
  /// outbox `Op`, with sync-metadata columns (`updated_at`, `hlc`, …)
  /// stripped so the audit trail stays focused on user-visible state.
  Future<void> recordCreated({
    required String entityTable,
    required String entityId,
    required MutationStamp stamp,
    required Map<String, Object?> after,
    String? reason,
  }) {
    return _insert(
      entityTable: entityTable,
      entityId: entityId,
      kind: DomainEventKind.created,
      stamp: stamp,
      before: null,
      after: after,
      reason: reason,
    );
  }

  /// Records a field-level update. `before` and `after` MUST share the
  /// same key set — the writer asserts this so a forgotten old/new value
  /// pair surfaces in tests instead of silently shipping a half-blank
  /// audit row.
  ///
  /// No-op when `after` is empty: an empty diff means the caller already
  /// short-circuited the write, so there is nothing to audit.
  Future<void> recordFieldChanged({
    required String entityTable,
    required String entityId,
    required MutationStamp stamp,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
    String? reason,
  }) async {
    if (after.isEmpty) return;
    assert(
      before.keys.toSet().containsAll(after.keys),
      'event_log: every changed field must have a before-value '
      '(missing: ${after.keys.toSet().difference(before.keys.toSet())})',
    );
    await _insert(
      entityTable: entityTable,
      entityId: entityId,
      kind: DomainEventKind.fieldChanged,
      stamp: stamp,
      before: before,
      after: after,
      reason: reason,
    );
  }

  /// Records a soft-delete (tombstone) of an entity. `before` may carry
  /// any user-visible state the caller wants preserved for the audit
  /// view; if `null`, the audit row simply marks the transition.
  Future<void> recordSoftDeleted({
    required String entityTable,
    required String entityId,
    required MutationStamp stamp,
    Map<String, Object?>? before,
    String? reason,
  }) {
    return _insert(
      entityTable: entityTable,
      entityId: entityId,
      kind: DomainEventKind.softDeleted,
      stamp: stamp,
      before: before,
      after: null,
      reason: reason,
    );
  }

  /// Records the restore of a previously soft-deleted entity.
  Future<void> recordRestored({
    required String entityTable,
    required String entityId,
    required MutationStamp stamp,
    Map<String, Object?>? after,
    String? reason,
  }) {
    return _insert(
      entityTable: entityTable,
      entityId: entityId,
      kind: DomainEventKind.restored,
      stamp: stamp,
      before: null,
      after: after,
      reason: reason,
    );
  }

  Future<void> _insert({
    required String entityTable,
    required String entityId,
    required DomainEventKind kind,
    required MutationStamp stamp,
    required Map<String, Object?>? before,
    required Map<String, Object?>? after,
    required String? reason,
  }) async {
    await _db.customStatement(
      'INSERT INTO domain_event_log '
      '(id, entity_table, entity_id, event_kind, actor_user_id, '
      ' actor_device_id, recorded_at, hlc, before_json, after_json, reason) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        entityTable,
        entityId,
        kind.wire,
        stamp.ownerUserId,
        stamp.deviceId,
        stamp.now.toUtc().toIso8601String(),
        stamp.hlc.toString(),
        encodeEventFields(before),
        encodeEventFields(after),
        reason,
      ],
    );
  }
}
