import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/journal_entry.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
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
      home: ActivityEntryDetailPage(entry: entry, accountsById: accounts),
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

  testWidgets('renders localized subscription insight for English keywords', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(entry: _entry(narration: 'Spotify subscription')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsOneWidget);
    expect(
      find.text(
        'Recurring subscription. Review whether it still fits your plan before the next renewal.',
      ),
      findsOneWidget,
    );
    expect(find.text('No insight available for this entry.'), findsNothing);
  });

  testWidgets('renders localized income insight for Chinese keywords', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: '5 月工资'),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('记录洞察'), findsOneWidget);
    expect(find.text('识别为主要收入流入。可作为现金流预测的稳定基线。'), findsOneWidget);
    expect(find.text('暂无该笔记录的洞察。'), findsNothing);
  });

  testWidgets('uses FRB profile LLM explanation when available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Spotify subscription'),
        insightClient: _FakeInsightClient(
          responseText:
              'This looks like a recurring media subscription paid from cash.',
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
    expect(
      find.text(
        'Recurring subscription. Review whether it still fits your plan before the next renewal.',
      ),
      findsNothing,
    );
  });

  testWidgets('falls back to heuristic when FRB profile LLM fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entry: _entry(narration: 'Spotify subscription'),
        insightClient: _FakeInsightClient(error: StateError('llm down')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsOneWidget);
    expect(
      find.text(
        'Recurring subscription. Review whether it still fits your plan before the next renewal.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides the entire insight card when no heuristic matches', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(entry: _entry(narration: 'Coffee')));
    await tester.pumpAndSettle();

    expect(find.text('Entry insight'), findsNothing);
    expect(find.byIcon(FLucideIcons.sparkles), findsNothing);
    expect(find.text('No insight available for this entry.'), findsNothing);
    expect(find.text('Living'), findsOneWidget);
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
