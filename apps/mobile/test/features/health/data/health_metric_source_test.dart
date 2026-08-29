import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

import '../../../core/persistence/test_database.dart';

const _user = 'u-source';
const _device = 'dev-source';

SyncMeta _sync({int counter = 0}) => SyncMeta(
  ownerUserId: _user,
  updatedAt: DateTime.utc(2026, 6, 3),
  updatedByDevice: _device,
  hlc: Hlc(
    wallMillis: DateTime.utc(2026, 6, 3).millisecondsSinceEpoch,
    counter: counter,
    nodeId: _device,
  ),
);

HealthMetricRow _row({
  String? sourceId,
  String? sourceDevice,
  String id = 'm',
}) {
  return HealthMetricRow(
    id: id,
    capturedAt: DateTime.utc(2026, 6, 3),
    kind: HealthMetricKind.hrvDaily.wire,
    value: 40,
    unit: 'ms',
    sourceDevice: sourceDevice,
    sourceId: sourceId,
    ownerUserId: _user,
    updatedAt: DateTime.utc(2026, 6, 3),
    updatedByDevice: _device,
    hlc: Hlc(
      wallMillis: DateTime.utc(2026, 6, 3).millisecondsSinceEpoch,
      counter: 0,
      nodeId: _device,
    ),
  );
}

void main() {
  group('healthMetricSourceFromId', () {
    test('maps every persisted wire id', () {
      expect(healthMetricSourceFromId('garmin'), HealthMetricSource.garmin);
      expect(
        healthMetricSourceFromId('healthkit'),
        HealthMetricSource.healthKit,
      );
      expect(
        healthMetricSourceFromId('health_connect'),
        HealthMetricSource.healthConnect,
      );
      expect(healthMetricSourceFromId('manual'), HealthMetricSource.manual);
      expect(healthMetricSourceFromId('unknown'), HealthMetricSource.unknown);
    });

    test('returns null for absent or unrecognized values', () {
      expect(healthMetricSourceFromId(null), isNull);
      expect(healthMetricSourceFromId(''), isNull);
      expect(healthMetricSourceFromId('  '), isNull);
      expect(healthMetricSourceFromId('polar'), isNull);
    });
  });

  group('legacyHealthMetricSource', () {
    test('prefers adapter row-id prefixes', () {
      expect(
        legacyHealthMetricSource(rowId: 'garmin:r1'),
        HealthMetricSource.garmin,
      );
      expect(
        legacyHealthMetricSource(rowId: 'hk:r1'),
        HealthMetricSource.healthKit,
      );
      expect(
        legacyHealthMetricSource(rowId: 'hc:r1'),
        HealthMetricSource.healthConnect,
      );
      expect(
        legacyHealthMetricSource(rowId: 'manual:r1'),
        HealthMetricSource.manual,
      );
    });

    test('falls back to legacy device attribution', () {
      expect(
        legacyHealthMetricSource(rowId: 'r1', sourceDevice: 'Garmin Venu'),
        HealthMetricSource.garmin,
      );
      expect(
        legacyHealthMetricSource(rowId: 'r1', sourceDevice: 'health connect'),
        HealthMetricSource.healthConnect,
      );
      expect(
        legacyHealthMetricSource(rowId: 'r1', sourceDevice: 'Apple Watch'),
        HealthMetricSource.healthKit,
      );
      expect(
        legacyHealthMetricSource(rowId: 'r1', sourceDevice: 'manual'),
        HealthMetricSource.manual,
      );
      expect(
        legacyHealthMetricSource(rowId: 'r1', sourceDevice: 'Polar'),
        HealthMetricSource.unknown,
      );
      expect(legacyHealthMetricSource(rowId: 'r1'), HealthMetricSource.unknown);
    });
  });

  group('sourceForHealthMetricRow', () {
    test('the persisted column wins over the id prefix', () {
      expect(
        sourceForHealthMetricRow(_row(sourceId: 'manual', id: 'garmin:x')),
        HealthMetricSource.manual,
      );
    });

    test('legacy rows without a column value fall back to the prefix', () {
      expect(
        sourceForHealthMetricRow(_row(id: 'hk:x')),
        HealthMetricSource.healthKit,
      );
      expect(
        sourceForHealthMetricRow(_row(sourceId: 'polar', id: 'garmin:x')),
        HealthMetricSource.garmin,
        reason: 'an unrecognized column value must not mask the prefix',
      );
    });
  });

  group('HealthMetricRepository source persistence', () {
    late AppDatabase db;
    late InMemoryOutboxStore outbox;
    late HealthMetricRepository repo;

    setUp(() {
      db = makeTestDatabase();
      outbox = InMemoryOutboxStore();
      repo = HealthMetricRepository(db: db, outbox: outbox);
    });

    tearDown(() => db.close());

    test('upsert persists the derived source id for each adapter', () async {
      for (final entry in <String, HealthMetricSource>{
        'garmin:g1': HealthMetricSource.garmin,
        'hk:h1': HealthMetricSource.healthKit,
        'hc:c1': HealthMetricSource.healthConnect,
        'manual:m1': HealthMetricSource.manual,
      }.entries) {
        await repo.upsert(
          HealthMetric(
            id: entry.key,
            capturedAt: DateTime.utc(2026, 6, 3),
            kind: HealthMetricKind.hrvDaily,
            value: 40,
            unit: 'ms',
            sync: _sync(counter: entry.key.length),
          ),
        );
      }

      final rows = await db.select(db.healthMetrics).get();
      expect(
        {for (final row in rows) row.id: row.sourceId},
        <String, String?>{
          'garmin:g1': 'garmin',
          'hk:h1': 'healthkit',
          'hc:c1': 'health_connect',
          'manual:m1': 'manual',
        },
      );
      expect(await outbox.depth(), 4);
    });
  });
}
