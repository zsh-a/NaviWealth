import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/domain_prefix.dart';

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

    test('hasDomainPrefix true for fin:/health:, false otherwise', () {
      expect(hasDomainPrefix('fin:accounts'), isTrue);
      expect(hasDomainPrefix('health:hrv_daily'), isTrue);
      expect(hasDomainPrefix('accounts'), isFalse);
      expect(hasDomainPrefix('time:slot'), isFalse);
    });

    test('prefix round-trip on a finance table is the identity', () {
      const table = 'options_trade_journal';
      expect(stripDomainPrefix(prefixFinanceTable(table)), table);
    });

    test('domainPrefixForTable routes knowledge tables to know:, else fin:',
        () {
      expect(domainPrefixForTable('knowledge_notes'), 'know:');
      expect(domainPrefixForTable('knowledge_routines'), 'know:');
      expect(domainPrefixForTable('accounts'), 'fin:');
      expect(domainPrefixForTable('options_trade_journal'), 'fin:');
    });

    test('prefixTable tags each domain correctly', () {
      expect(prefixTable('knowledge_decisions'), 'know:knowledge_decisions');
      expect(prefixTable('accounts'), 'fin:accounts');
    });

    test('prefix round-trip on a knowledge table is the identity', () {
      for (final table in kKnowledgeTables) {
        expect(stripDomainPrefix(prefixTable(table)), table);
      }
    });
  });
}
