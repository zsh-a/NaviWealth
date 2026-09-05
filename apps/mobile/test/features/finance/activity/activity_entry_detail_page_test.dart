import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../data/repositories/_stub_stamper.dart';

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

JournalEntryWithPostings _entry({required String narration, String? payee}) {
  return JournalEntryWithPostings(
    entry: JournalEntry(
      id: 'je-1',
      date: DateTime.utc(2026, 5, 1, 9, 30),
      narration: narration,
      payee: payee,
      sync: _sync,
    ),
    postings: [
      _posting(
        id: 'p-expense',
        journalEntryId: 'je-1',
        accountId: 'expenses:living',
        units: '1234.50',
      ),
      _posting(
        id: 'p-cash',
        journalEntryId: 'je-1',
        accountId: 'assets:cash',
        units: '-1234.50',
        position: 1,
      ),
    ],
  );
}

JournalEntryWithPostings _multiUnitEntry() {
  return JournalEntryWithPostings(
    entry: JournalEntry(
      id: 'je-multi-unit',
      date: DateTime.utc(2026, 8, 21, 16, 42),
      narration: 'AAPL put assignment',
      sync: _sync,
    ),
    postings: [
      Posting(
        id: 'p-aapl',
        journalEntryId: 'je-multi-unit',
        position: 0,
        accountId: 'assets:brokerage',
        units: Decimal.fromInt(100),
        unit: 'AAPL',
        sync: _sync,
      ),
      Posting(
        id: 'p-usd',
        journalEntryId: 'je-multi-unit',
        position: 1,
        accountId: 'assets:brokerage',
        units: Decimal.fromInt(-32500),
        unit: 'USD',
        sync: _sync,
      ),
    ],
  );
}

Widget _wrap({
  required JournalEntryWithPostings entry,
  Locale locale = const Locale('en'),
  ActivityEntryInsightClient? insightClient,
}) {
  final accounts = {
    'expenses:living': _account(
      id: 'expenses:living',
      name: 'Living',
      category: AccountSide.expense,
    ),
    'assets:cash': _account(
      id: 'assets:cash',
      name: 'Cash',
      category: AccountSide.asset,
    ),
  };
  return ProviderScope(
    overrides: [
      aiTouchedAtProvider.overrideWith((ref, key) => Stream.value(null)),
      activityEntryInsightClientProvider.overrideWithValue(insightClient),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: ActivityEntryDetailPage(entry: entry, accountsById: accounts),
      ),
    ),
  );
}

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}

class _FailingDeleteRepository extends JournalEntryRepository {
  _FailingDeleteRepository(AppDatabase db)
    : super(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
        fxRateSource: const _IdentityFx(),
        baseCurrency: 'CNY',
      );

  @override
  Future<void> softDelete(String id) async {
    throw StateError('delete failed');
  }
}

