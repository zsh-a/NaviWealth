import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

final _meta = SyncMeta(
  ownerUserId: 'filters-owner',
  updatedAt: DateTime.utc(2026, 5, 20),
  updatedByDevice: 'filters-device',
  hlc: Hlc.zero('filters-device'),
);
final _accounts = [
  Account(
    id: 'bank',
    type: AccountCategory.bank,
    name: '日常账户',
    currency: 'CNY',
    category: AccountSide.asset,
    sync: _meta,
  ),
  Account(
    id: 'expense',
    type: AccountCategory.bank,
    name: '日常支出',
    currency: 'CNY',
    category: AccountSide.expense,
    sync: _meta,
  ),
];
final _entries = [
  for (final (id, title, amount) in [
    ('coffee', '咖啡', '28'),
    ('market', '周末采购', '186.50'),
  ])
    JournalEntryWithPostings(
      entry: JournalEntry(
        id: id,
        date: DateTime.utc(2026, 5, 20, 10),
        narration: title,
        sync: _meta,
      ),
      postings: [
        Posting(
          id: '$id-expense',
          journalEntryId: id,
          position: 0,
          accountId: 'expense',
          units: Decimal.parse(amount),
          unit: 'CNY',
          sync: _meta,
        ),
        Posting(
          id: '$id-bank',
          journalEntryId: id,
          position: 1,
          accountId: 'bank',
          units: -Decimal.parse(amount),
          unit: 'CNY',
          sync: _meta,
        ),
      ],
    ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final theme in [GoldenTheme.light, GoldenTheme.dark]) {
    testVisualGolden('records filter flow — ${theme.name}', (tester) async {
      await _capture(tester, theme);
    });
  }
  testVisualGolden('records filters — narrow, enlarged labels', (tester) async {
    await _capture(tester, GoldenTheme.light, scaled: true);
  });
}

Future<void> _capture(
  WidgetTester tester,
  GoldenTheme theme, {
  bool scaled = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final name = scaled ? 'activity_filters_scaled' : 'activity_filters';
  final accounts = {for (final account in _accounts) account.id: account};
  await pumpAndSnapshotMobile(
    tester,
    name: name,
    variant: theme,
    locale: const Locale('zh'),
    routePath: '/activity',
    logicalSize: scaled ? const Size(320, 900) : kGoldenLogicalSize,
    textScaler: TextScaler.linear(scaled ? 1.5 : 1),
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountsStreamProvider.overrideWith((_) => Stream.value(_accounts)),
      activityFeedProvider.overrideWith((ref) {
        final query = ref.watch(activityFeedQueryProvider);
        final entries = filterActivityEntries(
          entries: _entries,
          query: query,
          accountsById: accounts,
        );
        return Stream.value(
          ActivityFeedPage(
            entries: entries,
            totalCount: entries.length,
            hasMore: false,
            isFiltered: query.hasFilters,
            accountsById: accounts,
          ),
        );
      }),
    ],
    child: const ActivityPage(),
  );
  final context = tester.element(find.byType(ActivityPage));
  ProviderScope.containerOf(context)
      .read(activityFeedQueryProvider.notifier)
      .setQuery(
        const ActivityFeedQuery(
          kinds: {ActivityKind.expense},
          accountIds: {'bank'},
        ),
      );
  await tester.pumpAndSettle();
  await expectGoldenSurface(
    'goldens/${name}_applied_${theme.filenameSuffix}.png',
  );
  await tester.tap(find.byKey(const ValueKey('activity-filter-kind')));
  await tester.pumpAndSettle();
  await expectGoldenSurface(
    'goldens/${name}_picker_${theme.filenameSuffix}.png',
  );
  expect(tester.takeException(), isNull);
}
