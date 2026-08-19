import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_filter_sheet.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: _hlc,
);

Account _account(String id, String name) {
  return Account(
    id: id,
    type: AccountCategory.bank,
    name: name,
    currency: 'CNY',
    category: AccountSide.asset,
    sync: _sync,
  );
}

Widget _wrap({required List<Account> accounts, Widget? home}) {
  return ProviderScope(
    overrides: [
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
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
