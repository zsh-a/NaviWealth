import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _userA = 'u-a';
const _userB = 'u-b';
const _device = 'dev-test';

HealthMetric _metric({
  required String id,
  required HealthMetricKind kind,
  required double value,
  required DateTime capturedAt,
  String unit = 's',
  String? payloadJson,
  String? sourceDevice,
  String ownerUserId = _userA,
  int wallMillis = 1_700_000_000_000,
  int counter = 0,
  DateTime? deletedAt,
}) => HealthMetric(
  id: id,
  capturedAt: capturedAt,
  kind: kind,
  value: value,
  unit: unit,
  payloadJson: payloadJson,
  sourceDevice: sourceDevice,
  sync: SyncMeta(
    ownerUserId: ownerUserId,
    updatedAt: capturedAt,
    updatedByDevice: _device,
    hlc: Hlc(wallMillis: wallMillis, counter: counter, nodeId: _device),
    deletedAt: deletedAt,
  ),
);

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late HealthMetricRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = HealthMetricRepository(db: db, outbox: outbox);
  });

  tearDown(() => db.close());

  test('upsert persists a metric and enqueues a sync dirty pointer', () async {
    final metric = _metric(
      id: 'm-1',
      kind: HealthMetricKind.sleepSession,
      value: 28800, // 8h
      capturedAt: DateTime.utc(2026, 5, 25, 23),
    );
    await repo.upsert(metric);

    final fetched = await repo.findById('m-1');
    expect(fetched, isNotNull);
    expect(fetched!.kind, HealthMetricKind.sleepSession);
    expect(fetched.value, 28800);
    expect(fetched.unit, 's');
    expect(fetched.sync.ownerUserId, _userA);
    expect(fetched.sync.deletedAt, isNull);

    expect(await outbox.depth(), 1);
  });

  test('upsert with same id replaces the row in-place', () async {
    await repo.upsert(_metric(
      id: 'm-1',
      kind: HealthMetricKind.hrvDaily,
      value: 45,
      unit: 'ms',
      capturedAt: DateTime.utc(2026, 5, 25),
    ));
    await repo.upsert(_metric(
      id: 'm-1',
      kind: HealthMetricKind.hrvDaily,
      value: 52, // corrected reading
      unit: 'ms',
      capturedAt: DateTime.utc(2026, 5, 25),
      counter: 1,
    ));
    final fetched = await repo.findById('m-1');
    expect(fetched?.value, 52, reason: 'second upsert wins');
    expect(await outbox.depth(), 2, reason: 'each upsert enqueues');
  });

  test('listByKind returns only matching kind, newest first', () async {
    final base = DateTime.utc(2026, 5, 20);
    for (var i = 0; i < 3; i++) {
      await repo.upsert(_metric(
        id: 'hrv-$i',
        kind: HealthMetricKind.hrvDaily,
        value: 40.0 + i,
        unit: 'ms',
        capturedAt: base.add(Duration(days: i)),
        counter: i,
      ));
    }
    await repo.upsert(_metric(
      id: 'steps-1',
      kind: HealthMetricKind.stepsDaily,
      value: 9000,
      unit: 'count',
      capturedAt: base,
      counter: 10,
    ));

    final hrv = await repo.listByKind(
      ownerUserId: _userA,
      kind: HealthMetricKind.hrvDaily,
    );
    expect(hrv.map((m) => m.id), ['hrv-2', 'hrv-1', 'hrv-0']);
    final steps = await repo.listByKind(
      ownerUserId: _userA,
      kind: HealthMetricKind.stepsDaily,
    );
    expect(steps.single.id, 'steps-1');
  });

  test(
    'listByKinds groups requested kinds newest-first with per-kind limit',
    () async {
      final base = DateTime.utc(2026, 5, 20);
      for (var i = 0; i < 4; i++) {
        await repo.upsert(
          _metric(
            id: 'hrv-$i',
            kind: HealthMetricKind.hrvDaily,
            value: 40.0 + i,
            unit: 'ms',
            capturedAt: base.add(Duration(days: i)),
            counter: i,
          ),
        );
        await repo.upsert(
          _metric(
            id: 'steps-$i',
            kind: HealthMetricKind.stepsDaily,
            value: 8000.0 + i,
            unit: 'count',
            capturedAt: base.add(Duration(days: i)),
            counter: 10 + i,
          ),
        );
      }
      await repo.upsert(
        _metric(
          id: 'sleep-ignored',
          kind: HealthMetricKind.sleepSession,
          value: 28800,
          capturedAt: base.add(const Duration(days: 4)),
          counter: 20,
        ),
      );

      final grouped = await repo.listByKinds(
        ownerUserId: _userA,
        kinds: const <HealthMetricKind>{
          HealthMetricKind.hrvDaily,
          HealthMetricKind.stepsDaily,
        },
        limit: 2,
      );

      expect(
        grouped.keys,
        containsAll([HealthMetricKind.hrvDaily, HealthMetricKind.stepsDaily]),
      );
      expect(grouped[HealthMetricKind.hrvDaily]!.map((m) => m.id), [
        'hrv-3',
        'hrv-2',
      ]);
      expect(grouped[HealthMetricKind.stepsDaily]!.map((m) => m.id), [
        'steps-3',
        'steps-2',
      ]);
      expect(grouped.containsKey(HealthMetricKind.sleepSession), isFalse);
    },
  );

  test('listByKind partitions by owner', () async {
    await repo.upsert(_metric(
      id: 'a-1',
      kind: HealthMetricKind.hrvDaily,
      value: 40,
      unit: 'ms',
      capturedAt: DateTime.utc(2026, 5, 20),
      ownerUserId: _userA,
    ));
    await repo.upsert(_metric(
      id: 'b-1',
      kind: HealthMetricKind.hrvDaily,
      value: 50,
      unit: 'ms',
      capturedAt: DateTime.utc(2026, 5, 20),
      ownerUserId: _userB,
    ));
    final forA = await repo.listByKind(
      ownerUserId: _userA,
      kind: HealthMetricKind.hrvDaily,
    );
    final forB = await repo.listByKind(
      ownerUserId: _userB,
      kind: HealthMetricKind.hrvDaily,
    );
    expect(forA.map((m) => m.id), ['a-1']);
    expect(forB.map((m) => m.id), ['b-1']);
  });

  test('tombstoned (deletedAt) rows are excluded from list and watch', () async {
    final alive = _metric(
      id: 'alive',
      kind: HealthMetricKind.weight,
      value: 70.5,
      unit: 'kg',
      capturedAt: DateTime.utc(2026, 5, 26),
    );
    final dead = _metric(
      id: 'dead',
      kind: HealthMetricKind.weight,
      value: 72.0,
      unit: 'kg',
      capturedAt: DateTime.utc(2026, 5, 25),
      deletedAt: DateTime.utc(2026, 5, 26),
      counter: 1,
    );
    await repo.upsert(alive);
    await repo.upsert(dead);

    final list = await repo.listByKind(
      ownerUserId: _userA,
      kind: HealthMetricKind.weight,
    );
    expect(list.map((m) => m.id), ['alive']);

    final stream = repo.watchRecent(
      ownerUserId: _userA,
      kind: HealthMetricKind.weight,
    );
    final firstEmit = await stream.first;
    expect(firstEmit.map((m) => m.id), ['alive']);
  });

  test('watchRecent emits on insert', () async {
    final stream = repo.watchRecent(
      ownerUserId: _userA,
      kind: HealthMetricKind.stepsDaily,
    );
    expect(await stream.first, isEmpty);

    await repo.upsert(_metric(
      id: 'steps-1',
      kind: HealthMetricKind.stepsDaily,
      value: 10500,
      unit: 'count',
      capturedAt: DateTime.utc(2026, 5, 26),
    ));
    final after = await stream.first;
    expect(after.single.id, 'steps-1');
    expect(after.single.value, 10500);
  });

  test('parses unknown kind safely', () async {
    // Simulate a wire kind the client hasn't been taught yet — write
    // directly via Drift companion bypassing the typed wrapper.
    await db.into(db.healthMetrics).insert(
      HealthMetricsCompanion.insert(
        id: 'future-kind',
        capturedAt: DateTime.utc(2026, 5, 26),
        kind: 'glucose_daily', // not in the enum
        value: 95,
        unit: 'mg/dl',
        ownerUserId: _userA,
        updatedAt: DateTime.utc(2026, 5, 26),
        updatedByDevice: _device,
        hlc: const Hlc(
          wallMillis: 1_700_000_000_005,
          counter: 0,
          nodeId: _device,
        ),
      ),
    );
    final fetched = await repo.findById('future-kind');
    expect(fetched, isNotNull);
    expect(fetched!.kind, HealthMetricKind.unknown);
  });
}
