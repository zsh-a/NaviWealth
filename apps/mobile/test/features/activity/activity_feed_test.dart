import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/journal_entry.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/activity/ui/activity_feed.dart';
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
  required AccountSide category,
  String currency = 'CNY',
}) {
  return Account(
    id: id,
    type: AccountCategory.bank,
    name: name,
    currency: currency,
    category: category,
    sync: _sync,
  );
}

Posting _posting({
  required String id,
  required String journalEntryId,
  required String accountId,
  required String units,
  int position = 0,
}) {
  return Posting(
    id: id,
    journalEntryId: journalEntryId,
    position: position,
    accountId: accountId,
    units: Decimal.parse(units),
    unit: 'CNY',
    sync: _sync,
  );
}

JournalEntryWithPostings _entry({
  required String id,
  required DateTime date,
  required String narration,
  String? payee,
  required List<Posting> postings,
}) {
  return JournalEntryWithPostings(
    entry: JournalEntry(
      id: id,
      date: date,
      narration: narration,
      payee: payee,
      sync: _sync,
    ),
    postings: postings,
  );
}

Widget _wrap({
  required List<JournalEntryWithPostings> entries,
  required List<Account> accounts,
}) {
  return ProviderScope(
    overrides: [
      activityFeedProvider.overrideWith(
        (ref) => Stream.value(
          ActivityFeedPage(
            entries: entries,
            totalCount: entries.length,
            hasMore: false,
            isFiltered: false,
            accountsById: {for (final account in accounts) account.id: account},
          ),
        ),
      ),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ActivityFeed()),
    ),
  );
}

Future<void> _enlarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders the feed empty state', (tester) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(entries: const [], accounts: const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('No activity yet'), findsOneWidget);
    expect(find.byIcon(Icons.timeline_outlined), findsOneWidget);
  });

  testWidgets('renders a dated journal row with payee and headline amount', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(
        id: 'expenses:food',
        name: 'Food',
        category: AccountSide.expense,
      ),
      _account(
        id: 'assets:wallet',
        name: 'Wallet',
        category: AccountSide.asset,
      ),
    ];
    final today = DateTime.now();
    final entry = _entry(
      id: 'je-coffee',
      date: DateTime(today.year, today.month, today.day, 10, 5),
      narration: 'Coffee',
      payee: 'Blue Bottle',
      postings: [
        _posting(
          id: 'p-food',
          journalEntryId: 'je-coffee',
          accountId: 'expenses:food',
          units: '32',
        ),
        _posting(
          id: 'p-wallet',
          journalEntryId: 'je-coffee',
          accountId: 'assets:wallet',
          units: '-32',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(entries: [entry], accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Blue Bottle'), findsOneWidget);
    expect(find.text('-32 CNY'), findsOneWidget);
  });

  testWidgets('expands a journal row to reveal posting details', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(
        id: 'expenses:food',
        name: 'Food',
        category: AccountSide.expense,
      ),
      _account(
        id: 'assets:wallet',
        name: 'Wallet',
        category: AccountSide.asset,
      ),
    ];
    final today = DateTime.now();
    final entry = _entry(
      id: 'je-coffee',
      date: DateTime(today.year, today.month, today.day, 10, 5),
      narration: 'Coffee',
      postings: [
        _posting(
          id: 'p-food',
          journalEntryId: 'je-coffee',
          accountId: 'expenses:food',
          units: '32',
        ),
        _posting(
          id: 'p-wallet',
          journalEntryId: 'je-coffee',
          accountId: 'assets:wallet',
          units: '-32',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(entries: [entry], accounts: accounts));
    await tester.pumpAndSettle();

    // The compact row already surfaces the entry's primary account, while
    // the counterparty stays hidden until expansion.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);

    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('32 CNY'), findsOneWidget);
  });
}
