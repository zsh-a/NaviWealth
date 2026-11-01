import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_filter_sheet.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
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

Account _account(
  String id,
  String name, {
  AccountSide side = AccountSide.asset,
}) {
  return Account(
    id: id,
    type: AccountCategory.bank,
    name: name,
    currency: 'CNY',
    category: side,
    sync: _sync,
  );
}

Widget _wrap({
  required List<Account> accounts,
  Stream<List<Account>> Function()? accountStream,
  Widget? home,
  JournalEntryRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      accountsStreamProvider.overrideWith(
        (_) => accountStream?.call() ?? Stream.value(accounts),
      ),
      allAccountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
      if (repository != null)
        journalEntryRepositoryProvider.overrideWith((_) async => repository),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: home ?? const _OpenSheetHost(),
      ),
    ),
  );
}

class _OpenSheetHost extends StatelessWidget {
  const _OpenSheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FButton(
          onPress: () => ActivityFeedFilterSheet.show(context),
          child: const Text('open-filter'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'preview counts draft filters without changing the feed before Apply',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = JournalEntryRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );
      for (final account in ['wallet', 'bank']) {
        await repo.create(
          entry: JournalEntryDraft(
            date: DateTime.utc(2026),
            narration: account,
          ),
          postings: [
            PostingDraft(accountId: account, units: -Decimal.one, unit: 'CNY'),
            PostingDraft(accountId: 'food', units: Decimal.one, unit: 'CNY'),
          ],
        );
      }
      await tester.pumpWidget(
        _wrap(
          repository: repo,
          accounts: [
            _account('wallet', 'Wallet'),
            _account('bank', 'Bank'),
            _account('food', 'Food', side: AccountSide.expense),
          ],
        ),
      );
      await tester.tap(find.text('open-filter'));
      await tester.pumpAndSettle();
      expect(find.text('Show 2 results'), findsOneWidget);
      await tester.ensureVisible(find.text('Wallet'));
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 result'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityFeedFilterSheet)),
      );
      expect(container.read(activityFeedQueryProvider).accountIds, isEmpty);
      await tester.tap(find.text('Show 1 result'));
      await tester.pumpAndSettle();
      expect(container.read(activityFeedQueryProvider).accountIds, {'wallet'});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'account search preserves selected accounts outside the result list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft = ValueNotifier(const ActivityFeedQuery(accountIds: {'a0'}));
      await tester.pumpWidget(
        _wrap(
          accounts: [
            for (var i = 0; i < 10; i++) _account('a$i', 'Account $i'),
          ],
          home: Scaffold(
            body: ActivityFeedFilterSheet(
              draft: draft,
              section: ActivityFilterSection.account,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Account 9');
      await tester.pumpAndSettle();
      expect(find.text('Account 0'), findsNothing);
      expect(find.text('Account 9'), findsNWidgets(2));
      await tester.tap(find.text('Account 9').last);
      await tester.pumpAndSettle();
      expect(draft.value.accountIds, {'a0', 'a9'});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      draft.dispose();
    },
  );

  testWidgets('failed account load offers retry instead of an empty state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var attempts = 0;
    await tester.pumpWidget(
      _wrap(
        accounts: const [],
        accountStream: () {
          attempts++;
          return attempts == 1
              ? Stream<List<Account>>.error(StateError('unavailable'))
              : Stream.value([_account('a1', 'Wallet')]);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();
    expect(
      find.text('Accounts could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(
      find.text('No accounts yet — add one from the Accounts tab.'),
      findsNothing,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
  });

  test('custom dates include the final day and round trip across year end', () {
    final selected = DateTimeRange(
      start: DateTime(2026, 12, 31),
      end: DateTime(2026, 12, 31),
    );
    final query = activityQueryRange(selected);
    expect(query.start, DateTime(2026, 12, 31));
    expect(query.end, DateTime(2027));
    expect(DateTime(2026, 12, 31, 23, 59).isBefore(query.end), isTrue);
    expect(activityPickerRange(query), selected);
  });

  testWidgets('shows account empty state when no accounts exist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(accounts: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();

    // The Account section renders an empty-state line instead of a list.
    expect(
      find.text('No accounts yet — add one from the Accounts tab.'),
      findsOneWidget,
    );
    expect(find.text('Apply filters'), findsOneWidget);

    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filter'), findsNothing);
  });

  testWidgets('renders one row per account inside the sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = [
      _account('a1', 'Wallet'),
      _account('a2', 'Bank'),
      _account('a3', 'Brokerage'),
    ];

    await tester.pumpWidget(_wrap(accounts: accounts));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();

    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Brokerage'), findsOneWidget);
  });

  testWidgets('date preset stays in the draft until applied', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const _OpenSheetHost(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();

    final initialQuery = container.read(activityFeedQueryProvider);
    expect(initialQuery.dateRange, isNull);

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).dateRange, isNull);

    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(container.read(activityFeedQueryProvider).dateRange, isNotNull);
  });

  testWidgets('Clear resets the draft and Apply commits every dimension', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(activityFeedQueryProvider.notifier)
        .setQuery(
          ActivityFeedQuery(
            dateRange: DateTimeRange(
              start: DateTime(2026, 5, 1),
              end: DateTime(2026, 6, 1),
            ),
            accountIds: const {'a1'},
            kinds: const {ActivityKind.expense},
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const _OpenSheetHost(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-filter'));
    await tester.pumpAndSettle();

    // The sheet's Clear action lives in the header alongside the title.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    final beforeApply = container.read(activityFeedQueryProvider);
    expect(beforeApply.dateRange, isNotNull);
    expect(beforeApply.accountIds, isNotEmpty);
    expect(beforeApply.kinds, isNotEmpty);

    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    final cleared = container.read(activityFeedQueryProvider);
    expect(cleared.dateRange, isNull);
    expect(cleared.accountIds, isEmpty);
    expect(cleared.kinds, isEmpty);
  });
}
