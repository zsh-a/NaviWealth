import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_page.dart';
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
  testWidgets(
    'mobile shell keeps filters in the sheet and fixes the main CTA',
    (tester) async {
      // Below 1024 dp -> mobile branch without the desktop quick-filter rail.
      await tester.binding.setSurfaceSize(const Size(760, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container: container));
      await tester.pumpAndSettle();

      expect(find.text('All'), findsNothing);
      expect(find.text('Expense'), findsNothing);
      expect(find.text('Record entry'), findsOneWidget);
    },
  );

  testWidgets('desktop quick filter toggles a kind into the active query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

  testWidgets('desktop All chip clears any selected kinds', (tester) async {
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

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(container.read(activityFeedQueryProvider).kinds, isEmpty);
  });
}
