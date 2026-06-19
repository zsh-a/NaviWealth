// Flow / Task test: "Export" — Task #12 in docs/testing-strategy.md.
//
// This boots the real app shell, discovers Backup & Restore through global
// Settings, enters an export passphrase, and proves the UI hands encrypted
// bytes to the file-save boundary. The OS save dialog itself is faked because
// flow tests run headless under `flutter test`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/features/settings/backup/backup_page.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Export', () {
    testWidgets('user exports an encrypted backup from settings', (
      tester,
    ) async {
      String? exportPassphrase;
      Uint8List? savedBytes;
      String? savedFileName;

      await bootApp(
        tester,
        extraOverrides: [
          backupExportRunnerProvider.overrideWith((ref) async {
            return ({required String passphrase}) async {
              exportPassphrase = passphrase;
              return Uint8List.fromList([1, 2, 3, 4]);
            };
          }),
          backupFileSaverProvider.overrideWithValue((bytes, fileName) async {
            savedBytes = Uint8List.fromList(bytes);
            savedFileName = fileName;
            return true;
          }),
        ],
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openSettings();

      final settings = SettingsPageObject(tester);
      settings.expectLanded();
      await settings.openBackupAndRestore();

      final backup = BackupPageObject(tester);
      backup.expectLanded();
      await backup.exportWithPassphrase('correct horse battery staple');

      backup.expectExportSucceeded();
      expect(exportPassphrase, 'correct horse battery staple');
      expect(savedBytes, Uint8List.fromList([1, 2, 3, 4]));
      expect(savedFileName, startsWith('naviwealth-backup-'));
      expect(savedFileName, endsWith('.bak'));
      await closeApp(tester);
    }, tags: 'flow');
  });
}
