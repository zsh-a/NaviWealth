import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';

void main() {
  group('D-1.4 sync domain prefix', () {
    test('prefixFinanceTable composes the fin: prefix', () {
      expect(prefixFinanceTable('accounts'), 'fin:accounts');
      expect(prefixFinanceTable('journal_entries'), 'fin:journal_entries');
    });

    test('stripDomainPrefix recovers the bare table name', () {
      expect(stripDomainPrefix('fin:accounts'), 'accounts');
      expect(stripDomainPrefix('health:sleep_session'), 'sleep_session');
    });

    test('stripDomainPrefix returns null for unrecognised input', () {
      expect(stripDomainPrefix('accounts'), isNull);
      expect(stripDomainPrefix('unknown:rows'), isNull);
      expect(stripDomainPrefix(''), isNull);
    });

    test(
      'hasDomainPrefix true for active domain prefixes, false otherwise',
      () {
        expect(hasDomainPrefix('fin:accounts'), isTrue);
        expect(hasDomainPrefix('health:hrv_daily'), isTrue);
        expect(hasDomainPrefix('know:knowledge_notes'), isTrue);
        expect(hasDomainPrefix('accounts'), isFalse);
        expect(hasDomainPrefix('time:slot'), isFalse);
      },
    );

    test('prefix round-trip on a finance table is the identity', () {
      const table = 'options_trade_journal';
      expect(stripDomainPrefix(prefixFinanceTable(table)), table);
    });

    test('domainPrefixForTable routes Health and Knowledge explicitly', () {
      expect(domainPrefixForTable('health_metrics'), 'health:');
      expect(domainPrefixForTable('knowledge_notes'), 'know:');
      expect(domainPrefixForTable('knowledge_routines'), 'know:');
      expect(domainPrefixForTable('execution_projects'), 'exec:');
      expect(domainPrefixForTable('execution_actions'), 'exec:');
      expect(domainPrefixForTable('accounts'), 'fin:');
      expect(domainPrefixForTable('options_trade_journal'), 'fin:');
    });

    test('prefixTable tags each domain correctly', () {
      expect(prefixTable('health_metrics'), 'health:health_metrics');
      expect(prefixTable('knowledge_decisions'), 'know:knowledge_decisions');
      expect(prefixTable('execution_projects'), 'exec:execution_projects');
      expect(prefixTable('accounts'), 'fin:accounts');
    });

    test('prefix round-trip on a knowledge table is the identity', () {
      for (final table in kKnowledgeTables) {
        expect(stripDomainPrefix(prefixTable(table)), table);
      }
    });

    test('prefixTable round-trips every syncable table', () {
      // SP-B-3 / SP-G-4: every syncable row crosses the wire with an explicit
      // LifeOS domain prefix, and stripping that prefix recovers the local
      // Drift table name.
      for (final table in kSyncableTables) {
        final wireTable = prefixTable(table);
        expect(hasDomainPrefix(wireTable), isTrue, reason: table);
        expect(stripDomainPrefix(wireTable), table, reason: table);
      }
    });
  });
}
