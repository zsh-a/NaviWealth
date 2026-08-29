import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_backfill.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

import '../persistence/test_database.dart';

void main() {
  group('sync table registry', () {
    test('table registrations are unique', () {
      final tables = <String>{};
      for (final registration in kSyncTableRegistrations) {
        expect(
          tables.add(registration.table),
          isTrue,
          reason: '${registration.table} is registered more than once',
        );
      }
    });

    test('contains the FIR-130 ledger triple', () {
      expect(
        kSyncableTables,
        containsAll(<String>{'journal_entries', 'postings', 'prices'}),
      );
    });

    test('derives the closed set from domain table groups', () {
      final expected = <String>{
        for (final tables in kSyncTablesByDomainPrefix.values) ...tables,
      };
      expect(kSyncableTables, expected);
    });

    test('domain table groups are disjoint', () {
      final seen = <String>{};
      for (final entry in kSyncTablesByDomainPrefix.entries) {
        for (final table in entry.value) {
          expect(
            seen.add(table),
            isTrue,
            reason: '$table is registered in more than one row family',
          );
        }
      }
      expect(seen, kSyncableTables);
    });

    test('primary-key overrides target syncable tables', () {
      expect(kSyncPkOverrides.keys, everyElement(isIn(kSyncableTables)));
      expect(syncPrimaryKeyForTable('accounts'), 'id');
      expect(syncPrimaryKeyForTable('settings'), 'user_id');
      expect(syncPrimaryKeyForTable('options_strategy_profile'), 'user_id');
    });

    test('backfill tables are derived from eligible registrations', () {
      final expected = kSyncTableRegistrations
          .where(
            (registration) =>
                registration.ownerScoped && registration.backfillEligible,
          )
          .map((registration) => registration.table)
          .toList(growable: false);

      expect(kSyncBackfillTables, expected);
      expect(SyncBackfill.tables, expected);
      expect(kSyncBackfillTables, contains('corporate_actions'));
      expect(kSyncBackfillTables, contains('health_metrics'));
      expect(kSyncBackfillTables, contains('execution_plans'));
      expect(kSyncBackfillTables, isNot(contains('fx_rates')));
    });

    test('agent lifecycle tables stay local-only', () {
      const agentLocalOnlyTables = <String>{
        'agent_runs',
        'agent_artifacts',
        'agent_preferences',
        'agent_runtime_checkpoints',
      };

      for (final table in agentLocalOnlyTables) {
        expect(kSyncableTables, isNot(contains(table)));
        expect(kSyncBackfillTables, isNot(contains(table)));
        for (final tables in kSyncTablesByDomainPrefix.values) {
          expect(tables, isNot(contains(table)));
        }
      }
    });

    test('registry metadata matches Drift table columns', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      for (final registration in kSyncTableRegistrations) {
        final table = db.allTables.firstWhere(
          (table) => table.actualTableName == registration.table,
          orElse: () => fail('missing Drift table: ${registration.table}'),
        );
        final columns = table.$columns.map((column) => column.name).toSet();

        expect(
          columns.contains('owner_user_id'),
          registration.ownerScoped,
          reason: registration.table,
        );
        expect(columns, contains(registration.primaryKey));
        if (registration.backfillEligible) {
          expect(
            columns,
            contains('owner_user_id'),
            reason: registration.table,
          );
          expect(columns, contains('deleted_at'), reason: registration.table);
        }
      }
    });
  });
}
