import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/features/finance/home/ui/activity_timeline_preview.dart';
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

GoRouter _router({Widget child = const ActivityTimelinePreview()}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: AppRoutes.activity,
        builder: (_, _) => const Scaffold(body: Text('activity-route')),
      ),
      GoRoute(
        name: AppRouteNames.activityEntryDetail,
        path: '/activity/entry/:entryId',
        builder: (_, state) => Scaffold(
          body: Text('entry-detail-${state.pathParameters['entryId']}'),
        ),
      ),
    ],
  );
}

Widget _wrap({
  required List<JournalEntryWithPostings> entries,
  required List<Account> accounts,
  GoRouter? router,
}) {
  return _wrapStream(
    stream: Stream.value(
      ActivityFeedPage(
        entries: entries,
        totalCount: entries.length,
        hasMore: false,
        isFiltered: false,
        accountsById: {for (final a in accounts) a.id: a},
      ),
    ),
    router: router,
  );
}

Widget _wrapStream({
  required Stream<ActivityFeedPage> stream,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [activityFeedPreviewProvider.overrideWith((ref) => stream)],
    child: MaterialApp.router(
      routerConfig: router ?? _router(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) =>
          FTheme(data: FTheme.neutral.light.desktop, child: child!),
    ),
  );
}

void main() {
  testWidgets('keeps a stable section while the feed is loading', (
    tester,
  ) async {
    final controller = StreamController<ActivityFeedPage>();
    addTearDown(controller.close);

    await tester.pumpWidget(_wrapStream(stream: controller.stream));

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('shows a retry affordance when the feed fails', (tester) async {
    await tester.pumpWidget(
      _wrapStream(stream: Stream.error(Exception('boom'))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't load this view. Please try again."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('renders nothing when the feed is empty', (tester) async {
    await tester.pumpWidget(_wrap(entries: const [], accounts: const []));
    await tester.pumpAndSettle();

    expect(find.text('Recent activity'), findsNothing);
  });

  testWidgets('renders header + rows for the most recent entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = [
      _account(
        id: 'assets:wallet',
        name: 'Wallet',
        category: AccountSide.asset,
      ),
      _account(
        id: 'expenses:food',
        name: 'Food',
        category: AccountSide.expense,
      ),
    ];
    final today = DateTime.now();
    final entries = [
      for (var i = 0; i < 3; i++)
        _entry(
          id: 'je-$i',
          date: DateTime(today.year, today.month, today.day, 10, i * 5),
          narration: 'Coffee $i',
          postings: [
            _posting(
              id: 'p-food-$i',
              journalEntryId: 'je-$i',
              accountId: 'expenses:food',
              units: '32',
            ),
            _posting(
              id: 'p-wallet-$i',
              journalEntryId: 'je-$i',
              accountId: 'assets:wallet',
              units: '-32',
              position: 1,
            ),
          ],
        ),
    ];

    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.text('Coffee 0'), findsOneWidget);
    expect(find.text('Coffee 1'), findsOneWidget);
    expect(find.text('Coffee 2'), findsOneWidget);
    // "View all" link routes into the full activity page.
    expect(find.textContaining('View all'), findsOneWidget);
  });

  testWidgets('tapping a preview row opens the entry detail route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = [
      _account(
        id: 'assets:wallet',
        name: 'Wallet',
        category: AccountSide.asset,
      ),
      _account(
        id: 'expenses:food',
        name: 'Food',
        category: AccountSide.expense,
      ),
    ];
    final entry = _entry(
      id: 'je-detail',
      date: DateTime.now(),
      narration: 'Lunch',
      postings: [
        _posting(
          id: 'p-food',
          journalEntryId: 'je-detail',
          accountId: 'expenses:food',
          units: '48',
        ),
        _posting(
          id: 'p-wallet',
          journalEntryId: 'je-detail',
          accountId: 'assets:wallet',
          units: '-48',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(entries: [entry], accounts: accounts));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();

    expect(find.text('entry-detail-je-detail'), findsOneWidget);
  });

  testWidgets('caps the preview at kHomeActivityPreviewCount entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = [
      _account(
        id: 'assets:wallet',
        name: 'Wallet',
        category: AccountSide.asset,
      ),
      _account(
        id: 'expenses:food',
        name: 'Food',
        category: AccountSide.expense,
      ),
    ];
    final today = DateTime.now();
    final entries = [
      for (var i = 0; i < kHomeActivityPreviewCount + 3; i++)
        _entry(
          id: 'je-$i',
          date: DateTime(today.year, today.month, today.day, 10, i),
          narration: 'Entry $i',
          postings: [
            _posting(
              id: 'p-food-$i',
              journalEntryId: 'je-$i',
              accountId: 'expenses:food',
              units: '5',
            ),
            _posting(
              id: 'p-wallet-$i',
              journalEntryId: 'je-$i',
              accountId: 'assets:wallet',
              units: '-5',
              position: 1,
            ),
          ],
        ),
    ];

    await tester.pumpWidget(_wrap(entries: entries, accounts: accounts));
    await tester.pumpAndSettle();

    for (var i = 0; i < kHomeActivityPreviewCount; i++) {
      expect(
        find.text('Entry $i'),
        findsOneWidget,
        reason: 'Entry $i should appear inside the preview cap',
      );
    }
    for (
      var i = kHomeActivityPreviewCount;
      i < kHomeActivityPreviewCount + 3;
      i++
    ) {
      expect(
        find.text('Entry $i'),
        findsNothing,
        reason: 'Entry $i is beyond the cap; preview must not render it',
      );
    }
  });
}
