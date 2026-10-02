// Flow / Task test: "Encrypted backup / restore" — Task #11 in
// docs/development/testing-strategy.md.
//
// This boots the real app shell, discovers Backup & Restore through global
// Settings, selects a backup through the injected file-picker seam, confirms
// the destructive restore sheet, and proves the UI passes bytes and passphrase
// to the restore boundary. The OS picker and cryptographic restore itself are
// faked because flow tests run headless under `flutter test`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/settings/ui/backup/backup_page.dart';

import '../core/persistence/test_database.dart';
import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Encrypted backup restore', () {
    testWidgets('user restores an encrypted backup from settings', (
      tester,
    ) async {
      String? restorePassphrase;
      Uint8List? restoredBytes;
      final db = makeTestDatabase();
      addTearDown(db.close);
      final service = BackupService(
        db: db,
        codec: BackupCodec(),
        outbox: DriftOutboxStore(db),
        ownerUserId: kLocalOnlyUserId,
      );
      final bytes = await service.exportBackup(
        passphrase: 'correct horse battery staple',
        overrideIterations: 1000,
      );
      var applied = false;

      await bootApp(
        tester,
        extraOverrides: [
          backupRestoreFilePickerProvider.overrideWithValue(() async {
            return PickedBackupFile(
              name: 'naviwealth-backup-flow.bak',
              bytes: bytes,
            );
          }),
          backupPrepareRestoreRunnerProvider.overrideWith((ref) async {
            return ({
              required String passphrase,
              required Uint8List fileBytes,
              DomainScope? expectedDomain,
            }) async {
              restorePassphrase = passphrase;
              restoredBytes = Uint8List.fromList(fileBytes);
              expect(applied, isFalse);
              return service.prepareRestore(
                passphrase: passphrase,
                fileBytes: fileBytes,
                expectedDomain: expectedDomain,
              );
            };
          }),
          backupApplyPreparedRestoreRunnerProvider.overrideWith(
            (ref) async => (PreparedBackup prepared) async {
              applied = true;
              return service.restorePreparedBackup(prepared);
            },
          ),
        ],
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openSettings();

      final settings = SettingsPageObject(tester);
      settings.expectLanded();
      await settings.openBackupAndRestore();

      final backup = BackupPageObject(tester);
      backup.expectLanded();
      await backup.importWithPassphrase('correct horse battery staple');

      backup.expectImportSucceeded(rows: 0);
      expect(applied, isTrue);
      expect(restorePassphrase, 'correct horse battery staple');
      expect(restoredBytes, bytes);
      await closeApp(tester);
    }, tags: 'flow');
  });
}
