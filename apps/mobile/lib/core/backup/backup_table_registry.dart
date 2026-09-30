import '../sync/sync_table_registry.dart';

class BackupTableRegistration {
  const BackupTableRegistration(
    this.table, {
    this.primaryKey = 'id',
    this.enqueueRestoreOp = false,
    this.rowFilter,
  });

  final String table;
  final String primaryKey;

  /// True when restoring rows from this table should queue a sync dirty
  /// pointer after insertion.
  final bool enqueueRestoreOp;

  /// Trusted SQL predicate shared by export and replacement during restore.
  /// A filtered resource must not erase unrelated rows in the same table.
  final String? rowFilter;
}

/// Backup coverage derives domain sources from sync metadata and explicitly
/// registers confirmed local resources with their row-selection policy.
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
      const BackupTableRegistration(
        'memories',
        rowFilter: "authority = 'user_confirmed'",
      ),
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
