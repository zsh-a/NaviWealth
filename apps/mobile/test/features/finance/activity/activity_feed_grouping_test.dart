import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_grouping.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: _hlc,
);

void main() {
  final accounts = <String, Account>{
    'expenses:food': Account(
      id: 'expenses:food',
      type: AccountCategory.bank,
      name: 'Food',
      currency: 'CNY',
      category: AccountSide.expense,
      sync: _sync,
    ),
    'assets:wallet': Account(
      id: 'assets:wallet',
      type: AccountCategory.bank,
      name: 'Wallet',
      currency: 'CNY',
      category: AccountSide.asset,
      sync: _sync,
    ),
    'income:salary': Account(
      id: 'income:salary',
      type: AccountCategory.bank,
      name: 'Salary',
      currency: 'CNY',
      category: AccountSide.income,
      sync: _sync,
    ),
  };

  JournalEntryWithPostings entry({
    required String id,
    required DateTime date,
    required List<Posting> postings,
  }) {
    return JournalEntryWithPostings(
      entry: JournalEntry(
        id: id,
        date: date,
        narration: id,
        sync: _sync,
      ),
      postings: postings,
    );
  }

  Posting p(String id, String je, String account, String units) => Posting(
    id: id,
    journalEntryId: je,
    position: 0,
    accountId: account,
    units: Decimal.parse(units),
    unit: 'CNY',
    sync: _sync,
  );

  test('groups by calendar day newest first with expense totals', () {
    final day1 = DateTime(2026, 5, 10, 9);
    final day2 = DateTime(2026, 5, 11, 15);
    final entries = [
      entry(
        id: 'a',
        date: day2,
        postings: [
          p('1', 'a', 'expenses:food', '20'),
          p('2', 'a', 'assets:wallet', '-20'),
        ],
      ),
      entry(
        id: 'b',
        date: day1,
        postings: [
          p('3', 'b', 'expenses:food', '10'),
          p('4', 'b', 'assets:wallet', '-10'),
        ],
      ),
      entry(
        id: 'c',
        date: day2,
        postings: [
          p('5', 'c', 'assets:wallet', '100'),
          p('6', 'c', 'income:salary', '-100'),
        ],
      ),
    ];

    final groups = groupActivityEntriesByDay(
      entries,
      accountsById: accounts,
    );
    expect(groups, hasLength(2));
    expect(groups.first.day, DateTime(2026, 5, 11));
    expect(groups.first.entries, hasLength(2));
    expect(groups.first.expenseTotal, Decimal.parse('20'));
    expect(groups.first.incomeTotal, Decimal.parse('100'));
    expect(groups.last.day, DateTime(2026, 5, 10));
    expect(groups.last.expenseTotal, Decimal.parse('10'));
  });
}
