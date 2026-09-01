import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

const _user = 'u-test';
const _simulationId = 'simulation-concurrent';
const _deviceA = 'device-a';
const _deviceB = 'device-b';

String _hlc(int wall, String device) =>
    Hlc(wallMillis: wall, counter: 0, nodeId: device).toString();

RowChange _change({
  required String table,
  required String id,
  required Map<String, Object?> payload,
  required String version,
  required String device,
}) => RowChange(
  table: prefixFinanceTable(table),
  id: id,
  payload: payload,
  version: version,
  deleted: false,
  deviceId: device,
);

Map<String, Object?> _syncPayload({
  required String id,
  required String device,
  required String hlc,
  required Map<String, Object?> fields,
}) => <String, Object?>{
  'id': id,
  ...fields,
  'owner_user_id': _user,
  'updated_at': 1_700_000_000,
  'updated_by_device': device,
  'hlc': hlc,
  'deleted_at': null,
};

List<RowChange> _baseChanges() {
  final version = _hlc(1_000, _deviceA);
  return [
    _change(
      table: 'watchlist_simulations',
      id: _simulationId,
      version: version,
      device: _deviceA,
      payload: _syncPayload(
        id: _simulationId,
        device: _deviceA,
        hlc: version,
        fields: const {
          'collection_id': 'collection-1',
          'name': 'Concurrent simulation',
          'base_currency': 'USD',
          'starting_capital': '1000',
          'cash_weight': '0.4',
          'calculation_mode': 'holdingsTotalReturnV2',
          'baseline_at': 1_700_000_000,
          'created_at': 1_700_000_000,
        },
      ),
    ),
    _change(
      table: 'watchlist_simulation_allocation_versions',
      id: 'allocation-base',
      version: version,
      device: _deviceA,
      payload: _syncPayload(
        id: 'allocation-base',
        device: _deviceA,
        hlc: version,
        fields: const {
          'simulation_id': _simulationId,
          'effective_at': 1_700_000_000,
          'reason': 'creation',
          'previous_allocation_version_id': null,
          'requires_explicit_head': true,
          'cash_weight': '0.4',
          'is_complete': true,
          'created_at': 1_700_000_000,
        },
      ),
    ),
    _holdingChange(
      id: 'holding-base-aapl',
      allocationId: 'allocation-base',
      itemId: 'us_stock:AAPL',
      symbol: 'AAPL',
      targetWeight: '0.6',
      version: version,
      device: _deviceA,
    ),
    _headChange(
      allocationId: 'allocation-base',
      version: version,
      device: _deviceA,
    ),
  ];
}

RowChange _holdingChange({
  required String id,
  required String allocationId,
  required String itemId,
  required String symbol,
  required String targetWeight,
  required String version,
  required String device,
}) => _change(
  table: 'watchlist_simulation_holding_versions',
  id: id,
  version: version,
  device: device,
  payload: _syncPayload(
    id: id,
    device: device,
    hlc: version,
    fields: {
      'allocation_version_id': allocationId,
      'simulation_id': _simulationId,
      'watchlist_item_id': itemId,
      'symbol': symbol,
      'market': 'us_stock',
      'target_weight': targetWeight,
      'quantity': null,
      'raw_price': null,
      'price_currency': null,
      'price_as_of': null,
      'price_source': null,
      'fx_to_base': null,
      'effective_at': 1_700_000_100,
      'created_at': 1_700_000_100,
    },
  ),
);

RowChange _headChange({
  required String allocationId,
  required String version,
  required String device,
}) => _change(
  table: 'watchlist_simulation_allocation_heads',
  id: _simulationId,
  version: version,
  device: device,
  payload: _syncPayload(
    id: _simulationId,
    device: device,
    hlc: version,
    fields: {
      'simulation_id': _simulationId,
      'allocation_version_id': allocationId,
      'created_at': 1_700_000_000,
    },
  ),
);

