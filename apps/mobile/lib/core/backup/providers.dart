import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persistence/providers.dart';
import '../auth/current_user.dart';
import '../auth/domain_scope.dart';
import '../logging/providers.dart';
import '../sync/outbox_provider.dart';
import '../sync/providers.dart';
import 'backup_codec.dart';
import 'backup_service.dart';

final backupCodecProvider = Provider<BackupCodec>((ref) {
  return BackupCodec();
});

final backupServiceProvider = FutureProvider<BackupService?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final codec = ref.watch(backupCodecProvider);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null) return null;
  return BackupService(
    db: db,
    codec: codec,
    outbox: outbox,
    logger: ref.read(loggerProvider),
  );
});

typedef BackupExportRunner =
    Future<Uint8List> Function({required String passphrase});

final backupExportRunnerProvider = FutureProvider<BackupExportRunner?>((
  ref,
) async {
  final service = await ref.watch(backupServiceProvider.future);
  if (service == null) return null;
  return ({required String passphrase}) {
    return service.exportBackup(passphrase: passphrase);
  };
});

typedef DomainBackupExportRunner =
    Future<Uint8List> Function({
      required String passphrase,
      required DomainScope domain,
    });

final domainBackupExportRunnerProvider =
    FutureProvider<DomainBackupExportRunner?>((ref) async {
      final service = await ref.watch(backupServiceProvider.future);
      if (service == null) return null;
      return ({required String passphrase, required DomainScope domain}) {
        return service.exportBackup(passphrase: passphrase, domain: domain);
      };
    });

typedef BackupRestoreRunner =
    Future<RestoreResult> Function({
      required String passphrase,
      required Uint8List fileBytes,
    });

final backupRestoreRunnerProvider = FutureProvider<BackupRestoreRunner?>((
  ref,
) async {
  final service = await ref.watch(backupServiceProvider.future);
  if (service == null) return null;
  final scheduler = await ref.watch(syncSchedulerProvider.future);
  return ({required String passphrase, required Uint8List fileBytes}) {
    return service.restoreBackup(
      passphrase: passphrase,
      fileBytes: fileBytes,
      pauseSync: scheduler?.pause,
      resumeSync: scheduler?.resume,
    );
  };
});

typedef DomainBackupRestoreRunner =
    Future<RestoreResult> Function({
      required String passphrase,
      required Uint8List fileBytes,
      required DomainScope domain,
    });

final domainBackupRestoreRunnerProvider =
    FutureProvider<DomainBackupRestoreRunner?>((ref) async {
      final service = await ref.watch(backupServiceProvider.future);
      if (service == null) return null;
      final scheduler = await ref.watch(syncSchedulerProvider.future);
      return ({
        required String passphrase,
        required Uint8List fileBytes,
        required DomainScope domain,
      }) {
        return service.restoreBackup(
          passphrase: passphrase,
          fileBytes: fileBytes,
          expectedDomain: domain,
          pauseSync: scheduler?.pause,
          resumeSync: scheduler?.resume,
        );
      };
    });
