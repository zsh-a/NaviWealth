// Finance ledger E2E suite.
//
// This complements the generic row-state sync E2E by exercising a realistic
// ledger bundle: accounts, a journal entry, and its two postings move through
// dirty pointer → push → pull → RowApplier as one user task would.

import 'package:flutter_test/flutter_test.dart';

import '_cluster.dart';

Map<String, Object?> _account({required String name, String currency = 'CNY'}) {
  return <String, Object?>{
    'type': 'bank',
    'name': name,
    'currency': currency,
    'category': 'asset',
  };
}

Map<String, Object?> _journalEntry({required String narration}) {
  return <String, Object?>{
    'date': 1_777_000_000,
    'narration': narration,
    'flag': 'confirmed',
    'tag_ids_json': '[]',
  };
}

Map<String, Object?> _posting({
  required String journalEntryId,
  required int position,
  required String accountId,
  required String units,
  String unit = 'CNY',
}) {
  return <String, Object?>{
    'journal_entry_id': journalEntryId,
    'position': position,
    'account_id': accountId,
    'units': units,
    'unit': unit,
  };
}

void main() {
  group('finance ledger E2E', () {
    test('two-device sync materialises a balanced transfer bundle', () async {
      final cluster = SyncCluster();
      addTearDown(cluster.disposeAll);
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      iphone.offline = true;
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'checking',
        columns: _account(name: 'Checking'),
      );
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'savings',
        columns: _account(name: 'Savings'),
      );
      await iphone.writeRow(
        table: 'journal_entries',
        rowId: 'je-transfer',
        columns: _journalEntry(narration: 'Move emergency fund'),
      );
      await iphone.writeRow(
        table: 'postings',
        rowId: 'p-out',
        columns: _posting(
          journalEntryId: 'je-transfer',
          position: 0,
          accountId: 'checking',
          units: '-1200',
        ),
      );
      await iphone.writeRow(
        table: 'postings',
        rowId: 'p-in',
        columns: _posting(
          journalEntryId: 'je-transfer',
          position: 1,
          accountId: 'savings',
          units: '1200',
        ),
      );

      expect(await iphone.pendingDepth(), 5);

      iphone.offline = false;
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();

      expect(await iphone.pendingDepth(), 0);
      expect((await mac.lookup('accounts', 'checking'))!['name'], 'Checking');
      expect((await mac.lookup('accounts', 'savings'))!['name'], 'Savings');
      expect(
        (await mac.lookup('journal_entries', 'je-transfer'))!['narration'],
        'Move emergency fund',
      );

      final outgoing = await mac.lookup('postings', 'p-out');
      final incoming = await mac.lookup('postings', 'p-in');
      expect(outgoing!['journal_entry_id'], 'je-transfer');
      expect(outgoing['account_id'], 'checking');
      expect(outgoing['units'], '-1200');
      expect(incoming!['journal_entry_id'], 'je-transfer');
      expect(incoming['account_id'], 'savings');
      expect(incoming['units'], '1200');
    });
  });
}
