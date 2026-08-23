/// Drift-backed [EventStore] for the cross-domain event log
/// (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// `events` is append-mostly. Writers idempotently upsert by id so
/// indexers can replay the source stream without duplicating rows.
/// The store exposes a few well-shaped reads:
///
/// - [recentEvents] — owner+time-window slice, optionally filtered by
///   source family / kind / domain / entities. Drives recent context events.
/// - [readEvent] — point lookup by id (used to follow
///   [MemoryRecord.sourceEventId]).
library;

import 'package:drift/drift.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../auth/domain_scope.dart';
import '../../contracts/event_record.dart';
import '../../contracts/source_identity.dart';

abstract class EventStore {
  Future<void> writeEvent(EventRecord event);
  Future<EventRecord?> readEvent(String id);
  Future<List<EventRecord>> recentEvents({
    required String ownerUserId,
    String? source,
    Set<String>? sourcePrefixes,
    Set<DomainScope>? domains,
    Set<EventKind>? kindFilter,
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
      '  id, domain, kind, occurred_at, observed_at, source_family,'
      '  source_row_id, source_fingerprint, owner_user_id, title, summary,'
      '  facts_json, entities_json, importance, confidence'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        e.id,
        e.domain?.wire,
        e.kind.wire,
        e.occurredAt.toUtc().millisecondsSinceEpoch,
        e.observedAt.toUtc().millisecondsSinceEpoch,
        e.sourceIdentity.rowFamily,
        e.sourceIdentity.rowId,
        e.sourceIdentity.fingerprint,
        e.ownerUserId,
        e.title,
        e.summary,
        e.encodeFacts(),
        e.encodeEntities(),
        e.importance,
        e.confidence,
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
    Set<String>? sourcePrefixes,
    Set<DomainScope>? domains,
    Set<EventKind>? kindFilter,
    Set<String>? entityFilter,
    DateTime? since,
    int limit = 50,
  }) async {
    if (limit <= 0) return const <EventRecord>[];
    final normalizedSourcePrefixes = sourcePrefixes
        ?.map((prefix) => prefix.trim())
        .where((prefix) => prefix.isNotEmpty)
        .toSet();
    if (normalizedSourcePrefixes != null && normalizedSourcePrefixes.isEmpty) {
      return const <EventRecord>[];
    }
    if (domains != null && domains.isEmpty) {
      return const <EventRecord>[];
    }
    final filters = <String>['owner_user_id = ?'];
    final vars = <Variable<Object>>[Variable.withString(ownerUserId)];

    if (source != null) {
      filters.add('source_family = ?');
      vars.add(Variable.withString(source));
    }
    if (normalizedSourcePrefixes != null) {
      final prefixFilters = <String>[];
      for (final prefix in normalizedSourcePrefixes) {
        prefixFilters.add("source_family LIKE ? ESCAPE '\\'");
        vars.add(Variable.withString('${_escapeLike(prefix)}%'));
      }
      filters.add('(${prefixFilters.join(' OR ')})');
    }
    if (domains != null) {
      final placeholders = List<String>.filled(domains.length, '?').join(', ');
      filters.add('domain IN ($placeholders)');
      for (final domain in domains) {
        vars.add(Variable.withString(domain.wire));
      }
    }
    if (kindFilter != null && kindFilter.isNotEmpty) {
      final placeholders = List<String>.filled(
        kindFilter.length,
        '?',
      ).join(', ');
      filters.add('kind IN ($placeholders)');
      for (final kind in kindFilter) {
        vars.add(Variable.withString(kind.wire));
      }
    }
    if (since != null) {
      filters.add('occurred_at >= ?');
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
          'ORDER BY occurred_at DESC LIMIT $pullLimit',
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

String _escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

EventRecord _rowToEvent(QueryRow row) => EventRecord(
  id: row.read<String>('id'),
  domain: switch (row.readNullable<String>('domain')) {
    final String wire => DomainScope.tryParse(wire),
    null => null,
  },
  kind: EventKind.fromWire(row.read<String>('kind')),
  occurredAt: DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('occurred_at'),
    isUtc: true,
  ),
  observedAt: DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('observed_at'),
    isUtc: true,
  ),
  sourceIdentity: _sourceIdentityFromRow(row),
  ownerUserId: row.read<String>('owner_user_id'),
  title: row.read<String?>('title'),
  summary: row.read<String>('summary'),
  facts: EventRecord.decodeFacts(row.read<String>('facts_json')),
  entities: EventRecord.decodeEntities(row.read<String>('entities_json')),
  importance: row.read<double>('importance'),
  confidence: row.read<double>('confidence'),
);

SourceIdentity _sourceIdentityFromRow(QueryRow row) {
  final domainWire = row.readNullable<String>('domain');
  return SourceIdentity(
    domain: domainWire == null ? null : DomainScope.tryParse(domainWire),
    rowFamily: row.read<String>('source_family'),
    rowId: row.read<String>('source_row_id'),
    fingerprint: row.read<String>('source_fingerprint'),
  );
}
