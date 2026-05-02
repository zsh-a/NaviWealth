import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test(
    'createCash inserts a cash row, seeds a genesis valuationAdjust '
    'transaction, and enqueues both ops',
    () async {
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
      expect(batch.map((o) => o.tableName).toList(),
          unorderedEquals(<String>['assets', 'transactions']));
      final assetOp = batch.firstWhere((o) => o.tableName == 'assets');
      expect(assetOp.opType, OpType.insert);
      final txOp = batch.firstWhere((o) => o.tableName == 'transactions');
      expect(txOp.opType, OpType.insert);
      expect(txOp.fieldsDiff!['type'], 'valuationAdjust');
      expect(txOp.fieldsDiff!['quantity'], '0');
      expect(txOp.fieldsDiff!['price'], '1234.56');
    },
  );

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

  test(
    'recordValuationAdjust appends a transaction event and refreshes the '
    'denormalized last_price cache',
    () async {
      final asset = await repo.createCash(
        accountId: 'acc-1',
        currency: 'USD',
        balance: Decimal.parse('100'),
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      await repo.recordValuationAdjust(
        assetId: asset.id,
        newValuation: Decimal.parse('150'),
      );
      final reloaded = await repo.findById(asset.id);
      expect(reloaded!.lastPrice, Decimal.parse('150'));

      // Two ops: the assets cache update and the appended transaction row.
      final batch = await outbox.peekBatch();
      expect(batch.map((o) => o.tableName).toList(), unorderedEquals(<String>['assets', 'transactions']));

      final assetOp = batch.firstWhere((o) => o.tableName == 'assets');
      expect(assetOp.opType, OpType.update);
      final assetDiff = assetOp.fieldsDiff!;
      expect(assetDiff['last_price'], '150');
      expect(assetDiff.containsKey('metadata_json'), isFalse);
      expect(assetDiff.containsKey('name'), isFalse);

      final txOp = batch.firstWhere((o) => o.tableName == 'transactions');
      expect(txOp.opType, OpType.insert);
      final txDiff = txOp.fieldsDiff!;
      expect(txDiff['type'], 'valuationAdjust');
      expect(txDiff['quantity'], '0');
      expect(txDiff['price'], '150');
      expect(txDiff['account_id'], 'acc-1');
      expect(txDiff['asset_id'], asset.id);
    },
  );

  test(
    'three sequential recordValuationAdjust calls produce three '
    'transactions on the timeline (FIR-123 acceptance)',
    () async {
      final asset = await repo.createWealthProduct(
        accountId: 'acc-1',
        name: '稳健 30 天',
        currency: 'CNY',
        principal: Decimal.parse('100'),
        expectedAnnualReturn: Decimal.parse('0.04'),
      );
      // The createWealthProduct call already seeded a genesis valuationAdjust
      // event at price = 100. Subsequent record* calls append additional
      // rows so the full timeline is replayable.
      await repo.recordValuationAdjust(
        assetId: asset.id,
        newValuation: Decimal.parse('200'),
        asOf: DateTime.utc(2026, 4, 2),
      );
      await repo.recordValuationAdjust(
        assetId: asset.id,
        newValuation: Decimal.parse('250'),
        asOf: DateTime.utc(2026, 4, 3),
      );

      final txRows = await (db.select(db.transactions)
            ..where(
              (t) => t.assetId.equals(asset.id) &
                  t.type.equalsValue(TransactionType.valuationAdjust),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.tradeDate)]))
          .get();
      expect(txRows.map((r) => r.price.toString()).toList(),
          ['100', '200', '250']);
      expect(txRows.every((r) => r.quantity == Decimal.zero), isTrue);

      final reloaded = await repo.findById(asset.id);
      expect(reloaded!.lastPrice, Decimal.parse('250'));
    },
  );

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
