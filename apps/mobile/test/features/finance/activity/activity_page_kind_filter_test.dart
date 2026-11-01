import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences _preferences;

GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.activity,
    routes: [
      GoRoute(
        path: AppRoutes.activity,
        builder: (_, _) => const ActivityPage(),
      ),
      GoRoute(
        path: AppRoutes.activityIngest,
        builder: (_, _) => const Scaffold(body: Text('ingest-route')),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const Scaffold(body: Text('settings-route')),
      ),
    ],
  );
}

Widget _wrap({required ProviderContainer container, double textScale = 1}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: _router(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppMessenger.init(
          child: FTheme(data: FTheme.neutral.light.desktop, child: child!),
        ),
      ),
    ),
  );
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_preferences),
      accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
      activityFeedProvider.overrideWith(
        (_) => Stream.value(
          const ActivityFeedPage(
            entries: [],
            totalCount: 0,
            hasMore: false,
            isFiltered: false,
            accountsById: {},
          ),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('clearing a filter chip preserves search and other filters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container: container, textScale: 1.5));
    await tester.pumpAndSettle();
    container
        .read(activityFeedQueryProvider.notifier)
        .setQuery(
          const ActivityFeedQuery(
            kinds: {ActivityKind.expense, ActivityKind.transfer},
            accountIds: {'account'},
            searchText: 'coffee',
          ),
        );
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(AppFilterChip, 'Expense');
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(FLucideIcons.x)),
    );
    await tester.pumpAndSettle();
    final query = container.read(activityFeedQueryProvider);
    expect(query.kinds, {ActivityKind.transfer});
    expect(query.accountIds, {'account'});
    expect(query.searchText, 'coffee');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile search is direct and clearing it preserves filters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();
    container
        .read(activityFeedQueryProvider.notifier)
        .setQuery(const ActivityFeedQuery(kinds: {ActivityKind.expense}));
    await tester.pumpAndSettle();
    expect(find.byType(FTextField), findsOneWidget);
    await tester.enterText(find.byType(FTextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 250));
    expect(container.read(activityFeedQueryProvider).searchText, 'coffee');
    await tester.tap(
      find.descendant(
        of: find.byType(AppSearchField),
        matching: find.byIcon(FLucideIcons.x),
      ),
    );
    await tester.pumpAndSettle();
    final query = container.read(activityFeedQueryProvider);
    expect(query.searchText, isEmpty);
    expect(query.kinds, {ActivityKind.expense});
    expect(find.byType(FTextField), findsOneWidget);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
  });

  testWidgets('mobile shell shows a semantic filter summary and header add', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Kind'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Expense'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('activity-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
  });

  testWidgets('filter bar stays bounded on a narrow scaled viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container, textScale: 1.5));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsNothing);
    expect(find.byIcon(FLucideIcons.listFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter sheet applies kind changes as one draft', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);

    await tester.tap(find.byKey(const ValueKey('activity-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    // Chip edits remain local until the pinned action is submitted.
    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(
      container.read(activityFeedQueryProvider).kinds,
      contains(ActivityKind.expense),
    );
  });

  testWidgets('All in the filter sheet clears selected kinds', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    container
        .read(activityFeedQueryProvider.notifier)
        .setQuery(
          const ActivityFeedQuery(
            kinds: {ActivityKind.expense, ActivityKind.transfer},
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.listFilter));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, hasLength(2));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
  });

  testWidgets('focused kind picker clears only that facet after applying', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();
    final range = DateTimeRange(start: DateTime(2026), end: DateTime(2027));
    container
        .read(activityFeedQueryProvider.notifier)
        .setQuery(
          ActivityFeedQuery(
            dateRange: range,
            kinds: const {ActivityKind.expense},
            accountIds: const {'wallet'},
            searchText: 'coffee',
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-filter-kind')));
    await tester.pumpAndSettle();
    expect(find.text('This month'), findsNothing);
    expect(
      find.text('No accounts yet — add one from the Accounts tab.'),
      findsNothing,
    );
    await tester.tap(find.text('Clear').last);
    await tester.pumpAndSettle();
    expect(container.read(activityFeedQueryProvider).kinds, {
      ActivityKind.expense,
    });
    // A focused draft must not overwrite another dimension changed meanwhile.
    container
        .read(activityFeedQueryProvider.notifier)
        .mutateQuery(
          (query) => query.copyWith(accountIds: const {'updated-wallet'}),
        );
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    final query = container.read(activityFeedQueryProvider);
    expect(query.kinds, isEmpty);
    expect(query.dateRange, range);
    expect(query.accountIds, {'updated-wallet'});
    expect(query.searchText, 'coffee');
  });

  testWidgets('wide search debounces query updates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    expect(find.byType(FTextField), findsOneWidget);

    await tester.enterText(find.byType(FTextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(activityFeedQueryProvider).searchText, isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    expect(container.read(activityFeedQueryProvider).searchText, 'coffee');
  });

  testWidgets('wide toolbar keeps search and filters visible together', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    expect(find.byType(FTextField), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Kind'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });
}
