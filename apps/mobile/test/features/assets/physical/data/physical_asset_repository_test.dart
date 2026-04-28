import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_repository.dart';
import 'package:naviwealth/features/assets/physical/data/sync_stamper.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/db/test_database.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late InMemoryCursorStore cursors;
  late PhysicalAssetRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    cursors = InMemoryCursorStore();
    repo = PhysicalAssetRepository(
      db: db,
      stamper: SyncStamper(
        db: db,
        cursors: cursors,
        outbox: outbox,
        userId: 'u1',
        deviceId: 'd1',
      ),
      uuid: const Uuid(),
    );
  });

  tearDown(() => db.close());

  group('createRealEstate', () {
    test('persists row and enqueues an insert op', () async {
      final created = await repo.createRealEstate(
        name: 'Beijing Apt',
        address: '北京市朝阳区',
        currency: 'CNY',
        purchaseDate: DateTime.utc(2024, 1, 1),
        purchasePrice: Decimal.fromInt(2000000),
        linkedLiabilityId: 'liab-1',
      );

      expect(created.type, AssetType.realEstate);
      expect(created.name, 'Beijing Apt');
      expect(created.address, '北京市朝阳区');
      expect(created.purchasePrice, Decimal.fromInt(2000000));
      expect(created.currentValuation, Decimal.fromInt(2000000));
      expect(created.linkedLiabilityId, 'liab-1');

      final list = await repo.listAll();
      expect(list, hasLength(1));
      expect(list.first.id, created.id);

      expect(await outbox.depth(), 1);
      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.first.tableName, 'assets');
      expect(ops.first.opType.name, 'insert');
      expect(ops.first.fieldsDiff!['type'], 'realEstate');
    });
  });

  group('createVehicle', () {
    test('stores residual rate and depreciation flag in metadata', () async {
      final created = await repo.createVehicle(
        name: 'Tesla',
        currency: 'USD',
        purchaseDate: DateTime.utc(2023, 1, 1),
        purchasePrice: Decimal.fromInt(60000),
        annualResidualRate: Decimal.parse('0.85'),
      );
      expect(created.annualResidualRate, Decimal.parse('0.85'));
      expect(created.autoDepreciation, isTrue);
      expect(created.type, AssetType.vehicle);
    });
  });

  group('updateValuation', () {
    test(
      'bumps lastPrice, inserts valuationAdjust transaction, enqueues '
      'two ops',
      () async {
        final created = await repo.createRealEstate(
          name: 'Apt',
          currency: 'CNY',
          purchaseDate: DateTime.utc(2024, 1, 1),
          purchasePrice: Decimal.fromInt(2000000),
        );
        await outbox.ack((await outbox.peekBatch()).map((o) => o.opId));

        await repo.updateValuation(
          assetId: created.id,
          newValuation: Decimal.fromInt(2200000),
          asOf: DateTime.utc(2026, 1, 1),
          note: 'spring 2026',
        );

        final reread = await repo.getById(created.id);
        expect(reread!.currentValuation, Decimal.fromInt(2200000));

        final txRows = await db.select(db.transactions).get();
        expect(txRows, hasLength(1));
        expect(txRows.first.type, TransactionType.valuationAdjust);
        expect(txRows.first.price, Decimal.fromInt(2200000));
        expect(txRows.first.assetId, created.id);
        expect(txRows.first.note, 'spring 2026');

        final ops = await outbox.peekBatch();
        expect(ops, hasLength(2));
        expect(ops.map((o) => o.tableName).toSet(), {'assets', 'transactions'});
      },
    );

    test('throws when asset is missing', () async {
      expect(
        () => repo.updateValuation(
          assetId: 'nope',
          newValuation: Decimal.fromInt(1),
          asOf: DateTime.utc(2026, 1, 1),
        ),
        throwsStateError,
      );
    });
  });

  group('getValuationHistory', () {
    test('seeds with a purchase point and appends manual updates', () async {
      final created = await repo.createVehicle(
        name: 'Car',
        currency: 'USD',
        purchaseDate: DateTime.utc(2024, 1, 1),
        purchasePrice: Decimal.fromInt(60000),
        annualResidualRate: Decimal.parse('0.85'),
      );
      await repo.updateValuation(
        assetId: created.id,
        newValuation: Decimal.fromInt(50000),
        asOf: DateTime.utc(2025, 1, 1),
      );
      await repo.updateValuation(
        assetId: created.id,
        newValuation: Decimal.fromInt(45000),
        asOf: DateTime.utc(2026, 1, 1),
      );

      final hist = await repo.getValuationHistory(created.id);
      expect(hist, hasLength(3));
      expect(hist.first.value, Decimal.fromInt(60000));
      expect(hist.last.value, Decimal.fromInt(45000));
      // Sorted ascending by tradeDate.
      for (var i = 1; i < hist.length; i++) {
        expect(
          !hist[i].asOf.isBefore(hist[i - 1].asOf),
          isTrue,
        );
      }
    });
  });

  group('delete', () {
    test('soft-deletes the row and enqueues a delete op', () async {
      final created = await repo.createRealEstate(
        name: 'Apt',
        currency: 'CNY',
        purchaseDate: DateTime.utc(2024, 1, 1),
        purchasePrice: Decimal.fromInt(1000000),
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId));

      await repo.delete(created.id);
      expect(await repo.listAll(), isEmpty);
      expect(await repo.getById(created.id), isNull);

      // The row still exists physically — sync needs to ship the delete.
      final raw = await (db.select(db.assets)
            ..where((t) => t.id.equals(created.id)))
          .getSingle();
      expect(raw.deletedAt, isNotNull);

      final ops = await outbox.peekBatch();
      expect(ops, hasLength(1));
      expect(ops.first.opType.name, 'delete');
      expect(ops.first.fieldsDiff, isNull);
    });
  });

  group('updateMetadata', () {
    test('rewrites metadataJson without touching valuation', () async {
      final created = await repo.createRealEstate(
        name: 'Apt',
        currency: 'CNY',
        purchaseDate: DateTime.utc(2024, 1, 1),
        purchasePrice: Decimal.fromInt(2000000),
        currentValuation: Decimal.fromInt(2100000),
      );
      final updatedMeta = created.meta.copyWith(address: 'New street');
      await repo.updateMetadata(
        assetId: created.id,
        meta: updatedMeta,
        name: 'Renamed',
      );

      final reread = await repo.getById(created.id);
      expect(reread!.address, 'New street');
      expect(reread.name, 'Renamed');
      // Valuation must be unchanged.
      expect(reread.currentValuation, Decimal.fromInt(2100000));
    });
  });

  test('listAll filters out non-physical asset types', () async {
    // Insert a stock manually — must not appear in physical listing.
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: 'stk-1',
            type: AssetType.stock,
            symbol: 'AAPL',
            currency: 'USD',
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd1'),
          ),
        );
    final list = await repo.listAll();
    expect(list, isEmpty);
  });
}
