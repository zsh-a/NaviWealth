import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder_diagnostics.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../../../persistence/test_database.dart';

MemoryRecord _memory({required String id, required String source}) =>
    MemoryRecord(
      id: id,
      kind: MemoryKind.episodic,
      ownerUserId: 'u1',
      scope: '*',
      source: source,
      sourceId: id,
      title: id,
      summary: 'summary $id',
      payload: const {},
      entities: const {},
      importance: 0.5,
      confidence: 0.9,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );

void main() {
  test('reports active embedder and vector store stats', () async {
    final db = makeTestDatabase();
    final embedder = StubEmbedder(dimension: 8);
    final store = SqliteMemoryStore(db: db);
    await store.writeMemory(
      _memory(id: 'current', source: 'know:notes'),
      vector: await embedder.embed('current'),
      fingerprint: embedder.fingerprint,
    );
    await store.writeMemory(
      _memory(id: 'stale', source: 'fin:journal'),
      vector: List<double>.filled(8, 0),
      fingerprint: 'old-fingerprint',
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        embedderProvider.overrideWith((ref) async => embedder),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    final diagnostics = await container.read(
      embedderDiagnosticsProvider.future,
    );

    expect(diagnostics.kind, EmbedderRuntimeKind.stub);
    expect(diagnostics.isReady, isTrue);
    expect(diagnostics.fingerprint, 'stub-v1-d8');
    expect(diagnostics.dimension, 8);
    expect(diagnostics.memoryCount, 2);
    expect(diagnostics.vectorCount, 2);
    expect(diagnostics.currentVectorCount, 1);
    expect(diagnostics.staleVectorCount, 1);
    expect(diagnostics.eventCount, 0);
    expect(
      diagnostics.sourceStats.map((s) => (s.source, s.memories, s.vectors)),
      containsAll(<(String, int, int)>[
        ('fin:journal', 1, 1),
        ('know:notes', 1, 1),
      ]),
    );
  });
}
