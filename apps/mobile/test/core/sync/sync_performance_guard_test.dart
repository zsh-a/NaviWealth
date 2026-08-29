import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';

import '../persistence/test_database.dart';

/// Bounded-duration guards for the two hot sync paths.
///
/// These are regression floors, not benchmarks: the budget follows the
/// deterministic-test-environment convention of the 1,000-row restore
/// fixture (bounded to ten seconds) and exists to catch gross complexity
/// regressions — an accidental per-row transaction, an N+1 query added on
/// top of the loop, or a missing index forcing table scans. The current
/// implementations finish in low single-digit seconds on CI hardware;
/// if a legitimate optimization lands, tighten the budget.
void main() {
  const rowCount = 2000;
  const budget = Duration(seconds: 10);

  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() => db.close());

  Map<String, Object?> healthPayload(int i, Hlc version) {
    return <String, Object?>{
      'id': 'garmin:perf-$i',
      'captured_at': DateTime.utc(2026, 6, 1).millisecondsSinceEpoch ~/ 1000,
      'kind': 'hrv_daily',
      'value': 40.0 + i,
      'unit': 'ms',
      'owner_user_id': 'u-perf',
      'updated_at': DateTime.utc(2026, 6, 2).millisecondsSinceEpoch ~/ 1000,
      'updated_by_device': 'dev-perf',
      'hlc': version.toString(),
    };
  }

  test('applier writes $rowCount pulled rows inside the budget', () async {
    final applier = RowApplier(db);
    final rows = <RowChange>[
      for (var i = 0; i < rowCount; i++)
        RowChange(
          table: 'health:health_metrics',
          id: 'garmin:perf-$i',
          payload: healthPayload(
            i,
            Hlc(wallMillis: 1, counter: i, nodeId: 'dev-perf'),
          ),
          version: Hlc(
            wallMillis: 1,
            counter: i,
            nodeId: 'dev-perf',
          ).toString(),
          deleted: false,
        ),
    ];

    final sw = Stopwatch()..start();
    final written = await applier.applyAll(rows);
    sw.stop();

    expect(written, rowCount);
    expect(sw.elapsed, lessThan(budget));
  });

  test('push side serializes $rowCount dirty rows inside the budget', () async {
    final outbox = DriftOutboxStore(db);
    final pending = DriftPendingRows(db);

    // Seed the rows and the dirty pointers in one transaction each, so
    // the guarded cost is the serialization loop, not the setup.
    await db.transaction(() async {
      for (var i = 0; i < rowCount; i++) {
        final version = Hlc(wallMillis: 1, counter: i, nodeId: 'dev-perf');
        final payload = healthPayload(i, version);
        await db.customStatement(
          'INSERT INTO health_metrics '
          '(id, captured_at, kind, value, unit, owner_user_id, updated_at, '
          'updated_by_device, hlc) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            payload['id'],
            payload['captured_at'],
            payload['kind'],
            payload['value'],
            payload['unit'],
            payload['owner_user_id'],
            payload['updated_at'],
            payload['updated_by_device'],
            (payload['hlc'] as String),
          ],
        );
        await outbox.enqueue(
          table: 'health_metrics',
          rowId: payload['id'] as String,
        );
      }
    });

    final sw = Stopwatch()..start();
    final pointers = await pending.pointers();
    expect(pointers, hasLength(rowCount));
    var serialized = 0;
    for (final pointer in pointers) {
      final row = await pending.readRow(pointer.table, pointer.rowId);
      if (row != null) serialized++;
    }
    sw.stop();

    expect(serialized, rowCount);
    expect(sw.elapsed, lessThan(budget));
  });
}
