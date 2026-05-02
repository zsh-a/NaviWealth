import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import '../domain/hlc.dart';
import 'domain_event.dart';

/// Read API over `domain_event_log`. Powers the per-entity "change
/// history" detail-page surface and any dev/maintenance tooling that
/// needs to inspect or sweep the ledger.
///
/// Reads are deliberately scoped: every query takes an `entityTable`
/// + `entityId`, or a recorded-at window. The table has no compound
/// query patterns beyond those, so we don't expose a generic
/// query-builder.
class EventLogReader {
  EventLogReader(this._db);

  final AppDatabase _db;

  /// One-shot read of every event for a given entity, oldest first.
  /// Ordering uses the canonical lex-sortable HLC column so causality
  /// holds even across counter resets within a single millisecond.
  Future<List<DomainEvent>> listByEntity({
    required String entityTable,
    required String entityId,
    int? limit,
  }) async {
    final args = <Variable<Object>>[
      Variable.withString(entityTable),
      Variable.withString(entityId),
    ];
    final limitClause = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(Variable.withInt(limit));

    final rows = await _db
        .customSelect(
          'SELECT id, entity_table, entity_id, event_kind, actor_user_id, '
          '       actor_device_id, recorded_at, hlc, before_json, after_json, '
          '       reason '
          'FROM domain_event_log '
          'WHERE entity_table = ? AND entity_id = ? '
          'ORDER BY hlc ASC$limitClause',
          variables: args,
        )
        .get();
    return rows.map(_rowToEvent).toList(growable: false);
  }

  /// Live stream of [listByEntity] — the detail page subscribes to this
  /// so a follow-up edit immediately appears in the timeline without a
  /// pull-to-refresh.
  Stream<List<DomainEvent>> watchByEntity({
    required String entityTable,
    required String entityId,
    int? limit,
  }) {
    final args = <Variable<Object>>[
      Variable.withString(entityTable),
      Variable.withString(entityId),
    ];
    final limitClause = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(Variable.withInt(limit));

    return _db
        .customSelect(
          'SELECT id, entity_table, entity_id, event_kind, actor_user_id, '
          '       actor_device_id, recorded_at, hlc, before_json, after_json, '
          '       reason '
          'FROM domain_event_log '
          'WHERE entity_table = ? AND entity_id = ? '
          'ORDER BY hlc ASC$limitClause',
          variables: args,
          readsFrom: {_db.assets, _db.accounts, _db.transactions},
        )
        .watch()
        .map((rows) => rows.map(_rowToEvent).toList(growable: false));
  }

  /// Count of events for an entity. Cheap; the entity index covers the
  /// predicate and SQLite's COUNT(*) over the index avoids a row scan.
  Future<int> countByEntity({
    required String entityTable,
    required String entityId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM domain_event_log '
          'WHERE entity_table = ? AND entity_id = ?',
          variables: [
            Variable.withString(entityTable),
            Variable.withString(entityId),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Local-maintenance entry point: drop every event for one entity.
  ///
  /// Deliberately not exposed in the regular UI — the audit log is
  /// supposed to be append-only. This exists for the "I deleted the
  /// account by mistake and want a clean reset" / debug story, and
  /// returns the number of rows removed so the caller can confirm.
  Future<int> deleteByEntity({
    required String entityTable,
    required String entityId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM domain_event_log '
          'WHERE entity_table = ? AND entity_id = ?',
          variables: [
            Variable.withString(entityTable),
            Variable.withString(entityId),
          ],
        )
        .getSingle();
    final count = row.read<int>('c');
    if (count == 0) return 0;
    await _db.customStatement(
      'DELETE FROM domain_event_log '
      'WHERE entity_table = ? AND entity_id = ?',
      [entityTable, entityId],
    );
    return count;
  }

  DomainEvent _rowToEvent(QueryRow row) {
    return DomainEvent(
      id: row.read<String>('id'),
      entityTable: row.read<String>('entity_table'),
      entityId: row.read<String>('entity_id'),
      kind: DomainEventKind.fromWire(row.read<String>('event_kind')),
      actorUserId: row.read<String>('actor_user_id'),
      actorDeviceId: row.read<String>('actor_device_id'),
      recordedAt: DateTime.parse(row.read<String>('recorded_at')),
      hlc: Hlc.parse(row.read<String>('hlc')),
      before: decodeEventFields(row.read<String?>('before_json')),
      after: decodeEventFields(row.read<String?>('after_json')),
      reason: row.read<String?>('reason'),
    );
  }
}
