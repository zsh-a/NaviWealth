import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/backup/backup_table_registry.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

import '../persistence/test_database.dart';

void main() {
  group('backup table registry', () {
    test('derives table order from backup-eligible sync registrations', () {
      final expected = kSyncTableRegistrations
          .where((registration) => registration.backupEligible)
          .map((registration) => registration.table)
          .followedBy(const <String>['personal_profile_facts'])
          .toList(growable: false);

      expect(kBackupTables, expected);
      expect(kBackupTableSet, expected.toSet());
      expect(kBackupTables, contains('fx_rates'));
    });

    test('registrations are unique and target local tables', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final seen = <String>{};

      for (final registration in kBackupTableRegistrations) {
        expect(
          seen.add(registration.table),
          isTrue,
          reason: '${registration.table} is registered more than once',
        );
        final rows = await db
            .customSelect('PRAGMA table_info(${registration.table})')
            .get();
        final columns = rows.map((row) => row.read<String>('name')).toSet();
        expect(columns, isNotEmpty, reason: registration.table);
        expect(columns, contains(registration.primaryKey));
      }
    });

    test('restore sync enqueue flag matches syncable table coverage', () {
      for (final registration in kBackupTableRegistrations) {
        expect(
          registration.enqueueRestoreOp,
          kSyncableTables.contains(registration.table),
          reason: registration.table,
        );
      }
    });

    test('agent lifecycle tables are not backed up', () {
      const agentLocalOnlyTables = <String>{
        'agent_runs',
        'agent_artifacts',
        'agent_preferences',
        'agent_runtime_checkpoints',
      };

      for (final table in agentLocalOnlyTables) {
        expect(kBackupTables, isNot(contains(table)));
        expect(isBackupTable(table), isFalse);
        expect(shouldEnqueueRestoreOpForBackupTable(table), isFalse);
      }
    });
  });
}
