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

  test('materialises paper simulation rows in the finance namespace', () async {
    final version = _hlc(1_500);
    final written = await applier.applyAll([
      RowChange(
        table: prefixFinanceTable('watchlist_simulations'),
        id: 'simulation-1',
        payload: <String, Object?>{
          'id': 'simulation-1',
          'collection_id': 'collection-growth',
          'name': 'Growth paper mix',
          'base_currency': 'USD',
          'starting_capital': '100000',
          'cash_weight': '0.2',
          'allocation_protocol_version': 1,
          'baseline_at': 1_700_000_000,
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
      RowChange(
        table: prefixFinanceTable('watchlist_simulation_positions'),
        id: 'position-1',
        payload: <String, Object?>{
          'id': 'position-1',
          'simulation_id': 'simulation-1',
          'watchlist_item_id': 'us_stock:AAPL',
          'target_weight': '0.8',
          'requires_explicit_head': true,
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
      RowChange(
        table: prefixFinanceTable('watchlist_simulation_allocation_heads'),
        id: 'simulation-1',
        payload: <String, Object?>{
          'id': 'simulation-1',
          'simulation_id': 'simulation-1',
          'allocation_version_id': 'allocation-1',
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
      RowChange(
        table: prefixFinanceTable('watchlist_simulation_allocation_versions'),
        id: 'allocation-1',
        payload: <String, Object?>{
          'id': 'allocation-1',
          'simulation_id': 'simulation-1',
          'effective_at': 1_700_000_000,
          'reason': 'creation',
          'previous_allocation_version_id': null,
          'requires_explicit_head': true,
          'cash_weight': '0.2',
          'is_complete': true,
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
      RowChange(
        table: prefixFinanceTable('watchlist_simulation_holding_versions'),
        id: 'holding-1',
        payload: <String, Object?>{
          'id': 'holding-1',
          'allocation_version_id': 'allocation-1',
          'simulation_id': 'simulation-1',
          'watchlist_item_id': 'us_stock:AAPL',
          'symbol': 'AAPL',
          'market': 'us_stock',
          'target_weight': '0.8',
          'quantity': '400',
          'raw_price': '200',
          'price_currency': 'USD',
          'price_as_of': 1_700_000_000,
          'price_source': 'fixture',
          'fx_to_base': '1',
          'effective_at': 1_700_000_000,
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
      RowChange(
        table: prefixFinanceTable('watchlist_simulation_action_entries'),
        id: 'action-1',
        payload: <String, Object?>{
          'id': 'action-1',
          'simulation_id': 'simulation-1',
          'watchlist_item_id': 'us_stock:AAPL',
          'symbol': 'AAPL',
          'market': 'us_stock',
          'source': 'yfinance',
          'dataset': 'chart',
          'source_key': 'AAPL:dividend:1',
          'revision_hash': 'revision-1',
          'kind': 'distribution',
          'status': 'implemented',
          'paper_state': 'grossCashPendingTax',
          'record_date': 1_700_086_400,
          'ex_date': 1_700_172_800,
          'pay_date': 1_700_259_200,
          'currency': 'USD',
          'cash_per_share': '0.25',
          'eligible_quantity': '100',
          'gross_amount': '25',
          'receivable_gross_amount': null,
          'paper_cash_gross_amount': '25',
          'state_at': 1_700_259_200,
          'allocation_basis_key': 'alloc-v1:allocation-1',
          'created_at': 1_700_000_000,
          'owner_user_id': _user,
          'updated_at': 1_700_000_000,
          'updated_by_device': _devA,
          'hlc': version,
          'deleted_at': null,
        },
        version: version,
        deleted: false,
        deviceId: _devA,
      ),
    ]);

    expect(written, 6);
    final simulation = await (db.select(
      db.watchlistSimulations,
    )..where((t) => t.id.equals('simulation-1'))).getSingle();
    final position = await (db.select(
      db.watchlistSimulationPositions,
    )..where((t) => t.id.equals('position-1'))).getSingle();
    expect(simulation.collectionId, 'collection-growth');
    expect(simulation.startingCapital.toString(), '100000');
    expect(simulation.allocationProtocolVersion, 1);
    final head = await (db.select(
      db.watchlistSimulationAllocationHeads,
    )..where((t) => t.id.equals('simulation-1'))).getSingle();
    final allocation = await (db.select(
      db.watchlistSimulationAllocationVersions,
    )..where((t) => t.id.equals('allocation-1'))).getSingle();
    final holding = await (db.select(
      db.watchlistSimulationHoldingVersions,
    )..where((t) => t.id.equals('holding-1'))).getSingle();
    final action = await (db.select(
      db.watchlistSimulationActionEntries,
    )..where((t) => t.id.equals('action-1'))).getSingle();
    expect(position.watchlistItemId, 'us_stock:AAPL');
    expect(position.targetWeight.toString(), '0.8');
    expect(position.requiresExplicitHead, isTrue);
    expect(head.allocationVersionId, 'allocation-1');
    expect(allocation.requiresExplicitHead, isTrue);
    expect(allocation.isComplete, isTrue);
    expect(holding.quantity.toString(), '400');
    expect(holding.fxToBase.toString(), '1');
    expect(action.revisionHash, 'revision-1');
    expect(action.cashPerShare.toString(), '0.25');
    expect(action.eligibleQuantity.toString(), '100');
    expect(action.receivableGrossAmount, isNull);
    expect(action.paperCashGrossAmount.toString(), '25');
    expect(action.allocationBasisKey, 'alloc-v1:allocation-1');

    await db.customStatement('''
      INSERT INTO watchlist_simulation_observations (
        id, owner_user_id, simulation_id, observation_day, observed_at,
        projected_value, weighted_daily_change, priced_weight,
        missing_quote_weight, created_at, updated_at
      ) VALUES (
        'observation-1', '$_user', 'simulation-1', '2023-11-14',
        1700000000, '100000', '0', '0', '0.8', 1700000000, 1700000000
      )
    ''');
    final tombstoneVersion = _hlc(2_000);
    expect(
      await applier.applyAll([
        RowChange(
          table: prefixFinanceTable('watchlist_simulations'),
          id: 'simulation-1',
          payload: <String, Object?>{
            'id': 'simulation-1',
            'collection_id': 'collection-growth',
            'name': 'Growth paper mix',
            'base_currency': 'USD',
            'starting_capital': '100000',
            'cash_weight': '0.2',
            'calculation_mode': 'holdingsTotalReturnV2',
            'baseline_at': 1_700_000_000,
            'created_at': 1_700_000_000,
            'owner_user_id': _user,
            'updated_at': 1_700_000_500,
            'updated_by_device': _devB,
            'hlc': tombstoneVersion,
            'deleted_at': 1_700_000_500,
          },
          version: tombstoneVersion,
          deleted: true,
          deviceId: _devB,
        ),
      ]),
      1,
    );
    final observationCount = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM watchlist_simulation_observations',
        )
        .getSingle();
    expect(observationCount.read<int>('count'), 0);
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
