import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_metric_write_service.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-test';
const _deviceId = 'dev-test';

MutationStamper _fakeStamper({int startMillis = 1_700_000_000_000}) {
  var counter = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async =>
        Hlc(wallMillis: startMillis + counter++, counter: 0, nodeId: _deviceId),
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late HealthMetricRepository repo;
  late HealthMetricWriteService service;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = HealthMetricRepository(db: db, outbox: outbox);
    service = HealthMetricWriteService(
      repository: repo,
      stamper: _fakeStamper(),
    );
  });

  tearDown(() => db.close());

  test('records manual weight with stable same-day id', () async {
    final row = await service.recordBodyMeasurement(
      kind: HealthMetricKind.weight,
      value: 72.4,
      capturedAt: DateTime.utc(2026, 5, 30, 9),
      note: 'morning',
    );

    expect(row.id, 'manual:weight:$_userId:2026-05-30');
    expect(row.kind, HealthMetricKind.weight);
    expect(row.unit, 'kg');
    expect(row.sourceDevice, 'manual');
    expect(row.payloadJson, contains('morning'));
    expect(await outbox.depth(), 1);
  });

  test('body fat percent is normalized to fraction', () async {
    final row = await service.recordBodyMeasurement(
      kind: HealthMetricKind.bodyFat,
      value: 18.5,
      capturedAt: DateTime.utc(2026, 5, 30, 9),
      source: 'ai',
    );

    expect(row.kind, HealthMetricKind.bodyFat);
    expect(row.value, closeTo(0.185, 1e-9));
    expect(row.unit, 'fraction');
    expect(row.sourceDevice, 'ai');
  });

  test('same day/kind replaces the row instead of duplicating', () async {
    await service.recordBodyMeasurement(
      kind: HealthMetricKind.weight,
      value: 72.4,
      capturedAt: DateTime.utc(2026, 5, 30, 9),
    );
    await service.recordBodyMeasurement(
      kind: HealthMetricKind.weight,
      value: 72.1,
      capturedAt: DateTime.utc(2026, 5, 30, 22),
    );

    final row = await repo.findById('manual:weight:$_userId:2026-05-30');
    expect(row, isNotNull);
    expect(row!.value, 72.1);
    expect(await outbox.depth(), 2);
  });
}
