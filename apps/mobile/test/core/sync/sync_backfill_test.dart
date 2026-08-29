import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/sync_backfill.dart';

import '../persistence/test_database.dart';

/// Execution-path coverage for the one-time local-row backfill: which rows
/// get a dirty pointer, which are deliberately skipped, and the sync_meta
/// marker that makes a second pass a no-op.
void main() {
  final session = AuthSession(
    accessToken: 'test-token',
    expiresAt: DateTime.utc(2030),
    userId: 'u-backfill',
    deviceId: 'dev-backfill',
  );

  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() => db.close());

  Future<void> seedAccounts() async {
    await db.customStatement('''
      INSERT INTO accounts (
        id, name, type, category, currency,
        owner_user_id, updated_at, updated_by_device, hlc
      ) VALUES ('acc-live', 'Broker', 'broker', 'asset', 'CNY',
        'u-backfill', 1, 'dev-1', '1-dev-1')
    ''');
    await db.customStatement('''
      INSERT INTO accounts (
        id, name, type, category, currency,
        owner_user_id, updated_at, updated_by_device, hlc
      ) VALUES ('system-account:seed', 'Seeded cash', 'broker', 'asset', 'CNY',
        'u-backfill', 1, 'dev-1', '1-dev-1')
    ''');
    await db.customStatement('''
      INSERT INTO accounts (
        id, name, type, category, currency,
        owner_user_id, updated_at, updated_by_device, hlc, deleted_at
      ) VALUES ('acc-deleted', 'Gone', 'broker', 'asset', 'CNY',
        'u-backfill', 1, 'dev-1', '1-dev-1', 1)
    ''');
    await db.customStatement('''
      INSERT INTO accounts (
        id, name, type, category, currency,
        owner_user_id, updated_at, updated_by_device, hlc
      ) VALUES ('acc-other-user', 'Other owner', 'broker', 'asset', 'CNY',
        'u-someone-else', 1, 'dev-1', '1-dev-1')
    ''');
  }

  Future<void> seedHealthMetrics() async {
    await db.customStatement('''
      INSERT INTO health_metrics (
        id, captured_at, kind, value, unit,
        owner_user_id, updated_at, updated_by_device, hlc
      ) VALUES ('garmin:m1', 1, 'hrv_daily', 40.0, 'ms',
        'u-backfill', 1, 'dev-1', '1-dev-1')
    ''');
    await db.customStatement('''
      INSERT INTO health_metrics (
        id, captured_at, kind, value, unit,
        owner_user_id, updated_at, updated_by_device, hlc, deleted_at
      ) VALUES ('hk:m2', 1, 'steps_daily', 100.0, 'count',
        'u-backfill', 1, 'dev-1', '1-dev-1', 1)
    ''');
  }

  test('enqueues one pointer per live row owned by the session user', () async {
    await seedAccounts();
    await seedHealthMetrics();
    final outbox = InMemoryOutboxStore();
    final backfill = SyncBackfill(db: db, outbox: outbox, session: session);

    final queued = await backfill.enqueueMissingLocalRows();

    expect(queued, 2, reason: 'one live account + one live health metric');
    expect(
      outbox.items.map((item) => '${item.table}:${item.rowId}').toSet(),
      <String>{'accounts:acc-live', 'health_metrics:garmin:m1'},
    );
  });

  test('a second pass is a no-op', () async {
    await seedAccounts();
    final outbox = InMemoryOutboxStore();
    final backfill = SyncBackfill(db: db, outbox: outbox, session: session);

    expect(await backfill.enqueueMissingLocalRows(), 1);
    expect(await backfill.enqueueMissingLocalRows(), 0);
    expect(outbox.items, hasLength(1));
  });

  test('markers are scoped per user and device', () async {
    await seedAccounts();
    final outbox = InMemoryOutboxStore();
    final backfill = SyncBackfill(db: db, outbox: outbox, session: session);
    await backfill.enqueueMissingLocalRows();

    final otherDevice = SyncBackfill(
      db: db,
      outbox: outbox,
      session: AuthSession(
        accessToken: 'test-token',
        expiresAt: DateTime.utc(2030),
        userId: 'u-backfill',
        deviceId: 'dev-other',
      ),
    );
    expect(await otherDevice.enqueueMissingLocalRows(), 1);
    expect(outbox.items, hasLength(2));
  });
}
