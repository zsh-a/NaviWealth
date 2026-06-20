import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_meta.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../../../features/finance/data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late PhysicalAssetRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    final priceRepo = PriceRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      uuid: const Uuid(),
    );
    repo = PhysicalAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      priceRepo: priceRepo,
      uuid: const Uuid(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'createVehicle stores metadata, price history, and sync pointers',
    () async {
      final purchaseDate = DateTime.utc(2024, 1, 2);
      final asset = await repo.createVehicle(
        name: 'Model 3',
        currency: 'USD',
        purchaseDate: purchaseDate,
        purchasePrice: Decimal.parse('42000'),
        annualResidualRate: Decimal.parse('0.82'),
      );

      expect(asset.name, 'Model 3');
      expect(asset.isVehicle, isTrue);
      expect(asset.purchasePrice, Decimal.parse('42000'));
      expect(asset.annualResidualRate, Decimal.parse('0.82'));

      final history = await repo.getValuationHistory(asset.id);
      expect(history, hasLength(2));
      expect(history.first.kind, ValuationPointKind.purchase);
      expect(history.first.value, Decimal.parse('42000'));
      expect(history.last.kind, ValuationPointKind.manual);
      expect(history.last.asOf.isAtSameMomentAs(purchaseDate), isTrue);

      expect(
        outbox.queued.map((op) => op.table),
        containsAll(['assets', 'prices']),
      );
    },
  );

  test(
    'updateMetadata updates fields without adding valuation history',
    () async {
      final asset = await repo.createRealEstate(
        name: 'Apartment',
        address: 'Old address',
        currency: 'CNY',
        purchaseDate: DateTime.utc(2020, 5, 1),
        purchasePrice: Decimal.parse('1000000'),
      );
      final before = await repo.getValuationHistory(asset.id);

      await repo.updateMetadata(
        assetId: asset.id,
        name: 'Apartment A',
        meta: PhysicalAssetMeta(
          address: 'New address',
          purchaseDate: asset.purchaseDate,
          purchasePrice: asset.purchasePrice,
        ),
      );

      final updated = await repo.getById(asset.id);
      expect(updated?.name, 'Apartment A');
      expect(updated?.address, 'New address');
      expect(
        await repo.getValuationHistory(asset.id),
        hasLength(before.length),
      );
      expect(outbox.queued.last.table, 'assets');
      expect(outbox.queued.last.rowId, asset.id);
    },
  );

  test('delete tombstones physical asset and hides it from reads', () async {
    final asset = await repo.createVehicle(
      name: 'Car',
      currency: 'USD',
      purchaseDate: DateTime.utc(2023),
      purchasePrice: Decimal.parse('30000'),
    );

    await repo.delete(asset.id);

    expect(await repo.getById(asset.id), isNull);
    expect(await repo.listAll(), isEmpty);
    expect(outbox.queued.last.table, 'assets');
    expect(outbox.queued.last.rowId, asset.id);
  });
}
