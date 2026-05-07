import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/journal_entry.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/activity/data/activity_feed_query.dart';

final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'd',
  hlc: Hlc.zero('d'),
);

void main() {
  test('filters by account id', () {
    final entries = [
      _entry('food', DateTime.utc(2026, 5, 1), ['expense', 'cash']),
      _entry('salary', DateTime.utc(2026, 5, 2), ['income', 'bank']),
    ];

    final filtered = filterActivityEntries(
      entries: entries,
      query: const ActivityFeedQuery(accountIds: {'bank'}),
      accountsById: _accounts,
    );

    expect(filtered.map((e) => e.entry.id), ['salary']);
  });

  test('filters by derived activity kind', () {
    final entries = [
      _entry('food', DateTime.utc(2026, 5, 1), ['expense', 'cash']),
      _entry('salary', DateTime.utc(2026, 5, 2), ['income', 'bank']),
    ];

    final filtered = filterActivityEntries(
      entries: entries,
      query: const ActivityFeedQuery(kinds: {ActivityKind.expense}),
      accountsById: _accounts,
    );

    expect(filtered.map((e) => e.entry.id), ['food']);
  });

  test('filters by half-open date range', () {
    final entries = [
      _entry('old', DateTime.utc(2026, 4, 30), ['expense', 'cash']),
      _entry('inside', DateTime.utc(2026, 5, 1), ['expense', 'cash']),
      _entry('end', DateTime.utc(2026, 6, 1), ['expense', 'cash']),
    ];

    final filtered = filterActivityEntries(
      entries: entries,
      query: ActivityFeedQuery(
        dateRange: DateTimeRange(
          start: DateTime.utc(2026, 5),
          end: DateTime.utc(2026, 6),
        ),
      ),
      accountsById: _accounts,
    );

    expect(filtered.map((e) => e.entry.id), ['inside']);
  });
}

final _accounts = {
  'cash': _account('cash', AccountCategory.asset),
  'bank': _account('bank', AccountCategory.asset),
  'expense': _account('expense', AccountCategory.expense),
  'income': _account('income', AccountCategory.income),
};

Account _account(String id, AccountCategory category) {
  return Account(
    id: id,
    type: AccountType.bank,
    name: id,
    currency: 'CNY',
    category: category,
    sync: _sync,
  );
}

JournalEntryWithPostings _entry(
  String id,
  DateTime date,
  List<String> accountIds,
) {
  return JournalEntryWithPostings(
    entry: JournalEntry(id: id, date: date, narration: id, sync: _sync),
    postings: [
      for (var i = 0; i < accountIds.length; i++)
        Posting(
          id: '$id-$i',
          journalEntryId: id,
          position: i,
          accountId: accountIds[i],
          units: i == 0 ? Decimal.one : -Decimal.one,
          unit: 'CNY',
          sync: _sync,
        ),
    ],
  );
}
