/// Drift-backed [MemoryStore] for the Memory Runtime
/// (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// Storage layout (DDL in `core/persistence/local_only_tables.dart`):
///
/// - `memories`           — typed records, no vector
/// - `memory_embeddings`  — vectors keyed by memory_id, fingerprint-tagged
///
/// Why split: embedder swap (Stub → Rust EmbeddingGemma) only
/// invalidates embeddings, not records. We can drop vectors +
/// reindex without losing payload / lifecycle / entities.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../../../core/persistence/app_database.dart';
import '../../contracts/memory_record.dart';

/// One row pulled from a candidate scan. [semanticSim] is the cosine
/// vs the query vector when the caller asked for it; `null` when the
/// caller pulled non-semantically (e.g. "all rules in scope X").
class MemoryCandidate {
  const MemoryCandidate({required this.record, this.semanticSim});

  final MemoryRecord record;
  final double? semanticSim;
}

abstract class MemoryStore {
  Future<void> writeMemory(
    MemoryRecord record, {
    required List<double> vector,
    required String fingerprint,
  });

  /// Write a memory without an embedding (e.g. a hand-set semantic
  /// fact the user typed; or a procedural rule). Such rows are
  /// retrievable by kind/scope/entity but not by semantic similarity.
  Future<void> writeMemoryWithoutVector(MemoryRecord record);

  Future<MemoryRecord?> readMemory(String id);
  Future<void> deleteMemory(String id);

  /// Touch [lastAccessedAt] on the listed memories (no-op for unknown
  /// ids). Called by the runtime after a recall.
  Future<void> touchAccess(Iterable<String> ids, DateTime at);

  /// Pull candidate memories filtered by owner / kind / scope / source,
  /// optionally scored by cosine vs [queryVector]. The caller reranks
  /// + cuts.
  ///
  /// When [queryVector] is supplied, [fingerprint] must match the
  /// embedder that produced it; rows with other fingerprints are
  /// silently skipped (stale-vector defense).
  ///
  /// When [queryVector] is null, [fingerprint] is ignored and rows
  /// without embeddings still come back ([MemoryCandidate.semanticSim]
  /// is null).
  Future<List<MemoryCandidate>> queryMemories({
    required String ownerUserId,
    Set<MemoryKind>? kinds,
    String? scope,
    String? source,
    List<double>? queryVector,
    String? fingerprint,
    DateTime? validAt,
    int limit = 50,
  });

  /// Drop every embedding whose fingerprint is not [keepFingerprint].
  /// Memory rows themselves are untouched. Returns rows removed.
  Future<int> dropOtherFingerprints(String keepFingerprint);

  Future<int> countMemories();
}

class SqliteMemoryStore implements MemoryStore {
  SqliteMemoryStore({required AppDatabase db}) : _db = db;
  final AppDatabase _db;

  @override
  Future<void> writeMemory(
    MemoryRecord record, {
    required List<double> vector,
    required String fingerprint,
  }) async {
    await _db.transaction(() async {
      await _upsertMemoryRow(record);
      await _db.customStatement(
        'INSERT OR REPLACE INTO memory_embeddings ('
        '  memory_id, fingerprint, dimension, vector_bytes'
        ') VALUES (?, ?, ?, ?)',
        <Object?>[record.id, fingerprint, vector.length, packVector(vector)],
      );
    });
  }

  @override
  Future<void> writeMemoryWithoutVector(MemoryRecord record) async {
    await _upsertMemoryRow(record);
  }

