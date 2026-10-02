import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/backup/backup_codec.dart';
import 'package:naviwealth/core/backup/backup_service.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/backup/backup_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
  testWidgets(
    'restore retries the same file, checks before applying, and preserves preview after failure',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = makeTestDatabase();
      addTearDown(db.close);
      final service = BackupService(
        db: db,
        codec: BackupCodec(),
        outbox: DriftOutboxStore(db),
        ownerUserId: 'owner',
      );
      final bytes = await service.exportBackup(
        passphrase: 'correct',
        overrideIterations: 1000,
      );
      var picked = 0;
      var inspected = 0;
      var applied = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupRestoreFilePickerProvider.overrideWithValue(() async {
              picked++;
              return PickedBackupFile(
                name: 'selected-backup.bak',
                bytes: bytes,
              );
            }),
            backupPrepareRestoreRunnerProvider.overrideWith(
              (_) async =>
                  ({
                    required String passphrase,
                    required Uint8List fileBytes,
                    DomainScope? expectedDomain,
                  }) {
                    inspected++;
                    return service.prepareRestore(
                      passphrase: passphrase,
                      fileBytes: fileBytes,
                      expectedDomain: expectedDomain,
                    );
                  },
            ),
            backupApplyPreparedRestoreRunnerProvider.overrideWith(
              (_) async => (PreparedBackup preview) async {
                applied++;
                if (applied == 1) throw StateError('Temporary write failure');
                return service.restorePreparedBackup(preview);
              },
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => AppMessenger.init(child: child!),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const BackupPage(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import Backup'));
      await tester.pumpAndSettle();
      expect(find.text('selected-backup.bak'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('backup-restore-passphrase')),
        'wrong',
      );
      await tester.tap(find.byKey(const Key('backup-restore-submit')));
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.backupWrongPassphrase), findsOneWidget);
      expect(picked, 1);
      expect(applied, 0);
      await tester.enterText(
        find.byKey(const Key('backup-restore-passphrase')),
        'correct',
      );
      await tester.tap(find.byKey(const Key('backup-restore-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-restore-passphrase')), findsNothing);
      expect(find.text(l10n.backupFullScope), findsOneWidget);
      expect(inspected, 2);
      expect(applied, 0);
      await tester.tap(find.byKey(const Key('backup-restore-submit')));
      await tester.pumpAndSettle();
      expect(find.text('selected-backup.bak'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsWidgets);
      await tester.tap(find.byKey(const Key('backup-restore-submit')));
      await tester.pumpAndSettle();
      expect(picked, 1);
      expect(inspected, 2);
      expect(applied, 2);
      expect(find.byKey(const Key('backup-restore-submit')), findsNothing);
      expect(find.text(l10n.backupImportSuccess(0)), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