List<RowChange> _branchChanges({
  required String allocationId,
  required String itemId,
  required String symbol,
  required String targetWeight,
  required String cashWeight,
  required String device,
}) {
  final version = _hlc(2_000, device);
  return [
    _change(
      table: 'watchlist_simulation_allocation_versions',
      id: allocationId,
      version: version,
      device: device,
      payload: _syncPayload(
        id: allocationId,
        device: device,
        hlc: version,
        fields: {
          'simulation_id': _simulationId,
          'effective_at': 1_700_000_100,
          'reason': 'reallocation',
          'previous_allocation_version_id': 'allocation-base',
          'requires_explicit_head': true,
          'cash_weight': cashWeight,
          'is_complete': true,
          'created_at': 1_700_000_100,
        },
      ),
    ),
    _holdingChange(
      id: 'holding-$allocationId',
      allocationId: allocationId,
      itemId: itemId,
      symbol: symbol,
      targetWeight: targetWeight,
      version: version,
      device: device,
    ),
    _headChange(allocationId: allocationId, version: version, device: device),
  ];
}

void main() {
  test('two devices converge on one atomic allocation head', () async {
    final dbA = makeTestDatabase();
    final dbB = makeTestDatabase();
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final applierA = RowApplier(dbA);
    final applierB = RowApplier(dbB);
    await applierA.applyAll(_baseChanges());
    await applierB.applyAll(_baseChanges());

    final branchA = _branchChanges(
      allocationId: 'allocation-a',
      itemId: 'us_stock:AAPL',
      symbol: 'AAPL',
      targetWeight: '0.7',
      cashWeight: '0.3',
      device: _deviceA,
    );
    final branchB = _branchChanges(
      allocationId: 'allocation-b',
      itemId: 'us_stock:MSFT',
      symbol: 'MSFT',
      targetWeight: '0.5',
      cashWeight: '0.5',
      device: _deviceB,
    );
    await applierA.applyAll(branchA);
    await applierB.applyAll(branchB);
    await applierA.applyAll(branchB);
    await applierB.applyAll(branchA.reversed.toList());

    Future<ResolvedWatchlistSimulationAllocation> resolve(AppDatabase db) {
      return WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      ).resolveAllocation(ownerUserId: _user, simulationId: _simulationId);
    }

    final resolvedA = await resolve(dbA);
    final resolvedB = await resolve(dbB);
    for (final resolved in [resolvedA, resolvedB]) {
      expect(resolved.status, WatchlistSimulationAllocationStatus.selected);
      expect(resolved.allocationVersionId, 'allocation-b');
      expect(resolved.cashWeight, Decimal.parse('0.5'));
      expect(resolved.positions, hasLength(1));
      expect(resolved.positions.single.watchlistItemId, 'us_stock:MSFT');
      expect(
        resolved.cashWeight! + resolved.positions.single.targetWeight,
        Decimal.one,
      );
    }
  });

  test(
    'head-first sync stays pending until the snapshot is complete',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final applier = RowApplier(db);
      await applier.applyAll(_baseChanges());
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      final branch = _branchChanges(
        allocationId: 'allocation-b',
        itemId: 'us_stock:MSFT',
        symbol: 'MSFT',
        targetWeight: '0.5',
        cashWeight: '0.5',
        device: _deviceB,
      );

      await applier.applyAll([branch.last]);
      expect(
        (await repository.resolveAllocation(
          ownerUserId: _user,
          simulationId: _simulationId,
        )).status,
        WatchlistSimulationAllocationStatus.pending,
      );

      await applier.applyAll([branch.first]);
      expect(
        (await repository.resolveAllocation(
          ownerUserId: _user,
          simulationId: _simulationId,
        )).status,
        WatchlistSimulationAllocationStatus.pending,
      );

      await applier.applyAll([branch[1]]);
      final selected = await repository.resolveAllocation(
        ownerUserId: _user,
        simulationId: _simulationId,
      );
      expect(selected.status, WatchlistSimulationAllocationStatus.selected);
      expect(selected.allocationVersionId, 'allocation-b');
      expect(selected.positions.single.watchlistItemId, 'us_stock:MSFT');
    },
  );
}