  Future<void> _upsertMemoryRow(MemoryRecord r) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO memories ('
      '  id, kind, scope, owner_user_id, source, source_id, source_event_id,'
      '  title, summary, payload_json, entities_json, importance, confidence,'
      '  valid_from, valid_until, created_at, updated_at, last_accessed_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        r.id,
        r.kind.wire,
        r.scope,
        r.ownerUserId,
        r.source,
        r.sourceId,
        r.sourceEventId,
        r.title,
        r.summary,
        r.encodePayload(),
        r.encodeEntities(),
        r.importance,
        r.confidence,
        r.validFrom?.toUtc().millisecondsSinceEpoch,
        r.validUntil?.toUtc().millisecondsSinceEpoch,
        r.createdAt.toUtc().millisecondsSinceEpoch,
        r.updatedAt.toUtc().millisecondsSinceEpoch,
        r.lastAccessedAt?.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<MemoryRecord?> readMemory(String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM memories WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToMemory(row);
  }

  @override
  Future<void> deleteMemory(String id) async {
    // FK CASCADE drops the embedding row too.
    await _db.customStatement('DELETE FROM memories WHERE id = ?', <Object?>[
      id,
    ]);
  }

  @override
  Future<void> touchAccess(Iterable<String> ids, DateTime at) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final ms = at.toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final id in list) {
        await _db.customStatement(
          'UPDATE memories SET last_accessed_at = ? WHERE id = ?',
          <Object?>[ms, id],
        );
      }
    });
  }

  @override
  Future<List<MemoryCandidate>> queryMemories({
    required String ownerUserId,
    Set<MemoryKind>? kinds,
    String? scope,
    String? source,
    List<double>? queryVector,
    String? fingerprint,
    DateTime? validAt,
    int limit = 50,
  }) async {
    if (limit <= 0) return const <MemoryCandidate>[];

    final filters = <String>['m.owner_user_id = ?'];
    final vars = <Variable<Object>>[Variable.withString(ownerUserId)];

    if (kinds != null && kinds.isNotEmpty) {
      final placeholders = List<String>.filled(kinds.length, '?').join(', ');
      filters.add('m.kind IN ($placeholders)');
      for (final k in kinds) {
        vars.add(Variable.withString(k.wire));
      }
    }
    if (scope != null) {
      // '*' is the global scope — a record stored with scope='*' is
      // applicable to any scoped query, and a query for scope='*'
      // matches everything. Both directions handled here.
      if (scope == '*') {
        // No filter — match all scopes.
      } else {
        filters.add('(m.scope = ? OR m.scope = ?)');
        vars.add(Variable.withString(scope));
        vars.add(Variable.withString('*'));
      }
    }
    if (source != null) {
      filters.add('m.source = ?');
      vars.add(Variable.withString(source));
    }
    if (validAt != null) {
      final ms = validAt.toUtc().millisecondsSinceEpoch;
      filters.add('(m.valid_from IS NULL OR m.valid_from <= ?)');
      vars.add(Variable.withInt(ms));
      filters.add('(m.valid_until IS NULL OR m.valid_until >= ?)');
      vars.add(Variable.withInt(ms));
    }

    final wantsVector = queryVector != null && queryVector.isNotEmpty;
    // LEFT JOIN so memories without embeddings still come back when
    // wantsVector is false. When wantsVector is true we also filter by
    // fingerprint so stale vectors are skipped.
    const join = 'LEFT JOIN memory_embeddings e ON e.memory_id = m.id';
    if (wantsVector) {
      filters.add('e.fingerprint = ?');
      vars.add(Variable.withString(fingerprint ?? ''));
    }

    final sql =
        'SELECT m.*, e.dimension AS emb_dimension, '
        '       e.vector_bytes AS emb_vector_bytes, '
        '       e.fingerprint AS emb_fingerprint '
        'FROM memories m $join '
        'WHERE ${filters.join(' AND ')} '
        // Cap the raw pull so a huge memory table doesn't drag the
        // brute-force cosine. The caller's `limit` is final cut after
        // scoring.
        'LIMIT ${(limit * 5).clamp(50, 1000)}';

    final rows = await _db.customSelect(sql, variables: vars).get();
    final out = <MemoryCandidate>[];
    for (final row in rows) {
      final record = _rowToMemory(row);
      double? sim;
      if (wantsVector) {
        final bytes = row.read<Uint8List?>('emb_vector_bytes');
        final dim = row.read<int?>('emb_dimension');
        if (bytes != null && dim != null) {
          final vec = unpackVector(bytes, dim);
          sim = cosineSimilarity(queryVector, vec);
        }
      }
      out.add(MemoryCandidate(record: record, semanticSim: sim));
    }
    return out;
  }

  @override
  Future<int> dropOtherFingerprints(String keepFingerprint) async {
    await _db.customStatement(
      'DELETE FROM memory_embeddings WHERE fingerprint != ?',
      <Object?>[keepFingerprint],
    );
    final r = await _db.customSelect('SELECT changes() AS n').getSingle();
    return r.read<int>('n');
  }

  @override
  Future<int> countMemories() async {
    final r = await _db
        .customSelect('SELECT COUNT(*) AS n FROM memories')
        .getSingle();
    return r.read<int>('n');
  }
}

MemoryRecord _rowToMemory(QueryRow row) => MemoryRecord(
  id: row.read<String>('id'),
  kind: MemoryKindWire.parse(row.read<String>('kind')),
  scope: row.read<String>('scope'),
  ownerUserId: row.read<String>('owner_user_id'),
  source: row.read<String?>('source'),
  sourceId: row.read<String?>('source_id'),
  sourceEventId: row.read<String?>('source_event_id'),
  title: row.read<String>('title'),
  summary: row.read<String>('summary'),
  payload: MemoryRecord.decodePayload(row.read<String>('payload_json')),
  entities: MemoryRecord.decodeEntities(row.read<String>('entities_json')),
  importance: row.read<double>('importance'),
  confidence: row.read<double>('confidence'),
  validFrom: _dt(row.read<int?>('valid_from')),
  validUntil: _dt(row.read<int?>('valid_until')),
  lastAccessedAt: _dt(row.read<int?>('last_accessed_at')),
  createdAt: _dt(row.read<int>('created_at'))!,
  updatedAt: _dt(row.read<int>('updated_at'))!,
);

DateTime? _dt(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// Pack a vector as little-endian Float32. Public for tests + reused
/// by [EventStore] internals.
Uint8List packVector(List<double> v) {
  final bytes = ByteData(v.length * 4);
  for (var i = 0; i < v.length; i++) {
    bytes.setFloat32(i * 4, v[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

List<double> unpackVector(Uint8List bytes, int dimension) {
  final data = ByteData.sublistView(bytes);
  final out = List<double>.filled(dimension, 0);
  for (var i = 0; i < dimension; i++) {
    out[i] = data.getFloat32(i * 4, Endian.little);
  }
  return out;
}

/// Pure cosine similarity. Tolerates non-normalised inputs; returns 0
/// when either side has zero magnitude or shape mismatch. Public so
/// tests + other stores can share the math.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0;
  var sa = 0.0;
  var sb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    sa += a[i] * a[i];
    sb += b[i] * b[i];
  }
  if (sa == 0 || sb == 0) return 0;
  return dot / (math.sqrt(sa) * math.sqrt(sb));
}
