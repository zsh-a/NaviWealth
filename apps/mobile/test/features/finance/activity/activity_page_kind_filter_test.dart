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
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: FTheme(data: FThemes.slate.light.desktop, child: child!),
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

    expect(find.text('All dates · All kinds'), findsOneWidget);
    expect(find.text('Expense'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsWidgets);

    await tester.tap(find.text('All dates · All kinds'));
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

    await tester.tap(find.text('All dates · All kinds'));
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

    await tester.tap(find.text('All dates · 2 kinds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, hasLength(2));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
  });

  testWidgets('search debounces updates and closing clears the query', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    final searchButton = find.widgetWithIcon(
      AppIconButton,
      FLucideIcons.search,
    );
    await tester.tap(searchButton);
    await tester.pump();
    expect(find.byType(FTextField), findsOneWidget);

    await tester.enterText(find.byType(FTextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(activityFeedQueryProvider).searchText, isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    expect(container.read(activityFeedQueryProvider).searchText, 'coffee');

    await tester.tap(find.widgetWithIcon(AppIconButton, FLucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.byType(FTextField), findsNothing);
    expect(container.read(activityFeedQueryProvider).searchText, isEmpty);
  });
}
