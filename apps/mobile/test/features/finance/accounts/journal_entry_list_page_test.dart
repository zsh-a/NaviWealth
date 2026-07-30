import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/ui/journal_entry_list_page.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_row.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: _hlc,
);

Account _account({
  required String id,
  required String name,
  AccountSide category = AccountSide.asset,
  String currency = 'CNY',
}) => Account(
  id: id,
  type: AccountCategory.bank,
  name: name,
  currency: currency,
  category: category,
  sync: _sync,
);

JournalEntryWithPostings _entry({
  required String id,
  required DateTime date,
  required String narration,
  String? payee,
  required List<Posting> postings,
}) => JournalEntryWithPostings(
  entry: JournalEntry(
    id: id,
    date: date,
    narration: narration,
    payee: payee,
    sync: _sync,
  ),
  postings: postings,
);

Posting _p({
  required String id,
  required String journalEntryId,
  required String accountId,
  required String units,
  required String unit,
  int position = 0,
}) => Posting(
  id: id,
  journalEntryId: journalEntryId,
  position: position,
  accountId: accountId,
  units: Decimal.parse(units),
  unit: unit,
  sync: _sync,
);

Widget _wrap({
  required List<JournalEntryWithPostings> entries,
  required List<Account> accounts,
}) {
  return ProviderScope(
    overrides: [
      journalEntriesWithPostingsStreamProvider.overrideWith(
        (_) => Stream.value(entries),
      ),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const JournalEntryListPage(),
    ),
  );
}

Future<void> _enlarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders the empty state when the ledger has no entries', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(entries: const [], accounts: const []));
    await tester.pumpAndSettle();
    expect(find.textContaining('No journal entries yet'), findsOneWidget);
  });

  testWidgets('renders one dense grouped timeline row per journal entry', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(id: 'a-bank-a', name: 'Bank A'),
      _account(id: 'a-bank-b', name: 'Bank B'),
    ];
    final entries = [
      _entry(
        id: 'je-1',
        date: DateTime.utc(2026, 4, 1),
        narration: 'Monthly transfer',
        postings: [
          _p(
            id: 'p-1',
            journalEntryId: 'je-1',
            accountId: 'a-bank-a',
            units: '-1000',
            unit: 'CNY',
            position: 0,
          ),
          _p(
            id: 'p-2',
            journalEntryId: 'je-1',
            accountId: 'a-bank-b',
            units: '1000',
            unit: 'CNY',
            position: 1,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    // The journal shares the modern Activity row and grouped-surface chrome.
    expect(find.text('Monthly transfer'), findsOneWidget);
    expect(find.text('-¥1,000'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.arrowLeftRight), findsOneWidget);
    expect(find.byType(ActivityFeedEntrySurface), findsOneWidget);
    expect(find.byType(SectionHeader), findsOneWidget);
    expect(find.byType(FAccordion), findsNothing);
  });

  testWidgets('keeps the journal timeline readable on wide desktop windows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final accounts = [
      _account(id: 'a-bank-a', name: 'Bank A'),
      _account(id: 'a-bank-b', name: 'Bank B'),
    ];
    final entries = [
      _entry(
        id: 'je-wide',
        date: DateTime.utc(2026, 4, 1),
        narration: 'Desktop transfer',
        postings: [
          _p(
            id: 'p-1',
            journalEntryId: 'je-wide',
            accountId: 'a-bank-a',
            units: '-1000',
            unit: 'CNY',
          ),
          _p(
            id: 'p-2',
            journalEntryId: 'je-wide',
            accountId: 'a-bank-b',
            units: '1000',
            unit: 'CNY',
            position: 1,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(ActivityFeedEntrySurface)).width,
      lessThanOrEqualTo(AdaptiveMaxWidth.page),
    );
  });

  testWidgets('tapping a row opens the complete journal entry detail', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(id: 'a-bank-a', name: 'Bank A'),
      _account(id: 'a-bank-b', name: 'Bank B'),
    ];
    final entries = [
      _entry(
        id: 'je-1',
        date: DateTime.utc(2026, 4, 1),
        narration: 'Monthly transfer',
        postings: [
          _p(
            id: 'p-1',
            journalEntryId: 'je-1',
            accountId: 'a-bank-a',
            units: '-1000',
            unit: 'CNY',
            position: 0,
          ),
          _p(
            id: 'p-2',
            journalEntryId: 'je-1',
            accountId: 'a-bank-b',
            units: '1000',
            unit: 'CNY',
            position: 1,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.text('-¥1,000'), findsOneWidget);
    expect(find.text('+¥1,000'), findsNothing);

    await tester.tap(find.text('Monthly transfer'));
    await tester.pumpAndSettle();

    // Detail owns the posting tree instead of expanding a second card style
    // inline in the timeline.
    expect(find.text('+¥1,000'), findsOneWidget);
  });

  testWidgets('payee renders inline next to the date when present', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(id: 'a-food', name: 'Food', category: AccountSide.expense),
      _account(id: 'a-bank', name: 'Bank'),
    ];
    final entries = [
      _entry(
        id: 'je-coffee',
        date: DateTime.utc(2026, 4, 1),
        narration: 'Coffee',
        payee: 'Blue Bottle',
        postings: [
          _p(
            id: 'p-1',
            journalEntryId: 'je-coffee',
            accountId: 'a-food',
            units: '50',
            unit: 'CNY',
            position: 0,
          ),
          _p(
            id: 'p-2',
            journalEntryId: 'je-coffee',
            accountId: 'a-bank',
            units: '-50',
            unit: 'CNY',
            position: 1,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.textContaining('Blue Bottle'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.shoppingBag), findsOneWidget);
  });

  testWidgets('uses a representative fallback amount for unusual entries', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(id: 'a-equity', name: 'Equity', category: AccountSide.equity),
      _account(id: 'a-income', name: 'Income', category: AccountSide.income),
    ];
    final entries = [
      _entry(
        id: 'je-edge',
        date: DateTime.utc(2026, 4, 1),
        narration: 'Edge case',
        postings: [
          _p(
            id: 'p-1',
            journalEntryId: 'je-edge',
            accountId: 'a-equity',
            units: '-10',
            unit: 'USD',
          ),
          _p(
            id: 'p-2',
            journalEntryId: 'je-edge',
            accountId: 'a-income',
            units: '10',
            unit: 'USD',
            position: 1,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.text('Edge case'), findsOneWidget);
    expect(find.text(r'-$10'), findsOneWidget);
    expect(find.text(r'+$10'), findsNothing);
  });
}
