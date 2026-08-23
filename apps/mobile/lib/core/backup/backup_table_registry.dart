import '../sync/sync_table_registry.dart';

class BackupTableRegistration {
  const BackupTableRegistration(
    this.table, {
    this.primaryKey = 'id',
    this.enqueueRestoreOp = false,
  });

  final String table;
  final String primaryKey;

  /// True when restoring rows from this table should queue a sync dirty
  /// pointer after insertion.
  final bool enqueueRestoreOp;
}

/// Backup table surface. It is derived from sync table metadata today so
/// backup/sync coverage stays consistent without duplicating table names, but
/// BackupService depends only on this registry.
final List<BackupTableRegistration> kBackupTableRegistrations =
    List<BackupTableRegistration>.unmodifiable(<BackupTableRegistration>[
      for (final registration in kSyncTableRegistrations)
        if (registration.backupEligible)
          BackupTableRegistration(
            registration.table,
            primaryKey: registration.primaryKey,
            enqueueRestoreOp: kSyncableTables.contains(registration.table),
          ),
      const BackupTableRegistration('personal_profile_facts'),
    ]);

final List<String> kBackupTables = List<String>.unmodifiable(
  kBackupTableRegistrations.map(
    (BackupTableRegistration registration) => registration.table,
  ),
);

final Set<String> kBackupTableSet = Set<String>.unmodifiable(kBackupTables);

final Map<String, BackupTableRegistration> kBackupTableRegistry =
    Map<String, BackupTableRegistration>.unmodifiable(
      <String, BackupTableRegistration>{
        for (final registration in kBackupTableRegistrations)
          registration.table: registration,
      },
    );

bool isBackupTable(String table) => kBackupTableSet.contains(table);

String backupPrimaryKeyForTable(String table) =>
    kBackupTableRegistry[table]?.primaryKey ?? 'id';

bool shouldEnqueueRestoreOpForBackupTable(String table) =>
    kBackupTableRegistry[table]?.enqueueRestoreOp ?? false;
