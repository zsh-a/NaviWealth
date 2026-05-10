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
import 'package:naviwealth/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/accounts/journal_entry_list_page.dart';
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
}) =>
    Account(
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
}) =>
    JournalEntryWithPostings(
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
}) =>
    Posting(
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
    await tester.pumpWidget(
      _wrap(entries: const [], accounts: const []),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No journal entries yet'),
      findsOneWidget,
    );
  });

  testWidgets('renders one collapsed row per JE with badge + amount', (
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

    // Title + headline amount visible while collapsed.
    expect(find.text('Monthly transfer'), findsOneWidget);
    expect(find.textContaining('1000 CNY'), findsAtLeastNWidgets(1));

    // Transfer-classified badge surfaces.
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);

    // PostingsPreview is still hidden — its Σ-balance check icon
    // doesn't render in the collapsed row.
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('tapping a row expands it to reveal PostingsPreview', (
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

    // Before tapping: only the collapsed-row headline carries an
    // amount. The headline picks the first largest-|units| leg, which
    // for an equal-and-opposite transfer is `-1000 CNY`.
    expect(find.text('-1000 CNY'), findsOneWidget);

    await tester.tap(find.text('Monthly transfer'));
    await tester.pumpAndSettle();

    // After expansion: the headline is still rendered AND both legs
    // show up in PostingsPreview. The "+1000 CNY" leg is unique to
    // the preview (the collapsed headline only ever shows one
    // amount), so it's a stable signal that the preview has
    // expanded.
    expect(find.text('1000 CNY'), findsOneWidget);
  });

  testWidgets('payee renders inline next to the date when present', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(
        id: 'a-food',
        name: 'Food',
        category: AccountSide.expense,
      ),
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

    expect(find.text('· Blue Bottle'), findsOneWidget);
    // Expense-classified badge.
    expect(find.byIcon(Icons.north_east), findsOneWidget);
  });

  testWidgets('no headline amount renders when no asset/liability legs', (
    tester,
  ) async {
    // A pure adjustment JE — say a stock split where every leg is on
    // an asset account but the unit is a commodity, not currency.
    // The summary picks the largest |units| asset/liability leg, so
    // this still renders something. To exercise the "no headline"
    // path we feed only equity / income legs (rare but possible for
    // padding entries).
    await _enlarge(tester);
    final accounts = [
      _account(
        id: 'a-equity',
        name: 'Equity',
        category: AccountSide.equity,
      ),
      _account(
        id: 'a-income',
        name: 'Income',
        category: AccountSide.income,
      ),
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
    // No headline-amount Text in the collapsed row → only the
    // narration appears.
    expect(find.textContaining('USD'), findsNothing);
  });
}
