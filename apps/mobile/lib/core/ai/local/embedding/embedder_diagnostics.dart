/// Runtime diagnostics for the local embedder and Memory vector store.
///
/// Domain-neutral: this reads only the active [Embedder] provider and shared
/// Memory Runtime tables. Settings uses it to show whether the app is running
/// the stub or native model, and how many memories/vectors are indexed.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../persistence/app_database.dart';
import '../../../persistence/providers.dart';
import '../memory/providers.dart';
import 'embedder.dart';

enum EmbedderRuntimeKind { stub, native, unknown }

class EmbedderSourceStats {
  const EmbedderSourceStats({
    required this.source,
    required this.memories,
    required this.vectors,
  });

  final String source;
  final int memories;
  final int vectors;
}

class EmbedderDiagnostics {
  const EmbedderDiagnostics({
    required this.kind,
    required this.isReady,
    required this.fingerprint,
    required this.dimension,
    required this.memoryCount,
    required this.eventCount,
    required this.vectorCount,
    required this.currentVectorCount,
    required this.staleVectorCount,
    required this.sourceStats,
    this.error,
  });

  final EmbedderRuntimeKind kind;
  final bool isReady;
  final String fingerprint;
  final int dimension;
  final int memoryCount;
  final int eventCount;
  final int vectorCount;
  final int currentVectorCount;
  final int staleVectorCount;
  final List<EmbedderSourceStats> sourceStats;
  final String? error;

  bool get isStub => kind == EmbedderRuntimeKind.stub;
  bool get hasStaleVectors => staleVectorCount > 0;
}

final embedderDiagnosticsProvider = FutureProvider<EmbedderDiagnostics>((
  ref,
) async {
  final dbFuture = ref.watch(appDatabaseProvider.future);
  final embedderFuture = ref.watch(embedderProvider.future);
  final db = await dbFuture;

  final stats = await _readVectorStats(db);
  Embedder? embedder;
  String? error;
  try {
    embedder = await embedderFuture;
  } on Object catch (e) {
    error = '$e';
  }
  final fingerprint = embedder?.fingerprint ?? '';

  final currentVectors = fingerprint.isEmpty
      ? 0
      : await _countWhere(
          db,
          'SELECT COUNT(*) AS n FROM memory_embeddings WHERE fingerprint = ?',
          <Variable<Object>>[Variable.withString(fingerprint)],
        );
  final staleVectors = fingerprint.isEmpty
      ? stats.vectorCount
      : await _countWhere(
          db,
          'SELECT COUNT(*) AS n FROM memory_embeddings WHERE fingerprint != ?',
          <Variable<Object>>[Variable.withString(fingerprint)],
        );

  return EmbedderDiagnostics(
    kind: _kindOf(embedder),
    isReady: embedder != null && error == null,
    fingerprint: fingerprint,
    dimension: embedder?.dimension ?? 0,
    memoryCount: stats.memoryCount,
    eventCount: stats.eventCount,
    vectorCount: stats.vectorCount,
    currentVectorCount: currentVectors,
    staleVectorCount: staleVectors,
    sourceStats: stats.sourceStats,
    error: error,
  );
});

EmbedderRuntimeKind _kindOf(Embedder? embedder) {
  if (embedder == null) return EmbedderRuntimeKind.unknown;
  if (embedder is StubEmbedder) return EmbedderRuntimeKind.stub;
  return EmbedderRuntimeKind.native;
}

class _VectorStats {
  const _VectorStats({
    required this.memoryCount,
    required this.eventCount,
    required this.vectorCount,
    required this.sourceStats,
  });

  final int memoryCount;
  final int eventCount;
  final int vectorCount;
  final List<EmbedderSourceStats> sourceStats;
}

Future<_VectorStats> _readVectorStats(AppDatabase db) async {
  final memoryCount = await _countWhere(
    db,
    'SELECT COUNT(*) AS n FROM memories',
    const <Variable<Object>>[],
  );
  final eventCount = await _countWhere(
    db,
    'SELECT COUNT(*) AS n FROM events',
    const <Variable<Object>>[],
  );
  final vectorCount = await _countWhere(
    db,
    'SELECT COUNT(*) AS n FROM memory_embeddings',
    const <Variable<Object>>[],
  );
  final rows = await db.customSelect('''
SELECT COALESCE(m.source, '(none)') AS source,
       COUNT(*) AS memories,
       SUM(CASE WHEN e.memory_id IS NULL THEN 0 ELSE 1 END) AS vectors
FROM memories m
LEFT JOIN memory_embeddings e ON e.memory_id = m.id
GROUP BY COALESCE(m.source, '(none)')
ORDER BY memories DESC, source ASC
LIMIT 8
''').get();
  return _VectorStats(
    memoryCount: memoryCount,
    eventCount: eventCount,
    vectorCount: vectorCount,
    sourceStats: [
      for (final row in rows)
        EmbedderSourceStats(
          source: row.read<String>('source'),
          memories: row.read<int>('memories'),
          vectors: row.read<int>('vectors'),
        ),
    ],
  );
}

Future<int> _countWhere(
  AppDatabase db,
  String sql,
  List<Variable<Object>> args,
) async {
  final row = await db.customSelect(sql, variables: args).getSingle();
  return row.read<int>('n');
}
