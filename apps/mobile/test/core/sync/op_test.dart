import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

void main() {
  group('sync table registry', () {
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
  });
}