Widget _deleteWrap({
  required JournalEntryRepository repository,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      journalEntryRepositoryProvider.overrideWith((ref) async => repository),
      aiTouchedAtProvider.overrideWith((ref, key) => Stream.value(null)),
      activityEntryInsightClientProvider.overrideWithValue(null),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: FTheme.neutral.light.desktop,
        child: AppMessenger.init(child: child!),
      ),
    ),
  );
}

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  testWidgets('renders compact localized hero details', (tester) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Coffee', payee: 'Blue Bottle'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Living'), findsOneWidget);
    expect(find.byType(SignedMoneyText), findsOneWidget);
    await tester.tap(find.text('Ledger breakdown'));
    await tester.pumpAndSettle();
    expect(find.byType(SignedMoneyText), findsWidgets);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Blue Bottle'), findsOneWidget);
    expect(find.textContaining('5/1/2026'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.startsWith('-') &&
            widget.data!.contains('1,234.5'),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('uses directional colors for positive and negative unit totals', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(entry: _multiUnitEntry()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger breakdown'));
    await tester.pumpAndSettle();
    final positiveLabel = find.text('Σ AAPL');
    final negativeLabel = find.text('Σ USD');
    expect(positiveLabel, findsOneWidget);
    expect(negativeLabel, findsOneWidget);

    final positiveRow = find
        .ancestor(of: positiveLabel, matching: find.byType(Row))
        .first;
    final negativeRow = find
        .ancestor(of: negativeLabel, matching: find.byType(Row))
        .first;
    final positiveAmount = find.descendant(
      of: positiveRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data?.startsWith('+') == true &&
            widget.data?.contains('100') == true,
      ),
    );
    final negativeAmount = find.descendant(
      of: negativeRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data?.startsWith('-') == true &&
            widget.data?.contains('32,500') == true,
      ),
    );
    expect(positiveAmount, findsOneWidget);
    expect(negativeAmount, findsOneWidget);

    final appTheme = tester.element(positiveLabel).appTheme;
    expect(
      tester.widget<Text>(positiveAmount).style?.color,
      appTheme.market.up.fg,
    );
    expect(
      tester.widget<Text>(negativeAmount).style?.color,
      appTheme.market.down.fg,
    );
    expect(appTheme.market.up.fg, isNot(appTheme.market.down.fg));
  });

  testWidgets('hides the insight card when no client is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(entry: _entry(narration: 'Spotify subscription')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsNothing);
    expect(find.text('No insight available for this entry.'), findsNothing);
  });

  testWidgets('uses FRB profile LLM explanation when available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Spotify subscription'),
        insightClient: _FakeInsightClient(
          responseText:
              '```text\n'
              '- This looks like a recurring media subscription paid from cash.\n'
              '```',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsOneWidget);
    expect(
      find.text(
        'This looks like a recurring media subscription paid from cash.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides the insight card when FRB profile LLM fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Spotify subscription'),
        insightClient: _FakeInsightClient(error: StateError('llm down')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsNothing);
  });

  testWidgets('hides the entire insight card when client returns no output', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Coffee'),
        insightClient: _FakeInsightClient(responseText: '   '),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsNothing);
    expect(find.byIcon(FLucideIcons.sparkles), findsNothing);
    expect(find.text('No insight available for this entry.'), findsNothing);
    expect(find.text('Living'), findsOneWidget);
  });

  testWidgets('deletes the entry, returns to activity, and supports Undo', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = JournalEntryRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'CNY',
    );
    final persisted = await repository.create(
      entry: JournalEntryDraft(
        id: 'je-delete',
        date: DateTime.utc(2026, 5, 1),
        narration: 'Coffee',
      ),
      postings: [
        PostingDraft(
          id: 'p-expense',
          accountId: 'expenses:living',
          units: Decimal.parse('25'),
          unit: 'CNY',
        ),
        PostingDraft(
          id: 'p-cash',
          accountId: 'assets:cash',
          units: Decimal.parse('-25'),
          unit: 'CNY',
        ),
      ],
    );
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (context, state) => ActivityEntryDetailPage(
            entry: persisted,
            accountsById: {
              'expenses:living': _account(
                id: 'expenses:living',
                name: 'Living',
                category: AccountSide.expense,
              ),
              'assets:cash': _account(
                id: 'assets:cash',
                name: 'Cash',
                category: AccountSide.asset,
              ),
            },
          ),
        ),
        GoRoute(
          path: '/activity',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Activity destination'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _deleteWrap(repository: repository, router: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Activity destination'), findsOneWidget);
    expect(find.text('Entry deleted'), findsOneWidget);
    expect(await repository.getById('je-delete'), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Change undone'), findsOneWidget);
    final restored = await repository.getById('je-delete');
    expect(restored, isNotNull);
    expect(restored!.postings, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('keeps the detail visible and explains a delete failure', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = _FailingDeleteRepository(db);
    final entry = _entry(narration: 'Coffee');
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (context, state) => ActivityEntryDetailPage(
            entry: entry,
            accountsById: {
              'expenses:living': _account(
                id: 'expenses:living',
                name: 'Living',
                category: AccountSide.expense,
              ),
              'assets:cash': _account(
                id: 'assets:cash',
                name: 'Cash',
                category: AccountSide.asset,
              ),
            },
          ),
        ),
        GoRoute(
          path: '/activity',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Activity destination'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _deleteWrap(repository: repository, router: router),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't delete this entry. Try again."), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Activity destination'), findsNothing);
    expect(find.byIcon(FLucideIcons.trash2), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

class _FakeInsightClient implements ActivityEntryInsightClient {
  _FakeInsightClient({this.responseText, this.error});

  final String? responseText;
  final Object? error;

  @override
  Future<String?> explain(
    ActivityEntryInsightRequest request,
    AppLocalizations l10n,
  ) async {
    final e = error;
    if (e != null) throw e;
    return responseText;
  }
}
