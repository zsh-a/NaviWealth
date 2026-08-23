import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

HealthMetric _metric({
  required String id,
  required HealthMetricKind kind,
  required double value,
  required DateTime capturedAt,
  String unit = 's',
  String? payloadJson,
  String? sourceDevice,
}) => HealthMetric(
  id: id,
  capturedAt: capturedAt,
  kind: kind,
  value: value,
  unit: unit,
  payloadJson: payloadJson,
  sourceDevice: sourceDevice,
  sync: SyncMeta(
    ownerUserId: 'u1',
    updatedAt: capturedAt,
    updatedByDevice: 'dev',
    hlc: Hlc(
      wallMillis: capturedAt.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'dev',
    ),
    deletedAt: null,
  ),
);

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

void main() {
  final now = DateTime.utc(2026, 5, 27, 12);

  group('HealthMetricMemoryIndexer.reindex — event emission', () {
    test('one event per metric, regardless of kind', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'sleep-1',
          kind: HealthMetricKind.sleepSession,
          value: 25200, // 7h — not notable
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
        _metric(
          id: 'hrv-1',
          kind: HealthMetricKind.hrvDaily,
          value: 50,
          unit: 'ms',
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
        _metric(
          id: 'steps-1',
          kind: HealthMetricKind.stepsDaily,
          value: 9000,
          unit: 'count',
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');

      expect(out.events, 3);
      expect(
        out.memories,
        0,
        reason: 'normal sleep + plain HRV + plain steps → no episodic',
      );

      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      expect(events, hasLength(3));
      expect(events.map((event) => event.kind.name).toSet(), {
        kEventSleepSessionEnded,
        kEventHrvRecorded,
        kEventStepsRecorded,
      });
    });

    test('unknown kind is skipped silently', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'mystery',
          kind: HealthMetricKind.unknown,
          value: 1,
          unit: 'foo',
          capturedAt: now,
        ),
      ], ownerUserId: 'u1');
      expect(out.events, 0);
      expect(out.memories, 0);
    });

    test('every kind gets a distinct event type', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final knownKinds = <HealthMetricKind>[
        HealthMetricKind.sleepSession,
        HealthMetricKind.hrvDaily,
        HealthMetricKind.stepsDaily,
        HealthMetricKind.rhrDaily,
        HealthMetricKind.activeEnergyDaily,
        HealthMetricKind.weight,
        HealthMetricKind.bodyFat,
        HealthMetricKind.workoutSession,
        HealthMetricKind.vo2Max,
        HealthMetricKind.distanceWalkingRunningDaily,
        HealthMetricKind.heartRateDaily,
        HealthMetricKind.totalEnergyDaily,
        HealthMetricKind.floorsClimbedDaily,
        HealthMetricKind.respiratoryRateDaily,
      ];
      final metrics = [
        for (var i = 0; i < knownKinds.length; i++)
          _metric(
            id: 'k-$i',
            kind: knownKinds[i],
            value: knownKinds[i] == HealthMetricKind.sleepSession ? 25200 : 50,
            unit: knownKinds[i].defaultUnit,
            capturedAt: now.subtract(Duration(days: i + 1)),
          ),
      ];
      final out = await indexer.reindex(rt, metrics, ownerUserId: 'u1');
      expect(out.events, knownKinds.length);

      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      // Every event type unique
      expect(
        events.map((event) => event.kind.name).toSet().length,
        knownKinds.length,
      );
    });
  });

  group('HealthMetricMemoryIndexer.reindex — workout / vo2max events', () {
    test('workout row emits workout_completed event, no episodic', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'workout-1',
          kind: HealthMetricKind.workoutSession,
          value: 45 * 60.0,
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');
      expect(out.events, 1);
      expect(out.memories, 0);
      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      expect(events.single.kind.name, kEventWorkoutCompleted);
    });

    test('vo2 max row emits vo2_max_recorded event, no episodic', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'vo2-1',
          kind: HealthMetricKind.vo2Max,
          value: 42.5,
          unit: 'ml_kg_min',
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');
      expect(out.events, 1);
      expect(out.memories, 0);
      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      expect(events.single.kind.name, kEventVo2MaxRecorded);
    });
  });

  group('HealthMetricMemoryIndexer.reindex — episodic memory emission', () {
    test(
      'short sleep (< 5h) → episodic memory with short_sleep entity',
      () async {
        final rt = _runtime();
        final indexer = HealthMetricMemoryIndexer(clock: () => now);
        final out = await indexer.reindex(rt, [
          _metric(
            id: 'short-1',
            kind: HealthMetricKind.sleepSession,
            value: 4.5 * 3600.0, // 4.5h
            capturedAt: now.subtract(const Duration(days: 1)),
          ),
        ], ownerUserId: 'u1');
        expect(out.events, 1);
        expect(out.memories, 1);

        // Recall by entity
        final hits = await rt.recall(
          queryText: '',
          ownerUserId: 'u1',
          entityFilter: const {'short_sleep'},
          topK: 5,
        );
        expect(hits, hasLength(1));
        expect(hits.single.record.kind, MemoryKind.episodic);
        expect(hits.single.record.scope, 'health');
      },
    );

    test('long sleep (> 9h) → episodic with long_sleep entity', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'long-1',
          kind: HealthMetricKind.sleepSession,
          value: 10 * 3600.0, // 10h
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');
      expect(out.memories, 1);
      final hits = await rt.recall(
        queryText: '',
        ownerUserId: 'u1',
        entityFilter: const {'long_sleep'},
        topK: 5,
      );
      expect(hits, hasLength(1));
    });

    test('normal sleep (7h) → event only, no episodic', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'normal-1',
          kind: HealthMetricKind.sleepSession,
          value: 7 * 3600.0,
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');
      expect(out.events, 1);
      expect(out.memories, 0);
    });

    test(
      'sleep with payloadJson note → episodic + reasoning carries note',
      () async {
        final rt = _runtime();
        final indexer = HealthMetricMemoryIndexer(clock: () => now);
        const note = '{"reason":"travel jet lag"}';
        final out = await indexer.reindex(rt, [
          _metric(
            id: 'noted-1',
            kind: HealthMetricKind.sleepSession,
            value: 7 * 3600.0, // duration alone wouldn't trigger
            payloadJson: note,
            capturedAt: now.subtract(const Duration(days: 1)),
          ),
        ], ownerUserId: 'u1');
        expect(out.memories, 1);

        final hits = await rt.recall(
          queryText: '',
          ownerUserId: 'u1',
          entityFilter: const {'noted_sleep'},
          topK: 5,
        );
        expect(hits, hasLength(1));
        final payload = hits.single.record.payload;
        expect(payload['reasoning'], note);
      },
    );

    test('HRV / steps / RHR rows never produce episodic memories', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final out = await indexer.reindex(rt, [
        _metric(
          id: 'hrv-extreme',
          kind: HealthMetricKind.hrvDaily,
          value: 200, // unusual but indexer doesn't reason about HRV
          unit: 'ms',
          capturedAt: now,
        ),
        _metric(
          id: 'steps-zero',
          kind: HealthMetricKind.stepsDaily,
          value: 0,
          unit: 'count',
          capturedAt: now,
        ),
      ], ownerUserId: 'u1');
      expect(out.memories, 0);
    });
  });

  group('HealthMetricMemoryIndexer.reindex — trend memory extraction', () {
    test(
      'falling HRV writes semantic trend and procedural recovery rule',
      () async {
        final rt = _runtime();
        final indexer = HealthMetricMemoryIndexer(clock: () => now);
        final input = <HealthMetric>[
          _metric(
            id: 'hrv-1',
            kind: HealthMetricKind.hrvDaily,
            value: 72,
            unit: 'ms',
            capturedAt: now.subtract(const Duration(days: 4)),
          ),
          _metric(
            id: 'hrv-2',
            kind: HealthMetricKind.hrvDaily,
            value: 68,
            unit: 'ms',
            capturedAt: now.subtract(const Duration(days: 3)),
          ),
          _metric(
            id: 'hrv-3',
            kind: HealthMetricKind.hrvDaily,
            value: 59,
            unit: 'ms',
            capturedAt: now.subtract(const Duration(days: 2)),
          ),
          _metric(
            id: 'hrv-4',
            kind: HealthMetricKind.hrvDaily,
            value: 55,
            unit: 'ms',
            capturedAt: now.subtract(const Duration(days: 1)),
          ),
        ];

        final out = await indexer.reindex(rt, input, ownerUserId: 'u1');

        expect(out.events, 4);
        expect(out.memories, 2);

        final semantic = await rt.recall(
          queryText: '',
          ownerUserId: 'u1',
          kinds: const {MemoryKind.semantic},
          source: kHealthSource,
          entityFilter: const {'health_trend'},
          topK: 5,
        );
        expect(semantic, hasLength(1));
        expect(semantic.single.record.id, contains('semantic:trend:hrv_daily'));
        expect(semantic.single.record.payload['trend'], 'decreasing');
        expect(semantic.single.record.payload['sample_count'], 4);
        expect(semantic.single.record.entities, contains('recovery_risk'));

        final procedural = await rt.recall(
          queryText: '',
          ownerUserId: 'u1',
          kinds: const {MemoryKind.procedural},
          source: kHealthSource,
          entityFilter: const {'health_rule'},
          topK: 5,
        );
        expect(procedural, hasLength(1));
        expect(procedural.single.record.payload['rule'], contains('HRV'));
        expect(procedural.single.record.entities, contains('workout_planning'));
      },
    );

    test('stable steps write semantic trend without procedural rule', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);

      final out = await indexer.reindex(rt, [
        _metric(
          id: 'steps-1',
          kind: HealthMetricKind.stepsDaily,
          value: 8000,
          unit: 'count',
          capturedAt: now.subtract(const Duration(days: 4)),
        ),
        _metric(
          id: 'steps-2',
          kind: HealthMetricKind.stepsDaily,
          value: 8200,
          unit: 'count',
          capturedAt: now.subtract(const Duration(days: 3)),
        ),
        _metric(
          id: 'steps-3',
          kind: HealthMetricKind.stepsDaily,
          value: 7900,
          unit: 'count',
          capturedAt: now.subtract(const Duration(days: 2)),
        ),
        _metric(
          id: 'steps-4',
          kind: HealthMetricKind.stepsDaily,
          value: 8100,
          unit: 'count',
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ], ownerUserId: 'u1');

      expect(out.events, 4);
      expect(out.memories, 1);

      final semantic = await rt.recall(
        queryText: '',
        ownerUserId: 'u1',
        kinds: const {MemoryKind.semantic},
        source: kHealthSource,
        entityFilter: const {'health_trend'},
        topK: 5,
      );
      expect(semantic, hasLength(1));
      expect(semantic.single.record.payload['trend'], 'stable');
      expect(semantic.single.record.entities, isNot(contains('recovery_risk')));

      final procedural = await rt.recall(
        queryText: '',
        ownerUserId: 'u1',
        kinds: const {MemoryKind.procedural},
        source: kHealthSource,
        topK: 5,
      );
      expect(procedural, isEmpty);
    });

    test('trend memory ids are stable across repeated reindex', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final input = [
        for (var i = 0; i < 4; i++)
          _metric(
            id: 'rhr-$i',
            kind: HealthMetricKind.rhrDaily,
            value: 58 + i * 3,
            unit: 'bpm',
            capturedAt: now.subtract(Duration(days: 4 - i)),
          ),
      ];

      final first = await indexer.reindex(rt, input, ownerUserId: 'u1');
      final second = await indexer.reindex(rt, input, ownerUserId: 'u1');

      expect(first.memories, 2);
      expect(second.memories, 2);
      expect(await rt.memoryCount, 2);
    });
  });

  group('HealthMetricMemoryIndexer.reindex — idempotency', () {
    test('repeated reindex with same input doesn\'t duplicate rows', () async {
      final rt = _runtime();
      final indexer = HealthMetricMemoryIndexer(clock: () => now);
      final input = [
        _metric(
          id: 'sleep-keep',
          kind: HealthMetricKind.sleepSession,
          value: 4 * 3600.0, // short → memory
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
        _metric(
          id: 'hrv-keep',
          kind: HealthMetricKind.hrvDaily,
          value: 50,
          unit: 'ms',
          capturedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      final first = await indexer.reindex(rt, input, ownerUserId: 'u1');
      final second = await indexer.reindex(rt, input, ownerUserId: 'u1');
      // Counts reflect work done; rows are upserts (same ids), so the
      // store doesn't grow.
      expect(first.events + second.events, 4);
      expect(first.memories + second.memories, 2);

      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      // Repo de-dupes by id ⇒ only 2 distinct events survive.
      expect(events, hasLength(2));

      final hits = await rt.recall(
        queryText: '',
        ownerUserId: 'u1',
        entityFilter: const {'short_sleep'},
        topK: 5,
      );
      expect(hits, hasLength(1));
    });
  });
}
