import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:naviwealth/features/health/data/health_check_in_repository.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _FailingOutbox extends DriftOutboxStore {
  _FailingOutbox(super.db);
  @override
  Future<void> enqueue({required String table, required String rowId}) async {
    await super.enqueue(table: table, rowId: rowId);
    throw StateError('write failed');
  }
}

void main() {
  final now = DateTime(2026, 10, 1, 12);
  late AppDatabase db;
  late HealthCheckInRepository repo;
  setUp(() {
    db = makeTestDatabase();
    repo = HealthCheckInRepository(
      db: db,
      outbox: DriftOutboxStore(db),
      stamper: makeStubStamper(userId: 'user'),
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  test(
    'save/edit one calendar date reuses id and preserves optional fields',
    () async {
      final first = await repo.save(
        day: now,
        energy: 4,
        tags: ['travel', 'future_tag', 'travel'],
        note: '  Jet lag  ',
      );
      final edited = await repo.save(
        day: now,
        energy: 3,
        sleepQuality: 2,
        stress: 4,
        tags: first.tags,
        note: first.note,
      );
      expect(edited.id, first.id);
      expect(edited.note, 'Jet lag');
      expect(edited.tags, ['future_tag', 'travel']);
      expect((await db.select(db.healthCheckIns).get()).length, 1);
      expect(await DriftOutboxStore(db).depth(), 2);
      expect(await repo.findDay(ownerUserId: 'other', day: now), isNull);
      final entries = await repo
          .watchInRange(
            ownerUserId: 'user',
            from: DateTime.utc(2026, 9, 30),
            to: DateTime.utc(2026, 10, 2),
          )
          .first;
      expect(entries.single.day, DateTime.utc(2026, 10, 1));
    },
  );
  test(
    'invalid, empty, future and changed-owner writes do not create rows',
    () async {
      await expectLater(repo.save(day: now), throwsArgumentError);
      await expectLater(repo.save(day: now, energy: 6), throwsArgumentError);
      await expectLater(
        repo.save(day: now.add(const Duration(days: 1)), energy: 3),
        throwsArgumentError,
      );
      await expectLater(
        repo.save(day: now, energy: 3, expectedOwnerUserId: 'other'),
        throwsStateError,
      );
      expect(await db.select(db.healthCheckIns).get(), isEmpty);
      expect(await DriftOutboxStore(db).depth(), 0);
    },
  );
  test('outbox failure rolls back both the entry and dirty pointer', () async {
    final broken = HealthCheckInRepository(
      db: db,
      outbox: _FailingOutbox(db),
      stamper: makeStubStamper(userId: 'user'),
      clock: () => now,
    );
    await expectLater(broken.save(day: now, energy: 4), throwsStateError);
    expect(await db.select(db.healthCheckIns).get(), isEmpty);
    expect(await DriftOutboxStore(db).depth(), 0);
  });
  test('delete is synced and a later save revives the same date id', () async {
    final entry = await repo.save(day: now, energy: 4);
    await repo.delete(entry);
    expect(await repo.findDay(ownerUserId: 'user', day: now), isNull);
    final pending = DriftPendingRows(db, ownerUserId: 'user');
    expect(
      (await pending.readRow('health_check_ins', entry.id))!['deleted_at'],
      isNotNull,
    );
    expect((await repo.save(day: now, stress: 2)).id, entry.id);
  });
  test(
    'migrated duplicate dates respect HLC tombstones despite wall-clock drift',
    () async {
      final entry = await repo.save(day: now, energy: 4);
      final row = (await db.select(db.healthCheckIns).get()).single;
      await db
          .into(db.healthCheckIns)
          .insert(
            row.copyWith(
              id: 'legacy-device-id',
              updatedAt: now.add(const Duration(days: 10)),
              hlc: Hlc(
                wallMillis: entry.sync.hlc.wallMillis - 1,
                counter: 0,
                nodeId: 'old',
              ),
            ),
          );
      await repo.delete(entry);
      expect(await repo.findDay(ownerUserId: 'user', day: now), isNull);
      expect(
        await repo
            .watchInRange(
              ownerUserId: 'user',
              from: now,
              to: now.add(const Duration(days: 1)),
            )
            .first,
        isEmpty,
      );
      expect((await repo.save(day: now, stress: 2)).id, entry.id);
    },
  );
  test('sync applies a new family and older clients can replay previously skipped rows', () async {
    final entry = await repo.save(
      day: now,
      energy: 4,
      tags: ['caffeine'],
      note: 'Afternoon coffee',
    );
    final payload = await DriftPendingRows(db)
        .readRow('health_check_ins', entry.id);
    final target = makeTestDatabase();
    addTearDown(target.close);
    final change = RowChange(
      table: prefixTable('health_check_ins'),
      id: entry.id,
      payload: payload,
      version: entry.sync.hlc.toString(),
      deleted: false,
    );
    final oldApplier = RowApplier(
      target,
      ownerUserId: 'user',
      registrations: kSyncTableRegistrations
          .where((r) => r.table != 'health_check_ins')
          .toList(),
    );
    await oldApplier.prepareCompatibility();
    expect(
      (await oldApplier.applyWithReport([change])).skippedUnsupportedTable,
      1,
    );
    final applier = RowApplier(target, ownerUserId: 'user');
    expect(await applier.prepareCompatibility(), true);
    expect(await applier.applyAll([change]), 1);
    final row = (await target.select(target.healthCheckIns).get()).single;
    expect(row.energy, 4);
    expect(row.tagsJson, '["caffeine"]');
    expect(row.note, 'Afternoon coffee');
    expect(await applier.prepareCompatibility(), false);
  });
  test('health backup restores check-ins and old archives preserve newly added records', () async {
    final service = BackupService(
      db: db,
      codec: BackupCodec(),
      outbox: DriftOutboxStore(db),
      ownerUserId: 'user',
    );
    final entry = await repo.save(day: now, energy: 4, note: 'Rested');
    final bytes = await service.exportBackup(
      passphrase: 'health-check-in-test',
      overrideIterations: 1000,
      domain: DomainScope.health,
    );
    await repo.delete(entry);
    await service.restoreBackup(
      passphrase: 'health-check-in-test',
      fileBytes: bytes,
      expectedDomain: DomainScope.health,
    );
    expect((await repo.findDay(ownerUserId: 'user', day: now))!.note, 'Rested');
    expect(await DriftOutboxStore(db).depth(), greaterThan(0));

    final codec = BackupCodec();
    final plaintext = await codec.decrypt(
      passphrase: 'health-check-in-test',
      envelope: BackupEnvelope.decodeBytes(bytes),
    );
    final payload = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final header = payload['header'] as Map<String, dynamic>;
    header['schemaVersion'] = 96;
    (header['tables'] as Map<String, dynamic>).remove('health_check_ins');
    (payload['data'] as Map<String, dynamic>).remove('health_check_ins');
    final oldArchive = await codec.encrypt(
      passphrase: 'health-check-in-test',
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      schemaVersion: 96,
      iterations: 1000,
    );
    await service.restoreBackup(
      passphrase: 'health-check-in-test',
      fileBytes: oldArchive.encodeBytes(),
      expectedDomain: DomainScope.health,
    );
    expect((await repo.findDay(ownerUserId: 'user', day: now))!.note, 'Rested');
  });
}
