import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_snapshot_writer.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-garmin';
const _deviceId = 'dev-garmin';

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
  late GarminSnapshotWriter writer;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = HealthMetricRepository(db: db, outbox: outbox);
    writer = GarminSnapshotWriter(repository: repo, stamper: _fakeStamper());
  });

  tearDown(() => db.close());

  test('writes normalized Rust HealthSnapshot rows idempotently', () async {
    final snapshot = {
      'hrv': [
        {
          'id': 'garmin:hrv:2026-06-07',
          'date': '2026-06-07',
          'value': 103,
          'unit': 'ms',
          'source_device': 'garmin',
        },
      ],
      'stress': [
        {
          'id': 'garmin:stress:2026-06-07',
          'date': '2026-06-07',
          'value': 19,
          'unit': 'level',
          'source_device': 'garmin',
        },
      ],
      'body_battery': [
        {
          'id': 'garmin:body_battery:2026-06-07',
          'date': '2026-06-07',
          'min': 27,
          'max': 98,
          'charged': 71,
          'drained': 72,
          'source_device': 'garmin',
        },
      ],
      'spo2': [
        {
          'id': 'garmin:spo2:2026-06-07',
          'date': '2026-06-07',
          'value': 96,
          'unit': '%',
          'source_device': 'garmin',
        },
      ],
      'sleep_sessions': [
        {
          'id': 'garmin:sleep:1780767017000',
          'started_at': '2026-06-06T17:30:17Z',
          'duration_seconds': 27000,
          'source_device': 'garmin',
          'stage_histogram_json': '{"deep":6840}',
        },
      ],
    };

    final first = await writer.writeSnapshotMap(snapshot);
    expect(first.ok, isTrue);
    expect(first.upserted, 5);
    expect(first.unchanged, 0);
    expect(await outbox.depth(), 5);

    final hrv = await repo.findById('garmin:hrv:2026-06-07');
    expect(hrv, isNotNull);
    expect(hrv!.kind, HealthMetricKind.hrvDaily);
    expect(hrv.value, 103);
    expect(hrv.unit, 'ms');
    expect(hrv.sourceDevice, 'garmin');
    expect(hrv.sync.ownerUserId, _userId);

    final stress = await repo.findById('garmin:stress:2026-06-07');
    expect(stress!.kind, HealthMetricKind.stressDaily);
    expect(stress.value, 19);

    final bodyBattery = await repo.findById('garmin:body_battery:2026-06-07');
    expect(bodyBattery!.kind, HealthMetricKind.bodyBatteryDaily);
    expect(bodyBattery.value, 98);
    expect(bodyBattery.payloadJson, contains('"charged":71'));
    expect(bodyBattery.payloadJson, contains('"drained":72'));

    final spo2 = await repo.findById('garmin:spo2:2026-06-07');
    expect(spo2!.kind, HealthMetricKind.spo2Daily);
    expect(spo2.value, 96);

    final sleep = await repo.findById('garmin:sleep:1780767017000');
    expect(sleep!.kind, HealthMetricKind.sleepSession);
    expect(sleep.capturedAt.toUtc(), DateTime.utc(2026, 6, 6, 17, 30, 17));

    final repeated = await writer.writeSnapshotMap(snapshot);
    expect(repeated.upserted, 0);
    expect(repeated.unchanged, 5);
    expect(await outbox.depth(), 5);
  });
}
