import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_metric_source.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v78 → v79 adds `health_metrics.source_id`. The legacy table keeps
/// working after the additive ALTER TABLE: pre-existing rows keep NULL
/// and resolve through the id-prefix derivation, new writes persist the
/// resolved source.
void main() {
  test(
    'v78 health metrics migrate without losing rows or attribution',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth-health-v79-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      final legacy = sqlite3.sqlite3.open(file.path);
      try {
        legacy.execute('''
          CREATE TABLE health_metrics (
            id TEXT NOT NULL PRIMARY KEY,
            captured_at INTEGER NOT NULL,
            kind TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL,
            payload_json TEXT,
            source_device TEXT,
            owner_user_id TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            updated_by_device TEXT NOT NULL,
            hlc TEXT NOT NULL,
            deleted_at INTEGER
          )
        ''');
        // captured_at / updated_at use Drift's native epoch-seconds shape.
        final captured =
            DateTime.utc(2026, 6, 1).millisecondsSinceEpoch ~/ 1000;
        final hlc = Hlc(
          wallMillis: captured * 1000,
          counter: 0,
          nodeId: 'dev-legacy',
        ).toString();
        legacy.execute('''
          INSERT INTO health_metrics
            (id, captured_at, kind, value, unit, payload_json, source_device,
             owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
          VALUES ('garmin:legacy-1', $captured, 'hrv_daily', 41.0, 'ms', NULL,
            'Forerunner 965', 'u-migrate', $captured, 'dev-legacy',
            '$hlc', NULL)
        ''');
        legacy.execute('''
          INSERT INTO health_metrics
            (id, captured_at, kind, value, unit, payload_json, source_device,
             owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
          VALUES ('hk:legacy-2', $captured, 'steps_daily', 8213.0, 'count',
            NULL, 'iPhone', 'u-migrate', $captured, 'dev-legacy',
            '$hlc', NULL)
        ''');
        legacy.execute('PRAGMA user_version = 78');
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT * FROM health_metrics ORDER BY id')
          .get();
      expect(rows, hasLength(2));
      expect(
        rows.every((row) => row.readNullable<String>('source_id') == null),
        isTrue,
      );

      // Legacy rows still resolve their source through the id prefix.
      final allRows = await db.select(db.healthMetrics).get();
      final legacyGarmin = allRows.singleWhere(
        (row) => row.id == 'garmin:legacy-1',
      );
      expect(sourceForHealthMetricRow(legacyGarmin), HealthMetricSource.garmin);
      final legacyHk = allRows.singleWhere((row) => row.id == 'hk:legacy-2');
      expect(sourceForHealthMetricRow(legacyHk), HealthMetricSource.healthKit);

      // New writes persist the resolved source into the column.
      final outbox = InMemoryOutboxStore();
      final repo = HealthMetricRepository(db: db, outbox: outbox);
      const device = 'dev-migrate';
      await repo.upsert(
        HealthMetric(
          id: 'garmin:new-1',
          capturedAt: DateTime.utc(2026, 6, 2),
          kind: HealthMetricKind.hrvDaily,
          value: 44,
          unit: 'ms',
          sync: SyncMeta(
            ownerUserId: 'u-migrate',
            updatedAt: DateTime.utc(2026, 6, 2),
            updatedByDevice: device,
            hlc: Hlc(
              wallMillis: DateTime.utc(2026, 6, 2).millisecondsSinceEpoch,
              counter: 0,
              nodeId: device,
            ),
          ),
        ),
      );
      final written = await db
          .customSelect(
            "SELECT source_id FROM health_metrics WHERE id = 'garmin:new-1'",
          )
          .getSingle();
      expect(written.read<String>('source_id'), 'garmin');
      expect(await outbox.depth(), 1);
    },
  );
}
