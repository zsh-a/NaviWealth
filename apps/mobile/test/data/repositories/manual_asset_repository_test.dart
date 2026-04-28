import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ManualAssetRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = ManualAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('createCash inserts a cash row and enqueues an op', () async {
    final asset = await repo.createCash(
      accountId: 'acc-1',
      currency: 'CNY',
      balance: Decimal.parse('1234.56'),
    );

    expect(asset.type, AssetType.cash);
    expect(asset.currency, 'CNY');
    expect(asset.lastPrice, Decimal.parse('1234.56'));
    final meta = asset.manualMetadata;
    expect(meta, isA<CashMetadata>());
    expect((meta as CashMetadata).accountId, 'acc-1');

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.insert);
    expect(batch.single.tableName, 'assets');
  });

  test('createDeposit persists rate + dates inside metadata blob', () async {
    final asset = await repo.createDeposit(
      accountId: 'acc-1',
      type: AssetType.bankDepositTerm,
      name: '招行 1 年期定期',
      currency: 'CNY',
      principal: Decimal.parse('50000'),
      interestRate: Decimal.parse('0.0325'),
      startDate: DateTime.utc(2026, 1, 1),
      maturityDate: DateTime.utc(2027, 1, 1),
      autoRenew: true,
    );
    expect(asset.type, AssetType.bankDepositTerm);
    final meta = asset.manualMetadata;
    expect(meta, isA<DepositMetadata>());
    final dep = meta! as DepositMetadata;
    expect(dep.principal, Decimal.parse('50000'));
    expect(dep.interestRate, Decimal.parse('0.0325'));
    expect(dep.startDate, DateTime.utc(2026, 1, 1));
    expect(dep.maturityDate, DateTime.utc(2027, 1, 1));
    expect(dep.autoRenew, isTrue);
  });

  test('createWealthProduct survives encode/decode roundtrip', () async {
    final asset = await repo.createWealthProduct(
      accountId: 'acc-1',
      name: '招银理财稳健 30 天',
      currency: 'CNY',
      principal: Decimal.parse('100000'),
      expectedAnnualReturn: Decimal.parse('0.045'),
      issuer: '招银理财',
      productCode: 'CMBWM-001',
      startDate: DateTime.utc(2026, 4, 1),
    );
    final meta = asset.manualMetadata;
    expect(meta, isA<WealthProductMetadata>());
    final wp = meta! as WealthProductMetadata;
    expect(wp.principal, Decimal.parse('100000'));
    expect(wp.expectedAnnualReturn, Decimal.parse('0.045'));
    expect(wp.issuer, '招银理财');
    expect(wp.productCode, 'CMBWM-001');
    expect(asset.symbol, 'CMBWM-001');
  });

  test('updateValuation only diffs price + sync metadata', () async {
    final asset = await repo.createCash(
      accountId: 'acc-1',
      currency: 'USD',
      balance: Decimal.parse('100'),
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.updateValuation(
      id: asset.id,
      newValuation: Decimal.parse('150'),
    );
    final reloaded = await repo.findById(asset.id);
    expect(reloaded!.lastPrice, Decimal.parse('150'));

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.update);
    final diff = batch.single.fieldsDiff!;
    expect(diff['last_price'], '150');
    expect(diff.containsKey('metadata_json'), isFalse);
    expect(diff.containsKey('name'), isFalse);
  });

  test('updateMetadata replaces the typed blob', () async {
    final asset = await repo.createDeposit(
      accountId: 'acc-1',
      type: AssetType.bankDepositTerm,
      name: 'Original',
      currency: 'CNY',
      principal: Decimal.parse('1000'),
      interestRate: Decimal.parse('0.02'),
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final newMeta = (asset.manualMetadata! as DepositMetadata).copyWith(
      interestRate: Decimal.parse('0.025'),
      maturityDate: DateTime.utc(2028, 1, 1),
    );
    await repo.updateMetadata(id: asset.id, metadata: newMeta);

    final reloaded = await repo.findById(asset.id);
    final reloadedMeta = reloaded!.manualMetadata! as DepositMetadata;
    expect(reloadedMeta.interestRate, Decimal.parse('0.025'));
    expect(reloadedMeta.maturityDate, DateTime.utc(2028, 1, 1));

    final batch = await outbox.peekBatch();
    expect(batch.single.fieldsDiff!.containsKey('metadata_json'), isTrue);
    expect(batch.single.fieldsDiff!.containsKey('last_price'), isFalse);
  });

  test('softDelete tombstones the asset and queues a delete op', () async {
    final asset = await repo.createCash(
      accountId: 'acc-1',
      currency: 'JPY',
      balance: Decimal.parse('10000'),
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(asset.id);
    final reloaded = await repo.findById(asset.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.delete);
    expect(batch.single.fieldsDiff, isNull);
  });

  test('watchManual filters to no-market-data asset types', () async {
    await repo.createCash(
      accountId: 'a1',
      currency: 'CNY',
      balance: Decimal.parse('1000'),
    );
    await repo.createDeposit(
      accountId: 'a2',
      type: AssetType.bankDepositDemand,
      name: 'demand',
      currency: 'CNY',
      principal: Decimal.parse('500'),
      interestRate: Decimal.parse('0.001'),
    );

    final stream = repo.watchManual();
    final first = await stream.first;
    expect(first.length, 2);
    expect(first.map((a) => a.type).toSet(), {
      AssetType.cash,
      AssetType.bankDepositDemand,
    });
  });
}
