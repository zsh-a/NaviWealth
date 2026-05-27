// D-2.2 HealthSyncService tests.
//
// We swap in a FakeHealthPlatformAdapter so the test never touches the
// real `health` plugin (which would fail in flutter_test without the
// platform side wired). Otherwise it's a real Drift in-memory DB +
// real repository so the upsert path is exercised end-to-end.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_platform_adapter.dart';
import 'package:naviwealth/features/health/data/health_sync_service.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-test';
const _deviceId = 'dev-test';

class _FakeAdapter implements HealthPlatformAdapter {
  _FakeAdapter({
    this.available = true,
    this.permissions = true,
    HealthPlatformSnapshot? snapshot,
  }) : _snapshot = snapshot ?? const HealthPlatformSnapshot.empty();

  bool available;
  bool permissions;
  HealthPlatformSnapshot _snapshot;
  int fetchCalls = 0;
  DateTime? lastFrom;
  DateTime? lastTo;

  void setSnapshot(HealthPlatformSnapshot s) => _snapshot = s;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> hasPermissions() async => permissions;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async {
    fetchCalls++;
    lastFrom = from;
    lastTo = to;
    return _snapshot;
  }
}

MutationStamper _fakeStamper({int startMillis = 1_700_000_000_000}) {
  var counter = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final hlc = Hlc(
        wallMillis: startMillis + counter,
        counter: 0,
        nodeId: _deviceId,
      );
      counter++;
      return hlc;
    },
  );
}

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

  test('skips when platform unavailable', () async {
    final svc = HealthSyncService(
      adapter: _FakeAdapter(available: false),
      repository: repo,
      stamper: _fakeStamper(),
    );
    final r = await svc.syncRange();
    expect(r.ok, isFalse);
    expect(r.errorMessage, 'health-platform-unavailable');
    expect(await outbox.depth(), 0);
  });

  test('skips when permissions are denied', () async {
    final svc = HealthSyncService(
      adapter: _FakeAdapter(permissions: false),
      repository: repo,
      stamper: _fakeStamper(),
    );
    final r = await svc.syncRange();
    expect(r.ok, isFalse);
    expect(r.errorMessage, 'health-platform-permission-denied');
  });

  test(
    'maps snapshot into health_metrics rows of the right kind/unit',
    () async {
      final adapter = _FakeAdapter(
        snapshot: HealthPlatformSnapshot(
          sleepSessions: <RawSleepSession>[
            RawSleepSession(
              externalId: 'hk:sleep:s1',
              startedAt: DateTime.utc(2026, 5, 25, 23),
              duration: const Duration(hours: 7, minutes: 30),
              sourceDevice: 'Apple Watch',
            ),
          ],
          hrv: <RawDailyValue>[
            RawDailyValue(
              externalId: 'hk:hrv:2026-05-25',
              day: DateTime.utc(2026, 5, 25),
              value: 48.2,
            ),
          ],
          steps: <RawDailyValue>[
            RawDailyValue(
              externalId: 'hk:steps:2026-05-25',
              day: DateTime.utc(2026, 5, 25),
              value: 12345,
            ),
          ],
          weight: <RawPointValue>[
            RawPointValue(
              externalId: 'hk:weight:w1',
              measuredAt: DateTime.utc(2026, 5, 25, 8),
              value: 72.4,
            ),
          ],
          bodyFat: <RawPointValue>[
            RawPointValue(
              externalId: 'hk:bodyfat:bf1',
              measuredAt: DateTime.utc(2026, 5, 25, 8),
              value: 0.184, // already fraction
            ),
          ],
        ),
      );
      final svc = HealthSyncService(
        adapter: adapter,
        repository: repo,
        stamper: _fakeStamper(),
      );

      final r = await svc.syncRange();
      expect(r.ok, isTrue);
      expect(r.totalFetched, 5);
      expect(r.upserted, 5);
      expect(r.unchanged, 0);

      final sleep = await repo.findById('hk:sleep:s1');
      expect(sleep, isNotNull);
      expect(sleep!.kind, HealthMetricKind.sleepSession);
      expect(sleep.value, 7 * 3600 + 30 * 60);
      expect(sleep.unit, 's');
      expect(sleep.sourceDevice, 'Apple Watch');
      expect(sleep.sync.ownerUserId, _userId);

      final hrv = await repo.findById('hk:hrv:2026-05-25');
      expect(hrv!.kind, HealthMetricKind.hrvDaily);
      expect(hrv.value, closeTo(48.2, 1e-6));
      expect(hrv.unit, 'ms');

      final steps = await repo.findById('hk:steps:2026-05-25');
      expect(steps!.kind, HealthMetricKind.stepsDaily);
      expect(steps.value, 12345);
      expect(steps.unit, 'count');

      final weight = await repo.findById('hk:weight:w1');
      expect(weight!.kind, HealthMetricKind.weight);
      expect(weight.unit, 'kg');

      final bf = await repo.findById('hk:bodyfat:bf1');
      expect(bf!.kind, HealthMetricKind.bodyFat);
      expect(bf.unit, 'fraction');
      expect(bf.value, closeTo(0.184, 1e-6));

      expect(await outbox.depth(), 5);
    },
  );

  test('re-syncing identical data is a no-op (idempotent, no outbox spam)',
      () async {
    final snapshot = HealthPlatformSnapshot(
      hrv: <RawDailyValue>[
        RawDailyValue(
          externalId: 'hk:hrv:2026-05-25',
          day: DateTime.utc(2026, 5, 25),
          value: 50,
        ),
      ],
    );
    final adapter = _FakeAdapter(snapshot: snapshot);
    final svc = HealthSyncService(
      adapter: adapter,
      repository: repo,
      stamper: _fakeStamper(),
    );

    final first = await svc.syncRange();
    expect(first.upserted, 1);
    expect(first.unchanged, 0);
    expect(await outbox.depth(), 1);

    final second = await svc.syncRange();
    expect(second.upserted, 0);
    expect(second.unchanged, 1);
    expect(
      await outbox.depth(),
      1,
      reason: 'unchanged rows must not enqueue a new outbox op',
    );
  });

  test(
    'value mutation rewrites the row and bumps the outbox',
    () async {
      final svc = HealthSyncService(
        adapter: _FakeAdapter(
          snapshot: HealthPlatformSnapshot(
            hrv: <RawDailyValue>[
              RawDailyValue(
                externalId: 'hk:hrv:d1',
                day: DateTime.utc(2026, 5, 25),
                value: 50,
              ),
            ],
          ),
        ),
        repository: repo,
        stamper: _fakeStamper(),
      );
      await svc.syncRange();
      expect((await repo.findById('hk:hrv:d1'))!.value, 50);

      // Same id, new value → must write through.
      final adapter2 = _FakeAdapter(
        snapshot: HealthPlatformSnapshot(
          hrv: <RawDailyValue>[
            RawDailyValue(
              externalId: 'hk:hrv:d1',
              day: DateTime.utc(2026, 5, 25),
              value: 55,
            ),
          ],
        ),
      );
      final svc2 = HealthSyncService(
        adapter: adapter2,
        repository: repo,
        stamper: _fakeStamper(startMillis: 1_700_000_001_000),
      );
      final r = await svc2.syncRange();
      expect(r.upserted, 1);
      expect(r.unchanged, 0);
      expect((await repo.findById('hk:hrv:d1'))!.value, 55);
    },
  );

  test('honours explicit from / to window', () async {
    final adapter = _FakeAdapter();
    final svc = HealthSyncService(
      adapter: adapter,
      repository: repo,
      stamper: _fakeStamper(),
    );
    final from = DateTime.utc(2026, 5, 1);
    final to = DateTime.utc(2026, 5, 10);
    await svc.syncRange(from: from, to: to);
    expect(adapter.fetchCalls, 1);
    expect(adapter.lastFrom, from);
    expect(adapter.lastTo, to);
  });
}
