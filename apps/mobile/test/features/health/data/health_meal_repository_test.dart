import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/owner_data_migration.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:naviwealth/features/health/data/health_meal_repository.dart';
import 'package:naviwealth/features/health/data/meal_food_catalog.dart';
import 'package:naviwealth/features/health/domain/health_meal.dart';
import 'package:naviwealth/features/health/domain/meal_photo.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _FailingOutbox extends DriftOutboxStore {
  _FailingOutbox(super.db);
  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    await super.enqueue(table: table, rowId: rowId);
    throw StateError('failed');
  }
}

void main() {
  final now = DateTime(2026, 10, 28, 12);
  final foods = [mealFoodCatalog.first.portion(200)];
  late AppDatabase db;
  late HealthMealRepository repo;
  var enabled = true;
  setUp(() {
    enabled = true;
    db = makeTestDatabase();
    repo = HealthMealRepository(
      db: db,
      outbox: DriftOutboxStore(db),
      stamper: makeStubStamper(userId: 'user'),
      clock: () => now,
      writesAllowed: (_) => enabled,
    );
  });
  tearDown(() => db.close());

  Future<HealthMeal> save({
    Uint8List? photo,
    DateTime? day,
    List<MealPhoto>? photos,
  }) => repo.save(
    expectedOwnerUserId: 'user',
    capturedAt: now,
    day: day ?? now,
    type: HealthMealType.lunch,
    foods: foods,
    photoBytes: photo,
    photos: photos,
  );

  test(
    'meal views retain order, roles and times and replace atomically',
    () async {
      final entry = await save(
        photos: [
          MealPhoto(
            bytes: Uint8List.fromList([1]),
            role: MealPhotoRole.side,
            timestampMs: 500,
          ),
          MealPhoto(bytes: Uint8List.fromList([2]), role: MealPhotoRole.label),
          MealPhoto(
            bytes: Uint8List.fromList([3]),
            role: MealPhotoRole.afterMeal,
          ),
        ],
      );
      final views = await repo.photos(id: entry.id, ownerUserId: 'user');
      expect(views.map((view) => view.role), [
        MealPhotoRole.side,
        MealPhotoRole.label,
        MealPhotoRole.afterMeal,
      ]);
      expect(views.first.timestampMs, 500);
      expect(await repo.photos(id: entry.id, ownerUserId: 'other'), isEmpty);
      await repo.save(
        id: entry.id,
        expectedRevision: entry.sync.hlc,
        expectedOwnerUserId: 'user',
        capturedAt: now,
        day: now,
        type: entry.type,
        foods: foods,
        photos: [views.last, views.first.withRole(MealPhotoRole.overview)],
      );
      final revised = await repo.photos(id: entry.id, ownerUserId: 'user');
      expect(revised.map((view) => view.id), [views.last.id, views.first.id]);
      expect(revised.last.role, MealPhotoRole.overview);
      final current = (await repo.find(id: entry.id, ownerUserId: 'user'))!;
      await repo.delete(current);
      expect(await db.select(db.healthMealPhotos).get(), isEmpty);
    },
  );

  test(
    'photos from another meal cannot be reassigned; invalid sets do not write',
    () async {
      final first = await save(photo: Uint8List.fromList([1]));
      final foreign = (await repo.photos(
        id: first.id,
        ownerUserId: 'user',
      )).single;
      final second = await save(photo: Uint8List.fromList([2]));
      await expectLater(
        repo.save(
          id: second.id,
          expectedRevision: second.sync.hlc,
          expectedOwnerUserId: 'user',
          capturedAt: now,
          day: now,
          type: second.type,
          foods: foods,
          photos: [foreign],
        ),
        throwsStateError,
      );
      expect(await repo.photo(id: second.id, ownerUserId: 'user'), [2]);
      expect(await repo.photo(id: first.id, ownerUserId: 'user'), [1]);
      for (final views in [
        List.generate(5, (_) => MealPhoto(bytes: Uint8List.fromList([1]))),
        [foreign, foreign],
        [
          MealPhoto(bytes: Uint8List.fromList([1]), timestampMs: 10001),
        ],
      ]) {
        await expectLater(save(photos: views), throwsArgumentError);
      }
      expect((await db.select(db.healthMeals).get()).length, 2);
    },
  );

  test('separate meals share a day, edit snapshots atomically and retain local photo', () async {
    final first = await save(photo: Uint8List.fromList([1, 2, 3]));
    final second = await save();
    expect(second.id, isNot(first.id));
    expect(first.total.kcal, 260);
    final changed = await repo.save(
      id: first.id,
      expectedRevision: first.sync.hlc,
      expectedOwnerUserId: 'user',
      capturedAt: now,
      day: now,
      type: first.type,
      foods: [mealFoodCatalog.first.portion(100)],
      note: 'half eaten',
    );
    expect(changed.total.kcal, 130);
    expect(await repo.photo(id: first.id, ownerUserId: 'user'), [1, 2, 3]);
    final rows = await repo
        .watchInRange(
          ownerUserId: 'user',
          from: now,
          to: now.add(const Duration(days: 1)),
        )
        .first;
    expect(rows.length, 2);
    expect(rows.fold(0.0, (sum, meal) => sum + meal.total.kcal), 390);
    expect(await repo.find(id: first.id, ownerUserId: 'other'), isNull);
    expect(await repo.photo(id: first.id, ownerUserId: 'other'), isNull);
    expect(await DriftOutboxStore(db).depth(), 3);
    await expectLater(
      repo.save(
        id: first.id,
        expectedRevision: first.sync.hlc,
        expectedOwnerUserId: 'user',
        capturedAt: now,
        day: now,
        type: first.type,
        foods: foods,
      ),
      throwsStateError,
    );
  });

  test(
    'invalid foods, future dates, wrong owner and disabled domain cannot write',
    () async {
      await expectLater(
        repo.save(
          expectedOwnerUserId: 'user',
          capturedAt: now,
          day: now,
          type: HealthMealType.lunch,
          foods: [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        save(day: now.add(const Duration(days: 1))),
        throwsArgumentError,
      );
      await expectLater(
        repo.save(
          expectedOwnerUserId: 'other',
          capturedAt: now,
          day: now,
          type: HealthMealType.lunch,
          foods: foods,
        ),
        throwsStateError,
      );
      for (final grams in [double.nan, double.infinity, -1.0, 0.0, 10001.0]) {
        await expectLater(
          repo.save(
            expectedOwnerUserId: 'user',
            capturedAt: now,
            day: now,
            type: HealthMealType.lunch,
            foods: [mealFoodCatalog.first.portion(grams)],
          ),
          throwsArgumentError,
        );
      }
      enabled = false;
      await expectLater(save(), throwsStateError);
      expect(await db.select(db.healthMeals).get(), isEmpty);
      expect(await DriftOutboxStore(db).depth(), 0);
    },
  );

  test('outbox failure rolls back meal, photo and dirty pointer', () async {
    final broken = HealthMealRepository(
      db: db,
      outbox: _FailingOutbox(db),
      stamper: makeStubStamper(userId: 'user'),
      clock: () => now,
    );
    await expectLater(
      broken.save(
        expectedOwnerUserId: 'user',
        capturedAt: now,
        day: now,
        type: HealthMealType.lunch,
        foods: foods,
        photoBytes: Uint8List.fromList([1]),
      ),
      throwsStateError,
    );
    expect(await db.select(db.healthMeals).get(), isEmpty);
    expect(await db.select(db.healthMealPhotos).get(), isEmpty);
    expect(await DriftOutboxStore(db).depth(), 0);
  });

  test('delete produces a tombstone and removes its local photo', () async {
    final entry = await save(photo: Uint8List.fromList([1]));
    await repo.delete(entry);
    expect(await repo.find(id: entry.id, ownerUserId: 'user'), isNull);
    expect(await db.select(db.healthMealPhotos).get(), isEmpty);
    final pending = await DriftPendingRows(db)
        .readRow('health_meals', entry.id);
    expect(pending!['deleted_at'], isNotNull);
    await expectLater(repo.delete(entry), throwsStateError);
    enabled = false;
    await expectLater(repo.delete(entry), throwsStateError);
  });

  test(
    'sync replays the complete meal after upgrade and excludes photo bytes',
    () async {
      final entry = await save(photo: Uint8List.fromList([7, 8, 9]));
      final payload = await DriftPendingRows(db)
          .readRow('health_meals', entry.id);
      expect(payload!.keys, isNot(contains('bytes')));
      expect(kSyncableTables, isNot(contains('health_meal_photos')));
      final target = makeTestDatabase();
      addTearDown(target.close);
      final change = RowChange(
        table: prefixTable('health_meals'),
        id: entry.id,
        payload: payload,
        version: entry.sync.hlc.toString(),
        deleted: false,
      );
      final old = RowApplier(
        target,
        ownerUserId: 'user',
        registrations: kSyncTableRegistrations
            .where((r) => r.table != 'health_meals')
            .toList(),
      );
      await old.prepareCompatibility();
      expect((await old.applyWithReport([change])).skippedUnsupportedTable, 1);
      final upgraded = RowApplier(target, ownerUserId: 'user');
      expect(await upgraded.prepareCompatibility(), true);
      expect(await upgraded.applyAll([change]), 1);
      final targetRepo = HealthMealRepository(
        db: target,
        outbox: DriftOutboxStore(target),
        stamper: makeStubStamper(userId: 'user'),
      );
      final restored = (await targetRepo.find(
        id: entry.id,
        ownerUserId: 'user',
      ))!;
      expect(restored.total.kcal, 260);
      expect(restored.foods.single.source, 'USDA FDC 168878');
      expect(await targetRepo.photo(id: entry.id, ownerUserId: 'user'), isNull);
    },
  );

  test('encrypted backups restore meals, omit photos, and older archives preserve meals', () async {
    final entry = await save(photo: Uint8List.fromList([1]));
    final codec = BackupCodec();
    final service = BackupService(
      db: db,
      codec: codec,
      outbox: DriftOutboxStore(db),
      ownerUserId: 'user',
    );
    final archive = await service.exportBackup(
      passphrase: 'meal-test',
      overrideIterations: 1000,
      domain: DomainScope.health,
    );
    final plaintext = await codec.decrypt(
      passphrase: 'meal-test',
      envelope: BackupEnvelope.decodeBytes(archive),
    );
    final payload = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    expect(
      (payload['data'] as Map<String, dynamic>).keys,
      isNot(contains('health_meal_photos')),
    );
    await repo.delete(entry);
    await service.restoreBackup(
      passphrase: 'meal-test',
      fileBytes: archive,
      expectedDomain: DomainScope.health,
    );
    expect(
      (await repo.find(id: entry.id, ownerUserId: 'user'))!.total.kcal,
      260,
    );
    expect(await repo.photo(id: entry.id, ownerUserId: 'user'), isNull);
    final header = payload['header'] as Map<String, dynamic>;
    header['schemaVersion'] = 99;
    (header['tables'] as Map<String, dynamic>).remove('health_meals');
    (payload['data'] as Map<String, dynamic>).remove('health_meals');
    final old = await codec.encrypt(
      passphrase: 'meal-test',
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      schemaVersion: 99,
      iterations: 1000,
    );
    await service.restoreBackup(
      passphrase: 'meal-test',
      fileBytes: old.encodeBytes(),
      expectedDomain: DomainScope.health,
    );
    expect(await repo.find(id: entry.id, ownerUserId: 'user'), isNotNull);
  });

  test('owner transfer keeps photo and meal together', () async {
    final entry = await save(photo: Uint8List.fromList([1]));
    await OwnerDataMigration(db).transfer(from: 'user', to: 'new-user');
    expect(await repo.find(id: entry.id, ownerUserId: 'user'), isNull);
    expect(
      (await repo.find(id: entry.id, ownerUserId: 'new-user'))!.total.kcal,
      260,
    );
    expect(await repo.photo(id: entry.id, ownerUserId: 'new-user'), [1]);
  });

  test(
    'a live owner or opt-in change while stamping prevents the write',
    () async {
      for (final changeOwner in [false, true]) {
        final gate = Completer<void>();
        var owner = 'user';
        enabled = true;
        final guarded = HealthMealRepository(
          db: db,
          outbox: DriftOutboxStore(db),
          clock: () => now,
          writesAllowed: (expected) => enabled && owner == expected,
          stamper: MutationStamper(
            currentUserId: () async => 'user',
            deviceId: () async => 'device',
            stampHlc: () async {
              await gate.future;
              return const Hlc(
                wallMillis: 1700000000000,
                counter: 0,
                nodeId: 'device',
              );
            },
          ),
        );
        final pending = guarded.save(
          expectedOwnerUserId: 'user',
          capturedAt: now,
          day: now,
          type: HealthMealType.lunch,
          foods: foods,
        );
        if (changeOwner) {
          owner = 'other';
        } else {
          enabled = false;
        }
        gate.complete();
        await expectLater(pending, throwsStateError);
        expect(await db.select(db.healthMeals).get(), isEmpty);
        expect(await DriftOutboxStore(db).depth(), 0);
      }
    },
  );

  test(
    'a remotely applied tombstone physically removes local photo bytes',
    () async {
      final entry = await save(photo: Uint8List.fromList([4, 5]));
      final version = Hlc(
        wallMillis: entry.sync.hlc.wallMillis + 100,
        counter: 0,
        nodeId: 'remote',
      );
      final payload = (await DriftPendingRows(db)
          .readRow('health_meals', entry.id))!;
      payload['deleted_at'] = now.millisecondsSinceEpoch ~/ 1000;
      final applier = RowApplier(db, ownerUserId: 'user');
      expect(
        await applier.applyAll([
          RowChange(
            table: prefixTable('health_meals'),
            id: entry.id,
            payload: payload,
            version: version.toString(),
            deleted: true,
          ),
        ]),
        1,
      );
      expect(await db.select(db.healthMealPhotos).get(), isEmpty);
    },
  );
}
