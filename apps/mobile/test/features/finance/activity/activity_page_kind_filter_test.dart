import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/features/finance/activity/activity_page.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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

Widget _wrap({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: _router(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) =>
          FTheme(data: FThemes.slate.light.desktop, child: child!),
    ),
  );
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
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
  testWidgets('mobile shell renders inline kind chip row + empty feed', (
    tester,
  ) async {
    // Below 1024 dp -> mobile branch with inline chip row.
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    // All five kind chips render (All + four kinds).
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Trade'), findsOneWidget);
  });

  testWidgets('tapping a kind chip toggles it into the active query', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container: container));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);

    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    expect(
      container.read(activityFeedQueryProvider).kinds,
      contains(ActivityKind.expense),
    );

    // Tapping again toggles off.
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
  });

  testWidgets('All chip clears any selected kinds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
  });
}
