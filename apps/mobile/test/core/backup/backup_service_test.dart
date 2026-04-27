import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/data/repositories/drift_account_repository.dart';
import 'package:naviwealth/domain/entities/account.dart';

import '../db/test_database.dart';

void main() {
  group('BackupService', () {
    // Use a tiny iteration count so tests stay fast — production paths
    // hit BackupCodec directly with the default 200k iterations.
    final fastCodec = BackupCodec();

    Account sampleAccount({String id = 'acc-1', String name = '主账户'}) {
      final now = DateTime.utc(2026, 1, 15, 12);
      return Account(
        id: id,
        name: name,
        kind: AccountKind.bank,
        currency: 'CNY',
        openingBalance: 1000,
        institution: 'CMB',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('export then restore restores the same row set', () async {
      final source = makeTestDatabase();
      addTearDown(source.close);
      final sourceRepo = DriftAccountRepository(source);
      await sourceRepo.upsert(sampleAccount(id: 'a', name: '账户A'));
      await sourceRepo.upsert(sampleAccount(id: 'b', name: '账户B'));

      final service = BackupService(source, codec: fastCodec);
      final bytes = await service.exportEncrypted(passphrase: 'correct horse');

      final target = makeTestDatabase();
      addTearDown(target.close);
      final targetService = BackupService(target, codec: fastCodec);
      final report = await targetService.restoreEncrypted(
        passphrase: 'correct horse',
        bytes: bytes,
      );

      expect(report.rowsByTable['accounts'], 2);
      expect(report.totalRows, greaterThanOrEqualTo(2));

      final restored = await DriftAccountRepository(target).listAll();
      expect(restored.map((a) => a.id).toSet(), {'a', 'b'});
      expect(restored.firstWhere((a) => a.id == 'a').name, '账户A');
    });

    test('restore wipes pre-existing rows in the target database', () async {
      final source = makeTestDatabase();
      addTearDown(source.close);
      await DriftAccountRepository(
        source,
      ).upsert(sampleAccount(id: 'fresh', name: 'fresh'));

      final bytes = await BackupService(
        source,
        codec: fastCodec,
      ).exportEncrypted(passphrase: 'pw');

      final target = makeTestDatabase();
      addTearDown(target.close);
      await DriftAccountRepository(
        target,
      ).upsert(sampleAccount(id: 'stale', name: 'stale'));

      await BackupService(
        target,
        codec: fastCodec,
      ).restoreEncrypted(passphrase: 'pw', bytes: bytes);

      final ids = (await DriftAccountRepository(
        target,
      ).listAll()).map((a) => a.id).toSet();
      expect(ids, {'fresh'});
    });

    test(
      'wrong passphrase fails authentication without leaking data',
      () async {
        final source = makeTestDatabase();
        addTearDown(source.close);
        await DriftAccountRepository(source).upsert(sampleAccount());

        final bytes = await BackupService(
          source,
          codec: fastCodec,
        ).exportEncrypted(passphrase: 'right');

        final target = makeTestDatabase();
        addTearDown(target.close);

        expect(
          () => BackupService(
            target,
            codec: fastCodec,
          ).restoreEncrypted(passphrase: 'wrong', bytes: bytes),
          throwsA(isA<BackupAuthenticationException>()),
        );

        // Target was never touched.
        final ids = (await DriftAccountRepository(
          target,
        ).listAll()).map((a) => a.id).toList();
        expect(ids, isEmpty);
      },
    );

    test('rejects backup from a newer schema version', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final service = BackupService(db, codec: fastCodec);

      final tamperedEnvelope = await fastCodec.encrypt(
        passphrase: 'pw',
        plaintext: Uint8List.fromList(utf8.encode('{"tables":{}}')),
        schemaVersion: 999,
      );

      expect(
        () => service.restoreEncrypted(
          passphrase: 'pw',
          bytes: tamperedEnvelope.encodeBytes(),
        ),
        throwsA(isA<BackupSchemaMismatch>()),
      );
    });
  });
}
