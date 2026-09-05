import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_row.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
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
  String unit = 'CNY',
  int position = 0,
}) {
  return Posting(
    id: id,
    journalEntryId: journalEntryId,
    position: position,
    accountId: accountId,
    units: Decimal.parse(units),
    unit: unit,
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
  bool hasMore = false,
  bool isFiltered = false,
}) {
  return ProviderScope(
    overrides: [
      activityFeedProvider.overrideWith(
        (ref) => Stream.value(
          ActivityFeedPage(
            entries: entries,
            totalCount: entries.length,
            hasMore: hasMore,
            isFiltered: isFiltered,
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
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: const Scaffold(body: ActivityFeed()),
      ),
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
    expect(find.byIcon(FLucideIcons.workflow), findsOneWidget);
    // Empty state offers a primary CTA to record an entry.
    expect(find.text('Record entry'), findsOneWidget);
  });

  testWidgets('filtered empty state offers an inline filter action', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(entries: const [], accounts: const [], isFiltered: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('No activity matches these filters.'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
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
    expect(find.text('Blue Bottle'), findsOneWidget);
    // Merchant is primary; note and category remain available as metadata.
    expect(find.textContaining('Coffee'), findsOneWidget);
    final expenseAmount = find.descendant(
      of: find.byType(ActivityFeedEntryRow),
      matching: find.text('-¥32'),
    );
    expect(expenseAmount, findsOneWidget);
    final expenseText = tester.widget<Text>(expenseAmount);
    final expenseContext = tester.element(expenseAmount);
    expect(
      expenseText.style?.color,
      expenseContext.appTheme.market.roleForDelta(-1).fg,
    );
    expect(find.textContaining('Net cash flow'), findsOneWidget);
    // Day rows are virtualized with DecoratedBox chrome (not one
    // AppGroupedSurface wrapping the whole day).
    expect(find.byType(ActivityFeedEntryRow), findsOneWidget);
  });

  testWidgets('trade row shows a currency-rounded cash headline', (
    tester,
  ) async {
    await _enlarge(tester);
    final accounts = [
      _account(
        id: 'assets:broker',
        name: 'Broker',
        category: AccountSide.asset,
      ),
      _account(id: 'assets:cash', name: 'Cash', category: AccountSide.asset),
    ];
    final today = DateTime.now();
    final entry = _entry(
      id: 'je-buy',
      date: DateTime(today.year, today.month, today.day, 10, 5),
      narration: 'Buy 1000.12345678 600519',
      postings: [
        _posting(
          id: 'p-stock',
          journalEntryId: 'je-buy',
          accountId: 'assets:broker',
          units: '1000.12345678',
          unit: 'cn_stock:600519',
        ),
        _posting(
          id: 'p-cash',
          journalEntryId: 'je-buy',
          accountId: 'assets:cash',
          units: '-50.12345678901234',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(entries: [entry], accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.text('-¥50.12'), findsOneWidget);
    final tradeAmount = find.text('-¥50.12');
    final tradeText = tester.widget<Text>(tradeAmount);
    final tradeContext = tester.element(tradeAmount);
    expect(tradeText.style?.color, tradeContext.theme.colors.foreground);
    expect(find.textContaining('50.123456'), findsNothing);
    expect(find.textContaining('1000.12345678 600519'), findsOneWidget);
  });

  test('directional amount colors are limited to real cash-flow kinds', () {
    expect(activityKindUsesDirectionalAmountColor(EntryKind.income), isTrue);
    expect(activityKindUsesDirectionalAmountColor(EntryKind.expense), isTrue);
    expect(activityKindUsesDirectionalAmountColor(EntryKind.payment), isTrue);
    for (final kind in const [
      EntryKind.trade,
      EntryKind.transfer,
      EntryKind.adjustment,
      EntryKind.opening,
      EntryKind.other,
    ]) {
      expect(activityKindUsesDirectionalAmountColor(kind), isFalse);
    }
  });

  testWidgets('uses a quiet automatic-pagination footer when more exists', (
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

    await tester.pumpWidget(
      _wrap(entries: [entry], accounts: accounts, hasMore: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Load more'), findsNothing);
    expect(find.text('All activity loaded'), findsNothing);
  });

  testWidgets('ends an exhausted feed without status copy', (tester) async {
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

    await tester.pumpWidget(
      _wrap(entries: [entry], accounts: accounts, hasMore: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Load more'), findsNothing);
    expect(find.text('All activity loaded'), findsNothing);
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
    await tester.tap(find.text('Ledger breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('+¥32'), findsOneWidget);
  });
}
