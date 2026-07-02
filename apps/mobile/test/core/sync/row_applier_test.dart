import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

import '../../core/persistence/test_database.dart';

const _user = 'user-1';
const _devA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _devB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

/// Build the full `accounts` row payload as raw, JSON-safe SQLite values —
/// the shape the push side serialises (`DriftPendingRows.readRow`).
Map<String, Object?> _accountPayload({
  String id = 'account-1',
  String name = 'Cash',
  String currency = 'CNY',
  required String hlc,
  String device = _devA,
  int? deletedAt,
}) {
  return <String, Object?>{
    'id': id,
    'type': 'cash',
    'name': name,
    'currency': currency,
    'institution': null,
    'account_number': null,
    'note': null,
    'archived': 0,
    'category': 'asset',
    'parent_id': null,
    'icon': null,
    'color': null,
    'owner_user_id': _user,
    'updated_at': 1_700_000_000,
    'updated_by_device': device,
    'hlc': hlc,
    'deleted_at': deletedAt,
  };
}

String _hlc(int wall) => Hlc(
  wallMillis: wall,
  counter: 0,
  nodeId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
).toString();

RowChange _accountChange({
  required String version,
  String id = 'account-1',
  String name = 'Cash',
  String device = _devA,
  bool deleted = false,
  int? deletedAt,
}) {
  return RowChange(
    table: prefixFinanceTable('accounts'),
    id: id,
    payload: _accountPayload(
      id: id,
      name: name,
      hlc: version,
      device: device,
      deletedAt: deletedAt,
    ),
    version: version,
    deleted: deleted,
    deviceId: device,
  );
}

Future<AccountRow> _account(AppDatabase db, String id) {
  return (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingle();
}

void main() {
  late AppDatabase db;
  late RowApplier applier;

  setUp(() {
    db = makeTestDatabase();
    applier = RowApplier(db);
  });

  tearDown(() => db.close());

  test('materialises a remote RowChange into the local table', () async {
    final written = await applier.applyAll([
      _accountChange(version: _hlc(1_000), name: 'Cash'),
    ]);

    expect(written, 1);
    final row = await _account(db, 'account-1');
    expect(row.name, 'Cash');
    expect(row.currency, 'CNY');
    expect(row.ownerUserId, _user);
    expect(row.updatedByDevice, _devA);
    expect(row.hlc.wallMillis, 1_000);
    expect(row.deletedAt, isNull);
  });

  test('LWW skips a lower-version change', () async {
    await applier.applyAll([
      _accountChange(version: _hlc(2_000), name: 'Newer'),
    ]);

    // A change with a lower version must not overwrite the stored row.
    final report = await applier.applyWithReport([
      _accountChange(version: _hlc(1_000), name: 'Stale', device: _devB),
    ]);

    expect(
      report.written,
      0,
      reason: 'older version is shadowed by local state',
    );
    expect(report.skippedLocalWins, 1);
    expect(report.skippedIgnored, 0);
    final row = await _account(db, 'account-1');
    expect(row.name, 'Newer');
    expect(row.hlc.wallMillis, 2_000);
  });

  test('LWW applies a higher-version change', () async {
    await applier.applyAll([_accountChange(version: _hlc(1_000), name: 'Old')]);
    final written = await applier.applyAll([
      _accountChange(version: _hlc(3_000), name: 'Updated', device: _devB),
    ]);

    expect(written, 1);
    final row = await _account(db, 'account-1');
    expect(row.name, 'Updated');
    expect(row.updatedByDevice, _devB);
    expect(row.hlc.wallMillis, 3_000);
  });

  test('materialises a deleted RowChange as a tombstone', () async {
    await applier.applyAll([
      _accountChange(version: _hlc(1_000), name: 'Cash'),
    ]);
    await applier.applyAll([
      _accountChange(
        version: _hlc(2_000),
        deleted: true,
        deletedAt: 1_700_000_500,
        device: _devB,
      ),
    ]);

    final row = await _account(db, 'account-1');
    expect(row.deletedAt, isNotNull);
    expect(row.hlc.wallMillis, 2_000);
  });

  test('skips rows that are not syncable tables', () async {
    final report = await applier.applyWithReport([
      RowChange(
        table: 'fin:not_a_table',
        id: 'x',
        payload: const {'id': 'x'},
        version: _hlc(1_000),
        deleted: false,
        deviceId: _devA,
      ),
    ]);
    expect(report.written, 0);
    expect(report.skippedUnsupportedTable, 1);
    expect(report.skippedIgnored, 1);
  });

  test('drops rows that arrive without a recognised domain prefix', () async {
    // Legacy rows (pre-D-1.4) lose their prefix until the backend
    // migration runs. Until then the applier refuses to write them.
    final report = await applier.applyWithReport([
      RowChange(
        table: 'accounts',
        id: 'account-1',
        payload: _accountPayload(hlc: _hlc(1_000)),
        version: _hlc(1_000),
        deleted: false,
        deviceId: _devA,
      ),
    ]);
    expect(report.written, 0);
    expect(report.skippedUnknownDomain, 1);
  });

  test('accepts inbound rows in the health namespace metadata-only', () async {
    // The current device has no `health:*` syncable table — the row must
    // be classified by domain prefix then dropped on the syncable-set
    // check, not crash.
    final written = await applier.applyAll([
      RowChange(
        table: 'health:sleep_session',
        id: 's-1',
        payload: const <String, Object?>{'id': 's-1'},
        version: _hlc(1_000),
        deleted: false,
        deviceId: _devA,
      ),
    ]);
    expect(written, 0);
  });
}
