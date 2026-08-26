import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset_meta.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/persistence/test_database.dart';
import '../../../../../core/sync/_outbox_test_ext.dart';
import '../../../data/repositories/_stub_stamper.dart';

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
        currentValuation: Decimal.parse('40000'),
        annualResidualRate: Decimal.parse('0.82'),
      );

      expect(asset.name, 'Model 3');
      expect(asset.isVehicle, isTrue);
      expect(asset.purchasePrice, Decimal.parse('42000'));
      expect(asset.currentValuation, Decimal.parse('40000'));
      expect(asset.lastValuationAt, isNull);
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

  test(
    'updateValuation appends manual valuation history and sync pointer',
    () async {
      final asset = await repo.createVehicle(
        name: 'Car',
        currency: 'USD',
        purchaseDate: DateTime.utc(2023, 1, 1),
        purchasePrice: Decimal.parse('30000'),
      );

      await repo.updateValuation(
        assetId: asset.id,
        newValuation: Decimal.parse('24000'),
        asOf: DateTime.utc(2024, 1, 1),
        note: 'dealer quote',
      );

      final history = await repo.getValuationHistory(asset.id);
      expect(history.map((p) => p.kind), [
        ValuationPointKind.purchase,
        ValuationPointKind.manual,
        ValuationPointKind.manual,
      ]);
      expect(history.last.value, Decimal.parse('24000'));
      final updated = await repo.getById(asset.id);
      expect(updated?.currentValuation, Decimal.parse('24000'));
      expect(updated?.lastValuationAt, DateTime.utc(2024, 1, 1));
      expect(
        history.last.asOf.isAtSameMomentAs(DateTime.utc(2024, 1, 1)),
        isTrue,
      );
      expect(history.last.note, 'dealer quote');

      expect(outbox.queued.last.table, 'prices');
    },
  );

  test('updateValuation rejects missing or deleted assets', () async {
    await expectLater(
      repo.updateValuation(
        assetId: 'missing',
        newValuation: Decimal.parse('1'),
        asOf: DateTime.utc(2024, 1, 1),
      ),
      throwsStateError,
    );

    final beforePurchase = await repo.createVehicle(
      name: 'Future car',
      currency: 'USD',
      purchaseDate: DateTime.utc(2023, 1, 1),
      purchasePrice: Decimal.parse('30000'),
    );
    await expectLater(
      repo.updateValuation(
        assetId: beforePurchase.id,
        newValuation: Decimal.parse('29000'),
        asOf: DateTime.utc(2022, 12, 31),
      ),
      throwsArgumentError,
    );

    final asset = await repo.createVehicle(
      name: 'Car',
      currency: 'USD',
      purchaseDate: DateTime.utc(2023, 1, 1),
      purchasePrice: Decimal.parse('30000'),
    );
    await repo.delete(asset.id);

    await expectLater(
      repo.updateValuation(
        assetId: asset.id,
        newValuation: Decimal.parse('1'),
        asOf: DateTime.utc(2024, 1, 1),
      ),
      throwsStateError,
    );
  });

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
