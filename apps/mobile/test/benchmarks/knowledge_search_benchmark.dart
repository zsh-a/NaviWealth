// Manual benchmark, excluded from the default *_test.dart suite:
// rtk flutter test test/benchmarks/knowledge_search_benchmark.dart --reporter expanded
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_search_service.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../core/persistence/test_database.dart';

const _owner = 'knowledge-benchmark';

void main() {
  for (final count in [1000, 5000, 10000]) {
    test('canonical search over $count Notes', () async {
      final database = makeTestDatabase();
      addTearDown(database.close);
      final repository = KnowledgeRepository(
        db: database,
        outbox: const NoopOutboxStore(),
      );
      final body = List.filled(
        16,
        'Evidence from a reversible trial.\nKeep the source and compare actual outcomes.\n',
      ).join();
      await repository.transaction(() async {
        for (var i = 0; i < count; i++) {
          final now = DateTime.utc(2026, 8, 30).add(Duration(seconds: i));
          await repository.upsertNote(
            KnowledgeNote(
              id: 'note-$i',
              title: 'Trial $i',
              bodyMd: body,
              tags: i % 50 == 0 ? const ['focus'] : const ['other'],
              createdAt: now,
              sync: SyncMeta(
                ownerUserId: _owner,
                updatedAt: now,
                updatedByDevice: 'benchmark',
                hlc: Hlc(
                  wallMillis: now.millisecondsSinceEpoch,
                  counter: 0,
                  nodeId: 'benchmark',
                ),
              ),
            ),
          );
        }
      });
      final service = KnowledgeSearchService(
        repository: repository,
        memoryRuntime: MemoryRuntime(
          embedder: _UnavailableEmbedder(),
          memoryStore: SqliteMemoryStore(db: database),
          eventStore: SqliteEventStore(db: database),
        ),
      );
      for (final tagged in [false, true]) {
        Future<List<KnowledgeSearchHit>> search() => service.searchNotes(
          ownerUserId: _owner,
          query: 'evidence trial',
          tags: tagged ? const {'focus'} : const {},
          limit: 50,
        );
        await search(); // Warm Drift and Dart before timing.
        final samples = <double>[];
        for (var i = 0; i < 5; i++) {
          final watch = Stopwatch()..start();
          final hits = await search();
          watch.stop();
          expect(hits, hasLength(tagged ? (count ~/ 50).clamp(0, 50) : 50));
          if (tagged) {
            expect(
              hits.every((hit) => hit.document.note!.tags.contains('focus')),
              isTrue,
            );
          }
          samples.add(watch.elapsedMicroseconds / 1000);
        }
        samples.sort();
        // ignore: avoid_print -- This is an explicitly invoked benchmark.
        print(
          'knowledge_search notes=$count tagged=$tagged p50_ms=${samples[2].toStringAsFixed(1)} p95_ms=${samples[4].toStringAsFixed(1)}',
        );
      }
    });
  }
}

final class _UnavailableEmbedder implements Embedder {
  @override
  int get dimension => 32;
  @override
  String get fingerprint => 'benchmark-unavailable';
  @override
  Future<List<double>> embed(String text) async =>
      throw StateError('Canonical lexical benchmark');
}
