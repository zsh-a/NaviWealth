/// Drift-backed [EventStore] for the cross-domain event log
/// (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// `events` is append-mostly. Writers idempotently upsert by id so
/// indexers can replay the source stream without duplicating rows.
/// The store exposes a few well-shaped reads:
///
/// - [recentEvents] — owner+time-window slice, optionally filtered by
///   source / type / entities. Drives [ContextPack.recentEvents].
/// - [readEvent] — point lookup by id (used to follow
///   [MemoryRecord.sourceEventId]).
library;

import 'package:drift/drift.dart';

import '../../../../data/db/app_database.dart';
import '../../contracts/event_record.dart';

abstract class EventStore {
  Future<void> writeEvent(EventRecord event);
  Future<EventRecord?> readEvent(String id);
  Future<List<EventRecord>> recentEvents({
    required String ownerUserId,
    String? source,
    Set<String>? typeFilter,
    Set<String>? entityFilter,
    DateTime? since,
    int limit = 50,
  });
  Future<int> countEvents();
}

class SqliteEventStore implements EventStore {
  SqliteEventStore({required AppDatabase db}) : _db = db;
  final AppDatabase _db;

  @override
  Future<void> writeEvent(EventRecord e) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO events ('
      '  id, type, timestamp, source, owner_user_id, title, summary,'
      '  payload_json, entities_json, importance'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        e.id,
        e.type,
        e.timestamp.toUtc().millisecondsSinceEpoch,
        e.source,
        e.ownerUserId,
        e.title,
        e.summary,
        e.encodePayload(),
        e.encodeEntities(),
        e.importance,
      ],
    );
  }

  @override
  Future<EventRecord?> readEvent(String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM events WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToEvent(row);
  }

  @override
  Future<List<EventRecord>> recentEvents({
    required String ownerUserId,
    String? source,
    Set<String>? typeFilter,
    Set<String>? entityFilter,
    DateTime? since,
    int limit = 50,
  }) async {
    if (limit <= 0) return const <EventRecord>[];
    final filters = <String>['owner_user_id = ?'];
    final vars = <Variable<Object>>[Variable.withString(ownerUserId)];

    if (source != null) {
      filters.add('source = ?');
      vars.add(Variable.withString(source));
    }
    if (typeFilter != null && typeFilter.isNotEmpty) {
      final placeholders = List<String>.filled(
        typeFilter.length,
        '?',
      ).join(', ');
      filters.add('type IN ($placeholders)');
      for (final t in typeFilter) {
        vars.add(Variable.withString(t));
      }
    }
    if (since != null) {
      filters.add('timestamp >= ?');
      vars.add(Variable.withInt(since.toUtc().millisecondsSinceEpoch));
    }

    // Pull a wider window than `limit` when we'll filter by entity in
    // Dart (entity match is on JSON, not indexed). 5× cushion balances
    // result density vs scan cost.
    final pullLimit = entityFilter != null && entityFilter.isNotEmpty
        ? (limit * 5).clamp(50, 500)
        : limit;

    final rows = await _db
        .customSelect(
          'SELECT * FROM events WHERE ${filters.join(' AND ')} '
          'ORDER BY timestamp DESC LIMIT $pullLimit',
          variables: vars,
        )
        .get();

    final out = <EventRecord>[];
    for (final row in rows) {
      final ev = _rowToEvent(row);
      if (entityFilter != null && entityFilter.isNotEmpty) {
        final overlap = ev.entities.intersection(entityFilter);
        if (overlap.isEmpty) continue;
      }
      out.add(ev);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<int> countEvents() async {
    final r = await _db
        .customSelect('SELECT COUNT(*) AS n FROM events')
        .getSingle();
    return r.read<int>('n');
  }
}

EventRecord _rowToEvent(QueryRow row) => EventRecord(
  id: row.read<String>('id'),
  type: row.read<String>('type'),
  timestamp: DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('timestamp'),
    isUtc: true,
  ),
  source: row.read<String>('source'),
  ownerUserId: row.read<String>('owner_user_id'),
  title: row.read<String?>('title'),
  summary: row.read<String>('summary'),
  payload: EventRecord.decodePayload(row.read<String>('payload_json')),
  entities: EventRecord.decodeEntities(row.read<String>('entities_json')),
  importance: row.read<double>('importance'),
);
